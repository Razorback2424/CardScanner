import Foundation

/// The sole output of game-specific parsing. Camera capture, rolling
/// confirmation, and lookup orchestration intentionally know no OCR details
/// beyond this stable identifier.
///
/// `Hashable` because the session catalog caches resolved cards by identifier,
/// which is what lets a second copy of an already-scanned printing skip the
/// network entirely.
enum ScanIdentifier: Equatable, Hashable, Sendable {
    case pokemon(setCode: String, cardNumber: String, printedTotal: Int, setDefinition: PokemonSetDefinition)
    case magic(setCode: String, collectorNumber: String, language: String)

    var game: CardGame {
        switch self {
        case .pokemon: return .pokemon
        case .magic: return .magic
        }
    }

    var displayIdentifier: String {
        switch self {
        case let .pokemon(setCode, cardNumber, printedTotal, _):
            let unpadded = Int(cardNumber).map(String.init) ?? cardNumber
            return "\(setCode) \(unpadded)/\(printedTotal)"
        case let .magic(setCode, collectorNumber, _):
            return "\(setCode) \(collectorNumber) EN"
        }
    }
}

/// Keeps confirmation tolerant of an occasional missed OCR frame without allowing
/// an old one-off reading to remain valid indefinitely.
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

enum ScanParser {
    // OCR commonly merges neighboring tokens (OBF223/197, G223/197) and confuses
    // O/0 or I/L/1 in tiny numeric text. Accept those narrow cases, then validate
    // the denominator against a known set before returning a candidate.
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-9OIL]{1,3})\s*/\s*([0-9OIL]{1,3})(?![0-9])"#,
        options: []
    )

    // A code may touch digits ("OBF223/197"), but must not be embedded inside an
    // alphabetic word such as "MASCAGNI" -> "ASC".
    private static let setCodeRegex = ScanText.setCodeRegex(codes: SetCodeMap.codes, boundary: "A-Z")

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

        let codes = ScanText.matchedSubstrings(setCodeRegex, in: normalized)
        let numbers = numberMatches(in: normalized)
        guard !codes.isEmpty, !numbers.isEmpty else { return nil }

        var candidates: [ScanIdentifier] = []

        for code in codes {
            guard let definition = SetCodeMap.definitions[code] else { continue }

            for number in numbers where number.total == definition.officialCount {
                // Collector number zero is never valid. Avoid an unnecessary /000
                // network lookup, but do not impose an arbitrary upper multiplier:
                // some legitimate Pokémon sets have unusually large secret ranges.
                guard number.card >= 1 else { continue }

                candidates.append(
                    .pokemon(
                        setCode: code,
                        cardNumber: String(format: "%03d", number.card),
                        printedTotal: number.total,
                        setDefinition: definition
                    )
                )
            }
        }

        let unique = ScanText.unique(candidates)
        return unique.count == 1 ? unique[0] : nil
    }

    private static func numberMatches(in text: String) -> [(card: Int, total: Int)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return numberRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let cardRange = Range(match.range(at: 1), in: text),
                  let totalRange = Range(match.range(at: 2), in: text),
                  let card = ScanText.normalizedInteger(String(text[cardRange])),
                  let total = ScanText.normalizedInteger(String(text[totalRange])) else {
                return nil
            }
            return (card, total)
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
    /// A line that is *nothing but* a collector number, allowing the rarity
    /// letter Magic prints on either side of it.
    private static let strictCollectorNumberRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[A-Z]\s+)?([0-9OIL]{1,4})(?:\s*/\s*([0-9OIL]{1,4}))?(?:\s+[A-Z])?\s*$"#,
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
        let lines = recognizedLines
            .map { $0.uppercased().replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Every line is examined once, then windows just combine the results.
        // Re-running the regexes per window would multiply the per-frame cost by
        // the window size for no new information.
        let examined = lines.map(examine)

        var candidates: [ScanIdentifier] = []
        for start in examined.indices {
            let limit = min(start + Self.footerWindow, examined.count)
            for stop in (start + 1)...limit {
                candidates.append(contentsOf: identities(in: examined[start..<stop]))
            }
        }

        let unique = ScanText.unique(candidates)
        return unique.count == 1 ? unique[0] : nil
    }

    /// What one observation contributes to a footer, worked out once.
    private struct ExaminedLine {
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
    }

    private func examine(_ line: String) -> ExaminedLine {
        ExaminedLine(
            hasEnglishMarker: containsEnglishMarker(in: line),
            codes: ScanText.matchedSubstrings(setCodeRegex, in: line),
            inlineNumbers: collectorNumbers(in: line),
            standaloneNumber: strictCollectorNumber(in: line)
        )
    }

    private func identities(in window: ArraySlice<ExaminedLine>) -> [ScanIdentifier] {
        guard window.contains(where: \.hasEnglishMarker) else { return [] }

        // More than one known code in view is two cards, or a coincidence. Either
        // way it is not an identification.
        let codes = ScanText.unique(window.flatMap(\.codes))
        guard codes.count == 1, let definition = definitions[codes[0]] else { return [] }

        var numbers: [CollectorNumberReading] = []
        for line in window {
            if line.isFooterText {
                numbers.append(contentsOf: line.inlineNumbers)
            } else if let standalone = line.standaloneNumber {
                numbers.append(standalone)
            }
        }

        return ScanText.unique(numbers)
            .filter { isValid($0, for: definition) }
            .map { .magic(setCode: codes[0], collectorNumber: String($0.card), language: "en") }
    }

    private func containsEnglishMarker(in text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.englishMarkerRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func collectorNumbers(in text: String) -> [CollectorNumberReading] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.collectorNumberRegex.matches(in: text, options: [], range: range)
            .compactMap { reading(from: $0, in: text) }
    }

    private func strictCollectorNumber(in text: String) -> CollectorNumberReading? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.strictCollectorNumberRegex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return reading(from: match, in: text)
    }

    private func reading(from match: NSTextCheckingResult, in text: String) -> CollectorNumberReading? {
        guard let cardRange = Range(match.range(at: 1), in: text),
              let card = ScanText.normalizedInteger(String(text[cardRange])) else { return nil }
        let denominator = Range(match.range(at: 2), in: text)
            .flatMap { ScanText.normalizedInteger(String(text[$0])) }
        return CollectorNumberReading(card: card, denominator: denominator)
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
