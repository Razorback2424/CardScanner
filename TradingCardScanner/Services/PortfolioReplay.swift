import Foundation

/// Which instruments were successfully checked on which portfolio day.
///
/// Deliberately opaque. `[Date: Set<String>]` is the right shape for the
/// volumes Phase 2 sees, but coverage is one row per instrument per day and
/// that is a lot of small rows a year. When it eventually needs sorted
/// `(day, instrument)` pairs, interned integer instrument ids or per-day
/// bitsets, only this type changes — the replay asks questions, it does not
/// read a dictionary.
struct PortfolioCoverageIndex: Sendable, Equatable {
    private let checkedByDay: [Date: Set<String>]

    init(checkedByDay: [Date: Set<String>] = [:]) {
        self.checkedByDay = checkedByDay
    }

    func wasChecked(_ instrument: String, on day: Date) -> Bool {
        checkedByDay[day]?.contains(instrument) ?? false
    }

    func checkedInstruments(on day: Date) -> Set<String> {
        checkedByDay[day] ?? []
    }

    var isEmpty: Bool { checkedByDay.isEmpty }
}

/// Everything one replay needs, as values. No `ModelContext`, no fetch
/// descriptors, no actor isolation — the accounting layer is testable with
/// literal arrays and a dictionary.
struct PortfolioReplayInput: Sendable {
    var events: [LedgerEntry]
    var observations: [ObservationEntry]
    var coverage: PortfolioCoverageIndex
    var epoch: Date
    var through: Date
    var timeZoneIdentifier: String

