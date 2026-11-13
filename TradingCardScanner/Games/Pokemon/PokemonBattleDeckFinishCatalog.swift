import Foundation

/// Reviewed English deck-exclusive printings, including the 30th Celebration Battle Decks.
/// Each entry belongs to the card's original catalog identity and names its own market product.
enum PokemonBattleDeckFinishCatalog {
    enum Printing: String, Decodable, Sendable {
        case normal = "Normal"
        case reverse = "Reverse Holofoil"
        case holo = "Holofoil"

        var variant: PhysicalVariant {
            switch self {
            case .normal: .normal
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

    static let entries = load("pokemon-battle-deck-finishes", printings: [.reverse, .holo])
    static let normalEntries = load("pokemon-deck-exclusive-normals", printings: [.normal])

    private static func load(_ name: String, printings: [Printing]) -> [Entry] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let resource = try? JSONDecoder().decode(Resource.self, from: data),
              resource.schemaVersion == 1,
              Set(resource.entries.map(\.cardID)).count == resource.entries.count,
              Set(resource.entries.map(\.productID)).count == resource.entries.count,
              resource.entries.allSatisfy({ entry in
                  guard !entry.setID.isEmpty && !entry.name.isEmpty && !entry.marketName.isEmpty,
                        Int(entry.localID) != nil, entry.cardID == entry.setID + "-" + entry.localID,
                        entry.productID > 0, printings.contains(entry.printing) else { return false }
                  switch entry.printing {
                  case .normal, .reverse:
                      return entry.groupID == 1840 && entry.officialCount != nil && entry.setID != "mee"
                  case .holo:
                      return entry.groupID == 24461 && entry.printedNumber == entry.localID && entry.setID == "mee"
                  }
              }) else { return [] }
        return resource.entries
    }

    private static let byCardID = Dictionary(grouping: entries + normalEntries, by: \.cardID)
    private static let byProductID = Dictionary(grouping: entries + normalEntries, by: \.productID)
    static let setIDs = Set((entries + normalEntries).map(\.setID))

    static func entry(cardID: String, variantID: String?) -> Entry? {
        byCardID[cardID]?.first { $0.variant.id == variantID }
    }

    static func entry(productID: Int, variantID: String?) -> Entry? {
        guard let matches = byProductID[productID], matches.count == 1,
              let entry = matches.first, entry.variant.id == variantID else { return nil }
        return entry
    }

    static func entries(for card: TCGdexCard) -> [Entry] {
        byCardID[card.id, default: []].filter { entry in
            entry.setID == card.set.id && entry.localID == card.localId
                && (entry.officialCount.map { $0 == card.set.cardCount.official } ?? true)
                && entry.matches(name: card.name, number: card.localId)
        }
    }

    private static func entries(for summary: CatalogCardSummary) -> [Entry] {
        guard summary.game == .pokemon, summary.pokemonPrintRun == nil else { return [] }
        return byCardID[summary.providerID, default: []].filter {
            $0.setID == summary.setID.providerID && $0.matches(name: summary.name, number: summary.collectorNumber)
        }
    }

    static func entry(for summary: CatalogCardSummary, variantID: String? = nil) -> Entry? {
        let matches = entries(for: summary)
        if let selected = variantID ?? summary.masterSetVariant?.id {
            return matches.first { $0.variant.id == selected }
        }
        return matches.count == 1 ? matches.first : nil
    }

    static func projecting(_ cards: [CatalogCardSummary]) -> [CatalogCardSummary] {
        guard cards.contains(where: { byCardID[$0.providerID] != nil }) else { return cards }
        var emitted = Set(cards.map(\.id))
        return cards.flatMap { original -> [CatalogCardSummary] in
            let matches = entries(for: original)
            guard !matches.isEmpty else { return [original] }
            var base = original
            base.isSoleSlotForCard = false
            let additions = matches.compactMap { entry -> CatalogCardSummary? in
                if base.masterSetVariant?.id == entry.variant.id {
                    base.isExpandedMasterSetVariant = true
                    return nil
                }
                var slot = base
                slot.masterSetVariant = entry.variant
                slot.isExpandedMasterSetVariant = true
                return emitted.insert(slot.id).inserted ? slot : nil
            }
            return [base] + additions
        }
    }
}
