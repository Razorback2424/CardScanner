import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TradingCardScanner

@MainActor
final class StoreRevisionMonitorTests: XCTestCase {
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
                      scene: MonitorScene, portfolio: PortfolioEngine? = nil) -> UIWindow {
        let portfolio = portfolio ?? PortfolioEngine()
        let storage = CollectionStorageGeneration()
        storage.installReady(storeID: UUID())
        refresh.registerPortfolio(portfolio)
        let monitor = StoreRevisionMonitor(portfolio: portfolio, projectionStore: CollectionProjectionStore(),
                                           priceSnapshot: PriceSnapshotStore(), revisionStore: StoreRevisionStore(),
                                           refresh: refresh, storageGeneration: storage,
                                           hasStartedPortfolio: true, completionSignal: signal)
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
