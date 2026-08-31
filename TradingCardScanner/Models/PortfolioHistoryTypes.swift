import Foundation

enum PortfolioHistoryMode: String, CaseIterable, Codable, Sendable {
    case marketMovement
    case performance
    case value

    var title: String {
        switch self {
        case .marketMovement: return "Market movement"
        case .performance: return "Performance"
        case .value: return "Collection Value"
        }
    }

    var chartLabel: String {
        switch self {
        case .marketMovement: return "Market movement"
        case .performance: return "Return in dollars"
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
    var newlyAddedValue: Money = .zero
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

/// The market movement a position experienced during one or more replay steps.
/// `cumulativeUnitMovement` keeps the per-copy price path separate from the
/// holding impact, while `affectedQuantities` makes it possible to refuse a
/// misleading per-copy average when ownership changed during the period.
struct PortfolioContributionDetail: Equatable, Sendable {
    var totalImpact: Money = .zero
    var cumulativeUnitMovement: Money = .zero
    var affectedQuantities: [Int] = []

    var hasConsistentQuantity: Bool { affectedQuantities.count == 1 }

    mutating func record(unitMovement: Money, quantity: Int) {
        totalImpact += unitMovement * quantity
        cumulativeUnitMovement += unitMovement
        if !affectedQuantities.contains(quantity) {
            affectedQuantities.append(quantity)
            affectedQuantities.sort()
        }
    }
}

enum PortfolioCardMovementState: Equatable, Sendable {
    case historyRecording
    case noRecordedMarketMovement
    case recorded(PortfolioContributionDetail)
}

/// Sparse position-level market impacts from replay. This is derived data, not
/// a persisted accounting model: a key is retained only for a nonzero eligible
/// market update on that portfolio day.
struct PortfolioContributionIndex: Equatable, Sendable {
    var byDay: [Date: [String: Money]] = [:]
    /// Enriched contribution data from the same replay that produced `byDay`.
    /// `byDay` remains as a compatibility projection for portfolio rows and
    /// existing history consumers.
    var detailsByDay: [Date: [String: PortfolioContributionDetail]] = [:]
    /// A day may have genuine market updates whose position impacts cancel to
    /// zero. Keep that state separate from the sparse value index so the UI
    /// does not mistake an interesting $0 day for no movement.
    var daysWithEligibleMarketMovement: Set<Date> = []

    init(
        byDay: [Date: [String: Money]] = [:],
        detailsByDay: [Date: [String: PortfolioContributionDetail]] = [:],
        daysWithEligibleMarketMovement: Set<Date> = []
    ) {
        self.byDay = byDay
        self.detailsByDay = detailsByDay
        self.daysWithEligibleMarketMovement = daysWithEligibleMarketMovement
    }

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

    func movementDetails(in interval: PortfolioAccountingInterval) -> [String: PortfolioContributionDetail] {
        var result: [String: PortfolioContributionDetail] = [:]
        let days = interval.includedClosedDays
            + (interval.includesLiveDay ? [interval.liveDay].compactMap { $0 } : [])

        for day in days {
            if let details = detailsByDay[day] {
                for (key, detail) in details {
                    var combined = result[key, default: PortfolioContributionDetail()]
                    combined.totalImpact += detail.totalImpact
                    combined.cumulativeUnitMovement += detail.cumulativeUnitMovement
                    for quantity in detail.affectedQuantities where !combined.affectedQuantities.contains(quantity) {
                        combined.affectedQuantities.append(quantity)
                    }
                    combined.affectedQuantities.sort()
                    result[key] = combined
                }
            } else {
                // Older in-memory fixtures and imported callers may provide the
                // original money-only projection. Preserve their totals while
                // correctly withholding a made-up unit figure.
                for (key, amount) in byDay[day, default: [:]] {
                    var combined = result[key, default: PortfolioContributionDetail()]
                    combined.totalImpact += amount
                    result[key] = combined
                }
            }
        }
        return result.filter { !$0.value.totalImpact.isZero }
    }
}

struct PortfolioHistoryPoint: Identifiable, Equatable, Sendable {
    /// The calendar day represented by this point, such as Aug 24.
    var displayDay: Date
    /// The economic instant represented by the point: the next midnight for a
    /// published close, or the live summary's current instant.
    var instant: Date
    var value: Money
    /// Additive market movement from the selected period's anchor close.
    /// Unlike performance dollars, this is the same measure used by the
    /// accounting total and holding contributors.
    var cumulativeMarketMovement: Money = .zero
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
    var newlyAddedValue: Money = .zero
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
    var movementDetails: [String: PortfolioContributionDetail] = [:]
    var hasEligibleMarketMovement: Bool

    var isEmpty: Bool { points.isEmpty }

    /// Whether this result actually describes the given selection.
    ///
    /// Results arrive asynchronously, so a view holding one has no guarantee it
    /// still matches what the range control says. Presenting a mismatched
    /// result puts a 1M total under a 3M heading, which a person has no way to
    /// detect — so every period-scoped surface asks this first.
    func matches(range: PortfolioHistoryRange, mode: PortfolioHistoryMode) -> Bool {
        self.range == range && self.mode == mode
    }

    func movement(for collectionKey: String) -> PortfolioContributionDetail? {
        movementDetails[collectionKey]
    }

    func cardMovement(for collectionKey: String) -> PortfolioCardMovementState {
        guard hasTwoPublishedPoints, accountingInterval != nil else {
            return .historyRecording
        }
        guard let detail = movement(for: collectionKey), !detail.totalImpact.isZero else {
            return .noRecordedMarketMovement
        }
        return .recorded(detail)
    }
}

/// Shared display policy for the history presentations. The performance series
/// is a time-weighted index, so its dollar projection is always anchored to the
/// selected period's starting value.
enum PortfolioHistoryDisplay {
    static let performanceUnavailable = "Return isn't available for this period"

    static func periodChange(
        for mode: PortfolioHistoryMode,
        accounting: PortfolioHistoryAccounting,
        performanceFactor: Decimal?
    ) -> Money? {
        switch mode {
        case .marketMovement:
            return accounting.market
        case .value:
            return accounting.totalChange
        case .performance:
            guard let dollars = performanceDollars(
                factor: performanceFactor,
                anchorValue: accounting.anchorValue
            ) else { return nil }
            return Money(rounding: dollars)
        }
    }

    static func percentChange(amount: Money, anchor: Money) -> Double? {
        guard !anchor.isZero else { return nil }
        return amount.doubleValue / anchor.doubleValue
    }

    static func performanceDollars(
        factor: Decimal?,
        anchorValue: Money?
    ) -> Double? {
        guard let factor, let anchorValue, !anchorValue.isZero else { return nil }
        let factorValue = NSDecimalNumber(decimal: factor).doubleValue
        return anchorValue.doubleValue * (factorValue - 1)
    }

    static func hasBreakdown(_ accounting: PortfolioHistoryAccounting) -> Bool {
        !accounting.netInventoryActivity.isZero
            || !accounting.corrections.isZero
            || !accounting.newlyAddedValue.isZero
            || !accounting.pricingAdjustments.isZero
            || !accounting.unexplained.isZero
    }

    static func currencyFractionDigits(forSpan span: Double) -> Int {
        span < 10 ? 2 : 0
    }

    static func signedCurrency(_ amount: Money) -> String {
        let magnitude = amount.magnitude.formatted()
        if amount.tenThousandths < 0 { return "−\(magnitude)" }
        if amount.tenThousandths > 0 { return "+\(magnitude)" }
        return magnitude
    }

    static func signedPercent(_ ratio: Double) -> String {
        let magnitude = abs(ratio).formatted(.percent.precision(.fractionLength(2)))
        if ratio < 0 { return "−\(magnitude)" }
        if ratio > 0 { return "+\(magnitude)" }
        return magnitude
    }
}
