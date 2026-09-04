import SwiftData
import XCTest
@testable import TradingCardScanner

final class BrowseFeatureTests: XCTestCase {
#if DEBUG
    func testBundledModernPokemonChecklistCoversEveryScannerSet() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(
            root: root,
            bundle: Bundle.main
        )
        let bundledSnapshot = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(bundledSnapshot)

        for definition in SetCodeMap.definitions.values {
            let entries = snapshot.manifest.entries.filter {
                $0.providerID.caseInsensitiveCompare(definition.tcgdexSetID) == .orderedSame
            }
            XCTAssertFalse(entries.isEmpty, "Missing bundled set \(definition.tcgdexSetID)")
            XCTAssertTrue(
                entries.allSatisfy { !(snapshot.checklist(for: $0.set.catalogID)?.isEmpty ?? true) },
                "Bundled set \(definition.tcgdexSetID) has no checklist"
            )
            XCTAssertTrue(
                entries.allSatisfy { $0.officialCount != nil },
                "Bundled set \(definition.tcgdexSetID) is missing its printed denominator"
            )
        }
    }

#endif
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

    func testSnapshotGeneratorRejectsMissingModernSetCoverage() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try await PokemonChecklistSnapshotGenerator.generate(
                transport: FakePokemonBrowseTransport(),
                outputDirectory: root
            )
            XCTFail("Expected the generator to reject incomplete modern coverage")
        } catch let error as PokemonChecklistError {
            guard case let .missingModernSetCoverage(ids) = error else {
                return XCTFail("Unexpected generator error: \(error)")
            }
            XCTAssertEqual(ids.count, SetCodeMap.definitions.count)
        }
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

    func testGameLandingOrdersSetsNewestFirstByReleaseOrder() {
        let older = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "older"),
            name: "Older",
            code: "OLD",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 10
        )
        let newer = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "newer"),
            name: "Newer",
            code: "NEW",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 20
        )

        XCTAssertEqual(
            CatalogGameCardsOrdering.newestFirst([older, newer]).map(\.id),
            [newer.id, older.id]
        )
    }

    func testSealedSetOrderingUsesReleaseDateNewestFirst() {
        let older = SealedSetSummary(
            id: "older",
            name: "Older Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: Date(timeIntervalSince1970: 100)
        )
        let newer = SealedSetSummary(
            id: "newer",
            name: "Newer Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: Date(timeIntervalSince1970: 200)
        )
        let undated = SealedSetSummary(
            id: "undated",
            name: "Undated Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: nil
        )

        XCTAssertEqual(
            SealedSetOrdering.newestFirst([older, undated, newer]).map(\.id),
            [newer.id, older.id, undated.id]
        )
    }

    @MainActor
    func testSealedSearchReadsCachedResultsWithoutCredentials() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let product = SealedProductSummary(
            id: "cached-sealed-1",
            name: "Cached Booster Box",
            setName: "Example Set",
            variantID: "sealed",
            marketPriceUSD: 100,
            updatedAt: .now,
            imageURL: nil,
            tcgplayerProductID: nil
        )
        let cache = CatalogCacheStore(root: root)
        let key = CatalogCacheStore.sealedPageKey(
            game: .pokemon,
            setID: nil,
            query: "box",
            offset: 0
        )
        await cache.storeSealedProductPage(
            CatalogPage(items: [product], nextCursor: nil),
            for: key
        )
        let client = RecordingJustTCGProviding()
        let model = SealedBrowseModel(
            client: client,
            cache: cache,
            isConfigured: { false }
        )

        await model.search(query: "box")

        XCTAssertEqual(model.searchLanes[.pokemon]?.products, [product])
        let requestCount = await client.sealedSearchCount()
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testSealedSearchPopulatesOneLanePerGameAndHonorsMinimumQueryLength() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pokemonProduct = SealedProductSummary(
            id: "pokemon-sealed-1",
            name: "Pokémon Booster Box",
            setName: "Example Pokémon Set",
            variantID: "sealed",
            marketPriceUSD: 120,
            updatedAt: nil,
            imageURL: nil,
            tcgplayerProductID: nil
        )
        let magicProduct = SealedProductSummary(
            id: "magic-sealed-1",
            name: "Magic Booster Box",
            setName: "Example Magic Set",
            variantID: "sealed",
            marketPriceUSD: 90,
            updatedAt: nil,
            imageURL: nil,
            tcgplayerProductID: nil
        )
        let client = RecordingJustTCGProviding(productsByGame: [
            .pokemon: [pokemonProduct],
            .magic: [magicProduct]
        ])
        let model = SealedBrowseModel(
            client: client,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )

        await model.search(query: "b")
        XCTAssertTrue(model.searchLanes.isEmpty)
        let shortQueryRequestCount = await client.sealedSearchCount()
        XCTAssertEqual(shortQueryRequestCount, 0)

        await model.search(query: "box")

        XCTAssertEqual(model.searchLanes[.pokemon]?.products, [pokemonProduct])
        XCTAssertEqual(model.searchLanes[.magic]?.products, [magicProduct])
        let searchedGames = await client.sealedSearchGames()
        XCTAssertEqual(Set(searchedGames), Set(CardGame.allCases))
    }

    @MainActor
    func testBrowseSearchDebouncesBeforeStartingBothSearchLanes() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sealedClient = RecordingJustTCGProviding()
        let sealedModel = SealedBrowseModel(
            client: sealedClient,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )
        let catalog = EmptyBrowseCatalog()
        let model = BrowseViewModel(catalog: catalog, sealedModel: sealedModel)

        model.searchText = "box"
        try await Task.sleep(for: .milliseconds(150))
        let earlyCardSearchCount = await catalog.searchCount()
        let earlySealedSearchCount = await sealedClient.sealedSearchCount()
        XCTAssertEqual(earlyCardSearchCount, 0)
        XCTAssertEqual(earlySealedSearchCount, 0)

        try await Task.sleep(for: .milliseconds(450))
        let cardSearchCount = await catalog.searchCount()
        let sealedSearchCount = await sealedClient.sealedSearchCount()
        XCTAssertEqual(cardSearchCount, CardGame.allCases.count)
        XCTAssertEqual(sealedSearchCount, CardGame.allCases.count)
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

    func testPreTreatmentCSVUsesCollectionReadThrough() throws {
        let context = try makeContext()
        let existing = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=surgefoil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        context.insert(existing)
        try context.save()

        // This is the shape exported before Slice 5 appended the treatment
        // column: the old finish key is the treatment-free alias.
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,finish,finish_name,quantity
        magic,printing,Fixture,Fixture Set,FIC,10,foil,Foil,1
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.insertedEntries, 0)
        XCTAssertEqual(existing.quantity, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.collectionKey),
            ["magic:printing#foil#treatment=surgefoil"]
        )
    }

    func testPostTreatmentCSVUsesCollectionReadThroughForLegacyRow() throws {
        let context = try makeContext()
        let existing = CollectedCard(
            collectionKey: "magic:printing#foil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed
        )
        context.insert(existing)
        try context.save()

        let source = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=neonink",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.neonInk],
            magicTreatmentQualifiers: ["neonink": "red"]
        )

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([source]).text.utf8)
        )
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.insertedEntries, 0)
        XCTAssertEqual(existing.collectionKey, source.collectionKey)
        XCTAssertEqual(existing.magicTreatmentIDsRaw, ["neonink"])
        XCTAssertEqual(existing.magicTreatmentQualifiers, ["neonink": "red"])
        XCTAssertEqual(existing.quantity, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testCSVImportStoresUnknownTreatmentAndContentKindWithoutProjectingIt() throws {
        let context = try makeContext()
        let unknown = try XCTUnwrap(MagicTreatment(id: "Future / Foil"))
        let source = CollectedCard(
            collectionKey: MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
                base: "magic:printing",
                game: .magic,
                finish: .foil,
                treatments: [unknown]
            ),
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [unknown],
            magicTreatmentQualifiers: ["Future / Foil": "publisher stamp"]
        )
        source.magicContentKindRaw = "future-face"

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([source]).text.utf8)
        )
        _ = try CollectionCSV.apply(plan, to: context)
        let stored = try XCTUnwrap(
            context.fetch(FetchDescriptor<CollectedCard>()).first
        )

        XCTAssertEqual(stored.magicTreatmentIDsRaw, ["Future / Foil"])
        XCTAssertEqual(stored.magicTreatmentQualifiers, ["future / foil": "publisher stamp"])
        XCTAssertEqual(stored.magicContentKindRaw, "future-face")
        XCTAssertEqual(stored.magicContentKind, .regular)
        XCTAssertEqual(stored.variant, .foil)
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

    /// The instrument a position is attributed to and the record whose price is
    /// shown for it must be one decision. `CollectionView` projects the whole
    /// collection through this on every render, so it also has to answer without
    /// touching the store — the ledger's equivalent costs two predicate fetches
    /// per candidate key, which is what made the grid re-fetch thousands of rows
    /// per keystroke.
    func testPriceStorageKeyAgreesWithTheRecordThatSuppliesThePrice() {
        let card = completionCard(number: "001", variant: .firstEdition)
        let legacyKey = PriceRecord.key(
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        XCTAssertNotEqual(card.priceKey, legacyKey)

        // No records at all: the canonical key, never a legacy one.
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: [:]), card.priceKey)

        // Only the legacy key holds a value, so that is the instrument in force
        // — matching the record `record(for:in:)` hands back for display.
        let legacyRecord = PriceRecord(
            key: legacyKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        legacyRecord.applyImported(amount: 125, sourceUpdatedAt: nil)
        let legacyOnly = [legacyKey: legacyRecord]
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: legacyOnly), legacyKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: legacyOnly)?.key,
            PriceStore.priceStorageKey(for: card, in: legacyOnly)
        )

        // Once the canonical key carries its own value it wins outright.
        let canonical = PriceRecord(
            key: card.priceKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: card.variantID
        )
        canonical.applyImported(amount: 200, sourceUpdatedAt: nil)
        let both = [legacyKey: legacyRecord, card.priceKey: canonical]
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: both), card.priceKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: both)?.key,
            PriceStore.priceStorageKey(for: card, in: both)
        )

        // An invalidated canonical record is authoritative: the position must
        // not fall through to the legacy value the invalidation withdrew.
        canonical.invalidate(at: .now)
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: both), card.priceKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: both)?.key,
            PriceStore.priceStorageKey(for: card, in: both)
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

    func testCatalogSetQuerySortsCollectorNumberSuffixesNaturally() {
        let cards = [
            magicSummary(id: "suffix-b", number: "525b"),
            magicSummary(id: "bare", number: "525"),
            magicSummary(id: "suffix-a", number: "525a")
        ]

        XCTAssertEqual(
            query(cards).map(\.collectorNumber),
            ["525", "525a", "525b"]
        )
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

    func testCatalogSummaryCarriesTreatmentAndQualifierWithoutChangingItsSlotID() throws {
        let summary = magicSummary(
            id: "printing",
            number: "429",
            treatments: [MagicTreatment.neonInk.id],
            qualifiers: [MagicTreatment.neonInk.id: "red"]
        )
        let decoded = try JSONDecoder().decode(
            CatalogCardSummary.self,
            from: JSONEncoder().encode(summary)
        )

        XCTAssertEqual(decoded.magicTreatmentIDsRaw, ["neonink"])
        XCTAssertEqual(decoded.magicTreatmentDisplayLabel, "Neon Ink · Red")
        XCTAssertEqual(decoded.id, summary.id)
    }

    func testBrowseOwnershipRequiresTreatmentWhenTheSummarySpecifiesOne() {
        let summary = magicSummary(
            id: "fic-10",
            number: "10",
            treatments: [MagicTreatment.surgeFoil.id]
        )
        let genericFoil = magicCompletionCard(number: "10", variant: .foil)
        let treatedFoil = magicCompletionCard(
            number: "10",
            variant: .foil,
            treatments: [.surgeFoil]
        )
        let nonfoil = magicCompletionCard(number: "10", variant: .nonfoil)

        XCTAssertFalse(SetCompletionCalculator.owns(summary, cards: [genericFoil]))
        XCTAssertFalse(SetCompletionCalculator.owns(summary, cards: [nonfoil]))
        XCTAssertTrue(SetCompletionCalculator.owns(summary, cards: [treatedFoil]))
        XCTAssertEqual(
            CatalogOwnershipIndex([genericFoil, treatedFoil]).quantity(of: summary),
            1
        )
    }

    func testSetCompletionDoesNotCreateATreatmentSlotAndKeepsSuffixesDistinct() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .magic, providerID: "fic"),
            name: "Final Fantasy Commander",
            code: "FIC",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 2,
            releaseDate: nil,
            sortRank: 1
        )
        let owned = [
            magicCompletionCard(number: "523a", variant: .foil),
            magicCompletionCard(number: "523a", variant: .foil, treatments: [.surgeFoil]),
            magicCompletionCard(number: "523b", variant: .foil)
        ]

        XCTAssertEqual(
            SetCompletionCalculator.progress(for: set, cards: owned),
            SetCompletion(owned: 2, total: 2, unit: "cards")
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

    private func summary(
        id: String,
        number: String,
        treatments: [String] = []
    ) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .pokemon,
            providerID: id,
            setID: CatalogSetID(game: .pokemon, providerID: "set"),
            setName: "Set",
            setCode: "SET",
            name: "Card \(number)",
            collectorNumber: number,
            thumbnailURL: nil,
            imageURL: nil,
            magicTreatmentIDsRaw: treatments
        )
    }

    private func magicSummary(
        id: String,
        number: String,
        treatments: [String] = [],
        qualifiers: [String: String] = [:]
    ) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .magic,
            providerID: id,
            setID: CatalogSetID(game: .magic, providerID: "fic"),
            setName: "Final Fantasy Commander",
            setCode: "FIC",
            name: "Fixture",
            collectorNumber: number,
            thumbnailURL: nil,
            imageURL: nil,
            magicTreatmentIDsRaw: treatments,
            magicTreatmentQualifiers: qualifiers
        )
    }

    private func magicCompletionCard(
        number: String,
        variant: PhysicalVariant,
        treatments: [MagicTreatment] = []
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: "magic:fic-\(number)#\(variant.id)",
            game: .magic,
            providerID: "fic-\(number)",
            name: "Fixture",
            setName: "Final Fantasy Commander",
            setCode: "FIC",
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            magicTreatments: treatments
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
    func testOfflineModernPokemonCardResolvesWithoutProviderRequests() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv10"),
            name: "Destined Rivals",
            code: "DRI",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 182,
            releaseDate: nil,
            sortRank: 1
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv10-085",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Example Pokémon",
            collectorNumber: "085",
            thumbnailURL: URL(string: "https://example.com/card-small.png"),
            imageURL: URL(string: "https://example.com/card-large.png")
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv10",
                    providerFingerprint: "fixture",
                    resource: "sets/sv10.json"
                )]
            ),
            checklists: [set.id: [summary]]
        )
        let store = PokemonChecklistStore(root: root, bundle: nil)
        try await store.publish(snapshot)
        let offline = PokemonOfflineCatalog(
            store: PokemonChecklistStore(root: root, bundle: nil)
        )

        let offlineCard = await offline.card(
            providerSetID: "SV10",
            localID: "085",
            expectedOfficialCount: 182
        )
        let card = try XCTUnwrap(offlineCard)
        XCTAssertEqual(card.id, "sv10-085")
        XCTAssertEqual(card.name, "Example Pokémon")
        XCTAssertNil(card.pricing)
        XCTAssertNil(card.variants)
        XCTAssertEqual(card.highImageURL, URL(string: "https://example.com/card-large.png"))

        let identified = IdentifiedCard.pokemon(card, setCode: "DRI")
        XCTAssertEqual(
            VariantResolver.resolve(identified.variantEvidence),
            .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        )
    }

    func testOfflinePokemonCardAllowsMasterCountDifferentFromPrintedDenominator() throws {
        let set = sampleSet(id: "sv10", name: "Destined Rivals")
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv10-085",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Example Pokémon",
            collectorNumber: "085",
            thumbnailURL: nil,
            imageURL: nil
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv10",
                    providerFingerprint: "fixture",
                    resource: "sets/sv10.json"
                )]
            ),
            checklists: [set.id: [summary]]
        )

        XCTAssertNotNil(
            PokemonOfflineCardFactory.card(
                in: snapshot,
                providerSetID: "sv10",
                localID: "085",
                expectedOfficialCount: 181
            )
        )
    }

    func testOfflineHistoricalMatchingRejectsWrongPrintedDenominator() throws {
        let set = sampleSet(id: "sv09", name: "Journey Together")
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv09-085",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Example Pokémon",
            collectorNumber: "085",
            thumbnailURL: nil,
            imageURL: nil
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv09",
                    providerFingerprint: "fixture",
                    officialCount: 159,
                    resource: "sets/sv09.json"
                )]
            ),
            checklists: [set.id: [summary]]
        )
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(
                numberLines: ["085/182"],
                titleLines: ["Example Pokémon"]
            )
        )
        guard case let .pokemonHistorical(evidence) = identifier else {
            return XCTFail("Expected historical Pokémon evidence")
        }

        XCTAssertNil(
            PokemonOfflineCardFactory.historicalCard(in: snapshot, evidence: evidence),
            "A same-number/title match from a set with the wrong denominator must not identify the card."
        )
    }

    func testOfflinePokemonCardPreservesAllPublishedVariantRows() throws {
        let set = sampleSet(id: "sv04", name: "Paradox Rift")
        let variants: [PhysicalVariant] = [.normal, .holo, .reverse, PhysicalVariant(id: "energy", label: "Energy")]
        let summaries = variants.map { variant in
            CatalogCardSummary(
                game: .pokemon,
                providerID: "sv04-085",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Example Pokémon",
                collectorNumber: "085",
                thumbnailURL: nil,
                imageURL: nil,
                masterSetVariant: variant,
                isExpandedMasterSetVariant: variant.id == "energy",
                isSoleSlotForCard: false
            )
        }
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv04",
                    providerFingerprint: "fixture",
                    resource: "sets/sv04.json"
                )]
            ),
            checklists: [set.id: summaries]
        )

        let card = try XCTUnwrap(
            PokemonOfflineCardFactory.card(
                in: snapshot,
                providerSetID: "sv04",
                localID: "085",
                expectedOfficialCount: 182
            )
        )
        XCTAssertNil(card.pricing)
        XCTAssertEqual(
            Set(card.catalogVariants),
            Set(variants)
        )
        switch VariantResolver.resolve(
            IdentifiedCard.pokemon(card, setCode: "PAR").variantEvidence
        ) {
        case let .needsChoice(options, lockDidNotApply):
            XCTAssertNil(lockDidNotApply)
            XCTAssertEqual(Set(options), Set(variants))
        case .resolved:
            XCTFail("Multiple offline variant rows must remain a user choice.")
        }
    }

    func testOfflineModernScanUsesZeroProviderRequestsEvenWhenMasterCountDiffers() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv04"),
            name: "Paradox Rift",
            code: "PAR",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 250,
            releaseDate: nil,
            sortRank: 1
        )
        let summaries = ["085", "182"].map { number in
            CatalogCardSummary(
                game: .pokemon,
                providerID: "sv04-\(number)",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Offline Card \(number)",
                collectorNumber: number,
                thumbnailURL: nil,
                imageURL: nil
            )
        }
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: set.providerID,
                    providerFingerprint: "fixture",
                    resource: "sets/sv04.json"
                )]
            ),
            checklists: [set.id: summaries]
        )
        try await PokemonChecklistStore(root: root, bundle: nil).publish(snapshot)

        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .failure(.badResponse)
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root, bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["PAR"])
        for number in ["085", "182"] {
            let card = try await catalog.card(for: .pokemon(
                setCode: "PAR",
                cardNumber: number,
                printedTotal: definition.officialCount,
                setDefinition: definition
            ))
            XCTAssertEqual(card.name, "Offline Card \(number)")
        }
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testPokemonFallbackUsesSecondaryProviderOnlyAfterRetryablePrimaryFailure() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .card(pokemonAPIResult(setID: "sv10", number: "85"))
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let card = try await catalog.card(for: .pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        ))

        // The secondary provider returns `sv10-85`, but the resolved card must
        // remain addressable by TCGdex as `sv10-085` for later repricing.
        XCTAssertEqual(card.providerID, "sv10-085")
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 1)
    }

    func testModernFallbackSuccessDoesNotClearTCGdexBreaker() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .card(pokemonAPIResult(setID: "sv10", number: "85"))
        )
        let breaker = TCGdexCircuitBreaker(cooldown: 60)
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: breaker
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])

        _ = try await catalog.card(for: .pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        ))

        let breakerPermitted = await breaker.permitsRequest(now: Date().addingTimeInterval(1))
        XCTAssertFalse(breakerPermitted)
    }

    func testPromoFallbackSuccessDoesNotClearTCGdexBreaker() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .card(pokemonAPIResult(setID: "svp", number: "001"))
        )
        let breaker = TCGdexCircuitBreaker(cooldown: 60)
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: breaker
        )
        let definition = PokemonPromoSetDefinition(
            printedPrefix: "SVP",
            tcgdexSetID: "svp",
            catalogLocalIDPrefix: ""
        )

        _ = try await catalog.card(for: .pokemonPromo(
            prefix: "SVP",
            localID: "001",
            setDefinition: definition
        ))

        let breakerPermitted = await breaker.permitsRequest(now: Date().addingTimeInterval(1))
        XCTAssertFalse(breakerPermitted)
    }

    func testNetworkPokemonLookupDoesNotRequireProviderDenominator() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .card(try makeTCGdexCard(setID: "sv10", localID: "085")),
            fallback: .failure(.badResponse)
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let card = try await catalog.card(for: .pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        ))

        XCTAssertEqual(card.providerID, "sv10-085")
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testPokemonCardNotFoundDoesNotFallThroughToSecondaryProvider() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.cardNotFound),
            fallback: .card(pokemonAPIResult(setID: "sv10", number: "85"))
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])

        do {
            _ = try await catalog.card(for: .pokemon(
                setCode: "DRI",
                cardNumber: "085",
                printedTotal: definition.officialCount,
                setDefinition: definition
            ))
            XCTFail("Expected terminal card-not-found")
        } catch {
            XCTAssertEqual(CardCatalog.classify(error), .notInCatalog)
        }
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testVariantlessResolvedCacheFallsThroughToTheOfflineVariantChecklist() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("resolved")
        let offlineRoot = root.appendingPathComponent("offline")
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let key = "pokemon|sv10|085|\(definition.officialCount)"

        // Simulate a cache entry with the right identity but no finish
        // evidence, exactly as an outage-time fallback used to save.
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let storedAt = ISO8601DateFormatter().string(from: .now)
        let staleFile = """
        {"appVersion":"test","schemaGeneration":2,"entries":[
          {"key":"\(key)","storedAt":"\(storedAt)","cardID":"sv10-085","localID":"085","name":"Stale cache card","image":null,"rarity":null,"setID":"sv10","setName":"Destined Rivals","officialCount":\(definition.officialCount),"setCode":"DRI","variants":[]}
        ]}
        """
        try Data(staleFile.utf8).write(to: cacheRoot.appendingPathComponent("ResolvedPokemonCards.json"))

        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv10"),
            name: "Destined Rivals",
            code: "DRI",
            logoURL: nil,
            symbolURL: nil,
            cardCount: definition.officialCount,
            releaseDate: nil,
            sortRank: 1
        )
        let summaries: [CatalogCardSummary] = [.normal, .reverse].map { variant in
            CatalogCardSummary(
                game: .pokemon,
                providerID: "sv10-085",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Checklist card",
                collectorNumber: "085",
                thumbnailURL: nil,
                imageURL: nil,
                masterSetVariant: variant,
                isExpandedMasterSetVariant: false,
                isSoleSlotForCard: false
            )
        }
        try await writeSnapshot([set: summaries], to: offlineRoot)

        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .failure(.badResponse)
        )
        let cache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: offlineRoot, bundle: nil)
            ),
            resolvedDiskCache: cache,
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        )

        let card = try await catalog.card(for: identifier)

        XCTAssertEqual(card.name, "Checklist card")
        XCTAssertEqual(Set(card.variantEvidence.catalogVariants), Set([.normal, .reverse]))
        switch VariantResolver.resolve(card.variantEvidence) {
        case let .needsChoice(options, _):
            XCTAssertEqual(Set(options), Set([.normal, .reverse]))
        case .resolved:
            XCTFail("A richer offline checklist must reopen the finish picker.")
        }
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.fallback, 0)
        let healedCacheEntry = await cache.card(for: key)
        XCTAssertNil(healedCacheEntry, "variant-less entries self-heal on the next scan")
    }

    func testPriorGenerationResolvedCacheIsIgnored() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("resolved")
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let key = "pokemon|sv10|085|\(definition.officialCount)"

        // A complete entry from the prior format must not survive the schema
        // invalidation merely because it contains usable variant evidence.
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let storedAt = ISO8601DateFormatter().string(from: .now)
        let oldGenerationFile = """
        {"appVersion":"test","schemaGeneration":1,"entries":[
          {"key":"\(key)","storedAt":"\(storedAt)","cardID":"sv10-085","localID":"085","name":"Old generation card","image":null,"rarity":null,"setID":"sv10","setName":"Destined Rivals","officialCount":\(definition.officialCount),"setCode":"DRI","variants":[{"id":"normal","label":"Non-Holo"},{"id":"reverse","label":"Reverse Holo"}]}
        ]}
        """
        try Data(oldGenerationFile.utf8).write(
            to: cacheRoot.appendingPathComponent("ResolvedPokemonCards.json")
        )

        let cache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")
        let cachedEntry = await cache.card(for: key)

        XCTAssertNil(cachedEntry, "A prior cache generation must always be treated as a miss.")
    }

    func testVariantlessStorePreservesAnExistingResolvedCard() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let key = "pokemon|sv10|085|\(definition.officialCount)"
        let cache = ResolvedPokemonCardCache(
            root: root.appendingPathComponent("resolved"),
            appVersion: "test"
        )
        let completeCard = try makeTCGdexCard(setID: "sv10", localID: "085")
        let incompleteCard = try decode(TCGdexCard.self, from: """
        {"id":"sv10-085","localId":"085","name":"Incomplete Card","image":null,
         "set":{"id":"sv10","name":"Destined Rivals","cardCount":{"total":\(definition.officialCount),"official":\(definition.officialCount)}}}
        """)

        await cache.store(
            card: completeCard,
            setCode: "DRI",
            key: key,
            officialCount: definition.officialCount
        )
        await cache.store(
            card: incompleteCard,
            setCode: "DRI",
            key: key,
            officialCount: definition.officialCount
        )
        let storedEntry = await cache.card(for: key)
        let cachedEntry = try XCTUnwrap(storedEntry)

        XCTAssertEqual(cachedEntry.card.name, "Resolved Card")
        XCTAssertEqual(
            Set(cachedEntry.card.catalogVariants),
            Set([.normal, .reverse]),
            "A variant-less response must not evict an existing complete cache entry."
        )
    }

    func testResolvedPokemonIdentitySurvivesAColdCatalogInstance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("resolved")
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let firstSource = CountingPokemonCardSource(
            primary: .card(try makeTCGdexCard(setID: "sv10", localID: "085")),
            fallback: .failure(.badResponse)
        )
        let first = CardCatalog(
            source: firstSource,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test"),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        )
        _ = try await first.card(for: identifier)

        let secondSource = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .failure(.badResponse)
        )
        let second = CardCatalog(
            source: secondSource,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test"),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let card = try await second.card(for: identifier)

        XCTAssertEqual(card.providerID, "sv10-085")
        let counts = await secondSource.requestCounts()
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.fallback, 0)
    }

    private func makeTCGdexCard(setID: String, localID: String) throws -> TCGdexCard {
        try decode(TCGdexCard.self, from: """
        {"id":"\(setID)-\(localID)","localId":"\(localID)","name":"Resolved Card","image":null,
         "set":{"id":"\(setID)","name":"Resolved Set","cardCount":{"total":1,"official":1}},
         "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true}}
        """)
    }

    private func pokemonAPIResult(setID: String, number: String) -> PokemonTCGAPICard {
        PokemonTCGAPICard(
            id: "\(setID)-\(CatalogIdentityNormalization.localNumber(number))",
            name: "Fallback Card",
            number: number,
            set: PokemonTCGAPISet(id: setID, name: "Fallback Set", printedTotal: nil),
            images: PokemonTCGAPIImages(
                small: URL(string: "https://example.com/small.png")!,
                large: URL(string: "https://example.com/large.png")!
            )
        )
    }

    func testTCGdexCircuitBreakerSuppressesRequestsDuringCooldown() async {
        let breaker = TCGdexCircuitBreaker(cooldown: 10)
        let now = Date(timeIntervalSince1970: 10_000)

        let initiallyPermitted = await breaker.permitsRequest(now: now)
        XCTAssertTrue(initiallyPermitted)
        await breaker.recordFailure(now: now)
        let blockedDuringCooldown = await breaker.permitsRequest(now: now.addingTimeInterval(1))
        XCTAssertFalse(blockedDuringCooldown)
        let permittedAfterCooldown = await breaker.permitsRequest(now: now.addingTimeInterval(11))
        XCTAssertTrue(permittedAfterCooldown)
    }

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

    func testRefreshPublishesSuccessfulSetsWhenALaterSetFails() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try (1...5).map { index in
            try decode(TCGdexBrowseSet.self, from: """
            {"id":"fixture\(index)","name":"Fixture \(index)","cardCount":{"total":1,"official":1}}
            """)
        }
        var providers: [String: TCGdexSetCatalog] = [:]
        var cards: [String: TCGdexCard] = [:]
        for index in 1...5 {
            let providerID = "fixture\(index)"
            let cardID = "\(providerID)-001"
            providers[providerID] = try decode(TCGdexSetCatalog.self, from: """
            {"id":"\(providerID)","name":"Fixture \(index)","cards":[{"id":"\(cardID)","localId":"001","name":"Card \(index)","image":null}],"cardCount":{"total":1,"official":1}}
            """)
            cards[cardID] = try decode(TCGdexCard.self, from: """
            {"id":"\(cardID)","localId":"001","name":"Card \(index)","image":null,
             "set":{"id":"\(providerID)","name":"Fixture \(index)","cardCount":{"total":1,"official":1}}}
            """)
        }
        let transport = FakePokemonBrowseTransport(
            rows: rows,
            sets: providers,
            cards: cards,
            failingSetIDs: ["fixture3"]
        )
        let store = PokemonChecklistStore(
            root: root.appendingPathComponent("checklists"),
            bundle: nil
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        await catalog.refreshCatalogNow()

        let downloaded = await store.downloadedSnapshot()
        let publishedIDs = Set(downloaded?.manifest.entries.map(\.providerID) ?? [])
        XCTAssertTrue(publishedIDs.contains("fixture1"))
        XCTAssertTrue(publishedIDs.contains("fixture2"))
        XCTAssertFalse(publishedIDs.contains("fixture3"))
        XCTAssertTrue(publishedIDs.contains("fixture4"))
        XCTAssertTrue(publishedIDs.contains("fixture5"))
    }

    func testCorruptChecklistEntryDoesNotHideOtherValidEntries() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = sampleSet(id: "fixture1", name: "Fixture One")
        let second = sampleSet(id: "fixture2", name: "Fixture Two")
        let store = PokemonChecklistStore(root: root, bundle: nil)
        try await writeSnapshot(
            [
                first: [sampleSummary(set: first, name: "First")],
                second: [sampleSummary(set: second, name: "Second")]
            ],
            to: root
        )

        let firstResource = root.appendingPathComponent(
            "sets/\(StableCatalogFingerprint.string(first.id)).json"
        )
        try Data("not-json".utf8).write(to: firstResource, options: .atomic)

        let loaded = await store.downloadedSnapshot()
        XCTAssertEqual(
            Set(loaded?.manifest.entries.map(\.providerID) ?? []),
            Set(["fixture2"])
        )
        XCTAssertEqual(loaded?.checklist(for: second.catalogID)?.first?.name, "Second")
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

