import Foundation
import Security

/// Storage for the price vendor's API key.
///
/// Keychain rather than `UserDefaults`/`@AppStorage`, which write plaintext into
/// a file that is trivially readable from a backup. The key is a billable
/// credential tied to a quota, so it is treated as a secret even in a personal
/// build.
///
/// The value is deliberately hard to leak: it is never logged, never included in
/// diagnostics or CSV exports, and `hasKey` exists so the UI can report whether a
/// key is present without reading it back.
enum PriceVendorCredentials {
    /// Scoped to this app and this vendor, so adding a second vendor later does
    /// not collide with — or silently overwrite — this one.
    private static let service = "com.tradingcardscanner.pricing"
    private static let account = "justtcg.api-key"

    /// `kSecAttrAccessibleAfterFirstUnlock` rather than `WhenUnlocked`: price
    /// refreshes run in the background, and a key readable only while the phone
    /// is unlocked would make them fail silently in exactly that case.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlock

    enum CredentialError: LocalizedError {
        case storeFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .storeFailed:
                return "The API key could not be saved to the keychain."
            }
        }
    }

    static var hasKey: Bool {
        key?.isEmpty == false
    }

    static var key: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Storing an empty string removes the key, so the settings field clearing to
    /// blank means "forget this" rather than "save nothing".
    static func store(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove()
            return
        }

        // Delete-then-add rather than SecItemUpdate: it is one path instead of
        // two, and it cannot leave a stale attribute behind from an earlier write.
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = accessibility

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.storeFailed(status)
        }
    }

    @discardableResult
    static func remove() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
