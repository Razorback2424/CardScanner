import Foundation

/// Parses the provider's original freshness timestamp; invalid dates remain
/// unknown rather than being replaced with the HTTP retrieval time.
enum BrowsePriceObservationDayResolver {
    static func pokemonTCGIO(updatedAt: String?) -> Date? {
        guard let updatedAt,
              let date = parsePokemonDate(updatedAt) else { return nil }
        return date
    }

    private static func parsePokemonDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let slashParts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if slashParts.count == 3,
           slashParts[0].count == 4,
           slashParts[1].count == 2,
           slashParts[2].count == 2,
           let year = Int(slashParts[0]),
           let month = Int(slashParts[1]),
           let day = Int(slashParts[2]) {
            return utcDate(year: year, month: month, day: day)
        }
        return FlexibleDate.parse(trimmed)
    }

    private static func utcDate(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date).year == year,
              calendar.dateComponents([.year, .month, .day], from: date).month == month,
              calendar.dateComponents([.year, .month, .day], from: date).day == day else {
            return nil
        }
        return date
    }
}
