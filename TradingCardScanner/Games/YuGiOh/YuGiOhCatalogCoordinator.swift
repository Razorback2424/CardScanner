import CryptoKit
import Foundation

/// An injected, approved-only integration. App defaults intentionally retain
/// the bundle until owner trust configuration and activation acceptance exist.
actor YuGiOhCatalogCoordinator: GameCatalogActivationSource {
    nonisolated var game: CardGame { .yuGiOh }
    enum RefreshResult: Sendable { case disabled, notModified, activated(Int), rejected }
    private let store: YuGiOhCandidateReleaseStore
    private let client: SignedCatalogUpdateClient<YuGiOhCandidateEnvelope>?
    private var task: Task<RefreshResult, Never>?
    private var taskID: UUID?
    private var launched = false
    private var cached: GameCatalogSnapshot?
    private var continuations: [UUID: AsyncStream<GameCatalogSnapshot>.Continuation] = [:]
    #if DEBUG
    private var didCoalesceForTesting: (@Sendable () -> Void)?
    func setCoalescingObserverForTesting(_ observer: @escaping @Sendable () -> Void) {
        didCoalesceForTesting = observer
    }
    #endif

    init(root: URL, keys: [String: Curve25519.Signing.PublicKey], bundledBytes: Data,
         endpoint: URL? = nil, configuration: URLSessionConfiguration = .ephemeral,
         bundledCatalog: YuGiOhCatalog? = nil) throws {
        let bundle = try bundledCatalog ?? YuGiOhCatalog(data: bundledBytes)
        store = try .init(root: root, keys: keys, bundled: bundle, state: .approved,
            bundledSHA256: YuGiOhReleaseWire.hash(bundledBytes))
        client = try endpoint.map { try .init(endpoint: $0, configuration: configuration,
            maximumBytes: YuGiOhReleaseWire.maximumEnvelopeBytes) }
    }

    func catalog() async -> YuGiOhCatalog { await store.snapshot().catalog }

    func currentSnapshot() async -> GameCatalogSnapshot? {
        let value = await store.snapshot()
        let revision = value.catalog.publicationRevision ?? 0
        if let cached, cached.revision >= revision { return cached }
        let catalog = value.catalog
        let snapshot = GameCatalogSnapshot(revision: revision, catalog: YuGiOhCatalogAdapter(catalog: catalog),
            recognizer: YuGiOhRecognitionAdapter(catalog: catalog), variantPolicy: YuGiOhVariantPolicy(),
            browse: YuGiOhBrowseAdapter(catalog: catalog), importer: YuGiOhImportAdapter(catalog: catalog),
            priceAuthority: value.priceAuthority, capabilities: YuGiOhGameRuntime.capabilities(for: catalog))
        cached = snapshot
        return snapshot
    }

    func activationSnapshots() -> AsyncStream<GameCatalogSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: GameCatalogSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return stream
    }
    private func remove(_ id: UUID) { continuations.removeValue(forKey: id) }

    func refreshAtLaunch() async {
        guard !launched else { return }
        launched = true
        _ = await refresh()
    }

    func refresh() async -> RefreshResult {
        guard let client, !Task.isCancelled else { return .disabled }
        let shared: Task<RefreshResult, Never>
        let id: UUID
        if let task, let taskID {
            shared = task; id = taskID
            #if DEBUG
            didCoalesceForTesting?()
            #endif
        }
        else {
            let next = Task { await self.fetch(client) }
            task = next
            id = UUID(); taskID = id
            shared = next
        }
        let result = await withTaskCancellationHandler { await shared.value } onCancel: { shared.cancel() }
        if taskID == id { task = nil; taskID = nil }
        return result
    }

    private func fetch(_ client: SignedCatalogUpdateClient<YuGiOhCandidateEnvelope>) async -> RefreshResult {
        do {
            switch try await client.fetch() {
            case .notModified: return .notModified
            case let .fetched(envelope):
                try Task.checkCancellation()
                return try await activate(envelope)
            }
        } catch {
            await client.resetConditionalState()
            return .rejected
        }
    }

    /// Actor-isolated parsing and signature checks keep the full corpus off the
    /// UI executor. Container-bound consumers still cross the existing atomic
    /// collection/price authority boundary before seeing this snapshot.
    func activate(_ envelope: YuGiOhCandidateEnvelope, now: Date = .now) async throws -> RefreshResult {
        try Task.checkCancellation()
        let result = try await store.stage(envelope, now: now)
        guard case .activated = result, let snapshot = await currentSnapshot() else { return .notModified }
        for continuation in continuations.values { continuation.yield(snapshot) }
        return .activated(snapshot.revision)
    }
}

