import Foundation

/// One Vision text observation, kept with the geometry Vision reported for it.
/// Bounds are normalized to the active request ROI. String-only parser callers
/// intentionally use `nil`, preserving their established text-only behavior.
struct RecognizedLine: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect?
    /// Vision's normalized confidence for the selected candidate. Parser rules
    /// deliberately do not use this as identity evidence.
    let confidence: Float?
    /// Lower-ranked readings retained for diagnostics and future conservative
    /// character-confusion handling.
    let alternatives: [String]
    /// The observation bounds mapped into the oriented source image in pixels.
    let sourcePixelRect: CGRect?

    init(
        text: String,
        boundingBox: CGRect? = nil,
        confidence: Float? = nil,
        alternatives: [String] = [],
        sourcePixelRect: CGRect? = nil
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.alternatives = alternatives
        self.sourcePixelRect = sourcePixelRect
    }
}

/// The sole output of game-specific parsing. Modern cards carry a printed
/// identifier; historical Pokémon cards carry a stable, conservative evidence
/// key that must still earn a unique catalog identity (or ask the user).
///
/// `Hashable` because the session catalog caches resolved cards by identifier,
/// which is what lets a second copy of an already-scanned printing skip the
/// network entirely.
enum ScanIdentifier: Equatable, Hashable, Sendable {
    case pokemon(setCode: String, cardNumber: String, printedTotal: Int, setDefinition: PokemonSetDefinition)
    /// A Black Star Promo whose printed prefix is the set identity. It is kept
    /// separate from modern expansions because promo cards have no `/total`.
    case pokemonPromo(prefix: String, localID: String, setDefinition: PokemonPromoSetDefinition)
    /// A pre-Scarlet & Violet Pokémon card whose printed number is useful
    /// evidence but does not carry a textual expansion code. The evidence stays
    /// separate from catalog identity: it may resolve to exactly one provider
    /// card, several candidates, or none, and only the first case may auto-add.
    case pokemonHistorical(PokemonHistoricalScanEvidence)
    /// - Parameter contentKind: what the printed marker says this is. Part of
    ///   identity, not decoration: `MSH 17` and `T 0017 MSH` are different cards
    ///   — Invisible Woman and a Clue token — and they must never confirm each
    ///   other across frames or share a cache entry.
    case magic(
        setCode: String,
        collectorNumber: String,
        language: String,
        contentKind: MagicContentKind = .regular
    )

    var game: CardGame {
        switch self {
        case .pokemon, .pokemonPromo, .pokemonHistorical: return .pokemon
        case .magic: return .magic
        }
    }

    var magicContentKind: MagicContentKind {
        switch self {
        case .pokemon, .pokemonPromo, .pokemonHistorical: return .regular
        case let .magic(_, _, _, contentKind): return contentKind
        }
    }

    /// What the app read off the card, in the card's own terms.
    ///
    /// Shown beside the resolved name so a wrong resolution is visible: seeing
    /// `Token · T 0017 MSH EN` above "Clue" is how the user knows the scanner
    /// understood the marker rather than silently ignoring it.
    var displayIdentifier: String {
        switch self {
        case let .pokemon(setCode, cardNumber, printedTotal, _):
            let unpadded = ScanText.unpaddedPokemonLocalID(cardNumber)
            return "\(setCode) \(unpadded)/\(printedTotal)"
        case let .pokemonPromo(prefix, localID, _):
            let visibleNumber = localID.uppercased().hasPrefix(prefix)
                ? String(localID.dropFirst(prefix.count))
                : localID
            return "\(prefix) \(visibleNumber)"
        case let .pokemonHistorical(evidence):
            return evidence.number.displayIdentifier
        case let .magic(setCode, collectorNumber, _, contentKind):
            switch contentKind {
            case .regular:
                return "\(setCode) \(collectorNumber) EN"
            case .token:
                return "T \(collectorNumber) \(setCode) EN"
            case .artCard:
                return "A \(collectorNumber) \(setCode) EN"
            }
        }
    }
}

