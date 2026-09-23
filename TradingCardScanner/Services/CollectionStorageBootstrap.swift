import CloudKit
import Foundation
import SwiftData

enum CollectionStorageMode: String, Equatable, Sendable {
    case cloudKit
    case onDevice

    static var localOnly: Self { .onDevice }

    var label: String {
        switch self {
        case .cloudKit:
            return "iCloud sync enabled"
        case .onDevice:
            return "On this device only"
        }
    }

    var detail: String {
        switch self {
        case .cloudKit:
            return "The collection uses this device's iCloud account."
        case .onDevice:
            return "The collection is stored on this device while iCloud is unavailable or not attached."
        }
    }

    var isCloudSyncing: Bool { self == .cloudKit }
}

enum CollectionStorageBootstrapError: LocalizedError, Equatable {
    case storageLocationUnavailable
    case cloudKitUnavailableInLocalOnlyBuild
    case storageSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .storageLocationUnavailable:
            return "CardScanner could not resolve its persistent Application Support location."
        case .cloudKitUnavailableInLocalOnlyBuild:
            return "This build does not contain the CloudKit entitlement required for iCloud storage."
        case .storageSessionUnavailable:
            return "CardScanner has no process-authoritative storage session to borrow."
        }
    }
}

struct StorageGenerationToken: Equatable, Sendable {
    let generation: UInt
    let storeID: UUID
}

typealias StorageGenerationContinuation = @Sendable () -> Bool

/// A lock-backed snapshot lets work owned by a SwiftData model actor check the
/// app-level store generation without hopping back to the main actor. The
/// bootstrap remains the authority that installs or invalidates the snapshot.
private final class StorageGenerationSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var token: StorageGenerationToken?

    func suspend() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }

    func install(_ token: StorageGenerationToken) {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    func isCurrent(_ token: StorageGenerationToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.token == token
    }
}

/// App-level fence shared by the bootstrap and long-running foreground
/// workflows. A completion may update UI only while its token still describes
/// the ready store that started the work.
@MainActor
final class CollectionStorageGeneration: ObservableObject {
    static let shared = CollectionStorageGeneration()

    @Published private(set) var generation: UInt = 0
    @Published private(set) var isReady = false
    @Published private(set) var activeStoreID: UUID?
    private let snapshot = StorageGenerationSnapshot()
    private var activeStorageSession: CollectionStorageSession?
    private var hadSuspendedSession = false

    func suspend() {
        snapshot.suspend()
        generation &+= 1
        isReady = false
        activeStoreID = nil
        activeStorageSession = nil
        hadSuspendedSession = true
    }

    func installReady(storeID: UUID) {
        installReady(session: nil, storeID: storeID)
    }

    func installReady(session: CollectionStorageSession) {
        installReady(session: session, storeID: session.storeID)
    }

    private func installReady(
        session: CollectionStorageSession?,
        storeID: UUID
    ) {
        snapshot.suspend()
        generation &+= 1
        isReady = true
        activeStoreID = storeID
        activeStorageSession = session
        hadSuspendedSession = false
        snapshot.install(
            StorageGenerationToken(
                generation: generation,
                storeID: storeID
            )
        )
    }

    func currentToken() -> StorageGenerationToken? {
        guard isReady, let activeStoreID else { return nil }
        return StorageGenerationToken(
            generation: generation,
            storeID: activeStoreID
        )
    }

    func isCurrent(_ token: StorageGenerationToken) -> Bool {
        isReady
            && generation == token.generation
            && activeStoreID == token.storeID
    }

    /// Returns the one active process session, if one is alive. A background
    /// task must reuse this session rather than constructing a second
    /// container for the same SQLite URL, even when the session is only
    /// last-known and therefore non-authoritative for writes.
    func activeSession() -> CollectionStorageSession? {
        guard isReady, let activeStorageSession else { return nil }
        return activeStorageSession
    }

    /// A suspended foreground session means a storage/account transition is
    /// underway. A fresh process has never suspended a session and may run the
    /// guarded headless preflight once.
    var mayCreateHeadlessSession: Bool {
        !isReady && activeStorageSession == nil && !hadSuspendedSession
    }

    /// Returns a Sendable continuation fence for work that can outlive the
    /// main actor, such as an isolated CSV import.
    func continuation(for token: StorageGenerationToken) -> StorageGenerationContinuation {
        let snapshot = self.snapshot
        return { snapshot.isCurrent(token) }
    }
}

struct AccountAttachmentRequest: Equatable, Sendable {
    var storeID: UUID
    var newAccountFingerprint: String
}

struct AccountConflictSummary: Equatable, Sendable {
    var localStoreIDSuffix: String
    var remoteStoreIDSuffix: String
}

struct CollectionStorageSession {
    let container: ModelContainer
    let storeID: UUID
    let mode: CollectionStorageMode
    let isAuthoritative: Bool

    init(
        container: ModelContainer,
        storeID: UUID,
        mode: CollectionStorageMode,
        isAuthoritative: Bool = true
    ) {
        self.container = container
        self.storeID = storeID
        self.mode = mode
        self.isAuthoritative = isAuthoritative
    }
}

struct CollectionStoragePaths: Equatable, Sendable {
    let applicationSupportURL: URL
    let collectionStorageDirectoryURL: URL
    let structuredStoreURL: URL
    let portfolioStoreURL: URL
    let isStable: Bool

    init(
        applicationSupportURL: URL,
        collectionStorageDirectoryURL: URL,
        structuredStoreURL: URL,
        portfolioStoreURL: URL,
        isStable: Bool = true
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.collectionStorageDirectoryURL = collectionStorageDirectoryURL
        self.structuredStoreURL = structuredStoreURL
        self.portfolioStoreURL = portfolioStoreURL
        self.isStable = isStable
    }

