import Foundation
import os

actor PokemonCatalogCoordinator {
    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "pokemonCatalogCoordinator"
    )

    // MARK: - Activation event

    struct ActivationEvent: Sendable {
        let revision: Int
        let previousRevision: Int?
        let registry: PokemonCatalogRegistry
        let changedOfficialCountSetIDs: Set<String>
    }

    // MARK: - Dependencies

    private let store: PokemonCatalogReleaseStore
    private let client: PokemonCatalogUpdateClient
    private let keys: [PokemonCatalogSignatureVerifier.PinnedKey]
    private let rolloutMode: PokemonCatalogRolloutMode
    private let diagnostics: PokemonCatalogRolloutDiagnostics

    // MARK: - State

    private var activeRegistry: PokemonCatalogRegistry
    private var activeRevision: Int?
    private var continuations: [UUID: AsyncStream<ActivationEvent>.Continuation] = [:]
    private var didPerformInitialLoad = false

    // MARK: - Init

    init(
        store: PokemonCatalogReleaseStore = PokemonCatalogReleaseStore(),
        client: PokemonCatalogUpdateClient = PokemonCatalogUpdateClient(),
        keys: [PokemonCatalogSignatureVerifier.PinnedKey] = PokemonCatalogSignatureVerifier.pinnedKeys,
        rolloutMode: PokemonCatalogRolloutMode = .configured,
        diagnostics: PokemonCatalogRolloutDiagnostics = .shared
    ) {
        self.store = store
        self.client = client
        self.keys = keys
        self.rolloutMode = rolloutMode
        self.diagnostics = diagnostics
        self.activeRegistry = PokemonCatalogRegistry.bundledSeed
        self.activeRevision = nil
    }

    // MARK: - Public interface

    var registry: PokemonCatalogRegistry { activeRegistry }

    var revision: Int? { activeRevision }

    var currentRolloutMode: PokemonCatalogRolloutMode { rolloutMode }

    func activationEvents() -> AsyncStream<ActivationEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ActivationEvent.self)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
        continuations[id] = continuation
        return stream
    }

    func loadPersistedOrBundled() async {
        guard !didPerformInitialLoad else { return }
        didPerformInitialLoad = true

        let start = Date()
        let loadState = PerformanceSignpost.beginInterval(
            "pokemonCatalogLaunchLoad",
            id: PerformanceSignpost.makeID(),
            "mode=\(rolloutMode.rawValue)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "pokemonCatalogLaunchLoad",
                loadState,
                "mode=\(rolloutMode.rawValue)"
            )
        }

        // During the measured rollout the bundled seed is the authority. Do
        // not even load a previously persisted remote release in this mode;
        // an install that was previously used with staging must still have
        // deterministic production behavior.
        guard rolloutMode == .remoteAuthority else {
            activeRegistry = store.recoverFromBundledSeed()
            activeRevision = nil
            await diagnostics.recordLaunchLoad(
                mode: rolloutMode,
                duration: Date().timeIntervalSince(start),
                usedPersistedRelease: false
            )
            Self.logger.info("Using bundled seed registry in validation-only rollout mode")
            return
        }

        await store.load(keys: keys)
        if let stored = await store.activeRegistry {
            activeRegistry = stored
            activeRevision = await store.activeRevision
            await diagnostics.recordLaunchLoad(
                mode: rolloutMode,
                duration: Date().timeIntervalSince(start),
                usedPersistedRelease: true
            )
            Self.logger.info("Loaded persisted registry revision \(self.activeRevision ?? 0)")
        } else {
            activeRegistry = store.recoverFromBundledSeed()
            activeRevision = nil
            await diagnostics.recordLaunchLoad(
                mode: rolloutMode,
                duration: Date().timeIntervalSince(start),
                usedPersistedRelease: false
            )
            Self.logger.info("Using bundled seed registry")
        }
    }

    enum RefreshResult: Sendable {
        case activated(ActivationEvent)
        case validated(PokemonCatalogRolloutValidation)
        case notModified
        case rejected(Error)
    }

    func refresh() async -> RefreshResult {
        await loadPersistedOrBundled()
        await diagnostics.recordRefreshStarted(mode: rolloutMode)

        let fetchResult: PokemonCatalogUpdateClient.FetchResult
        do {
            fetchResult = try await client.fetch()
        } catch {
            if Task.isCancelled {
                await diagnostics.recordCancellation()
            } else {
                await diagnostics.recordRejection(error)
            }
            Self.logger.warning("Catalog fetch failed: \(error)")
            return .rejected(error)
        }

        switch fetchResult {
        case .notModified:
            return .notModified

        case .fetched(let envelope):
            guard rolloutMode == .remoteAuthority else {
                return await validateAndDiscard(envelope)
            }
            return await activateEnvelope(envelope)
        }
    }

    func activateEnvelope(_ envelope: PokemonCatalogReleaseEnvelope) async -> RefreshResult {
        let activationStart = Date()
        let activationState = PerformanceSignpost.beginInterval(
            "pokemonCatalogActivation",
            id: PerformanceSignpost.makeID(),
            "mode=\(rolloutMode.rawValue)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "pokemonCatalogActivation",
                activationState,
                "mode=\(rolloutMode.rawValue)"
            )
        }
        let verified: (release: PokemonCatalogRelease, registry: PokemonCatalogRegistry)
        do {
            verified = try verifyAndBuildRegistry(envelope)
        } catch {
            await diagnostics.recordRejection(error)
            Self.logger.warning("Catalog verification failed: \(error)")
            return .rejected(error)
        }

        let release = verified.release
        let newRegistry = verified.registry

        if let currentRevision = activeRevision {
            if release.revision < currentRevision {
                let error = PokemonCatalogSignatureVerifier.VerificationError
                    .revisionNotMonotonic(
                        received: release.revision,
                        current: currentRevision
                    )
                await diagnostics.recordRejection(error)
                Self.logger.warning("Catalog verification failed: \(error)")
                return .rejected(error)
            }

            if release.revision == currentRevision {
                guard let stored = await store.activeRelease,
                      stored.envelope == envelope else {
                    let error = PokemonCatalogSignatureVerifier.VerificationError
                        .revisionNotMonotonic(
                            received: release.revision,
                            current: currentRevision
                        )
                    await diagnostics.recordRejection(error)
                    Self.logger.warning(
                        "Catalog revision \(release.revision) conflicts with the persisted current revision"
                    )
                    return .rejected(error)
                }

                await diagnostics.recordNotModified()
                Self.logger.info("Catalog revision \(release.revision) is already current")
                return .notModified
            }
        }

        let changedCounts = officialCountChanges(
            from: activeRegistry,
            to: newRegistry,
            release: release
        )

        let result: PokemonCatalogReleaseStore.ActivationResult
        do {
            result = try await store.activate(
                envelope: envelope,
                release: release,
                registry: newRegistry
            )
        } catch {
            await diagnostics.recordRejection(error)
            Self.logger.error("Failed to persist catalog release: \(error)")
            return .rejected(error)
        }

        switch result {
        case .alreadyCurrent:
            await diagnostics.recordNotModified()
            return .notModified

        case .activated(let rev, let prev):
            activeRegistry = newRegistry
            activeRevision = rev

            let event = ActivationEvent(
                revision: rev,
                previousRevision: prev,
                registry: newRegistry,
                changedOfficialCountSetIDs: changedCounts
            )
            for (_, continuation) in continuations {
                continuation.yield(event)
            }
            Self.logger.info(
                "Activated catalog revision \(rev) (previous: \(prev.map(String.init) ?? "none"), changed counts: \(changedCounts.count))"
            )
            await diagnostics.recordActivation(
                revision: rev,
                diskBytes: await store.diskUsageBytes(),
                memoryFootprintBytes: PokemonCatalogRolloutDiagnostics.currentMemoryFootprintBytes(),
                duration: Date().timeIntervalSince(activationStart)
            )
            return .activated(event)
        }
    }

    // MARK: - Consumer invalidation

    func invalidateConsumers(
        event: ActivationEvent,
        offline: PokemonOfflineCatalog,
        resolvedCache: ResolvedPokemonCardCache,
        browseCatalog: BrowseCatalog,
        checklistStore: PokemonChecklistStore
    ) async {
        await offline.updateRegistry(event.registry)
        await offline.invalidate()
        await resolvedCache.invalidateEntries(forSetIDs: event.changedOfficialCountSetIDs)
        await browseCatalog.invalidateSetCache(for: .pokemon)
        await checklistStore.clearCursorForRegistryActivation()
    }

    // MARK: - Private

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func validateAndDiscard(
        _ envelope: PokemonCatalogReleaseEnvelope
    ) async -> RefreshResult {
        let validationStart = Date()
        let validationState = PerformanceSignpost.beginInterval(
            "pokemonCatalogValidation",
            id: PerformanceSignpost.makeID(),
            "mode=\(rolloutMode.rawValue)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "pokemonCatalogValidation",
                validationState,
                "mode=\(rolloutMode.rawValue)"
            )
        }
        do {
            let verified = try verifyAndBuildRegistry(envelope)
            let validation = PokemonCatalogRolloutValidation(
                revision: verified.release.revision,
                descriptorCount: verified.release.sets.count,
                supportedDescriptorCount: verified.registry.descriptors.count,
                payloadBytes: Base64URL.decode(envelope.payload)?.count
            )
            await diagnostics.recordValidation(
                validation,
                diskBytes: await store.diskUsageBytes(),
                memoryFootprintBytes: PokemonCatalogRolloutDiagnostics.currentMemoryFootprintBytes(),
                duration: Date().timeIntervalSince(validationStart)
            )
            Self.logger.info(
                "Validated catalog revision \(validation.revision) without activation (bundled authority)"
            )
            return .validated(validation)
        } catch {
            await diagnostics.recordRejection(error)
            Self.logger.warning("Catalog validation failed: \(error)")
            return .rejected(error)
        }
    }

    private func verifyAndBuildRegistry(
        _ envelope: PokemonCatalogReleaseEnvelope
    ) throws -> (release: PokemonCatalogRelease, registry: PokemonCatalogRegistry) {
        let release = try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            keys: keys
        )
        try PokemonCatalogRegistry.validate(release)
        return (release, PokemonCatalogRegistry(release: release))
    }

    private func officialCountChanges(
        from old: PokemonCatalogRegistry,
        to new: PokemonCatalogRegistry,
        release: PokemonCatalogRelease
    ) -> Set<String> {
        var changed = Set<String>()
        for descriptor in release.sets {
            let id = descriptor.providerSetID
            let oldCount = old.officialCount(forProviderSetID: id)
            let newCount = new.officialCount(forProviderSetID: id)
            if oldCount != newCount {
                changed.insert(id.lowercased())
            }
        }
        return changed
    }

    // MARK: - Testing

    #if DEBUG
    func overrideRegistry(_ registry: PokemonCatalogRegistry, revision: Int?) {
        activeRegistry = registry
        activeRevision = revision
        didPerformInitialLoad = true
    }
    #endif
}
