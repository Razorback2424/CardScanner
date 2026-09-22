import Foundation

struct ResolvedBrowsePriceDay: Equatable, Sendable {
    let day: BrowsePriceDay
    let providerUpdatedAt: Date
}
/// Converts provider freshness metadata into the date-only UTC identity used by
/// Browse history. A nil result is intentional: callers must skip history rather
/// than substitute the ordinary HTTP fetch time.
enum BrowsePriceObservationDayResolver {
    static func pokemonTCGIO(updatedAt: String?) -> ResolvedBrowsePriceDay? {
        guard let updatedAt,
              let date = parsePokemonDate(updatedAt) else { return nil }
        return resolved(date)
    }

    static func tcgdex(updatedAt: Date?) -> ResolvedBrowsePriceDay? {
        updatedAt.map(resolved)
    }

    /// Scryfall's bulk-data stamp is an approximate dataset day, not exact
    /// per-card price provenance. The distinction is kept in the transport and
    /// UI copy rather than pretending this is a card-level timestamp.
    static func scryfallDataset(updatedAt: Date?) -> ResolvedBrowsePriceDay? {
        updatedAt.map(resolved)
    }

    private static func resolved(_ date: Date) -> ResolvedBrowsePriceDay {
        ResolvedBrowsePriceDay(
            day: BrowsePriceDay(date: date),
            providerUpdatedAt: date
        )
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
