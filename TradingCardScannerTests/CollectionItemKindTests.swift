import XCTest
import SwiftData
@testable import TradingCardScanner

/// Graded slabs and sealed products entering a collection that was built for
/// raw singles. The rules that keep them from contaminating what was there.
@MainActor
final class CollectionItemKindTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, ProductIdentity.self,
            CollectionActivity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func rawCard(number: String = "001", setCode: String = "PRE") -> CollectedCard {
        CollectedCard(
            collectionKey: "raw-\(setCode)-\(number)",
            game: .pokemon,
            providerID: "sv08.5-\(number)",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: setCode,
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .holo,
            variantResolution: .userConfirmed
        )
    }

    // MARK: - Migration

    /// Every row written before item kinds existed is a raw card, and says so
    /// without a migration pass.
    func testExistingRowsMigrateAsRawCards() throws {
        let card = rawCard()

        XCTAssertEqual(card.itemKind, .rawCard)
        XCTAssertEqual(card.itemKindLabel, PhysicalVariant.holo.label)
        XCTAssertNil(card.cardGrade)
    }

    /// Raw keys keep their unprefixed form, so no existing ownership row or
    /// price record moves.
    func testRawKeysAreUnchangedByTheWidening() {
        let raw = PriceRecord.key(game: .pokemon, printingID: "sv08.5-001", variantID: "holo")

        XCTAssertFalse(raw.hasPrefix("graded:"))
        XCTAssertFalse(raw.hasPrefix("sealed:"))
        XCTAssertEqual(raw, PriceRecord.key(game: .pokemon, printingID: "sv08.5-001", variantID: "holo"))
    }

    // MARK: - Grades

    /// Grades are text, because `9.5` is not an integer and `Authentic` is not a
    /// number at all.
    func testGradeLabelsRenderTheWayCollectorsWriteThem() {
        XCTAssertEqual(CardGrade(value: "10").display(company: .psa), "PSA 10")
        XCTAssertEqual(CardGrade(value: "9.5").display(company: .bgs), "BGS 9.5")
        XCTAssertEqual(
            CardGrade(value: "10", label: "Black Label").display(company: .bgs),
            "BGS 10 Black Label"
        )
        XCTAssertEqual(
            CardGrade(value: "10", qualifier: "OC").display(company: .psa),
            "PSA 10 OC"
        )
        XCTAssertEqual(
            CardGrade(value: nil, label: "Authentic").display(company: .cgc),
            "CGC Authentic"
        )
        XCTAssertEqual(
            CardGrade(value: "10", label: "Pristine").display(company: .cgc),
            "CGC 10 Pristine"
        )
    }

    /// A qualifier makes a different object. A PSA 10 and a PSA 10 OC are not
    /// the same holding and must never merge.
    func testEveryGraderGradeLabelAndQualifierStaysDistinct() {
        let grades = [
            CardGrade(value: "10"),
            CardGrade(value: "10", qualifier: "OC"),
            CardGrade(value: "10", label: "Black Label"),
            CardGrade(value: "9.5"),
            CardGrade(value: nil, label: "Authentic")
        ]
        let fragments = Set(grades.map(\.identityFragment))

        XCTAssertEqual(fragments.count, grades.count, "each must be its own holding")
    }

    // MARK: - Namespaced keys

    func testGradedAndSealedRowsCannotCollideWithRaw() {
        let graded = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "sv08.5-001", variantUUID: "g-uuid"
        )
        let sealed = CollectedCard.sealedCollectionKey(
            game: .pokemon, productUUID: "p-uuid", variantUUID: "v-uuid"
        )

        XCTAssertNotEqual(graded, sealed)
        XCTAssertTrue(graded.contains("sv08.5-001"))
        XCTAssertTrue(sealed.hasPrefix("sealed:pokemon:"))
    }

    func testMagicTreatmentIsNamespacedInGradedAndSealedKeys() {
        let graded = CollectedCard.gradedCollectionKey(
            game: .magic,
            underlyingPrintingID: "neo-429",
            variantUUID: "graded-uuid",
            magicTreatments: [.neonInk]
        )
        let certified = CollectedCard.gradedCollectionKey(
            game: .magic,
            underlyingPrintingID: "neo-429",
            variantUUID: "graded-uuid",
            certificationNumber: "1234",
            magicTreatments: [.neonInk]
        )
        let sealed = CollectedCard.sealedCollectionKey(
            game: .magic,
            productUUID: "product-uuid",
            variantUUID: "variant-uuid",
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            graded,
            "graded:magic:neo-429:graded-uuid#treatment=neonink"
        )
        XCTAssertEqual(
            certified,
            "graded:magic:neo-429:graded-uuid:cert:1234#treatment=neonink"
        )
        XCTAssertEqual(
            sealed,
            "sealed:magic:product-uuid:variant-uuid#treatment=surgefoil"
        )
        XCTAssertNotEqual(graded, certified)
        XCTAssertNotEqual(graded, sealed)
    }

    func testMagicTreatmentPriceRowsDoNotReadThroughGenericFoilPrice() {
        let card = CollectedCard(
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
        let genericKey = PriceRecord.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        let treatmentKey = PriceRecord.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )

        XCTAssertEqual(card.priceKey, treatmentKey)
        XCTAssertTrue(card.legacyPriceKeys.isEmpty)
        XCTAssertNotEqual(card.priceKey, genericKey)
        XCTAssertEqual(card.priceLookupKeys, [treatmentKey])

        let genericRecord = PriceRecord(
            key: genericKey,
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        genericRecord.unitMarketPriceUSD = 99
        XCTAssertNil(
            PriceStore.record(
                for: card,
                in: [genericRecord.key: genericRecord]
            )
        )

        let nonfoil = CollectedCard(
            collectionKey: "magic:printing#nonfoil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .nonfoil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        XCTAssertEqual(
            nonfoil.priceKey,
            PriceRecord.key(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.nonfoil.id
            )
        )
    }

    /// A certificate identifies one physical slab, so two of them never stack
    /// even at an identical grade from the same grader.
    func testCertifiedSlabsAreSeparateRows() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedPokemonCard()
        let variant = GradedVariant(
            id: "g-uuid", company: .psa,
            grade: CardGrade(value: "10"),
            marketPriceUSD: 500, updatedAt: nil
        )

        let first = try! store.addGraded(
            underlying: card, variant: variant, certificationNumber: "11111111"
        )
        let second = try! store.addGraded(
            underlying: card, variant: variant, certificationNumber: "22222222"
        )

        XCTAssertTrue(first.didInsert)
        XCTAssertTrue(second.didInsert, "a second certificate is a second slab")
        XCTAssertNotEqual(first.collectionKey, second.collectionKey)

        let firstRow = try XCTUnwrap(store.card(forKey: first.collectionKey))
        let secondRow = try XCTUnwrap(store.card(forKey: second.collectionKey))
        XCTAssertEqual(firstRow.priceKey, secondRow.priceKey, "certificates do not split market identity")
        XCTAssertEqual(firstRow.priceStorageID, "justtcg:v2:g-uuid")
        let prices = try context.fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(prices.count, 1)
        XCTAssertEqual(prices.first?.unitMarketPriceUSD, 500)
        XCTAssertEqual(prices.first?.sourceVariantID, "g-uuid")
    }

    /// Without a certificate the app cannot tell two identical slabs apart, so
    /// they aggregate the way raw copies do.
    func testUncertifiedSlabsAggregate() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedPokemonCard()
        let variant = GradedVariant(
            id: "g-uuid", company: .psa,
            grade: CardGrade(value: "10"),
            marketPriceUSD: 500, updatedAt: nil
        )

        let first = try! store.addGraded(underlying: card, variant: variant, certificationNumber: nil)
        let second = try! store.addGraded(underlying: card, variant: variant, certificationNumber: nil)

        XCTAssertTrue(first.didInsert)
        XCTAssertFalse(second.didInsert, "identical uncertified slabs stack")
        XCTAssertEqual(store.card(forKey: first.collectionKey)?.quantity, 2)
    }

    func testSealedProductsAggregate() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let artwork = try XCTUnwrap(URL(
            string: "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        ))
        let product = SealedProductSummary(
            id: "p-uuid", name: "Legendary Treasures Booster Box",
            setName: "Legendary Treasures", variantID: "v-uuid",
            marketPriceUSD: 18_750, updatedAt: nil, imageURL: artwork
        )

        let first = try! store.addSealed(product, game: .pokemon)
        let second = try! store.addSealed(product, game: .pokemon)

        XCTAssertTrue(first.didInsert)
        XCTAssertFalse(second.didInsert)
        let row = store.card(forKey: first.collectionKey)
        XCTAssertEqual(row?.quantity, 2)
        XCTAssertEqual(row?.itemKind, .sealedProduct)
        XCTAssertEqual(row?.itemKindLabel, "Sealed")
        XCTAssertEqual(row?.priceStorageID, "justtcg:v1:v-uuid")
        XCTAssertEqual(row?.imageURL, artwork.absoluteString)
        let price = try XCTUnwrap(
            PriceStore(context: context).record(forKey: try XCTUnwrap(row?.priceKey))
        )
        XCTAssertEqual(price.unitMarketPriceUSD, 18_750)
        XCTAssertEqual(price.sourceVariantID, "v-uuid")
    }

    func testReaddingSealedProductHealsLegacyMissingArtwork() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let withoutArtwork = SealedProductSummary(
            id: "p-uuid", name: "Legendary Treasures Booster Box",
            setName: "Legendary Treasures", variantID: "v-uuid",
            marketPriceUSD: 18_750, updatedAt: nil, imageURL: nil
        )
        let first = try! store.addSealed(withoutArtwork, game: .pokemon)
        let artwork = try XCTUnwrap(URL(
            string: "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        ))
        let withArtwork = SealedProductSummary(
            id: withoutArtwork.id, name: withoutArtwork.name,
            setName: withoutArtwork.setName, variantID: withoutArtwork.variantID,
            marketPriceUSD: withoutArtwork.marketPriceUSD,
            updatedAt: withoutArtwork.updatedAt, imageURL: artwork
        )

        _ = try! store.addSealed(withArtwork, game: .pokemon)

        XCTAssertEqual(store.card(forKey: first.collectionKey)?.imageURL, artwork.absoluteString)
    }

    func testNullPriceBatchStillBackfillsSealedArtworkAndIdentity() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Legendary Treasures Booster Box",
                setName: "Legendary Treasures", variantID: "v-uuid",
                marketPriceUSD: nil, updatedAt: nil, imageURL: nil
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let hit = try sealedBatchHit(tcgplayerID: "98580", price: nil)
        let owner = marketOwner(for: row)

        PriceRefreshController.applyVendorBatchHit(
            card: hit.card,
            variant: hit.variant,
            owners: [owner],
            store: PriceStore(context: context),
            identities: ProductIdentityStore(context: context),
            rowsByPriceKey: [row.priceKey: [row]],
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            row.imageURL,
            "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        )
        XCTAssertEqual(row.catalogMetadataVersion, CollectionCatalogNormalizer.metadataVersion)
        XCTAssertNil(ArtworkDiagnostics.reason(for: row))
        XCTAssertEqual(
            ProductIdentityStore(context: context).cachedVariantID(forKey: row.priceKey),
            "v-uuid"
        )
        XCTAssertNil(
            PriceStore(context: context).record(forKey: row.priceKey),
            "a null market price stays null while artwork and identity are retained"
        )
    }

    func testProviderWithoutArtworkBecomesTerminalInsteadOfRetryingForever() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Artworkless Box", setName: "Set",
                variantID: "v-uuid", marketPriceUSD: 25,
                updatedAt: nil, imageURL: nil
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let hit = try sealedBatchHit(tcgplayerID: nil, price: 25)

        PriceRefreshController.applyVendorBatchHit(
            card: hit.card,
            variant: hit.variant,
            owners: [marketOwner(for: row)],
            store: PriceStore(context: context),
            identities: ProductIdentityStore(context: context),
            rowsByPriceKey: [row.priceKey: [row]],
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertNil(row.imageURL)
        XCTAssertFalse(ArtworkDiagnostics.shouldRetrySealedArtwork(for: row))
        XCTAssertEqual(ArtworkDiagnostics.reason(for: row), .providerHasNoArtwork)
    }

    func testVendorBatchHitPersistsMarketplaceIdentityForIllustratedRows() throws {
        let context = try makeContext()
        let row = rawCard()
        row.imageURL = "https://example.com/already-illustrated.png"
        context.insert(row)
        try context.save()

        let hit = try sealedBatchHit(tcgplayerID: "98580", price: 25)
        let owner = MarketPriceTarget(
            priceKey: row.priceKey,
            game: row.cardGame,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            itemKind: .rawCard,
            marketVariantID: nil,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil
        )

        PriceRefreshController.applyVendorBatchHit(
            card: hit.card,
            variant: hit.variant,
            owners: [owner],
            store: PriceStore(context: context),
            identities: ProductIdentityStore(context: context),
            rowsByPriceKey: [row.priceKey: [row]],
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(row.tcgplayerProductID, "98580")
        XCTAssertNotNil(
            TCGplayerLinkBuilder.url(for: row),
            "an illustrated row still needs the exact marketplace identity returned by the batch"
        )
    }

    func testExistingSealedRowFromOlderArtworkRulesGetsOneBackfill() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Legacy Box", setName: "Set",
                variantID: "v-uuid", marketPriceUSD: 25,
                updatedAt: nil, imageURL: nil
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        row.catalogMetadataCheckedAt = .now
        row.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion - 1

        XCTAssertTrue(ArtworkDiagnostics.shouldRetrySealedArtwork(for: row))
        XCTAssertEqual(ArtworkDiagnostics.reason(for: row), .lookupPending)
    }

    func testLegacySealedGatewayArtworkIsRepairedLocally() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let legacyURL = try XCTUnwrap(URL(
            string: "https://product-images.tcgplayer.com/fit-in/1000x1000/98580.jpg"
        ))
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Legacy Box", setName: "Set",
                variantID: "v-uuid", marketPriceUSD: 25,
                updatedAt: nil, imageURL: legacyURL
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))

        XCTAssertTrue(CollectionCatalogNormalizer.repairLegacySealedArtworkURLs(in: [row]))
        XCTAssertEqual(
            row.imageURL,
            "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        )
    }

    // MARK: - Set completion

    func testSealedProductsNeverAffectSetCompletion() {
        XCTAssertFalse(CollectionItemKind.sealedProduct.countsTowardSetCompletion)
    }

    /// Owning a raw copy and three grades of one card is still one slot filled.
    func testRawAndGradedOwnershipOfOneCardCountsOnce() {
        let raw = CollectionRow(
            id: "raw", game: .pokemon, name: "Eevee", setCode: "PRE",
            setName: "Prismatic Evolutions", setReleaseOrder: 1, cardNumber: "001",
            variantID: "holo", variantLabel: "Holo", quantity: 1,
            dateAdded: .now, price: .unknown, itemKind: .rawCard, itemKindLabel: "Holo"
        )
        let graded = CollectionRow(
            id: "graded", game: .pokemon, name: "Eevee", setCode: "PRE",
            setName: "Prismatic Evolutions", setReleaseOrder: 1, cardNumber: "001",
            variantID: nil, variantLabel: nil, quantity: 1,
            dateAdded: .now, price: .unknown, itemKind: .gradedCard, itemKindLabel: "PSA 10"
        )
        let sealed = CollectionRow(
            id: "sealed", game: .pokemon, name: "Booster Box", setCode: "",
            setName: "Prismatic Evolutions", setReleaseOrder: 1, cardNumber: "",
            variantID: nil, variantLabel: nil, quantity: 1,
            dateAdded: .now, price: .unknown, itemKind: .sealedProduct, itemKindLabel: "Sealed"
        )

        let slots = Set([raw, graded, sealed].compactMap(\.setCompletionSlot))

        XCTAssertEqual(slots.count, 1, "one card, one slot, however many copies")
        XCTAssertNil(sealed.setCompletionSlot, "a box completes nothing")
    }

    // MARK: - Filtering

    func testItemKindFilterNarrowsToOneKind() {
        let rows = [
            CollectionRow(
                id: "a", game: .pokemon, name: "Eevee", setCode: "PRE", setName: "s",
                setReleaseOrder: 1, cardNumber: "1", variantID: nil, variantLabel: nil,
                quantity: 1, dateAdded: .now, price: .unknown, itemKind: .rawCard
            ),
            CollectionRow(
                id: "b", game: .pokemon, name: "Eevee", setCode: "PRE", setName: "s",
                setReleaseOrder: 1, cardNumber: "1", variantID: nil, variantLabel: nil,
                quantity: 1, dateAdded: .now, price: .unknown, itemKind: .gradedCard
            ),
            CollectionRow(
                id: "c", game: .pokemon, name: "Box", setCode: "", setName: "s",
                setReleaseOrder: 1, cardNumber: "", variantID: nil, variantLabel: nil,
                quantity: 1, dateAdded: .now, price: .unknown, itemKind: .sealedProduct
            )
        ]

        var filters = CollectionFilters.none
        filters.itemKinds = [.gradedCard]
        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).map(\.id), ["b"])

        // Empty means every kind — that is what "All Items" selects.
        filters.itemKinds = []
        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).count, 3)
    }

    // MARK: - Helpers

    private func identifiedPokemonCard() throws -> IdentifiedCard {
        let json = """
        {
          "id": "sv08.5-001", "localId": "001", "name": "Eevee",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } }
        }
        """
        return .pokemon(
            try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)),
            setCode: "PRE"
        )
    }

    private func sealedBatchHit(
        tcgplayerID: String?,
        price: Double?
    ) throws -> (card: JustTCGCard, variant: JustTCGVariant) {
        let marketplace = tcgplayerID.map { "\"tcgplayerId\": \"\($0)\"," } ?? ""
        let amount = price.map { String($0) } ?? "null"
        let json = """
        {
          "data": [ {
            "id": "box", "uuid": "p-uuid", \(marketplace)
            "variants": [ {
              "uuid": "v-uuid", "condition": "Sealed", "price": \(amount)
            } ]
          } ]
        }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self,
            from: Data(json.utf8)
        )
        let card = try XCTUnwrap(response.data.first)
        return (card, try XCTUnwrap(card.variants?.first))
    }

    private func marketOwner(for row: CollectedCard) -> MarketPriceTarget {
        MarketPriceTarget(
            priceKey: row.priceKey,
            game: row.cardGame,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            itemKind: .sealedProduct,
            marketVariantID: row.justTCGVariantID,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil
        )
    }
}
