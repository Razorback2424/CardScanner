import SwiftData
import XCTest
@testable import TradingCardScanner

private actor RefreshTestBarrier {
    private var entered = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        guard !entered else { return }
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilPaused() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
final class RefreshStructuralWriteTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testRemovingUnreachedRowDuringSlowRefreshKeepsLaterPatchesAndPrices() async throws {
        let container = try makeContainer()
        let blockedID = "structural-150"
        try seedRows(count: 300, in: container)

        let barrier = RefreshTestBarrier()
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setPokemonFetchOverrideForTesting { printing in
            if printing.printingID == blockedID { await barrier.pause() }
            return .pokemon(Self.card(id: printing.printingID), setCode: "STR")
        }

        let pass = Task {
            await worker.run(
                PriceRefreshRequest(
                    usesPriceFallback: false,
                    includeImported: true,
                    forceUnsupportedRetry: false,
                    sortOldestFirst: false,
                    maximumTargetCount: nil,
                    markRecentlyCheckedIfEmpty: false
                ),
                progress: { _ in },
                shouldContinue: nil
            )
        }
        await barrier.waitUntilPaused()
        try deleteRows(in: container, matching: blockedID)
        await barrier.release()

        guard case let .completed(result) = await pass.value else {
            return XCTFail("Expected the refresh to complete after the sibling delete")
        }
        XCTAssertFalse(result.persistenceFailed)

        let verification = ModelContext(container)
        let rows = try verification.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 299)
        XCTAssertTrue(rows.allSatisfy { $0.pendingCatalogFinishID == PhysicalVariant.normal.id })
        let prices = try verification.fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(prices.count, 300)
        XCTAssertGreaterThanOrEqual(prices.filter { $0.effectiveUnitMarketPriceUSD == 12.34 }.count, 299)
    }

    func testDeleteAllDuringSlowRefreshDoesNotTrapAndPricesStillCheckpoint() async throws {
        let container = try makeContainer()
        let blockedID = "structural-075"
        try seedRows(count: 300, in: container)

        let barrier = RefreshTestBarrier()
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setPokemonFetchOverrideForTesting { printing in
            if printing.printingID == blockedID { await barrier.pause() }
            return .pokemon(Self.card(id: printing.printingID), setCode: "STR")
        }
        let pass = Task {
            await worker.run(
                PriceRefreshRequest(
                    usesPriceFallback: false,
                    includeImported: true,
                    forceUnsupportedRetry: false,
                    sortOldestFirst: false,
                    maximumTargetCount: nil,
                    markRecentlyCheckedIfEmpty: false
                ),
                progress: { _ in },
                shouldContinue: nil
            )
        }
        await barrier.waitUntilPaused()
        try deleteRows(in: container, matching: nil)
        await barrier.release()

        guard case let .completed(result) = await pass.value else {
            return XCTFail("Expected the refresh to complete after delete-all")
        }
        XCTAssertFalse(result.persistenceFailed)
        let verification = ModelContext(container)
        XCTAssertTrue(try verification.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let prices = try verification.fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(prices.count, 300)
        XCTAssertGreaterThanOrEqual(prices.filter { $0.effectiveUnitMarketPriceUSD == 12.34 }.count, 299)
    }

    func testRefreshArrivingDuringSuspensionWaitsForResumedQueue() async throws {
        let container = try makeContainer()
        let controller = PriceRefreshController()
        let token = await controller.suspendPasses()
        let refresh = Task {
            await controller.refresh(
                PriceRefreshRequest(
                    usesPriceFallback: false,
                    includeImported: true,
                    forceUnsupportedRetry: false,
                    sortOldestFirst: false,
                    maximumTargetCount: nil,
                    markRecentlyCheckedIfEmpty: false
                ),
                container: container
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        controller.resume(token)
        let result = await refresh.value
        XCTAssertFalse(result.targetBuildFailed)
    }

    func testGradedPriceBindingRemainsCanonicalAcrossTwoPassesInOneWorkerContext() throws {
        let container = try makeContainer()
        let oldPrintingID = "graded:pokemon:two-pass-card:psa-10"
        let newPrintingID = "justtcg:v2:two-pass-variant"
        let oldKey = PriceRecord.key(
            game: .pokemon,
            printingID: oldPrintingID,
            variantID: nil
        )
        let newKey = PriceRecord.key(
            game: .pokemon,
            printingID: newPrintingID,
            variantID: nil
        )
        let fetchedAt = Date.now
        let firstPassContext = ModelContext(container)
        let firstPassStore = PriceStore(context: firstPassContext)
        XCTAssertTrue(firstPassStore.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 8,
                    currencyCode: "USD",
                    source: .importedCSV,
                    sourceVariantID: oldPrintingID,
                    sourceUpdatedAt: nil,
                    fetchedAt: fetchedAt
                )
            ),
            game: .pokemon,
            printingID: oldPrintingID,
            variantID: nil,
            at: fetchedAt
        ))
        try firstPassContext.save()

        // PriceRefreshModelActor keeps this context and its index for the
        // entire queue. Promotion must update that context's materialization,
        // so the next pass cannot recreate the old key or duplicate the row.
        let workerContext = ModelContext(container)
        let index = PriceRefreshDataIndex(context: workerContext)
        let store = PriceStore(context: workerContext, index: index)
        XCTAssertTrue(try PriceIdentityLineageMigration.migratePriceSide(
            from: oldKey,
            to: newKey,
            game: .pokemon,
            printingID: newPrintingID,
            variantID: nil,
            treatmentIDs: [],
            in: workerContext,
            index: index
        ))
        try workerContext.save()

        XCTAssertTrue(store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 12,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "two-pass-variant",
                    sourceUpdatedAt: nil,
                    fetchedAt: fetchedAt.addingTimeInterval(60)
                )
            ),
            game: .pokemon,
            printingID: newPrintingID,
            variantID: nil,
            marketVariantID: "two-pass-variant",
            at: fetchedAt.addingTimeInterval(60)
        ))
        try workerContext.save()

        // Simulate the next pass rebuilding its context-owned index.
        index.reload()
        XCTAssertNil(store.record(forKey: oldKey))
        XCTAssertEqual(store.record(forKey: newKey)?.effectiveUnitMarketPriceUSD, 12)
        let records = try ModelContext(container).fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.key, newKey)
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container
    }

    private func seedRows(count: Int, in container: ModelContainer) throws {
        let context = container.mainContext
        for index in 0..<count {
            let id = "structural-\(String(format: "%03d", index))"
            context.insert(
                CollectedCard(
                    collectionKey: "\(id)#holo",
                    game: .pokemon,
                    providerID: id,
                    name: "Structural Card \(index)",
                    setName: "Structural Fixture",
                    setCode: "STR",
                    cardNumber: String(index + 1),
                    rarity: "Common",
                    imageURL: nil,
                    thumbnailURL: nil,
                    variant: .holo,
                    variantResolution: .uniqueInCatalog
                )
            )
        }
        try context.save()
    }

    private func deleteRows(in container: ModelContainer, matching providerID: String?) throws {
        try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            let rows = try context.fetch(FetchDescriptor<CollectedCard>())
                .filter { providerID == nil || $0.providerID == providerID }
            for row in rows { context.delete(row) }
            try context.save()
        }
    }

    nonisolated private static func card(id: String) -> TCGdexCard {
        TCGdexCard(
            id: id,
            localId: "1",
            name: "Structural Card",
            image: nil,
            rarity: "Common",
            set: TCGdexSetBrief(
                id: "STR",
                name: "Structural Fixture",
                cardCount: TCGdexCardCount(total: 300, official: 300)
            ),
            variants: TCGdexVariants(
                firstEdition: false,
                holo: false,
                normal: true,
                reverse: false,
                wPromo: false
            ),
            pricing: TCGdexPricing(
                tcgplayer: TCGPlayerPricing(
                    updated: "2026-09-22T12:00:00.000Z",
                    normal: nil,
                    holo: nil,
                    holofoil: TCGPlayerPricePoint(marketPrice: 12.34),
                    reverse: nil,
                    reverseHolofoil: nil
                ),
                cardmarket: nil
            ),
            variantsDetailed: nil
        )
    }
}
