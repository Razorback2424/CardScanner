import Foundation
import SwiftData

/// What a ledger row says happened to ownership.
enum InventoryEventKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// The synthetic baseline written once, when portfolio tracking starts.
    /// Nothing else may ever use this — see `PortfolioEpoch`.
    case initialBalance
    /// A copy entered the collection now: a scan, a browse add, a purchase.
    case acquire
    /// A copy the user already owned was *recorded* now. A shoebox of 400
    /// pre-owned cards being scanned is this, not `initialBalance`: it is new
    /// to the app on the day it is entered and has to appear in that day's
    /// reconciliation, or its value lands in Unexplained.
    case recordExisting
    /// A copy left the collection.
    case dispose
    /// A quantity edited directly, with no acquisition or disposal implied.
    case quantityAdjust
    /// One leg of a two-leg correction. Never appears alone.
    case correction

    /// Whether this kind adds copies to the collection as a *flow*, which is
    /// the "Added to collection" line on the Today card.
    var isInflow: Bool {
        self == .acquire || self == .recordExisting
    }
}

/// Which half of a correction a row is.
enum InventoryCorrectionLeg: String, Codable, Hashable, Sendable {
    /// The copy leaving the identity it was wrongly recorded as.
    case from
    /// The copy arriving at the identity it really is.
    case to
}

/// One immutable row in the ownership ledger.
///
/// Append-only and never deleted. An undo is an inverse event, not a deletion:
/// a record that can be edited away cannot be trusted six months later, and
/// deletion is also how removals became invisible to history in the first
/// place.
///
/// Synced, because ownership is a fact about the person rather than about a
/// device — unlike `PriceObservation`, which records what one phone happened to
/// learn and when.
@Model
final class InventoryEvent {
    // MARK: - Three identities, not one
    //
    // Collapsing these is what breaks corrections. Deduplicating by operation
    // would silently drop one leg of a two-leg correction and leave the ledger
    // permanently unbalanced; deduplicating by row id would dedupe nothing,
    // since a retry generates a fresh one.

    /// This physical row.
    var eventID: UUID = UUID()
    /// The user or system operation this row belongs to. A correction's two
    /// legs share it, which is also what makes undo a group inversion.
    var operationID: UUID = UUID()
    /// The stable identity of *this leg* across retries — `"operation:leg"`.
    /// Dedupe matches on this and nothing else.
    var idempotencyKey: String = ""
    var legRaw: String?
    /// Set on an inverse event, pointing at what it takes back.
    var reversesEventID: UUID?

    /// When the change happened in the world. Drives quantity as of a cutoff.
    var occurredAt: Date = Date.now
    /// When this device wrote the row. A late CloudKit arrival has an
    /// `occurredAt` before a published close and a `recordedAt` after it, which
    /// is exactly what distinguishes a reconciliation from a new event.
    var recordedAt: Date = Date.now

    var kindRaw: String = ""
    /// Reuses the `CollectionActivitySource` vocabulary rather than inventing a
    /// parallel one.
    var sourceRaw: String = ""
    var collectionKey: String = ""
    /// The `PriceRecord.key` this position is valued through.
    var priceStorageKey: String = ""
    /// Signed. The only place quantity semantics live — there is no separate
    /// "direction" field to disagree with it.
    var deltaQuantity: Int = 0

    // MARK: - Valuation evidence
    //
    // Self-contained on purpose, and deliberately *not* a foreign key into
    // `PriceObservation`: observations do not sync, so that id has no referent
    // on another device. A ledger row has to be able to explain its own value
    // wherever it lands.

    /// `nil` means the copy was added while genuinely unpriced — offline, or
    /// before any provider had a number for it. It flows through as `added $0`,
    /// and the value arrives later as a pricing adjustment. Mechanically
    /// honest, and it must never surface as market movement or a correction.
    var unitPriceUSDTenThousandths: Int64?
    var priceSourceAtEvent: String?
    var priceEffectiveAtEvent: Date?
    /// The knowledge time of the value this event was priced with. Also the
    /// tie-break basis when an event and an observation share a timestamp.
    var priceReceivedAtEvent: Date?
    /// Provenance for debugging only. Meaningless on another device.
    var localObservationID: UUID?

