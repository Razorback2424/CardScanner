import Foundation
import Security

/// Local record of "which Apple ID this app considers signed in."
///
/// This does not carry the collection anywhere by itself — CloudKit's private
/// database does that, using whichever iCloud account is signed into the
/// device. What this store is for is deciding, once per launch, whether
/// `TradingCardScannerApp` should hand SwiftData a CloudKit-backed
/// configuration or a local-only one (see `makeContainer()`), and letting the
/// Settings screen show "Signed in" state honestly.
///
/// Keychain rather than `UserDefaults`, for the same reason as
/// `PriceVendorCredentials`: this is durable identity, not disposable UI
/// state, and it should survive the same way an API key does.
enum AppleAccountCredentials {
    private static let service = "com.tradingcardscanner.account"
    private static let identifierAccount = "apple.user-identifier"
    private static let displayNameAccount = "apple.display-name"

    /// Background-eligible for the same reason as the pricing vendor key: a
    /// future background sync task should not silently stop working just
    /// because the phone is locked.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlock

    enum CredentialError: LocalizedError {
        case storeFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .storeFailed:
                return "The Apple ID could not be saved to the keychain."
            }
        }
    }

    /// Apple's stable, opaque per-app-per-user identifier from Sign in with
    /// Apple. Not the person's Apple ID email — Apple does not hand that out
    /// beyond the optional one-time name/email at first authorization.
    static var userIdentifier: String? { read(account: identifierAccount) }

    /// Only ever populated from the *first* authorization — Apple does not
    /// return the name again on later sign-ins to the same app, so this is
    /// the one chance to keep it.
    static var displayName: String? { read(account: displayNameAccount) }

    static var isSignedIn: Bool { userIdentifier?.isEmpty == false }

    static func store(userIdentifier: String, displayName: String?) throws {
        try write(userIdentifier, account: identifierAccount)
        if let displayName, !displayName.isEmpty {
            try write(displayName, account: displayNameAccount)
        }
    }

    static func clear() {
        remove(account: identifierAccount)
        remove(account: displayNameAccount)
    }

    // MARK: - Keychain primitives

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
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

    private static func write(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = baseQuery(account: account)

        // Delete-then-add rather than SecItemUpdate: one path instead of two,
        // and it cannot leave a stale attribute behind from an earlier write.
        SecItemDelete(query as CFDictionary)

        guard !trimmed.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = accessibility

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.storeFailed(status)
        }
    }

    @discardableResult
    private static func remove(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
