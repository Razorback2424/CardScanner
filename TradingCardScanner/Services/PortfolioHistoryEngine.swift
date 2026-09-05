import Foundation
import CryptoKit
import SwiftData

/// Pure Phase 2 history calculations. SwiftData is only referenced by the
/// main-actor controller at the bottom; all chart inputs and outputs are value
/// snapshots.
enum PortfolioHistoryEngine {
    static func calculate(
        input: PortfolioHistoryInput,
        mode: PortfolioHistoryMode,
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
        guard let anchor = latest.first(where: { $0.date >= requestedStart }) ?? latest.first else {
            return PortfolioHistoryResult(
                mode: mode, range: range, points: [], accounting: nil,
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

        let liveIsDistinct = input.now > (points.last?.instant ?? .distantPast)
        if liveIsDistinct {
            var cursor = PortfolioCalendar.boundary(afterDay: previousDate, in: timeZone)
            let liveDay = PortfolioCalendar.day(containing: input.now, in: timeZone)
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
        let interval = PortfolioAccountingInterval(
            anchorDate: anchor.date,
            includedClosedDays: Array(selected.dropFirst().map(\.date)),
            includesLiveDay: liveIsDistinct,
            liveDay: liveIsDistinct ? PortfolioCalendar.day(containing: input.now, in: timeZone) : nil
        )
        let accounting = accounting(
            anchor: anchor,
            interval: interval,
            closes: latestByDate,
            liveAttribution: input.summary.attribution,
            endValue: points.last?.value ?? anchor.closeValue
        )
        let performanceFactor = factorAvailable ? factors.last ?? 1 : nil

        return PortfolioHistoryResult(
            mode: mode,
            range: range,
            points: points,
            accounting: accounting,
            performanceFactor: performanceFactor,
            performanceAvailable: factorAvailable,
            coverage: coverage(selected: selected, live: liveIsDistinct ? input.summary.coverage : nil),
            revisions: audit,
            trackingBeganDate: requestedStart < anchor.date ? anchor.date : nil,
            hasTwoPublishedPoints: selected.count >= 2,
            accountingInterval: interval,
            contributions: input.contributions.contributions(in: interval),
            movementDetails: input.contributions.movementDetails(in: interval),
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
        var flow = Money.zero
        var corrections = Money.zero
        var newlyAddedValue = Money.zero
        var pricing = Money.zero
        for day in interval.includedClosedDays {
            guard let close = closes[day] else { continue }
            market += close.market
            flow += close.flow
            corrections += close.corrections
            newlyAddedValue += close.newlyAddedValue
            pricing += close.pricingAdjustment
        }
        if interval.includesLiveDay, let live = liveAttribution {
            market += live.market
            flow += live.added - live.removed
            corrections += live.corrections
            newlyAddedValue += live.newlyAddedValue
            pricing += live.pricingAdjustment
        }
        return PortfolioHistoryAccounting(
            anchorValue: anchor.closeValue,
            endValue: endValue,
            market: market,
            netInventoryActivity: flow,
            corrections: corrections,
            newlyAddedValue: newlyAddedValue,
            pricingAdjustments: pricing,
            unexplained: endValue - anchor.closeValue - market - flow - corrections - newlyAddedValue - pricing
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
    @Published var mode: PortfolioHistoryMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "portfolioHistoryMode")
            if oldValue != mode { result = nil }
        }
    }

    @Published var range: PortfolioHistoryRange {
        didSet {
            UserDefaults.standard.set(range.rawValue, forKey: "portfolioHistoryRange")
            if oldValue != range { result = nil }
        }
    }

    @Published private(set) var result: PortfolioHistoryResult?

    init() {
        // The primary Portfolio screen has one period metric. Ignore the
        // legacy Performance/Collection Value preference so an old setting
        // cannot restore the ambiguous presentation.
        mode = .marketMovement
        range = PortfolioHistoryRange(
            rawValue: UserDefaults.standard.string(forKey: "portfolioHistoryRange") ?? ""
        ) ?? .oneMonth
    }

    /// Result scoped to the currently selected period and presentation mode.
    var activeResult: PortfolioHistoryResult? {
        guard let result, result.matches(range: range, mode: mode) else { return nil }
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
        guard let summary else {
            result = nil
            return
        }
        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
        // Closes only. The chart plots published days and needs no replay of
        // its own — the factors arrive from the computation the engine already
        // performed.
        let storedCloses: [PortfolioDailyClose]
        do {
            storedCloses = try PortfolioEngine.allCloses(in: context)
        } catch {
            // History is derived from persisted closes. If that read is
            // unavailable, publishing an empty chart would make a storage
            // problem look like missing history.
            result = nil
            return
        }
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
                revisionReason: $0.revisionReason
            )
        }
        result = PortfolioHistoryEngine.calculate(
            input: PortfolioHistoryInput(
                closes: closes,
                summary: summary,
                epoch: PortfolioEpoch.startedAt(context: context),
                timeZoneIdentifier: timeZone.identifier,
                now: now,
                factors: factors,
                contributions: contributions
            ),
            mode: mode,
            range: range
        )
    }

}