    static func production(fileManager: FileManager = .default) -> Self {
        production(
            resolvedApplicationSupportURL: fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
            ).first
        )
    }

    static func production(resolvedApplicationSupportURL: URL?) -> Self {
        guard let applicationSupport = resolvedApplicationSupportURL else {
            let unavailable = URL(
                fileURLWithPath: "/__cardscanner_application_support_unavailable__",
                isDirectory: true
            )
            return Self(
                applicationSupportURL: unavailable,
                collectionStorageDirectoryURL: unavailable.appendingPathComponent(
                    "CollectionStorage",
                    isDirectory: true
                ),
                structuredStoreURL: unavailable.appendingPathComponent("default.store"),
                portfolioStoreURL: unavailable.appendingPathComponent("PortfolioLocal.store"),
                isStable: false
            )
        }
        let directory = applicationSupport
            .appendingPathComponent("CardScanner", isDirectory: true)
            .appendingPathComponent("CollectionStorage", isDirectory: true)
        return Self(
            applicationSupportURL: applicationSupport,
            collectionStorageDirectoryURL: directory,
            // These are the locations used by the pre-bootstrap build: an
            // unnamed SwiftData configuration resolves to default.store and
            // the named PortfolioLocal configuration resolves beside it in
            // Application Support. Keeping those URLs explicit preserves the
            // existing on-device collection without a speculative copy or
            // store replacement during the 1.0 bootstrap.
            structuredStoreURL: applicationSupport.appendingPathComponent("default.store"),
            portfolioStoreURL: applicationSupport.appendingPathComponent("PortfolioLocal.store"),
            isStable: true
        )
    }
}

struct LegacyCollectionStoreAdoption: Sendable {
    let manifest: CollectionStoreManifest
    let localHasUserData: Bool
}

enum CollectionStorageModelSchema {
    static let synced = Schema([
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self,
        InventoryEvent.self
    ])

    static let localOnly = Schema([
        ReferenceQuote.self,
        PriceObservation.self,
        PriceCheckDay.self,
        PortfolioDailyClose.self,
        LocalArtworkOverride.self
    ])

    static let full = Schema([
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self,
        InventoryEvent.self,
        ReferenceQuote.self,
        PriceObservation.self,
        PriceCheckDay.self,
        PortfolioDailyClose.self,
        LocalArtworkOverride.self
    ])
}

/// All I/O needed to choose a collection store is injected here. The
/// bootstrap itself remains a small main-actor state machine, which makes it
/// possible to test account changes and stale generations without touching a
/// real CloudKit account.
@MainActor
struct CollectionStorageBootstrapDependencies {
    var paths: CollectionStoragePaths
    var manifestStore: CollectionStoreManifestStore
    var accountAvailability: @MainActor () async -> CloudAccountAvailability
    var anchorState: @MainActor () async -> CloudCollectionAnchorState = { .unknown }
    var claimAnchor: @MainActor (UUID) async -> CloudCollectionAnchorClaimResult
    var makeContainer: @MainActor (CollectionStorageMode) throws -> ModelContainer
    var readinessSource: any CloudRestorationReadinessSource
    var structuredStoreFilePresent: @MainActor () -> Bool
    var structuredStoreBaseFilePresent: @MainActor () -> Bool
    var localHasUserData: @MainActor () -> Bool
    var storeFileIdentity: @MainActor () throws -> String
    var readStoreFileIdentity: @MainActor () throws -> String?
    var adoptLegacyStore: @MainActor () throws -> LegacyCollectionStoreAdoption?
    /// Test-only provenance guard: production wiring is never acceptable for
    /// storage-suite fixtures unless an entitled integration test opts in.
    var usesProductionDependencies: Bool = false
    var storageGeneration: CollectionStorageGeneration = .shared

    static func production(
        fileManager: FileManager = .default,
        readinessSource: any CloudRestorationReadinessSource = UnprovenCloudRestorationReadinessSource()
    ) -> Self {
        let paths = CollectionStoragePaths.production(fileManager: fileManager)
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL,
            isUsable: paths.isStable
        )
        let discoveryLocations = CollectionStoreDiscovery.locations(
            applicationSupportURL: paths.applicationSupportURL,
            explicitStructuredStoreURL: paths.structuredStoreURL
        )

