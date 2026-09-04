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

/// What changed in the collection. `CollectionActivitySource` remains the
/// answer to a different question: where the change came from.
enum CollectionActivityKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case added
    case removed
    case restored
    case corrected
    case quantityAdjusted
    case undone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: return "Added"
        case .removed: return "Removed"
        case .restored: return "Restored"
        case .corrected: return "Corrected"
        case .quantityAdjusted: return "Quantity adjusted"
        case .undone: return "Undone"
        }
    }

    var symbolName: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .restored: return "arrow.uturn.backward.circle.fill"
        case .corrected: return "pencil.circle.fill"
        case .quantityAdjusted: return "number.circle.fill"
        case .undone: return "arrow.uturn.left.circle.fill"
        }
    }

    /// The positive quantity an entry still represents. Correction entries are
    /// deliberately zero: the original entry moves identity and the correction
    /// row records that fact without counting the copy twice.
    var hasQuantityClaim: Bool {
        self == .added || self == .restored
    }
}

/// Durable, user-facing history for every collection mutation. The timestamp
/// and source are immutable facts; the metadata snapshot follows user
/// corrections so history shows what the collection currently believes was
/// added while the correction rows preserve the fact that it changed.
@Model
final class CollectionActivity {
    // CloudKit does not support unique constraints. `id` never needs a code-level
    // lookup the way the other stores' keys do — a UUID collision is not a
    // realistic concern — so nothing else has to change to compensate.
    @Attribute var id: UUID = UUID()
    var occurredAt: Date = Date.now
    var sourceRaw: String = ""
    /// Added in the history phase. The default keeps rows written by the older
    /// acquisition-only model meaningful after a lightweight migration.
    var kindRaw: String = CollectionActivityKind.added.rawValue
    var collectionKey: String = ""
    var gameRaw: String = ""
    var itemKindRaw: String = ""
    var name: String = ""
    var setName: String = ""
    var setCode: String = ""
    var cardNumber: String = ""
    var variantID: String?
    var variantLabel: String?
    /// Stored independently from the finish so history preserves the exact
    /// treatment-qualified collection identity it describes.
    var magicTreatmentIDsRaw: [String] = []
    var pokemonPrintRunRaw: String?
    /// Kept for lightweight migration compatibility with the acquisition-only
    /// model. New code reads `deltaQuantity`; it is the unsigned legacy mirror.
    var quantity: Int = 1
    /// Signed quantity represented by this history entry. A zero is reserved for
    /// a correction entry and also lets old rows fall back to `quantity`.
    var deltaQuantity: Int = 0
    /// Ledger operations represented by this entry. It is session-independent
    /// history state, unlike `CollectionMutation`, and is what makes a restore
    /// or correction target the exact operation it describes.
    var ledgerOperationIDs: [UUID] = []
    /// Only removal entries use this. The ledger has no artwork/provider fields,
    /// so this snapshot is the durable material needed to restore a position.
    var removalSnapshotData: Data?
    /// Number of the entry's claimed copies already consumed by a later action.
    /// It prevents a repeated tap from applying the same history action twice.
    var resolvedQuantity: Int = 0
    var correctedAt: Date?

    init(
        card: CollectedCard,
        source: CollectionActivitySource,
        quantity: Int = 1,
        occurredAt: Date = .now,
        kind: CollectionActivityKind = .added,
        deltaQuantity: Int? = nil,
        ledgerOperationIDs: [UUID] = [],
        removalSnapshotData: Data? = nil,
        resolvedQuantity: Int = 0
    ) {
        id = UUID()
        self.occurredAt = occurredAt
        sourceRaw = source.rawValue
        kindRaw = kind.rawValue
        collectionKey = card.collectionKey
        gameRaw = card.game
        itemKindRaw = card.itemKindRaw
        name = card.name
        setName = card.setName
        setCode = card.setCode
        cardNumber = card.cardNumber
        variantID = card.variantID
        variantLabel = card.variantLabel
        magicTreatmentIDsRaw = card.magicTreatmentIDsRaw
        pokemonPrintRunRaw = card.pokemonPrintRun?.rawValue
        self.quantity = quantity
        let defaultDelta: Int
        switch kind {
        case .removed, .undone: defaultDelta = -quantity
        case .corrected: defaultDelta = 0
        case .added, .restored, .quantityAdjusted: defaultDelta = quantity
        }
        self.deltaQuantity = deltaQuantity ?? defaultDelta
        self.ledgerOperationIDs = ledgerOperationIDs
        self.removalSnapshotData = removalSnapshotData
        self.resolvedQuantity = resolvedQuantity
    }

    var source: CollectionActivitySource {
        CollectionActivitySource(rawValue: sourceRaw) ?? .catalog
    }

    var kind: CollectionActivityKind {
        CollectionActivityKind(rawValue: kindRaw) ?? .added
    }

    /// Old rows have a zero-filled `deltaQuantity` after migration. Their
    /// original unsigned quantity remains available as the truthful fallback.
    var signedQuantity: Int {
        if deltaQuantity != 0 { return deltaQuantity }
        return kind == .added ? quantity : 0
    }

    var claimedQuantity: Int { abs(signedQuantity) }
    var remainingQuantity: Int {
        max(0, claimedQuantity - resolvedQuantity)
    }

    var isResolved: Bool {
        remainingQuantity == 0
    }

    var game: CardGame { CardGame(rawValue: gameRaw) ?? .pokemon }
    var itemKind: CollectionItemKind {
        CollectionItemKind(rawValue: itemKindRaw) ?? .rawCard
    }
    var pokemonPrintRun: PokemonPrintRun? {
        pokemonPrintRunRaw.flatMap(PokemonPrintRun.init(rawValue:))
    }
}

extension CollectionActivity {
    /// Removal restore is intentionally a short-lived affordance. The snapshot
    /// remains stored forever, so extending this later does not lose data.
    static let restoreWindow: TimeInterval = 15 * 60

    /// Compares the history projection with the append-only ledger. Keys present
    /// on only one side are included too, so a missing history row is visible as
    /// a diagnostic rather than silently treated as zero activity.
    static func integrityDefects(
        activities: [CollectionActivity],
        events: [InventoryEvent]
    ) -> [LedgerIntegrityDefect] {
        let activityKeys = Set(activities.map(\.collectionKey))
            .union(events.map(\.collectionKey))
        guard !activityKeys.isEmpty else { return [] }

        let activityQuantities = activities.reduce(into: [String: Int]()) { result, activity in
            result[activity.collectionKey, default: 0] += activity.signedQuantity
        }
        let ledgerQuantities = events.reduce(into: [String: Int]()) { result, event in
            result[event.collectionKey, default: 0] += event.deltaQuantity
        }

        return activityKeys
            .filter { activityQuantities[$0, default: 0] != ledgerQuantities[$0, default: 0] }
            .map { key in
                LedgerIntegrityDefect(
                    reason: .quantityMismatch,
                    collectionKey: key,
                    detail: "ledger \(ledgerQuantities[key, default: 0]), activity \(activityQuantities[key, default: 0])",
                    canRepairQuantity: false
                )
            }
            .sorted { $0.collectionKey < $1.collectionKey }
    }
}
