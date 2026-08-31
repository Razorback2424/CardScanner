import Foundation
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
    /// Whether derived history can be trusted right now.
    ///
    /// When false the collection's current value is still shown — the cards are
    /// still owned — but attribution and history are paused and no close is
    /// published or revised. A system that knows its ledger is incomplete must
    /// not simultaneously publish a supposedly trustworthy close; doing so is
    /// what turns an integrity diagnostic into an ornament.
    var isAuthoritative = true
}

/// Current, authoritative presentation metadata for a logical owned position.
/// Historical contribution keys that do not resolve here are deliberately not
/// named by inference in the UI.
struct PortfolioHoldingSnapshot: Identifiable, Equatable, Sendable {
    var collectionKey: String
    var name: String
    var detail: String
    var artworkURL: URL?
    var quantity: Int
    var currentValue: Money?

    var id: String { collectionKey }
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
    /// Monotonic signal for consumers whose derived inputs may change without
    /// changing the visible summary values (for example, a close revision or
    /// two offsetting market updates).
    @Published private(set) var inputRevision: UInt = 0
    /// Time-weighted factors from the same replay that produced the summary, so
    /// the history card never runs a second pass.
    @Published private(set) var performanceFactors = PortfolioPerformanceFactors()
    /// One sparse value snapshot published per completed replay, never a
    /// nested observable that changes while SwiftUI is rendering it.
    @Published private(set) var contributionIndex = PortfolioContributionIndex()
    @Published private(set) var holdings: [PortfolioHoldingSnapshot] = []
    /// Integrity defects from the latest computation, including defects found
    /// before a usable summary can be produced. This stays separate from the
    /// summary so a first-launch unreadable store does not become a fabricated
    /// zero-valued portfolio.
    @Published private(set) var integrityDefects: [LedgerIntegrityDefect] = []

    /// Kept separately from `status` because recomputation moves status through
    /// `.computing` before its result arrives. A failed read can therefore
    /// retain the last usable summary without making `summary` appear ready
    /// while work is still in flight.
    private var lastUsableSummary: PortfolioSummary?
    private var lastComputedDay: Date?
    /// Guards against a slower earlier pass publishing over a fresher one.
    private var computationSequence: UInt = 0
    private var computationTask: Task<Void, Never>?

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

    /// Starts a recomputation. Returns immediately; the result is published
    /// when the background computation finishes.
    ///
    /// Everything expensive — fetching and flattening the ledger, the
    /// observation log and the check-day rows, then replaying them — happens on
    /// `PortfolioComputationActor`. Only the small act of building the summary
    /// and writing at most a few hundred close rows happens here.
    func recompute(context: ModelContext, now: Date = .now) {
        status = .computing

        let timeZone = PortfolioCalendar.timeZone()

        computationSequence &+= 1
        let sequence = computationSequence
        let container = context.container
        let epoch = PortfolioEpoch.startedAt() ?? now

        computationTask?.cancel()
        computationTask = Task { [weak self] in
            let actor = PortfolioComputationActor(modelContainer: container)
            let computation = await actor.compute(
                epoch: epoch,
                through: now,
                timeZoneIdentifier: timeZone.identifier
            )
            guard !Task.isCancelled else { return }
            self?.apply(
                computation,
                sequence: sequence,
                now: now,
                timeZone: timeZone,
                context: context
            )
        }
    }

    /// Recomputes and waits. Tests and any caller that needs the result before
    /// continuing use this; the app uses `recompute`.
    func recomputeAndWait(context: ModelContext, now: Date = .now) async {
        recompute(context: context, now: now)
        await computationTask?.value
    }

