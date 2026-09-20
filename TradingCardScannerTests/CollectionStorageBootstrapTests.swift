import SwiftData
import XCTest
@testable import TradingCardScanner

private enum BootstrapTestError: Error {
    case containerConstruction
}

@MainActor
private final class RecordingReadinessProbe: CloudRestorationProbe {
    let result: CloudRestorationReadiness
    private var cancelled = false

    init(result: CloudRestorationReadiness) {
        self.result = result
    }

    func awaitReadiness(container: ModelContainer) async -> CloudRestorationReadiness {
        cancelled ? .failed(category: "recording-probe-cancelled") : result
    }

    func cancel() {
        cancelled = true
    }
}

@MainActor
private final class RecordingReadinessSource: @unchecked Sendable, CloudRestorationReadinessSource {
    let result: CloudRestorationReadiness
    private(set) var requests: [CloudRestorationRequest] = []
    var armCall: (() -> Void)?

    var isProven: Bool { true }

    init(result: CloudRestorationReadiness) {
        self.result = result
    }

    func arm(_ request: CloudRestorationRequest) -> any CloudRestorationProbe {
        requests.append(request)
        armCall?()
        return RecordingReadinessProbe(result: result)
    }
}

@MainActor
private final class ScriptedReadinessProbe: CloudRestorationProbe {
    private var results: [CloudRestorationReadiness]
    private var cancelled = false
    private(set) var awaitCount = 0

    init(results: [CloudRestorationReadiness]) {
        self.results = results
    }

    func awaitReadiness(container: ModelContainer) async -> CloudRestorationReadiness {
        awaitCount += 1
        guard !cancelled else {
            return .failed(category: "scripted-probe-cancelled")
        }
        guard !results.isEmpty else {
            return .failed(category: "scripted-probe-exhausted")
        }
        return results.removeFirst()
    }

    func cancel() {
        cancelled = true
    }
}

@MainActor
private final class ScriptedReadinessSource: @unchecked Sendable, CloudRestorationReadinessSource {
    private let results: [CloudRestorationReadiness]
    private(set) var probe: ScriptedReadinessProbe?

    var isProven: Bool { true }

    init(results: [CloudRestorationReadiness]) {
        self.results = results
    }

    func arm(_ request: CloudRestorationRequest) -> any CloudRestorationProbe {
        let probe = ScriptedReadinessProbe(results: results)
        self.probe = probe
        return probe
    }
}

