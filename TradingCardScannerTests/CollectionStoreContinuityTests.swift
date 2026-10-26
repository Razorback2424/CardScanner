import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

private actor HeadlessPricingProbe {
    private(set) var preparations = 0
    private(set) var requests: [String] = []
    func prepared() { preparations += 1 }
    func record(_ key: String) { requests.append(key) }
}

private struct HeadlessVariantPolicy: GameVariantPolicy {
    let selectableVariants: [PhysicalVariant] = [.normal]
}

private struct HeadlessPriceAdapter: GamePriceAdapter {
    let game: CardGame
    let probe: HeadlessPricingProbe
    var supportsStoredPrintingRefresh: Bool { true }
    var allowsProviderFallback: Bool { false }
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        throw PriceQuoteError.identityMismatch
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        await probe.record(PriceRecord.key(game: game, printingID: printingID, variantID: variant?.id))
        return .price(.init(unitMarketPriceUSD: 8.16, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "fixture", sourceUpdatedAt: nil, fetchedAt: .now,
            catalogIdentity: "fixture:\(printingID)"))
    }
}

@MainActor
final class CollectionStoreContinuityTests: XCTestCase {
    private let localStoreID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testColdHeadlessPricingBindsEnabledGamesWithoutForegroundInitialization() async throws {
        for kind in [BackgroundPriceRefresh.Kind.processing, .appRefresh] {
            let directory = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let paths = makePaths(in: directory)
            let manifestStore = CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL)
            let identity = try manifestStore.ensureStoreFileIdentity()
            let games: [CardGame] = [.lorcana, .yuGiOh, .onePiece]
            let expectedKeys = games.map {
                PriceRecord.key(game: $0, printingID: "fixture-\($0.rawValue)", variantID: "normal")
            }
            let withdrawnKey = PriceRecord.key(game: .lorcana, printingID: "withdrawn", variantID: "normal")
            // Seed a previously used disk store directly. No runtime binding,
            // scanner, app root, or foreground bootstrap runs in this fixture.
            do {
                let seed = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
                for game in games {
                    let providerID = "fixture-\(game.rawValue)"
                    seed.mainContext.insert(CollectedCard(collectionKey: "\(game.rawValue):\(providerID)#normal",
                        game: game, providerID: providerID, name: "Headless fixture", setName: "Fixture",
                        setCode: "FIX", cardNumber: "1", rarity: nil, imageURL: nil, thumbnailURL: nil,
                        variant: .normal, variantResolution: .userConfirmed))
                }
                try seed.mainContext.save()
                let prices = PriceStore(context: seed.mainContext)
                XCTAssertTrue(prices.store(.price(.init(unitMarketPriceUSD: 1, currencyCode: "USD", source: .tcgCSV,
                    sourceVariantID: "old", sourceUpdatedAt: nil, fetchedAt: .distantPast)),
                    game: .lorcana, printingID: "withdrawn", variantID: "normal"))
                XCTAssertTrue(prices.save())
            }
            try manifestStore.save(.init(storeID: localStoreID, attachmentState: .neverAttached, storeFileIdentity: identity))
            let generation = CollectionStorageGeneration()
            defer { generation.suspend() }
            var opens = 0
            let dependencies = CollectionStorageHeadlessPreflightDependencies(paths: paths, manifestStore: manifestStore,
                accountAvailability: { .noAccount }, makeContainer: { mode in
                    opens += 1
                    return try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: mode)
                }, storageGeneration: generation)
            let probe = HeadlessPricingProbe()
            let modules = games.map { game in
                CardGameRuntime(descriptor: .init(game: game, displayName: game.rawValue, sortOrder: 0,
                    capabilities: [.pricing, .collectionWrite]),
                    variantPolicy: HeadlessVariantPolicy(),
                    pricing: HeadlessPriceAdapter(game: game, probe: probe),
                    priceAuthority: .init(game: game, managedSources: [.tcgCSV], identityByPriceKey: [
                        PriceRecord.key(game: game, printingID: "fixture-\(game.rawValue)", variantID: "normal"):
                            "fixture:fixture-\(game.rawValue)"
                    ]))
            }
            let unbound = try CardGameRuntimeContainer(runtimes: modules)
            // A fresh controller starts with only the legacy pricing adapters.
            // A warmed shared controller cannot make this regression pass.
            let controller = PriceRefreshController()
            let success = await BackgroundPriceRefresh.run(kind, allowsForeground: true,
                storageDependencies: dependencies, prepareRuntimes: {
                    await probe.prepared()
                    return unbound
                }, refreshController: controller)
            XCTAssertTrue(success)
            XCTAssertEqual(opens, 1)
            let preparations = await probe.preparations
            XCTAssertEqual(preparations, 1)
            let requests = await probe.requests
            XCTAssertEqual(Set(requests), Set(expectedKeys))
            XCTAssertEqual(requests.count, 3)
            let reopened = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
            let prices = PriceStore(context: reopened.mainContext)
            for key in expectedKeys {
                XCTAssertEqual(prices.record(forKey: key)?.effectiveUnitMarketPriceUSD, 8.16)
            }
            XCTAssertNotNil(prices.record(forKey: withdrawnKey)?.invalidatedAt,
                "Headless binding must install catalog price authority before fetching")
            XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [1, 1, 1])
        }
    }

    func testHeadlessPricingDoesNotPrepareRuntimesWithoutAProvenStore() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = makePaths(in: directory)
        let generation = CollectionStorageGeneration()
        let probe = HeadlessPricingProbe()
        var opens = 0
        let dependencies = CollectionStorageHeadlessPreflightDependencies(paths: paths,
            manifestStore: .init(directoryURL: paths.collectionStorageDirectoryURL),
            accountAvailability: { .noAccount }, makeContainer: { mode in
                opens += 1
                return try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: mode)
            }, storageGeneration: generation)
        let empty = try CardGameRuntimeContainer(runtimes: [])
        let result = await BackgroundPriceRefresh.run(.processing, allowsForeground: true,
            storageDependencies: dependencies, prepareRuntimes: {
                await probe.prepared()
                return empty
            }, refreshController: PriceRefreshController())
        XCTAssertTrue(result, "An unproven store remains a harmless no-op")
        XCTAssertEqual(opens, 0)
        let preparations = await probe.preparations
        XCTAssertEqual(preparations, 0)
        XCTAssertNil(generation.currentToken())
    }

    func testHeadlessPricingStopsIfPreparationIsCancelledOrStorageIsReplaced() async throws {
        for cancelsTask in [false, true] {
            let directory = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let paths = makePaths(in: directory)
            let manifestStore = CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL)
            let identity = try manifestStore.ensureStoreFileIdentity()
            do {
                let seed = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
                let prices = PriceStore(context: seed.mainContext)
                XCTAssertTrue(prices.store(.price(.init(unitMarketPriceUSD: 1, currencyCode: "USD", source: .tcgCSV,
                    sourceVariantID: "old", sourceUpdatedAt: nil, fetchedAt: .distantPast)),
                    game: .lorcana, printingID: "withdrawn", variantID: "normal"))
                XCTAssertTrue(prices.save())
            }
            try manifestStore.save(.init(storeID: localStoreID, attachmentState: .neverAttached, storeFileIdentity: identity))
            let generation = CollectionStorageGeneration()
            defer { generation.suspend() }
            let dependencies = CollectionStorageHeadlessPreflightDependencies(paths: paths, manifestStore: manifestStore,
                accountAvailability: { .noAccount }, makeContainer: { mode in
                    try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: mode)
                }, storageGeneration: generation)
            let probe = HeadlessPricingProbe()
            let unbound = try CardGameRuntimeContainer(runtimes: [
                .init(descriptor: .init(game: .lorcana, displayName: "Fixture", sortOrder: 0, capabilities: .pricing),
                    variantPolicy: HeadlessVariantPolicy(), pricing: HeadlessPriceAdapter(game: .lorcana, probe: probe),
                    priceAuthority: .init(game: .lorcana, managedSources: [.tcgCSV], identityByPriceKey: [:]))
            ])
            let controller = PriceRefreshController()
            let run = Task { @MainActor in
                await BackgroundPriceRefresh.run(.processing, allowsForeground: true,
                    storageDependencies: dependencies, prepareRuntimes: {
                        await probe.prepared()
                        if cancelsTask { withUnsafeCurrentTask { $0?.cancel() } }
                        else { await MainActor.run { generation.suspend() } }
                        return unbound
                    }, refreshController: controller)
            }
            let result = await run.value
            XCTAssertFalse(result)
            let preparations = await probe.preparations
            let requests = await probe.requests
            XCTAssertEqual(preparations, 1)
            XCTAssertTrue(requests.isEmpty)
            let reopened = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
            let key = PriceRecord.key(game: .lorcana, printingID: "withdrawn", variantID: "normal")
            XCTAssertNil(PriceStore(context: reopened.mainContext).record(forKey: key)?.invalidatedAt,
                "Cancelled or stale preparation must not install quote authority")
        }
    }

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
            readinessProven: true,
            storageGeneration: CollectionStorageGeneration()
        )

        let session = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: dependencies
        )

        XCTAssertNil(session)
        XCTAssertEqual(makeCount, 0)
    }

    func testUnprovenReadinessOpensAttachedReplicaLocallyInHeadlessProcess() async throws {
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

        XCTAssertEqual(headlessSession?.storeID, localStoreID)
        XCTAssertEqual(headlessSession?.mode, .onDevice)
        XCTAssertTrue(headlessSession?.isAuthoritative == true)
        XCTAssertEqual(makeCount, 1)
        XCTAssertNotNil(headlessGeneration.currentToken())
        headlessGeneration.suspend()
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
            readinessProven: true,
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
            readinessProven: true,
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
                readinessProven: true,
                storageGeneration: CollectionStorageGeneration()
            )

            let session = await CollectionStorageHeadlessPreflight.prepare(dependencies: dependencies)
            XCTAssertNil(session, "anchor case \(index) must fail closed")
            XCTAssertEqual(makeCount, 0, "anchor case \(index) must not construct a container")
        }
    }
}
