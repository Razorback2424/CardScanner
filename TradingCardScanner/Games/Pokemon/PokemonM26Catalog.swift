import Foundation

/// The English Happy Meal set, with one reviewed physical finish per number.
/// Use marketplace IDs as stable identities while the set has no TCGdex IDs.
enum PokemonM26Catalog {
    static let groupID = 24938
    static let setID = "tcgplayer:\(groupID)"
    static let catalogSetID = CatalogSetID(game: .pokemon, providerID: setID)
    static let setCode = "M26"
    static let officialCount = 15
    private static let resource = "pokemon-mcdonalds-2026"

    enum Printing: String, Decodable, Sendable {
        case normal = "Normal"
        case holo = "Holofoil"

        var variant: PhysicalVariant { self == .normal ? .normal : .holo }
    }

    struct Entry: Decodable, Sendable {
        let number: String
        let name: String
        let productID: Int
        let printing: Printing

        var localID: String { String(number.prefix(3)) }
        var cardID: String { "tcgplayer:\(productID)" }
        var variant: PhysicalVariant { printing.variant }
        var thumbnailURL: URL? { artwork(suffix: "_200w.jpg") }
        var imageURL: URL? { artwork(suffix: "_in_1000x1000.jpg") }

        func matches(name: String, number: String) -> Bool {
            CatalogIdentityNormalization.canonicalText(name) == CatalogIdentityNormalization.canonicalText(self.name)
                && ProductCatalogIdentity.numbersMatch(self.number, number)
        }

        private func artwork(suffix: String) -> URL? {
            URL(string: "https://tcgplayer-cdn.tcgplayer.com/product/\(productID)\(suffix)")
        }
    }

    private struct Resource: Decodable {
        let schemaVersion: Int
        let groupID: Int
        let setCode: String
        let setName: String
        let releaseDate: String
        let cards: [Entry]
    }

    private static let table: Resource? = {
        let numbers = Set((1...officialCount).map { String(format: "%03d/%03d", $0, officialCount) })
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Resource.self, from: bytes),
              decoded.schemaVersion == 1, decoded.groupID == groupID, decoded.setCode == setCode,
              !decoded.setName.isEmpty, FlexibleDate.parse(decoded.releaseDate) != nil,
              decoded.cards.count == officialCount, Set(decoded.cards.map(\.number)) == numbers,
              Set(decoded.cards.map(\.productID)).count == officialCount,
              decoded.cards.allSatisfy({ $0.productID > 0 && !$0.name.isEmpty }) else { return nil }
        return decoded
    }()

    static let entries = table?.cards ?? []
    private static let byCardID = Dictionary(uniqueKeysWithValues: entries.map { ($0.cardID, $0) })
    private static let byNumber = Dictionary(uniqueKeysWithValues: entries.map { ($0.localID, $0) })

    static let descriptor: PokemonCatalogSetDescriptor? = table.map {
        .init(providerSetID: setID, displayName: $0.setName, releaseDate: $0.releaseDate,
              releaseOrder: 25, recognitionKind: .expansion, printedCode: setCode,
              officialCount: officialCount, printedPrefix: nil, catalogLocalIDPrefix: nil,
              localIDPadWidth: nil, scanEnabled: true, logoURL: nil, symbolURL: nil,
              providerFingerprint: nil, rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules)
    }

    static let checklistEntry: PokemonChecklistSnapshotEntry? = table.map {
        let set = CatalogSet(catalogID: catalogSetID, name: $0.setName,
            code: setCode, logoURL: nil, symbolURL: nil, cardCount: officialCount,
            releaseDate: FlexibleDate.parse($0.releaseDate), sortRank: 25,
            artworkFallbackURLs: entries.prefix(3).compactMap(\.imageURL), limitlessArtworkAuthorized: false)
        return .init(set: set, providerID: setID, officialCount: officialCount,
            standardSlotCount: officialCount, expandedSlotCount: officialCount, resource: resource + ".json")
    }

    static func checklist(for entry: PokemonChecklistSnapshotEntry) -> [CatalogCardSummary]? {
        guard entry == checklistEntry else { return nil }
        return entries.map { card in
            CatalogCardSummary(game: .pokemon, providerID: card.cardID, setID: entry.set.catalogID,
                setName: entry.set.name, setCode: setCode, name: card.name, collectorNumber: card.localID,
                thumbnailURL: card.thumbnailURL, imageURL: card.imageURL,
                masterSetVariant: card.variant, isSoleSlotForCard: true, limitlessArtworkAuthorized: false)
        }
    }

    static func entry(cardID: String) -> Entry? { byCardID[cardID] }
    static func entry(localID: String) -> Entry? { byNumber[localID] }

    static func entry(for summary: CatalogCardSummary) -> Entry? {
        guard summary.game == .pokemon, summary.setID == catalogSetID,
              let entry = entry(cardID: summary.providerID),
              entry.matches(name: summary.name, number: summary.collectorNumber) else { return nil }
        return entry
    }

    static func entry(for card: TCGdexCard) -> Entry? {
        guard card.set.id == setID, card.set.cardCount.official == officialCount,
              let entry = entry(cardID: card.id), entry.localID == card.localId,
              entry.matches(name: card.name, number: card.localId) else { return nil }
        return entry
    }

    static func card(providerID: String) -> TCGdexCard? {
        byCardID[providerID].flatMap(card(for:))
    }

    static func card(for entry: Entry) -> TCGdexCard? {
        guard let table else { return nil }
        let variant = entry.variant
        return TCGdexCard(id: entry.cardID, localId: entry.localID, name: entry.name,
            image: entry.imageURL?.absoluteString, rarity: "Promo",
            set: .init(id: setID, name: table.setName, cardCount: .init(total: officialCount, official: officialCount)),
            variants: .init(firstEdition: false, holo: variant == .holo, normal: variant == .normal,
                reverse: false, wPromo: false), pricing: nil, variantsDetailed: nil, projectedCatalogVariants: [variant])
    }
}