    init(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        coverage: PortfolioCoverageIndex = PortfolioCoverageIndex(),
        epoch: Date,
        through: Date,
        timeZoneIdentifier: String
    ) {
        self.events = events
        self.observations = observations
        self.coverage = coverage
        self.epoch = epoch
        self.through = through
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// One finished portfolio day.
struct PortfolioReplayDay: Sendable, Equatable {
    var displayDay: Date
    /// The instant the day became final — the next midnight in the portfolio
    /// zone. A close is labelled by its day and plotted here.
    var boundary: Date
    var closeValue: Money
    var market: Money
    var added: Money
    var removed: Money
    var corrections: Money
    var pricingAdjustment: Money
    /// Time-weighted factor for this day alone. `nil` where no meaningful link
    /// could be formed — an honest "not defined", never a silent 0%.
    var performanceFactor: Decimal?
    var pricedPositionCount: Int
    var excludedQuantity: Int
    var coverage: PortfolioCoverage
    var carriedForwardValue: Money
    /// Sparse position impacts for this completed portfolio day.
    var contributions: [String: Money]
    /// Enriched position impacts from the same market updates.
    var movementDetails: [String: PortfolioContributionDetail]
    var hasEligibleMarketMovement: Bool

    var flow: Money { added - removed }
}

/// The unfinished day at the end of the replay.
struct PortfolioReplayLive: Sendable, Equatable {
    var day: Date
    var attribution: PortfolioClose.Attribution
    var performanceFactor: Decimal?
    var pricedPositionCount: Int
    var excludedQuantity: Int
    var contributions: [String: Money]
    var movementDetails: [String: PortfolioContributionDetail]
    var hasEligibleMarketMovement: Bool
}

extension PortfolioReplayLive {
    /// Coverage for the still-open day. Held instruments come from the live
    /// collection rather than the replay, so a position the ledger has not yet
    /// heard about is still counted as something needing a check.
    func coverageToday(
        index: PortfolioCoverageIndex,
        heldInstruments: Set<String>,
        day: Date
    ) -> PortfolioCoverage {
        guard !heldInstruments.isEmpty else { return PortfolioCoverage(state: .complete) }
        let refreshed = heldInstruments.intersection(index.checkedInstruments(on: day)).count
        let carriedForward = heldInstruments.count - refreshed
        return PortfolioCoverage(
            refreshed: refreshed,
            carriedForward: carriedForward,
            state: carriedForward == 0 ? .complete : .partial
        )
    }
}

struct PortfolioReplayResult: Sendable, Equatable {
    /// Every finished day from the epoch through the last completed boundary.
    var days: [PortfolioReplayDay]
    /// The current, still-open day. Absent when `through` lands exactly on a
    /// boundary and nothing is open.
    var live: PortfolioReplayLive?
    /// Cumulative time-weighted factor across every finished day.
    var performanceAvailable: Bool
    var contributionIndex: PortfolioContributionIndex
}

/// One forward pass over the merged timeline.
///
/// The engine this replaces recomputed the whole prefix for every day: each
/// close called `state(asOf:)`, which grouped and sorted every event and
/// observation from time zero, and the performance walk did it again per day
/// segment. Measured on synthetic history, 30 days took 3.4 s and 90 days took
/// 78 s — the cost grew faster than the data because a quadratic timeline
/// builder was being invoked inside a per-day loop.
///
/// Here everything is normalised once and the cursor only moves forward. Close
/// value, attribution, time-weighted return and coverage all come off the same
/// evolving state, so they can no longer disagree with each other by having
/// been produced by separate passes.
enum PortfolioReplayEngine {

    // MARK: - Prepared inputs

    /// One operation, with its legs already ordered and its timestamp resolved.
    struct PreparedOperation: Sendable, Equatable {
        var occurredAt: Date
        var legs: [LedgerEntry]
        /// Whether any leg was valued from an observation received at exactly
        /// this instant, which decides tie ordering against that observation.
        var isNewBasis: Bool
        var sortID: String
    }

    struct Prepared: Sendable {
        var operations: [PreparedOperation]
        var observations: [ObservationEntry]
        var coverage: PortfolioCoverageIndex
        var epoch: Date
        var through: Date
        var timeZone: TimeZone
    }

    /// Groups legs, resolves undo pairs, and sorts both streams exactly once.
    nonisolated static func prepare(_ input: PortfolioReplayInput) -> Prepared {
        let timeZone = TimeZone(identifier: input.timeZoneIdentifier) ?? .current

        // An operation and its explicit undo inside the same accounting day are
        // audit rows, not economic activity: collapsing both makes an add+Undo
        // disappear, and makes a remove+Undo behave as though the temporary
        // mutation never happened. A reversal of an *earlier* day's operation
        // is today's correction and stays in the walk.
        let eventByID = Dictionary(input.events.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        var collapsed: Set<UUID> = []
        for reversal in input.events {
            guard let originalID = reversal.reversesEventID,
                  let original = eventByID[originalID],
                  PortfolioCalendar.day(containing: original.occurredAt, in: timeZone)
                    == PortfolioCalendar.day(containing: reversal.occurredAt, in: timeZone)
            else { continue }
            collapsed.insert(originalID)
            collapsed.insert(reversal.eventID)
        }

        var groups: [UUID: [LedgerEntry]] = [:]
        for event in input.events where !collapsed.contains(event.eventID) {
            groups[event.operationID, default: []].append(event)
        }

        var operations: [PreparedOperation] = []
        operations.reserveCapacity(groups.count)
        for (_, legs) in groups {
            let ordered = legs.sorted { lhs, rhs in
                if lhs.leg != rhs.leg {
                    // `from` before `to`; an unlegged row sorts before either.
                    return legOrder(lhs.leg) < legOrder(rhs.leg)
                }
                return lhs.eventID.uuidString < rhs.eventID.uuidString
            }
            guard let first = ordered.first else { continue }
            let occurredAt = first.occurredAt
            operations.append(
                PreparedOperation(
                    occurredAt: occurredAt,
                    legs: ordered,
                    isNewBasis: ordered.contains { $0.priceReceivedAtEvent == occurredAt },
                    sortID: first.eventID.uuidString
                )
            )
        }

        operations.sort { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
            // At one instant: operations valued from the old price, then the
            // observation, then operations valued from the new price. The
            // observation itself is placed by the merge below.
            if lhs.isNewBasis != rhs.isNewBasis { return !lhs.isNewBasis }
            return lhs.sortID < rhs.sortID
        }

        let observations = input.observations.sorted { lhs, rhs in
            if lhs.receivedAt != rhs.receivedAt { return lhs.receivedAt < rhs.receivedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return Prepared(
            operations: operations,
            observations: observations,
            coverage: input.coverage,
            epoch: input.epoch,
            through: input.through,
            timeZone: timeZone
        )
    }

    private nonisolated static func legOrder(_ leg: InventoryCorrectionLeg?) -> Int {
        switch leg {
        case .none: return 0
        case .from: return 1
        case .to: return 2
        }
    }

    // MARK: - The pass

    nonisolated static func replay(_ input: PortfolioReplayInput) -> PortfolioReplayResult {
        run(prepare(input))
    }

    nonisolated static func run(_ prepared: Prepared) -> PortfolioReplayResult {
        var state = PortfolioReplayState()
        var days: [PortfolioReplayDay] = []
        var performanceAvailable = true

        var operationIndex = 0
        var observationIndex = 0

        var day = PortfolioCalendar.day(containing: prepared.epoch, in: prepared.timeZone)
        var boundary = PortfolioCalendar.boundary(afterDay: day, in: prepared.timeZone)

        var openingValue = state.value
        var accumulator = DayAccumulator()

        // The cursor only moves forward. Nothing here filters the full arrays,
        // rebuilds a timeline, or recomputes a prefix.
        while true {
            let nextOperation = operationIndex < prepared.operations.count
                ? prepared.operations[operationIndex] : nil
            let nextObservation = observationIndex < prepared.observations.count
                ? prepared.observations[observationIndex] : nil

            let nextInstant = [nextOperation?.occurredAt, nextObservation?.receivedAt]
                .compactMap { $0 }
                .min()

            // Close every day that finishes before the next entry. `>=` because
            // days are half-open: an entry exactly on the boundary opens the
            // next day rather than closing this one.
            while boundary <= prepared.through,
                  nextInstant.map({ $0 >= boundary }) ?? true {
                days.append(
                    finish(
                        day: day,
                        boundary: boundary,
                        openingValue: openingValue,
                        accumulator: accumulator,
                        state: state,
                        coverage: prepared.coverage
                    )
                )
                if accumulator.performanceFactor == nil { performanceAvailable = false }
                openingValue = state.value
                accumulator = DayAccumulator()
                day = boundary
                boundary = PortfolioCalendar.boundary(afterDay: day, in: prepared.timeZone)
            }

            guard let nextInstant, nextInstant <= prepared.through else { break }

            // At a tie: old-basis operations, then the observation, then
            // new-basis operations. `prepare` already ordered operations so
            // old-basis sorts first, so the merge only has to decide whether
            // the observation goes before the operation at hand.
            let takeObservation: Bool
            if let nextObservation, let nextOperation {
                if nextObservation.receivedAt != nextOperation.occurredAt {
                    takeObservation = nextObservation.receivedAt < nextOperation.occurredAt
                } else {
                    takeObservation = nextOperation.isNewBasis
                }
            } else {
                takeObservation = nextObservation != nil
            }

            if takeObservation, let observation = nextObservation {
                apply(observation, to: &state, into: &accumulator)
                observationIndex += 1
            } else if let operation = nextOperation {
                apply(operation, to: &state, into: &accumulator)
                operationIndex += 1
            } else {
                break
            }
        }

        // Whatever is still open at `through`.
        var live: PortfolioReplayLive?
        if boundary > prepared.through {
            var attribution = PortfolioClose.Attribution()
            attribution.closeValue = openingValue
            attribution.market = accumulator.market
            attribution.added = accumulator.added
            attribution.removed = accumulator.removed
            attribution.corrections = accumulator.corrections
            attribution.pricingAdjustment = accumulator.pricingAdjustment
            attribution.currentValue = state.value
            attribution.pricedPositionCount = state.pricedPositionCount
            live = PortfolioReplayLive(
                day: day,
                attribution: attribution,
                performanceFactor: accumulator.performanceFactor,
                pricedPositionCount: state.pricedPositionCount,
                excludedQuantity: state.excludedQuantity,
                contributions: accumulator.contributions,
                movementDetails: accumulator.movementDetails,
                hasEligibleMarketMovement: accumulator.hasEligibleMarketMovement
            )
        }

        var contributionIndex = PortfolioContributionIndex()
        for finished in days {
            if !finished.contributions.isEmpty {
                contributionIndex.byDay[finished.displayDay] = finished.contributions
            }
            if !finished.movementDetails.isEmpty {
                contributionIndex.detailsByDay[finished.displayDay] = finished.movementDetails
            }
            if finished.hasEligibleMarketMovement {
                contributionIndex.daysWithEligibleMarketMovement.insert(finished.displayDay)
            }
        }
        if let live {
            if !live.contributions.isEmpty {
                contributionIndex.byDay[live.day] = live.contributions
            }
            if !live.movementDetails.isEmpty {
                contributionIndex.detailsByDay[live.day] = live.movementDetails
            }
            if live.hasEligibleMarketMovement {
                contributionIndex.daysWithEligibleMarketMovement.insert(live.day)
            }
        }

        return PortfolioReplayResult(
            days: days,
            live: live,
            performanceAvailable: performanceAvailable,
            contributionIndex: contributionIndex
        )
    }

    // MARK: -

    /// One day's attribution while it is still being accumulated.
    private struct DayAccumulator {
        var market = Money.zero
        var added = Money.zero
        var removed = Money.zero
        var corrections = Money.zero
        var pricingAdjustment = Money.zero
        var performanceFactor: Decimal? = 1
        var contributions: [String: Money] = [:]
        var movementDetails: [String: PortfolioContributionDetail] = [:]
        var hasEligibleMarketMovement = false
    }

    private nonisolated static func apply(
        _ observation: ObservationEntry,
        to state: inout PortfolioReplayState,
        into accumulator: inout DayAccumulator
    ) {
        let instrument = observation.instrumentKey
        let old = state.prices[instrument]
        let new = observation.amount
        let quantity = state.quantityPriced(through: instrument)
        let difference = (new ?? .zero) - (old ?? .zero)

        // Market movement is only what the market did to a value the app
        // already held and still holds. An instrument arriving at or leaving
        // USD-priceability is a change in what the app knows; a restatement or
        // a source transition is provenance being repaired. Neither is
        // performance.
        let isMarketMovement = observation.kind == .marketUpdate && old != nil && new != nil

        if isMarketMovement {
            accumulator.market += difference * quantity
            if quantity != 0, !difference.isZero {
                accumulator.hasEligibleMarketMovement = true
            }
            if !difference.isZero {
                for (position, heldQuantity) in state.positionsPriced(through: instrument) {
                    let contribution = difference * heldQuantity
                    guard !contribution.isZero else { continue }
                    accumulator.contributions[position, default: .zero] += contribution
                    if accumulator.contributions[position]?.isZero == true {
                        accumulator.contributions.removeValue(forKey: position)
                    }
                    var detail = accumulator.movementDetails[position, default: PortfolioContributionDetail()]
                    detail.record(unitMovement: difference, quantity: heldQuantity)
                    accumulator.movementDetails[position] = detail
                }
            }
        } else {
            accumulator.pricingAdjustment += difference * quantity
        }

        // The time-weighted link comes off the same state transition, in the
        // same pass, so performance can never disagree with attribution.
        if isMarketMovement, quantity != 0, old != new {
            let before = state.value
            state.setPrice(new, for: instrument)
            let after = state.value
            if before.tenThousandths > 0, let factor = accumulator.performanceFactor {
                accumulator.performanceFactor = rounded(
                    factor * (Decimal(after.tenThousandths) / Decimal(before.tenThousandths))
                )
            } else {
                accumulator.performanceFactor = nil
            }
            return
        }

        state.setPrice(new, for: instrument)
    }

    private nonisolated static func apply(
        _ operation: PreparedOperation,
        to state: inout PortfolioReplayState,
        into accumulator: inout DayAccumulator
    ) {
        // Correction legs move together or the ledger does not balance: an
        // observation between them would value one identity before a price
        // change and the other after it.
        for event in operation.legs {
            let price = state.prices[event.priceStorageKey]
            let value = (price ?? .zero) * event.deltaQuantity

            if event.reversesEventID != nil {
                // Reversing an operation from an already-published day is
                // today's correction. The old close stays immutable, and
                // negative Added/Removed never reaches the UI.
                accumulator.corrections += value
            } else {
                switch event.kind {
                case .correction, .quantityAdjust:
                    accumulator.corrections += value
                case .dispose:
                    accumulator.removed += Money(tenThousandths: -value.tenThousandths)
                case .acquire, .recordExisting, .initialBalance:
                    accumulator.added += value
                }
            }

            state.apply(
                delta: event.deltaQuantity,
                position: event.collectionKey,
                instrument: event.priceStorageKey
            )
        }
    }

    private nonisolated static func finish(
        day: Date,
        boundary: Date,
        openingValue: Money,
        accumulator: DayAccumulator,
        state: PortfolioReplayState,
        coverage index: PortfolioCoverageIndex
    ) -> PortfolioReplayDay {
        let held = state.heldInstrumentKeys
        let checked = index.checkedInstruments(on: day)
        let refreshed = held.intersection(checked).count
        let carriedForwardInstruments = held.count - refreshed

        // What the value would be worth from prices that were not confirmed
        // today. Stated rather than folded into the total.
        var carriedForwardValue = Money.zero
        for (position, quantity) in state.quantities where quantity != 0 {
            guard let instrument = state.instruments[position],
                  !checked.contains(instrument),
                  let price = state.prices[instrument] else { continue }
            carriedForwardValue += price * quantity
        }

        return PortfolioReplayDay(
            displayDay: day,
            boundary: boundary,
            closeValue: state.value,
            market: accumulator.market,
            added: accumulator.added,
            removed: accumulator.removed,
            corrections: accumulator.corrections,
            pricingAdjustment: accumulator.pricingAdjustment,
            performanceFactor: accumulator.performanceFactor,
            pricedPositionCount: state.pricedPositionCount,
            excludedQuantity: state.excludedQuantity,
            coverage: PortfolioCoverage(
                refreshed: refreshed,
                carriedForward: carriedForwardInstruments,
                state: held.isEmpty
                    ? .complete
                    : (carriedForwardInstruments == 0 ? .complete : .partial)
            ),
            carriedForwardValue: carriedForwardValue,
            contributions: accumulator.contributions,
            movementDetails: accumulator.movementDetails,
            hasEligibleMarketMovement: accumulator.hasEligibleMarketMovement
        )
    }

    private nonisolated static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal.zero
        NSDecimalRound(&output, &input, 16, .bankers)
        return output
    }
}

/// The evolving portfolio, with its aggregates maintained rather than rescanned.
///
/// This is the difference between linear and quadratic. Recomputing `value` and
/// "how many copies share this instrument" from the position dictionary on
/// every observation costs O(positions) each time — at 1,284 positions and a
/// year of daily refreshes that is billions of operations, which is slow for
/// exactly the same structural reason the old per-day prefix replay was slow.
/// Both totals are derivable from the deltas that change them, so they are.
struct PortfolioReplayState: Equatable {
    private(set) var quantities: [String: Int] = [:]
    /// Which instrument each position is currently valued through.
    private(set) var instruments: [String: String] = [:]
    private(set) var prices: [String: Money] = [:]
    /// Total quantity valued through each instrument. One observation values
    /// every position sharing it, so this is what a price change multiplies by.
    private(set) var quantityByInstrument: [String: Int] = [:]
    /// Current position quantities by instrument. This lets a price update
    /// attribute its impact to the precise positions it values without
    /// scanning the full collection on every observation.
    private(set) var quantitiesByPositionByInstrument: [String: [String: Int]] = [:]
    /// `Σ price × quantity` over priceable instruments, maintained in step.
    /// Unpriced and non-USD positions are excluded, never zeroed into the
    /// total and never converted at a rate the app does not have.
    private(set) var value: Money = .zero

    /// Positions currently owned that carry a USD price.
    var pricedPositionCount: Int {
        quantities.reduce(0) { count, entry in
            guard entry.value != 0,
                  let instrument = instruments[entry.key],
                  prices[instrument] != nil else { return count }
            return count + 1
        }
    }

    /// Copies owned but absent from the total.
    var excludedQuantity: Int {
        quantities.reduce(0) { count, entry in
            guard entry.value != 0,
                  let instrument = instruments[entry.key],
                  prices[instrument] != nil else {
                return count + Swift.abs(entry.value)
            }
            return count
        }
    }

    /// Instruments backing something actually owned. Derived from positions
    /// rather than from `quantityByInstrument`, because two positions on one
    /// instrument can net to zero while both are still held.
    var heldInstrumentKeys: Set<String> {
        Set(quantities.compactMap { key, quantity in
            quantity != 0 ? instruments[key] : nil
        })
    }

    func quantityPriced(through instrument: String) -> Int {
        quantityByInstrument[instrument] ?? 0
    }

    func positionsPriced(through instrument: String) -> [String: Int] {
        quantitiesByPositionByInstrument[instrument] ?? [:]
    }

    /// Sets or withdraws an instrument's price, moving `value` by exactly what
    /// the holders of that instrument are worth.
    mutating func setPrice(_ new: Money?, for instrument: String) {
        let quantity = quantityByInstrument[instrument] ?? 0
        let old = prices[instrument]
        if quantity != 0 {
            value += (new ?? .zero) * quantity
            value -= (old ?? .zero) * quantity
        }
        if let new {
            prices[instrument] = new
        } else {
            prices.removeValue(forKey: instrument)
        }
    }

    /// Applies one ledger leg.
    ///
    /// A leg also re-states which instrument the position is valued through, so
    /// the position's whole quantity moves to the named instrument — matching
    /// what a correction between identities means.
    mutating func apply(delta: Int, position: String, instrument: String) {
        let previousInstrument = instruments[position]
        let previousQuantity = quantities[position] ?? 0
        let newQuantity = previousQuantity + delta

        if let previousInstrument {
            adjust(instrument: previousInstrument, by: -previousQuantity)
            adjust(position: position, instrument: previousInstrument, by: -previousQuantity)
        }
        quantities[position] = newQuantity
        instruments[position] = instrument
        adjust(instrument: instrument, by: newQuantity)
        adjust(position: position, instrument: instrument, by: newQuantity)
    }

    private mutating func adjust(instrument: String, by delta: Int) {
        guard delta != 0 else { return }
        quantityByInstrument[instrument, default: 0] += delta
        if let price = prices[instrument] {
            value += price * delta
        }
    }

    private mutating func adjust(position: String, instrument: String, by delta: Int) {
        guard delta != 0 else { return }
        var positions = quantitiesByPositionByInstrument[instrument, default: [:]]
        let updated = (positions[position] ?? 0) + delta
        if updated == 0 {
            positions.removeValue(forKey: position)
        } else {
            positions[position] = updated
        }
        if positions.isEmpty {
            quantitiesByPositionByInstrument.removeValue(forKey: instrument)
        } else {
            quantitiesByPositionByInstrument[instrument] = positions
        }
    }
}