    /// When the copy was *acquired*, which is not when it was recorded.
    var acquiredAt: Date?
    /// No UI in Phase 1. Cheap to add now, a migration to add later.
    var pricePaidUSDTenThousandths: Int64?

    init(
        operationID: UUID,
        leg: InventoryCorrectionLeg?,
        kind: InventoryEventKind,
        source: CollectionActivitySource,
        collectionKey: String,
        priceStorageKey: String,
        deltaQuantity: Int,
        occurredAt: Date,
        recordedAt: Date = .now,
        valuation: InventoryValuation,
        acquiredAt: Date? = nil,
        reversesEventID: UUID? = nil
    ) {
        self.eventID = UUID()
        self.operationID = operationID
        self.idempotencyKey = InventoryEvent.idempotencyKey(operationID: operationID, leg: leg)
        self.legRaw = leg?.rawValue
        self.reversesEventID = reversesEventID
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.collectionKey = collectionKey
        self.priceStorageKey = priceStorageKey
        self.deltaQuantity = deltaQuantity
        self.unitPriceUSDTenThousandths = valuation.unitPrice?.tenThousandths
        self.priceSourceAtEvent = valuation.source?.rawValue
        self.priceEffectiveAtEvent = valuation.effectiveAt
        self.priceReceivedAtEvent = valuation.receivedAt
        self.localObservationID = valuation.observationID
        self.acquiredAt = acquiredAt
    }

    static func idempotencyKey(operationID: UUID, leg: InventoryCorrectionLeg?) -> String {
        "\(operationID.uuidString):\(leg?.rawValue ?? "-")"
    }

    var kind: InventoryEventKind {
        InventoryEventKind(rawValue: kindRaw) ?? .quantityAdjust
    }

    var leg: InventoryCorrectionLeg? {
        legRaw.flatMap(InventoryCorrectionLeg.init(rawValue:))
    }

    var source: CollectionActivitySource {
        CollectionActivitySource(rawValue: sourceRaw) ?? .catalog
    }

    var unitPrice: Money? {
        unitPriceUSDTenThousandths.map(Money.init(tenThousandths:))
    }

    /// The signed value this event moved, or `nil` when the copy was unpriced.
    var signedValue: Money? {
        unitPrice.map { $0 * deltaQuantity }
    }

    /// Everything dedupe compares. Two rows sharing an idempotency key but
    /// disagreeing here is a ledger-integrity defect, never something to
    /// resolve by picking one.
    var payload: InventoryEventPayload {
        InventoryEventPayload(
            kindRaw: kindRaw,
            sourceRaw: sourceRaw,
            collectionKey: collectionKey,
            priceStorageKey: priceStorageKey,
            deltaQuantity: deltaQuantity,
            occurredAt: occurredAt,
            unitPriceUSDTenThousandths: unitPriceUSDTenThousandths,
            reversesEventID: reversesEventID
        )
    }

    func isLogicallyEquivalent(to other: InventoryEvent) -> Bool {
        if kind == .initialBalance, other.kind == .initialBalance {
            // Devices racing the migration deliberately share a deterministic
            // key. Their local knowledge times and stamped prices may differ;
            // ownership identity is the position, instrument, and quantity.
            return collectionKey == other.collectionKey
                && priceStorageKey == other.priceStorageKey
                && deltaQuantity == other.deltaQuantity
        }
        return payload == other.payload
    }
}

/// The comparable content of a ledger row.
struct InventoryEventPayload: Equatable, Sendable {
    var kindRaw: String
    var sourceRaw: String
    var collectionKey: String
    var priceStorageKey: String
    var deltaQuantity: Int
    var occurredAt: Date
    var unitPriceUSDTenThousandths: Int64?
    var reversesEventID: UUID?
}

/// The price evidence an event is stamped with, resolved once at write time.
struct InventoryValuation: Equatable, Sendable {
    var unitPrice: Money?
    var source: PriceSource?
    var effectiveAt: Date?
    var receivedAt: Date?
    var observationID: UUID?

    /// A copy recorded with no price the app is willing to claim.
    static let unpriced = InventoryValuation()
}