    private func apply(
        _ computation: PortfolioReplaySnapshotBuilder.Computation,
        sequence: UInt,
        now: Date,
        timeZone: TimeZone,
        context: ModelContext
    ) {
        // A slower earlier pass must never overwrite a fresher one.
        guard sequence == computationSequence else { return }

        // A failed read must never replace a known-good summary with a
        // fabricated zero. Keep the last usable values visible, mark them
        // non-authoritative, and leave the day eligible for a later retry.
        if computation.defects.contains(where: { $0.reason == .unreadableStore }) {
            integrityDefects = computation.defects
            LedgerIntegrityLog.shared.replaceAll(with: integrityDefects)

            if var retained = lastUsableSummary {
                retained.defects = computation.defects
                retained.isAuthoritative = false
                status = .ready(retained)
            } else {
                // There is no trustworthy value to retain on first launch.
                // Keep summary nil so the UI can honestly render “Value
                // unavailable” while still surfacing the read failure.
                status = .idle
            }
            return
        }

        lastComputedDay = PortfolioCalendar.day(containing: now, in: timeZone)

        // Bumped here rather than when the work starts. Consumers key their
        // recomputation off this, and a revision published before the result
        // exists means they run once against a nil summary and never run again.
        inputRevision &+= 1

        let today = PortfolioCalendar.day(containing: now, in: timeZone)
        let valuation = computation.valuation

        var summary = PortfolioSummary(
            currentValue: valuation.value,
            unpricedCount: valuation.unpricedCount,
            otherCurrencyCount: valuation.otherCurrencyCount
        )
        summary.defects = computation.defects
        summary.isAuthoritative = summary.defects.isEmpty
        integrityDefects = summary.defects
        lastUsableSummary = summary
        LedgerIntegrityLog.shared.replaceAll(with: summary.defects)

#if DEBUG
        if !summary.defects.isEmpty {
            print("🚨 PORTFOLIO RECONCILIATION FAILED")
            print("Defect count: \(summary.defects.count)")

            for defect in summary.defects {
                print("""
                ---
                Reason: \(defect.reason.rawValue)
                Collection key: \(defect.collectionKey)
                Detail: \(defect.detail)
                """)
            }
        }
#endif

        guard let epoch = PortfolioEpoch.startedAt() else {
            status = .ready(summary)
            return
        }

        summary.isMigrationDay = PortfolioEpoch.isMigrationDay(now, epoch: epoch, timeZone: timeZone)

        let replay = computation.replay
        contributionIndex = replay.contributionIndex
        holdings = computation.holdings
        performanceFactors = PortfolioPerformanceFactors(
            daily: Dictionary(
                replay.days.compactMap { day in
                    day.performanceFactor.map { (day.displayDay, $0) }
                },
                uniquingKeysWith: { _, latest in latest }
            ),
            live: replay.live?.performanceFactor
        )
        summary.coverage = replay.live?.coverageToday(
            index: computation.coverage,
            heldInstruments: Set(valuation.instrumentsHeld),
            day: today
        ) ?? PortfolioCoverage(state: .complete)

        // Migration day has no yesterday, so there is nothing to attribute
        // against and nothing is invented. The first legitimate close forms at
        // the first midnight boundary.
        //
        // A non-authoritative ledger is treated the same way for publication:
        // the value above is still shown, but nothing is written down as
        // history until the conflict is resolved.
        if !summary.isMigrationDay, summary.isAuthoritative {
            summary.closeDate = PortfolioCalendar.day(
                containing: today.addingTimeInterval(-1),
                in: timeZone
            )
            summary.revisionNote = Self.publish(replay.days, timeZone: timeZone, context: context)?
                .revisionNote

            if var attribution = replay.live?.attribution {
                // Current value is still measured independently, from the
                // collection itself. Feeding the replay's own ending value back
                // in would make the residual vacuous.
                attribution.currentValue = valuation.value
                summary.attribution = attribution
            }
        }

        status = .ready(summary)
    }

    // MARK: - Current value, measured independently of the walk

    struct CurrentValuation: Sendable {
        var value: Money = .zero
        var unpricedCount: Int = 0
        var otherCurrencyCount: Int = 0
        var instrumentsHeld: [String] = []
    }

