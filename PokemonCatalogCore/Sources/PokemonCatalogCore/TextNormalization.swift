import Foundation

/// Shared normalization used by membership validation and cross-provider set
/// matching. Keeping it here prevents the two safety-sensitive call sites from
/// acquiring subtly different folding rules.
public enum PokemonCatalogTextNormalization {
    public static func canonicalMembershipName(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).replacingOccurrences(of: "&", with: " and ")
        return folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        .joined()
        .split(whereSeparator: { $0 == " " })
        .joined(separator: " ")
    }

    public static func normalizedCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return result.isEmpty ? nil : result
    }

    /// Returns a UTC calendar date in the provider-neutral yyyy-MM-dd form.
    public static func normalizedDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let datePrefix = String(trimmed.prefix(10)).replacingOccurrences(of: "/", with: "-")
        let parts = datePrefix.split(separator: "-")
        if parts.count == 3,
           parts[0].count == 4,
           parts[1].count == 2,
           parts[2].count == 2,
           let year = Int(parts[0]),
           let month = Int(parts[1]),
           let day = Int(parts[2]) {
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(secondsFromGMT: 0)
            components.year = year
            components.month = month
            components.day = day
            guard let date = components.calendar?.date(from: components) else { return nil }
            return format(date)
        }

        guard let date = ISO8601DateFormatter().date(from: trimmed) else { return nil }
        return format(date)
    }

    public static func date(_ value: String?) -> Date? {
        guard let normalized = normalizedDate(value) else { return nil }
        let parts = normalized.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.calendar?.date(from: components)
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
