import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TradingCardScanner

@MainActor
final class StoreRevisionMonitorTests: XCTestCase {
    func testUnchangedBulkCompletionIsAcknowledgedBeforeOrdinarySave() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let debounce = MonitorDebounceGate(), computations = MonitorDebounceGate()
        await debounce.release()
        await computations.release()
        let portfolio = PortfolioEngine(computationProvider: { container, epoch, now, timeZone in
            await computations.wait()
            return await PortfolioComputationActor(modelContainer: container)
                .compute(epoch: epoch, liveInstant: now, timeZoneIdentifier: timeZone)
        })
        let writes = DerivedStateWriteCoordinator(), revision = StoreRevisionStore()
        let window = host(container: container, refresh: PriceRefreshController(),
            signal: PriceRefreshCompletionSignal(), writes: writes, scene: MonitorScene(),
            portfolio: portfolio, revision: revision, debounce: { await debounce.wait() })
        defer { window.isHidden = true; window.rootViewController = nil }
        defer { Task { await debounce.release(); await computations.release() } }
        try await waitForGate(computations, atLeast: 1)
        for _ in 0..<80 where portfolio.isRecomputing { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(portfolio.isRecomputing)
        try await Task.sleep(for: .milliseconds(100))
        await debounce.blockAgain()
        let baselineRevision = revision.revision
        let before = await debounce.count

        writes.beginBulkWrite()
        writes.endBulkWrite() // Deliberately no durable input change.
        XCTAssertEqual(writes.generation, 1)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(revision.revision, baselineRevision)
        let afterBulk = await debounce.count
        XCTAssertEqual(afterBulk, before, "An unchanged completed generation still bypasses debounce")

        let price = PriceRecord(key: "noop-bulk#normal", game: .lorcana,
            printingID: "noop-bulk", variantID: PhysicalVariant.normal.id)
        price.unitMarketPriceUSD = 1
        container.mainContext.insert(price)
        try container.mainContext.save()
        try await waitForGate(debounce, atLeast: before + 1)
        XCTAssertEqual(revision.revision, baselineRevision,
            "The no-op bulk apply must acknowledge its generation, restoring ordinary debounce")
        await debounce.release()
        for _ in 0..<80 where revision.revision == baselineRevision {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(revision.revision, baselineRevision + 1)
    }

    func testSupersededBulkApplyRemainsPendingUntilSameGenerationRetrySettles() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let debounce = MonitorDebounceGate(), computations = MonitorDebounceGate()
        await debounce.release()
        await computations.release()
        let portfolio = PortfolioEngine(computationProvider: { container, epoch, now, timeZone in
            await computations.wait()
            return await PortfolioComputationActor(modelContainer: container)
                .compute(epoch: epoch, liveInstant: now, timeZoneIdentifier: timeZone)
        })
        let writes = DerivedStateWriteCoordinator(), revision = StoreRevisionStore()
        let signal = PriceRefreshCompletionSignal()
        let window = host(container: container, refresh: PriceRefreshController(),
            signal: signal, writes: writes, scene: MonitorScene(), portfolio: portfolio,
            revision: revision, debounce: { await debounce.wait() })
        defer { window.isHidden = true; window.rootViewController = nil }
        defer { Task { await debounce.release(); await computations.release() } }
        try await waitForGate(computations, atLeast: 1)
        for _ in 0..<80 where portfolio.isRecomputing { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(portfolio.isRecomputing)
        try await Task.sleep(for: .milliseconds(100))
        await debounce.blockAgain()
        await computations.blockAgain()
        let beforeDebounce = await debounce.count
        let beforeComputation = await computations.count
        writes.beginBulkWrite()
        let price = PriceRecord(key: "superseded-bulk#normal", game: .lorcana,
            printingID: "superseded-bulk", variantID: PhysicalVariant.normal.id)
        price.unitMarketPriceUSD = 1
        container.mainContext.insert(price)
        try container.mainContext.save()
        writes.endBulkWrite()
        try await waitForGate(computations, atLeast: beforeComputation + 1)
        XCTAssertTrue(portfolio.isRecomputing, "The first bulk apply is suspended in derived work")

        signal.advance() // Cancels/supersedes the observation, not the bulk generation.
        try await Task.sleep(for: .milliseconds(150))
        await computations.releaseCurrent()
        try await waitForGate(computations, atLeast: beforeComputation + 2)
        XCTAssertEqual(writes.generation, 1, "The retry belongs to the same completed bulk generation")
        let retryDebounce = await debounce.count
        XCTAssertEqual(retryDebounce, beforeDebounce,
            "A superseded apply cannot consume the pending bulk generation before its retry")
        await computations.release()
        for _ in 0..<80 where portfolio.isRecomputing { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(portfolio.isRecomputing)
        try await Task.sleep(for: .milliseconds(100))
        let settledRevision = revision.revision

        price.unitMarketPriceUSD = 2
        try container.mainContext.save()
        try await waitForGate(debounce, atLeast: beforeDebounce + 1)
        XCTAssertEqual(revision.revision, settledRevision,
            "After the retry settles, ordinary saves must wait for debounce again")
        await debounce.release()
        for _ in 0..<80 where revision.revision == settledRevision {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(revision.revision, settledRevision + 1)
    }

    private func waitForGate(_ gate: MonitorDebounceGate, atLeast expected: Int) async throws {
        for _ in 0..<80 {
            if await gate.count >= expected { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let actual = await gate.count
        XCTAssertGreaterThanOrEqual(actual, expected)
    }

    func testNestedBulkCompletionBypassesDebounceAndOrdinaryBurstsStillCoalesce() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let projection = CollectionProjectionStore()
        let revision = StoreRevisionStore()
        let writes = DerivedStateWriteCoordinator()
        let debounce = MonitorDebounceGate()
        defer { Task { await debounce.release() } }
        writes.beginBulkWrite()
        writes.beginBulkWrite()
        let signal = PriceRefreshCompletionSignal(), refresh = PriceRefreshController()
        refresh.registerCompletionSignal(signal)
        let window = host(container: container, refresh: refresh, signal: signal,
            writes: writes, scene: MonitorScene(), projection: projection,
            revision: revision, debounce: { await debounce.wait() })
        defer { window.isHidden = true; window.rootViewController = nil }
        writes.endBulkWrite()
        XCTAssertEqual(writes.generation, 0)
        XCTAssertTrue(writes.isBulkWriteInFlight)
        XCTAssertNil(projection.snapshot)
        writes.endBulkWrite()
        for _ in 0..<80 where projection.snapshot == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        let bulkWaits = await debounce.count
        XCTAssertNotNil(projection.snapshot,
            "Completed bulk state publishes while ordinary debounce remains blocked")
        // Allow the initial apply to settle before sending ordinary notifications.
        try await Task.sleep(for: .milliseconds(100))
        let settledRevision = revision.revision
        XCTAssertEqual(projection.revision, 1, "The completed bulk interval publishes one settled projection")
        let price = PriceRecord(key: "debounce-fixture#normal", game: .lorcana,
            printingID: "debounce-fixture", variantID: PhysicalVariant.normal.id)
        container.mainContext.insert(price)
        for value in 1...5 {
            price.unitMarketPriceUSD = Double(value)
            try container.mainContext.save()
            NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        }
        for _ in 0..<80 {
            if await debounce.count > bulkWaits { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let ordinaryWaits = await debounce.count
        XCTAssertGreaterThan(ordinaryWaits, bulkWaits)
        XCTAssertEqual(revision.revision, settledRevision, "Ordinary changes wait for debounce")
        await debounce.release()
        for _ in 0..<80 where revision.revision == settledRevision {
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(revision.revision, settledRevision + 1, "Save and remote bursts publish one settled revision")
    }

    func testFirstObservationReconcilesSameCountOwnershipChanges() async throws {
        for replacement in [false, true] {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let context = container.mainContext
            let original = monitorCard(game: .lorcana)
            context.insert(original)
            try context.save()
            let projection = CollectionProjectionStore()
            await projection.rebuild(container: container)
            XCTAssertEqual(projection.snapshot?.rows.first?.quantity, 1)
            let writes = DerivedStateWriteCoordinator()
            writes.beginBulkWrite()
            let signal = PriceRefreshCompletionSignal(), refresh = PriceRefreshController()
            refresh.registerCompletionSignal(signal)
            let window = host(container: container, refresh: refresh, signal: signal,
                writes: writes, scene: MonitorScene(), projection: projection)
            defer { window.isHidden = true; window.rootViewController = nil }
            let saved: CollectedCard
            if replacement {
                context.delete(original)
                saved = monitorCard(game: .yuGiOh)
                saved.collectionKey = "replacement-card#normal"
                context.insert(saved)
            } else {
                saved = original
                saved.quantity = 2
            }
            try context.save()
            let expectedKey = saved.collectionKey
            let expectedQuantity = saved.quantity
            writes.endBulkWrite()
            for _ in 0..<100 {
                if projection.snapshot?.rows.first?.id == expectedKey,
                   projection.snapshot?.rows.first?.quantity == expectedQuantity { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(projection.snapshot?.rows.map(\.id), [expectedKey])
            XCTAssertEqual(projection.snapshot?.rows.first?.quantity, expectedQuantity)
        }
    }

    func testBulkStartingDuringDebounceDefersUntilItsCompletion() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let projection = CollectionProjectionStore()
        let writes = DerivedStateWriteCoordinator(), debounce = MonitorDebounceGate()
        defer { Task { await debounce.release() } }
        let signal = PriceRefreshCompletionSignal(), refresh = PriceRefreshController()
        let window = host(container: container, refresh: refresh, signal: signal,
            writes: writes, scene: MonitorScene(), projection: projection,
            debounce: { await debounce.wait() })
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<80 {
            if await debounce.count > 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let before = await debounce.count
        XCTAssertGreaterThan(before, 0)
        writes.beginBulkWrite()
        await debounce.releaseCurrent()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(projection.snapshot, "A newly active bulk interval prevents publication")
        writes.endBulkWrite()
        for _ in 0..<80 where projection.snapshot == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNotNil(projection.snapshot,
            "The completed interval publishes without releasing another debounce wait")
    }

    func testCancelledDebounceCannotPublish() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let projection = CollectionProjectionStore(), debounce = MonitorDebounceGate()
        defer { Task { await debounce.release() } }
        let window = host(container: container, refresh: PriceRefreshController(),
            signal: PriceRefreshCompletionSignal(), writes: DerivedStateWriteCoordinator(),
            scene: MonitorScene(), projection: projection,
            debounce: { await debounce.wait() })
        for _ in 0..<80 {
            if await debounce.count > 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let count = await debounce.count
        XCTAssertGreaterThan(count, 0)
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(50))
        await debounce.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(projection.snapshot, "A cancelled observation cannot publish after its wait resumes")
    }

    func testFirstObservationReconcilesACollectionSavedAfterLaunchProjection() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let projection = CollectionProjectionStore()
        await projection.rebuild(container: container)
        XCTAssertTrue(projection.snapshot?.rows.isEmpty == true)
        let writes = DerivedStateWriteCoordinator()
        writes.beginBulkWrite()
        let signal = PriceRefreshCompletionSignal(), refresh = PriceRefreshController()
        refresh.registerCompletionSignal(signal)
        let window = host(container: container, refresh: refresh, signal: signal,
            writes: writes, scene: MonitorScene(), projection: projection)
        defer { window.isHidden = true; window.rootViewController = nil }
        let card = monitorCard(game: .lorcana)
        container.mainContext.insert(card)
        try container.mainContext.save()
        XCTAssertTrue(projection.snapshot?.rows.isEmpty == true)
        writes.endBulkWrite()
        for _ in 0..<100 where projection.snapshot?.rows.isEmpty != false {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(projection.snapshot?.rows.map(\.id), [card.collectionKey])
        XCTAssertEqual(projection.snapshot?.rows.first?.quantity, 1)
    }

    func testOwnershipEditReplaysBeforeAnActivePriceRefreshFinishes() async throws {
        for usesBulkInterval in [false, true] {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let card = monitorCard(game: .pokemon)
        context.insert(card)
        let baselineOperationID = UUID()
        context.insert(InventoryEvent(operationID: baselineOperationID, leg: nil, kind: .initialBalance, source: .catalog,
                                      collectionKey: card.collectionKey, priceStorageKey: card.priceKey,
                                      deltaQuantity: 1, occurredAt: .now, valuation: .unpriced))
        context.insert(CollectionActivity(card: card, source: .catalog, quantity: 1,
                                          ledgerOperationIDs: [baselineOperationID]))
        let price = PriceRecord(key: card.priceKey, game: .pokemon,
                                printingID: card.providerID, variantID: card.variantID)
        price.unitMarketPriceUSD = 1
        price.lastCheckedAt = .now
        context.insert(price)
        try context.save()
        let computations = MonitorAttemptCount()
        let portfolio = PortfolioEngine(computationProvider: { container, epoch, now, timeZone in
            await computations.increment()
            return await PortfolioComputationActor(modelContainer: container)
                .compute(epoch: epoch, liveInstant: now, timeZoneIdentifier: timeZone)
        })
        let refresh = PriceRefreshController()
        let gate = MonitorRefreshGate()
        defer { Task { await gate.release() } }
        refresh.setPokemonFetchOverrideForTesting { printing in
            await gate.wait()
            let data = Data("""
            {"id":"\(printing.printingID)","localId":"1","name":"Monitor Card",
             "set":{"id":"fixture","name":"Monitor Set","cardCount":{"total":1,"official":1}},
             "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":false,"wPromo":false},
             "pricing":{"tcgplayer":{"normal":{"marketPrice":1.0}}}}
            """.utf8)
            return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: data), setCode: "MON")
        }
        let signal = PriceRefreshCompletionSignal()
        refresh.registerCompletionSignal(signal)
        portfolio.start(context: context)
        let writes = DerivedStateWriteCoordinator()
        let window = host(container: container, refresh: refresh, signal: signal,
                          writes: writes, scene: MonitorScene(), portfolio: portfolio)
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<100 where signal.generation == 0 || portfolio.isRecomputing {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(500))
        let before = await computations.value
        price.lastCheckedAt = Date.now.addingTimeInterval(-9 * 60 * 60)
        try context.save()
        let pass = Task {
            await refresh.refresh(PriceRefreshRequest(usesPriceFallback: false, includeImported: true,
                                  forceUnsupportedRetry: false, sortOldestFirst: true,
                                  maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false), container: container)
        }
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let started = await gate.started
        XCTAssertTrue(started)
        if usesBulkInterval {
            writes.beginBulkWrite()
            writes.beginBulkWrite()
        }
        card.quantity += 1
        let editOperationID = UUID()
        context.insert(InventoryEvent(operationID: editOperationID, leg: nil, kind: .acquire, source: .catalog,
                                      collectionKey: card.collectionKey, priceStorageKey: card.priceKey,
                                      deltaQuantity: 1, occurredAt: .now, valuation: .unpriced))
        context.insert(CollectionActivity(card: card, source: .catalog, quantity: 1,
                                          ledgerOperationIDs: [editOperationID]))
        try context.save()
        if usesBulkInterval {
            writes.endBulkWrite()
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(portfolio.holdings.first?.quantity, 1,
                "A new nested bulk interval must withhold ownership replay during the active refresh")
            writes.endBulkWrite()
        }
        for _ in 0..<100 {
            if await computations.value > before && !portfolio.isRecomputing { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let duringPass = await computations.value
        XCTAssertTrue(refresh.isPassInFlight)
        XCTAssertEqual(duringPass, before + 1)
        XCTAssertEqual(portfolio.holdings.first?.quantity, 2)
        await gate.release()
        _ = await pass.value
        for _ in 0..<100 where portfolio.isRecomputing {
            try await Task.sleep(for: .milliseconds(50))
        }
        let afterPass = await computations.value
        XCTAssertEqual(afterPass, before + 2, "Ownership replay plus the controller's terminal replay")
        }
    }

    func testForegroundReconsidersUnchangedTargetsAndDefersThroughBulkWrites() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let card = monitorCard(game: .pokemon)
        context.insert(card)
        let price = PriceRecord(key: card.priceKey, game: .pokemon,
                                printingID: card.providerID, variantID: card.variantID)
        price.unitMarketPriceUSD = 1
        price.lastCheckedAt = .now
        context.insert(price)
        try context.save()
        let attempts = MonitorAttemptCount()
        let refresh = PriceRefreshController()
        refresh.setPokemonFetchOverrideForTesting { printing in
            await attempts.increment()
            let data = Data("""
            {"id":"\(printing.printingID)","localId":"1","name":"Monitor Card",
             "set":{"id":"fixture","name":"Monitor Set","cardCount":{"total":1,"official":1}},
             "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":false,"wPromo":false},
             "pricing":{"tcgplayer":{"normal":{"marketPrice":1.0}}}}
            """.utf8)
            return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: data), setCode: "MON")
        }
        let signal = PriceRefreshCompletionSignal()
        refresh.registerCompletionSignal(signal)
        let writes = DerivedStateWriteCoordinator()
        let scene = MonitorScene()
        let window = host(container: container, refresh: refresh, signal: signal, writes: writes, scene: scene)
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<100 where signal.generation == 0 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertGreaterThan(signal.generation, 0)
        await assertAttempts(attempts, equals: 0)
        scene.phase = .inactive
        price.lastCheckedAt = Date.now.addingTimeInterval(-9 * 60 * 60)
        try context.save()
        try await Task.sleep(for: .milliseconds(500))
        await assertAttempts(attempts, equals: 0)
        writes.beginBulkWrite()
        scene.phase = .active
        try await Task.sleep(for: .milliseconds(400))
        await assertAttempts(attempts, equals: 0)
        writes.endBulkWrite()
        for _ in 0..<100 {
            if await attempts.value == 1 && !refresh.isPassInFlight { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        await assertAttempts(attempts, equals: 1)
        let completed = signal.generation
        scene.phase = .inactive
        try await Task.sleep(for: .milliseconds(50))
        scene.phase = .active
        try await Task.sleep(for: .milliseconds(600))
        await assertAttempts(attempts, equals: 1)
        XCTAssertEqual(signal.generation, completed, "a fresh visit does not start an empty price pass")
    }

    private func monitorCard(game: CardGame) -> CollectedCard {
        CollectedCard(collectionKey: "monitor-card#normal", game: game, providerID: "monitor-card",
                      name: "Monitor Card", setName: "Monitor Set", setCode: "MON", cardNumber: "1",
                      rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal,
                      variantResolution: .userConfirmed)
    }

    func testMagicQuantityChangeReplaysOnceAfterSettledBaseline() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let card = monitorCard(game: .magic)
        card.magicTreatmentMigrationVersion = MagicTreatmentMigration.currentVersion
        context.insert(card)
        let price = PriceRecord(key: card.priceKey, game: .magic,
                                printingID: card.providerID, variantID: card.variantID)
        price.unitMarketPriceUSD = 1
        price.lastCheckedAt = .now
        context.insert(price)
        try context.save()
        let computations = MonitorAttemptCount()
        let portfolio = PortfolioEngine(computationProvider: { container, epoch, now, timeZone in
            await computations.increment()
            return await PortfolioComputationActor(modelContainer: container)
                .compute(epoch: epoch, liveInstant: now, timeZoneIdentifier: timeZone)
        })
        let refresh = PriceRefreshController()
        let signal = PriceRefreshCompletionSignal()
        refresh.registerCompletionSignal(signal)
        // The app starts Portfolio before enabling StoreRevisionMonitor.
        // Otherwise its first replay opens the epoch after the quantity edit,
        // and that baseline save legitimately requests another replay.
        portfolio.start(context: context)
        let window = host(container: container, refresh: refresh, signal: signal,
                          writes: DerivedStateWriteCoordinator(), scene: MonitorScene(), portfolio: portfolio)
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<100 where signal.generation == 0 || portfolio.isRecomputing {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(500))
        let before = await computations.value
        XCTAssertGreaterThan(before, 0, "The initial Portfolio replay must settle before testing a quantity change")
        card.quantity += 1
        try context.save()
        for _ in 0..<100 {
            if await computations.value > before && !portfolio.isRecomputing { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(500))
        await assertAttempts(computations, equals: before + 1)
    }

    private func assertAttempts(_ attempts: MonitorAttemptCount, equals expected: Int) async {
        let actual = await attempts.value
        XCTAssertEqual(actual, expected)
    }

    private func host(container: ModelContainer, refresh: PriceRefreshController,
                      signal: PriceRefreshCompletionSignal, writes: DerivedStateWriteCoordinator,
                      scene: MonitorScene, portfolio: PortfolioEngine? = nil,
                      projection: CollectionProjectionStore? = nil,
                      revision: StoreRevisionStore? = nil,
                      debounce: @escaping @Sendable () async throws -> Void = {
                          try await Task.sleep(for: .milliseconds(300))
                      }) -> UIWindow {
        let portfolio = portfolio ?? PortfolioEngine()
        let storage = CollectionStorageGeneration()
        storage.installReady(storeID: UUID())
        refresh.registerPortfolio(portfolio)
        let monitor = StoreRevisionMonitor(portfolio: portfolio, projectionStore: projection ?? CollectionProjectionStore(),
                                           priceSnapshot: PriceSnapshotStore(), revisionStore: revision ?? StoreRevisionStore(),
                                           refresh: refresh, storageGeneration: storage,
                                           hasStartedPortfolio: true, completionSignal: signal, debounce: debounce)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: MonitorHarness(scene: scene, monitor: monitor)
            .environment(\.modelContext, container.mainContext).environmentObject(writes))
        window.makeKeyAndVisible()
        return window
    }
    func testPersistedMagicMigrationFingerprintSuppressesUnchangedPendingRows() {
        let pending: Set<String> = ["magic:legacy-a", "magic:legacy-b"]
        let fingerprint = StoreRevisionFingerprinting
            .pendingMagicMigrationFingerprint(pending)

        XCTAssertTrue(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: nil,
            currentPendingKeys: pending
        ))
        XCTAssertFalse(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: fingerprint,
            currentPendingKeys: pending
        ))
        XCTAssertTrue(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: fingerprint,
            currentPendingKeys: pending.union(["magic:new-row"])
        ))
        XCTAssertFalse(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: fingerprint,
            currentPendingKeys: []
        ))
    }

    func testDerivedOnlySavesAreIgnoredAndOwnershipSavesRemainRelevant() throws {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let row = CollectedCard(
            collectionKey: "revision-filter-card",
            game: .pokemon,
            providerID: "revision-filter-card",
            name: "Filter Card",
            setName: "Filter Set",
            setCode: "FLT",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
        let price = PriceRecord(
            key: "pokemon:revision-filter-card:normal",
            game: .pokemon,
            printingID: "revision-filter-card",
            variantID: PhysicalVariant.normal.id
        )
        let observation = PriceObservation(
            instrumentKey: price.key,
            kind: .marketUpdate,
            amount: Money(tenThousandths: 1),
            source: .tcgplayer,
            sourceVariantID: "filter",
            marketVariantID: nil,
            effectiveAt: .now,
            receivedAt: .now,
            isSourceStamped: false
        )
        let checkDay = PriceCheckDay(
            instrumentKey: price.key,
            portfolioDay: .now,
            lastSuccessfulCheckAt: .now,
            source: .tcgplayer
        )
        let close = PortfolioDailyClose(
            date: .now,
            revision: 1,
            timeZoneIdentifier: "UTC",
            closeValue: .zero,
            market: .zero,
            flow: .zero,
            corrections: .zero,
            pricingAdjustment: .zero,
            carriedForwardValue: .zero,
            coverage: .unknown,
            refreshedInstrumentCount: 0,
            carriedForwardInstrumentCount: 0,
            pricedPositionCount: 0,
            excludedCount: 0,
            inputsFingerprint: "filter",
            revisionReason: nil
        )
        let reference = ReferenceQuote(
            key: "reference-filter",
            game: .pokemon,
            printingID: "reference-filter",
            variantID: nil
        )
        let identity = ProductIdentity(key: "identity-filter", vendor: .justTCG)
        context.insert(row)
        context.insert(price)
        context.insert(observation)
        context.insert(checkDay)
        context.insert(close)
        context.insert(reference)
        context.insert(identity)
        try context.save()

        XCTAssertFalse(isRelevant([observation.persistentModelID, checkDay.persistentModelID, close.persistentModelID, reference.persistentModelID, identity.persistentModelID], passInFlight: false))
        XCTAssertFalse(isRelevant([price.persistentModelID], passInFlight: true))
        XCTAssertTrue(isRelevant([price.persistentModelID], passInFlight: false))
        XCTAssertTrue(isRelevant([row.persistentModelID, price.persistentModelID], passInFlight: true))
    }

    func testMissingIdentifierKeysUseSafeRelevantDefault() {
        let info: [AnyHashable: Any] = ["inserted": [PersistentIdentifier]()]
        XCTAssertTrue(StoreRevisionSaveFilter.isRelevantSave(userInfo: info, passInFlight: true))
        XCTAssertTrue(StoreRevisionSaveFilter.isRelevantSave(userInfo: nil, passInFlight: false))
    }

    private func isRelevant(_ identifiers: [PersistentIdentifier], passInFlight: Bool) -> Bool {
        let info: [AnyHashable: Any] = [
            ModelContext.NotificationKey.insertedIdentifiers: identifiers,
            ModelContext.NotificationKey.updatedIdentifiers: [PersistentIdentifier](),
            ModelContext.NotificationKey.deletedIdentifiers: [PersistentIdentifier]()
        ]
        return StoreRevisionSaveFilter.isRelevantSave(userInfo: info, passInFlight: passInFlight)
    }
}

private actor MonitorRefreshGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class MonitorScene: ObservableObject {
    @Published var phase: ScenePhase = .active
}

private struct MonitorHarness: View {
    @ObservedObject var scene: MonitorScene
    let monitor: StoreRevisionMonitor
    var body: some View { monitor.environment(\.scenePhase, scene.phase) }
}

private actor MonitorAttemptCount {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor MonitorDebounceGate {
    private(set) var count = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func blockAgain() { released = false }
    func wait() async {
        count += 1
        guard !released else { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() {
        released = true
        releaseCurrent()
    }
    func releaseCurrent() {
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}