        let adoptLegacyStore: @MainActor () throws -> LegacyCollectionStoreAdoption? = {
            guard fileManager.fileExists(atPath: paths.structuredStoreURL.path) else {
                return nil
            }

            // The old build already used this same SQLite file. Probe it with
            // the five structured models only, without a CloudKit-backed
            // configuration, before creating any identity or asking CloudKit
            // about an account. This is metadata adoption, not a migration:
            // the original store bytes remain at their original URL.
            let probeConfiguration = ModelConfiguration(
                "CardScannerLegacyProbe",
                schema: CollectionStorageModelSchema.synced,
                url: paths.structuredStoreURL,
                cloudKitDatabase: .none
            )
            let probe = try ModelContainer(
                for: CollectionStorageModelSchema.synced,
                configurations: [probeConfiguration]
            )
            let context = probe.mainContext
            let cardCount = try context.fetchCount(FetchDescriptor<CollectedCard>())
            let priceCount = try context.fetchCount(FetchDescriptor<PriceRecord>())
            let identityCount = try context.fetchCount(FetchDescriptor<ProductIdentity>())
            let activityCount = try context.fetchCount(FetchDescriptor<CollectionActivity>())
            let eventCount = try context.fetchCount(FetchDescriptor<InventoryEvent>())
            let hasUserData = cardCount > 0
                || priceCount > 0
                || identityCount > 0
                || activityCount > 0
                || eventCount > 0

            let manifest = CollectionStoreManifest(
                storeID: UUID(),
                attachmentState: .neverAttached,
                storeFileIdentity: try manifestStore.ensureStoreFileIdentity()
            )
            try manifestStore.save(manifest)
            return LegacyCollectionStoreAdoption(
                manifest: manifest,
                localHasUserData: hasUserData
            )
        }

#if LOCAL_ONLY_SIGNING
        // This build has no CloudKit entitlement, so account and anchor
        // providers are intentionally inert. This branch does not authorize
        // or deny reopening the shared store on-device.
        let accountAvailability: @MainActor () async -> CloudAccountAvailability = { .noAccount }
        let anchorState: @MainActor () async -> CloudCollectionAnchorState = { .unknown }
        let claimAnchor: @MainActor (UUID) async -> CloudCollectionAnchorClaimResult = { storeID in
            .claimed(CloudCollectionAnchor(
                storeID: storeID,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                remoteGeneration: "local-only-\(storeID.uuidString)"
            ))
        }
#else
        let accountProbe: CloudAccountProbe? = try? CloudAccountProbe.production()
        let anchorStore = CloudCollectionAnchorStore(
            client: CloudKitPrivateAnchorDatabaseClient()
        )
        let accountAvailability: @MainActor () async -> CloudAccountAvailability = {
            guard let accountProbe else { return .couldNotDetermine }
            return await accountProbe.availability()
        }
        let anchorState: @MainActor () async -> CloudCollectionAnchorState = {
            await anchorStore.readState()
        }
        let claimAnchor: @MainActor (UUID) async -> CloudCollectionAnchorClaimResult = { storeID in
            await anchorStore.claim(storeID: storeID)
        }
#endif
        return Self(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: accountAvailability,
            anchorState: anchorState,
            claimAnchor: claimAnchor,
            makeContainer: { mode in
                return try Self.makeContainer(paths: paths, mode: mode)
            },
            readinessSource: readinessSource,
            structuredStoreFilePresent: {
                CollectionStoreDiscovery.existingLocation(
                    locations: discoveryLocations,
                    fileManager: fileManager
                ) != nil
            },
            structuredStoreBaseFilePresent: {
                fileManager.fileExists(atPath: paths.structuredStoreURL.path)
            },
            localHasUserData: { false },
            storeFileIdentity: { try manifestStore.ensureStoreFileIdentity() },
            readStoreFileIdentity: { try manifestStore.readStoreFileIdentity() },
            adoptLegacyStore: adoptLegacyStore,
            usesProductionDependencies: true
        )
    }

    @MainActor
    static func makeContainer(
        paths: CollectionStoragePaths,
        mode: CollectionStorageMode
    ) throws -> ModelContainer {
        guard paths.isStable else {
            throw CollectionStorageBootstrapError.storageLocationUnavailable
        }
        let collectionConfiguration: ModelConfiguration
#if LOCAL_ONLY_SIGNING
        // LOCAL_ONLY_SIGNING is an entitlement constraint: this build cannot
        // construct a CloudKit-backed configuration. It does not speak to the
        // safety of reopening the shared store on-device.
        guard mode == .onDevice else {
            throw CollectionStorageBootstrapError.cloudKitUnavailableInLocalOnlyBuild
        }
        collectionConfiguration = ModelConfiguration(
            "CardScannerCollection",
            schema: CollectionStorageModelSchema.synced,
            url: paths.structuredStoreURL,
            cloudKitDatabase: .none
        )
#else
        switch mode {
        case .cloudKit:
            collectionConfiguration = ModelConfiguration(
                "CardScannerCollection",
                schema: CollectionStorageModelSchema.synced,
                url: paths.structuredStoreURL,
                cloudKitDatabase: .private(CloudAccountProbe.containerIdentifier)
            )
        case .onDevice:
            collectionConfiguration = ModelConfiguration(
                "CardScannerCollection",
                schema: CollectionStorageModelSchema.synced,
                url: paths.structuredStoreURL,
                cloudKitDatabase: .none
            )
        }
#endif
        let portfolioConfiguration = ModelConfiguration(
            "PortfolioLocal",
            schema: CollectionStorageModelSchema.localOnly,
            url: paths.portfolioStoreURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [collectionConfiguration, portfolioConfiguration]
        )
    }
}

struct HeadlessCollectionStorageSession {
    let container: ModelContainer
    let storeID: UUID
    let mode: CollectionStorageMode
    /// A cached populated checkpoint is only last-known state until a fresh
    /// foreground readiness proof runs. Background mutation/close publication
    /// is forbidden for that session.
    let isAuthoritative: Bool
    let token: StorageGenerationToken
    let continuation: StorageGenerationContinuation
}

/// A background process may use a previously proven replica, but it may not
/// make first-launch ownership or restoration decisions. This preflight only
/// accepts durable metadata written after affirmative foreground readiness.
@MainActor
struct CollectionStorageHeadlessPreflightDependencies {
    var paths: CollectionStoragePaths
    var manifestStore: CollectionStoreManifestStore
    var accountAvailability: @MainActor () async -> CloudAccountAvailability
    var anchorState: @MainActor () async -> CloudCollectionAnchorState = { .unknown }
    var makeContainer: @MainActor (CollectionStorageMode) throws -> ModelContainer
    /// Production and tests share the manifest-to-container-mode decision so a
    /// local-only manifest cannot accidentally inherit the entitled build's
    /// CloudKit configuration.
    var containerModeForManifest: @MainActor (CloudAttachmentState) -> CollectionStorageMode? = { attachmentState in
        switch attachmentState {
        case .neverAttached, .suspended:
            return .onDevice
        case .attached, .conflict:
            return nil
        }
    }
    var storageGeneration: CollectionStorageGeneration

    static func production(
        fileManager: FileManager = .default,
        storageGeneration: CollectionStorageGeneration? = nil
    ) -> Self {
        let storageGeneration = storageGeneration ?? CollectionStorageGeneration.shared
        let paths = CollectionStoragePaths.production(fileManager: fileManager)
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL,
            isUsable: paths.isStable
        )
#if LOCAL_ONLY_SIGNING
        // A no-entitlement build cannot create the CloudKit-backed background
        // container; it may still reuse a proven local replica.
        let accountAvailability: @MainActor () async -> CloudAccountAvailability = { .noAccount }
        let anchorState: @MainActor () async -> CloudCollectionAnchorState = { .unknown }
#else
        let accountProbe: CloudAccountProbe? = try? CloudAccountProbe.production()
        let accountAvailability: @MainActor () async -> CloudAccountAvailability = {
            guard let accountProbe else { return .couldNotDetermine }
            return await accountProbe.availability()
        }
        let anchorStore = CloudCollectionAnchorStore(
            client: CloudKitPrivateAnchorDatabaseClient()
        )
        let anchorState: @MainActor () async -> CloudCollectionAnchorState = {
            await anchorStore.readState()
        }
#endif
        return Self(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: accountAvailability,
            anchorState: anchorState,
            makeContainer: { mode in
                try CollectionStorageBootstrapDependencies.makeContainer(
                    paths: paths,
                    mode: mode
                )
            },
            containerModeForManifest: { attachmentState in
                switch attachmentState {
                case .neverAttached, .suspended:
                    return .onDevice
                case .attached, .conflict:
                    return nil
                }
            },
            storageGeneration: storageGeneration
        )
    }
}

