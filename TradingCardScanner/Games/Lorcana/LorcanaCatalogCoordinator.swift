import Foundation

protocol LorcanaCatalogUpdateFetching: Sendable {
    func fetch() async throws -> SignedCatalogFetchResult<LorcanaCatalogReleaseEnvelope>
    func resetConditionalState() async
}

actor LorcanaCatalogUpdateClient: LorcanaCatalogUpdateFetching {
    private let transport: SignedCatalogUpdateClient<LorcanaCatalogReleaseEnvelope>
    init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral) throws {
        transport = try .init(endpoint: endpoint, configuration: configuration,
                              maximumBytes: LorcanaCatalogSignature.maximumEnvelopeBytes)
    }
    func fetch() async throws -> SignedCatalogFetchResult<LorcanaCatalogReleaseEnvelope> { try await transport.fetch() }
    func resetConditionalState() async { await transport.resetConditionalState() }
}

/// Durable verified activation precedes publication. Every adapter in a snapshot
/// uses the same immutable registry; container binding owns collection authority.
actor LorcanaCatalogCoordinator: GameCatalogActivationSource {
    enum RemoteMode: Sendable { case disabled, validationOnly, authority }
    enum Result: Sendable {
        case disabled, notModified, validated(Int), activated(GameCatalogSnapshot), rejected(Error)
    }
    nonisolated let game: CardGame = .lorcana
    private let store: LorcanaCatalogReleaseStore
    private let client: (any LorcanaCatalogUpdateFetching)?
    private let mode: RemoteMode
    private var snapshot: GameCatalogSnapshot?
    private var didLoad = false
    private var loadingTask: Task<LorcanaCatalogReleaseStore.StoredRelease?, Never>?
    private var refreshTask: Task<Result, Never>?
    private var didAttemptLaunchRefresh = false
    private var continuations: [UUID: AsyncStream<GameCatalogSnapshot>.Continuation] = [:]

    init(store: LorcanaCatalogReleaseStore, client: (any LorcanaCatalogUpdateFetching)? = nil,
         mode: RemoteMode = .disabled) {
        self.store = store; self.client = client; self.mode = mode
    }

    func currentSnapshot() async -> GameCatalogSnapshot? {
        await load()
        return snapshot
    }
    func activationSnapshots() -> AsyncStream<GameCatalogSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: GameCatalogSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in Task { await self?.removeContinuation(id) } }
        continuations[id] = continuation
        return stream
    }
    func refreshAtLaunch() async {
        guard !didAttemptLaunchRefresh else { return }
        didAttemptLaunchRefresh = true
        _ = await refresh()
    }
    func refresh(now: Date = .now) async -> Result {
        guard mode != .disabled, let client else { return .disabled }
        if let refreshTask { return await refreshTask.value }
        let task = Task { await self.fetch(client, now: now) }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }
    func activate(_ envelope: LorcanaCatalogReleaseEnvelope, now: Date = .now) async -> Result {
        await load(now: now)
        do {
            let result = try await store.activate(envelope, now: now)
            guard case .activated = result, let head = await store.activeRelease,
                  let installed = install(head, publish: true) else { return .notModified }
            return .activated(installed)
        } catch { return .rejected(error) }
    }
    private func load(now: Date = .now) async {
        guard !didLoad else { return }
        let task: Task<LorcanaCatalogReleaseStore.StoredRelease?, Never>
        if let loadingTask { task = loadingTask }
        else {
            task = Task { [store] in await store.load(now: now); return await store.activeRelease }
            loadingTask = task
        }
        if let stored = await task.value { _ = install(stored, publish: false) }
        didLoad = true; loadingTask = nil
    }
    private func install(_ head: LorcanaCatalogReleaseStore.StoredRelease, publish: Bool) -> GameCatalogSnapshot? {
        let revision = head.release.release.revision
        guard snapshot.map({ revision > $0.revision }) ?? true else { return nil }
        let registry = head.registry
        let next = GameCatalogSnapshot(revision: revision, catalog: LorcanaCatalogAdapter(registry: registry),
            recognizer: LorcanaRecognitionAdapter(registry: registry), variantPolicy: LorcanaVariantPolicy(registry: registry),
            browse: LorcanaBrowseAdapter(registry: registry), importer: LorcanaImportAdapter(registry: registry),
            priceAuthority: LorcanaPriceAdapter.priceAuthority(registry))
        snapshot = next
        if publish { for continuation in continuations.values { continuation.yield(next) } }
        return next
    }
    private func fetch(_ client: any LorcanaCatalogUpdateFetching, now: Date) async -> Result {
        await load(now: now)
        do {
            switch try await client.fetch() {
            case .notModified:
                guard mode == .validationOnly || snapshot != nil else { throw SignedCatalogUpdateError.unexpectedNotModified }
                return .notModified
            case let .fetched(envelope):
                if mode == .validationOnly { return .validated(try await store.validateEnvelope(envelope, now: now)) }
                let result = await activate(envelope, now: now)
                if case let .rejected(error) = result { throw error }
                return result
            }
        } catch { await client.resetConditionalState(); return .rejected(error) }
    }
    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }
}
