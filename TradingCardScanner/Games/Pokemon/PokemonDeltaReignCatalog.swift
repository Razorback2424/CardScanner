import Foundation

/// The two non-holo deck reprints and the English Delta Reign promo printings.
/// The printed footer identifies the card. Its finish or stamp is a separate choice.
enum PokemonDeltaReignCatalog {
    static let deckSetID = "me06"
    static let promoSetID = "mep"
    static let setIDs: Set<String> = [deckSetID, promoSetID]
    private static let resource = "pokemon-delta-reign-printings"
    private static let promoSetName = "MEP Black Star Promos"

    enum Finish: String, Decodable, Sendable {
        case normal, prerelease, staff, cosmos, holo, pokemonCenter

        var variant: PhysicalVariant {
            switch self {
            case .normal: .normal
            case .holo: .holo
            case .cosmos: .pokemonFoilPattern("cosmos")
            case .prerelease: PokemonCatalogStampVariant.make(base: .holo, stamps: ["set-logo"])!
            case .staff: PokemonCatalogStampVariant.make(base: .holo, stamps: ["set-logo", "staff"])!
            case .pokemonCenter: PokemonCatalogStampVariant.make(base: .holo, stamps: ["pokemon-center"])!
            }
        }

        var printing: String { self == .normal ? "Normal" : "Holofoil" }
    }

    struct Printing: Decodable, Sendable {
        let finish: Finish
        let productID: Int?
        let marketName: String?
        let marketNumberMayBeMissing: Bool?

        var variant: PhysicalVariant { finish.variant }
        var thumbnailURL: URL? { artwork("_200w.jpg") }
        var imageURL: URL? { artwork("_in_1000x1000.jpg") }

        private func artwork(_ suffix: String) -> URL? {
            productID.flatMap { URL(string: "https://tcgplayer-cdn.tcgplayer.com/product/\($0)\(suffix)") }
        }
    }

    struct Card: Decodable, Sendable {
        let cardID: String
        let name: String
        let number: String
        let printings: [Printing]

        var localID: String { String(number.prefix(3)) }
        var setID: String { String(cardID.dropLast(4)) }
        var isPromo: Bool { setID == PokemonDeltaReignCatalog.promoSetID }
        var groupID: Int { isPromo ? 24451 : 1840 }

        func matches(setID: String, name: String, localID: String) -> Bool {
            self.setID == setID && self.localID == localID
                && CatalogIdentityNormalization.canonicalText(self.name) == CatalogIdentityNormalization.canonicalText(name)
        }
    }

    private struct Resource: Decodable {
        let schemaVersion: Int
        let cards: [Card]
    }

