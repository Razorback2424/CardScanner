import Foundation
import SwiftData

/// A stable diagnosis for a ledger that does not add up.
///
/// Deliberately shaped like `PricingDiagnosticReason`: the raw value is
/// support-friendly, so a screenshot and an export describe the same state.
/// None of these are ever repaired silently. A ledger that quietly fixes itself
/// is a ledger whose totals cannot be defended, which is the one thing this
/// whole feature exists to avoid.
enum LedgerIntegrityReason: String, Equatable, Sendable {
    case conflictingPayloadForIdempotencyKey = "conflicting_payload_for_idempotency_key"
    case quantityMismatch = "ledger_quantity_mismatch"
    case orphanedCorrectionLeg = "orphaned_correction_leg"
    case duplicatePositionPricingConflict = "duplicate_position_pricing_conflict"

    var title: String {
        switch self {
        case .conflictingPayloadForIdempotencyKey: return "Conflicting ledger rows"
        case .quantityMismatch: return "Ledger and collection disagree"
        case .orphanedCorrectionLeg: return "Incomplete correction"
        case .duplicatePositionPricingConflict: return "Duplicate rows disagree"
        }
    }

    var detail: String {
        switch self {
        case .conflictingPayloadForIdempotencyKey:
            return "Two ledger rows share one identity but describe different changes. Neither was discarded; the portfolio total may be affected until this is resolved."
        case .quantityMismatch:
            return "The quantity derived from the ledger does not match the collection. The ledger is missing an event, or an event was written that the collection never applied."
        case .orphanedCorrectionLeg:
            return "A correction recorded only one of its two halves. The two legs must be present together or the ledger does not balance."
        case .duplicatePositionPricingConflict:
            return "More than one stored row claims this position, and they are priced through different instruments. Which one is right decides the position's value, so neither was chosen."
        }
    }
}

struct LedgerIntegrityDefect: Identifiable, Equatable, Sendable {
    var id = UUID()
    var reason: LedgerIntegrityReason
    var collectionKey: String
    /// Short, concrete, and safe to put on screen — "ledger 3, collection 2".
    var detail: String
    var detectedAt: Date = .now
}

/// Where integrity defects accumulate for display.
///
/// In memory and bounded: this is an instrument, not a second ledger. If it
/// ever has entries in it, the answer is to find out why, not to make the list
/// bigger.
@MainActor
final class LedgerIntegrityLog: ObservableObject {
    static let shared = LedgerIntegrityLog()

    @Published private(set) var defects: [LedgerIntegrityDefect] = []

    private let limit = 50

    func report(_ defect: LedgerIntegrityDefect) {
        defects.append(defect)
        if defects.count > limit {
            defects.removeFirst(defects.count - limit)
        }
    }

    /// Replaces the defects of one reason, for checks that are recomputed from
    /// scratch on every pass rather than appended to.
    func replace(reason: LedgerIntegrityReason, with new: [LedgerIntegrityDefect]) {
        defects.removeAll { $0.reason == reason }
        defects.append(contentsOf: new)
    }

    /// Replaces everything derived on one full recomputation pass. Derived
    /// checks are recomputed from scratch each time, so accumulating them would
    /// show the same defect once per refresh.
    func replaceAll(with new: [LedgerIntegrityDefect]) {
        defects = Array(new.suffix(limit))
    }

    func clear() { defects.removeAll() }
}

/// Reads and appends the ownership ledger.
///
/// Every mutation of the collection writes its event here, in the same
/// transaction as the mutation itself. That is deliberately not a new
/// synchronous chokepoint — nothing queues, nothing coordinates; each existing
/// write simply also states what it did.
struct InventoryLedger {
    let context: ModelContext

    enum WriteOutcome: Equatable {
        /// A new row.
        case appended(InventoryEvent)
        /// This exact leg was already recorded. A retry, not a second event.
        case duplicate(InventoryEvent)
        /// The same leg identity, describing something different. Surfaced,
        /// never resolved by arbitrarily picking one.
        case conflict(LedgerIntegrityDefect)

        var event: InventoryEvent? {
            switch self {
            case let .appended(event), let .duplicate(event): return event
            case .conflict: return nil
            }
        }
    }

    // MARK: - Reading

