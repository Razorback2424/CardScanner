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

    /// Whether JustTCG-backed features can run. Through the pricing proxy the
    /// operator holds the credential, so access never depends on a customer key.
    static var hasKey: Bool { keyPresence == true }

    static var keyPresence: Bool? {
        if PricingProxy.isEnabled { return true }
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

/// Operator-funded JustTCG access through the Card Scanner pricing proxy
/// (`pricing-proxy/` in the repository).
///
/// When a build sets `JUSTTCG_PROXY_BASE_URL`, every JustTCG request goes
/// through the proxy: the operator's key stays on the server, customers never
/// need an account or key, and any key saved by an older build is removed.
/// While the setting is empty (until launch preparation) the legacy
/// customer-key path remains for development builds.
enum PricingProxy {
    struct Endpoint: Sendable, Equatable {
        /// Ends in `/v1/justtcg`; JustTCG paths such as `v1/cards` append to it.
        let baseURL: URL
        let installID: String
    }

    static let infoKey = "JUSTTCG_PROXY_BASE_URL"

    static let configured: Endpoint? = baseURL(
        from: Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
    ).map { Endpoint(baseURL: $0, installID: installID) }

    static var isEnabled: Bool { configured != nil }

    /// The proxy caches a current quote for at most an hour. Delta refresh
    /// cutoffs widen by this much so an update published after a cached answer
    /// was fetched is still requested. Keep it at or above the proxy's quote TTL.
    static let maximumCachedQuoteAge: TimeInterval = 2 * 60 * 60

    static func baseURL(from value: String?) -> URL? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.hasSuffix("/v1/justtcg") else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        // The Firebase emulator serves plain HTTP on this Mac.
        if url.scheme == "http", ["localhost", "127.0.0.1"].contains(host) { return url }
        #endif
        return nil
    }

    private static let installIDKey = "pricingProxy.installID"

    /// A random identifier used only for the proxy's per-install throttling.
    /// It is not tied to an account and the proxy keeps only a salted hash.
    static var installID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIDKey), !existing.isEmpty { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: installIDKey)
        return created
    }

    /// A Firebase App Check token (App Attest) proving the request comes from
    /// the genuine app; see `PricingAppCheck`. Nil until the build sets
    /// `PRICING_APP_CHECK_APP_ID` and `PRICING_APP_CHECK_API_KEY` at launch
    /// preparation; the local emulator accepts requests without one.
    static func appCheckToken() async -> String? {
        await PricingAppCheck.shared?.token()
    }

    /// The proxy rejected the request's App Check token: the next request
    /// fetches a new one instead of reusing it.
    static func noteRejection(_ response: HTTPURLResponse) async {
        guard response.statusCode == 401 else { return }
        await PricingAppCheck.shared?.invalidate()
    }

    static func authorize(_ request: inout URLRequest, endpoint: Endpoint, lane: JustTCGRequestLane) async {
        request.setValue(endpoint.installID, forHTTPHeaderField: "X-ScanStash-Install")
        request.setValue(lane == .background ? "background" : "interactive", forHTTPHeaderField: "X-ScanStash-Lane")
        if let token = await appCheckToken() {
            request.setValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
    }

    /// Part of the body is past the proxy's freshness window. It may be shown
    /// with its real age, but it is never evidence of a successful check.
    static func isStale(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "X-ScanStash-Cache")?.lowercased() == "stale"
    }

    /// Launch-time setup for proxy builds: JustTCG gap filling is on by default
    /// (an explicit user choice is kept), and a customer key saved by an
    /// earlier build is deleted because it is never used again.
    static func prepareAtLaunch(defaults: UserDefaults = .standard) {
        guard isEnabled else { return }
        defaults.register(defaults: ["usesPriceFallback": true])
        let retiredKey = "pricingProxy.customerKeyRetired"
        guard !defaults.bool(forKey: retiredKey) else { return }
        if PriceVendorCredentials.remove() {
            defaults.set(true, forKey: retiredKey)
        }
    }
}
