import Foundation
import CryptoKit
import SwiftData

/// Pure history calculations over value snapshots. The background model actor
/// below owns SwiftData reads; the main-actor store schedules work and publishes
/// the result for the latest inputs and selected range.
enum PortfolioHistoryEngine {
    static func calculate(
        input: PortfolioHistoryInput,
        range: PortfolioHistoryRange
    ) -> PortfolioHistoryResult {
        let timeZone = TimeZone(identifier: input.timeZoneIdentifier) ?? .current
        let calendar = PortfolioCalendar.calendar(in: timeZone)
        let latestByDate = Dictionary(grouping: input.closes, by: \.date)
            .compactMapValues { $0.max { lhs, rhs in lhs.revision < rhs.revision } }
        let latest = latestByDate.values.sorted { $0.date < $1.date }
        let requestedStart = range.requestedStart(
            now: input.now,
            calendar: calendar,
            earliest: latest.first?.date
        )
        guard let anchor = latest.first(where: { $0.date >= requestedStart })
            ?? latest.last(where: { $0.date < requestedStart }) else {
            return PortfolioHistoryResult(
                range: range, points: [], accounting: nil,
                performanceFactor: nil, performanceAvailable: true,
                coverage: PortfolioHistoryCoverage(), revisions: [],
                trackingBeganDate: nil, hasTwoPublishedPoints: false,
                accountingInterval: nil, contributions: [:],
                hasEligibleMarketMovement: false
            )
        }

        let selected = latest.filter { $0.date >= anchor.date }
        var points: [PortfolioHistoryPoint] = []
        var factors: [Decimal?] = []
        var factorAvailable = true
        var factor: Decimal = 1
        var cumulativeMarketMovement = Money.zero
        points.append(PortfolioHistoryPoint(
            displayDay: anchor.date,
            instant: anchor.instant,
            value: anchor.closeValue,
            cumulativeMarketMovement: .zero,
            performanceFactor: 1,
            isLive: false
        ))
        factors.append(1)

        // Daily factors come straight from the replay, which already produced
        // them in the same forward pass that produced the closes. There is no
        // second walk here — the engine this replaced re-derived the whole
        // prefix once per close.
        let dailyFactors = input.factors.daily

        var previousDate = anchor.date
        for close in selected.dropFirst() {
            var cursor = PortfolioCalendar.boundary(afterDay: previousDate, in: timeZone)
            while cursor <= close.date {
                guard let link = dailyFactors[cursor] else {
                    factorAvailable = false
                    break
                }
                factor = rounded(factor * link)
                cursor = PortfolioCalendar.boundary(afterDay: cursor, in: timeZone)
            }
            points.append(PortfolioHistoryPoint(
                displayDay: close.date,
                instant: close.instant,
                value: close.closeValue,
                cumulativeMarketMovement: cumulativeMarketMovement + close.market,
                performanceFactor: factorAvailable ? factor : nil,
                isLive: false
            ))
            cumulativeMarketMovement += close.market
            factors.append(factorAvailable ? factor : nil)
            previousDate = close.date
        }

        // Resolve the accounting interval before plotting its optional live
        // endpoint. The chart and every accounting/contribution consumer must
        // use this same live-day decision.
        let includesLiveDay = input.now > (points.last?.instant ?? .distantPast)
        let interval = PortfolioAccountingInterval(
            anchorDate: anchor.date,
            includedClosedDays: Array(selected.dropFirst().map(\.date)),
            includesLiveDay: includesLiveDay,
            liveDay: includesLiveDay
                ? PortfolioCalendar.day(containing: input.now, in: timeZone)
                : nil
        )
        if interval.includesLiveDay, let liveDay = interval.liveDay {
            var cursor = PortfolioCalendar.boundary(afterDay: previousDate, in: timeZone)
            while cursor <= liveDay {
                guard let link = cursor == liveDay
                    ? input.factors.live
                    : dailyFactors[cursor] else {
                    factorAvailable = false
                    break
                }
                factor = rounded(factor * link)
                cursor = PortfolioCalendar.boundary(afterDay: cursor, in: timeZone)
            }
            cumulativeMarketMovement += input.summary.attribution?.market ?? .zero
            points.append(PortfolioHistoryPoint(
                displayDay: PortfolioCalendar.day(containing: input.now, in: timeZone),
                instant: input.now,
                value: input.summary.currentValue,
                cumulativeMarketMovement: cumulativeMarketMovement,
                performanceFactor: factorAvailable ? factor : nil,
                isLive: true
            ))
            factors.append(factorAvailable ? factor : nil)
        }

        let selectedDates = Set(selected.map(\.date))
        let audit = revisionAudit(closes: input.closes, dates: selectedDates)
        let accounting = accounting(
            anchor: anchor,
            interval: interval,
            closes: latestByDate,
            liveAttribution: input.summary.attribution,
            endValue: points.last?.value ?? anchor.closeValue
        )
        let performanceFactor = factorAvailable ? factors.last ?? 1 : nil

        return PortfolioHistoryResult(
            range: range,
            points: points,
            accounting: accounting,
            performanceFactor: performanceFactor,
            performanceAvailable: factorAvailable,
            coverage: coverage(
                selected: selected,
                live: interval.includesLiveDay ? input.summary.coverage : nil
            ),
            revisions: audit,
            trackingBeganDate: anchor.date < requestedStart ? anchor.date : nil,
            hasTwoPublishedPoints: selected.count >= 2,
            accountingInterval: interval,
            contributions: input.contributions.contributions(in: interval),
            movementDetails: input.contributions.movementDetails(in: interval),
            additions: input.contributions.additions(in: interval),
            addedQuantities: input.contributions.addedQuantities(in: interval),
            hasEligibleMarketMovement: input.contributions.hasEligibleMarketMovement(in: interval)
        )
    }