    /// What the ledger can currently be read to say, and whether that reading
    /// is safe to publish accounting from.
    ///
    /// Retries of one leg collapse harmlessly — that is what the idempotency
    /// key is for. But two rows sharing a leg identity while describing
    /// *different* changes cannot both be true, and choosing between them by
    /// UUID order decides someone's portfolio history by an implementation
    /// detail. The contract is that a conflict is surfaced and never resolved
    /// arbitrarily, so neither row is counted and the whole reading stops being
    /// authoritative.
    struct LedgerReadResult {
        var events: [InventoryEvent]
        var defects: [LedgerIntegrityDefect]

        /// False when something in the ledger makes derived history untrustworthy.
        /// The current collection value is still real — the cards are still
        /// owned — but no close may be published or revised from this reading.
        var isAuthoritative: Bool { defects.isEmpty }
    }

    /// Convenience for callers that only need the rows and do not publish
    /// accounting from them.
    func allEvents() -> [InventoryEvent] { read().events }

    func allEventsThrowing() throws -> [InventoryEvent] {
        try context.fetch(FetchDescriptor<InventoryEvent>())
    }

    /// Strict event lookup for transactional operations. The presentation
    /// reader intentionally tolerates an unreadable store; undo cannot, since
    /// treating a missing operation as an empty operation would create a
    /// collection change with no ledger inverse.
    func events(forOperationID operationID: UUID) throws -> [InventoryEvent] {
        let descriptor = FetchDescriptor<InventoryEvent>(
            predicate: #Predicate { $0.operationID == operationID }
        )
        return try context.fetch(descriptor)
    }

    /// Whether an event has already been inverted. A fresh inverse operation ID
    /// is deliberately used for every undo, so idempotency alone cannot detect
    /// a stale second tap.
    func reversalEvents(forEventID eventID: UUID) throws -> [InventoryEvent] {
        let descriptor = FetchDescriptor<InventoryEvent>(
            predicate: #Predicate { $0.reversesEventID == eventID }
        )
        return try context.fetch(descriptor)
    }

    func read() -> LedgerReadResult {
        let descriptor = FetchDescriptor<InventoryEvent>(
            sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        var canonical: [InventoryEvent] = []
        var defects: [LedgerIntegrityDefect] = []

        for (_, duplicates) in Dictionary(grouping: rows, by: {
            $0.idempotencyKey.isEmpty ? "legacy:\($0.eventID.uuidString)" : $0.idempotencyKey
        }) {
            let ordered = duplicates.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
            guard let stable = ordered.first else { continue }

            let equivalent = ordered.filter { stable.isLogicallyEquivalent(to: $0) }

            // A genuine conflict. Counting `stable` and reporting the rest
            // would still be picking a story: the total would silently reflect
            // whichever row sorted first. Drop the whole group and say so.
            guard equivalent.count == ordered.count else {
                defects.append(
                    LedgerIntegrityDefect(
                        reason: .conflictingPayloadForIdempotencyKey,
                        collectionKey: stable.collectionKey,
                        detail: "\(stable.idempotencyKey): \(ordered.count) rows share this leg identity and describe different changes; none was counted"
                    )
                )
                continue
            }

            // Equivalent retries collapse. Initial baselines from two offline
            // devices intentionally ignore their device-local timestamp when
            // deciding equivalence, so the canonical row must still take the
            // earliest such time — choosing by row id could otherwise move an
            // already-published close forward by a day after sync.
            let chosen: InventoryEvent
            if stable.kind == .initialBalance {
                chosen = equivalent.min {
                    if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                    return $0.eventID.uuidString < $1.eventID.uuidString
                } ?? stable
            } else {
                chosen = stable
            }
            canonical.append(chosen)
        }

        return LedgerReadResult(
            events: canonical.sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return $0.eventID.uuidString < $1.eventID.uuidString
            },
            defects: defects
        )
    }

    func events(collectionKey: String) -> [InventoryEvent] {
        allEvents().filter { $0.collectionKey == collectionKey }
    }

