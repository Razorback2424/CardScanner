import SwiftData
import XCTest
@testable import TradingCardScanner

final class BrowseFeatureTests: XCTestCase {
#if DEBUG
    /// Developer-only release step. Set POKEMON_SNAPSHOT_OUTPUT to a checkout
    /// directory before running this test; normal unit-test runs are a no-op.
    func testGeneratePokemonChecklistSnapshotWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["POKEMON_SNAPSHOT_OUTPUT"],
              !path.isEmpty else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try await PokemonChecklistSnapshotGenerator.generate(
            transport: TCGdexBrowseTransport(),
            outputDirectory: output
        )

        let store = PokemonChecklistStore(root: output, bundle: nil)
        let snapshot = await store.downloadedSnapshot()
        XCTAssertNotNil(snapshot)
        XCTAssertFalse(snapshot?.manifest.entries.isEmpty == true)
    }
#endif

    func testCatalogIDsAreNamespacedByGame() {
        XCTAssertNotEqual(
            CatalogSetID(game: .pokemon, providerID: "abc").id,
            CatalogSetID(game: .magic, providerID: "abc").id
        )
    }

    func testPokemonReleaseOrderCacheUsesProviderSetID() {
        PokemonCatalogReleaseOrder.install(["sv08.5": 312])
        XCTAssertEqual(PokemonCatalogReleaseOrder.order(forSetID: "SV08.5"), 312)
    }

    func testPokemonSearchURLCarriesNameAndPagination() throws {
        let url = try XCTUnwrap(BrowseRequestBuilder.pokemonSearchURL(query: "ho oh", page: 3))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["name"], "ho oh")
        XCTAssertEqual(values["pagination:page"], "3")
        XCTAssertEqual(values["pagination:itemsPerPage"], "60")
    }

    func testScryfallSearchRequestsExactPrintings() throws {
        let query = "name:\"Black Lotus\" lang:en game:paper (e:lea or e:2ed)"
        let url = try XCTUnwrap(BrowseRequestBuilder.scryfallSearchURL(query: query))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["q"], query)
        XCTAssertEqual(values["unique"], "prints")
    }

    func testSetDirectoryCacheSurvivesANewStoreInstance() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 180,
            releaseDate: nil,
            sortRank: 1
        )

        let writer = CatalogCacheStore(root: root)
        await writer.storeSets([set], for: .pokemon)
        let reader = CatalogCacheStore(root: root)
        let saved = await reader.sets(for: .pokemon)

        XCTAssertEqual(saved?.value, [set])
        XCTAssertTrue(saved?.isFresh == true)
    }

    func testSealedPageCacheRetainsSavedPageAndFreshness() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let product = SealedProductSummary(
            id: "sealed-1",
            name: "Booster Box",
            setName: "Example Set",
            variantID: "sealed",
            marketPriceUSD: 120,
            updatedAt: .now,
            imageURL: URL(string: "https://example.com/product.jpg"),
            tcgplayerProductID: "123"
        )
        let key = CatalogCacheStore.sealedPageKey(game: .pokemon, setID: "example", query: nil, offset: 0)
        let writer = CatalogCacheStore(root: root)
        await writer.storeSealedProductPage(
            CatalogPage(items: [product], nextCursor: "1"),
            for: key
        )

        let reader = CatalogCacheStore(root: root)
        let saved = await reader.sealedProductPage(for: key)

        XCTAssertEqual(saved?.value.items, [product])
        XCTAssertEqual(saved?.value.nextCursor, "1")
        XCTAssertTrue(saved?.isFresh == true)
    }

    private func makeTemporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

