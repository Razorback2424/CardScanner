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
        let contentChangedProviderSetIDs: Set<String>
    }

    // MARK: - Dependencies

    private let store: PokemonCatalogReleaseStore
    private let checklistStore: PokemonChecklistStore
    private let client: PokemonCatalogUpdateClient
    private let keys: [PokemonCatalogSignatureVerifier.PinnedKey]
    private let rolloutMode: PokemonCatalogRolloutMode
    private let diagnostics: PokemonCatalogRolloutDiagnostics
    private let now: @Sendable () -> Date

    // MARK: - State

    private nonisolated let registrySnapshot = OSAllocatedUnfairLock(initialState: PokemonCatalogRegistry.bundledSeed)
    private var activeRegistry: PokemonCatalogRegistry {
        get { registrySnapshot.withLock { $0 } }
        set { registrySnapshot.withLock { $0 = newValue } }
    }
    private var activeRevision: Int?
    private var continuations: [UUID: AsyncStream<ActivationEvent>.Continuation] = [:]
    private var didPerformInitialLoad = false
    private var initialLoadTask: Task<Void, Never>?
    private var automaticRefreshTask: Task<RefreshResult, Never>?
    private var automaticRefreshRetryAfter: Date?
    static let automaticRefreshFailureCooldown: TimeInterval = 5 * 60

    // MARK: - Init

    init(
        store: PokemonCatalogReleaseStore = PokemonCatalogReleaseStore(),
        checklistStore: PokemonChecklistStore = .shared,
        client: PokemonCatalogUpdateClient = PokemonCatalogUpdateClient(),
        keys: [PokemonCatalogSignatureVerifier.PinnedKey] = PokemonCatalogSignatureVerifier.pinnedKeys,
        rolloutMode: PokemonCatalogRolloutMode = .configured,
        diagnostics: PokemonCatalogRolloutDiagnostics = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.checklistStore = checklistStore
        self.client = client
        self.keys = keys
        self.rolloutMode = rolloutMode
        self.diagnostics = diagnostics
        self.now = now
        self.activeRevision = nil
    }

    // MARK: - Public interface

    var registry: PokemonCatalogRegistry { activeRegistry }
    var activeCatalog: (registry: PokemonCatalogRegistry, revision: Int?) { (activeRegistry, activeRevision) }

    nonisolated func acceptsAcquisition(_ card: TCGdexCard, automaticIdentifier: ScanIdentifier?) -> Bool {
        guard let captured = card.acquisitionCatalog else { return false }
        return registrySnapshot.withLock { registry in
            let descriptor = registry.descriptor(forProviderSetID: card.set.id)
            guard descriptor == captured.descriptor(forProviderSetID: card.set.id),
                  registry.resolvedCardCacheFingerprint(forProviderSetID: card.set.id)
                    == captured.resolvedCardCacheFingerprint(forProviderSetID: card.set.id) else { return false }
            guard let automaticIdentifier else { return true }
            // The header and year only identify a family. Saving one Energy
            // type requires the user's explicit printing selection.
            guard automaticIdentifier.namespace != PokemonUnnumberedEnergyEvidence.namespace else { return false }
            switch automaticIdentifier.legacyIdentity {
            case let .pokemon(code, _, total, definition):
                return descriptor?.scanEnabled == true && descriptor?.recognitionKind == .expansion
                    && descriptor?.printedCode == code && descriptor?.officialCount == total
                    && descriptor?.providerSetID == definition.tcgdexSetID
            case let .pokemonPromo(prefix, _, definition):
                return descriptor?.scanEnabled == true && registry.pokemonPromoSetDefinition(forPrefix: prefix) == definition
            case let .pokemonEnergy(code, _, definition):
                return descriptor?.scanEnabled == true && registry.energyDefinition(forCode: code) == definition
            default:
                return true
            }
        }
    }

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
        if let initialLoadTask {
            await initialLoadTask.value
            return
        }
        guard !didPerformInitialLoad else { return }
        let task = Task { await self.performInitialLoad() }
        initialLoadTask = task
        await task.value
        initialLoadTask = nil
    }

    private func performInitialLoad() async {
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
        let current = await store.activeRelease
        let previous = await store.previousRelease
        for stored in [current, previous].compactMap({ $0 }) {
            if stored.release.checklistInputSHA256 != nil,
               !(await checklistStore.activateSignedSnapshot(for: stored.release)) { continue }
            activeRegistry = stored.registry
            activeRevision = stored.release.revision
            await diagnostics.recordLaunchLoad(
                mode: rolloutMode,
                duration: Date().timeIntervalSince(start),
                usedPersistedRelease: true
            )
            Self.logger.info("Loaded persisted registry revision \(self.activeRevision ?? 0)")
            return
        }
        activeRegistry = store.recoverFromBundledSeed()
        activeRevision = nil
        await diagnostics.recordLaunchLoad(mode: rolloutMode, duration: Date().timeIntervalSince(start),
            usedPersistedRelease: false)
        Self.logger.info("Using bundled seed registry")
    }

    enum RefreshResult: Sendable {
        case activated(ActivationEvent)
        case validated(PokemonCatalogRolloutValidation)
        case notModified
        case rejected(Error)
    }

    /// Share automatic checks across callers and wait five minutes after a
    /// failure. Direct `refresh()` calls remain available for an explicit retry.
    func refreshAutomatically() async -> RefreshResult? {
        if let automaticRefreshTask { return await automaticRefreshTask.value }
        if let automaticRefreshRetryAfter, now() < automaticRefreshRetryAfter { return nil }

        let task = Task { await self.refresh() }
        automaticRefreshTask = task
        let result = await task.value
        if case .rejected(let error) = result, !(error is CancellationError), !task.isCancelled {
            automaticRefreshRetryAfter = now().addingTimeInterval(Self.automaticRefreshFailureCooldown)
        } else {
            automaticRefreshRetryAfter = nil
        }
        automaticRefreshTask = nil
        return result
    }

    func refresh() async -> RefreshResult {
        await loadPersistedOrBundled()
        await diagnostics.recordRefreshStarted(mode: rolloutMode)

        guard !keys.isEmpty else {
            let error = PokemonCatalogSignatureVerifier.VerificationError.noPinnedKeysConfigured
            await diagnostics.recordRejection(error)
            Self.logger.error(
                "POKEMON_CATALOG_PINNED_KEYS is empty in mode \(self.rolloutMode.rawValue, privacy: .public); no release can be verified. Check the configuration's xcconfig."
            )
            return .rejected(error)
        }

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
            let result: RefreshResult
            if rolloutMode == .remoteAuthority {
                result = await activateEnvelope(envelope)
            } else {
                result = await validateAndDiscard(envelope)
            }
            if case .rejected = result { await client.resetConditionalState() }
            return result
        }
    }

    func activateEnvelope(_ envelope: PokemonCatalogReleaseEnvelope) async -> RefreshResult {
        // Keep direct callers (including diagnostics and tests) on the same
        // persisted-state path as refresh(). Without this, activeRevision can
        // still be nil when the monotonicity check runs.
        await loadPersistedOrBundled()
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

        let result: PokemonCatalogReleaseStore.ActivationResult
        do {
            if release.checklistInputSHA256 != nil,
               !checklistStore.hasStagedSignedSnapshot(for: release) {
                let inputs = try await client.fetchChecklistInputs(for: release)
                let snapshot = try PokemonMasterSetChecklistBuilder.buildSigned(
                    inputs, registry: newRegistry, generatedAt: release.generatedAt)
                try await checklistStore.stageSignedSnapshot(snapshot, for: release)
            }
            try Task.checkCancellation()
            result = try await store.activate(
                envelope: envelope,
                release: release,
                registry: newRegistry,
                checklistStore: checklistStore
            )
        } catch {
            await diagnostics.recordRejection(error)
            Self.logger.error("Failed to persist catalog release: \(error)")
            return .rejected(error)
        }

        if case .alreadyCurrent = result {
            let persisted = await store.activeRelease
            if activeRevision == release.revision || persisted?.envelope != envelope {
                await diagnostics.recordNotModified()
                return .notModified
            }
        }

        do {
            // Actor reentrancy allows a newer activation to publish while the
            // store is awaited. Never reinstall an older registry afterward.
            let rev = release.revision
            guard activeRevision.map({ rev > $0 }) ?? true else { return .notModified }
            if release.checklistInputSHA256 != nil || activeRegistry.checklistInputSHA256 != nil {
                guard await checklistStore.activateSignedSnapshot(for: release) else {
                    if let activeRevision, activeRevision > rev { return .notModified }
                    return .rejected(PokemonChecklistError.malformedSnapshot)
                }
            }
            guard activeRevision.map({ rev > $0 }) ?? true else { return .notModified }
            let prev = activeRevision
            let changedCounts = officialCountChanges(
                from: activeRegistry,
                to: newRegistry,
                release: release
            )
            let changedContent = providerContentChanges(
                from: activeRegistry,
                release: release
            )
            activeRegistry = newRegistry
            activeRevision = rev
            let event = ActivationEvent(
                revision: rev,
                previousRevision: prev,
                registry: newRegistry,
                changedOfficialCountSetIDs: changedCounts,
                contentChangedProviderSetIDs: changedContent
            )
            for (_, continuation) in continuations {
                continuation.yield(event)
            }
            if release.checklistInputSHA256 != nil {
                let previous = await store.previousRelease
                await checklistStore.removeStagedRevisions(olderThan: previous?.release.revision ?? rev)
            }
            Self.logger.info(
                "Activated catalog revision \(rev) (previous: \(prev.map(String.init) ?? "none"), changed counts: \(changedCounts.count), changed content: \(changedContent.count))"
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
        await resolvedCache.invalidateEntries(
            forSetIDs: event.changedOfficialCountSetIDs.union(
                event.contentChangedProviderSetIDs
            )
        )
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

    private func providerContentChanges(
        from old: PokemonCatalogRegistry,
        release: PokemonCatalogRelease
    ) -> Set<String> {
        var changed = Set<String>()
        for descriptor in release.sets {
            guard let oldDescriptor = old.descriptor(
                forProviderSetID: descriptor.providerSetID
            ),
            (oldDescriptor.providerFingerprint != descriptor.providerFingerprint
                && descriptor.providerFingerprint != nil)
                || oldDescriptor.additionalVariants != descriptor.additionalVariants else { continue }
            changed.insert(descriptor.providerSetID.lowercased())
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