@MainActor
final class CollectionStorageBootstrapTests: XCTestCase {
    private let localID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let remoteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makeDependencies(
        account: @escaping @MainActor () async -> CloudAccountAvailability,
        anchor: @escaping @MainActor () async -> CloudCollectionAnchorState = { .missing },
        claim: @escaping @MainActor (UUID) async -> CloudCollectionAnchorClaimResult = { storeID in
            .claimed(CloudCollectionAnchor(
                storeID: storeID,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                remoteGeneration: "test-generation"
            ))
        },
        readiness: any CloudRestorationReadinessSource = FixedCloudRestorationReadinessSource(
            result: .readyEmpty
        ),
        makeContainer: (@MainActor (CollectionStorageMode) throws -> ModelContainer)? = nil,
        structuredStoreFilePresent: Bool = false,
        structuredStoreBaseFilePresent: Bool? = nil,
        structuredStorePresence: (@MainActor () -> Bool)? = nil,
        storeFileIdentityValue: String? = nil,
        sidecarPresent: Bool? = nil,
        directorySuffix: String = UUID().uuidString
    ) throws -> CollectionStorageBootstrapDependencies {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardScannerBootstrapTests-\(directorySuffix)", isDirectory: true)
        let paths = CollectionStoragePaths(
            applicationSupportURL: directory,
            collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage", isDirectory: true),
            structuredStoreURL: directory.appendingPathComponent("CollectionStorage/CardScannerCollection.store"),
            portfolioStoreURL: directory.appendingPathComponent("CollectionStorage/PortfolioLocal.store")
        )
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL
        )
        let factory = makeContainer ?? { _ in
            try ModelContainer(
                for: CollectionStorageModelSchema.full,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
        }
        return CollectionStorageBootstrapDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: account,
            anchorState: anchor,
            claimAnchor: claim,
            makeContainer: factory,
            readinessSource: readiness,
            structuredStoreFilePresent: {
                structuredStorePresence?() ?? structuredStoreFilePresent
            },
            structuredStoreBaseFilePresent: {
                structuredStorePresence?()
                    ?? (structuredStoreBaseFilePresent ?? structuredStoreFilePresent)
            },
            localHasUserData: { false },
            storeFileIdentity: { "test-store-file-identity" },
            readStoreFileIdentity: {
                if let sidecarPresent {
                    guard sidecarPresent else { return nil }
                    return storeFileIdentityValue ?? "test-store-file-identity"
                }
                if let storeFileIdentityValue { return storeFileIdentityValue }
                if let persisted = try manifestStore.readStoreFileIdentity() {
                    return persisted
                }
                return structuredStoreFilePresent ? "test-store-file-identity" : nil
            },
            adoptLegacyStore: { nil }
        )
    }

    func testProductionPathsPreserveThePreBootstrapStoreLocations() {
        let paths = CollectionStoragePaths.production()
        XCTAssertEqual(paths.structuredStoreURL.lastPathComponent, "default.store")
        XCTAssertEqual(paths.portfolioStoreURL.lastPathComponent, "PortfolioLocal.store")
        XCTAssertEqual(
            paths.collectionStorageDirectoryURL.lastPathComponent,
            "CollectionStorage"
        )
    }

#if LOCAL_ONLY_SIGNING
    func testLocalOnlyBuildRejectsCloudKitConfigurationForEntitlementReason() throws {
        let dependencies = CollectionStorageBootstrapDependencies.production()
        XCTAssertThrowsError(try dependencies.makeContainer(.cloudKit)) { error in
            XCTAssertEqual(
                error as? CollectionStorageBootstrapError,
                .cloudKitUnavailableInLocalOnlyBuild
            )
        }
    }
    #endif

#if !LOCAL_ONLY_SIGNING
    func testProductionDependencyGraphRequiresExplicitEntitledIntegrationOptIn() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TCS_ENTITLED_INTEGRATION"] == "1",
            "Production dependency wiring is reserved for explicitly entitled integration tests."
        )
        let dependencies = CollectionStorageBootstrapDependencies.production()
        XCTAssertTrue(dependencies.usesProductionDependencies)
    }
#endif

#if DEBUG
    func testDebugProductionStorageSuiteUsesInjectedAccountAvailability() throws {
        let dependencies = try makeDependencies(account: { .noAccount })
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)
        XCTAssertFalse(
            bootstrap.usesProductionDependencies,
            "Storage tests must construct the bootstrap with injected dependencies."
        )
    }