@MainActor
enum CollectionStorageHeadlessPreflight {
    static func prepare(
        dependencies: CollectionStorageHeadlessPreflightDependencies
    ) async -> HeadlessCollectionStorageSession? {
        if let activeSession = dependencies.storageGeneration.activeSession(),
           let token = dependencies.storageGeneration.currentToken() {
            TradingCardScannerApp.activeStorageMode = activeSession.mode
            TradingCardScannerApp.activeStoreID = activeSession.storeID
            return HeadlessCollectionStorageSession(
                container: activeSession.container,
                storeID: activeSession.storeID,
                mode: activeSession.mode,
                isAuthoritative: activeSession.isAuthoritative,
                token: token,
                continuation: dependencies.storageGeneration.continuation(for: token)
            )
        }
        guard dependencies.storageGeneration.mayCreateHeadlessSession else {
            // The process has a suspended/transitioning foreground session.
            // Do not reopen its store from a background callback.
            return nil
        }
        guard dependencies.paths.isStable else { return nil }

        let manifest: CollectionStoreManifest
        do {
            guard let loadedManifest = try dependencies.manifestStore.load() else {
                return nil
            }
            manifest = loadedManifest
        } catch {
            return nil
        }

        guard !manifest.storeFileIdentity.isEmpty else {
            return nil
        }

        let sidecar: String?
        do {
            sidecar = try dependencies.manifestStore.readStoreFileIdentity()
        } catch {
            return nil
        }
        guard sidecar == manifest.storeFileIdentity,
              FileManager.default.fileExists(atPath: dependencies.paths.structuredStoreURL.path),
              CollectionStoreDiscovery.existingLocation(
                  locations: CollectionStoreDiscovery.locations(
                      applicationSupportURL: dependencies.paths.applicationSupportURL,
                      explicitStructuredStoreURL: dependencies.paths.structuredStoreURL
                  )
              )?.url.standardizedFileURL == dependencies.paths.structuredStoreURL.standardizedFileURL else {
            return nil
        }

        if manifest.attachmentState == .attached {
            guard manifest.attachmentState == .attached,
                  let accountFingerprint = manifest.lastAttachedAccountFingerprint,
                  let checkpoint = manifest.cloudRestoreCheckpoint,
                  case let .available(currentFingerprint) = await dependencies.accountAvailability(),
                  currentFingerprint == accountFingerprint,
                  case let .found(anchor) = await dependencies.anchorState(),
                  anchor.storeID == manifest.storeID,
                  anchor.formatVersion == CloudCollectionAnchorSchema.currentFormatVersion,
                  CollectionStoragePolicy.acceptsRestoreCheckpoint(
                      checkpoint,
                      storeID: manifest.storeID,
                      accountFingerprint: accountFingerprint,
                      storeFileIdentity: manifest.storeFileIdentity,
                      mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
                      currentRemoteGeneration: anchor.remoteGeneration
                  ),
                  checkpoint.readiness == .populated else {
                return nil
            }
            // G4 gate: the production restoration-readiness mechanism is not
            // proven, so a populated checkpoint is last-known state only. Do
            // not construct a non-authoritative second CloudKit container.
            return nil
        }

        guard let mode = dependencies.containerModeForManifest(manifest.attachmentState),
              let container = try? dependencies.makeContainer(mode) else {
            return nil
        }
        let isAuthoritative = true
        let session = CollectionStorageSession(
            container: container,
            storeID: manifest.storeID,
            mode: mode,
            isAuthoritative: isAuthoritative
        )
        guard dependencies.storageGeneration.mayCreateHeadlessSession else {
            return nil
        }
        dependencies.storageGeneration.installReady(session: session)
        TradingCardScannerApp.activeStorageMode = mode
        TradingCardScannerApp.activeStoreID = manifest.storeID
        guard let token = dependencies.storageGeneration.currentToken() else { return nil }
        return HeadlessCollectionStorageSession(
            container: container,
            storeID: manifest.storeID,
            mode: mode,
            isAuthoritative: isAuthoritative,
            token: token,
            continuation: dependencies.storageGeneration.continuation(for: token)
        )
    }
}

@MainActor
final class CollectionStorageBootstrap: ObservableObject {
    enum State {
        case loading
        case restoringFromCloud(CloudRestorationReadiness)
        case ready(session: CollectionStorageSession)
        case confirmationRequired(AccountAttachmentRequest)
        case accountConflict(AccountConflictSummary)
        case temporarilyUnavailable(String)
        case recoveryRequired(String)
    }

    @Published private(set) var state: State = .loading

    /// Test-only provenance guard for the shared bootstrap fixture. Production
    /// startup uses the default production dependency graph; storage tests must
    /// make that choice explicit through injection.
    var usesProductionDependencies: Bool {
        dependencies.usesProductionDependencies
    }

    private let dependencies: CollectionStorageBootstrapDependencies
    private var generation: UInt = 0
    private var proposedFreshStoreID: UUID?
    private var pendingAttachment: AccountAttachmentRequest?
    private var confirmationAccepted = false
    private var restorationContainer: ModelContainer?
    private var pendingRestoration: (storeID: UUID, accountFingerprint: String)?
    private var accountChangedObserver: NSObjectProtocol?
    private(set) var lastErrorCategory: String?

