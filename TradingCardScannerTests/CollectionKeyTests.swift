import XCTest
@testable import TradingCardScanner

/// Covers the join between what a catalog publishes and the row a scan mutates.
final class CollectionKeyTests: XCTestCase {
    private func decodePokemon(variantsJSON: String?) throws -> TCGdexCard {
        let variants = variantsJSON.map { "\"variants\": \($0)," } ?? ""
        let json = """
        {
          "id": "sv08.5-074",
          "localId": "074",
          "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074",
          "rarity": "Common",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          \(variants)
          "pricing": { "tcgplayer": {
            "normal": { "marketPrice": 0.42 },
            "reverse-holofoil": { "marketPrice": 3.75 }
          } }
        }
        """
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    private func decodeMagic() throws -> ScryfallCard {
        let json = """
        {
          "id": "3f0a1f52-0000-4000-8000-000000000001",
          "name": "Llanowar Elves",
          "set": "ecl",
          "set_name": "Eclipse",
          "collector_number": "218",
          "lang": "en",
          "digital": false,
          "frame": "2015",
          "rarity": "common",
          "finishes": ["nonfoil", "foil"],
          "image_uris": {
            "small": "https://cards.example/s.jpg",
            "normal": "https://cards.example/n.jpg"
          }
        }
        """
        return try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
    }

    func testCatalogVariantsComeFromTheCatalogAlone() throws {
        let card = try decodePokemon(
            variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#
        )

        XCTAssertEqual(card.catalogVariants, [.normal, .reverse])
    }

    /// A record that omits variants is a catalog with nothing to say about
    /// finish, not a failed identification.
    func testMissingVariantsBlockDecodesToSilenceRatherThanThrowing() throws {
        let card = try decodePokemon(variantsJSON: nil)

        XCTAssertTrue(card.catalogVariants.isEmpty)
        XCTAssertEqual(
            VariantResolver.resolve(IdentifiedCard.pokemon(card, setCode: "PRE").variantEvidence),
            .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        )
    }

    func testMarketPricesCarryTheVariantTheyBelongTo() throws {
        let card = IdentifiedCard.pokemon(
            try decodePokemon(variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#),
            setCode: "PRE"
        )

        XCTAssertEqual(
            card.marketPrices.map(\.variantID),
            [PhysicalVariant.normal.id, PhysicalVariant.reverse.id]
        )
    }

    /// A Master Ball copy and a plain reverse copy are different physical objects
    /// and must never share a quantity.
    func testVariantsGetSeparateCollectionRows() throws {
        let card = IdentifiedCard.pokemon(
            try decodePokemon(variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#),
            setCode: "PRE"
        )

        XCTAssertNotEqual(
            card.collectionKey(variant: .masterBall),
            card.collectionKey(variant: .reverse)
        )
        XCTAssertEqual(card.collectionKey(variant: .masterBall), "sv08.5-074#masterBall")
    }

    /// Collections built before finish resolution keep incrementing their row.
    func testUnknownVariantKeepsTheLegacyProviderKey() throws {
        let card = IdentifiedCard.pokemon(try decodePokemon(variantsJSON: nil), setCode: "PRE")

        XCTAssertEqual(card.collectionKey(variant: nil), "sv08.5-074")
    }

    func testMagicFinishesBecomePhysicalVariants() throws {
        let card = IdentifiedCard.magic(try decodeMagic())

        XCTAssertEqual(card.variantEvidence.catalogVariants, [.nonfoil, .foil])
        XCTAssertEqual(card.variantEvidence.setID, "ecl")
        XCTAssertEqual(card.collectionKey(variant: .foil), "magic:3f0a1f52-0000-4000-8000-000000000001#foil")
    }

    /// An unfamiliar finish must survive rather than be dropped: silently
    /// discarding one would make a multi-variant printing look unique.
    func testUnknownCatalogFinishIsCarriedThroughVerbatim() {
        let variant = PhysicalVariant.resolving("galaxyFoil")

        XCTAssertEqual(variant.id, "galaxyFoil")
        XCTAssertEqual(
            VariantResolver.resolve(
                VariantEvidence(game: .magic, setID: "ecl", cardNumber: "218", catalogVariants: [.foil, variant])
            ),
            .needsChoice(options: [.foil, variant], lockDidNotApply: nil)
        )
    }

    func testScannedGradedKeysSeparateGradeAndCertificateWithoutRawCollision() {
        let psa10 = CollectedCard.scannedGradedCollectionKey(
            game: .pokemon,
            underlyingPrintingID: "sv08.5-074",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678"
        )
        let psa9 = CollectedCard.scannedGradedCollectionKey(
            game: .pokemon,
            underlyingPrintingID: "sv08.5-074",
            company: .psa,
            grade: CardGrade(value: "9", label: "Mint"),
            certificationNumber: "12345678"
        )
        let secondPsa10 = CollectedCard.scannedGradedCollectionKey(
            game: .pokemon,
            underlyingPrintingID: "sv08.5-074",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "87654321"
        )

        XCTAssertTrue(psa10.hasPrefix("graded:pokemon:sv08.5-074:g:psa-"))
        XCTAssertNotEqual(psa10, psa9)
        XCTAssertNotEqual(psa10, secondPsa10)
        XCTAssertNotEqual(psa10, "sv08.5-074")
    }

    func testUnboundCSVGradedRowsStillReadTheirLegacyProviderPriceKey() {
        let row = CollectedCard(
            collectionKey: "graded:pokemon:sv08.5-074:g:psa-10|Gem Mint",
            game: .pokemon,
            providerID: "sv08.5-074",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: "074",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .catalogSilent
        )
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        row.gradingCompanyRaw = GradingCompany.psa.rawValue
        row.gradeRaw = "10"
        row.gradeLabel = "Gem Mint"

        let legacyKey = PriceRecord.key(
            game: .pokemon,
            printingID: row.providerID,
            variantID: nil
        )
        let record = PriceRecord(
            key: legacyKey,
            game: .pokemon,
            printingID: row.providerID,
            variantID: nil
        )
        record.unitMarketPriceUSD = 42

        XCTAssertEqual(row.priceStorageID, row.collectionKey)
        XCTAssertTrue(row.legacyPriceKeys.contains(legacyKey))
        XCTAssertEqual(
            PriceStore.record(for: row, in: [legacyKey: record])?.effectiveUnitMarketPriceUSD,
            42
        )
    }

    // REQ-004: the identity counterpart uses the same production-shaped row
    // that the CSV and variant-correction tests are required to exercise.
    @MainActor
    func testREQ004CollectionKeyCounterpartUsesProductionShapedGradedRow() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let row = try ProductionRowFixtures.scannedGradedRow(in: container.mainContext)

        XCTAssertEqual(row.providerID, row.collectionKey)
        XCTAssertNotNil(row.catalogProviderID)
        XCTAssertNotEqual(row.catalogProviderID, row.collectionKey)
    }

    // REQ-001: every item kind resolves the underlying printing/product
    // identity without interpreting a collection namespace as that identity.
    @MainActor
    func testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let raw = CollectedCard(
            collectionKey: "sv08.5-074#reverse",
            game: .pokemon,
            providerID: ProductionRowFixtures.pokemonPrintingID,
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: "074",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .reverse,
            variantResolution: .userConfirmed
        )
        let graded = try ProductionRowFixtures.gradedRow(in: context)
        let scannedGraded = try ProductionRowFixtures.scannedGradedRow(in: context)
        let sealed = try ProductionRowFixtures.sealedRow(in: context)

        let directSealedProduct = SealedProductSummary(
            id: "direct-product",
            name: "Direct Product",
            setName: "Prismatic Evolutions",
            variantID: "direct-variant",
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let directSealedMutation = try CollectionStore(context: context).addSealed(
            directSealedProduct,
            game: .pokemon
        )
        let directSealed = try XCTUnwrap(
            CollectionStore(context: context).card(forKey: directSealedMutation.collectionKey)
        )
        XCTAssertNil(directSealed.catalogProviderID)

        XCTAssertEqual(raw.underlyingPrintingID, ProductionRowFixtures.pokemonPrintingID)
        XCTAssertEqual(graded.underlyingPrintingID, ProductionRowFixtures.pokemonPrintingID)
        XCTAssertEqual(scannedGraded.underlyingPrintingID, ProductionRowFixtures.pokemonPrintingID)
        XCTAssertEqual(sealed.underlyingPrintingID, ProductionRowFixtures.pokemonProductID)
        XCTAssertEqual(directSealed.underlyingPrintingID, directSealedProduct.id)

        let underlyingIDs = [
            raw.underlyingPrintingID,
            graded.underlyingPrintingID,
            scannedGraded.underlyingPrintingID,
            sealed.underlyingPrintingID,
            directSealed.underlyingPrintingID
        ]
        XCTAssertTrue(underlyingIDs.allSatisfy { $0 != nil })
        for value in underlyingIDs.compactMap({ $0 }) {
            XCTAssertFalse(value.hasPrefix("graded:"))
            XCTAssertFalse(value.hasPrefix("sealed:"))
        }
    }
}
