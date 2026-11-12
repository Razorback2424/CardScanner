import Foundation

/// Reviewed English printings from the two 30th Celebration Battle Decks.
/// Each entry belongs to the card's original catalog identity and names its own market product.
enum PokemonBattleDeckFinishCatalog {
    enum Printing: String, Decodable, Sendable {
        case reverse = "Reverse Holofoil"
        case holo = "Holofoil"

        var variant: PhysicalVariant {
            switch self {
            case .reverse: PokemonBattleDeckFinishCatalog.reverse
            case .holo: PokemonBattleDeckFinishCatalog.holo
            }
        }
    }

    struct Entry: Decodable, Sendable {
        let cardID: String
        let name: String
        let printedNumber: String
        let groupID: Int
        let productID: Int
        let marketName: String
        let printing: Printing

        var localID: String { String(printedNumber.prefix { $0 != "/" }) }
        var setID: String { String(cardID.dropLast(localID.count + 1)) }
        var officialCount: Int? { printedNumber.split(separator: "/").dropFirst().first.flatMap { Int($0) } }
        var variant: PhysicalVariant { printing.variant }

        func matches(name: String, number: String) -> Bool {
            CatalogIdentityNormalization.canonicalText(name) == CatalogIdentityNormalization.canonicalText(self.name)
                && ProductCatalogIdentity.numbersMatch(printedNumber, number)
        }
    }

    private struct Resource: Decodable {
        let schemaVersion: Int
        let entries: [Entry]
    }

    static let reverse = PokemonCatalogStampVariant.make(base: .reverse, stamps: ["30th-anniversary"])!
    static let holo = PokemonCatalogStampVariant.make(base: .holo, stamps: ["30th-anniversary"])!

    static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "pokemon-battle-deck-finishes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let resource = try? JSONDecoder().decode(Resource.self, from: data),
              resource.schemaVersion == 1,
              Set(resource.entries.map(\.cardID)).count == resource.entries.count,
              Set(resource.entries.map(\.productID)).count == resource.entries.count,
              resource.entries.allSatisfy({ entry in
                  !entry.setID.isEmpty && !entry.name.isEmpty && !entry.marketName.isEmpty
                      && Int(entry.localID) != nil && entry.cardID == entry.setID + "-" + entry.localID
                      && entry.productID > 0 && (entry.printing == .reverse
                          ? entry.groupID == 1840 && entry.officialCount != nil && entry.setID != "mee"
                          : entry.groupID == 24461 && entry.printedNumber == entry.localID && entry.setID == "mee")
              }) else { return [] }
        return resource.entries
    }()

    private static let byCardID = Dictionary(uniqueKeysWithValues: entries.map { ($0.cardID, $0) })
    private static let byProductID = Dictionary(uniqueKeysWithValues: entries.map { ($0.productID, $0) })
    static let setIDs = Set(entries.map(\.setID))

    static func entry(cardID: String, variantID: String?) -> Entry? {
        guard let entry = byCardID[cardID], entry.variant.id == variantID else { return nil }
        return entry
    }

    static func entry(productID: Int, variantID: String?) -> Entry? {
        guard let entry = byProductID[productID], entry.variant.id == variantID else { return nil }
        return entry
    }

    static func entry(for card: TCGdexCard) -> Entry? {
        guard let entry = byCardID[card.id], entry.setID == card.set.id, entry.localID == card.localId,
              entry.officialCount.map({ $0 == card.set.cardCount.official }) ?? true,
              entry.matches(name: card.name, number: card.localId) else { return nil }
        return entry
    }

    static func entry(for summary: CatalogCardSummary) -> Entry? {
        guard summary.game == .pokemon, summary.pokemonPrintRun == nil,
              let entry = byCardID[summary.providerID], entry.setID == summary.setID.providerID,
              entry.matches(name: summary.name, number: summary.collectorNumber) else { return nil }
        return entry
    }

    static func projecting(_ cards: [CatalogCardSummary]) -> [CatalogCardSummary] {
        guard cards.contains(where: { byCardID[$0.providerID] != nil }) else { return cards }
        var emitted = Set(cards.map(\.id))
        return cards.flatMap { original -> [CatalogCardSummary] in
            guard let entry = entry(for: original) else { return [original] }
            var base = original
            var deck = original
            deck.masterSetVariant = entry.variant
            deck.isExpandedMasterSetVariant = true
            deck.isSoleSlotForCard = false
            if base.masterSetVariant?.id == entry.variant.id { return [deck] }
            base.isSoleSlotForCard = false
            return emitted.insert(deck.id).inserted ? [base, deck] : [base]
        }
    }
}
