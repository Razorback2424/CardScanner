import Foundation
import SwiftData

enum CollectionActivitySource: String, CaseIterable, Sendable {
    case scan
    case csvImport
    case catalog
    case sealedCatalog
    case gradedCatalog
    case correction

    var label: String {
        switch self {
        case .scan: return "Scan"
        case .csvImport: return "CSV Import"
        case .catalog: return "Browse"
        case .sealedCatalog: return "Sealed Browse"
        case .gradedCatalog: return "Graded Browse"
        case .correction: return "Correction"
        }
    }

    var symbolName: String {
        switch self {
        case .scan: return "viewfinder"
        case .csvImport: return "square.and.arrow.down"
        case .catalog: return "rectangle.grid.2x2"
        case .sealedCatalog: return "shippingbox"
        case .gradedCatalog: return "checkmark.seal"
        case .correction: return "pencil"
        }
    }
}

/// Durable audit trail for every acquisition. The timestamp and source are
/// immutable facts; the metadata snapshot follows user corrections so history
/// always shows what the collection currently believes was added.
@Model
final class CollectionActivity {
    @Attribute(.unique) var id: UUID
    var occurredAt: Date
    var sourceRaw: String
    var collectionKey: String
    var gameRaw: String
    var itemKindRaw: String
    var name: String
    var setName: String
    var setCode: String
    var cardNumber: String
    var variantID: String?
    var variantLabel: String?
    var pokemonPrintRunRaw: String?
    var quantity: Int
    var correctedAt: Date?

    init(
        card: CollectedCard,
        source: CollectionActivitySource,
        quantity: Int = 1,
        occurredAt: Date = .now
    ) {
        id = UUID()
        self.occurredAt = occurredAt
        sourceRaw = source.rawValue
        collectionKey = card.collectionKey
        gameRaw = card.game
        itemKindRaw = card.itemKindRaw
        name = card.name
        setName = card.setName
        setCode = card.setCode
        cardNumber = card.cardNumber
        variantID = card.variantID
        variantLabel = card.variantLabel
        pokemonPrintRunRaw = card.pokemonPrintRun?.rawValue
        self.quantity = quantity
    }

    var source: CollectionActivitySource {
        CollectionActivitySource(rawValue: sourceRaw) ?? .catalog
    }

    var game: CardGame { CardGame(rawValue: gameRaw) ?? .pokemon }
    var itemKind: CollectionItemKind {
        CollectionItemKind(rawValue: itemKindRaw) ?? .rawCard
    }
    var pokemonPrintRun: PokemonPrintRun? {
        pokemonPrintRunRaw.flatMap(PokemonPrintRun.init(rawValue:))
    }
}
