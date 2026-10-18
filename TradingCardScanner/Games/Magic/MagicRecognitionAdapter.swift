import Foundation

struct MagicRecognitionAdapter: GameRecognitionAdapter {
    let profile: MagicScanProfile
    var game: CardGame { .magic }
    var customWords: [String] { profile.customWords + ["PRM", "Bring-a-Friend", "Welcome Back", "Tarkir Dragonfury"] }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        let ordinary = profile.parseOutcome(lines)
        let promos = Self.printedPromos(lines)
        if !promos.isEmpty {
            if case .ambiguous = ordinary { return .ambiguous }
            if case .spatiallyRejectedCollector = ordinary { return .ambiguous }
            if case let .identified(identifier) = ordinary,
               !promos.contains(identifier),
               !Self.isDragonfuryBase(identifier, promos: promos) { return .ambiguous }
            return .identities(promos)
        }
        // An incomplete PRM footer must not fall through to an unrelated
        // historical title/number lookup. PRM is not a Scryfall set code.
        if lines.contains(where: { $0.text.localizedCaseInsensitiveContains("PRM") && Self.matches($0.text.uppercased(), #"\bPRM\b"#) }) {
            return .rejected(.init(reason: "Promo footer requires its release label and year", blocksFallbackRecognition: true))
        }
        switch ordinary {
        case .nothing: return .nothing
        case .ambiguous: return .ambiguous
        case let .identified(identifier): return .identified(ScanSubject(identifier: identifier))
        case .spatiallyRejectedCollector:
            return .rejected(.init(reason: "Collector reading is outside the footer identity region",
                                   blocksFallbackRecognition: true))
        }
    }

    /// Inspected Scryfall images and Wizards' promotion announcement are recorded
    /// in the coverage audit. Provider set/number differs from the physical footer.
    /// These are exact mappings, never a nearest-name or normal-set fallback.
    private static func printedPromos(_ lines: [RecognizedLine]) -> [ScanIdentifier] {
        let texts = lines.map { $0.text.uppercased().replacingOccurrences(of: "\n", with: " ") }
        guard texts.contains(where: { $0.contains("PRM") || $0.contains("TARKIR DRAGONFURY") }) else { return [] }
        var result: [ScanIdentifier] = []
        for start in texts.indices {
            let text = texts[start..<min(start + 3, texts.count)].joined(separator: " ")
            if matches(text, #"\bPRM\s*[★•·]?\s*EN\b"#), matches(text, #"\b2020\b"#) {
                for (label, rarity, number) in [("BRING[-– ]A[-– ]FRIEND", "U", "1"), ("WELCOME BACK", "P", "2")] {
                    if matches(text, #"\b001\s*/\s*001\s+"# + rarity + #"\s+"# + label + #"\b"#) {
                        result.append(.magic(setCode: "PLG20", collectorNumber: number, language: "en"))
                    }
                }
            }
            if text.contains("TARKIR DRAGONFURY"),
               let identifier = MagicScanProfile(definitions: [.init(code: "DTK", printedSize: 264)]).parse([text]),
               case let .magic(_, number, _, kind) = identifier.legacyIdentity,
               kind == .regular, ["135", "138", "187", "248"].contains(number) {
                result.append(.magic(setCode: "PTKDF", collectorNumber: number, language: "en"))
            }
        }
        return ScanText.unique(result)
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
