import CryptoKit
import DeviceCheck
import Foundation
import Security

/// Firebase App Check tokens for the pricing proxy, obtained with Apple's App
/// Attest through the App Check REST API.
///
/// The proxy refuses requests without a valid token, so its JustTCG access only
/// serves the genuine app on a real device. This talks to the REST API directly
/// instead of linking the Firebase SDK: the app needs one token header, not a
/// package graph that would weigh on launch time.
///
/// Flow (the same one the Firebase SDK's App Attest provider uses):
/// 1. First use: generate an App Attest key, attest it against a server
///    challenge, and exchange the attestation for a token plus an artifact.
/// 2. Later: sign `SHA256(artifact ‖ challenge)` with the key and exchange the
///    assertion for a fresh token.
/// Tokens are cached until shortly before they expire, and concurrent callers
/// share one exchange. Failures return nil (the proxy then answers 401, which
/// the pricing clients already treat as a failed check) and back off briefly so
/// a bad configuration cannot hammer the token service.
actor PricingAppCheck {
    struct Configuration: Sendable, Equatable {
        let projectNumber: String
        let appID: String
        let apiKey: String
        let bundleID: String

        static let appIDInfoKey = "PRICING_APP_CHECK_APP_ID"
        static let apiKeyInfoKey = "PRICING_APP_CHECK_API_KEY"

        /// `appID` is the Firebase iOS app ID, `1:<project number>:ios:<hex>`.
        static func make(appID rawAppID: String?, apiKey rawAPIKey: String?, bundleID: String?) -> Configuration? {
            let appID = rawAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let apiKey = rawAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = appID.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4,
                  parts[0] == "1",
                  !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber),
                  parts[2] == "ios",
                  !parts[3].isEmpty, parts[3].allSatisfy(\.isHexDigit),
                  !apiKey.isEmpty, !apiKey.contains("$"),
                  apiKey.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                  let bundleID, !bundleID.isEmpty else { return nil }
            return Configuration(projectNumber: String(parts[1]), appID: appID, apiKey: apiKey, bundleID: bundleID)
        }

        static func fromBundle(_ bundle: Bundle = .main) -> Configuration? {
            make(
                appID: bundle.object(forInfoDictionaryKey: appIDInfoKey) as? String,
                apiKey: bundle.object(forInfoDictionaryKey: apiKeyInfoKey) as? String,
                bundleID: bundle.bundleIdentifier
            )
        }
    }

    struct StoredKey: Sendable, Equatable {
        let keyID: String
        let artifact: Data
    }

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared: PricingAppCheck? = Configuration.fromBundle().map { PricingAppCheck(configuration: $0) }

    /// A token this close to expiry is replaced before use.
    static let refreshMargin: TimeInterval = 5 * 60
    /// After a failed exchange, callers get nil without a network attempt for this long.
    static let failureBackoff: TimeInterval = 60

    private let configuration: Configuration
    private let attester: any PricingAppAttester
    private let keyStore: any PricingAppAttestKeyStore
    private let transport: Transport
    private let now: @Sendable () -> Date
    private let debugToken: String?

    private var cached: (token: String, expiry: Date)?
    private var inFlight: Task<String?, Never>?
    private var lastFailure: Date?

    init(
        configuration: Configuration,
        attester: any PricingAppAttester = SystemAppAttester(),
        keyStore: any PricingAppAttestKeyStore = KeychainAppAttestKeyStore(),
        transport: @escaping Transport = PricingAppCheck.defaultTransport,
        now: @escaping @Sendable () -> Date = Date.init,
        debugToken: String? = PricingAppCheck.environmentDebugToken
    ) {
        self.configuration = configuration
        self.attester = attester
        self.keyStore = keyStore
        self.transport = transport
        self.now = now
        self.debugToken = debugToken
    }

    /// A current token, or nil when one cannot be obtained right now.
    func token() async -> String? {
        if let cached, cached.expiry.timeIntervalSince(now()) > Self.refreshMargin { return cached.token }
        if let inFlight { return await inFlight.value }
        if let lastFailure, now().timeIntervalSince(lastFailure) < Self.failureBackoff { return nil }

        let task = Task { await self.exchange() }
        inFlight = task
        let token = await task.value
        inFlight = nil
        return token
    }

    /// Drops the cached token, e.g. after the proxy rejected it.
    func invalidate() {
        cached = nil
    }

    private func exchange() async -> String? {
        do {
            let issued = try await obtainToken()
            cached = (issued.token, now().addingTimeInterval(issued.ttl))
            lastFailure = nil
            return issued.token
        } catch {
            lastFailure = now()
            return nil
        }
    }

    private func obtainToken() async throws -> IssuedToken {
        #if DEBUG
        // Simulators cannot attest. A debug token registered in the Firebase
        // console is supplied through the scheme environment, never committed.
        if let debugToken {
            return try await post("exchangeDebugToken", body: ["debugToken": debugToken], decode: IssuedToken.init)
        }
        #endif
        guard attester.isSupported else { throw AppCheckError.unsupported }

        if let stored = keyStore.load() {
            do {
                return try await assert(with: stored)
            } catch let error as AppCheckError where error.invalidatesKey {
                keyStore.clear()
            } catch let error as DCError where error.code == .invalidKey || error.code == .invalidInput {
                keyStore.clear()
            }
        }
        return try await attest()
    }

    private func attest() async throws -> IssuedToken {
        let keyID = try await attester.generateKey()
        let challenge = try await generateChallenge()
        let statement = try await attester.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: challenge)))
        let result = try await post(
            "exchangeAppAttestAttestation",
            body: [
                "attestationStatement": statement.base64EncodedString(),
                "challenge": challenge.base64EncodedString(),
                "keyId": keyID
            ],
            decode: AttestationResult.init
        )
        keyStore.save(StoredKey(keyID: keyID, artifact: result.artifact))
        return result.token
    }

    private func assert(with stored: StoredKey) async throws -> IssuedToken {
        let challenge = try await generateChallenge()
        let clientData = stored.artifact + challenge
        let assertion = try await attester.generateAssertion(stored.keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
        return try await post(
            "exchangeAppAttestAssertion",
            body: [
                "artifact": stored.artifact.base64EncodedString(),
                "assertion": assertion.base64EncodedString(),
                "challenge": challenge.base64EncodedString()
            ],
            decode: IssuedToken.init
        )
    }

    private func generateChallenge() async throws -> Data {
        try await post("generateAppAttestChallenge", body: [:]) { json in
            guard let encoded = json["challenge"] as? String, let challenge = Data(base64Encoded: encoded), !challenge.isEmpty else {
                throw AppCheckError.malformedResponse
            }
            return challenge
        }
    }

    private func post<T>(_ method: String, body: [String: String], decode: ([String: Any]) throws -> T) async throws -> T {
        let path = "https://firebaseappcheck.googleapis.com/v1/projects/\(configuration.projectNumber)/apps/\(configuration.appID):\(method)"
        guard let url = URL(string: path) else { throw AppCheckError.malformedResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(configuration.bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw AppCheckError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw AppCheckError.rejected(status: http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppCheckError.malformedResponse
        }
        return try decode(json)
    }

    static let defaultTransport: Transport = { request in
        try await tokenSession.data(for: request)
    }

    private static let tokenSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static var environmentDebugToken: String? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment["PRICING_APP_CHECK_DEBUG_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
        #else
        return nil
        #endif
    }
}

private enum AppCheckError: Error {
    case unsupported
    case malformedResponse
    case rejected(status: Int)

    /// The service refused the key or artifact itself (not a quota, outage or
    /// network problem), so a new key must be attested.
    var invalidatesKey: Bool {
        if case let .rejected(status) = self { return [400, 403, 404].contains(status) }
        return false
    }
}

private struct IssuedToken {
    let token: String
    let ttl: TimeInterval

    init(_ json: [String: Any]) throws {
        guard let token = json["token"] as? String, !token.isEmpty else { throw AppCheckError.malformedResponse }
        self.token = token
        ttl = Self.duration(json["ttl"]) ?? 3600
    }

    /// Protobuf JSON durations look like "3600s" or "3600.5s".
    static func duration(_ value: Any?) -> TimeInterval? {
        guard let text = value as? String, text.hasSuffix("s"), let seconds = Double(text.dropLast()), seconds > 0 else { return nil }
        return seconds
    }
}

private struct AttestationResult {
    let token: IssuedToken
    let artifact: Data

    init(_ json: [String: Any]) throws {
        guard let encoded = json["artifact"] as? String,
              let artifact = Data(base64Encoded: encoded), !artifact.isEmpty,
              let token = json["appCheckToken"] as? [String: Any] else { throw AppCheckError.malformedResponse }
        self.token = try IssuedToken(token)
        self.artifact = artifact
    }
}

/// The App Attest operations PricingAppCheck needs; tests substitute a fake.
protocol PricingAppAttester: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct SystemAppAttester: PricingAppAttester {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

/// Where the attested key's ID and its App Check artifact are kept.
protocol PricingAppAttestKeyStore: Sendable {
    func load() -> PricingAppCheck.StoredKey?
    func save(_ key: PricingAppCheck.StoredKey)
    func clear()
}

/// Keychain, readable after first unlock so background price refreshes can
/// authenticate. The item is device-only: an App Attest key never leaves the
/// device, so restoring its artifact elsewhere would only cause a failed exchange.
struct KeychainAppAttestKeyStore: PricingAppAttestKeyStore {
    private let service = "com.tradingcardscanner.pricing"
    private let account = "pricing-proxy.app-attest"

    func load() -> PricingAppCheck.StoredKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let keyID = json["keyID"], !keyID.isEmpty,
              let encoded = json["artifact"], let artifact = Data(base64Encoded: encoded), !artifact.isEmpty else { return nil }
        return PricingAppCheck.StoredKey(keyID: keyID, artifact: artifact)
    }

    func save(_ key: PricingAppCheck.StoredKey) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["keyID": key.keyID, "artifact": key.artifact.base64EncodedString()]) else { return }
        clear()
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
