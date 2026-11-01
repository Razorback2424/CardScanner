import Foundation

struct MagicRecognitionAdapter: GameRecognitionAdapter {
    let profile: MagicScanProfile
    init(profile: MagicScanProfile) {
        // ALA 250 was printed in 2022 with a modern footer, although its
        // provider set dates to 2008 and correctly stays out of the set-wide
        // modern vocabulary. Every ALA result remains gated to this printing.
        self.profile = MagicScanProfile(definitions: Array(profile.definitions.values)
            + [.init(code: "ALA", printedSize: nil)])
    }
    var game: CardGame { .magic }
    var customWords: [String] { profile.customWords + ["PRM", "Bring-a-Friend", "Welcome Back", "Tarkir Dragonfury"] }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        let ordinary = profile.parseOutcome(lines)
        let promoWindows = Self.promoWindows(lines)
        let hasDragonfury = promoWindows.contains(where: Self.hasDragonfuryMarker)
        // A different window's EN must not erase a positive foreign footer.
        // Keep set/language adjacency bounded while checking all observations
        // before any reviewed promo mapping can win.
        if promoWindows.contains(where: { Self.hasConflictingLanguage($0, setCode: "PRM") })
            || (hasDragonfury && promoWindows.contains(where: { Self.hasConflictingLanguage($0, setCode: "DTK") })) {
            return .rejected(.init(reason: "Promo footer contains conflicting language evidence",
                blocksFallbackRecognition: true))
        }
        let promos = Self.printedPromos(promoWindows)
        if !promos.isEmpty {
            if case .ambiguous = ordinary { return .ambiguous }
            if case .spatiallyRejectedCollector = ordinary { return .ambiguous }
            if case let .identified(identifier) = ordinary,
               !promos.contains(identifier),
               !Self.isDragonfuryBase(identifier, promos: promos) { return .ambiguous }
            return .identities(promos)
        }
        // Positive promo evidence must not disappear when the remaining footer
        // is incomplete. Dragonfury prints DTK, so falling through here could
        // otherwise acquire an ordinary card under an OCR-misread number.
        if promoWindows.contains(where: { Self.matches($0, #"\bPRM\b"#) || Self.hasDragonfuryMarker($0) }) {
            return .rejected(.init(reason: "Promo footer requires matching release and collector evidence", blocksFallbackRecognition: true))
        }
        switch ordinary {
        case .nothing:
            if profile.hasModernFooterEvidence(lines) {
                return .rejected(.init(reason: "Modern Magic footer requires its collector number",
                    blocksFallbackRecognition: true))
            }
            return .nothing
        case .ambiguous: return .ambiguous
        case let .identified(identifier):
            if case let .magic(code, number, language, kind) = identifier.legacyIdentity,
               code == "ALA" {
                guard number == "250", language == "en", kind == .regular,
                      promoWindows.contains(where: { Self.matches($0, #"\bALA\s*[★•·]?\s*EN\b"#) }),
                      !promoWindows.contains(where: { Self.hasConflictingLanguage($0, setCode: "ALA") }),
                      !promoWindows.contains(where: { Self.matches($0, #"\b[0O]*25[0O]\s*/"#) }) else {
                    return .rejected(.init(reason: "Legacy-set footer is not a reviewed modern printing",
                        blocksFallbackRecognition: true))
                }
            }
            return .identified(ScanSubject(identifier: identifier))
        case .spatiallyRejectedCollector:
            return .rejected(.init(reason: "Collector reading is outside the footer identity region",
                                   blocksFallbackRecognition: true))
        }
    }

    /// Inspected Scryfall images and Wizards' promotion announcement are recorded
    /// in the coverage audit. Provider set/number differs from the physical footer.
    /// These are exact mappings, never a nearest-name or normal-set fallback.
    private static func printedPromos(_ windows: [String]) -> [ScanIdentifier] {
        guard windows.contains(where: { matches($0, #"\bPRM\b"#) || hasDragonfuryMarker($0) }) else { return [] }
        var result: [ScanIdentifier] = []
        for text in windows {
            if matches(text, #"\bPRM\s*[★•·]?\s*EN\b"#), matches(text, #"\b2020\b"#) {
                for (label, rarity, number) in [("BRING[-– ]A[-– ]FRIEND", "U", "1"), ("WELCOME BACK", "P", "2")] {
                    if matches(text, #"\b001\s*/\s*001\s+"# + rarity + #"\s+"# + label + #"\b"#) {
                        result.append(.magic(setCode: "PLG20", collectorNumber: number, language: "en"))
                    }
                }
            }
            if hasDragonfuryMarker(text),
               let identifier = MagicScanProfile(definitions: [.init(code: "DTK", printedSize: 264)]).parse([text]),
               case let .magic(_, number, _, kind) = identifier.legacyIdentity,
               kind == .regular, ["135", "138", "187", "248"].contains(number) {
                result.append(.magic(setCode: "PTKDF", collectorNumber: number, language: "en"))
            }
        }
        return ScanText.unique(result)
    }

    /// Vision may split a release label into adjacent observations. Use the
    /// same bounded windows for recognition and rejection so neither path can
    /// silently ignore that label or borrow distant card text.
    private static func promoWindows(_ lines: [RecognizedLine]) -> [String] {
        let texts = lines.map { $0.text.uppercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        return texts.indices.map { start in
            texts[start..<min(start + 3, texts.count)].joined(separator: " ")
        }
    }

    private static func hasDragonfuryMarker(_ text: String) -> Bool {
        matches(text, #"\bTARKIR\s+DRAGONFURY\b"#)
    }

    private static func hasConflictingLanguage(_ text: String, setCode: String) -> Bool {
        matches(text, #"\b"# + NSRegularExpression.escapedPattern(for: setCode)
            + #"\s*[★•·]?\s*(?!EN\b)[A-Z]{2,3}\b"#)
    }

    private static func isDragonfuryBase(_ identifier: ScanIdentifier, promos: [ScanIdentifier]) -> Bool {
        guard case let .magic(code, number, language, kind) = identifier.legacyIdentity,
              code.uppercased() == "DTK", language == "en", kind == .regular else { return false }
        return promos.contains(.magic(setCode: "PTKDF", collectorNumber: number, language: "en"))
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
