import Foundation

public enum OnePieceTextNormalization {
    /// Exact printed-number normalization. OCR confusion repair belongs to the
    /// recognizer and may only occur after a registry-supported prefix is known.
    public static func printedNumber(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: "^[A-Z]{1,8}[0-9]{0,3}-[0-9]{3}$", options: .regularExpression) != nil,
              !normalized.hasPrefix("DON-") else { return nil }
        return normalized
    }

    public static func prefix(of number: String) -> String? {
        guard let number = printedNumber(number) else { return nil }
        return String(number.prefix { $0 != "-" })
    }

    /// Strict publisher calendar day. DateFormatter alone can normalize an
    /// impossible date or accept a differently shaped date silently.
    public static func releaseDate(_ value: String) -> Date? {
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    public static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }
}