/// Keeps confirmation tolerant of an occasional missed OCR frame without allowing
/// an old one-off reading to remain valid indefinitely.
/// What the duplicate latch treats as "the same piece of cardboard".
///
/// Deliberately coarser than `ScanIdentifier` for historical Pokémon, whose
/// identity carries every title observation: one card produces a new identifier
/// the moment OCR picks up one more line of its name, and suppression keyed on
/// that would stop suppressing exactly when the reading gets noisy — which is
/// when duplicates happen. The printed number is the part that does not drift.
///
/// Two different historical cards printed with the same number therefore share a
/// key, and the second has to wait for the first to leave the band. That is the
/// same trade the latch already makes for two identical copies back to back, and
/// it errs the same way: a missed card costs one more pass, a phantom duplicate
/// quietly corrupts a collection.
enum ScanSuppressionKey: Hashable, Sendable {
    case identifier(ScanIdentifier)
    case pokemonPrintedNumber(PokemonPrintedNumberEvidence)
}

extension ScanIdentifier {
    var suppressionKey: ScanSuppressionKey {
        switch self {
        case let .pokemonHistorical(evidence):
            return .pokemonPrintedNumber(evidence.number)
        case .pokemon, .pokemonPromo, .magic:
            return .identifier(self)
        }
    }
}

struct CandidateConfirmationWindow {
    let matchesRequired: Int
    let windowSize: Int

    private var observations: [ScanIdentifier?] = []

    init(matchesRequired: Int = 2, windowSize: Int = 4) {
        self.matchesRequired = matchesRequired
        self.windowSize = max(windowSize, matchesRequired)
    }

    mutating func observe(_ candidate: ScanIdentifier?) -> ScanIdentifier? {
        observations.append(candidate)
        if observations.count > windowSize {
            observations.removeFirst(observations.count - windowSize)
        }

        guard let candidate else { return nil }

        let matchingCount = observations.compactMap { $0 }.filter { $0 == candidate }.count
        guard matchingCount >= matchesRequired else { return nil }

        reset()
        return candidate
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }
}

/// Historical footer evidence is confirmed before the scanner asks the user to
/// reposition the card. It intentionally cannot produce a `ScanIdentifier`:
/// collector number alone is never identity.
struct HistoricalNumberConfirmationWindow {
    let matchesRequired: Int
    let windowSize: Int

    private var observations: [PokemonPrintedNumberEvidence?] = []

    init(matchesRequired: Int = 2, windowSize: Int = 4) {
        self.matchesRequired = matchesRequired
        self.windowSize = max(windowSize, matchesRequired)
    }

    mutating func observe(
        _ candidate: PokemonPrintedNumberEvidence?
    ) -> PokemonPrintedNumberEvidence? {
        observations.append(candidate)
        if observations.count > windowSize {
            observations.removeFirst(observations.count - windowSize)
        }
        guard let candidate else { return nil }
        guard observations.compactMap({ $0 }).filter({ $0 == candidate }).count >= matchesRequired else {
            return nil
        }
        reset()
        return candidate
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }
}