    private static func accounting(
        anchor: PortfolioPublishedClose,
        interval: PortfolioAccountingInterval,
        closes: [Date: PortfolioPublishedClose],
        liveAttribution: PortfolioClose.Attribution?,
        endValue: Money
    ) -> PortfolioHistoryAccounting {
        var market = Money.zero
        var added = Money.zero
        var removed = Money.zero
        var corrections = Money.zero
        var newlyAddedValue = Money.zero
        var pricing = Money.zero
        for day in interval.includedClosedDays {
            guard let close = closes[day] else { continue }
            market += close.market
            added += close.added
            removed += close.removed
            corrections += close.corrections
            newlyAddedValue += close.newlyAddedValue
            pricing += close.pricingAdjustment
        }
        if interval.includesLiveDay, let live = liveAttribution {
            market += live.market
            added += live.added
            removed += live.removed
            corrections += live.corrections
            newlyAddedValue += live.newlyAddedValue
            pricing += live.pricingAdjustment
        }
        return PortfolioHistoryAccounting(
            anchorValue: anchor.closeValue,
            endValue: endValue,
            market: market,
            added: added,
            removed: removed,
            corrections: corrections,
            newlyAddedValue: newlyAddedValue,
            pricingAdjustments: pricing,
            unexplained: endValue - anchor.closeValue - market - (added - removed) - corrections - newlyAddedValue - pricing
        )
    }

    private static func coverage(
        selected: [PortfolioPublishedClose],
        live: PortfolioCoverage?
    ) -> PortfolioHistoryCoverage {
        var result = PortfolioHistoryCoverage(live: live)
        for close in selected {
            switch close.coverage {
            case .complete: result.completeDays += 1
            case .partial: result.partialDays += 1
            case .unknown: result.unknownDays += 1
            }
        }
        return result
    }

    private static func revisionAudit(
        closes: [PortfolioPublishedClose],
        dates: Set<Date>
    ) -> [PortfolioHistoryRevision] {
        Dictionary(grouping: closes.filter { dates.contains($0.date) }, by: \.date)
            .compactMap { date, revisions in
                guard let original = revisions.min(by: { $0.revision < $1.revision }),
                      let latest = revisions.max(by: { $0.revision < $1.revision }),
                      latest.revision > original.revision else { return nil }
                return PortfolioHistoryRevision(date: date, original: original, latest: latest)
            }
            .sorted { $0.date < $1.date }
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal.zero
        NSDecimalRound(&output, &input, 16, .bankers)
        return output
    }
}

@MainActor
final class PortfolioHistoryStore: ObservableObject {
    @Published var range: PortfolioHistoryRange {
        didSet {
            UserDefaults.standard.set(range.rawValue, forKey: "portfolioHistoryRange")
            if oldValue != range { scheduleComputation() }
        }
    }

    @Published private(set) var result: PortfolioHistoryResult?
    private var cachedInput: PortfolioHistoryInput?
    private var loadRequest: PortfolioHistoryLoadRequest?
    private var inputRevision: UInt = 0
    private var requestRevision: UInt = 0
    private var computationTask: Task<Void, Never>?
    typealias Calculation = @Sendable (PortfolioHistoryInput, PortfolioHistoryRange) async -> PortfolioHistoryResult
    private let calculate: Calculation

    init(calculate: Calculation? = nil) {
        self.calculate = calculate ?? { input, range in
            await PortfolioHistoryCalculationWorker().calculate(input: input, range: range)
        }
        range = PortfolioHistoryRange(
            rawValue: UserDefaults.standard.string(forKey: "portfolioHistoryRange") ?? ""
        ) ?? .oneMonth
    }

