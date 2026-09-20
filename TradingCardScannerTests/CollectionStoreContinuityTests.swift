import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class CollectionStoreContinuityTests: XCTestCase {
    private let localStoreID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardScannerContinuityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makePaths(in directory: URL) -> CollectionStoragePaths {
        let collectionDirectory = directory.appendingPathComponent(
            "CollectionStorage",
            isDirectory: true
        )
        return CollectionStoragePaths(
            applicationSupportURL: directory,
            collectionStorageDirectoryURL: collectionDirectory,
            structuredStoreURL: collectionDirectory.appendingPathComponent(
                "CardScannerCollection.store"
            ),
            portfolioStoreURL: collectionDirectory.appendingPathComponent(
                "PortfolioLocal.store"
            )
        )
    }

    private func makeDiskBootstrapDependencies(
        paths: CollectionStoragePaths,
        manifestStore: CollectionStoreManifestStore,
        generation: CollectionStorageGeneration,
        account: @escaping @MainActor () async -> CloudAccountAvailability = { .noAccount }
    ) -> CollectionStorageBootstrapDependencies {
        CollectionStorageBootstrapDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: account,
            anchorState: { .unknown },
            claimAnchor: { storeID in
                .claimed(CloudCollectionAnchor(
                    storeID: storeID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "continuity-test-generation"
                ))
            },
            makeContainer: { mode in
                try CollectionStorageBootstrapDependencies.makeContainer(
                    paths: paths,
                    mode: mode
                )
            },
            readinessSource: UnprovenCloudRestorationReadinessSource(),
            structuredStoreFilePresent: {
                CollectionStoreDiscovery.existingLocation(
                    locations: CollectionStoreDiscovery.locations(
                        applicationSupportURL: paths.applicationSupportURL,
                        explicitStructuredStoreURL: paths.structuredStoreURL
                    )
                ) != nil
            },
            structuredStoreBaseFilePresent: {
                FileManager.default.fileExists(atPath: paths.structuredStoreURL.path)
            },
            localHasUserData: { false },
            storeFileIdentity: { try manifestStore.ensureStoreFileIdentity() },
            readStoreFileIdentity: { try manifestStore.readStoreFileIdentity() },
            adoptLegacyStore: { nil },
            storageGeneration: generation
        )
    }

    func testProductionHeadlessBindingMapsLocalManifestStatesToOnDeviceMode() {
        let dependencies = CollectionStorageHeadlessPreflightDependencies.production()

        XCTAssertEqual(
            dependencies.containerModeForManifest(.neverAttached),
            .onDevice
        )
        XCTAssertEqual(
            dependencies.containerModeForManifest(.suspended),
            .onDevice
        )
        XCTAssertNil(dependencies.containerModeForManifest(.attached))
        XCTAssertNil(dependencies.containerModeForManifest(.conflict))
    }

    func testManifestPlusMissingStoreIsUnverifiedAndCannotOpenLocally() {
        let local = CollectionStorageLocalFacts(
            manifest: CollectionStoreManifest(
                storeID: localStoreID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "file-a"
            ),
            structuredStoreFilePresent: false,
            localHasUserData: false,
            storeFileIdentityStatus: .matching
        )

        XCTAssertEqual(local.replicaState, .replicaCompletelyAbsent)
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: .noAccount
                )
            ),
            .blockUnprovenTransition
        )
    }

    func testSidecarAbsenceAndMismatchAreBothReplacementSignals() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifestStore = CollectionStoreManifestStore(directoryURL: directory)
        let manifest = CollectionStoreManifest(
            storeID: localStoreID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "file-a"
        )
        try manifestStore.save(manifest)

        XCTAssertNil(try manifestStore.readStoreFileIdentity())
        let missingSidecar = CollectionStorageLocalFacts(
            manifest: manifest,
            structuredStoreFilePresent: true,
            localHasUserData: true,
            storeFileIdentityStatus: .missing
        )
        XCTAssertEqual(missingSidecar.replicaState, .baseStoreIdentityMissing)

        try Data("file-b".utf8).write(to: manifestStore.storeFileIdentityURL)
        XCTAssertEqual(try manifestStore.readStoreFileIdentity(), "file-b")
        let mismatchedSidecar = CollectionStorageLocalFacts(
            manifest: manifest,
            structuredStoreFilePresent: true,
            localHasUserData: true,
            storeFileIdentityStatus: .mismatched
        )
        XCTAssertEqual(mismatchedSidecar.replicaState, .baseStoreIdentityMismatch)
    }

    func testStorePresentWithoutManifestBlocksInsteadOfMintingIdentity() {
        let local = CollectionStorageLocalFacts(
            structuredStoreFilePresent: true,
            localHasUserData: true,
            proposedFreshStoreID: UUID()
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: .available(fingerprint: "account-a"),
                    anchor: .missing
                )
            ),
            .blockUnprovenTransition
        )
    }

    func testWALAndSHMEvidenceCountsAsAnExistingStore() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try Data().write(to: URL(fileURLWithPath: "\(storeURL.path)-wal"))

        let locations = CollectionStoreDiscovery.locations(
            applicationSupportURL: directory,
            explicitStructuredStoreURL: storeURL
        )
        XCTAssertEqual(
            CollectionStoreDiscovery.existingLocation(locations: locations)?.url,
            storeURL
        )
        let local = CollectionStorageLocalFacts(
            manifest: CollectionStoreManifest(
                storeID: localStoreID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "file-a"
            ),
            structuredStoreFilePresent: true,
            structuredStoreBaseFilePresent: false,
            localHasUserData: true,
            storeFileIdentityStatus: .matching
        )
        XCTAssertTrue(local.hasDurableLocalPresence)
        XCTAssertEqual(local.replicaState, .orphanedJournalArtifacts)
    }

    func testApplicationSupportResolutionFailureIsFailClosed() throws {
        let paths = CollectionStoragePaths.production(resolvedApplicationSupportURL: nil)
        XCTAssertFalse(paths.isStable)
        XCTAssertFalse(paths.applicationSupportURL.path.contains(FileManager.default.temporaryDirectory.path))

        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL,
            isUsable: paths.isStable
        )
        XCTAssertThrowsError(try manifestStore.load()) { error in
            XCTAssertEqual(
                error as? CollectionStoreManifestStoreError,
                .storageLocationUnavailable
            )
        }
    }

    func testMatchingRemoteAnchorEntersRestorationForMissingLocalReplica() {
        let local = CollectionStorageLocalFacts(
            manifest: CollectionStoreManifest(
                storeID: localStoreID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "file-a"
            ),
            structuredStoreFilePresent: false,
            localHasUserData: false,
            storeFileIdentityStatus: .matching
        )
        XCTAssertEqual(
            CollectionStoragePolicy.decide(
                CollectionStoragePolicyInput(
                    local: local,
                    account: .available(fingerprint: "account-a"),
                    anchor: .found(CloudCollectionAnchor(
                        storeID: localStoreID,
                        formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                        remoteGeneration: "generation-a"
                    ))
                )
            ),
            .restoreMissingLocalReplica(
                storeID: localStoreID,
                accountFingerprint: "account-a"
            )
        )
    }

    func testCheckpointWithUnknownReadinessCannotAuthorizeStartup() {
        let checkpoint = CloudRestoreCheckpoint(
            storeID: localStoreID,
            accountFingerprint: "account-a",
            storeFileIdentity: "file-a",
            mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
            readiness: .unknown,
            confirmedAt: .now
        )
        XCTAssertFalse(
            CollectionStoragePolicy.acceptsRestoreCheckpoint(
                checkpoint,
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion
            )
        )
    }

    func testHeadlessPreflightRejectsFreshProcessWithoutConstructingAContainer() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CollectionStoragePaths(
            applicationSupportURL: directory,
            collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage", isDirectory: true),
            structuredStoreURL: directory.appendingPathComponent("default.store"),
            portfolioStoreURL: directory.appendingPathComponent("PortfolioLocal.store")
        )
        var makeCount = 0
        let dependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL),
            accountAvailability: { .available(fingerprint: "account-a") },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            storageGeneration: CollectionStorageGeneration()
        )

        let session = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
        XCTAssertNil(session)
        XCTAssertEqual(makeCount, 0)
        XCTAssertNil(dependencies.storageGeneration.currentToken())
    }

    func testHeadlessPreflightOpensNeverAttachedReplicaWithoutAnAccount() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = makePaths(in: directory)
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL
        )
        let identity = try manifestStore.ensureStoreFileIdentity()
        do {
            _ = try CollectionStorageBootstrapDependencies.makeContainer(
                paths: paths,
                mode: .onDevice
            )
        }
        try manifestStore.save(CollectionStoreManifest(
            storeID: localStoreID,
            attachmentState: .neverAttached,
            storeFileIdentity: identity
        ))

        var makeCount = 0
        let generation = CollectionStorageGeneration()
        let dependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: { .noAccount },
            makeContainer: { _ in
                makeCount += 1
                return try CollectionStorageBootstrapDependencies.makeContainer(
                    paths: paths,
                    mode: .onDevice
                )
            },
            storageGeneration: generation
        )

        let session = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: dependencies
        )

        XCTAssertEqual(session?.storeID, localStoreID)
        XCTAssertEqual(session?.mode, .onDevice)
        XCTAssertTrue(session?.isAuthoritative == true)
        XCTAssertEqual(TradingCardScannerApp.activeStorageMode, .onDevice)
        XCTAssertEqual(makeCount, 1)
        generation.suspend()
    }

    func testHeadlessPreflightKeepsAttachedReplicaBehindCloudProofGate() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = makePaths(in: directory)
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL
        )
        let identity = try manifestStore.ensureStoreFileIdentity()
        do {
            _ = try CollectionStorageBootstrapDependencies.makeContainer(
                paths: paths,
                mode: .onDevice
            )
        }
        try manifestStore.save(CollectionStoreManifest(
            storeID: localStoreID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: identity
        ))

        var makeCount = 0
        let dependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: { .noAccount },
            makeContainer: { _ in
                makeCount += 1
                return try CollectionStorageBootstrapDependencies.makeContainer(
                    paths: paths,
                    mode: .onDevice
                )
            },
            storageGeneration: CollectionStorageGeneration()
        )

        let session = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: dependencies
        )

        XCTAssertNil(session)
        XCTAssertEqual(makeCount, 0)
    }

    func testTemporaryUnavailableKeepsAttachedReplicaBehindHeadlessCloudProofGate() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = makePaths(in: directory)
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL
        )
        let identity = try manifestStore.ensureStoreFileIdentity()
        do {
            _ = try CollectionStorageBootstrapDependencies.makeContainer(
                paths: paths,
                mode: .onDevice
            )
        }
        try manifestStore.save(CollectionStoreManifest(
            storeID: localStoreID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: identity
        ))

        let foregroundGeneration = CollectionStorageGeneration()
        let foregroundDependencies = makeDiskBootstrapDependencies(
            paths: paths,
            manifestStore: manifestStore,
            generation: foregroundGeneration,
            account: { .temporarilyUnavailable }
        )
        do {
            let bootstrap = CollectionStorageBootstrap(dependencies: foregroundDependencies)
            await bootstrap.start()
            guard case let .ready(session) = bootstrap.state else {
                return XCTFail("expected a local session during a transient outage")
            }
            XCTAssertEqual(session.mode, .onDevice)
        }
        foregroundGeneration.suspend()

        let persisted = try XCTUnwrap(try manifestStore.load())
        XCTAssertEqual(persisted.attachmentState, .attached)
        XCTAssertEqual(persisted.lastAttachedAccountFingerprint, "account-a")

        var makeCount = 0
        let headlessGeneration = CollectionStorageGeneration()
        let headlessDependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: { .temporarilyUnavailable },
            makeContainer: { _ in
                makeCount += 1
                return try CollectionStorageBootstrapDependencies.makeContainer(
                    paths: paths,
                    mode: .onDevice
                )
            },
            storageGeneration: headlessGeneration
        )

        let headlessSession = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: headlessDependencies
        )

        XCTAssertNil(headlessSession)
        XCTAssertEqual(makeCount, 0)
        XCTAssertNil(headlessGeneration.currentToken())
    }

    func testOnDeviceRelaunchWithNoAccountPreservesIdenticalDigest() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = makePaths(in: directory)
        let manifestStore = CollectionStoreManifestStore(
            directoryURL: paths.collectionStorageDirectoryURL
        )
        let firstGeneration = CollectionStorageGeneration()
        let firstDependencies = makeDiskBootstrapDependencies(
            paths: paths,
            manifestStore: manifestStore,
            generation: firstGeneration
        )
        let firstDigest: CollectionStoreDigest
        do {
            let bootstrap = CollectionStorageBootstrap(dependencies: firstDependencies)
            await bootstrap.start()
            guard case let .ready(session) = bootstrap.state else {
                return XCTFail("expected the first local launch to be ready")
            }
            let card = CollectedCard(
                collectionKey: "continuity:card:normal",
                game: .pokemon,
                providerID: "continuity-card",
                name: "Continuity fixture",
                setName: "Continuity set",
                setCode: "CNT",
                cardNumber: "001",
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: .normal,
                variantResolution: .uniqueInCatalog,
                quantity: 4,
                dateAdded: Date(timeIntervalSinceReferenceDate: 1234)
            )
            session.container.mainContext.insert(card)
            try session.container.mainContext.save()
            firstDigest = try CollectionStoreDigester.make(
                in: session.container.mainContext,
                storeID: localStoreID
            )
        }
        firstGeneration.suspend()

        let secondGeneration = CollectionStorageGeneration()
        let secondDependencies = makeDiskBootstrapDependencies(
            paths: paths,
            manifestStore: manifestStore,
            generation: secondGeneration
        )
        do {
            let bootstrap = CollectionStorageBootstrap(dependencies: secondDependencies)
            await bootstrap.start()
            guard case let .ready(session) = bootstrap.state else {
                return XCTFail("expected the relaunch to be ready locally")
            }
            let secondDigest = try CollectionStoreDigester.make(
                in: session.container.mainContext,
                storeID: localStoreID
            )
            XCTAssertEqual(secondDigest, firstDigest)
            XCTAssertEqual(session.mode, .onDevice)
        }
        secondGeneration.suspend()
    }

    func testEmptyCheckpointNeverConstructsAHeadlessContainer() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CollectionStoragePaths(
            applicationSupportURL: directory,
            collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage", isDirectory: true),
            structuredStoreURL: directory.appendingPathComponent("default.store"),
            portfolioStoreURL: directory.appendingPathComponent("PortfolioLocal.store")
        )
        let manifestStore = CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL)
        try FileManager.default.createDirectory(
            at: paths.collectionStorageDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data().write(to: paths.structuredStoreURL)
        try Data("file-a".utf8).write(to: manifestStore.storeFileIdentityURL)
        var manifest = CollectionStoreManifest(
            storeID: localStoreID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "file-a"
        )
        manifest.cloudRestoreCheckpoint = CloudRestoreCheckpoint(
            storeID: localStoreID,
            accountFingerprint: "account-a",
            storeFileIdentity: "file-a",
            mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
            readiness: .empty,
            remoteGeneration: "generation-a",
            confirmedAt: .now
        )
        try manifestStore.save(manifest)

        var makeCount = 0
        let generation = CollectionStorageGeneration()
        let dependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: { .available(fingerprint: "account-a") },
            anchorState: {
                .found(CloudCollectionAnchor(
                    storeID: self.localStoreID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "generation-a"
                ))
            },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            storageGeneration: generation
        )

        let session = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
        XCTAssertNil(session)
        XCTAssertEqual(makeCount, 0)
        XCTAssertNil(generation.currentToken())
    }

    func testMatchingPopulatedCheckpointDoesNotConstructAHeadlessContainer() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CollectionStoragePaths(
            applicationSupportURL: directory,
            collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage", isDirectory: true),
            structuredStoreURL: directory.appendingPathComponent("default.store"),
            portfolioStoreURL: directory.appendingPathComponent("PortfolioLocal.store")
        )
        let manifestStore = CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL)
        try FileManager.default.createDirectory(
            at: paths.collectionStorageDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data().write(to: paths.structuredStoreURL)
        try Data("file-a".utf8).write(to: manifestStore.storeFileIdentityURL)
        var manifest = CollectionStoreManifest(
            storeID: localStoreID,
            lastAttachedAccountFingerprint: "account-a",
            attachmentState: .attached,
            storeFileIdentity: "file-a"
        )
        manifest.cloudRestoreCheckpoint = CloudRestoreCheckpoint(
            storeID: localStoreID,
            accountFingerprint: "account-a",
            storeFileIdentity: "file-a",
            mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
            readiness: .populated,
            remoteGeneration: "generation-a",
            confirmedAt: .now
        )
        try manifestStore.save(manifest)

        var makeCount = 0
        let generation = CollectionStorageGeneration()
        var dependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: manifestStore,
            accountAvailability: { .available(fingerprint: "account-a") },
            anchorState: {
                .found(CloudCollectionAnchor(
                    storeID: self.localStoreID,
                    formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                    remoteGeneration: "generation-a"
                ))
            },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            storageGeneration: generation
        )

        let session = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
        XCTAssertNil(session)
        XCTAssertEqual(makeCount, 0)
        XCTAssertNil(generation.currentToken())
        let reused = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
        XCTAssertNil(reused)
        XCTAssertEqual(makeCount, 0)
        generation.suspend()

        dependencies.accountAvailability = { .couldNotDetermine }
        let uncertainAccountSession = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: dependencies
        )
        XCTAssertNil(uncertainAccountSession)
        XCTAssertEqual(makeCount, 0)

        dependencies.accountAvailability = { .available(fingerprint: "account-a") }
        try FileManager.default.removeItem(at: paths.structuredStoreURL)
        let missingStoreSession = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: dependencies
        )
        XCTAssertNil(missingStoreSession)
        XCTAssertEqual(makeCount, 0)
    }

    func testForegroundSessionIsReusedWithoutGenerationRotationAndTransitionSkips() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CollectionStoragePaths(
            applicationSupportURL: directory,
            collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage", isDirectory: true),
            structuredStoreURL: directory.appendingPathComponent("default.store"),
            portfolioStoreURL: directory.appendingPathComponent("PortfolioLocal.store")
        )
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let generation = CollectionStorageGeneration()
        generation.installReady(
            session: CollectionStorageSession(
                container: container,
                storeID: localStoreID,
                mode: .cloudKit
            )
        )
        let originalToken = try XCTUnwrap(generation.currentToken())
        var makeCount = 0
        let dependencies = CollectionStorageHeadlessPreflightDependencies(
            paths: paths,
            manifestStore: CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL),
            accountAvailability: { .available(fingerprint: "account-a") },
            makeContainer: { _ in
                makeCount += 1
                return try ModelContainer(
                    for: CollectionStorageModelSchema.full,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                )
            },
            storageGeneration: generation
        )

        let reused = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
        XCTAssertTrue(reused?.container === container)
        XCTAssertTrue(try XCTUnwrap(reused?.isAuthoritative))
        XCTAssertEqual(reused?.token, originalToken)
        XCTAssertEqual(generation.currentToken(), originalToken)
        XCTAssertEqual(makeCount, 0)

        generation.suspend()
        let transitionSession = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: dependencies
        )
        XCTAssertNil(transitionSession)
        XCTAssertEqual(makeCount, 0)
    }

    func testHeadlessPreflightRejectsEveryNonmatchingCurrentAnchorWithoutAContainer() async throws {
        let anchorStates: [CloudCollectionAnchorState] = [
            .missing,
            .temporarilyUnavailable,
            .malformed,
            .unknown,
            .found(CloudCollectionAnchor(
                storeID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                remoteGeneration: "generation-a"
            )),
            .found(CloudCollectionAnchor(
                storeID: localStoreID,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion - 1,
                remoteGeneration: "generation-a"
            )),
            .found(CloudCollectionAnchor(
                storeID: localStoreID,
                formatVersion: CloudCollectionAnchorSchema.currentFormatVersion,
                remoteGeneration: "generation-b"
            ))
        ]

        for (index, anchorState) in anchorStates.enumerated() {
            let directory = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let paths = CollectionStoragePaths(
                applicationSupportURL: directory,
                collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage", isDirectory: true),
                structuredStoreURL: directory.appendingPathComponent("default.store"),
                portfolioStoreURL: directory.appendingPathComponent("PortfolioLocal.store")
            )
            let manifestStore = CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL)
            try FileManager.default.createDirectory(
                at: paths.collectionStorageDirectoryURL,
                withIntermediateDirectories: true
            )
            try Data().write(to: paths.structuredStoreURL)
            try Data("file-a".utf8).write(to: manifestStore.storeFileIdentityURL)
            var manifest = CollectionStoreManifest(
                storeID: localStoreID,
                lastAttachedAccountFingerprint: "account-a",
                attachmentState: .attached,
                storeFileIdentity: "file-a"
            )
            manifest.cloudRestoreCheckpoint = CloudRestoreCheckpoint(
                storeID: localStoreID,
                accountFingerprint: "account-a",
                storeFileIdentity: "file-a",
                mechanismVersion: CloudRestorationReadinessContract.currentMechanismVersion,
                readiness: .populated,
                remoteGeneration: "generation-a",
                confirmedAt: .now
            )
            try manifestStore.save(manifest)

            var makeCount = 0
            let dependencies = CollectionStorageHeadlessPreflightDependencies(
                paths: paths,
                manifestStore: manifestStore,
                accountAvailability: { .available(fingerprint: "account-a") },
                anchorState: { anchorState },
                makeContainer: { _ in
                    makeCount += 1
                    return try ModelContainer(
                        for: CollectionStorageModelSchema.full,
                        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                    )
                },
                storageGeneration: CollectionStorageGeneration()
            )

            let session = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
            XCTAssertNil(session, "anchor case \(index) must fail closed")
            XCTAssertEqual(makeCount, 0, "anchor case \(index) must not construct a container")
        }
    }
}