/// Small pieces both game parsers need. Every one of these runs inside the OCR
/// loop, so nothing here may compile a regular expression per call.
enum ScanText {
    /// Vision confuses O/0 and I/L/1 in the tiny numeric strip. Nothing else.
    static func normalizedInteger(_ text: String) -> Int? {
        Int(text
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1"))
    }

    static func pokemonLocalID(digits: String, suffix: String, minimumDigits: Int = 0) -> String? {
        guard let number = normalizedInteger(digits), number > 0 else { return nil }
        let numeric = minimumDigits > 0
            ? String(format: "%0*d", minimumDigits, number)
            : String(number)
        return numeric + suffix.lowercased()
    }

    static func unpaddedPokemonLocalID(_ localID: String) -> String {
        let digits = localID.prefix { $0.isNumber }
        let suffix = localID.dropFirst(digits.count)
        guard let number = Int(digits) else { return localID }
        return String(number) + suffix
    }

    /// Builds one alternation over a set-code vocabulary instead of running a
    /// separate regular expression per known code. Magic's vocabulary is the
    /// whole modern Scryfall directory, so per-code matching would mean hundreds
    /// of regex passes per OCR line, four times a second.
    static func setCodeRegex(codes: some Collection<String>, boundary: String) -> NSRegularExpression {
        let alternatives = codes
            .sorted()
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return try! NSRegularExpression(
            pattern: "(?<![\(boundary)])(?:\(alternatives))(?![\(boundary)])",
            options: []
        )
    }

    static func matchedSubstrings(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    /// Order-preserving de-duplication. The collections here hold two or three
    /// items, so a linear scan beats building a `Set`.
    static func unique<Element: Equatable>(_ values: [Element]) -> [Element] {
        var result: [Element] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }
}

/// The numbering rule printed on a Pokémon card.
///
/// Ordinary cards use the set's official denominator. Named subsets instead
/// print their own prefix and size (`H11/H32`, `TG01/TG30`, `GG01/GG70`,
/// `RC01/RC25`), so their denominator must never be compared with a set count.
enum PokemonPrintedNumberScheme: Equatable, Hashable, Sendable {
    case officialSet
    case subset(prefix: String)
}

struct PokemonPrintedNumberEvidence: Equatable, Hashable, Sendable {
    let localID: String
    let denominator: Int
    let scheme: PokemonPrintedNumberScheme

    var displayIdentifier: String {
        switch scheme {
        case .officialSet:
            return "\(localID)/\(denominator)"
        case let .subset(prefix):
            return "\(localID)/\(prefix)\(denominator)"
        }
    }
}

/// OCR evidence only. It is deliberately not a catalog identity.
struct PokemonHistoricalScanEvidence: Equatable, Hashable, Sendable {
    let number: PokemonPrintedNumberEvidence
    /// Canonicalized, sorted observations from the title region. Keeping every
    /// observation makes equality conservative across frames: unstable OCR does
    /// not confirm and therefore cannot mutate the collection.
    let titleCandidates: [String]
}

/// Parses the two deliberately separate historical OCR regions: the existing
/// collector-number band and a title-only band above it. No set is selected
/// here; this layer only describes what was printed.
enum PokemonHistoricalScanParser {
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Z0-9])((?:TG|GG|RC|H)?)\s*([0-9OIL]{1,3})([AB]?)\s*/\s*((?:TG|GG|RC|H)?)\s*([0-9OIL]{1,3})(?![A-Z0-9])"#,
        options: []
    )

    static func parse(numberLines: [String], titleLines: [String]) -> ScanIdentifier? {
        guard let number = numberEvidence(in: numberLines) else { return nil }

        return parse(number: number, titleLines: titleLines)
    }

    /// Builds historical evidence after the footer and title have been captured
    /// in two deliberate presentations of the same scan band.
    static func parse(
        number: PokemonPrintedNumberEvidence,
        titleLines: [String],
        excludingFooter footerSignature: Set<String> = []
    ) -> ScanIdentifier? {

        let titles = Array(
            Set(
                titleLines
                    .compactMap(canonicalTitle)
                    .filter { !footerSignature.contains(confusionFold($0)) }
            )
        ).sorted()
        guard !titles.isEmpty else { return nil }
        return .pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: titles)
        )
    }

    static func numberEvidence(in lines: [String]) -> PokemonPrintedNumberEvidence? {
        let readings = ScanText.unique(lines.flatMap(numberReadings))
        return readings.count == 1 ? readings[0] : nil
    }

    private static func numberReadings(in raw: String) -> [PokemonPrintedNumberEvidence] {
        let text = raw.uppercased().replacingOccurrences(of: "\n", with: " ")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return numberRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let cardPrefixRange = Range(match.range(at: 1), in: text),
                  let cardRange = Range(match.range(at: 2), in: text),
                  let suffixRange = Range(match.range(at: 3), in: text),
                  let totalPrefixRange = Range(match.range(at: 4), in: text),
                  let totalRange = Range(match.range(at: 5), in: text),
                  let card = ScanText.normalizedInteger(String(text[cardRange])),
                  let total = ScanText.normalizedInteger(String(text[totalRange])),
                  card > 0, total > 0 else { return nil }

            let cardPrefix = String(text[cardPrefixRange])
            let suffix = String(text[suffixRange])
            let totalPrefix = String(text[totalPrefixRange])
            guard totalPrefix.isEmpty || totalPrefix == cardPrefix else { return nil }

            if cardPrefix.isEmpty {
                return PokemonPrintedNumberEvidence(
                    localID: String(card) + suffix.lowercased(),
                    denominator: total,
                    scheme: .officialSet
                )
            }
            guard suffix.isEmpty else { return nil }
            return PokemonPrintedNumberEvidence(
                localID: "\(cardPrefix)\(card)",
                denominator: total,
                scheme: .subset(prefix: cardPrefix)
            )
        }
    }

    /// Text that is printed on every card and is therefore never its name.
    ///
    /// The prompt for a card name appears while the camera is still on the
    /// number band, so the first frames of title capture read the furniture
    /// around it: the copyright line, the illustrator credit, the
    /// resistance/weakness row. Accepting those as a name spent the prompt
    /// before the user could move the camera, and filed an unresolved scan for a
    /// card that was never actually presented.
    ///
    /// Matched exactly rather than by containment, because real card names use
    /// these words too — `Basic Lightning Energy` begins with "basic", and
    /// `Pokémon Catcher` contains "pokemon".
    private static let furniture: Set<String> = [
        "resistance", "weakness", "retreat", "retreat cost", "hp", "basic",
        "stage 1", "stage 2", "ability", "pokemon power", "poke power",
        "poke body", "trainer", "supporter", "stadium", "item", "energy"
    ]

    /// Rights holders, which appear only on the copyright line.
    /// `pokemon` is included: the rule needs a year *and* a rights holder, and a
    /// Trainer card named `Pokémon Catcher` carries no year.
    private static let rightsHolders = [
        "nintendo", "creatures", "game freak", "wizards", "pokemon"
    ]

    /// What was already read from the number band, so title capture can tell
    /// that it is still looking at it.
    ///
    /// The prompt for a card name appears while the camera is on the footer, and
    /// EX-era cards print a code there — `GKD-3F0-0SG` sits directly beside
    /// `78/109` on Spinarak. Read as a name it produced three unresolved scans
    /// for a card the user never got to present. Nothing that was just read off
    /// the footer can be the card's name.
    static func footerSignature(from lines: [String]) -> Set<String> {
        Set(lines.compactMap(canonicalTitle).map(confusionFold))
    }

    /// Folds the character pairs Vision confuses in small print, so one reading
    /// of the footer recognises another. The three device readings of that print
    /// code — `gkd 3fo 0sg`, `gkd 3fo osg`, `GKD 3F0 OSG` — differ only here, so
    /// matching the exact string would have rejected one and let two through.
    private static func confusionFold(_ value: String) -> String {
        String(value.lowercased().map { character in
            switch character {
            case "o": return "0"
            case "i", "l": return "1"
            case "s": return "5"
            case "b": return "8"
            default: return character
            }
        })
    }

    private static func canonicalTitle(_ raw: String) -> String? {
        let title = CatalogIdentityNormalization.canonicalText(raw)
        guard !title.isEmpty,
              title.count <= 60,
              title.rangeOfCharacter(from: .letters) != nil else { return nil }
        // Two letters is not a name; it is a fragment of one.
        guard title.count >= 3 else { return nil }
        guard !furniture.contains(title) else { return nil }
        guard !title.hasPrefix("illus") else { return nil }
        guard !title.hasPrefix("evolves from") else { return nil }
        // The copyright line: a year beside a rights holder. Either alone is not
        // enough — a card may legitimately be named after one.
        let hasYear = title.range(
            of: #"(19|20)\d{2}"#,
            options: .regularExpression
        ) != nil
        if hasYear, rightsHolders.contains(where: title.contains) { return nil }
        return title
    }
}