@MainActor
final class BrowseCollectionTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testCatalogSelectionIncrementsNormalizedImportAlias() throws {
        let context = try makeContext()
        let imported = CollectedCard(
            collectionKey: "csv:Prismatic Evolutions|074#reverse",
            game: .pokemon,
            providerID: "csv:Prismatic Evolutions|074",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: "074",
            rarity: "Common",
            imageURL: nil,
            thumbnailURL: nil,
            variant: .reverse,
            variantResolution: .imported,
            identityResolution: .imported,
            quantity: 1
        )
        imported.catalogProviderID = "sv08.5-074"
        context.insert(imported)
        try context.save()

        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let mutation = try! CollectionStore(context: context).add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            identityResolution: .catalogSelected,
            matchCatalogAliases: true
        )

        XCTAssertFalse(mutation.didInsert)
        XCTAssertEqual(mutation.collectionKey, imported.collectionKey)
        XCTAssertEqual(imported.quantity, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testNewCatalogSelectionStoresCatalogProvenanceAndUndoes() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let mutation = try! store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            identityResolution: .catalogSelected,
            setReleaseOrder: 300,
            matchCatalogAliases: true
        )

        let inserted = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(inserted.identityResolution, .catalogSelected)
        XCTAssertEqual(inserted.setReleaseOrder, 300)

        try! store.undo(mutation)
        XCTAssertNil(store.card(forKey: mutation.collectionKey))
    }

    func testSetCompletionCountsCollectorNumbersNotVariantsOrQuantity() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 180,
            releaseDate: nil,
            sortRank: 1
        )
        let cards = [
            completionCard(number: "074", variant: .normal, quantity: 3),
            completionCard(number: "074/131", variant: .reverse),
            completionCard(number: "075", variant: .masterBall)
        ]

        XCTAssertEqual(
            SetCompletionCalculator.progress(for: set, cards: cards),
            SetCompletion(owned: 2, total: 180, unit: "cards")
        )
    }

    func testLegacyFirstEditionPriceRemainsReadable() {
        let card = completionCard(number: "001", variant: .firstEdition)
        let oldKey = PriceRecord.key(
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        let oldRecord = PriceRecord(
            key: oldKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        oldRecord.applyImported(amount: 125, sourceUpdatedAt: nil)

        XCTAssertNotEqual(card.priceKey, oldKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: [oldKey: oldRecord])?.unitMarketPriceUSD,
            125
        )
    }

    func testImportedPrintRunMetadataIndexUsesStableProviderID() throws {
        let context = try makeContext()
        let card = completionCard(number: "001", variant: .holo)
        card.providerID = "csv:base-set|001"
        card.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        context.insert(card)
        try context.save()

        let indexed = PriceStore(context: context).importedCardsByProviderID()

        XCTAssertEqual(indexed[card.providerID]?.map(\.collectionKey), [card.collectionKey])
        XCTAssertNil(indexed[card.priceStorageID])
    }

    func testVariantCorrectionRetargetsTheScanActivity() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        _ = try! store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )

        let mutation = try XCTUnwrap(
            try! store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed)
            )
        )
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())

        XCTAssertEqual(activities.count, 2, "a correction is not another acquisition")
        let retargeted = try XCTUnwrap(activities.first { $0.kind == .added })
        let correction = try XCTUnwrap(activities.first { $0.kind == .corrected })
        XCTAssertEqual(retargeted.source, .scan)
        XCTAssertEqual(retargeted.collectionKey, mutation.collectionKey)
        XCTAssertEqual(retargeted.variantID, PhysicalVariant.reverse.id)
        XCTAssertNotNil(retargeted.correctedAt)
        XCTAssertEqual(correction.deltaQuantity, 0)
        XCTAssertEqual(correction.collectionKey, mutation.collectionKey)
    }

    func testVariantCorrectionPreservesPokemonPrintRunIdentity() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "BASE1")
        let store = CollectionStore(context: context)
        _ = try! store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan,
            pokemonPrintRun: .firstEdition
        )

        let mutation = try XCTUnwrap(
            try! store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                pokemonPrintRun: .firstEdition
            )
        )
        let corrected = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(corrected.pokemonPrintRun, .firstEdition)
        XCTAssertTrue(corrected.collectionKey.hasSuffix("@firstEdition"))
    }

    func testVariantCorrectionWithMissingSourceDoesNotCreateAnUnbalancedPosition() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)

        let mutation = try store.recordVariantCorrection(
            for: card,
            from: .normal,
            to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed)
        )

        XCTAssertNil(mutation)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testIncrementUndoRemovesExactlyOneCopyAndRecordsUndoActivity() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let second = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )

        try store.undo(second)

        XCTAssertEqual(store.card(forKey: second.collectionKey)?.quantity, 1)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 3)
        let undone = try XCTUnwrap(activities.first { $0.kind == .undone })
        XCTAssertEqual(undone.deltaQuantity, -1)
        XCTAssertEqual(
            activities.filter { $0.kind == .added && $0.id == second.activityID }.first?.resolvedQuantity,
            1
        )
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[second.collectionKey], 1)
    }

    func testMultipleCorrectionsUndoTheFullLineageToZero() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let acquired = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let firstCorrection = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                previousLedgerOperationIDs: acquired.ledgerOperationIDs
            )
        )
        let secondCorrection = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: card,
                from: .reverse,
                to: ResolvedVariant(variant: .holo, resolution: .userConfirmed),
                previousCollectionKey: firstCorrection.collectionKey,
                previousLedgerOperationIDs: firstCorrection.ledgerOperationIDs
            )
        )

        XCTAssertEqual(secondCorrection.ledgerOperationIDs.count, 3)
        try store.undo(secondCorrection)

        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 4)
        XCTAssertEqual(activities.filter { $0.kind == .added }.count, 1)
        XCTAssertEqual(activities.filter { $0.kind == .corrected }.count, 2)
        XCTAssertEqual(activities.filter { $0.kind == .undone }.count, 1)
        XCTAssertEqual(activities.reduce(0) { $0 + $1.signedQuantity }, 0)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertTrue(InventoryLedger.quantities(from: events).isEmpty)
    }

    func testCorrectionIntoExistingDestinationUndoPreservesOtherCopy() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let original = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            source: .scan
        )
        let corrected = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                previousLedgerOperationIDs: original.ledgerOperationIDs
            )
        )

        try store.undo(corrected)

        XCTAssertNil(store.card(forKey: original.collectionKey))
        XCTAssertEqual(store.card(forKey: corrected.collectionKey)?.quantity, 1)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[corrected.collectionKey], 1)
    }

    func testUndoWithMissingLineageDoesNotPartiallyMutateCollection() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let mutation = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let badMutation = CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: mutation.activityID,
            didInsert: mutation.didInsert,
            ledgerOperationIDs: [UUID()]
        )

        XCTAssertThrowsError(try store.undo(badMutation))
        XCTAssertEqual(store.card(forKey: mutation.collectionKey)?.quantity, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
    }

    func testPrintRunScanAggregatesLegacyUnqualifiedRow() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "BASE1")
        let resolved = ResolvedVariant(variant: .normal, resolution: .userConfirmed)
        let legacy = CollectedCard(card: card, resolved: resolved)
        legacy.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        context.insert(legacy)
        try context.save()

        let mutation = try! CollectionStore(context: context).add(
            card,
            resolved: resolved,
            source: .scan,
            pokemonPrintRun: .firstEdition,
            matchCatalogAliases: true
        )

        XCTAssertFalse(mutation.didInsert)
        XCTAssertEqual(mutation.collectionKey, legacy.collectionKey)
        XCTAssertEqual(legacy.quantity, 2)
    }

    func testSetCompletionIncludesNormalizedImportAlias() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 180,
            releaseDate: nil,
            sortRank: 1
        )
        let imported = completionCard(number: "076", variant: .reverse)
        imported.setCode = "Prismatic Evolutions"
        imported.catalogProviderID = "sv08.5-076"

        XCTAssertEqual(SetCompletionCalculator.progress(for: set, cards: [imported]).owned, 1)
    }

    func testStampedReprintDoesNotCompleteItsSourceExpansionSlot() throws {
        let stamped = try XCTUnwrap(
            PokemonStampedReleaseCatalog.entries(providerID: "swsh11-066").first?.variant
        )
        let owned = completionCard(number: "066", variant: stamped)
        owned.providerID = "swsh11-066"
        owned.catalogProviderID = "swsh11-066"
        owned.setName = "Trick or Trade 2023"
        owned.setCode = "TOT23"
        let lostOrigin = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "swsh11"),
            name: "Lost Origin",
            code: "LOR",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 196,
            releaseDate: nil,
            sortRank: 1
        )
        let gengar = CatalogCardSummary(
            game: .pokemon,
            providerID: "swsh11-066",
            setID: lostOrigin.catalogID,
            setName: lostOrigin.name,
            setCode: lostOrigin.code,
            name: "Gengar",
            collectorNumber: "066",
            thumbnailURL: nil,
            imageURL: nil
        )

        XCTAssertEqual(SetCompletionCalculator.progress(for: lostOrigin, cards: [owned]).owned, 0)
        XCTAssertFalse(SetCompletionCalculator.owns(gengar, cards: [owned]))
    }

    func testAddingStampedGengarStoresStampedReleaseMetadataAndArtwork() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodeStampedGengar(), setCode: "LOR")
        let stamped = try XCTUnwrap(
            PokemonStampedReleaseCatalog.entries(providerID: "swsh11-066").first?.variant
        )

        let mutation = try! CollectionStore(context: context).add(
            card,
            resolved: ResolvedVariant(variant: stamped, resolution: .userConfirmed),
            identityResolution: .printedIdentifier
        )
        let stored = try XCTUnwrap(CollectionStore(context: context).card(forKey: mutation.collectionKey))

        XCTAssertEqual(stored.setName, "Trick or Trade 2023")
        XCTAssertEqual(stored.setCode, "TOT23")
        XCTAssertEqual(stored.variantID, "trickOrTrade2023Holofoil")
        XCTAssertEqual(
            stored.imageURL,
            "https://tcgplayer-cdn.tcgplayer.com/product/515661_400w.jpg"
        )
        XCTAssertEqual(stored.thumbnailURL, stored.imageURL)
    }

    func testSetQuerySortsByNumberAndPriceWithUnknownPricesLast() {
        let cards = [
            summary(id: "set-10", number: "10"),
            summary(id: "set-2", number: "2"),
            summary(id: "set-1", number: "1")
        ]
        let prices = [cards[0].id: 4.50, cards[1].id: 12.00]

        XCTAssertEqual(query(cards, sort: .numberLowToHigh).map(\.collectorNumber), ["1", "2", "10"])
        XCTAssertEqual(query(cards, sort: .numberHighToLow).map(\.collectorNumber), ["10", "2", "1"])
        XCTAssertEqual(query(cards, sort: .priceHighToLow, prices: prices).map(\.collectorNumber), ["2", "10", "1"])
        XCTAssertEqual(query(cards, sort: .priceLowToHigh, prices: prices).map(\.collectorNumber), ["10", "2", "1"])
    }

    func testSetQueryFiltersOwnedAndNotOwnedIncludingCatalogAliases() {
        let ownedSummary = summary(id: "set-1", number: "1")
        let unownedSummary = summary(id: "set-2", number: "2")
        let alias = completionCard(number: "1", variant: .normal)
        alias.providerID = "csv:Set|1"
        alias.catalogProviderID = ownedSummary.providerID

        XCTAssertEqual(
            query([ownedSummary, unownedSummary], ownership: .owned, ownedCards: [alias]).map(\.id),
            [ownedSummary.id]
        )
        XCTAssertEqual(
            query([ownedSummary, unownedSummary], ownership: .notOwned, ownedCards: [alias]).map(\.id),
            [unownedSummary.id]
        )
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func completionCard(
        number: String,
        variant: PhysicalVariant,
        quantity: Int = 1
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: "test:\(number)#\(variant.id)",
            game: .pokemon,
            providerID: "sv08.5-\(number)",
            name: "Card \(number)",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            quantity: quantity
        )
    }

    private func summary(id: String, number: String) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .pokemon,
            providerID: id,
            setID: CatalogSetID(game: .pokemon, providerID: "set"),
            setName: "Set",
            setCode: "SET",
            name: "Card \(number)",
            collectorNumber: number,
            thumbnailURL: nil,
            imageURL: nil
        )
    }

    private func query(
        _ cards: [CatalogCardSummary],
        sort: CatalogSetSort = .numberLowToHigh,
        ownership: CatalogOwnershipFilter = .all,
        ownedCards: [CollectedCard] = [],
        prices: [String: Double] = [:]
    ) -> [CatalogCardSummary] {
        CatalogSetQuery.apply(
            cards,
            search: "",
            sort: sort,
            ownership: ownership,
            owned: CatalogOwnershipIndex(ownedCards),
            prices: prices
        )
    }

    private func decodePokemon() throws -> TCGdexCard {
        let json = #"""
        {
          "id": "sv08.5-074", "localId": "074", "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074", "rarity": "Common",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions", "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": true, "reverse": true }
        }
        """#
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    private func decodeStampedGengar() throws -> TCGdexCard {
        let json = #"""
        {
          "id": "swsh11-066", "localId": "066", "name": "Gengar",
          "image": "https://assets.tcgdex.net/en/swsh/swsh11/066", "rarity": "Rare Holo",
          "set": { "id": "swsh11", "name": "Lost Origin", "cardCount": { "total": 217, "official": 196 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": true }
        }
        """#
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    // MARK: - Which sets were really printed twice

    /// The e-card sets never had a 1st Edition run — TCGdex reports
    /// `cardCount.firstEd == 0` for Expedition, Aquapolis and Skyridge, against
    /// non-zero counts for every set from Base Set to Neo Destiny. Splitting
    /// them invented a "Skyridge — 1st Edition" master set that never existed
    /// and cut the real set's completion across two impossible halves.
    func testECardSetsAreNotSplitIntoPrintRuns() {
        for id in ["ecard1", "ecard2", "ecard3"] {
            let set = catalogSet(id: id, name: "Skyridge")
            let runs = PokemonMasterSetDefinition.virtualSets(set)
            XCTAssertEqual(runs.count, 1, "\(id) had one print run")
            XCTAssertNil(runs[0].pokemonPrintRun)
            XCTAssertEqual(runs[0].name, "Skyridge", "no qualifier against nothing")
        }
    }

    /// Base Set 2 and Legendary Collection are the other zero-firstEd sets of
    /// the era and must not be split either.
    func testSetsWithoutAFirstEditionRunAreNotSplit() {
        for id in ["base4", "lc"] {
            XCTAssertEqual(
                PokemonMasterSetDefinition.virtualSets(catalogSet(id: id, name: "Base Set 2")).count,
                1
            )
        }
    }

    /// Base Set alone had three runs; the other nine split sets had two.
    func testPrintedTwiceSetsStillSplit() {
        let base = PokemonMasterSetDefinition.virtualSets(catalogSet(id: "base1", name: "Base Set"))
        XCTAssertEqual(base.map(\.pokemonPrintRun), [.firstEdition, .shadowless, .unlimited])

        for id in ["base2", "base3", "base5", "gym1", "gym2", "neo1", "neo2", "neo3", "neo4"] {
            let runs = PokemonMasterSetDefinition.virtualSets(catalogSet(id: id, name: "Jungle"))
            XCTAssertEqual(
                runs.map(\.pokemonPrintRun), [.firstEdition, .unlimited], "\(id) split wrongly"
            )
        }
    }

    func testScannerPrintRunChoicesUseTheSameEligibilityAsBrowse() {
        XCTAssertEqual(
            PokemonMasterSetDefinition.printRuns(forSetProviderID: "base1"),
            [.firstEdition, .shadowless, .unlimited]
        )
        XCTAssertEqual(
            PokemonMasterSetDefinition.printRuns(forSetProviderID: "GYM2"),
            [.firstEdition, .unlimited]
        )
        XCTAssertTrue(PokemonMasterSetDefinition.printRuns(forSetProviderID: "ecard3").isEmpty)
        XCTAssertTrue(PokemonMasterSetDefinition.printRuns(forSetProviderID: "lc").isEmpty)
    }

    private func catalogSet(id: String, name: String) -> CatalogSet {
        CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: id),
            name: name,
            code: name.prefix(3).uppercased(),
            logoURL: nil,
            symbolURL: nil,
            cardCount: 100,
            releaseDate: nil,
            sortRank: 1
        )
    }
}

final class PokemonChecklistBrowseTests: XCTestCase {
    func testBundledChecklistOpensOfflineWithoutCatalogRequests() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let downloadedRoot = root.appendingPathComponent("downloaded", isDirectory: true)
        let set = sampleSet(id: "sv08.5", name: "Prismatic Evolutions")
        let card = sampleSummary(set: set, name: "Eevee")
        try await writeSnapshot([set: [card]], to: bundledRoot)

        let transport = FakePokemonBrowseTransport()
        let store = PokemonChecklistStore(
            root: downloadedRoot,
            bundle: nil,
            bundledRoot: bundledRoot
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        let sets = try await catalog.sets(for: .pokemon)
        let page = try await catalog.cards(in: try XCTUnwrap(sets.first), cursor: nil)

        XCTAssertEqual(sets, [set])
        XCTAssertEqual(page.items, [card])
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.directory, 0)
        XCTAssertEqual(counts.set, 0)
        XCTAssertEqual(counts.card, 0)
    }

    func testDownloadedChecklistOverridesBundledAndSurvivesNewCatalogInstance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let downloadedRoot = root.appendingPathComponent("downloaded", isDirectory: true)
        let bundledSet = sampleSet(id: "sv08.5", name: "Bundled Name")
        let downloadedSet = sampleSet(id: "sv08.5", name: "Refreshed Name")
        try await writeSnapshot(
            [bundledSet: [sampleSummary(set: bundledSet, name: "Bundled Card")]],
            to: bundledRoot
        )
        try await writeSnapshot(
            [downloadedSet: [sampleSummary(set: downloadedSet, name: "Refreshed Card")]],
            to: downloadedRoot
        )

        let transport = FakePokemonBrowseTransport()
        let store = PokemonChecklistStore(root: downloadedRoot, bundle: nil, bundledRoot: bundledRoot)
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )
        let sets = try await catalog.sets(for: .pokemon)
        let page = try await catalog.cards(in: try XCTUnwrap(sets.first), cursor: nil)

        XCTAssertEqual(sets.first?.name, "Refreshed Name")
        XCTAssertEqual(page.items.first?.name, "Refreshed Card")
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.directory, 0)

        let secondStore = PokemonChecklistStore(root: downloadedRoot, bundle: nil, bundledRoot: bundledRoot)
        let secondCatalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages-2")),
            pokemonTransport: transport,
            checklistStore: secondStore
        )
        let secondSets = try await secondCatalog.sets(for: .pokemon)
        XCTAssertEqual(secondSets.first?.name, "Refreshed Name")
    }

    func testOneProviderCardFetchFeedsEveryVirtualPrintRun() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"base1","name":"Base Set","cards":[{"id":"base1-001","localId":"001","name":"Alakazam","image":null}],"cardCount":{"total":1,"official":1,"normal":1,"reverse":0,"holo":0,"firstEd":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"base1-001","localId":"001","name":"Alakazam","image":null,"set":{"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}},"variants":{"firstEdition":true,"holo":true,"normal":false,"reverse":false,"wPromo":false}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["base1": provider],
            cards: ["base1-001": detail]
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(root: root.appendingPathComponent("checklists"), bundle: nil)
        )

        let sets = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(sets.count, 3)
        for set in sets { _ = try await catalog.cards(in: set, cursor: nil) }

        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.set, 1)
        XCTAssertEqual(counts.card, 1)
    }

    func testBuilderPreservesStandardAndExpandedVariantSlots() throws {
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {
          "id":"sv08.5","name":"Prismatic Evolutions",
          "cards":[{"id":"sv08.5-001","localId":"001","name":"Eevee","image":null}],
          "cardCount":{"total":1,"official":1,"normal":1,"reverse":1,"holo":0,"firstEd":0}
        }
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {
          "id":"sv08.5-001","localId":"001","name":"Eevee","image":null,
          "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":1,"official":1}},
          "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true,"wPromo":false},
          "variants_detailed":[
            {"type":"normal","size":"standard","languages":["en"]},
            {"type":"reverse","foil":"pokeball","size":"standard","languages":["en"]},
            {"type":"reverse","foil":"masterball","size":"standard","languages":["en"]}
          ]
        }
        """)

        let built = try XCTUnwrap(
            try PokemonMasterSetChecklistBuilder.build(
                providerSet: provider,
                baseSet: sampleSet(id: "sv08.5", name: "Prismatic Evolutions"),
                cardDetails: [detail.id: detail]
            ).first
        )

        XCTAssertEqual(built.cards.filter { !$0.isExpandedMasterSetVariant }.count, 2)
        XCTAssertEqual(built.cards.filter(\.isExpandedMasterSetVariant).count, 2)
        XCTAssertEqual(Set(built.cards.compactMap { $0.masterSetVariant?.id }), Set([
            PhysicalVariant.normal.id,
            PhysicalVariant.reverse.id,
            PhysicalVariant.pokemonFoilPattern("pokeball").id,
            PhysicalVariant.pokemonFoilPattern("masterball").id
        ]))
    }

    func testSuccessfulRefreshPublishesCompleteChecklistBeforeBrowseUsesIt() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"base1","name":"Base Set","cards":[{"id":"base1-001","localId":"001","name":"Alakazam","image":null}],"cardCount":{"total":1,"official":1,"normal":1,"reverse":0,"holo":0,"firstEd":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"base1-001","localId":"001","name":"Alakazam","image":null,"set":{"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}},"variants":{"firstEdition":true,"holo":true,"normal":false,"reverse":false,"wPromo":false}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["base1": provider],
            cards: ["base1-001": detail]
        )
        let checklistRoot = root.appendingPathComponent("checklists")
        let store = PokemonChecklistStore(root: checklistRoot, bundle: nil)
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        await catalog.refreshCatalogNow()
        let sets = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(sets.count, 3)
        for set in sets {
            let page = try await catalog.cards(in: set, cursor: nil)
            XCTAssertFalse(page.items.isEmpty)
        }

        let downloaded = await store.downloadedSnapshot()
        XCTAssertEqual(downloaded?.manifest.entries.count, 3)
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.set, 1)
        XCTAssertEqual(counts.card, 1)
    }

    func testFailedRefreshLeavesLastCompleteChecklistVisible() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let set = sampleSet(id: "sv08.5", name: "Prismatic Evolutions")
        let card = sampleSummary(set: set, name: "Eevee")
        try await writeSnapshot([set: [card]], to: bundledRoot)

        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":1,"official":1}}
        """)
        let transport = FakePokemonBrowseTransport(rows: [row], setError: TestError.failed)
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(
                root: root.appendingPathComponent("downloaded"),
                bundle: nil,
                bundledRoot: bundledRoot
            )
        )

        await catalog.refreshCatalogNow()
        let page = try await catalog.cards(in: set, cursor: nil)
        XCTAssertEqual(page.items, [card])
        let sets = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(sets.first?.name, "Prismatic Evolutions")
    }

    private func writeSnapshot(
        _ values: [CatalogSet: [CatalogCardSummary]],
        to root: URL
    ) async throws {
        let entries = values.keys.sorted { $0.id < $1.id }.map { set in
            PokemonChecklistSnapshotEntry(
                set: set,
                providerID: set.providerID,
                providerFingerprint: "fixture-\(set.providerID)",
                resource: "sets/\(StableCatalogFingerprint.string(set.id)).json"
            )
        }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: .now,
            directoryFingerprint: "fixture",
            entries: entries
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: manifest,
            checklists: Dictionary(uniqueKeysWithValues: values.map { ($0.key.id, $0.value) })
        )
        try await PokemonChecklistStore(root: root, bundle: nil).publish(snapshot)
    }

    private func sampleSet(id: String, name: String) -> CatalogSet {
        CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: id),
            name: name,
            code: "FIX",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 1
        )
    }

    private func sampleSummary(set: CatalogSet, name: String) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .pokemon,
            providerID: "\(set.providerID)-001",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: name,
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .normal,
            isExpandedMasterSetVariant: false,
            isSoleSlotForCard: true
        )
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from string: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private enum TestError: Error { case failed }

private actor FakePokemonBrowseTransport: PokemonBrowseTransport {
    private let rows: [TCGdexBrowseSet]
    private let setValues: [String: TCGdexSetCatalog]
    private let cardValues: [String: TCGdexCard]
    private let setError: Error?
    private var directoryRequests = 0
    private var setRequests = 0
    private var cardRequests = 0

    init(
        rows: [TCGdexBrowseSet] = [],
        sets: [String: TCGdexSetCatalog] = [:],
        cards: [String: TCGdexCard] = [:],
        setError: Error? = nil
    ) {
        self.rows = rows
        self.setValues = sets
        self.cardValues = cards
        self.setError = setError
    }

    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        directoryRequests += 1
        return rows
    }

    func fetchPocketSetIDs() async throws -> Set<String> { [] }

    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        setRequests += 1
        if let setError { throw setError }
        return try XCTUnwrap(setValues[id.lowercased()])
    }

    func fetchCard(id: String) async throws -> TCGdexCard {
        cardRequests += 1
        return try XCTUnwrap(cardValues[id])
    }

    func requestCounts() -> (directory: Int, set: Int, card: Int) {
        (directoryRequests, setRequests, cardRequests)
    }
}
