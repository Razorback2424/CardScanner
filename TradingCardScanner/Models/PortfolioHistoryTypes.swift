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

struct PortfolioHistoryInput: Equatable, Sendable {
    var closes: [PortfolioPublishedClose]
    var events: [LedgerEntry]
    var observations: [ObservationEntry]
    var summary: PortfolioSummary
    var epoch: Date?
    var timeZoneIdentifier: String
    var now: Date
    /// Time-weighted factor per finished portfolio day, produced by the same
    /// replay pass that produced the closes. The chart never re-walks history.
    var dailyPerformanceFactors: [Date: Decimal] = [:]
    /// The factor for the still-open day.
    var livePerformanceFactor: Decimal? = 1
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

    var isEmpty: Bool { points.isEmpty }
}
