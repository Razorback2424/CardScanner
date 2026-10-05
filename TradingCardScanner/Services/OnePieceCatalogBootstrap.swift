import CryptoKit
import Foundation
import OnePieceCatalogCore
import OSLog

struct OnePieceCatalogBootstrapConfiguration: Sendable {
    enum ConfigurationError: Error { case missingKeys, invalidKeys, reusedKey, invalidOrigin, missingSeed }
    let mode: OnePieceCatalogRolloutMode
    let keys: [String: Curve25519.Signing.PublicKey]
    let endpoint: URL?
    let collectionWrites: Bool

    init(mode: OnePieceCatalogRolloutMode, pinnedKeys: String?, baseURL: String?,
         forbiddenPublicKeys: Set<Data> = [], collectionWrites: Bool = false) throws {
        self.mode = mode
        self.collectionWrites = mode == .remoteAuthority && collectionWrites
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
            forbiddenPublicKeys: Set(legacyKeys),
            collectionWrites: (bundle.object(forInfoDictionaryKey: "ONE_PIECE_COLLECTION_WRITES") as? String)?.lowercased() == "yes")
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
        localReviewLaunchArguments(arguments: ProcessInfo.processInfo.arguments,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "ONE_PIECE_LOCAL_REVIEW_PUBLIC_KEY") as? String,
            reviewEnabled: Bundle.main.object(forInfoDictionaryKey: "ONE_PIECE_LOCAL_REVIEW_ENABLED") as? Bool == true)
            .contains("-one_piece_local_review")
#else
        false
#endif
    }

#if DEBUG && LOCAL_ONLY_SIGNING
    /// The owner's installed app can use a signed local catalog with its normal
    /// collection. This does not select the isolated review storage paths.
    static func ownerRuntime(bundle: Bundle = .main, seedURL: URL? = nil, preferences: UserDefaults = .standard,
                             now: Date = .now) throws -> CardGameRuntime? {
        guard bundle.bundleIdentifier == "com.seankeller.CardScanner" else { return nil }
        // Ordinary Xcode installs must work on their first launch, without a
        // previous custom install, Documents copy, or saved bootstrap preference.
        if seedURL == nil,
           let bundledSeed = bundle.url(forResource: "one-piece-owner-catalog", withExtension: "json", subdirectory: "OnePieceOwnerCatalog"),
           let pinsURL = bundle.url(forResource: "public-keys", withExtension: "json", subdirectory: "OnePieceOwnerCatalog") {
            let pins = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: pinsURL))
            guard let pin = pins["one-piece-local-review"] else {
                throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingKeys
            }
            return try localReviewRuntime(arguments: ["-one_piece_local_review", "-one_piece_review_seed", bundledSeed.path,
                                                      "-one_piece_review_public_key", pin], bundle: bundle, now: now)
        }
        let configured = bundle.object(forInfoDictionaryKey: "ONE_PIECE_OWNER_CATALOG_ENABLED") as? Bool == true
        guard configured || preferences.bool(forKey: "onePieceOwnerCatalogEnabled") else { return nil }
        let publicKey = configured
            ? bundle.object(forInfoDictionaryKey: "ONE_PIECE_OWNER_CATALOG_PUBLIC_KEY") as? String
            : preferences.string(forKey: "onePieceOwnerCatalogPublicKey")
        guard let publicKey,
              !publicKey.isEmpty else { throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingKeys }
        let url = seedURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("one-piece-owner-catalog.json")
        let runtime = try localReviewRuntime(arguments: ["-one_piece_local_review", "-one_piece_review_seed", url.path,
                                                  "-one_piece_review_public_key", publicKey], bundle: bundle, now: now)
        // Retain only the successfully verified public authority so the owner's
        // subsequent ordinary app builds keep One Piece without custom flags.
        preferences.set(publicKey, forKey: "onePieceOwnerCatalogPublicKey")
        preferences.set(true, forKey: "onePieceOwnerCatalogEnabled")
        return runtime
    }

    /// A signed debug review configuration can reopen from the Home Screen.
    /// Reusing the ordinary app identity requires an explicit review opt-in.
    static func localReviewLaunchArguments(arguments: [String], bundleIdentifier: String?, publicKey: String?,
                                          reviewEnabled: Bool = false) -> [String] {
        guard !arguments.contains("-one_piece_local_review"),
              bundleIdentifier == "com.seankeller.CardScanner.OnePieceReview"
                || (bundleIdentifier == "com.seankeller.CardScanner" && reviewEnabled),
              let publicKey, !publicKey.isEmpty else { return arguments }
        return arguments + ["-one_piece_local_review", "-one_piece_review_seed", "Documents/one-piece-local-review.json",
                            "-one_piece_review_public_key", publicKey]
    }

    static func localReviewRuntime(arguments: [String] = ProcessInfo.processInfo.arguments,
                                   bundle: Bundle = .main,
                                   now: Date = .now) throws -> CardGameRuntime? {
        let arguments = localReviewLaunchArguments(arguments: arguments, bundleIdentifier: bundle.bundleIdentifier,
            publicKey: bundle.object(forInfoDictionaryKey: "ONE_PIECE_LOCAL_REVIEW_PUBLIC_KEY") as? String,
            reviewEnabled: bundle.object(forInfoDictionaryKey: "ONE_PIECE_LOCAL_REVIEW_ENABLED") as? Bool == true)
        guard arguments.contains("-one_piece_local_review") else { return nil }
        func value(_ flag: String) throws -> String {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingSeed
            }
            return arguments[index + 1]
        }
        let seedPath = try value("-one_piece_review_seed")
        let seedURL: URL
        if seedPath == "Documents/one-piece-local-review.json" {
            seedURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("one-piece-local-review.json")
        } else { seedURL = URL(fileURLWithPath: seedPath) }
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
        let started = Date()
        let envelope = try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: seed)
        let decoded = Date()
        let store = try OnePieceCatalogReleaseStore(root: root, keys: configuration.keys, bundledEnvelope: envelope, now: now)
        let indexed = Date()
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
            .info("One Piece seed bytes=\(seed.count, privacy: .public) envelope_decode_ms=\(decoded.timeIntervalSince(started) * 1_000, privacy: .public) verify_index_ms=\(indexed.timeIntervalSince(decoded) * 1_000, privacy: .public)")
        guard let registry = store.bundledRegistry else {
            throw OnePieceCatalogBootstrapConfiguration.ConfigurationError.missingSeed
        }
        let client = try configuration.endpoint.map { try OnePieceCatalogUpdateClient(endpoint: $0) }
        let coordinator = OnePieceCatalogCoordinator(store: store, client: client, rolloutMode: configuration.mode)
        // The store has already verified and indexed this bundled envelope.
        var module = OnePieceGameRuntime(registry: registry, coordinator: coordinator)
        if configuration.mode == .remoteValidationOnly { module.capabilities = [] }
        if configuration.collectionWrites { module.capabilities.insert(.collectionWrite) }
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