    /// Result scoped to the currently selected period.
    var activeResult: PortfolioHistoryResult? {
        guard let result, result.matches(range: range) else { return nil }
        return result
    }

    func movementState(for collectionKey: String) -> PortfolioCardMovementState {
        activeResult?.cardMovement(for: collectionKey) ?? .historyRecording
    }

    func recompute(
        context: ModelContext,
        summary: PortfolioSummary?,
        factors: PortfolioPerformanceFactors,
        contributions: PortfolioContributionIndex,
        now: Date = .now
    ) {
        inputRevision &+= 1
        requestRevision &+= 1
        cachedInput = nil
        guard let summary else {
            loadRequest = nil
            result = nil
            return
        }
        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
        loadRequest = PortfolioHistoryLoadRequest(
            container: context.container, summary: summary,
            epoch: PortfolioEpoch.startedAt(), timeZoneIdentifier: timeZone.identifier,
            now: now, factors: factors, contributions: contributions
        )
        scheduleComputation()
    }

    /// Range changes reuse the last immutable input. Only one read/calculation
    /// runs at a time; a burst leaves one trailing request for the newest state.
    private func scheduleComputation() {
        requestRevision &+= 1
        guard loadRequest != nil, computationTask == nil else { return }
        computationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.computationTask = nil }
            while let request = self.loadRequest {
                let revision = self.requestRevision
                let inputRevision = self.inputRevision
                let range = self.range
                let input: PortfolioHistoryInput?
                if let cached = self.cachedInput {
                    input = cached
                } else {
                    let worker = await PortfolioHistoryModelActor.makeBackground(modelContainer: request.container)
                    input = await worker.input(for: request)
                }
                guard inputRevision == self.inputRevision else { continue }
                guard let input else {
                    // An unreadable store is unavailable history, never a
                    // fabricated empty chart. A later recompute can retry it.
                    self.result = nil
                    return
                }
                self.cachedInput = input
                guard revision == self.requestRevision else { continue }
                let result = await self.calculate(input, range)
                guard revision == self.requestRevision else { continue }
                self.result = result
                return
            }
        }
    }

    func waitForPendingComputation() async {
        await computationTask?.value
    }
}

private struct PortfolioHistoryLoadRequest: Sendable {
    let container: ModelContainer
    let summary: PortfolioSummary
    let epoch: Date?
    let timeZoneIdentifier: String
    let now: Date
    let factors: PortfolioPerformanceFactors
    let contributions: PortfolioContributionIndex
}

/// No SwiftData objects cross back to the presentation store.
@ModelActor
private actor PortfolioHistoryModelActor: BackgroundModelActor {
    init(modelContainer: ModelContainer, modelExecutor: any ModelExecutor) {
        self.modelContainer = modelContainer
        self.modelExecutor = modelExecutor
    }

    func input(for request: PortfolioHistoryLoadRequest) -> PortfolioHistoryInput? {
        let descriptor = FetchDescriptor<PortfolioDailyClose>(
            sortBy: [SortDescriptor(\.date, order: .forward), SortDescriptor(\.revision, order: .forward)]
        )
        guard let storedCloses = try? modelContext.fetch(descriptor) else { return nil }
        let closes = storedCloses.map {
            PortfolioPublishedClose(
                date: $0.date, revision: $0.revision, timeZoneIdentifier: $0.timeZoneIdentifier,
                closeValue: $0.closeValue, market: $0.marketContribution, flow: $0.flowContribution,
                corrections: $0.correctionContribution, newlyAddedValue: $0.newlyAddedValue,
                pricingAdjustment: $0.pricingAdjustment,
                carriedForwardValue: $0.carriedForwardValue, coverage: $0.coverageState,
                refreshedInstrumentCount: $0.refreshedInstrumentCount,
                carriedForwardInstrumentCount: $0.carriedForwardInstrumentCount,
                pricedPositionCount: $0.pricedPositionCount, excludedCount: $0.excludedCount,
                revisionReason: $0.revisionReason, added: $0.addedContribution,
                removed: $0.removedContribution
            )
        }
        return PortfolioHistoryInput(
            closes: closes,
            summary: request.summary,
            epoch: request.epoch,
            timeZoneIdentifier: request.timeZoneIdentifier,
            now: request.now,
            factors: request.factors,
            contributions: request.contributions
        )
    }
}

private actor PortfolioHistoryCalculationWorker {
    func calculate(input: PortfolioHistoryInput, range: PortfolioHistoryRange) -> PortfolioHistoryResult {
        PortfolioHistoryEngine.calculate(input: input, range: range)
    }
}
