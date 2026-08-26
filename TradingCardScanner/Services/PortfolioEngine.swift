import Foundation
import CryptoKit
import SwiftData

/// How much of what is held was actually repriced today.
///
/// Reported, never assumed. "1,276 of 1,284 repriced today · 8 carried forward"
/// is a claim the app can defend from persisted evidence; "prices updated" is
/// not.
struct PortfolioCoverage: Equatable, Sendable {
    var refreshed: Int = 0
    var carriedForward: Int = 0
    var state: PortfolioCoverageState = .unknown

    var total: Int { refreshed + carriedForward }
}

/// Everything the Today card needs, derived once.
struct PortfolioSummary: Equatable, Sendable {
    var currentValue: Money = .zero
    /// Absent on the first day of tracking, which genuinely has no yesterday.
    var attribution: PortfolioClose.Attribution?
    /// The day whose close `attribution` is measured from.
    var closeDate: Date?
    var coverage = PortfolioCoverage()
    /// Copies held but excluded from the total, with their existing separate
    /// meanings kept apart.
    var unpricedCount: Int = 0
    var otherCurrencyCount: Int = 0
    var isMigrationDay: Bool = false
    /// Set when the close being shown was revised — "reconciled after another
    /// device synced".
    var revisionNote: String?
    /// Ledger-versus-collection disagreements found on this pass. The most
    /// valuable instrument in the whole feature: it is what proves the ledger
    /// is complete.
    var defects: [LedgerIntegrityDefect] = []
}