    static let cards: [Card] = {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(Resource.self, from: data), table.schemaVersion == 1 else { return [] }
        let ids = Set(["me06-021", "me06-075"] + (111...117).map { "mep-\($0)" })
        let products = table.cards.flatMap(\.printings).compactMap(\.productID)
        guard table.cards.count == ids.count, Set(table.cards.map(\.cardID)) == ids,
              Set(products).count == products.count, table.cards.allSatisfy({ card in
                  !card.name.isEmpty && card.cardID == "\(card.setID)-\(card.localID)"
                      && card.number == (card.isPromo ? card.localID : "\(card.localID)/103")
                      && !card.printings.isEmpty && Set(card.printings.map { $0.variant.id }).count == card.printings.count
                      && card.printings.allSatisfy { printing in
                          guard (printing.finish == .normal) != card.isPromo else { return false }
                          if let id = printing.productID { return id > 0 && printing.marketName?.isEmpty == false }
                          return card.cardID == "mep-114" && printing.finish == .staff && printing.marketName == nil
                      }
              }) else { return [] }
        return table.cards
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.cardID, $0) })
    private static let byProductID = Dictionary(uniqueKeysWithValues: cards.flatMap { card in
        card.printings.compactMap { printing in printing.productID.map { ($0, printing) } }
    })

    static func card(_ cardID: String) -> Card? { byID[cardID] }

    static func card(for payload: TCGdexCard) -> Card? {
        guard let card = byID[payload.id], card.matches(setID: payload.set.id, name: payload.name, localID: payload.localId),
              card.isPromo || payload.set.cardCount.official == 103 else { return nil }
        return card
    }

    static func card(for summary: CatalogCardSummary) -> Card? {
        guard summary.game == .pokemon, summary.pokemonPrintRun == nil, let card = byID[summary.providerID],
              card.matches(setID: summary.setID.providerID, name: summary.name, localID: summary.collectorNumber) else { return nil }
        return card
    }

    static func printing(productID: Int, variantID: String?) -> Printing? {
        guard let printing = byProductID[productID], printing.variant.id == variantID else { return nil }
        return printing
    }

    static func printing(for summary: CatalogCardSummary) -> Printing? {
        card(for: summary)?.printings.first { $0.variant.id == summary.masterSetVariant?.id }
    }

    static func promoPayload(cardID: String) -> TCGdexCard? {
        guard let card = byID[cardID], card.isPromo else { return nil }
        return TCGdexCard(id: card.cardID, localId: card.localID, name: card.name,
            image: card.printings.first?.imageURL?.absoluteString, rarity: "Promo",
            set: .init(id: promoSetID, name: promoSetName, cardCount: .init(total: 0, official: 0)),
            variants: nil, pricing: nil, variantsDetailed: nil, projectedCatalogVariants: card.printings.map(\.variant))
    }

    static let bundledPromoEntry: PokemonChecklistSnapshotEntry? = {
        let promos = cards.filter(\.isPromo)
        guard !promos.isEmpty else { return nil }
        let total = promos.reduce(0) { $0 + $1.printings.count }
        let set = CatalogSet(catalogID: .init(game: .pokemon, providerID: promoSetID), name: promoSetName,
            code: "MEP", logoURL: nil, symbolURL: nil, cardCount: total, releaseDate: nil, sortRank: 0)
        return .init(set: set, providerID: promoSetID, officialCount: nil, standardSlotCount: promos.count,
            expandedSlotCount: total, resource: resource + ".json")
    }()

    static func projecting(_ summaries: [CatalogCardSummary], set: CatalogSet) -> [CatalogCardSummary] {
        guard set.game == .pokemon, set.pokemonPrintRun == nil, setIDs.contains(set.providerID) else { return summaries }
        var projected = summaries
        for card in cards where card.setID == set.providerID {
            let matching = projected.indices.filter { projected[$0].providerID == card.cardID }
            guard matching.allSatisfy({ card.matches(setID: projected[$0].setID.providerID,
                name: projected[$0].name, localID: projected[$0].collectorNumber) }) else { continue }
            if card.isPromo {
                let base = matching.first.map { projected[$0] } ?? CatalogCardSummary(game: .pokemon,
                    providerID: card.cardID, setID: set.catalogID, setName: set.name, setCode: "MEP", name: card.name,
                    collectorNumber: card.localID, thumbnailURL: nil, imageURL: nil)
                projected.removeAll { $0.providerID == card.cardID }
                for (index, printing) in card.printings.enumerated() {
                    var slot = base.withArtwork(thumbnailURL: printing.thumbnailURL, imageURL: printing.imageURL)
                    slot.masterSetVariant = printing.variant
                    slot.isExpandedMasterSetVariant = index > 0
                    slot.isSoleSlotForCard = card.printings.count == 1
                    slot.limitlessArtworkAuthorized = false
                    projected.append(slot)
                }
            } else if let first = matching.first, let printing = card.printings.first {
                var slot = projected[first].withArtwork(thumbnailURL: printing.thumbnailURL, imageURL: printing.imageURL)
                slot.masterSetVariant = printing.variant
                slot.isExpandedMasterSetVariant = true
                slot.isSoleSlotForCard = false
                for index in matching { projected[index].isSoleSlotForCard = false }
                if let existing = matching.first(where: { projected[$0].masterSetVariant == .normal }) {
                    projected[existing] = slot
                } else {
                    projected.append(slot)
                }
            }
        }
        return projected
    }
}
