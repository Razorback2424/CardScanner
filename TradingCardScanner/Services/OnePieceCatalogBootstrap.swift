import CryptoKit
import Foundation
import OnePieceCatalogCore

struct OnePieceCatalogBootstrapConfiguration: Sendable {
    enum ConfigurationError: Error { case missingKeys, invalidKeys, reusedKey, invalidOrigin, missingSeed }
    let mode: OnePieceCatalogRolloutMode
    let keys: [String: Curve25519.Signing.PublicKey]
    let endpoint: URL?

    init(mode: OnePieceCatalogRolloutMode, pinnedKeys: String?, baseURL: String?,
         forbiddenPublicKeys: Set<Data> = []) throws {
        self.mode = mode
        guard mode != .disabled else { keys = [:]; endpoint = nil; return }
        guard let pinnedKeys, !pinnedKeys.isEmpty else { throw ConfigurationError.missingKeys }
        var keys: [String: Curve25519.Signing.PublicKey] = [:]
        for entry in pinnedKeys.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ConfigurationError.invalidKeys }
            let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard id.hasPrefix("one-piece-"), id.count > "one-piece-".count, keys[id] == nil,
                  let bytes = Self.keyBytes(String(parts[1])), bytes.count == 32 else { throw ConfigurationError.invalidKeys }
            guard !forbiddenPublicKeys.contains(bytes) else { throw ConfigurationError.reusedKey }
            keys[id] = try Curve25519.Signing.PublicKey(rawRepresentation: bytes)
        }
        guard let baseURL, let url = URL(string: baseURL),
              url.scheme == "https", ["scanstash-catalog-prod.web.app", "catalog.scan-stash.com"].contains(url.host ?? ""), url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw ConfigurationError.invalidOrigin }
        self.keys = keys
        endpoint = url.appendingPathComponent("one-piece/v1/current.json")
    }

    static func configured(bundle: Bundle) throws -> Self {
        let mode = OnePieceCatalogRolloutMode.from(rawValue: bundle.object(forInfoDictionaryKey: "ONE_PIECE_CATALOG_ROLLOUT_MODE") as? String)
        let legacyKeys = ["POKEMON_CATALOG_PINNED_KEYS", "MAGIC_CATALOG_PINNED_KEYS"].compactMap {
            bundle.object(forInfoDictionaryKey: $0) as? String
        }.flatMap { $0.split(separator: ",") }.compactMap { entry -> Data? in
            guard let encoded = entry.split(separator: ":").last else { return nil }
            return keyBytes(String(encoded))
        }
        return try .init(mode: mode, pinnedKeys: bundle.object(forInfoDictionaryKey: "ONE_PIECE_CATALOG_PINNED_KEYS") as? String,
            baseURL: bundle.object(forInfoDictionaryKey: "ONE_PIECE_CATALOG_BASE_URL") as? String,
            forbiddenPublicKeys: Set(legacyKeys))
    }

    private static func keyBytes(_ value: String) -> Data? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4))
    }
}

enum OnePieceCatalogBootstrap {
    /// Review launches are available only in a debug binary with no CloudKit
    /// entitlement. They use a separate persistent store and never fetch updates.
    static var isLocalReviewLaunch: Bool {
#if DEBUG && LOCAL_ONLY_SIGNING
        ProcessInfo.processInfo.arguments.contains("-one_piece_local_review")
#else
        false
#endif
    }

#if DEBUG && LOCAL_ONLY_SIGNING
    static func localReviewRuntime(arguments: [String] = ProcessInfo.processInfo.arguments,
                                   now: Date = .now) throws -> CardGameRuntime? {
        guard arguments.contains("-one_piece_local_review") else { return nil }
        func value(_ flag: String) throws -> String {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingSeed
            }
            return arguments[index + 1]
        }
        let seedURL = URL(fileURLWithPath: try value("-one_piece_review_seed"))
        let configuration = try OnePieceCatalogBootstrapConfiguration(mode: .remoteAuthority,
            pinnedKeys: "one-piece-local-review:\(try value("-one_piece_review_public_key"))",
            baseURL: "https://scanstash-catalog-prod.web.app")
        let handle = try FileHandle(forReadingFrom: seedURL)
        defer { try? handle.close() }
        let seed = try handle.read(upToCount: 48 * 1_024 * 1_024 + 1) ?? Data()
        guard seed.count <= 48 * 1_024 * 1_024 else { throw OnePieceCatalogSignatureError.oversizedPayload }
        let envelope = try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: seed)
        let verified = try OnePieceCatalogSignature.verify(envelope, trustedKeys: configuration.keys, now: now)
        return OnePieceGameRuntime(registry: .init(verifiedRelease: verified),
            capabilities: [.scan, .browse, .collectionWrite, .pricing]).runtime
    }
#endif

    static func runtime(configuration: OnePieceCatalogBootstrapConfiguration, seed: Data?,
                        root: URL? = nil, now: Date = .now) throws -> CardGameRuntime? {
        guard configuration.mode != .disabled else { return nil }
        guard let seed, seed.count <= 48 * 1_024 * 1_024 else {
            throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingSeed
        }
        let envelope = try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: seed)
        let verified = try OnePieceCatalogSignature.verify(envelope, trustedKeys: configuration.keys, now: now)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: configuration.keys, bundledEnvelope: envelope, now: now)
        let client = try configuration.endpoint.map { try OnePieceCatalogUpdateClient(endpoint: $0) }
        let coordinator = OnePieceCatalogCoordinator(store: store, client: client, rolloutMode: configuration.mode)
        var module = OnePieceGameRuntime(registry: .init(verifiedRelease: verified), coordinator: coordinator)
        if configuration.mode == .remoteValidationOnly { module.capabilities = [] }
        return module.runtime
    }

    static func configuredRuntime(bundle: Bundle = .main) throws -> CardGameRuntime? {
        let configuration = try OnePieceCatalogBootstrapConfiguration.configured(bundle: bundle)
        guard configuration.mode != .disabled else { return nil }
        guard let url = bundle.url(forResource: "one-piece-catalog-release", withExtension: "json") else {
            throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingSeed
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try runtime(configuration: configuration, seed: handle.read(upToCount: 48 * 1_024 * 1_024 + 1))
    }
}
