import Foundation
import SwiftData

/// Evidence that the app successfully asked about one instrument on one
/// portfolio day.
///
/// Coverage — "1,276 of 1,284 repriced today · 8 carried forward" — has to come
/// from persisted evidence of *success*, never from a last-checked timestamp.
/// A field that records both success and failure cannot answer the question: a
/// 3 PM failure would report as refreshed and simultaneously erase the proof of
/// a good 9 AM check. It also has to survive the day: whether iOS happens to
/// schedule the close computation before or after the next morning's refresh is
/// not something a financial record can depend on.
///
/// One row per instrument per day is a lot of small rows. That is a deliberate
/// trade — correctness first, and measure the size before compacting it.
@Model
final class PriceCheckDay {
    var instrumentKey: String = ""
    /// `startOfDay` in the portfolio timezone. See `PortfolioCalendar`.
    var portfolioDay: Date = Date.now
    var lastSuccessfulCheckAt: Date = Date.now
    var sourceRaw: String = ""

    init(
        instrumentKey: String,
        portfolioDay: Date,
        lastSuccessfulCheckAt: Date,
        source: PriceSource?
    ) {
        self.instrumentKey = instrumentKey
        self.portfolioDay = portfolioDay
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
        self.sourceRaw = source?.rawValue ?? ""
    }

    var source: PriceSource? { PriceSource(rawValue: sourceRaw) }
}
