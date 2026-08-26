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
    /// Whether derived history can be trusted right now.
    ///
    /// When false the collection's current value is still shown — the cards are
    /// still owned — but attribution and history are paused and no close is
    /// published or revised. A system that knows its ledger is incomplete must
    /// not simultaneously publish a supposedly trustworthy close; doing so is
    /// what turns an integrity diagnostic into an ornament.
    var isAuthoritative = true
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
        inputRevision &+= 1
        status = .computing

        let timeZone = PortfolioCalendar.timeZone()
        let today = PortfolioCalendar.day(containing: now, in: timeZone)
        lastComputedDay = today

        // One snapshot, one replay. Everything below reads from that single
        // forward pass rather than recomputing prefixes per day.
        let snapshot = PortfolioReplaySnapshotBuilder.make(
            context: context,
            epoch: PortfolioEpoch.startedAt(context: context) ?? now,
            through: now,
            timeZone: timeZone
        )
        let projection = snapshot.projection
        let valuation = Self.currentValuation(
            projection: projection,
            valuations: snapshot.valuations,
            otherCurrencyInstruments: snapshot.otherCurrencyInstruments
        )

        var summary = PortfolioSummary(
            currentValue: valuation.value,
            unpricedCount: valuation.unpricedCount,
            otherCurrencyCount: valuation.otherCurrencyCount
        )
        summary.defects = snapshot.defects
            + Self.reconcile(projection: projection, events: snapshot.input.events)
        summary.isAuthoritative = summary.defects.isEmpty
        LedgerIntegrityLog.shared.replaceAll(with: summary.defects)

        guard let epoch = PortfolioEpoch.startedAt(context: context) else {
            status = .ready(summary)
            return
        }

        summary.isMigrationDay = PortfolioEpoch.isMigrationDay(now, epoch: epoch, timeZone: timeZone)

        let replay = PortfolioReplayEngine.replay(snapshot.input)
        summary.coverage = replay.live?.coverageToday(
            index: snapshot.input.coverage,
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
    /// The collection's value right now, taken from the collection itself.
    ///
    /// Deliberately not the replay's ending state: the residual only means
    /// something if the two sides are measured independently. Prices come from
    /// the bulk index — one fetch per position would be one fetch per position
    /// against the whole observation log.
    static func currentValuation(
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
    static func reconcile(
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
        // query per day inside a loop over the whole history.
        let stored = Dictionary(grouping: allCloses(in: context), by: \.date)
            .compactMapValues { $0.max { $0.revision < $1.revision } }

        var latest: PortfolioDailyClose?
        var inserted = false

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
            latest = close
            inserted = true
        }

        if inserted { try? context.save() }
        return latest
    }

    /// Whether a stored close already says exactly what the replay derived.
    private static func matches(_ stored: PortfolioDailyClose, _ day: PortfolioReplayDay) -> Bool {
        stored.closeValue == day.closeValue
            && stored.marketContribution == day.market
            && stored.flowContribution == day.flow
            && stored.correctionContribution == day.corrections
            && stored.pricingAdjustment == day.pricingAdjustment
            && stored.carriedForwardValue == day.carriedForwardValue
            && stored.coverageState == day.coverage.state
            && stored.refreshedInstrumentCount == day.coverage.refreshed
            && stored.carriedForwardInstrumentCount == day.coverage.carriedForward
            && stored.pricedPositionCount == day.pricedPositionCount
            && stored.excludedCount == day.excludedQuantity
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
        return ((try? context.fetch(descriptor)) ?? []).map(observationEntry(from:))
    }

    static func observationEntry(from row: PriceObservation) -> ObservationEntry {
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
