import Foundation

struct PokemonRecognitionAdapter: GameRecognitionAdapter {
    let profile: PokemonScanProfile
    private let catalogGeneration: String

    init(profile: PokemonScanProfile) {
        self.profile = profile
        catalogGeneration = PokemonCatalogAdapter.generation(for: profile.registry)
    }

    var game: CardGame { .pokemon }
    var customWords: [String] { profile.customWords }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        profile.parseOutcome(lines)
    }

    func needsFullCardText(afterFooterLines lines: [RecognizedLine]) -> Bool {
        guard let year = PokemonUnnumberedEnergyEvidence.copyrightYear(lines),
              let family = PokemonReviewedEnergyCatalog.unnumberedFamily(year: year) else { return false }
        return !profile.registry.isScanDisabled(forProviderSetID: family.providerSetID)
    }

    func identify(footerLines: [RecognizedLine], fullCardLines: [RecognizedLine]) -> GameRecognitionOutcome {
        guard let year = PokemonUnnumberedEnergyEvidence.copyrightYear(footerLines),
              let family = PokemonReviewedEnergyCatalog.unnumberedFamily(year: year),
              !profile.registry.isScanDisabled(forProviderSetID: family.providerSetID),
              PokemonUnnumberedEnergyEvidence.agreesWithFullCard(fullCardLines, year: year)
        else { return .nothing }
        return .identified(ScanSubject(identifier: PokemonUnnumberedEnergyEvidence.identifier(year: year, generation: catalogGeneration)))
    }
}

/// These layouts print the same header across Energy types.
/// These observations can open a printing choice. They never identify a type.
enum PokemonUnnumberedEnergyEvidence {
    static let namespace = "unnumbered-energy"
    private static let scanYears: Set<Int> = [2013, 2017, 2019, 2020, 2022]
    private static let fullCopyrightYears: Set<Int> = [2020, 2022]
    private static let copyright = try! NSRegularExpression(pattern:
        #"^(?:[©CE02] *)?(20\d{2}) POKEMON( */ *NINTENDO */ *CREATURES */ *GAME FREAK)?$"#)

    static func copyrightYear(_ lines: [RecognizedLine]) -> Int? {
        let text = ScanText.unique(lines.map { normalized($0.text) }.filter { !$0.isEmpty }).joined(separator: " ")
        guard let match = copyright.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let year = Int(text[range]),
              scanYears.contains(year),
              (match.range(at: 2).location != NSNotFound) == fullCopyrightYears.contains(year) else { return nil }
        return year
    }

    static func agreesWithFullCard(_ lines: [RecognizedLine], year: Int) -> Bool {
        let titleIndices = lines.indices.filter { normalized(lines[$0].text) == "ENERGY" }
        guard titleIndices.count == 1, let title = titleIndices.first,
              lines[title].boundingBox.map({ $0.minY >= 0.85 && $0.minX <= 0.30 }) ?? true else { return false }
        let footer = lines.enumerated().filter { $0.offset != title && !isCentralSymbol($0.element) }.map(\.element)
        return footer.allSatisfy { $0.boundingBox.map { $0.maxY <= 0.15 } ?? true }
            && copyrightYear(footer) == year
    }

    private static func isCentralSymbol(_ line: RecognizedLine) -> Bool {
        // Vision can read the large Psychic Energy icon as a copyright sign.
        guard line.text == "©", let box = line.boundingBox else { return false }
        return box.minX >= 0.25 && box.maxX <= 0.75 && box.minY >= 0.25 && box.maxY <= 0.75
    }

    static func identifier(year: Int, generation: String) -> ScanIdentifier {
        try! ScanIdentifier(game: .pokemon, namespace: namespace, fields: [.init(key: "year", value: String(year))],
            displayIdentifier: "\(year) Energy", suppressionIdentity: "\(namespace):\(year)", catalogGeneration: generation)
    }

    static func family(for identifier: ScanIdentifier, registry: PokemonCatalogRegistry) -> PokemonReviewedEnergyCatalog.UnnumberedFamily? {
        guard identifier.game == .pokemon, identifier.namespace == namespace, identifier.fields.count == 1,
              let field = identifier.fields.first, field.key == "year", let year = Int(field.value),
              field.value == String(year), scanYears.contains(year),
              let family = PokemonReviewedEnergyCatalog.unnumberedFamily(year: year),
              !registry.isScanDisabled(forProviderSetID: family.providerSetID) else { return nil }
        return family
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