    /// The collection's value right now, taken from the collection itself.
    ///
    /// Deliberately not the replay's ending state: the residual only means
    /// something if the two sides are measured independently. Prices come from
    /// the bulk index — one fetch per position would be one fetch per position
    /// against the whole observation log.
    nonisolated static func currentValuation(
        projection: LogicalCollectionProjection,
        valuations: InstrumentValuationIndex,
        otherCurrencyInstruments: Set<String>
    ) -> CurrentValuation {
        var valuation = CurrentValuation()
        var instruments: Set<String> = []

        for position in projection.positions {
            let quantity = position.quantity
            guard quantity != 0 else { continue }
            let instrumentKey = position.priceStorageKey
            instruments.insert(instrumentKey)

            guard let price = valuations.valuation(for: instrumentKey).unitPrice else {
                // Two different absences, kept apart because they mean
                // different things to the person reading the total.
                if otherCurrencyInstruments.contains(instrumentKey) {
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

    // MARK: - The ledger/projection assertion

    /// Compares quantities derived from the ledger against the collection.
    ///
    /// A mismatch is a reconciliation defect, surfaced and never silently
    /// repaired. Repairing it would hide the only evidence that a mutation
    /// somewhere is not writing its event — which is the failure mode this
    /// whole phase is built to catch.
    nonisolated static func reconcile(
        projection: LogicalCollectionProjection,
        events: [LedgerEntry]
    ) -> [LedgerIntegrityDefect] {
        var ledgerQuantities: [String: Int] = [:]
        for event in events {
            ledgerQuantities[event.collectionKey, default: 0] += event.deltaQuantity
        }
        let collectionQuantities = projection.quantities

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

        return defects.sorted { $0.collectionKey < $1.collectionKey }
    }

    // MARK: - Publishing closes

    /// Writes or revises closes from replay output, and returns the most recent
    /// one so the card can explain a revision.
    ///
    /// Revision is decided by comparing the derived payload against what is
    /// stored, not by an input fingerprint alone: changing how the replay is
    /// computed should not manufacture a revision on every historical day.
    @discardableResult
    static func publish(
        _ days: [PortfolioReplayDay],
        timeZone: TimeZone,
        context: ModelContext
    ) -> PortfolioDailyClose? {
        guard !days.isEmpty else { return nil }

        // One fetch for every stored close, grouped once. The publisher used to
        // query per day inside a loop over the whole history. A failed read is
        // not an empty history: returning nil keeps the caller from publishing
        // revision numbers derived from an incomplete view of the store.
        let storedCloses: [PortfolioDailyClose]
        do {
            storedCloses = try allCloses(in: context)
        } catch {
            return nil
        }
        let stored = Dictionary(grouping: storedCloses, by: \.date)
            .compactMapValues { $0.max { $0.revision < $1.revision } }

        var latest: PortfolioDailyClose?
        var insertedCloses: [PortfolioDailyClose] = []

        for day in days {
            let existing = stored[day.displayDay]
            if let existing, matches(existing, day) {
                latest = existing
                continue
            }

            let close = PortfolioDailyClose(
                date: day.displayDay,
                revision: (existing?.revision ?? 0) + 1,
                timeZoneIdentifier: timeZone.identifier,
                closeValue: day.closeValue,
                market: day.market,
                flow: day.flow,
                corrections: day.corrections,
                newlyAddedValue: day.newlyAddedValue,
                pricingAdjustment: day.pricingAdjustment,
                carriedForwardValue: day.carriedForwardValue,
                coverage: day.coverage.state,
                refreshedInstrumentCount: day.coverage.refreshed,
                carriedForwardInstrumentCount: day.coverage.carriedForward,
                pricedPositionCount: day.pricedPositionCount,
                excludedCount: day.excludedQuantity,
                inputsFingerprint: "",
                // A published close can only change because ownership was
                // incomplete: observations are read by knowledge time, so a
                // vendor backdating a price cannot reach a day that has already
                // closed. The wording stays at what the evidence supports.
                revisionReason: existing == nil ? nil : .recomputed
            )
            context.insert(close)
            insertedCloses.append(close)
            latest = close
        }

        if !insertedCloses.isEmpty {
            do {
                try context.save()
            } catch {
                // Delete only the objects this publisher inserted. A rollback
                // could discard unrelated work the caller staged in the same
                // context.
                for close in insertedCloses {
                    context.delete(close)
                }
                return nil
            }
        }
        return latest
    }

    /// Whether a stored close already says exactly what the replay derived.
    private static func matches(_ stored: PortfolioDailyClose, _ day: PortfolioReplayDay) -> Bool {
        stored.closeValue == day.closeValue
            && stored.marketContribution == day.market
            && stored.flowContribution == day.flow
            && stored.correctionContribution == day.corrections
            && stored.newlyAddedValue == day.newlyAddedValue
            && stored.pricingAdjustment == day.pricingAdjustment
            && stored.carriedForwardValue == day.carriedForwardValue
            && stored.coverageState == day.coverage.state
            && stored.refreshedInstrumentCount == day.coverage.refreshed
            && stored.carriedForwardInstrumentCount == day.coverage.carriedForward
            && stored.pricedPositionCount == day.pricedPositionCount
            && stored.excludedCount == day.excludedQuantity
    }

    static func allCloses(in context: ModelContext) throws -> [PortfolioDailyClose] {
        let descriptor = FetchDescriptor<PortfolioDailyClose>(
            sortBy: [SortDescriptor(\.date, order: .forward), SortDescriptor(\.revision, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    nonisolated static func entry(from event: InventoryEvent) -> LedgerEntry {
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

    static func observations(in context: ModelContext) throws -> [ObservationEntry] {
        let descriptor = FetchDescriptor<PriceObservation>(
            sortBy: [SortDescriptor(\.receivedAt, order: .forward)]
        )
        return try context.fetch(descriptor).map(observationEntry(from:))
    }

    nonisolated static func observationEntry(from row: PriceObservation) -> ObservationEntry {
        ObservationEntry(
            id: row.id,
            instrumentKey: row.instrumentKey,
            kind: row.kind,
            // Non-USD is normalised away here rather than deep in the walk, so
            // exactly one place in the app decides what "not in the total"
            // means.
            amount: row.currencyCode == "USD" ? row.amount : nil,
            receivedAt: row.receivedAt
        )
    }
}
