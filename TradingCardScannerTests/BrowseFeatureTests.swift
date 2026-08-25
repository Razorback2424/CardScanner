import SwiftData
import XCTest
@testable import TradingCardScanner

final class BrowseFeatureTests: XCTestCase {
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
        let mutation = CollectionStore(context: context).add(
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
        let mutation = store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            identityResolution: .catalogSelected,
            setReleaseOrder: 300,
            matchCatalogAliases: true
        )

        let inserted = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(inserted.identityResolution, .catalogSelected)
        XCTAssertEqual(inserted.setReleaseOrder, 300)

        store.undo(mutation)
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
        _ = store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )

        let mutation = try XCTUnwrap(
            store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed)
            )
        )
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())

        XCTAssertEqual(activities.count, 1, "a correction is not another acquisition")
        XCTAssertEqual(activities.first?.source, .scan)
        XCTAssertEqual(activities.first?.collectionKey, mutation.collectionKey)
        XCTAssertEqual(activities.first?.variantID, PhysicalVariant.reverse.id)
        XCTAssertNotNil(activities.first?.correctedAt)
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
            for: CollectedCard.self, PriceRecord.self, CollectionActivity.self,
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

    /// Base Set alone had three runs; the other ten split sets had two.
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
