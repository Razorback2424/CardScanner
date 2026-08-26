import Foundation
import SwiftData

/// One owned position, as the app reasons about ownership rather than as the
/// store happens to hold it.
///
/// A `collectionKey` identifies a physical object the user owns. It does *not*
/// identify a row: two devices adding the same card while offline each pass
/// their own local uniqueness check — `CollectionStore.card(forKey:)` is a
/// local read — and CloudKit later delivers both. Every part of the app that
/// asks "how many of this do I own" has to answer from the sum, not from
/// whichever row a fetch returned first.
struct LogicalCollectedPosition: Identifiable {
    let collectionKey: String
    /// Summed across every physical row claiming this key.
    let quantity: Int
    /// The row whose metadata represents the position. Chosen deterministically
    /// so the same store always projects the same way.
    let representative: CollectedCard
    /// The instrument this position is valued through.
    let priceStorageKey: String
    /// Most recent acquisition across the duplicates, which is what "recently
    /// added" should mean for a position that exists twice.
    let dateAdded: Date
    /// How many physical rows claim this key. Greater than one is not itself a
    /// defect — it is the condition the projection exists to absorb.
    let physicalRowCount: Int

    var id: String { collectionKey }
}

/// The whole collection, projected once.
struct LogicalCollectionProjection {
    /// Deterministically ordered: newest acquisition first, matching the query
    /// order the grid already relies on.
    let positions: [LogicalCollectedPosition]
    let byKey: [String: LogicalCollectedPosition]
    /// Duplicate rows that disagree about what they are — see
    /// `duplicatePositionPricingConflict`.
    let defects: [LedgerIntegrityDefect]

    /// Quantities keyed by position, for comparison against the ledger.
    var quantities: [String: Int] {
        Dictionary(uniqueKeysWithValues: positions.map { ($0.collectionKey, $0.quantity) })
    }

    var totalQuantity: Int { positions.reduce(0) { $0 + $1.quantity } }

    /// A cheap, order-independent signature of what is owned. Used to decide
    /// whether accounting needs recomputing — deliberately not a cryptographic
    /// digest, because nothing outside this process ever compares it.
    var mutationSignature: Int {
        var hasher = Hasher()
        hasher.combine(positions.count)
        for position in positions {
            hasher.combine(position.collectionKey)
            hasher.combine(position.quantity)
            hasher.combine(position.priceStorageKey)
        }
        return hasher.finalize()
    }
}

/// Builds the logical projection from physical storage rows.
///
/// Deliberately one implementation rather than five. Before this existed, the
/// grid summed duplicates, the CSV importer trapped on them, and the migration
/// baseline wrote one event per *row* — so a collection that had ever synced a
/// duplicate opened its books at the wrong quantity. Each site was individually
/// reasonable and collectively wrong; there is now a single answer to what is
/// owned.
@MainActor
enum LogicalCollection {
    static func project(
        cards: [CollectedCard],
        ledger: InventoryLedger
    ) -> LogicalCollectionProjection {
        var groups: [String: [CollectedCard]] = [:]
        var order: [String] = []
        for card in cards {
            if groups[card.collectionKey] == nil { order.append(card.collectionKey) }
            groups[card.collectionKey, default: []].append(card)
        }

        var positions: [LogicalCollectedPosition] = []
        var defects: [LedgerIntegrityDefect] = []
        positions.reserveCapacity(order.count)

        for key in order {
            guard let rows = groups[key], let first = rows.first else { continue }

            let representative = rows.count == 1 ? first : chooseRepresentative(from: rows)
            let priceStorageKey = ledger.priceStorageKey(for: representative)

            // Rows agreeing on identity but disagreeing on what they are priced
            // as cannot both be right, and picking one would decide the
            // position's value by fetch order. Surfaced instead.
            if rows.count > 1 {
                let conflicting = rows.filter { ledger.priceStorageKey(for: $0) != priceStorageKey }
                if !conflicting.isEmpty {
                    defects.append(
                        LedgerIntegrityDefect(
                            reason: .duplicatePositionPricingConflict,
                            collectionKey: key,
                            detail: "\(rows.count) rows claim this position; \(conflicting.count) price through a different instrument than \(priceStorageKey)"
                        )
                    )
                }
            }

            positions.append(
                LogicalCollectedPosition(
                    collectionKey: key,
                    quantity: rows.reduce(0) { $0 + $1.quantity },
                    representative: representative,
                    priceStorageKey: priceStorageKey,
                    dateAdded: rows.map(\.dateAdded).max() ?? representative.dateAdded,
                    physicalRowCount: rows.count
                )
            )
        }

        LedgerIntegrityLog.shared.replace(
            reason: .duplicatePositionPricingConflict,
            with: defects
        )

        return LogicalCollectionProjection(
            positions: positions,
            byKey: Dictionary(positions.map { ($0.collectionKey, $0) }, uniquingKeysWith: { first, _ in first }),
            defects: defects
        )
    }

    /// Deterministic, and deliberately not "whichever row came back first".
    ///
    /// The oldest acquisition wins, because it is the row the rest of the
    /// collection's history refers to. Remaining ties break on stable identity
    /// fields so two devices projecting the same store agree.
    private static func chooseRepresentative(from rows: [CollectedCard]) -> CollectedCard {
        rows.min { lhs, rhs in
            if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
            if lhs.providerID != rhs.providerID { return lhs.providerID < rhs.providerID }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return (lhs.catalogProviderID ?? "") < (rhs.catalogProviderID ?? "")
        } ?? rows[0]
    }
}