enum YuGiOhCatalogBootstrap {
    enum ConfigurationError: Error { case mode, keys, origin, seed }

    /// No endpoint or key is supplied by default. Production must explicitly
    /// provide dedicated owner pins and opt into approved authority. Acceptance
    /// launches retain the bundle even in a configured debug build.
    static func configuredRuntime(bundled: YuGiOhCatalog, bundle: Bundle = .main) throws -> CardGameRuntime? {
        #if DEBUG && LOCAL_ONLY_SIGNING
        if YuGiOhAcceptanceLaunch.enabled { return nil }
        #endif
        guard let mode = bundle.object(forInfoDictionaryKey: "YUGIOH_CATALOG_ROLLOUT_MODE") as? String,
              !mode.isEmpty, mode != "disabled" else { return nil }
        guard mode == "approved" else { throw ConfigurationError.mode }
        let keys = try productionKeys(bundle.object(forInfoDictionaryKey: "YUGIOH_CATALOG_PINNED_KEYS") as? String)
        let endpoint = try productionEndpoint(bundle.object(forInfoDictionaryKey: "YUGIOH_CATALOG_BASE_URL") as? String)
        guard let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed") else { throw ConfigurationError.seed }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let bytes = try file.read(upToCount: YuGiOhReleaseWire.maximumCatalogBytes + 1) ?? Data()
        guard bytes.count <= YuGiOhReleaseWire.maximumCatalogBytes else { throw ConfigurationError.seed }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuGiOhApprovedCatalog")
        let coordinator = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bytes,
            endpoint: endpoint, bundledCatalog: bundled)
        return YuGiOhGameRuntime(catalog: bundled, coordinator: coordinator).runtime
    }

    static func productionKeys(_ text: String?) throws -> [String: Curve25519.Signing.PublicKey] {
        guard let text, !text.isEmpty else { throw ConfigurationError.keys }
        var result: [String: Curve25519.Signing.PublicKey] = [:]
        let publicTestVector = Data([0xd7,0x5a,0x98,0x01,0x82,0xb1,0x0a,0xb7,0xd5,0x4b,0xfe,0xd3,0xc9,0x64,0x07,0x3a,
                                    0x0e,0xe1,0x72,0xf3,0xda,0xa6,0x23,0x25,0xaf,0x02,0x1a,0x68,0xf7,0x07,0x51,0x1a])
        for entry in text.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ConfigurationError.keys }
            let id = String(parts[0])
            guard id.range(of: "^yugioh-production-[a-z0-9][a-z0-9-]{0,40}$", options: .regularExpression) != nil,
                  result[id] == nil, let bytes = Data(base64Encoded: String(parts[1])), bytes.count == 32,
                  bytes != publicTestVector else { throw ConfigurationError.keys }
            result[id] = try .init(rawRepresentation: bytes)
        }
        guard Set(result.values.map(\.rawRepresentation)).count == result.count else { throw ConfigurationError.keys }
        return result
    }
    static func productionEndpoint(_ text: String?) throws -> URL {
        guard let text, let base = URL(string: text), base.scheme == "https",
              ["scanstash-catalog-prod.web.app", "catalog.scan-stash.com"].contains(base.host ?? ""),
              base.port == nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.path.isEmpty || base.path == "/" else { throw ConfigurationError.origin }
        return base.appendingPathComponent("yugioh/v1/current.json")
    }
}