    func event(idempotencyKey: String) -> InventoryEvent? {
        var descriptor = FetchDescriptor<InventoryEvent>(
            predicate: #Predicate { $0.idempotencyKey == idempotencyKey }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func hasAnyEvent() -> Bool {
        var descriptor = FetchDescriptor<InventoryEvent>()
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor).first) != nil)
    }

    /// Quantity per position derived purely from the ledger.
    nonisolated static func quantities(from events: [InventoryEvent]) -> [String: Int] {
        var quantities: [String: Int] = [:]
        for event in events {
            quantities[event.collectionKey, default: 0] += event.deltaQuantity
        }
        return quantities.filter { $0.value != 0 }
    }

    // MARK: - Valuation

    /// The price key this position is valued through, preferring a legacy key
    /// that actually holds a value — the same preference `PriceStore` applies,
    /// so the ledger and the grid never disagree about which number is being
    /// used.
    func priceStorageKey(for card: CollectedCard) -> String {
        let keys = card.priceLookupKeys
        for key in keys where usableValue(forPriceKey: key) != nil {
            return key
        }
        return keys.first ?? card.priceKey
    }

    /// The price evidence in force right now for one instrument.
    ///
    /// Prefers the observation log, because its `receivedAt` is the exact
    /// knowledge time the portfolio walk orders on. Falls back to the
    /// `PriceRecord` for positions priced before the log existed.
    func valuation(forPriceKey key: String) -> InventoryValuation {
        if let observation = PriceObservationLog(context: context)
            .newestObservation(instrumentKey: key) {
            // An invalidation is authoritative. Falling through to the mutable
            // PriceRecord would resurrect exactly the price the log withdrew.
            if observation.kind == .explicitInvalidation { return .unpriced }
            if let amount = observation.amount,
               observation.currencyCode == "USD" {
            return InventoryValuation(
                unitPrice: amount,
                source: observation.source,
                effectiveAt: observation.effectiveAt,
                receivedAt: observation.receivedAt,
                observationID: observation.id
            )
            }
        }

        guard let record = PriceStore(context: context).record(forKey: key),
              let amount = record.unitMarketPriceUSD,
              record.currencyCode == "USD" else {
            // Non-USD is unpriced *for portfolio purposes* on purpose: there is
            // no live exchange rate here, and the collection total already
            // excludes those copies and says so.
            return .unpriced
        }

        guard let money = Money(rounding: amount) else { return .unpriced }
        return InventoryValuation(
            unitPrice: money,
            source: record.source,
            effectiveAt: record.sourceUpdatedAt ?? record.fetchedAt,
            receivedAt: record.fetchedAt,
            observationID: nil
        )
    }

    private func usableValue(forPriceKey key: String) -> Money? {
        valuation(forPriceKey: key).unitPrice
    }

    // MARK: - Writing

    /// Appends one leg.
    ///
    /// Idempotent per leg, not per operation: retrying a correction must
    /// re-create whichever of its two halves is missing without dropping the
    /// other.
    @discardableResult
    func record(
        _ card: CollectedCard,
        kind: InventoryEventKind,
        source: CollectionActivitySource,
        deltaQuantity: Int,
        operationID: UUID = UUID(),
        leg: InventoryCorrectionLeg? = nil,
        occurredAt: Date = .now,
        acquiredAt: Date? = nil,
        reversesEventID: UUID? = nil
    ) -> WriteOutcome {
        let key = priceStorageKey(for: card)
        return record(
            collectionKey: card.collectionKey,
            priceStorageKey: key,
            valuation: valuation(forPriceKey: key),
            kind: kind,
            source: source,
            deltaQuantity: deltaQuantity,
            operationID: operationID,
            leg: leg,
            occurredAt: occurredAt,
            acquiredAt: acquiredAt,
            reversesEventID: reversesEventID
        )
    }

    /// The form used where the position no longer has a `CollectedCard` — a row
    /// that was just deleted, or one being corrected away from.
    @discardableResult
    func record(
        collectionKey: String,
        priceStorageKey: String,
        valuation: InventoryValuation,
        kind: InventoryEventKind,
        source: CollectionActivitySource,
        deltaQuantity: Int,
        operationID: UUID = UUID(),
        leg: InventoryCorrectionLeg? = nil,
        occurredAt: Date = .now,
        acquiredAt: Date? = nil,
        reversesEventID: UUID? = nil
    ) -> WriteOutcome {
        let idempotencyKey = InventoryEvent.idempotencyKey(operationID: operationID, leg: leg)
        let candidate = InventoryEventPayload(
            kindRaw: kind.rawValue,
            sourceRaw: source.rawValue,
            collectionKey: collectionKey,
            priceStorageKey: priceStorageKey,
            deltaQuantity: deltaQuantity,
            occurredAt: occurredAt,
            unitPriceUSDTenThousandths: valuation.unitPrice?.tenThousandths,
            reversesEventID: reversesEventID
        )

        if let existing = event(idempotencyKey: idempotencyKey) {
            let equivalent = kind == .initialBalance && existing.kind == .initialBalance
                ? existing.collectionKey == collectionKey
                    && existing.priceStorageKey == priceStorageKey
                    && existing.deltaQuantity == deltaQuantity
                : existing.payload == candidate
            guard equivalent else {
                let defect = LedgerIntegrityDefect(
                    reason: .conflictingPayloadForIdempotencyKey,
                    collectionKey: collectionKey,
                    detail: "\(idempotencyKey): recorded \(existing.deltaQuantity) of \(existing.collectionKey), attempted \(deltaQuantity) of \(collectionKey)"
                )
                // Returned rather than published from here: the write path is
                // no longer main-actor isolated, and the next recomputation's
                // ledger read finds the same conflict anyway.
                return .conflict(defect)
            }
            return .duplicate(existing)
        }

        let event = InventoryEvent(
            operationID: operationID,
            leg: leg,
            kind: kind,
            source: source,
            collectionKey: collectionKey,
            priceStorageKey: priceStorageKey,
            deltaQuantity: deltaQuantity,
            occurredAt: occurredAt,
            valuation: valuation,
            acquiredAt: acquiredAt,
            reversesEventID: reversesEventID
        )
        context.insert(event)
        return .appended(event)
    }

    /// Both halves of a correction, sharing one `operationID` and written
    /// together. A correction is a copy moving between identities, so later
    /// price movement follows the new identity automatically.
    @discardableResult
    func recordCorrection(
        fromCollectionKey: String,
        fromPriceStorageKey: String,
        toCard: CollectedCard,
        source: CollectionActivitySource = .correction,
        quantity: Int = 1,
        occurredAt: Date = .now,
        operationID: UUID = UUID()
    ) -> (from: WriteOutcome, to: WriteOutcome) {
        let toKey = priceStorageKey(for: toCard)
        let from = record(
            collectionKey: fromCollectionKey,
            priceStorageKey: fromPriceStorageKey,
            valuation: valuation(forPriceKey: fromPriceStorageKey),
            kind: .correction,
            source: source,
            deltaQuantity: -quantity,
            operationID: operationID,
            leg: .from,
            occurredAt: occurredAt
        )
        let to = record(
            collectionKey: toCard.collectionKey,
            priceStorageKey: toKey,
            valuation: valuation(forPriceKey: toKey),
            kind: .correction,
            source: source,
            deltaQuantity: quantity,
            operationID: operationID,
            leg: .to,
            occurredAt: occurredAt
        )
        return (from, to)
    }

    /// Takes an event back by writing its inverse.
    ///
    /// Same kind, negated quantity — so undoing an acquisition retracts it from
    /// "Added" rather than reporting it as a sale. Valued at the price in force
    /// *now*, like every other flow: valuing it at the original price would
    /// leave behind exactly the market movement that accrued while the copy was
    /// held, as an unexplained residual.
    @discardableResult
    func reverse(
        _ event: InventoryEvent,
        source: CollectionActivitySource? = nil,
        occurredAt: Date = .now,
        operationID: UUID = UUID()
    ) -> WriteOutcome {
        record(
            collectionKey: event.collectionKey,
            priceStorageKey: event.priceStorageKey,
            valuation: valuation(forPriceKey: event.priceStorageKey),
            kind: event.kind,
            source: source ?? event.source,
            deltaQuantity: -event.deltaQuantity,
            operationID: operationID,
            leg: event.leg,
            occurredAt: occurredAt,
            reversesEventID: event.eventID
        )
    }

    /// Inverts every leg of an operation together, so a correction can never be
    /// half-undone.
    @discardableResult
    func reverseOperation(_ operationID: UUID, at date: Date = .now) -> [WriteOutcome] {
        let descriptor = FetchDescriptor<InventoryEvent>(
            predicate: #Predicate { $0.operationID == operationID }
        )
        let legs = (try? context.fetch(descriptor)) ?? []
        let inverseOperation = UUID()
        return legs.map { reverse($0, occurredAt: date, operationID: inverseOperation) }
    }
}
