import Foundation
import os

actor MagicCatalogCoordinator {
    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "magicCatalogCoordinator"
    )

    struct ActivationEvent: Sendable {
        let revision: Int
        let previousRevision: Int?
        let registry: MagicCatalogRegistry
        let scannerProjectionChanged: Bool
        let browseProjectionChanged: Bool
        let routingProjectionChanged: Bool
    }

    enum RefreshResult: Sendable {
        case activated(ActivationEvent)
        case validated(revision: Int)
        case notModified
        case skippedLegacyLive
        case rejected(Error)
    }

    private let store: MagicCatalogReleaseStore
    private let client: MagicCatalogUpdateClient
    private let keys: [MagicCatalogSignatureVerifier.PinnedKey]
    private let rolloutMode: MagicCatalogRolloutMode
    private var activeRegistry: MagicCatalogRegistry
    private var activeRevision: Int?
    private var didPerformInitialLoad = false
    private var continuations: [UUID: AsyncStream<ActivationEvent>.Continuation] = [:]
    private var lastParityMismatches: [MagicCatalogParityMismatch] = []

    init(
        store: MagicCatalogReleaseStore = MagicCatalogReleaseStore(),
        client: MagicCatalogUpdateClient = MagicCatalogUpdateClient(),
        keys: [MagicCatalogSignatureVerifier.PinnedKey] = MagicCatalogSignatureVerifier.pinnedKeys,
        rolloutMode: MagicCatalogRolloutMode = .configured
    ) {
        self.store = store
        self.client = client
        self.keys = keys
        self.rolloutMode = rolloutMode
        self.activeRegistry = MagicCatalogRegistry.bundledSeed
    }

    var registry: MagicCatalogRegistry { activeRegistry }
    var revision: Int? { activeRevision }
    var currentRolloutMode: MagicCatalogRolloutMode { rolloutMode }
    var parityMismatches: [MagicCatalogParityMismatch] { lastParityMismatches }

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
        guard rolloutMode == .remoteAuthority else {
            activeRegistry = store.recoverFromBundledSeed()
            activeRevision = nil
            return
        }
        await store.load(keys: keys)
        if let stored = await store.activeRegistry {
            activeRegistry = stored
            activeRevision = await store.activeRevision
            Self.logger.info("Loaded persisted Magic catalog revision \(self.activeRevision ?? 0)")
        } else {
            activeRegistry = store.recoverFromBundledSeed()
            activeRevision = nil
            Self.logger.info("Using bundled Magic catalog seed")
        }
    }

    func refresh() async -> RefreshResult {
        await loadPersistedOrBundled()
        guard rolloutMode != .legacyLive else { return .skippedLegacyLive }
        let fetched: MagicCatalogUpdateClient.FetchResult
        do {
            fetched = try await client.fetch()
        } catch {
            Self.logger.warning("Magic catalog fetch failed: \(error)")
            return .rejected(error)
        }
        switch fetched {
        case .notModified:
            return .notModified
        case .fetched(let envelope):
            if rolloutMode == .remoteValidationOnly {
                return await validateAndDiscard(envelope)
            }
            return await activateEnvelope(envelope)
        }
    }

    func activateEnvelope(_ envelope: MagicCatalogReleaseEnvelope) async -> RefreshResult {
        await loadPersistedOrBundled()
        let verified: MagicCatalogRelease
        do {
            verified = try MagicCatalogSignatureVerifier.verify(
                envelope: envelope,
                currentRevision: nil,
                keys: keys
            )
        } catch {
            Self.logger.warning("Magic catalog verification failed: \(error)")
            return .rejected(error)
        }

        if let currentRevision = activeRevision {
            if verified.revision < currentRevision {
                return .rejected(
                    MagicCatalogSignatureVerifier.VerificationError.revisionNotMonotonic(
                        received: verified.revision,
                        current: currentRevision
                    )
                )
            }
            if verified.revision == currentRevision {
                guard let stored = await store.activeRelease,
                      stored.envelope == envelope else {
                    return .rejected(
                        MagicCatalogSignatureVerifier.VerificationError.revisionNotMonotonic(
                            received: verified.revision,
                            current: currentRevision
                        )
                    )
                }
                return .notModified
            }
        }

        let nextRegistry = MagicCatalogRegistry(release: verified)
        let oldScanner = Dictionary(
            activeRegistry.scannerDefinitions.map { ($0.code.lowercased(), $0.printedSize) },
            uniquingKeysWith: { first, _ in first }
        )
        let newScanner = Dictionary(
            nextRegistry.scannerDefinitions.map { ($0.code.lowercased(), $0.printedSize) },
            uniquingKeysWith: { first, _ in first }
        )
        let oldBrowse = Set(activeRegistry.browseSets)
        let newBrowse = Set(nextRegistry.browseSets)
        let oldRouting = routingProjection(activeRegistry)
        let newRouting = routingProjection(nextRegistry)

        do {
            _ = try await store.activate(
                envelope: envelope,
                release: verified,
                registry: nextRegistry
            )
        } catch {
            return .rejected(error)
        }

        let previousRevision = activeRevision
        activeRegistry = nextRegistry
        activeRevision = verified.revision
        let event = ActivationEvent(
            revision: verified.revision,
            previousRevision: previousRevision,
            registry: nextRegistry,
            scannerProjectionChanged: oldScanner != newScanner,
            browseProjectionChanged: oldBrowse != newBrowse,
            routingProjectionChanged: oldRouting != newRouting
        )
        for continuation in continuations.values { continuation.yield(event) }
        return .activated(event)
    }

    func recordLegacyParity(
        _ mismatches: [MagicCatalogParityMismatch],
        replacing surfaces: Set<MagicCatalogParitySurface> = Set(MagicCatalogParitySurface.allCases)
    ) {
        guard rolloutMode == .remoteValidationOnly else { return }
        var merged = Dictionary(
            uniqueKeysWithValues: lastParityMismatches.map { ($0.surface, $0) }
        )
        for surface in surfaces {
            merged.removeValue(forKey: surface)
        }
        for mismatch in mismatches where surfaces.contains(mismatch.surface) {
            merged[mismatch.surface] = mismatch
        }
        lastParityMismatches = MagicCatalogParitySurface.allCases.compactMap { merged[$0] }
        if !mismatches.isEmpty {
            Self.logger.warning("Magic legacy parity mismatches: \(mismatches.map(\.details).joined(separator: "; "))")
        }
    }

    #if DEBUG
    func overrideRegistry(_ registry: MagicCatalogRegistry, revision: Int?) {
        activeRegistry = registry
        activeRevision = revision
        didPerformInitialLoad = true
    }
    #endif

    private func validateAndDiscard(_ envelope: MagicCatalogReleaseEnvelope) async -> RefreshResult {
        do {
            let release = try MagicCatalogSignatureVerifier.verify(
                envelope: envelope,
                currentRevision: nil,
                keys: keys
            )
            return .validated(revision: release.revision)
        } catch {
            return .rejected(error)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func routingProjection(_ registry: MagicCatalogRegistry) -> Set<String> {
        Set(registry.childSetsByParentCode.flatMap { parent, children in
            children.compactMap { child in
                guard let kind = child.routingKind else { return nil }
                return "\(parent)|\(child.code.lowercased())|\(kind.rawValue)"
            }
        })
    }
}