private actor RecordingJustTCGProviding: SealedBrowseProviding {
    private let productsByGame: [CardGame: [SealedProductSummary]]
    private var sealedSearches = 0
    private var searchedGames: [CardGame] = []

    init(productsByGame: [CardGame: [SealedProductSummary]] = [:]) {
        self.productsByGame = productsByGame
    }

    func searchSealedProducts(
        game: CardGame,
        setID: String?,
        query: String?,
        offset: Int
    ) async throws -> MarketCatalogPage<SealedProductSummary> {
        sealedSearches += 1
        searchedGames.append(game)
        let items = productsByGame[game] ?? []
        return MarketCatalogPage(
            items: items,
            total: items.count,
            offset: offset,
            limit: JustTCGQuota.maximumPageSize,
            hasMore: false
        )
    }

    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] {
        throw TestError.failed
    }

    func sealedSearchCount() -> Int { sealedSearches }
    func sealedSearchGames() -> [CardGame] { searchedGames }
}

private actor EmptyBrowseCatalog: BrowseCatalogProviding {
    private var searches = 0

    func sets(for game: CardGame) async throws -> [CatalogSet] { [] }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [], nextCursor: nil)
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        searches += 1
        return CatalogPage(items: [], nextCursor: nil)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        throw TestError.failed
    }

    func sortPrices(for cards: [CatalogCardSummary]) async -> [String: Double] { [:] }
    func prepareCatalog() async {}

    func searchCount() -> Int { searches }
}