/// Owns portfolio computation.
///
/// A status enum as the presentation contract, matching
/// `PriceRefreshController`. Recomputation is triggered by collection changes,
/// refresh completion and day rollover — never from `body`. The collection
/// snapshot is already O(n) per render, and a close recomputed on every layout
/// pass would be both slow and, worse, a number that moves while being read.
@MainActor
final class PortfolioEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case computing
        case ready(PortfolioSummary)
    }

    @Published private(set) var status: Status = .idle

    private var lastComputedDay: Date?

    var summary: PortfolioSummary? {
        if case let .ready(summary) = status { return summary }
        return nil
    }

    /// Opens the books if they are not open, seeds the observation log from
    /// whatever prices already exist, and computes today.
    func start(context: ModelContext, now: Date = .now) {
        do {
            try PortfolioEpoch.establishIfNeeded(context: context, at: now)
        } catch {
            // A failed baseline save must not transition the UI into the
            // migration-day "tracking started" state. Recompute can still
            // show the current collection value; a later start retries the
            // durable epoch transaction.
            recompute(context: context, now: now)
            return
        }
        PriceObservationLog(context: context).backfillFromRecords(receivedAt: now)
        recompute(context: context, now: now)
    }

    /// Whether the portfolio day has rolled over since the last computation.
    /// Cheap enough to ask on every foreground.
    func needsRecomputeForNewDay(now: Date = .now) -> Bool {
        guard let lastComputedDay else { return true }
        let timeZone = PortfolioCalendar.timeZone()
        return PortfolioCalendar.day(containing: now, in: timeZone) != lastComputedDay
    }

    func recompute(context: ModelContext, now: Date = .now) {
        status = .computing

        let timeZone = PortfolioCalendar.timeZone()
        let today = PortfolioCalendar.day(containing: now, in: timeZone)
        lastComputedDay = today

        let ledger = InventoryLedger(context: context)
        let events = ledger.allEvents().map(Self.entry(from:))
        let observations = Self.observations(in: context)

        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        let valuation = Self.currentValuation(cards: cards, ledger: ledger)

        var summary = PortfolioSummary(
            currentValue: valuation.value,
            unpricedCount: valuation.unpricedCount,
            otherCurrencyCount: valuation.otherCurrencyCount
        )
        summary.defects = Self.reconcile(cards: cards, events: events)

        guard let epoch = PortfolioEpoch.startedAt(context: context) else {
            status = .ready(summary)
            return
        }

        summary.isMigrationDay = PortfolioEpoch.isMigrationDay(now, epoch: epoch, timeZone: timeZone)
        summary.coverage = Self.coverage(
            instruments: Set(valuation.instrumentsHeld),
            day: today,
            context: context,
            // Coverage is unknown only for days that predate the ledger. Today
            // always has evidence, even when that evidence says nothing was
            // checked.
            isKnown: true
        )

        // Migration day has no yesterday, so there is nothing to attribute
        // against and nothing is invented. The first legitimate close forms at
        // the first midnight boundary.
        if !summary.isMigrationDay {
            let closedDay = PortfolioCalendar.day(
                containing: today.addingTimeInterval(-1),
                in: timeZone
            )
            let boundary = today
            summary.closeDate = closedDay

            let stored = Self.publish(
                closesUpTo: closedDay,
                epoch: epoch,
                events: events,
                observations: observations,
                timeZone: timeZone,
                context: context
            )
            summary.revisionNote = stored?.revisionNote

            summary.attribution = PortfolioClose.attribute(
                events: events,
                observations: observations,
                boundary: boundary,
                now: now,
                currentValue: valuation.value
            )
        }

        status = .ready(summary)
    }

    // MARK: - Current value, measured independently of the walk

    struct CurrentValuation {
        var value: Money = .zero
        var unpricedCount: Int = 0
        var otherCurrencyCount: Int = 0
        var instrumentsHeld: [String] = []
    }

    /// The collection's value right now, taken from the collection itself.
    ///
    /// Deliberately not the walk's ending state: the residual only means
    /// something if the two sides are measured independently.
    static func currentValuation(cards: [CollectedCard], ledger: InventoryLedger) -> CurrentValuation {
        var valuation = CurrentValuation()
        var instruments: Set<String> = []

        // Duplicate collection keys are summed, for the same reason the grid
        // sums them: dropping one silently understates the total.
        let quantities = cards.reduce(into: [String: Int]()) { totals, card in
            totals[card.collectionKey, default: 0] += card.quantity
        }
        var representatives: [String: CollectedCard] = [:]
        for card in cards where representatives[card.collectionKey] == nil {
            representatives[card.collectionKey] = card
        }

        for (key, quantity) in quantities {
            guard quantity != 0, let card = representatives[key] else { continue }
            let instrumentKey = ledger.priceStorageKey(for: card)
            instruments.insert(instrumentKey)

            guard let price = ledger.valuation(forPriceKey: instrumentKey).unitPrice else {
                // Two different absences, kept apart because they mean
                // different things to the person reading the total.
                let record = PriceStore(context: ledger.context).record(forKey: instrumentKey)
                if record?.unitMarketPriceUSD != nil, record?.currencyCode != "USD" {
                    valuation.otherCurrencyCount += quantity
                } else {
                    valuation.unpricedCount += quantity
                }
                continue
            }
            valuation.value += price * quantity
        }

        valuation.instrumentsHeld = Array(instruments)
        return valuation
    }

    // MARK: - Coverage

    static func coverage(
        instruments: Set<String>,
        day: Date,
        context: ModelContext,
        isKnown: Bool
    ) -> PortfolioCoverage {
        guard !instruments.isEmpty else {
            return PortfolioCoverage(state: isKnown ? .complete : .unknown)
        }

        let log = PriceObservationLog(context: context)
        var refreshed = 0
        for instrument in instruments where log.checkDay(instrumentKey: instrument, day: day) != nil {
            refreshed += 1
        }
        let carriedForward = instruments.count - refreshed

        return PortfolioCoverage(
            refreshed: refreshed,
            carriedForward: carriedForward,
            state: !isKnown ? .unknown : (carriedForward == 0 ? .complete : .partial)
        )
    }

    // MARK: - The ledger/projection assertion

    /// Compares quantities derived from the ledger against the collection.
    ///
    /// A mismatch is a reconciliation defect, surfaced and never silently
    /// repaired. Repairing it would hide the only evidence that a mutation
    /// somewhere is not writing its event — which is the failure mode this
    /// whole phase is built to catch.
    static func reconcile(cards: [CollectedCard], events: [LedgerEntry]) -> [LedgerIntegrityDefect] {
        var ledgerQuantities: [String: Int] = [:]
        for event in events {
            ledgerQuantities[event.collectionKey, default: 0] += event.deltaQuantity
        }
        var collectionQuantities: [String: Int] = [:]
        for card in cards {
            collectionQuantities[card.collectionKey, default: 0] += card.quantity
        }

        var defects: [LedgerIntegrityDefect] = []
        for key in Set(ledgerQuantities.keys).union(collectionQuantities.keys) {
            let fromLedger = ledgerQuantities[key] ?? 0
            let fromCollection = collectionQuantities[key] ?? 0
            guard fromLedger != fromCollection else { continue }
            defects.append(
                LedgerIntegrityDefect(
                    reason: .quantityMismatch,
                    collectionKey: key,
                    detail: "ledger \(fromLedger), collection \(fromCollection)"
                )
            )
        }

        LedgerIntegrityLog.shared.replace(reason: .quantityMismatch, with: defects)
        return defects.sorted { $0.collectionKey < $1.collectionKey }
    }

    // MARK: - Publishing closes

    /// Materializes every close from the local knowledge epoch through `day`,
    /// revising a published day only when its deterministic inputs changed.
    @discardableResult
    static func publish(
        closesUpTo day: Date,
        epoch: Date,
        events: [LedgerEntry],
        observations: [ObservationEntry],
        timeZone: TimeZone,
        context: ModelContext
    ) -> PortfolioDailyClose? {
        let epochDay = PortfolioCalendar.day(containing: epoch, in: timeZone)
        guard day >= epochDay else { return nil }

        var cursor = epochDay
        var requestedClose: PortfolioDailyClose?
        var insertedAny = false

        while cursor <= day {
            if let close = makeClose(
                for: cursor,
                events: events,
                observations: observations,
                timeZone: timeZone,
                context: context
            ) {
                requestedClose = close
                insertedAny = true
            } else if cursor == day {
                requestedClose = latestClose(for: cursor, in: context)
            }
            cursor = PortfolioCalendar.boundary(afterDay: cursor, in: timeZone)
        }

        if insertedAny { try? context.save() }
        return requestedClose
    }

    /// Returns a newly inserted revision, or nil when the existing close is
    /// already current.
    private static func makeClose(
        for day: Date,
        events: [LedgerEntry],
        observations: [ObservationEntry],
        timeZone: TimeZone,
        context: ModelContext
    ) -> PortfolioDailyClose? {

        let boundary = PortfolioCalendar.boundary(afterDay: day, in: timeZone)
        let state = PortfolioClose.state(
            events: events,
            observations: observations,
            asOf: boundary
        )
        let fingerprint = self.fingerprint(
            events: events.filter { $0.occurredAt < boundary },
            observations: observations.filter { $0.receivedAt < boundary }
        )

        let existing = latestClose(for: day, in: context)
        if let existing, existing.inputsFingerprint == fingerprint {
            return nil
        }

        // A close only ever changes because ownership was incomplete. Market
        // information arriving late cannot reach this computation at all: the
        // close reads observations by `receivedAt`, and a vendor backdating a
        // price is received now, not then. That is contract 7 holding by
        // construction rather than by a rule someone has to remember.
        // With knowledge-time-safe observations, the only new pre-boundary
        // input that can alter an existing close is a newly visible ownership
        // event. Its originating `recordedAt` is irrelevant to when CloudKit
        // delivered it here; the changed input set is the evidence.
        let reason: PortfolioRevisionReason? = existing == nil ? nil : .lateInventoryTruth

        let instruments = state.heldInstrumentKeys
        let coverage = coverage(
            instruments: instruments,
            day: day,
            context: context,
            isKnown: true
        )
        let checked = Set(instruments.filter {
            PriceObservationLog(context: context).checkDay(instrumentKey: $0, day: day) != nil
        })
        let carriedForwardValue = state.quantities.reduce(Money.zero) { total, entry in
            guard entry.value != 0,
                  let instrument = state.instruments[entry.key],
                  !checked.contains(instrument),
                  let price = state.prices[instrument] else { return total }
            return total + price * entry.value
        }

        let attribution = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: PortfolioCalendar.day(containing: day, in: timeZone),
            now: boundary,
            currentValue: state.value
        )

        let close = PortfolioDailyClose(
            date: day,
            revision: (existing?.revision ?? 0) + 1,
            timeZoneIdentifier: timeZone.identifier,
            closeValue: state.value,
            market: attribution.market,
            flow: attribution.added - attribution.removed,
            corrections: attribution.corrections,
            pricingAdjustment: attribution.pricingAdjustment,
            carriedForwardValue: carriedForwardValue,
            coverage: coverage.state,
            refreshedInstrumentCount: coverage.refreshed,
            carriedForwardInstrumentCount: coverage.carriedForward,
            pricedPositionCount: state.pricedPositionCount,
            excludedCount: state.excludedQuantity,
            inputsFingerprint: fingerprint,
            revisionReason: reason
        )
        context.insert(close)
        return close
    }

    static func latestClose(for day: Date, in context: ModelContext) -> PortfolioDailyClose? {
        var descriptor = FetchDescriptor<PortfolioDailyClose>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.revision, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func allCloses(in context: ModelContext) -> [PortfolioDailyClose] {
        let descriptor = FetchDescriptor<PortfolioDailyClose>(
            sortBy: [SortDescriptor(\.date, order: .forward), SortDescriptor(\.revision, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: -

    /// A stable digest of everything a close was derived from. Changing it is
    /// the only thing that justifies a revision; leaving it alone is what makes
    /// recomputing an already-published day free.
    static func fingerprint(events: [LedgerEntry], observations: [ObservationEntry]) -> String {
        var hasher = SHA256()
        for event in events.sorted(by: { $0.eventID.uuidString < $1.eventID.uuidString }) {
            hasher.update(data: Data("\(event.eventID.uuidString):\(event.operationID.uuidString):\(event.kind.rawValue):\(event.deltaQuantity):\(event.collectionKey):\(event.priceStorageKey):\(event.reversesEventID?.uuidString ?? "-")".utf8))
        }
        for observation in observations.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.update(data: Data("\(observation.id.uuidString):\(observation.instrumentKey):\(observation.kind.rawValue):\(observation.amount?.tenThousandths.description ?? "nil")".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func entry(from event: InventoryEvent) -> LedgerEntry {
        LedgerEntry(
            eventID: event.eventID,
            operationID: event.operationID,
            leg: event.leg,
            kind: event.kind,
            occurredAt: event.occurredAt,
            recordedAt: event.recordedAt,
            reversesEventID: event.reversesEventID,
            collectionKey: event.collectionKey,
            priceStorageKey: event.priceStorageKey,
            deltaQuantity: event.deltaQuantity,
            unitPrice: event.unitPrice,
            priceReceivedAtEvent: event.priceReceivedAtEvent
        )
    }

    static func observations(in context: ModelContext) -> [ObservationEntry] {
        let descriptor = FetchDescriptor<PriceObservation>(
            sortBy: [SortDescriptor(\.receivedAt, order: .forward)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { row in
            ObservationEntry(
                id: row.id,
                instrumentKey: row.instrumentKey,
                kind: row.kind,
                // Non-USD is normalised away here rather than deep in the walk,
                // so exactly one place in the app decides what "not in the
                // total" means.
                amount: row.currencyCode == "USD" ? row.amount : nil,
                receivedAt: row.receivedAt
            )
        }
    }
}