enum ScanParser {
    // OCR commonly merges neighboring tokens (OBF223/197, G223/197) and confuses
    // O/0 or I/L/1 in tiny numeric text. Accept those narrow cases, then validate
    // the denominator against a known set before returning a candidate.
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-9OIL]{1,3})([AB]?)\s*/\s*([0-9OIL]{1,3})(?![A-Z0-9])"#,
        options: []
    )

    // A code may touch digits ("OBF223/197"), but must not be embedded inside an
    // alphabetic word such as "MASCAGNI" -> "ASC".
    private static let setCodeRegex = ScanText.setCodeRegex(codes: SetCodeMap.codes, boundary: "A-Z")
    private static let promoRegex: NSRegularExpression = {
        let prefixes = PokemonPromoCodeMap.codes
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return try! NSRegularExpression(
            pattern: #"(?<![A-Z0-9])("# + prefixes + #")\s*(?:EN\s*)?([0-9OIL]{2,3})(?![A-Z0-9/])"#,
            options: []
        )
    }()

    /// Prefer Vision's individual observations so a code stays paired with the
    /// collector number on the same line. Only fall back to joined text when no
    /// individual line resolves, which handles split observations like "OBF" +
    /// "223/197" without making two visible card identifiers ambiguous.
    static func parsePokemon(_ recognizedLines: [String]) -> ScanIdentifier? {
        let lineCandidates = ScanText.unique(
            recognizedLines.compactMap { uniqueCandidate(in: $0) }
        )

        if lineCandidates.count == 1 {
            return lineCandidates[0]
        }
        if lineCandidates.count > 1 {
            return nil
        }

        return uniqueCandidate(in: recognizedLines.joined(separator: " "))
    }

    static func parsePokemon(_ recognizedText: String) -> ScanIdentifier? {
        uniqueCandidate(in: recognizedText)
    }

    private static func uniqueCandidate(in recognizedText: String) -> ScanIdentifier? {
        let normalized = recognizedText
            .uppercased()
            .replacingOccurrences(of: "\n", with: " ")

        let promoCandidates = promoMatches(in: normalized)
        let codes = ScanText.matchedSubstrings(setCodeRegex, in: normalized)
        let numbers = numberMatches(in: normalized)

        var candidates: [ScanIdentifier] = promoCandidates

        for code in codes {
            guard let definition = SetCodeMap.definitions[code] else { continue }

            for number in numbers where number.total == definition.officialCount {
                // Collector number zero is never valid. Avoid an unnecessary /000
                // network lookup, but do not impose an arbitrary upper multiplier:
                // some legitimate Pokémon sets have unusually large secret ranges.
                candidates.append(
                    .pokemon(
                        setCode: code,
                        cardNumber: number.localID,
                        printedTotal: number.total,
                        setDefinition: definition
                    )
                )
            }
        }

        let unique = ScanText.unique(candidates)
        return unique.count == 1 ? unique[0] : nil
    }

    private static func numberMatches(in text: String) -> [(localID: String, total: Int)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return numberRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let cardRange = Range(match.range(at: 1), in: text),
                  let suffixRange = Range(match.range(at: 2), in: text),
                  let totalRange = Range(match.range(at: 3), in: text),
                  let localID = ScanText.pokemonLocalID(
                    digits: String(text[cardRange]),
                    suffix: String(text[suffixRange]),
                    minimumDigits: 3
                  ),
                  let total = ScanText.normalizedInteger(String(text[totalRange])) else {
                return nil
            }
            return (localID, total)
        }
    }

    private static func promoMatches(in text: String) -> [ScanIdentifier] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return promoRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let prefixRange = Range(match.range(at: 1), in: text),
                  let numberRange = Range(match.range(at: 2), in: text) else { return nil }
            let prefix = String(text[prefixRange])
            guard let definition = PokemonPromoCodeMap.definitions[prefix],
                  let number = ScanText.normalizedInteger(String(text[numberRange])),
                  number > 0 else { return nil }
            return .pokemonPromo(
                prefix: prefix,
                localID: definition.catalogLocalID(number: number),
                setDefinition: definition
            )
        }
    }
}