private actor FakePokemonBrowseTransport: PokemonBrowseTransport {
    private let rows: [TCGdexBrowseSet]
    private let setValues: [String: TCGdexSetCatalog]
    private let cardValues: [String: TCGdexCard]
    private let setError: Error?
    private let failingSetIDs: Set<String>
    private var directoryRequests = 0
    private var setRequests = 0
    private var cardRequests = 0

    init(
        rows: [TCGdexBrowseSet] = [],
        sets: [String: TCGdexSetCatalog] = [:],
        cards: [String: TCGdexCard] = [:],
        setError: Error? = nil,
        failingSetIDs: Set<String> = []
    ) {
        self.rows = rows
        self.setValues = sets
        self.cardValues = cards
        self.setError = setError
        self.failingSetIDs = Set(failingSetIDs.map { $0.lowercased() })
    }

    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        directoryRequests += 1
        return rows
    }

    func fetchPocketSetIDs() async throws -> Set<String> { [] }

    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        setRequests += 1
        if let setError { throw setError }
        if failingSetIDs.contains(id.lowercased()) { throw TestError.failed }
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

private actor CountingPokemonCardSource: PokemonCardSource {
    enum PrimaryResponse: Sendable {
        case card(TCGdexCard)
        case failure(TCGdexError)
    }

    enum FallbackResponse: Sendable {
        case card(PokemonTCGAPICard)
        case failure(TCGdexError)
        case empty
    }

    private let primaryResponse: PrimaryResponse
    private let fallbackResponse: FallbackResponse
    private var primaryRequests = 0
    private var fallbackRequests = 0

    init(primary: PrimaryResponse, fallback: FallbackResponse) {
        self.primaryResponse = primary
        self.fallbackResponse = fallback
    }

    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        primaryRequests += 1
        switch primaryResponse {
        case let .card(card): return card
        case let .failure(error): throw error
        }
    }

    func fetchPokemonTCGCard(setID: String, cardNumber: String) async throws -> PokemonTCGAPICard? {
        fallbackRequests += 1
        switch fallbackResponse {
        case let .card(card): return card
        case let .failure(error): throw error
        case .empty: return nil
        }
    }

    func requestCounts() -> (primary: Int, fallback: Int) {
        (primaryRequests, fallbackRequests)
    }
}
