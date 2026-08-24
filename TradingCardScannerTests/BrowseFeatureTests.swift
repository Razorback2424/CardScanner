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
            SetCompletion(owned: 2, total: 180)
        )
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

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self,
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
}
