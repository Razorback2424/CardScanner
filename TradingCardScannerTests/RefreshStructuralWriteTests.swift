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

    func testPokemonRefreshBackfillsOnlyTheExactProductForEachOwnedPrintRun() async throws {
        let container = try makeContainer()
        let pokemon = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"svp-1","localId":"1","name":"Test","set":{"id":"svp","name":"Set","cardCount":{"total":2,"official":2}},"variants":{"firstEdition":false,"holo":true,"normal":false,"reverse":false},"pricing":{"tcgplayer":{"holofoil":{"marketPrice":12.5,"productId":123456}}}}"#.utf8))
        let card = IdentifiedCard.pokemon(pokemon, setCode: "SVP")
        try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            for run: PokemonPrintRun? in [nil, .shadowless, .firstEdition] {
                let added = try CollectionStore(context: context).add(card,
                    resolved: .init(variant: .holo, resolution: .userConfirmed), pokemonPrintRun: run)
                let row = try XCTUnwrap(CollectionStore(context: context).card(forKey: added.collectionKey))
                if run == nil { XCTAssertEqual(row.tcgplayerProductID, "123456") }
                else { XCTAssertNil(row.tcgplayerProductID) }
                row.tcgplayerProductID = nil
                row.tcgplayerURL = nil
            }
            // Exercise the provider refresh, rather than the fresh-price skip.
            for price in try context.fetch(FetchDescriptor<PriceRecord>()) { context.delete(price) }
            try context.save()
        }
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setPokemonFetchOverrideForTesting { _ in card }
        _ = await worker.run(PriceRefreshRequest(usesPriceFallback: false, includeImported: true,
            forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
            markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            XCTAssertEqual(row.quantity, 1)
            XCTAssertEqual(row.tcgplayerProductID, row.pokemonPrintRun == nil ? "123456" : nil)
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: row)?.url.path,
                row.pokemonPrintRun == nil ? "/product/123456" : nil)
        }
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testOldCatalogResponseCannotRestoreCorrectedFinishHandlesOrPrice() async throws {
        let container = try makeContainer()
        let card = IdentifiedCard.pokemon(Self.card(id: "structural-correction"), setCode: "STR")
        let mutation = try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            let added = try CollectionStore(context: context).add(card,
                resolved: .init(variant: .holo, resolution: .userConfirmed))
            let row = try XCTUnwrap(CollectionStore(context: context).card(forKey: added.collectionKey))
            row.tcgplayerProductID = "111"
            row.tcgplayerURL = "https://www.tcgplayer.com/product/111"
            row.justTCGCardID = "outgoing"
            try context.save()
            return added
        }
        let barrier = RefreshTestBarrier()
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setPokemonFetchOverrideForTesting { _ in
            await barrier.pause()
            return card
        }
        let pass = Task {
            await worker.run(PriceRefreshRequest(usesPriceFallback: false, includeImported: true,
                forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
                markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
        }
        await barrier.waitUntilPaused()
        let corrected = try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            try CollectionStore(context: context).recordVariantCorrection(forCollectionKey: mutation.collectionKey,
                to: .init(variant: .reverse, resolution: .userConfirmed),
                activityID: XCTUnwrap(mutation.activityID), quantity: 1)
        }
        await barrier.release()
        _ = await pass.value
        let context = ModelContext(container)
        let row = try XCTUnwrap(CollectionStore(context: context).card(forKey: XCTUnwrap(corrected).collectionKey))
        XCTAssertEqual(row.variant, .reverse)
        XCTAssertNil(row.tcgplayerProductID)
        XCTAssertNil(row.tcgplayerURL)
        XCTAssertNil(row.justTCGCardID)
        XCTAssertNil(PriceStore(context: context).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD)
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

    func testGradedCheckpointPreservesHistoryWhenOwnerWasRemoved() throws {
        for removed in [false, true] {
            let container = try makeContainer()
            let mutation = try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
                try CollectionStore(context: context).addScannedGraded(
                    underlying: .pokemon(Self.card(id: "binding-history"), setCode: "STR"),
                    company: .psa, grade: CardGrade(value: "10"), certificationNumber: nil,
                    resolved: .init(variant: .holo, resolution: .userConfirmed))
            }
            let seed = ModelContext(container)
            let row = try XCTUnwrap(CollectionStore(context: seed).card(forKey: mutation.collectionKey))
            XCTAssertEqual(try seed.fetch(FetchDescriptor<CollectionActivity>()).first?.source, .scan)
            XCTAssertEqual(try seed.fetch(FetchDescriptor<InventoryEvent>()).first?.source, .scan)
            let oldKey = row.priceKey
            let original = Date.now.addingTimeInterval(-172800)
            let prices = PriceStore(context: seed)
            XCTAssertTrue(prices.store(.price(.init(unitMarketPriceUSD: 8, currencyCode: "USD",
                source: .importedCSV, sourceVariantID: "old", sourceUpdatedAt: nil, fetchedAt: original)),
                game: .pokemon, printingID: row.priceStorageID, variantID: row.variantID, at: original))
            XCTAssertTrue(prices.save())
            let staged = PriceStore(context: ModelContext(container), checkpointsInFreshContext: true)
            let variant = GradedVariant(id: "bound-variant", company: .psa, grade: CardGrade(value: "10"),
                marketPriceUSD: 12, updatedAt: .now)
            XCTAssertTrue(staged.enqueueGradedBinding(variant, collectionKey: row.collectionKey,
                expectedPriceKey: oldKey, expectedVariantID: row.variantID, expectedMarketVariantID: nil,
                game: .pokemon, treatmentIDs: [], at: .now))
            if removed {
                try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
                    _ = try CollectionStore(context: context).remove(collectionKey: mutation.collectionKey)
                }
            }
            XCTAssertTrue(staged.save())
            let verification = ModelContext(container)
            let events = try verification.fetch(FetchDescriptor<InventoryEvent>())
            let expected = removed ? oldKey : PriceRecord.key(game: .pokemon,
                printingID: "justtcg:v2:bound-variant", variantID: PhysicalVariant.holo.id)
            XCTAssertTrue(events.allSatisfy { $0.priceStorageKey == expected })
            let observations = try verification.fetch(FetchDescriptor<PriceObservation>())
            XCTAssertTrue(observations.contains { $0.instrumentKey == expected && $0.source == .importedCSV })
            let saved = CollectionStore(context: verification).card(forKey: mutation.collectionKey)
            XCTAssertEqual(saved?.justTCGVariantID, removed ? nil : "bound-variant")
        }
    }

    func testGradedCheckpointRollsBackBindingWhenNewerQuoteRejectsResponse() throws {
        let container = try makeContainer()
        let mutation = try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            try CollectionStore(context: context).addScannedGraded(
                underlying: .pokemon(Self.card(id: "binding-rollback"), setCode: "STR"),
                company: .psa, grade: CardGrade(value: "10"), certificationNumber: nil,
                resolved: .init(variant: .holo, resolution: .userConfirmed))
        }
        let context = ModelContext(container)
        let row = try XCTUnwrap(CollectionStore(context: context).card(forKey: mutation.collectionKey))
        let oldKey = row.priceKey
        let requestedAt = Date.now
        let newer = GradedVariant(id: "rollback-variant", company: .psa, grade: CardGrade(value: "10"),
            marketPriceUSD: 30, updatedAt: requestedAt.addingTimeInterval(60),
            quoteLifecycle: .init(status: "current", lastPrice: nil, lastSaleAt: requestedAt,
                priceExpiresAt: requestedAt.addingTimeInterval(86400)))
        let store = PriceStore(context: context)
        XCTAssertTrue(GradedVariantBinding.storeUnboundVariantQuote(newer, game: .pokemon,
            variantID: row.variantID, treatmentIDs: [], store: store,
            at: requestedAt.addingTimeInterval(60)).wasAccepted)
        XCTAssertTrue(store.save())
        let staged = PriceStore(context: ModelContext(container), checkpointsInFreshContext: true)
        let older = GradedVariant(id: newer.id, company: .psa, grade: CardGrade(value: "10"),
            marketPriceUSD: 12, updatedAt: requestedAt)
        XCTAssertTrue(staged.enqueueGradedBinding(older, collectionKey: row.collectionKey,
            expectedPriceKey: oldKey, expectedVariantID: row.variantID, expectedMarketVariantID: nil,
            game: .pokemon, treatmentIDs: [], at: requestedAt))
        XCTAssertFalse(staged.save())
        let verification = ModelContext(container)
        XCTAssertNil(CollectionStore(context: verification).card(forKey: mutation.collectionKey)?.justTCGVariantID)
        XCTAssertTrue(try verification.fetch(FetchDescriptor<InventoryEvent>()).allSatisfy {
            $0.priceStorageKey == oldKey
        })
        let newKey = PriceRecord.key(game: .pokemon, printingID: "justtcg:v2:\(newer.id)", variantID: row.variantID)
        XCTAssertEqual(PriceStore(context: verification).record(forKey: newKey)?.unitMarketPriceUSD, 30)
    }

    func testGradedRefreshKeepsFinishKeysDistinctWhenRowsShareMarketHandle() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let finishes: [PhysicalVariant?] = [nil, .normal]
        for (index, finish) in finishes.enumerated() {
            let row = CollectedCard(collectionKey: "shared-handle-\(index)", game: .pokemon,
                providerID: "binding-shared", name: "Structural Card", setName: "Structural Fixture",
                setCode: "STR", cardNumber: "1", rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: finish, variantResolution: .userConfirmed)
            row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
            row.gradingCompanyRaw = GradingCompany.psa.rawValue
            row.gradeRaw = "10"
            row.justTCGVariantID = "shared-bound-variant"
            row.justTCGAPIVersion = "v2"
            context.insert(row)
        }
        try context.save()
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setGradedLookupOverrideForTesting { _, _ in
            .matched([GradedVariant(id: "shared-bound-variant", company: .psa,
                grade: CardGrade(value: "10"), printing: "Normal", marketPriceUSD: 12, updatedAt: nil)])
        }
        guard case let .completed(result) = await worker.run(PriceRefreshRequest(
            usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false),
            progress: { _ in }, shouldContinue: nil) else { return XCTFail("Expected refresh completion") }
        XCTAssertFalse(result.persistenceFailed)
        let verification = ModelContext(container)
        let store = PriceStore(context: verification)
        for finish in finishes {
            let key = PriceRecord.key(game: .pokemon, printingID: "justtcg:v2:shared-bound-variant",
                variantID: finish?.id)
            XCTAssertEqual(store.record(forKey: key)?.effectiveUnitMarketPriceUSD, 12)
        }
    }

    func testCachedSealedAddDoesNotRenewProviderCheck() throws {
        let container = try makeContainer()
        let original = Date.now.addingTimeInterval(-172800)
        let product = SealedProductSummary(id: "cached-box", name: "Box", setName: nil,
            variantID: "box-variant", marketPriceUSD: 20, updatedAt: nil, imageURL: nil,
            retrievedAt: original)
        try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            _ = try CollectionStore(context: context).addSealed(product, game: .pokemon)
        }
        let context = ModelContext(container)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<PriceRecord>()).first)
        XCTAssertEqual(record.fetchedAt, original)
        XCTAssertEqual(record.lastSuccessfulCheckAt, original)
        XCTAssertEqual(record.display.state(), .stale)
        let today = PortfolioCalendar.day(containing: .now, in: .current)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PriceCheckDay>()).contains { $0.portfolioDay == today })
    }

    func testQuantityReadDoesNotRepairOrStageHistory() throws {
        let container = try makeContainer()
        let mutation = try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            try CollectionStore(context: context).add(.pokemon(Self.card(id: "quantity-read"), setCode: "STR"),
                resolved: .init(variant: .holo, resolution: .userConfirmed))
        }
        let context = ModelContext(container)
        XCTAssertEqual(try CollectionStore(context: context).logicalQuantity(forAnyKey: mutation.collectionKey), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testDecimalFilterInputAndNegativeCacheCompatibility() throws {
        XCTAssertEqual(PriceFilterView.decimal("1,50", locale: Locale(identifier: "de_DE")), 1.5)
        XCTAssertNil(PriceFilterView.decimal("1,50oops", locale: Locale(identifier: "de_DE")))
        XCTAssertEqual(PriceFilterView.decimal("1.50", locale: Locale(identifier: "en_US")), 1.5)
        XCTAssertEqual(PriceFilterView.decimal("١٫٥٠", locale: Locale(identifier: "ar_EG")), 1.5)
        let legacy = try JSONDecoder().decode(CatalogCachedPrice.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.confirmsNoUSDQuote)
        let gap = CatalogCachedPrice(value: nil, confirmsNoUSDQuote: true)
        XCTAssertEqual(try JSONDecoder().decode(CatalogCachedPrice.self, from: JSONEncoder().encode(gap)), gap)
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
