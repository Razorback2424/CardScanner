import Foundation

/// The timezone every portfolio day boundary is measured in, captured once and
/// then never moved.
///
/// A portfolio day is a published fact. If the boundary followed the device's
/// current timezone, flying to Berlin would silently re-cut every historical
/// day and rewrite closes that were already shown — months of numbers changing
/// because of a flight is exactly the kind of thing a ledger exists to prevent.
/// So the zone is stamped when tracking starts, stored, and read back
/// thereafter; a permanent relocation is a later feature handled by timezone
/// *epochs* ("Mountain through Dec 31 · Eastern from Jan 1"), never by
/// reinterpreting days that have already been published.
enum PortfolioCalendar {
    static let defaultsKey = "portfolioTimeZoneIdentifier"

    /// The zone in force. Captures the device's current zone the first time
    /// anything asks, which is the moment portfolio tracking begins.
    static func timeZone(defaults: UserDefaults = .standard) -> TimeZone {
        if let identifier = defaults.string(forKey: defaultsKey),
           let stored = TimeZone(identifier: identifier) {
            return stored
        }
        let current = TimeZone.current
        defaults.set(current.identifier, forKey: defaultsKey)
        return current
    }

    /// Reads the pinned zone without creating one. Used by anything that must
    /// not itself start the epoch — diagnostics and read-only settings rows.
    static func pinnedTimeZone(defaults: UserDefaults = .standard) -> TimeZone? {
        defaults.string(forKey: defaultsKey).flatMap(TimeZone.init(identifier:))
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The portfolio day `date` falls in. Days are half-open `[start, next)`,
    /// so an event landing exactly on the next day's `startOfDay` belongs to
    /// the next day — never to both and never to neither.
    nonisolated static func day(containing date: Date, in timeZone: TimeZone) -> Date {
        calendar(in: timeZone).startOfDay(for: date)
    }

    /// The cutoff that closes day `day`: the start of the following day.
    ///
    /// Computed by adding one calendar day and re-taking `startOfDay` rather
    /// than adding 86,400 seconds, so spring-forward and fall-back days close
    /// at midnight rather than at 11 PM or 1 AM.
    nonisolated static func boundary(afterDay day: Date, in timeZone: TimeZone) -> Date {
        let calendar = calendar(in: timeZone)
        let start = calendar.startOfDay(for: day)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else {
            return start.addingTimeInterval(24 * 60 * 60)
        }
        return calendar.startOfDay(for: next)
    }
}