    init(dependencies: CollectionStorageBootstrapDependencies? = nil) {
        self.dependencies = dependencies ?? .production()
        if !Self.isPerformanceHarnessLaunch {
            accountChangedObserver = NotificationCenter.default.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleAccountChanged()
                }
            }
        }
    }

    deinit {
        if let accountChangedObserver {
            NotificationCenter.default.removeObserver(accountChangedObserver)
        }
    }

    func start() async {
        if let reusable = reusableUnprovenLocalSession() {
            generation &+= 1
            confirmationAccepted = false
            pendingAttachment = nil
            restorationContainer = nil
            pendingRestoration = nil
            lastErrorCategory = nil
            TradingCardScannerApp.activeStorageMode = reusable.session.mode
            TradingCardScannerApp.activeStoreID = reusable.session.storeID
            TradingCardScannerApp.activeCloudAccountStatusRaw = LocalStorageReason.restorationUnproven.rawValue
            TradingCardScannerApp.activeAttachmentStateRaw = reusable.attachmentState.rawValue
            TradingCardScannerApp.storageIsReady = true
            state = .ready(session: reusable.session)
            return
        }

        generation &+= 1
        let currentGeneration = generation
        dependencies.storageGeneration.suspend()
        PriceRefreshController.shared.cancelRefresh()
        MagicTreatmentMigrationCoordinator.shared.suspendStorageSession()
        TradingCardScannerApp.storageIsReady = false
        confirmationAccepted = false
        pendingAttachment = nil
        restorationContainer = nil
        pendingRestoration = nil
        lastErrorCategory = nil

        if Self.isPerformanceHarnessLaunch {
            await openPerformanceContainer(generation: currentGeneration)
            return
        }

        state = .loading
        await evaluate(generation: currentGeneration)
    }

    /// Reuse a headless or already-open local container when the local policy
    /// still selects that exact store under unproven readiness. This preserves
    /// the storage-generation token and avoids opening the same SQLite files a
    /// second time during background-to-foreground handoff.
    private func reusableUnprovenLocalSession() -> (
        session: CollectionStorageSession,
        attachmentState: CloudAttachmentState
    )? {
        guard !dependencies.readinessSource.isProven,
              let session = dependencies.storageGeneration.activeSession(),
              session.mode == .onDevice,
              let local = try? localFacts() else { return nil }
        let decision = CollectionStoragePolicy.decide(
            CollectionStoragePolicyInput(
                local: local,
                account: .notQueried,
                cloudRestorationReadinessProven: false
            )
        )
        guard case let .openProvenLocal(storeID, reason) = decision,
              storeID == session.storeID,
              reason == .restorationUnproven else { return nil }
        return (session, local.manifest?.attachmentState ?? .neverAttached)
    }

    func retry() async {
        await start()
    }

    func confirmAttachment() async {
        guard pendingAttachment != nil else { return }
        confirmationAccepted = true
        generation &+= 1
        let currentGeneration = generation
        restorationContainer = nil
        state = .loading
        await evaluate(generation: currentGeneration)
    }

    func keepOnDevice() async {
        if let request = pendingAttachment {
            await keepOnDevice(request: request)
            return
        }

        guard case .restoringFromCloud(.failed) = state,
              let restoration = pendingRestoration else { return }
        generation &+= 1
        let currentGeneration = generation
        restorationContainer = nil
        state = .loading
        do {
            try await openLocal(
                storeID: restoration.storeID,
                reason: .restorationUnproven,
                generation: currentGeneration
            )
        } catch {
            showRecovery(error, category: "restoration-fallback")
        }
    }

    private func keepOnDevice(request: AccountAttachmentRequest) async {
        generation &+= 1
        let currentGeneration = generation
        pendingAttachment = nil
        confirmationAccepted = false
        do {
            var manifest = try dependencies.manifestStore.load()
                ?? CollectionStoreManifest(storeID: request.storeID)
            manifest.attachmentState = .suspended
            try dependencies.manifestStore.save(manifest)
            try await openLocal(
                storeID: request.storeID,
                reason: .attachmentSuspended,
                generation: currentGeneration
            )
        } catch {
            showRecovery(error, category: "keep-on-device")
        }
    }

    private func evaluate(generation currentGeneration: UInt) async {
        do {
            let local = try localFacts()
            let readinessProven = dependencies.readinessSource.isProven
            let account = readinessProven
                ? await dependencies.accountAvailability()
                : CloudAccountAvailability.notQueried
            guard currentGeneration == generation else { return }

            let anchor: CloudCollectionAnchorState
            if case .available = account,
               readinessProven {
                anchor = await dependencies.anchorState()
            } else {
                anchor = .unknown
            }
            guard currentGeneration == generation else { return }

            let decision = CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: account,
                    anchor: anchor,
                    confirmationAccepted: confirmationAccepted,
                    cloudRestorationReadinessProven: readinessProven
                )
            )
            await apply(
                decision,
                local: local,
                account: account,
                anchor: anchor,
                generation: currentGeneration
            )
        } catch {
            showRecovery(error, category: "storage-preflight")
        }
    }

    private func localFacts() throws -> CollectionStorageLocalFacts {
        var manifest: CollectionStoreManifest?
        do {
            manifest = try dependencies.manifestStore.load()
        } catch let error as CollectionStoreManifestStoreError {
            throw error
        } catch {
            throw CollectionStoreManifestStoreError.readFailure
        }

        let filePresent = dependencies.structuredStoreFilePresent()
        let baseFilePresent = dependencies.structuredStoreBaseFilePresent()
        var localHasUserData = dependencies.localHasUserData()
        if manifest == nil, filePresent,
           let adoption = try dependencies.adoptLegacyStore() {
            manifest = adoption.manifest
            localHasUserData = adoption.localHasUserData
        }
        var storeFileIdentityStatus: CollectionStoreIdentityStatus = .matching
        if let manifest {
            guard !manifest.storeFileIdentity.isEmpty else {
                storeFileIdentityStatus = .mismatched
                return CollectionStorageLocalFacts(
                    manifest: manifest,
                    structuredStoreFilePresent: filePresent,
                    structuredStoreBaseFilePresent: baseFilePresent,
                    localHasUserData: localHasUserData,
                    proposedFreshStoreID: proposedFreshStoreID,
                    storeFileIdentityStatus: storeFileIdentityStatus
                )
            }
            guard let sidecar = try dependencies.readStoreFileIdentity() else {
                storeFileIdentityStatus = .missing
                return CollectionStorageLocalFacts(
                    manifest: manifest,
                    structuredStoreFilePresent: filePresent,
                    structuredStoreBaseFilePresent: baseFilePresent,
                    localHasUserData: localHasUserData,
                    proposedFreshStoreID: proposedFreshStoreID,
                    storeFileIdentityStatus: storeFileIdentityStatus
                )
            }
            storeFileIdentityStatus = sidecar == manifest.storeFileIdentity
                ? .matching
                : .mismatched
        }
        if manifest == nil, !filePresent, !localHasUserData {
            if proposedFreshStoreID == nil {
                proposedFreshStoreID = UUID()
            }
        }
        return CollectionStorageLocalFacts(
            manifest: manifest,
            structuredStoreFilePresent: filePresent,
            structuredStoreBaseFilePresent: baseFilePresent,
            localHasUserData: localHasUserData,
            proposedFreshStoreID: proposedFreshStoreID,
            storeFileIdentityStatus: storeFileIdentityStatus
        )
    }

    private func apply(
        _ decision: CollectionStorageDecision,
        local: CollectionStorageLocalFacts,
        account: CloudAccountAvailability,
        anchor: CloudCollectionAnchorState,
        generation currentGeneration: UInt
    ) async {
        guard currentGeneration == generation else { return }
        let existingAnchorGeneration = anchorGeneration(from: anchor)
        switch decision {
        case let .openCloud(storeID, accountFingerprint):
            if local.manifest == nil {
                await claimFreshAnchor(
                    storeID: storeID,
                    accountFingerprint: accountFingerprint,
                    generation: currentGeneration
                )
            } else {
                guard let existingAnchorGeneration else {
                    state = .recoveryRequired(
                        "CloudKit restoration has no anchor generation to verify against."
                    )
                    return
                }
                await openCloud(
                    storeID: storeID,
                    accountFingerprint: accountFingerprint,
                    generation: currentGeneration,
                    anchorGeneration: existingAnchorGeneration
                )
            }

        case let .claimCloudAnchor(storeID, accountFingerprint):
            await claimExistingAnchor(
                storeID: storeID,
                accountFingerprint: accountFingerprint,
                generation: currentGeneration
            )

        case let .adoptRemoteCollection(storeID, accountFingerprint):
            guard let existingAnchorGeneration else {
                state = .recoveryRequired(
                    "CloudKit restoration has no anchor generation to verify against."
                )
                return
            }
            await adoptRemoteCollection(
                storeID: storeID,
                accountFingerprint: accountFingerprint,
                generation: currentGeneration,
                anchorGeneration: existingAnchorGeneration
            )

        case let .restoreMissingLocalReplica(storeID, accountFingerprint):
            guard let existingAnchorGeneration else {
                state = .recoveryRequired(
                    "CloudKit restoration has no anchor generation to verify against."
                )
                return
            }
            await openCloud(
                storeID: storeID,
                accountFingerprint: accountFingerprint,
                generation: currentGeneration,
                anchorGeneration: existingAnchorGeneration,
                forceRestoration: true
            )

        case let .openProvenLocal(storeID, reason):
            do {
                try await openLocal(
                    storeID: storeID,
                    reason: reason,
                    generation: currentGeneration
                )
            } catch {
                showRecovery(error, category: "local-container")
            }

        case let .requireAttachmentConfirmation(storeID, newAccountFingerprint):
            let request = AccountAttachmentRequest(
                storeID: storeID,
                newAccountFingerprint: newAccountFingerprint
            )
            pendingAttachment = request
            state = .confirmationRequired(request)

        case let .blockDifferentRemoteCollection(localStoreID, remoteStoreID):
            pendingAttachment = nil
            state = .accountConflict(AccountConflictSummary(
                localStoreIDSuffix: Self.idSuffix(localStoreID),
                remoteStoreIDSuffix: Self.idSuffix(remoteStoreID)
            ))

        case .retryAccountCheck:
            state = .temporarilyUnavailable(
                "iCloud account status could not be verified safely. Retry when the device is online and signed in to iCloud."
            )

        case .blockUnprovenTransition:
            state = .recoveryRequired(
                "CardScanner found existing collection storage without trustworthy identity metadata. The original bytes were left untouched, and the app cannot safely open this collection on this device. Retry after confirming the storage configuration."
            )
        }
    }

    private func claimFreshAnchor(
        storeID: UUID,
        accountFingerprint: String,
        generation currentGeneration: UInt
    ) async {
        guard currentGeneration == generation else { return }
        switch await dependencies.claimAnchor(storeID) {
        case let .claimed(anchor) where isUsableAnchor(anchor, storeID: storeID):
            guard let anchorGeneration = anchorGeneration(from: anchor) else {
                state = .recoveryRequired(
                    "The newly claimed iCloud collection has no anchor generation."
                )
                return
            }
            await claimFreshAnchor(
                storeID: storeID,
                accountFingerprint: accountFingerprint,
                generation: currentGeneration,
                anchorGeneration: anchorGeneration
            )
        case let .alreadyClaimed(anchor):
            guard isSupportedAnchor(anchor) else {
                state = .recoveryRequired(
                    "The iCloud collection anchor uses an unsupported format. The local store was not attached."
                )
                return
            }
            guard let anchorGeneration = anchorGeneration(from: anchor) else {
                state = .recoveryRequired(
                    "The existing iCloud collection has no anchor generation."
                )
                return
            }
            await adoptRemoteCollection(
                storeID: anchor.storeID,
                accountFingerprint: accountFingerprint,
                generation: currentGeneration,
                anchorGeneration: anchorGeneration
            )
        case .claimed, .malformed:
            state = .recoveryRequired(
                "The iCloud collection anchor did not match the requested identity. The local store was not attached."
            )
        case .temporarilyUnavailable:
            state = .temporarilyUnavailable(
                "iCloud is not available right now. The new collection identity was not attached."
            )
        }
    }

    /// Completes a fresh claim only with the generation read back from the
    /// authoritative anchor. The overload keeps the pre-claim path free of a
    /// placeholder generation while making the open-cloud boundary require a
    /// non-optional value.
    private func claimFreshAnchor(
        storeID: UUID,
        accountFingerprint: String,
        generation currentGeneration: UInt,
        anchorGeneration: String
    ) async {
        guard !anchorGeneration.isEmpty else {
            state = .recoveryRequired(
                "The newly claimed iCloud collection has no anchor generation."
            )
            return
        }
        await openCloud(
            storeID: storeID,
            accountFingerprint: accountFingerprint,
            generation: currentGeneration,
            anchorGeneration: anchorGeneration,
            anchorClaimedThisLaunch: true
        )
    }

    private func claimExistingAnchor(
        storeID: UUID,
        accountFingerprint: String,
        generation currentGeneration: UInt
    ) async {
        guard currentGeneration == generation else { return }
        switch await dependencies.claimAnchor(storeID) {
        case let .claimed(anchor) where isUsableAnchor(anchor, storeID: storeID):
            guard let anchorGeneration = anchorGeneration(from: anchor) else {
                state = .recoveryRequired(
                    "The newly claimed iCloud collection has no anchor generation."
                )
                return
            }
            await claimExistingAnchor(
                storeID: storeID,
                accountFingerprint: accountFingerprint,
                generation: currentGeneration,
                anchorGeneration: anchorGeneration
            )
        case let .alreadyClaimed(anchor):
            guard isSupportedAnchor(anchor) else {
                state = .recoveryRequired("The iCloud collection anchor could not be verified.")
                return
            }
            if anchor.storeID == storeID {
                guard let anchorGeneration = anchorGeneration(from: anchor) else {
                    state = .recoveryRequired(
                        "The existing iCloud collection has no anchor generation."
                    )
                    return
                }
                await claimExistingAnchor(
                    storeID: storeID,
                    accountFingerprint: accountFingerprint,
                    generation: currentGeneration,
                    anchorGeneration: anchorGeneration
                )
            } else {
                state = .accountConflict(AccountConflictSummary(
                    localStoreIDSuffix: Self.idSuffix(storeID),
                    remoteStoreIDSuffix: Self.idSuffix(anchor.storeID)
                ))
            }
        case .claimed, .malformed:
            state = .recoveryRequired("The iCloud collection anchor could not be verified.")
        case .temporarilyUnavailable:
            state = .temporarilyUnavailable("iCloud is temporarily unavailable. Retry to verify collection ownership.")
        }
    }

    /// Completes an existing-anchor claim with the freshly read generation,
    /// which is more authoritative than any pre-claim snapshot.
    private func claimExistingAnchor(
        storeID: UUID,
        accountFingerprint: String,
        generation currentGeneration: UInt,
        anchorGeneration: String
    ) async {
        guard !anchorGeneration.isEmpty else {
            state = .recoveryRequired(
                "The existing iCloud collection has no anchor generation."
            )
            return
        }
        await openCloud(
            storeID: storeID,
            accountFingerprint: accountFingerprint,
            generation: currentGeneration,
            anchorGeneration: anchorGeneration
        )
    }

    private func isUsableAnchor(
        _ anchor: CloudCollectionAnchor,
        storeID: UUID
    ) -> Bool {
        isSupportedAnchor(anchor) && anchor.storeID == storeID
    }

    private func isSupportedAnchor(_ anchor: CloudCollectionAnchor) -> Bool {
        anchor.formatVersion == CloudCollectionAnchorSchema.currentFormatVersion
            && anchorGeneration(from: anchor) != nil
    }

    private func anchorGeneration(from state: CloudCollectionAnchorState) -> String? {
        guard case let .found(anchor) = state else { return nil }
        return anchorGeneration(from: anchor)
    }

    private func anchorGeneration(from anchor: CloudCollectionAnchor) -> String? {
        guard let remoteGeneration = anchor.remoteGeneration,
              !remoteGeneration.isEmpty else {
            return nil
        }
        return remoteGeneration
    }

    private func adoptRemoteCollection(
        storeID: UUID,
        accountFingerprint: String,
        generation currentGeneration: UInt,
        anchorGeneration: String
    ) async {
        await openCloud(
            storeID: storeID,
            accountFingerprint: accountFingerprint,
            generation: currentGeneration,
            anchorGeneration: anchorGeneration,
            forceRestoration: true
        )
    }

    private func openCloud(
        storeID: UUID,
        accountFingerprint: String,
        generation currentGeneration: UInt,
        anchorGeneration: String,
        anchorClaimedThisLaunch: Bool = false,
        forceRestoration: Bool = false
    ) async {
        guard currentGeneration == generation else { return }
        guard !anchorGeneration.isEmpty else {
            state = .recoveryRequired(
                "CloudKit restoration has no anchor generation to verify against."
            )
            return
        }
        do {
            pendingRestoration = (storeID, accountFingerprint)
            let replacementStoreFileIdentity: String?
            if forceRestoration {
                replacementStoreFileIdentity = try dependencies.manifestStore.makeStoreFileIdentity()
            } else {
                replacementStoreFileIdentity = nil
            }
            let preflightAttachmentState = try dependencies.manifestStore.load()?.attachmentState
                ?? .neverAttached
            try persistManifest(
                storeID: storeID,
                accountFingerprint: accountFingerprint,
                // Establish identity and physical-file metadata before the
                // container exists, but do not claim CloudKit attachment until
                // the affirmative readiness result below.
                attachmentState: preflightAttachmentState,
                invalidateRestoreCheckpoint: forceRestoration,
                replacementStoreFileIdentity: replacementStoreFileIdentity
            )
            let request = CloudRestorationRequest(
                bootstrapGeneration: currentGeneration,
                storeID: storeID,
                expectedAnchorGeneration: anchorGeneration,
                accountFingerprint: accountFingerprint,
                anchorClaimedThisLaunch: anchorClaimedThisLaunch
            )
            let probe = dependencies.readinessSource.arm(request)
            defer { probe.cancel() }
            let container = try dependencies.makeContainer(.cloudKit)
            guard currentGeneration == generation else { return }
            restorationContainer = container
            state = .restoringFromCloud(.checkingRemoteCollection)

            var readiness = await probe.awaitReadiness(container: container)
            while currentGeneration == generation {
                switch readiness {
                case .readyEmpty, .readyPopulated:
                    try persistManifest(
                        storeID: storeID,
                        accountFingerprint: accountFingerprint,
                        attachmentState: .attached
                    )
                    try persistRestoreCheckpoint(
                        storeID: storeID,
                        accountFingerprint: accountFingerprint,
                        readiness: readiness,
                        anchorGeneration: anchorGeneration
                    )
                    TradingCardScannerApp.activeCloudAccountStatusRaw = "available"
                    TradingCardScannerApp.activeAttachmentStateRaw = CloudAttachmentState.attached.rawValue
                    installReady(
                        session: CollectionStorageSession(
                            container: container,
                            storeID: storeID,
                            mode: .cloudKit
                        ),
                        generation: currentGeneration
                    )
                    return
                case .notApplicable:
                    state = .recoveryRequired("CloudKit restoration did not provide a readiness proof.")
                    return
                case .checkingRemoteCollection, .importingRemoteCollection, .failed:
                    state = .restoringFromCloud(readiness)
                    if case .failed = readiness { return }
                    readiness = await probe.awaitReadiness(container: container)
                }
            }
        } catch {
            showRecovery(error, category: "cloud-container")
        }
    }

    private func openLocal(
        storeID: UUID,
        reason: LocalStorageReason,
        generation currentGeneration: UInt
    ) async throws {
        guard currentGeneration == generation else { return }
        let existingManifest = try dependencies.manifestStore.load()
        let targetAttachmentState: CloudAttachmentState
        if existingManifest == nil || existingManifest?.attachmentState == .neverAttached {
            targetAttachmentState = reason == .attachmentSuspended ? .suspended : .neverAttached
        } else if reason == .temporarilyUnavailable {
            targetAttachmentState = existingManifest?.attachmentState ?? .suspended
        } else {
            targetAttachmentState = .suspended
        }
        try persistManifest(
            storeID: storeID,
            accountFingerprint: nil,
            attachmentState: targetAttachmentState
        )
        TradingCardScannerApp.activeCloudAccountStatusRaw = reason.rawValue
        TradingCardScannerApp.activeAttachmentStateRaw = targetAttachmentState.rawValue
        let container = try dependencies.makeContainer(.onDevice)
        guard currentGeneration == generation else { return }
        installReady(
            session: CollectionStorageSession(
                container: container,
                storeID: storeID,
                mode: .onDevice
            ),
            generation: currentGeneration
        )
    }

    private func persistManifest(
        storeID: UUID,
        accountFingerprint: String?,
        attachmentState: CloudAttachmentState,
        invalidateRestoreCheckpoint: Bool = false,
        replacementStoreFileIdentity: String? = nil
    ) throws {
        var manifest = try dependencies.manifestStore.load()
            ?? CollectionStoreManifest(storeID: storeID)
        guard manifest.storeID == storeID else {
            throw CollectionStoreManifestStoreError.invalidStoreIdentity
        }
        if let replacementStoreFileIdentity {
            // A forced restoration creates/replaces the physical replica. Bind
            // its new opaque identity before the CloudKit container is opened;
            // readiness authority remains checkpoint-only.
            try dependencies.manifestStore.writeStoreFileIdentity(
                replacementStoreFileIdentity
            )
            manifest.storeFileIdentity = replacementStoreFileIdentity
        } else if manifest.storeFileIdentity.isEmpty {
            manifest.storeFileIdentity = try dependencies.storeFileIdentity()
        }
        let accountChanged = accountFingerprint.map {
            manifest.lastAttachedAccountFingerprint != nil
                && manifest.lastAttachedAccountFingerprint != $0
        } ?? false
        manifest.lastAttachedAccountFingerprint = accountFingerprint
            ?? manifest.lastAttachedAccountFingerprint
        if manifest.attachmentState != attachmentState {
            try CollectionStoreManifestStore.validateAttachmentTransition(
                from: manifest.attachmentState,
                to: attachmentState
            )
        }
        manifest.attachmentState = attachmentState
        if accountChanged || attachmentState != .attached || invalidateRestoreCheckpoint {
            manifest.cloudRestoreCheckpoint = nil
        }
        try dependencies.manifestStore.save(manifest)
    }

    private func persistRestoreCheckpoint(
        storeID: UUID,
        accountFingerprint: String,
        readiness: CloudRestorationReadiness,
        anchorGeneration: String
    ) throws {
        var manifest = try dependencies.manifestStore.load()
            ?? CollectionStoreManifest(storeID: storeID)
        guard manifest.storeID == storeID else {
            throw CollectionStoreManifestStoreError.invalidStoreIdentity
        }
        guard !manifest.storeFileIdentity.isEmpty else {
            throw CollectionStoreManifestStoreError.invalidStoreIdentity
        }
        let checkpointReadiness: CloudRestoreCheckpointReadiness
        switch readiness {
        case .readyEmpty:
            checkpointReadiness = .empty
        case .readyPopulated:
            checkpointReadiness = .populated
        case .notApplicable, .checkingRemoteCollection, .importingRemoteCollection, .failed:
            throw CollectionStoreManifestStoreError.invalidStoreIdentity
        }
        manifest.cloudRestoreCheckpoint = CloudRestoreCheckpoint(
            storeID: storeID,
            accountFingerprint: accountFingerprint,
            storeFileIdentity: manifest.storeFileIdentity,
            mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
            readiness: checkpointReadiness,
            remoteGeneration: anchorGeneration,
            confirmedAt: .now
        )
        try dependencies.manifestStore.save(manifest)
    }

    private func installReady(
        session: CollectionStorageSession,
        generation currentGeneration: UInt
    ) {
        guard currentGeneration == generation else { return }
        restorationContainer = nil
        pendingRestoration = nil
        pendingAttachment = nil
        confirmationAccepted = false
        dependencies.storageGeneration.installReady(session: session)
        TradingCardScannerApp.activeStorageMode = session.mode
        TradingCardScannerApp.storageIsReady = true
        TradingCardScannerApp.activeStoreID = session.storeID
        TradingCardScannerApp.lastBootstrapErrorCategory = nil
        CollectionArtworkStore.migrateLegacyMappings(in: ModelContext(session.container))
        state = .ready(session: session)
    }

    private func openPerformanceContainer(generation currentGeneration: UInt) async {
        do {
            let configuration = ModelConfiguration(
                "CardFinishPerformance",
                schema: CollectionStorageModelSchema.full,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: CollectionStorageModelSchema.full,
                configurations: [configuration]
            )
            installReady(
                session: CollectionStorageSession(
                    container: container,
                    storeID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    mode: .onDevice
                ),
                generation: currentGeneration
            )
        } catch {
            showRecovery(error, category: "performance-container")
        }
    }

    private func handleAccountChanged() async {
        guard dependencies.readinessSource.isProven else { return }
        guard case .ready = state else {
            await retry()
            return
        }
        TradingCardScannerApp.storageIsReady = false
        dependencies.storageGeneration.suspend()
        PriceRefreshController.shared.cancelRefresh()
        MagicTreatmentMigrationCoordinator.shared.suspendStorageSession()
        generation &+= 1
        restorationContainer = nil
        state = .temporarilyUnavailable(
            "The iCloud account changed. Collection writes and background work are paused until storage is verified again."
        )
        await evaluate(generation: generation)
    }

    private func showRecovery(_ error: Error, category: String) {
        lastErrorCategory = category
        dependencies.storageGeneration.suspend()
        PriceRefreshController.shared.cancelRefresh()
        MagicTreatmentMigrationCoordinator.shared.suspendStorageSession()
        TradingCardScannerApp.storageIsReady = false
        TradingCardScannerApp.lastBootstrapErrorCategory = category
        state = .recoveryRequired(error.localizedDescription)
    }

    static func idSuffix(_ storeID: UUID) -> String {
        String(storeID.uuidString.replacingOccurrences(of: "-", with: "").lowercased().suffix(8))
    }

    private static var isPerformanceHarnessLaunch: Bool {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_route"),
              arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "CollectionFinishPerformance"
#else
        return false
#endif
    }
}
