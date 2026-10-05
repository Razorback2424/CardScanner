import Foundation
import OnePieceCatalogCore

/// Catalog activation owns one immutable registry generation. A successful
/// durable transaction precedes every event; failed updates retain its snapshot.
actor OnePieceCatalogCoordinator {
    struct ActivationEvent: Sendable {
        let registry: OnePieceCatalogRegistry
        let revision: Int
        let previousRevision: Int?
        let recognitionVocabularyChanged: Bool
    }
    enum ActivationResult: Sendable {
        case activated(ActivationEvent)
        case notModified
        case rejected(Error)
    }
    enum RefreshResult: Sendable {
        case disabled, notModified, validated(Int)
        case activation(ActivationResult)
        case rejected(Error)
    }
    private let store: OnePieceCatalogReleaseStore
    private let client: (any OnePieceCatalogUpdateFetching)?
    private let rolloutMode: OnePieceCatalogRolloutMode
    private var refreshTask: Task<RefreshResult, Never>?
    private var didAttemptLaunchRefresh = false
    private var activeRegistry: OnePieceCatalogRegistry?
    // Shared by current-snapshot requests and activation-stream publication.
    private var cachedSnapshot: GameCatalogSnapshot?
    private var didLoad = false
    private var loadingTask: Task<OnePieceCatalogReleaseStore.StoredRelease?, Never>?
    private var continuations: [UUID: AsyncStream<ActivationEvent>.Continuation] = [:]

    init(store: OnePieceCatalogReleaseStore, client: (any OnePieceCatalogUpdateFetching)? = nil,
         rolloutMode: OnePieceCatalogRolloutMode = .disabled) {
        self.store = store; self.client = client; self.rolloutMode = rolloutMode
    }
    var registry: OnePieceCatalogRegistry? { activeRegistry }
    var revision: Int? { activeRegistry?.verifiedRelease.release.revision }

    func snapshot(_ registry: OnePieceCatalogRegistry) -> GameCatalogSnapshot {
        if let cachedSnapshot, cachedSnapshot.catalog.generation == registry.generation {
            return cachedSnapshot
        }
        let snapshot = GameCatalogSnapshot(revision: registry.verifiedRelease.release.revision,
            catalog: OnePieceCatalogAdapter(registry: registry),
            recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
            variantPolicy: OnePieceVariantPolicy(registry: registry), browse: OnePieceBrowseAdapter(registry: registry),
            importer: OnePieceImportAdapter(registry: registry),
            priceAuthority: OnePiecePriceAdapter.priceAuthority(registry))
        // A buffered older event must not evict the current generation's cache.
        if cachedSnapshot.map({ snapshot.revision >= $0.revision }) ?? true {
            cachedSnapshot = snapshot
        }
        return snapshot
    }

    func refreshAtLaunch() async {
        guard !didAttemptLaunchRefresh else { return }
        didAttemptLaunchRefresh = true
        _ = await refresh()
    }

    func refresh(now: Date = .now) async -> RefreshResult {
        guard rolloutMode != .disabled, let client else { return .disabled }
        if let refreshTask { return await refreshTask.value }
        let task = Task { await self.fetchAndActivate(client, now: now) }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func fetchAndActivate(_ client: any OnePieceCatalogUpdateFetching, now: Date) async -> RefreshResult {
        await loadPersistedOrBundled(now: now)
        do {
            switch try await client.fetch() {
            case .notModified:
                guard rolloutMode == .remoteValidationOnly || activeRegistry != nil else {
                    throw SignedCatalogUpdateError.unexpectedNotModified
                }
                return .notModified
            case let .fetched(envelope):
                if rolloutMode == .remoteValidationOnly {
                    return .validated(try await store.validateEnvelope(envelope, now: now))
                }
                let result = await activateEnvelope(envelope, now: now)
                if case let .rejected(error) = result { throw error }
                return .activation(result)
            }
        } catch {
            await client.resetConditionalState()
            return .rejected(error)
        }
    }

    func activationEvents() -> AsyncStream<ActivationEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ActivationEvent.self, bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        continuations[id] = continuation
        return stream
    }

    func loadPersistedOrBundled(now: Date = .now) async {
        guard !didLoad else { return }
        let task: Task<OnePieceCatalogReleaseStore.StoredRelease?, Never>
        if let loadingTask { task = loadingTask }
        else {
            task = Task { [store] in
                await store.load(now: now)
                return await store.activeRelease
            }
            loadingTask = task
        }
        if let stored = await task.value,
           revision.map({ stored.release.release.revision > $0 }) ?? true {
            activeRegistry = stored.registry
        }
        didLoad = true
        loadingTask = nil
    }

    func activateEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope, now: Date = .now) async -> ActivationResult {
        await loadPersistedOrBundled(now: now)
        do {
            let activation = try await store.activate(envelope, now: now)
            guard case .activated = activation, let stored = await store.activeRelease else { return .notModified }
            // Install the actual durable head after the await. A concurrent
            // higher revision cannot be overwritten by this caller's candidate.
            let next = stored.registry
            guard revision.map({ next.verifiedRelease.release.revision > $0 }) ?? true else { return .notModified }
            let oldPrefixes = activeRegistry?.recognitionPrefixes ?? []
            let newPrefixes = next.recognitionPrefixes
            let event = ActivationEvent(registry: next, revision: next.verifiedRelease.release.revision,
                previousRevision: revision, recognitionVocabularyChanged: oldPrefixes != newPrefixes)
            activeRegistry = next
            for continuation in continuations.values { continuation.yield(event) }
            return .activated(event)
        } catch { return .rejected(error) }
    }

    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }
}
