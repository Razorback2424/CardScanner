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

    public static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }
}