#endif

    func testStorageGenerationFencesCompletionsFromAnOlderSession() throws {
        let generation = CollectionStorageGeneration()
        generation.installReady(storeID: localID)
        let token = try XCTUnwrap(generation.currentToken())
        let continuation = generation.continuation(for: token)
        XCTAssertTrue(generation.isCurrent(token))
        XCTAssertTrue(continuation())

        generation.suspend()
        XCTAssertFalse(generation.isCurrent(token))
        XCTAssertFalse(continuation())

        generation.installReady(storeID: remoteID)
        XCTAssertFalse(generation.isCurrent(token))
        XCTAssertTrue(
            generation.isCurrent(
                try XCTUnwrap(generation.currentToken())
            )
        )
    }

    func testFreshNoAccountOpensOneProvenLocalSession() async throws {
        let dependencies = try makeDependencies(account: { .noAccount })
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .ready(session) = bootstrap.state else {
            return XCTFail("expected a ready local session")
        }
        XCTAssertNotEqual(
            session.storeID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        )
        XCTAssertEqual(session.mode, .onDevice)
        let manifest = try XCTUnwrap(try dependencies.manifestStore.load())
        XCTAssertEqual(manifest.storeID, session.storeID)
        XCTAssertEqual(manifest.attachmentState, .neverAttached)
        XCTAssertNil(manifest.lastAttachedAccountFingerprint)
        XCTAssertEqual(TradingCardScannerApp.activeCloudAccountStatusRaw, "noAccount")
        XCTAssertEqual(TradingCardScannerApp.activeAttachmentStateRaw, "neverAttached")
    }

    func testFreshAvailableAccountClaimsAndOpensCloudOnlyAfterReadinessProof() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            readiness: FixedCloudRestorationReadinessSource(
                result: .readyPopulated
            )
        )
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .ready(session) = bootstrap.state else {
            return XCTFail("expected a ready cloud session")
        }
        XCTAssertEqual(session.mode, .cloudKit)
        let manifest = try XCTUnwrap(try dependencies.manifestStore.load())
        XCTAssertTrue(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                manifest.cloudRestoreCheckpoint,
                storeID: session.storeID,
                accountFingerprint: "account-a",
                storeFileIdentity: "test-store-file-identity",
                mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
                currentRemoteGeneration: "test-generation"
            )
        )
    }

    func testUnprovenProductionReadinessUsesSafeLocalFallback() async throws {
        var requestedModes: [CollectionStorageMode] = []
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            readiness: UnprovenCloudRestorationReadinessSource(),
            makeContainer: { mode in
                requestedModes.append(mode)
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            }
        )
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .ready(session) = bootstrap.state else {
            return XCTFail("an unproven production readiness source must fall back locally")
        }
        XCTAssertEqual(session.mode, .onDevice)
        XCTAssertEqual(requestedModes, [.onDevice])
        XCTAssertEqual(
            try dependencies.manifestStore.load()?.attachmentState,
            .neverAttached
        )
    }

    func testReadinessIsArmedBeforeContainerAndNoSessionExistsBeforeProof() async throws {
        var callOrder: [String] = []
        let generation = CollectionStorageGeneration()
        let readiness = RecordingReadinessSource(result: .readyPopulated)
        readiness.armCall = { callOrder.append("arm") }
        var dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: {
                .found(CloudCollectionAnchor(
                    storeID: self.localID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            readiness: readiness,
            makeContainer: { _ in
                callOrder.append("makeContainer")
                XCTAssertNil(generation.activeSession())
                XCTAssertFalse(TradingCardScannerApp.storageIsReady)
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            structuredStoreFilePresent: true
        )
        dependencies.storageGeneration = generation
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        XCTAssertEqual(callOrder, ["arm", "makeContainer"])
        XCTAssertEqual(readiness.requests.count, 1)
        XCTAssertEqual(readiness.requests[0].expectedAnchorGeneration, "test-generation")
        guard case .ready = bootstrap.state else {
            return XCTFail("expected readiness proof to install the cloud session")
        }
    }

    func testOpenCloudReevaluatesReadinessUntilTheProbeReachesReady() async throws {
        let readiness = ScriptedReadinessSource(results: [
            .checkingRemoteCollection,
            .importingRemoteCollection,
            .readyPopulated
        ])
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: {
                .found(CloudCollectionAnchor(
                    storeID: self.localID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            readiness: readiness,
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        XCTAssertEqual(readiness.probe?.awaitCount, 3)
        guard case .ready = bootstrap.state else {
            return XCTFail("expected the scripted readiness progression to reach ready")
        }
    }

    func testThrowingContainerConstructionCancelsAllArmedObservers() async throws {
        let notificationCenter = NotificationCenter()
        let readiness = CloudKitEventReadinessSource(notificationCenter: notificationCenter)
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: {
                .found(CloudCollectionAnchor(
                    storeID: self.localID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            readiness: readiness,
            makeContainer: { _ in
                throw BootstrapTestError.containerConstruction
            },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        XCTAssertEqual(readiness.activeProbeForTesting?.registeredObserverCount, 0)
        guard case .recoveryRequired = bootstrap.state else {
            return XCTFail("expected the throwing container to enter recovery")
        }
    }

    func testExistingCollectionWithNewAccountStopsAtConfirmation() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-b") },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .confirmationRequired(request) = bootstrap.state else {
            return XCTFail("expected attachment confirmation")
        }
        XCTAssertEqual(request.storeID, localID)
        XCTAssertEqual(request.newAccountFingerprint, "account-b")
    }

    func testCancelConfirmationKeepsIdentityAndOpensLocal() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-b") },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()
        await bootstrap.keepOnDevice()

        guard case let .ready(session) = bootstrap.state else {
            return XCTFail("expected local session after cancellation")
        }
        XCTAssertEqual(session.storeID, localID)
        XCTAssertEqual(session.mode, .onDevice)
        XCTAssertEqual(try dependencies.manifestStore.load()?.attachmentState, .suspended)
        XCTAssertEqual(TradingCardScannerApp.activeCloudAccountStatusRaw, "attachmentSuspended")
        XCTAssertEqual(TradingCardScannerApp.activeAttachmentStateRaw, "suspended")
    }

    func testDifferentRemoteCollectionNeverOpensEitherCollection() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: {
                .found(CloudCollectionAnchor(
                    storeID: self.remoteID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .accountConflict(summary) = bootstrap.state else {
            return XCTFail("expected account conflict")
        }
        XCTAssertEqual(summary.localStoreIDSuffix, CollectionStorageBootstrap.idSuffix(localID))
        XCTAssertEqual(summary.remoteStoreIDSuffix, CollectionStorageBootstrap.idSuffix(remoteID))
    }

    func testTemporaryAccountFailureDoesNotCreateAContainerOrNewIdentity() async throws {
        var makeCount = 0
        let dependencies = try makeDependencies(
            account: { .temporarilyUnavailable },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            }
        )
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case .temporarilyUnavailable = bootstrap.state else {
            return XCTFail("expected temporary unavailability")
        }
        XCTAssertEqual(makeCount, 0)
        XCTAssertNil(try dependencies.manifestStore.load())
    }

    func testTemporaryAccountAvailabilityOpensLocallyWithoutChangingAttachedFingerprint() async throws {
        let dependencies = try makeDependencies(
            account: { .temporarilyUnavailable },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .ready(session) = bootstrap.state else {
            return XCTFail("expected the existing store to open locally during a transient outage")
        }
        XCTAssertEqual(session.mode, .onDevice)
        let manifest = try XCTUnwrap(try dependencies.manifestStore.load())
        XCTAssertEqual(manifest.lastAttachedAccountFingerprint, "account-a")
        XCTAssertEqual(manifest.attachmentState, .attached)
        XCTAssertEqual(
            TradingCardScannerApp.activeCloudAccountStatusRaw,
            LocalStorageReason.temporarilyUnavailable.rawValue
        )
        XCTAssertEqual(TradingCardScannerApp.activeAttachmentStateRaw, CloudAttachmentState.attached.rawValue)
    }

    func testRestrictedAndUnknownAccountAvailabilityOpenExistingStoreLocally() async throws {
        let accountStates: [CloudAccountAvailability] = [
            .noAccount,
            .restricted,
            .couldNotDetermine
        ]
        for (index, accountState) in accountStates.enumerated() {
            let dependencies = try makeDependencies(
                account: { accountState },
                structuredStoreFilePresent: true,
                directorySuffix: "local-availability-\(index)"
            )
            try dependencies.manifestStore.save(CollectionStoreManifest(
                storeID: localID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "test-store-file-identity"
            ))
            let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

            await bootstrap.start()

            guard case let .ready(session) = bootstrap.state else {
                return XCTFail("expected local readiness for account state \(accountState)")
            }
            XCTAssertEqual(session.mode, .onDevice)
            XCTAssertEqual(
                try dependencies.manifestStore.load()?.lastAttachedAccountFingerprint,
                "account-a"
            )
        }
    }

    func testCorruptReplicaStatesNeverOpenACloudContainer() async throws {
        for (basePresent, filePresent, sidecar) in [
            (true, true, Optional<String>.none),
            (true, true, Optional("different-file-identity")),
            (false, true, Optional("test-store-file-identity"))
        ] {
            var makeCount = 0
            let dependencies = try makeDependencies(
                account: { .available(fingerprint: "account-a") },
                anchor: {
                    .found(CloudCollectionAnchor(
                        storeID: self.localID,
                        formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                        remoteGeneration: "test-generation"
                    ))
                },
                makeContainer: { _ in
                    makeCount += 1
                    return try ModelContainer(
                        for: CollectionStorageModelSchema.full,
                        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                    )
                },
                structuredStoreFilePresent: filePresent,
                structuredStoreBaseFilePresent: basePresent,
                storeFileIdentityValue: sidecar,
                sidecarPresent: sidecar != nil
            )
            try dependencies.manifestStore.save(CollectionStoreManifest(
                storeID: localID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "test-store-file-identity"
            ))

            let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)
            await bootstrap.start()

            guard case .recoveryRequired = bootstrap.state else {
                return XCTFail("expected recovery for corrupt replica state")
            }
            XCTAssertEqual(makeCount, 0)
        }
    }

    func testCloudRestorationFailureDoesNotRenderReadyEmptyCollection() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            readiness: FixedCloudRestorationReadinessSource(result: .failed(category: "test-proof-missing"))
        )
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .restoringFromCloud(.failed(category)) = bootstrap.state else {
            return XCTFail("expected fail-closed restoration state")
        }
        XCTAssertEqual(category, "test-proof-missing")

        let failedManifest = try XCTUnwrap(try dependencies.manifestStore.load())
        XCTAssertEqual(
            failedManifest.attachmentState,
            .neverAttached,
            "a failed readiness attempt must not claim CloudKit attachment"
        )

        await bootstrap.keepOnDevice()

        guard case let .ready(session) = bootstrap.state else {
            return XCTFail("failed restoration should offer a local recovery path")
        }
        XCTAssertEqual(session.mode, .onDevice)
        XCTAssertEqual(
            try dependencies.manifestStore.load()?.attachmentState,
            .neverAttached
        )
    }

    func testFailedRemoteAdoptionRetainsIdentityAndRetriesRestorationOnRelaunch() async throws {
        var replicaPresent = false
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: {
                .found(CloudCollectionAnchor(
                    storeID: self.localID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            readiness: FixedCloudRestorationReadinessSource(
                result: .failed(category: "test-proof-missing")
            ),
            makeContainer: { _ in
                replicaPresent = true
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            structuredStoreFilePresent: false,
            structuredStoreBaseFilePresent: false,
            structuredStorePresence: { replicaPresent }
        )
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case let .restoringFromCloud(.failed(category)) = bootstrap.state else {
            return XCTFail("expected the first launch to remain in restoration")
        }
        XCTAssertEqual(category, "test-proof-missing")
        XCTAssertTrue(replicaPresent)
        let firstManifest = try XCTUnwrap(try dependencies.manifestStore.load())
        let firstIdentity = try XCTUnwrap(
            try dependencies.manifestStore.readStoreFileIdentity()
        )
        XCTAssertEqual(firstManifest.storeFileIdentity, firstIdentity)
        XCTAssertNil(firstManifest.cloudRestoreCheckpoint)

        await bootstrap.start()

        guard case let .restoringFromCloud(.failed(category)) = bootstrap.state else {
            return XCTFail("expected relaunch to retry restoration, not require support")
        }
        XCTAssertEqual(category, "test-proof-missing")
        let retryManifest = try XCTUnwrap(try dependencies.manifestStore.load())
        let retryIdentity = try XCTUnwrap(
            try dependencies.manifestStore.readStoreFileIdentity()
        )
        XCTAssertEqual(retryManifest.storeFileIdentity, firstIdentity)
        XCTAssertEqual(retryIdentity, firstIdentity)
    }

    func testSuccessfulMissingReplicaRestorationRotatesStoreFileIdentity() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: {
                .found(CloudCollectionAnchor(
                    storeID: self.localID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            readiness: FixedCloudRestorationReadinessSource(
                result: .readyPopulated
            ),
            structuredStoreFilePresent: false,
            structuredStoreBaseFilePresent: false,
            storeFileIdentityValue: nil
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "old-file-identity"
        ))

        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)
        await bootstrap.start()

        guard case .ready = bootstrap.state else {
            return XCTFail("expected restored cloud session")
        }
        let manifest = try XCTUnwrap(try dependencies.manifestStore.load())
        let activeIdentity = try XCTUnwrap(try dependencies.manifestStore.readStoreFileIdentity())
        XCTAssertEqual(manifest.storeFileIdentity, activeIdentity)
        XCTAssertNotEqual(activeIdentity, "old-file-identity")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dependencies.manifestStore.directoryURL
                    .appendingPathComponent("store-file.identity.previous")
                    .path
            )
        )
    }

    func testConfirmedNewAccountClaimsBeforeConstructingCloudContainer() async throws {
        var claimCount = 0
        var makeCount = 0
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-b") },
            claim: { storeID in
                claimCount += 1
                return .claimed(CloudCollectionAnchor(
                    storeID: storeID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()
        await bootstrap.confirmAttachment()

        XCTAssertEqual(claimCount, 1)
        XCTAssertEqual(makeCount, 1)
        guard case .ready = bootstrap.state else {
            return XCTFail("expected the claimed account to reach ready after readiness proof")
        }
    }

    func testRacingDifferentClaimProducesConflictWithoutConstructingContainer() async throws {
        var makeCount = 0
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-b") },
            claim: { _ in
                .alreadyClaimed(CloudCollectionAnchor(
                    storeID: self.remoteID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "test-generation"
                ))
            },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()
        await bootstrap.confirmAttachment()

        guard case .accountConflict = bootstrap.state else {
            return XCTFail("expected a racing remote identity conflict")
        }
        XCTAssertEqual(makeCount, 0)
    }

    func testTemporaryClaimFailureLeavesOriginalAttachmentMetadata() async throws {
        var makeCount = 0
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-b") },
            claim: { _ in .temporarilyUnavailable },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            structuredStoreFilePresent: true
        )
        try dependencies.manifestStore.save(CollectionStoreManifest(
            storeID: localID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "test-store-file-identity"
        ))
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()
        await bootstrap.confirmAttachment()

        guard case .temporarilyUnavailable = bootstrap.state else {
            return XCTFail("expected a retryable claim failure")
        }
        let manifest = try XCTUnwrap(try dependencies.manifestStore.load())
        XCTAssertEqual(manifest.lastAttachedAccountFingerprint, "account-a")
        XCTAssertEqual(manifest.attachmentState, .attached)
        XCTAssertEqual(makeCount, 0)
    }

    func testCorruptManifestUsesRecoveryAndLeavesStoreUntouched() async throws {
        let dependencies = try makeDependencies(account: { .noAccount })
        try FileManager.default.createDirectory(
            at: dependencies.manifestStore.directoryURL,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: dependencies.manifestStore.manifestURL)
        let bootstrap = CollectionStorageBootstrap(dependencies: dependencies)

        await bootstrap.start()

        guard case .recoveryRequired = bootstrap.state else {
            return XCTFail("expected recovery state")
        }
        XCTAssertEqual(
            try String(contentsOf: dependencies.manifestStore.manifestURL),
            "not-json"
        )
    }

    func testManifestSaveNeverOverwritesCorruptMetadata() throws {
        let dependencies = try makeDependencies(account: { .noAccount })
        try FileManager.default.createDirectory(
            at: dependencies.manifestStore.directoryURL,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: dependencies.manifestStore.manifestURL)

        XCTAssertThrowsError(
            try dependencies.manifestStore.save(CollectionStoreManifest(storeID: localID))
        )
        XCTAssertEqual(
            try String(contentsOf: dependencies.manifestStore.manifestURL),
            "not-json"
        )
    }
}