/// Magic footer parsing.
///
/// The printed footer is one logical thing — collector number, rarity, set code,
/// language — but Vision routinely returns it as two or three separate
/// observations, and which pieces land together varies frame to frame:
///
///     "0218/0269 U"  +  "ECL • EN"
///     "0218"  +  "ECL"  +  "EN"
///     "ECL • 0218 • EN"
///
/// So a footer is read as a *bounded group* of adjacent observations rather than
/// a single line. The group still has to earn the identification: exactly one
/// known set code, an English marker, and a collector number that either sits on
/// a line already carrying the code or the marker, or occupies a line entirely by
/// itself. That last rule is what keeps a copyright year from becoming a card
/// number.
struct MagicScanProfile: Sendable {
    let definitions: [String: MagicSetDefinition]

    /// How many consecutive observations may be treated as one footer. Three
    /// covers every split seen in practice; more would start pulling in unrelated
    /// text from the card body.
    private static let footerWindow = 3

    /// A standalone number in this range is much more likely to be the copyright
    /// year than the collector number. Do not reject every four-digit value:
    /// products such as Secret Lair legitimately use collector numbers above 999.
    /// A number printed with a denominator is exempt because that shape is already
    /// unambiguous.
    private static let plausibleCopyrightYears = 1993...2100

