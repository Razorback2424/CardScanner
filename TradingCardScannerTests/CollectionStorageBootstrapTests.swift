import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class CollectionStorageBootstrapTests: XCTestCase {
    private let localID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let remoteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makeDependencies(
        account: @escaping @MainActor () async -> CloudAccountAvailability,
        anchor: @escaping @MainActor () async -> CloudCollectionAnchorState = { .missing },
        claim: @escaping @MainActor (UUID) async -> CloudCollectionAnchorClaimResult = { storeID in
            .claimed(CloudCollectionAnchor(storeID: storeID, formatVersion: 1))
        },
        readiness: any CloudRestorationReadinessSource = FixedCloudRestorationReadinessSource(result: .readyEmpty),
        makeContainer: (@MainActor (CollectionStorageMode) throws -> ModelContainer)? = nil,
        structuredStoreFilePresent: Bool = false,
        structuredStoreBaseFilePresent: Bool? = nil,
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
            structuredStoreFilePresent: { structuredStoreFilePresent },
            structuredStoreBaseFilePresent: {
                structuredStoreBaseFilePresent ?? structuredStoreFilePresent
            },
            localHasUserData: { false },
            storeFileIdentity: { "test-store-file-identity" },
            readStoreFileIdentity: { structuredStoreFilePresent ? "test-store-file-identity" : nil },
            adoptLegacyStore: { nil },
            localOnlyTransitionProven: true
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

    #if !LOCAL_ONLY_SIGNING
    func testReleaseProductionDependenciesRejectUnprovenLocalOnlyMode() throws {
        let dependencies = CollectionStorageBootstrapDependencies.production()
        XCTAssertThrowsError(try dependencies.makeContainer(.onDevice)) { error in
            XCTAssertEqual(
                error as? CollectionStorageBootstrapError,
                .localOnlyTransitionNotProven
            )
        }
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
    }

    func testFreshAvailableAccountClaimsAndOpensCloudOnlyAfterReadinessProof() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            readiness: FixedCloudRestorationReadinessSource(result: .readyPopulated)
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
                mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion
            )
        )
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
    }

    func testDifferentRemoteCollectionNeverOpensEitherCollection() async throws {
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-a") },
            anchor: { .found(CloudCollectionAnchor(storeID: self.remoteID, formatVersion: 1)) },
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
    }

    func testConfirmedNewAccountClaimsBeforeConstructingCloudContainer() async throws {
        var claimCount = 0
        var makeCount = 0
        let dependencies = try makeDependencies(
            account: { .available(fingerprint: "account-b") },
            claim: { storeID in
                claimCount += 1
                return .claimed(CloudCollectionAnchor(storeID: storeID, formatVersion: 1))
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
                .alreadyClaimed(CloudCollectionAnchor(storeID: self.remoteID, formatVersion: 1))
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
