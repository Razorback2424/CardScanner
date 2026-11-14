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
    private static let cacheLock = NSLock()
    private static var cachedHasKey: Bool?

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

    /// A temporary Keychain access error is not proof of a missing vendor key.
    /// Returning nil deliberately leaves the cache unset for a later retry.
    static func cacheablePresence(status: OSStatus, key: String?) -> Bool? {
        switch status {
        case errSecItemNotFound:
            return false
        case errSecSuccess:
            return key?.isEmpty == false ? true : nil
        default:
            return nil
        }
    }

    static var hasKey: Bool { keyPresence == true }

    static var keyPresence: Bool? {
        cacheLock.lock()
        if let cachedHasKey {
            cacheLock.unlock()
            return cachedHasKey
        }
        cacheLock.unlock()

        let read = readKey()
        let presence = cacheablePresence(status: read.status, key: read.key)
        cacheLock.lock()
        // Store/remove may have updated the value during the Keychain read.
        if cachedHasKey == nil { cachedHasKey = presence }
        let available = cachedHasKey
        cacheLock.unlock()
        return available
    }

    static var key: String? { readKey().key }

    private static func readKey() -> (status: OSStatus, key: String?) {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return (status, nil)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (status, trimmed.isEmpty ? nil : trimmed)
    }

    /// Storing an empty string removes the key, so the settings field clearing to
    /// blank means "forget this" rather than "save nothing".
    static func store(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove()
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            setCachedHasKey(true)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.storeFailed(updateStatus)
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = accessibility

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialError.storeFailed(addStatus)
        }
        setCachedHasKey(true)
    }

    @discardableResult
    static func remove() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        let succeeded = status == errSecSuccess || status == errSecItemNotFound
        if succeeded { setCachedHasKey(false) }
        return succeeded
    }

    private static func setCachedHasKey(_ value: Bool) {
        cacheLock.lock()
        cachedHasKey = value
        cacheLock.unlock()
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
