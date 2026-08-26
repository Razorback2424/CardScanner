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
                trackingBeganDate: nil, hasTwoPublishedPoints: false
            )
        }

        let selected = latest.filter { $0.date >= anchor.date }
        var points: [PortfolioHistoryPoint] = []
        var factors: [Decimal?] = []
        var factorAvailable = true
        var factor: Decimal = 1
        points.append(PortfolioHistoryPoint(
            displayDay: anchor.date,
            instant: anchor.instant,
            value: anchor.closeValue,
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
                performanceFactor: factorAvailable ? factor : nil,
                isLive: false
            ))
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
            points.append(PortfolioHistoryPoint(
                displayDay: PortfolioCalendar.day(containing: input.now, in: timeZone),
                instant: input.now,
                value: input.summary.currentValue,
                performanceFactor: factorAvailable ? factor : nil,
                isLive: true
            ))
            factors.append(factorAvailable ? factor : nil)
        }

        let selectedDates = Set(selected.map(\.date))
        let audit = revisionAudit(closes: input.closes, dates: selectedDates)
        let accounting = accounting(
            anchor: anchor,
            selected: selected,
            liveIncluded: liveIsDistinct,
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
            hasTwoPublishedPoints: selected.count >= 2
        )
    }

    private static func accounting(
        anchor: PortfolioPublishedClose,
        selected: [PortfolioPublishedClose],
        liveIncluded: Bool,
        liveAttribution: PortfolioClose.Attribution?,
        endValue: Money
    ) -> PortfolioHistoryAccounting {
        var market = Money.zero
        var flow = Money.zero
        var corrections = Money.zero
        var pricing = Money.zero
        for close in selected.dropFirst() {
            market += close.market
            flow += close.flow
            corrections += close.corrections
            pricing += close.pricingAdjustment
        }
        if liveIncluded, let live = liveAttribution {
            market += live.market
            flow += live.added - live.removed
            corrections += live.corrections
            pricing += live.pricingAdjustment
        }
        return PortfolioHistoryAccounting(
            anchorValue: anchor.closeValue,
            endValue: endValue,
            market: market,
            netInventoryActivity: flow,
            corrections: corrections,
            pricingAdjustments: pricing,
            unexplained: endValue - anchor.closeValue - market - flow - corrections - pricing
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
final class PortfolioHistoryController: ObservableObject {
    @Published private(set) var result: PortfolioHistoryResult?

    func recompute(
        context: ModelContext,
        summary: PortfolioSummary?,
        factors: PortfolioPerformanceFactors,
        mode: PortfolioHistoryMode,
        range: PortfolioHistoryRange,
        now: Date = .now
    ) {
        guard let summary else {
            result = nil
            return
        }
        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? PortfolioCalendar.timeZone()
        // Closes only. The chart plots published days and needs no replay of
        // its own — the factors arrive from the computation the engine already
        // performed.
        let closes = PortfolioEngine.allCloses(in: context).map {
            PortfolioPublishedClose(
                date: $0.date, revision: $0.revision, timeZoneIdentifier: $0.timeZoneIdentifier,
                closeValue: $0.closeValue, market: $0.marketContribution, flow: $0.flowContribution,
                corrections: $0.correctionContribution, pricingAdjustment: $0.pricingAdjustment,
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
                factors: factors
            ),
            mode: mode,
            range: range
        )
    }

}
