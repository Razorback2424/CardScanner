import Foundation

enum PortfolioHistoryMode: String, CaseIterable, Codable, Sendable {
    case performance
    case value

    var title: String {
        switch self {
        case .performance: return "Performance"
        case .value: return "Collection Value"
        }
    }

    var chartLabel: String {
        switch self {
        case .performance: return "Return percent"
        case .value: return "Collection value"
        }
    }
}

enum PortfolioHistoryRange: String, CaseIterable, Codable, Sendable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case all = "ALL"

    var accessibilityName: String {
        switch self {
        case .oneWeek: return "One week"
        case .oneMonth: return "One month"
        case .threeMonths: return "Three months"
        case .oneYear: return "One year"
        case .all: return "All history"
        }
    }

    func requestedStart(now: Date, calendar: Calendar, earliest: Date?) -> Date {
        let rawStart: Date
        switch self {
        case .oneWeek:
            rawStart = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .oneMonth:
            rawStart = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            rawStart = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .oneYear:
            rawStart = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            rawStart = earliest ?? now
        }
        return calendar.startOfDay(for: rawStart)
    }
}

/// A SwiftData-free close snapshot. Retaining this as a value type keeps the
/// chart and its accounting deterministic and makes the calculation layer
/// safe to move off the main actor later.
struct PortfolioPublishedClose: Equatable, Sendable {
    var date: Date
    var revision: Int
    var timeZoneIdentifier: String
    var closeValue: Money
    var market: Money
    var flow: Money
    var corrections: Money
    var pricingAdjustment: Money
    var carriedForwardValue: Money
    var coverage: PortfolioCoverageState
    var refreshedInstrumentCount: Int
    var carriedForwardInstrumentCount: Int
    var pricedPositionCount: Int
    var excludedCount: Int
    var revisionReason: PortfolioRevisionReason?

    /// The close is labeled by its economic day but plotted at the boundary
    /// where that day became final.
    var instant: Date {
        PortfolioCalendar.boundary(
            afterDay: date,
            in: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }

    var revisionNote: String? {
        guard revision > 1, let revisionReason else { return nil }
        switch revisionReason {
        case .lateInventoryTruth: return "reconciled after another device synced"
        case .recomputed: return "recomputed from corrected inputs"
        }
    }
}

/// Time-weighted factors, produced by the one replay the engine already ran.
///
/// The chart never re-derives these. Before this existed the history card
/// built its own snapshot and replayed the entire observation log a second
/// time, so a single input change cost two full passes.
struct PortfolioPerformanceFactors: Equatable, Sendable {
    /// Per finished portfolio day. A day is *absent* when its factor is
    /// undefined — filling the gap with 1 would report an unmeasurable period
    /// as flat.
    var daily: [Date: Decimal] = [:]
    /// The still-open day.
    var live: Decimal? = 1
}

struct PortfolioHistoryInput: Equatable, Sendable {
    var closes: [PortfolioPublishedClose]
    var summary: PortfolioSummary
    var epoch: Date?
    var timeZoneIdentifier: String
    var now: Date
    var factors = PortfolioPerformanceFactors()
    /// Sparse impacts from the replay that produced the closes. History uses
    /// the resolved accounting interval below rather than reinterpreting a
    /// calendar range for contributors.
    var contributions = PortfolioContributionIndex()
}

/// The exact economic interval a history result explains. Its anchor close is
/// the starting value, never a contribution inside the selected period.
struct PortfolioAccountingInterval: Equatable, Sendable {
    var anchorDate: Date
    var includedClosedDays: [Date]
    var includesLiveDay: Bool
    var liveDay: Date?
}

/// Sparse position-level market impacts from replay. This is derived data, not
/// a persisted accounting model: a key is retained only for a nonzero eligible
/// market update on that portfolio day.
struct PortfolioContributionIndex: Equatable, Sendable {
    var byDay: [Date: [String: Money]] = [:]
    /// A day may have genuine market updates whose position impacts cancel to
    /// zero. Keep that state separate from the sparse value index so the UI
    /// does not mistake an interesting $0 day for no movement.
    var daysWithEligibleMarketMovement: Set<Date> = []

    func contributions(in interval: PortfolioAccountingInterval) -> [String: Money] {
        var result: [String: Money] = [:]
        let days = interval.includedClosedDays
            + (interval.includesLiveDay ? [interval.liveDay].compactMap { $0 } : [])
        for day in days {
            for (key, amount) in byDay[day, default: [:]] {
                result[key, default: .zero] += amount
            }
        }
        return result.filter { !$0.value.isZero }
    }

    func hasEligibleMarketMovement(in interval: PortfolioAccountingInterval) -> Bool {
        let days = interval.includedClosedDays
            + (interval.includesLiveDay ? [interval.liveDay].compactMap { $0 } : [])
        return days.contains { daysWithEligibleMarketMovement.contains($0) }
    }
}

struct PortfolioHistoryPoint: Identifiable, Equatable, Sendable {
    /// The calendar day represented by this point, such as Aug 24.
    var displayDay: Date
    /// The economic instant represented by the point: the next midnight for a
    /// published close, or the live summary's current instant.
    var instant: Date
    var value: Money
    var performanceFactor: Decimal?
    var isLive: Bool

    var id: String { "\(instant.timeIntervalSinceReferenceDate)-\(isLive)" }
}

struct PortfolioHistoryCoverage: Equatable, Sendable {
    var completeDays = 0
    var partialDays = 0
    var unknownDays = 0
    var live: PortfolioCoverage?
}

struct PortfolioHistoryRevision: Equatable, Sendable {
    var date: Date
    var original: PortfolioPublishedClose
    var latest: PortfolioPublishedClose
}

struct PortfolioHistoryAccounting: Equatable, Sendable {
    var anchorValue: Money
    var endValue: Money
    var market: Money
    var netInventoryActivity: Money
    var corrections: Money
    var pricingAdjustments: Money
    var unexplained: Money

    var totalChange: Money { endValue - anchorValue }
}

struct PortfolioHistoryResult: Equatable, Sendable {
    var mode: PortfolioHistoryMode
    var range: PortfolioHistoryRange
    var points: [PortfolioHistoryPoint]
    var accounting: PortfolioHistoryAccounting?
    var performanceFactor: Decimal?
    var performanceAvailable: Bool
    var coverage: PortfolioHistoryCoverage
    var revisions: [PortfolioHistoryRevision]
    var trackingBeganDate: Date?
    var hasTwoPublishedPoints: Bool
    var accountingInterval: PortfolioAccountingInterval?
    var contributions: [String: Money]
    var hasEligibleMarketMovement: Bool

    var isEmpty: Bool { points.isEmpty }
}