    /// Built once per profile. These used to be compiled inside the per-line
    /// loop, which put two `NSRegularExpression` compiles on every OCR line of
    /// every frame.
    private let setCodeRegex: NSRegularExpression
    private static let collectorNumberRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Z0-9])([0-9OIL]{1,4})(?:\s*/\s*([0-9OIL]{1,4}))?(?![A-Z0-9])"#,
        options: []
    )
    /// A collector-number line, allowing the rarity letter Magic prints on
    /// either side and an unrelated short print annotation after the number.
    /// Final Fantasy cards, for example, can print `0036 FFVII` above `FIN • EN`.
    /// The parser deliberately discards `FFVII`; only the known set-code match
    /// (`FIN`) participates in identity.
    /// Group 1 is the leading letter, now **captured** rather than skipped.
    ///
    /// It used to be `(?:[A-Z]\s+)?` — matched and thrown away — which is what
    /// made `T 0017` and `0017` indistinguishable, and why scanning a Clue token
    /// silently added Invisible Woman instead. The letter is either a content
    /// marker (`T`) or a rarity letter, and only the parser can tell which.
    private static let strictCollectorNumberRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:([A-Z])\s+)?([0-9OIL]{1,4})(?:\s*/\s*([0-9OIL]{1,4}))?(?:\s+[A-Z0-9]{2,6})?(?:\s+[A-Z])?\s*$"#,
        options: []
    )
    /// The same marker when it leads a full footer line, e.g. `T 0017 MSH EN`.
    private static let markerPrefixRegex = try! NSRegularExpression(
        pattern: #"^\s*([A-Z])\s+(?=[0-9OIL])"#,
        options: []
    )
    private static let englishMarkerRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Z])EN(?![A-Z])"#,
        options: []
    )

    init(definitions: [MagicSetDefinition]) {
        let keyed = Dictionary(
            definitions.map { ($0.code.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.definitions = keyed
        // Magic codes are alphanumeric (MH3, 40K), so digits are a word boundary
        // here in a way they are not for Pokémon's always-alphabetic codes.
        self.setCodeRegex = ScanText.setCodeRegex(codes: keyed.keys, boundary: "A-Z0-9")
    }

    var customWords: [String] {
        definitions.keys.sorted() + ["EN"]
    }

    func parse(_ recognizedLines: [String]) -> ScanIdentifier? {
        parseOutcome(recognizedLines.map { RecognizedLine(text: $0) }).identifier
    }

    /// Geometry-aware production result. A spatial rejection is kept distinct
    /// from `nothing` so a Magic P/T fraction cannot immediately become a
    /// historical-Pokemon trigger in the same frame.
    func parseOutcome(_ recognizedLines: [RecognizedLine]) -> MagicParseOutcome {
        let lines = recognizedLines
            .map {
                RecognizedLine(
                    text: $0.text
                        .uppercased()
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: $0.boundingBox
                )
            }
            .filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return .nothing }

        // Every line is examined once, then windows just combine the results.
        // Re-running the regexes per window would multiply the per-frame cost by
        // the window size for no new information.
        let examined = lines.map(examine)

        var candidates: [ScanIdentifier] = []
        var rejectedCollectorInMagicFooter = false
        for start in examined.indices {
            let limit = min(start + Self.footerWindow, examined.count)
            for stop in (start + 1)...limit {
                let result = identities(in: examined[start..<stop])
                candidates.append(contentsOf: result.identifiers)
                rejectedCollectorInMagicFooter = rejectedCollectorInMagicFooter
                    || result.rejectedCollectorSpatially
            }
        }

        let unique = ScanText.unique(candidates)
        if unique.count == 1 {
            return .identified(unique[0])
        }
        return rejectedCollectorInMagicFooter ? .spatiallyRejectedCollector : .nothing
    }

    /// What one observation contributes to a footer, worked out once.
    private struct ExaminedLine {
        let boundingBox: CGRect?
        let hasEnglishMarker: Bool
        let codes: [String]
        /// Numbers embedded anywhere in the line. Only trusted when the line is
        /// part of the footer proper.
        let inlineNumbers: [CollectorNumberReading]
        /// Set when the whole line is a collector number and nothing else.
        let standaloneNumber: CollectorNumberReading?

        /// A line carrying the set code or the language marker is footer text, so
        /// numbers inside it belong to the footer.
        var isFooterText: Bool { hasEnglishMarker || !codes.isEmpty }
    }

    private struct CollectorNumberReading: Equatable {
        let card: Int
        let denominator: Int?
        /// The printed content marker, when one led the number.
        var marker: MagicPrintedMarker?
        /// Observation-level geometry. If Vision merges several textual pieces,
        /// this is deliberately conservative rather than pretending to be the
        /// exact substring bounds.
        let sourceBounds: CGRect?

        /// Marker included: a token and an ordinary card that happen to share a
        /// number are different readings, and deduplication must not merge them.
        var contentKind: MagicContentKind { marker?.contentKind ?? .regular }
    }

    private func examine(_ line: RecognizedLine) -> ExaminedLine {
        ExaminedLine(
            boundingBox: line.boundingBox,
            hasEnglishMarker: containsEnglishMarker(in: line.text),
            codes: ScanText.matchedSubstrings(setCodeRegex, in: line.text),
            inlineNumbers: collectorNumbers(in: line.text, sourceBounds: line.boundingBox),
            standaloneNumber: strictCollectorNumber(in: line.text, sourceBounds: line.boundingBox)
        )
    }

    private struct WindowResult {
        let identifiers: [ScanIdentifier]
        let rejectedCollectorSpatially: Bool
    }

    private func identities(in window: ArraySlice<ExaminedLine>) -> WindowResult {
        guard window.contains(where: \.hasEnglishMarker) else {
            return WindowResult(identifiers: [], rejectedCollectorSpatially: false)
        }

        // More than one known code in view is two cards, or a coincidence. Either
        // way it is not an identification.
        let codes = ScanText.unique(window.flatMap(\.codes))
        guard codes.count == 1, let definition = definitions[codes[0]] else {
            return WindowResult(identifiers: [], rejectedCollectorSpatially: false)
        }

        // Anchor geometry is deliberately window-local. Frame-wide anchors could
        // associate a number from one visible card with the footer of another.
        let anchors = window.compactMap { line in
            line.isFooterText ? line.boundingBox : nil
        }

        var numbers: [CollectorNumberReading] = []
        for line in window {
            if line.isFooterText {
                numbers.append(contentsOf: line.inlineNumbers)
            } else if let standalone = line.standaloneNumber {
                numbers.append(standalone)
            }
        }

        var rejectedCollectorSpatially = false
        let identifiers: [ScanIdentifier] = ScanText.unique(numbers)
            .filter { number in
                guard isValid(number, for: definition) else { return false }
                guard isSpatiallyAssociated(number, with: anchors) else {
                    rejectedCollectorSpatially = true
                    return false
                }
                return true
            }
            .map {
                ScanIdentifier.magic(
                    setCode: codes[0],
                    collectorNumber: String($0.card),
                    language: "en",
                    contentKind: $0.contentKind
                )
            }
        return WindowResult(
            identifiers: identifiers,
            rejectedCollectorSpatially: rejectedCollectorSpatially
        )
    }

    /// Reject only substantial rightward detachment. Collector numbers to the
    /// left of, above, or overlapping the footer cluster retain existing behavior.
    /// The allowance scales with the number glyphs rather than a potentially
    /// merged footer/artist observation or the camera ROI.
    private func isSpatiallyAssociated(
        _ number: CollectorNumberReading,
        with anchors: [CGRect]
    ) -> Bool {
        guard let numberBounds = number.sourceBounds, !anchors.isEmpty else {
            return true
        }
        let anchorUnion = anchors.dropFirst().reduce(anchors[0]) { $0.union($1) }
        // Do not scale this allowance with the anchor width. Vision often merges
        // `FIN • EN` with the entire artist credit, producing a very wide anchor
        // box that reaches toward P/T and defeats the separation check.
        let allowedRightwardGap = numberBounds.width * 1.5
        return numberBounds.minX <= anchorUnion.maxX + allowedRightwardGap
    }

    private func containsEnglishMarker(in text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.englishMarkerRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func collectorNumbers(in text: String, sourceBounds: CGRect?) -> [CollectorNumberReading] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        // A marker leads the whole line — `T 0017 MSH EN` — so it is read once
        // and applied to the first number found. Later numbers on the same line
        // are not covered by it.
        let lineMarker = Self.markerPrefixRegex
            .firstMatch(in: text, options: [], range: range)
            .flatMap { Range($0.range(at: 1), in: text) }
            .flatMap { MagicPrintedMarker.marker(for: String(text[$0])) }

        return Self.collectorNumberRegex.matches(in: text, options: [], range: range)
            .enumerated()
            .compactMap { index, match in
                reading(
                    from: match,
                    in: text,
                    sourceBounds: sourceBounds,
                    fallbackMarker: index == 0 ? lineMarker : nil
                )
            }
    }

    private func strictCollectorNumber(in text: String, sourceBounds: CGRect?) -> CollectorNumberReading? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.strictCollectorNumberRegex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return reading(
            from: match,
            in: text,
            sourceBounds: sourceBounds,
            numberGroup: 2,
            markerGroup: 1
        )
    }

    /// - Parameter numberGroup: which capture group holds the collector number.
    ///   The strict pattern captures the marker first, so its number is group 2;
    ///   the inline pattern has no marker group and keeps the number at 1.
    private func reading(
        from match: NSTextCheckingResult,
        in text: String,
        sourceBounds: CGRect?,
        numberGroup: Int = 1,
        markerGroup: Int? = nil,
        fallbackMarker: MagicPrintedMarker? = nil
    ) -> CollectorNumberReading? {
        guard let cardRange = Range(match.range(at: numberGroup), in: text),
              let card = ScanText.normalizedInteger(String(text[cardRange])) else { return nil }
        var marker = fallbackMarker
        if let markerGroup,
           let range = Range(match.range(at: markerGroup), in: text) {
            // A leading letter that is not a known marker is a rarity letter and
            // is ignored, exactly as before.
            marker = MagicPrintedMarker.marker(for: String(text[range])) ?? marker
        }
        let denominator = Range(match.range(at: numberGroup + 1), in: text)
            .flatMap { ScanText.normalizedInteger(String(text[$0])) }
        return CollectorNumberReading(
            card: card,
            denominator: denominator,
            marker: marker,
            sourceBounds: sourceBounds
        )
    }

    private func isValid(_ number: CollectorNumberReading, for definition: MagicSetDefinition) -> Bool {
        guard number.card > 0 else { return false }

        if let denominator = number.denominator {
            // A denominator is useful independent evidence, but only where
            // Scryfall explicitly supplies a printed size. Do not invent a set
            // size for cards whose physical print run does not expose one.
            if let printedSize = definition.printedSize {
                return denominator == printedSize
            }
            return true
        }

        return !Self.plausibleCopyrightYears.contains(number.card)
    }
}

enum MagicParseOutcome: Equatable {
    case identified(ScanIdentifier)
    /// A known-code + EN footer window contained a textually valid collector
    /// reading that was rejected only because it was substantially to the right.
    case spatiallyRejectedCollector
    case nothing

    var identifier: ScanIdentifier? {
        guard case let .identified(identifier) = self else { return nil }
        return identifier
    }
}
