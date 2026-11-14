import XCTest
@testable import TradingCardScanner

/// The marketplace link exists so someone can check the price we showed them.
/// A link that occasionally opens the wrong reprint would defeat that entirely,
/// so most of these tests are about what the builder refuses to do.
final class TCGplayerLinkTests: XCTestCase {
    func testOwnedPokemonRetainsTheSameExactPricedProductAsBrowse() throws {
        let identified = try pricedPokemon()
        let row = CollectedCard(card: identified, resolved: .init(variant: .holo, resolution: .userConfirmed))
        XCTAssertEqual(row.tcgplayerProductID, "123456")
        XCTAssertEqual(TCGplayerLinkBuilder.destination(for: row),
                       TCGplayerLinkBuilder.destination(for: identified, variant: .holo))
        row.tcgplayerProductID = nil
        row.tcgplayerURL = nil
        row.applyCatalogMetadata(from: identified)
        XCTAssertEqual(row.tcgplayerProductID, "123456", "Metadata refresh backfills existing holdings")
        row.pokemonPrintRunRaw = PokemonPrintRun.shadowless.rawValue
        row.applyCatalogMetadata(from: identified)
        XCTAssertNil(row.tcgplayerProductID)
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: row))
        row.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        row.applyCatalogMetadata(from: identified)
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: row), "Unlimited product cannot price another print run")
    }

    func testGradedSlabCannotOfferRawMarketplaceProductAsEvidence() throws {
        let identified = try pricedPokemon()
        let raw = CollectedCard(card: identified,
            resolved: .init(variant: .holo, resolution: .userConfirmed))
        XCTAssertNotNil(TCGplayerLinkBuilder.destination(for: raw),
            "Ordinary raw collection product links must remain available")

        raw.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        XCTAssertEqual(raw.tcgplayerProductID, "123456",
            "The underlying raw product is deliberately still stored")
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: raw),
            "Collection and movement details must not advertise a raw product as the graded market")

        let subject = ScanSubject(identifier: .pokemon(setCode: "SVP", cardNumber: "1",
            printedTotal: 2, setDefinition: .init(printedCode: "SVP", tcgdexSetID: "svp",
                officialCount: 2, releaseIndex: 0)))
        let rawScan = ResolvedScan(request: ScanRequest(subject: subject,
            purpose: .priceCheck, generation: 0), card: identified,
            resolved: .init(variant: .holo, resolution: .userConfirmed),
            pokemonPrintRun: nil, options: [])
        XCTAssertNotNil(TCGplayerLinkBuilder.destination(for: rawScan))
        let slabSubject = ScanSubject(identifier: subject.identifier,
            slab: GradedSlabEvidence(company: .psa, grade: CardGrade(value: "10"),
                certificationNumber: "synthetic-cert", labelCardText: [], printedFinish: .holo))
        let slabScan = ResolvedScan(request: ScanRequest(subject: slabSubject,
            purpose: .priceCheck, generation: 0), card: identified,
            resolved: .init(variant: .holo, resolution: .userConfirmed),
            pokemonPrintRun: nil, options: [])
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: slabScan),
            "Price Check must not link the underlying ungraded TCGplayer product")
    }

    func testAmbiguousPokemonMetadataWithdrawsAnOwnedProduct() throws {
        let identified = try pricedPokemon()
        let row = CollectedCard(card: identified, resolved: .init(variant: .holo, resolution: .userConfirmed))
        let conflicting = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"svp-1","localId":"1","name":"Test","set":{"id":"svp","name":"Set","cardCount":{"total":2,"official":2}},"variants_detailed":[{"type":"holo","languages":["en"],"thirdParty":{"tcgplayer":100}},{"type":"holo","languages":["en"],"thirdParty":{"tcgplayer":200}}]}"#.utf8))
        row.applyCatalogMetadata(from: .pokemon(conflicting, setCode: "SVP"))
        XCTAssertNil(row.tcgplayerProductID)
        XCTAssertNil(row.tcgplayerURL)
    }

    private func pricedPokemon() throws -> IdentifiedCard {
        let pokemon = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"svp-1","localId":"1","name":"Test","set":{"id":"svp","name":"Set","cardCount":{"total":2,"official":2}},"variants":{"firstEdition":false,"holo":true,"normal":false,"reverse":false},"pricing":{"tcgplayer":{"holofoil":{"marketPrice":12.5,"productId":123456}}}}"#.utf8))
        return .pokemon(pokemon, setCode: "SVP")
    }

    func testMissingMarketplaceIdentityDoesNotOfferSearch() {
        for game: CardGame in [.pokemon, .magic, .yuGiOh, .lorcana, .onePiece, .init(rawValue: "future-game")] {
            let row = card(game: game, name: "Farfetch’d & Friends / \"Rare\"", variant: .jumbo)
            row.pokemonPrintRunRaw = "shadowless"
            XCTAssertNil(TCGplayerLinkBuilder.destination(for: row))
            XCTAssertNil(row.tcgplayerProductID)
            XCTAssertNil(TCGplayerLinkBuilder.url(for: row))
        }
    }

    func testExactDestinationRetainsVerifiedProductAndRejectsAProviderSearch() throws {
        let row = card(productID: "247241")
        let product = try XCTUnwrap(TCGplayerLinkBuilder.destination(for: row))
        XCTAssertTrue(product.isExactProduct)
        XCTAssertEqual(product.title, "View on TCGplayer")
        XCTAssertEqual(product.url, TCGplayerLinkBuilder.url(for: row))
        let unverified = card(providerURL: "https://www.tcgplayer.com/search/all/product?q=anything")
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: unverified))
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: card(providerURL: "https://evil.example/product/1")))
    }

    func testResolvedCatalogMappingOpensExactProductForSelectedFinish() throws {
        let card = try ResolvedCatalogCard(game: .onePiece, physicalPrintingID: "printing",
            canonicalCardID: "canonical", language: "en", name: "Test", setName: "Set",
            setCode: "OP", cardNumber: "1", printedIdentifier: "1",
            variantEvidence: .init(game: .onePiece, setID: "set", cardNumber: "1",
                catalogVariants: [.normal, .foil]),
            marketProductIDsByVariant: [PhysicalVariant.normal.id: "123", PhysicalVariant.foil.id: "456"])
        XCTAssertEqual(TCGplayerLinkBuilder.destination(for: card, variant: .foil)?.url.path, "/product/456")
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: card, variant: nil))
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: card, variant: .holo))
        let partial = try ResolvedCatalogCard(game: .onePiece, physicalPrintingID: "partial",
            canonicalCardID: "canonical", language: "en", name: "Test", setName: "Set",
            setCode: "OP", cardNumber: "1", printedIdentifier: "1",
            variantEvidence: .init(game: .onePiece, setID: "set", cardNumber: "1",
                catalogVariants: [.normal, .foil]),
            marketProductIDsByVariant: [PhysicalVariant.foil.id: "456"])
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: partial, variant: nil))
    }

    func testCatalogMappingsRequireSupportedFinishAndCompleteAgreementWithoutASelection() throws {
        let shared = try mappedCard([PhysicalVariant.normal.id: "123", PhysicalVariant.foil.id: "123"])
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: shared, variant: nil)?.path, "/product/123")
        XCTAssertNil(TCGplayerLinkBuilder.url(for: shared, variant: .foil, pokemonPrintRun: .firstEdition))
        let unsupported = try mappedCard([PhysicalVariant.holo.id: "456"])
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: unsupported, variant: .holo))
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: try mappedCard([:]), variant: nil))
    }

    func testCatalogWithdrawalClearsStoredURLAndProductID() throws {
        let original = try mappedCard([PhysicalVariant.foil.id: "123"])
        let row = CollectedCard(card: original, resolved: .init(variant: .foil, resolution: .userConfirmed))
        row.tcgplayerProductID = "stale-product"
        row.applyCatalogMetadata(from: original)
        XCTAssertEqual(row.tcgplayerProductID, "123")
        XCTAssertEqual(TCGplayerLinkBuilder.destination(for: row)?.url.path, "/product/123")
        row.applyCatalogMetadata(from: try mappedCard([:]))
        XCTAssertNil(row.tcgplayerProductID)
        XCTAssertNil(row.tcgplayerURL)
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: row))
    }

    func testPokemonConflictingOrIncompleteFinishEvidenceDoesNotChooseFirstProduct() throws {
        for records in [
            #"{"type":"holo","languages":["en"],"thirdParty":{"tcgplayer":100}},{"type":"holo","languages":["en"],"thirdParty":{"tcgplayer":200}}"#,
            #"{"type":"holo","languages":["en"],"thirdParty":{"tcgplayer":100}},{"type":"reverse","languages":["en"]}"#
        ] {
            let pokemon = try JSONDecoder().decode(TCGdexCard.self, from: Data("""
            {"id":"svp-1","localId":"1","name":"Test","set":{"id":"svp","name":"Set","cardCount":{"total":2,"official":2}},"variants_detailed":[\(records)]}
            """.utf8))
            let identified = IdentifiedCard.pokemon(pokemon, setCode: "SVP")
            XCTAssertNil(TCGplayerLinkBuilder.destination(for: identified, variant: nil))
            if records.contains("200") {
                XCTAssertNil(TCGplayerLinkBuilder.destination(for: identified, variant: .holo))
            }
        }
    }

    func testRefreshMetadataReplacesAndWithdrawsObsoleteStoredProductHandles() throws {
        let row = card(game: .onePiece, variant: .foil, productID: "111",
            providerURL: "https://www.tcgplayer.com/product/111")
        for id: String? in ["222", nil] {
            row.applyCatalogMetadata(ImportedCatalogMetadata(providerID: row.providerID,
                setCode: row.setCode, rarity: nil, imageURL: nil, thumbnailURL: nil,
                tcgplayerURL: id.map { "https://www.tcgplayer.com/product/\($0)" },
                setReleaseOrder: 0, tcgplayerProductID: id, updatesMarketplaceProductID: true))
            XCTAssertEqual(row.tcgplayerProductID, id)
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: row)?.url.path, id.map { "/product/\($0)" })
        }
    }

    private func mappedCard(_ mappings: [String: String]) throws -> ResolvedCatalogCard {
        try .init(game: .onePiece, physicalPrintingID: "printing", canonicalCardID: "canonical",
            language: "en", name: "Test", setName: "Set", setCode: "OP", cardNumber: "1", printedIdentifier: "1",
            variantEvidence: .init(game: .onePiece, setID: "set", cardNumber: "1", catalogVariants: [.normal, .foil]),
            marketProductIDsByVariant: mappings)
    }

    private func card(
        game: CardGame = .pokemon,
        name: String = "Umbreon VMAX",
        variant: PhysicalVariant? = .reverse,
        productID: String? = nil,
        skuID: String? = nil,
        providerURL: String? = nil,
        treatmentIDs: [String] = [],
        collectionKey: String = "key"
    ) -> CollectedCard {
        let card = CollectedCard(
            collectionKey: collectionKey,
            game: game,
            providerID: "provider",
            name: name,
            setName: "Evolving Skies",
            setCode: "EVS",
            cardNumber: "215",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed
        )
        card.tcgplayerProductID = productID
        card.tcgplayerSKUID = skuID
        card.tcgplayerURL = providerURL
        card.magicTreatmentIDsRaw = treatmentIDs
        return card
    }

    // MARK: - Exact identity wins

    func testProductIdentityBuildsAProductLinkWithThePrintingPreselected() {
        let url = TCGplayerLinkBuilder.url(for: card(variant: .reverse, productID: "247241"))

        XCTAssertEqual(
            url?.absoluteString,
            "https://www.tcgplayer.com/product/247241?Printing=Reverse%20Holofoil"
        )
    }

    func testMagicProviderURLOpensTheExactPrinting() {
        // Scryfall publishes a per-printing purchase URI, which is already an
        // exact destination; there is nothing to improve on it.
        let exact = "https://www.tcgplayer.com/product/1234567?page=1"
        let url = TCGplayerLinkBuilder.url(
            for: card(game: .magic, variant: .foil, providerURL: exact)
        )

        XCTAssertEqual(url?.absoluteString, exact)
    }

    func testProductIdentityIsPreferredOverTheProviderURL() {
        let url = TCGplayerLinkBuilder.url(
            for: card(
                game: .magic,
                variant: .foil,
                productID: "555",
                providerURL: "https://www.tcgplayer.com/product/999"
            )
        )

        XCTAssertEqual(url?.absoluteString, "https://www.tcgplayer.com/product/555?Printing=Foil")
    }

    func testTreatmentRowOpensItsExactMarketplaceProduct() {
        let exactCardURL = "https://www.tcgplayer.com/product/1234567?page=1"
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(
                for: card(
                    game: .magic,
                    variant: .foil,
                    productID: "1234567",
                    providerURL: exactCardURL,
                    treatmentIDs: ["surgefoil"]
                )
            )?.absoluteString,
            "https://www.tcgplayer.com/product/1234567?Printing=Foil"
        )
    }

    func testTreatmentMarkerInCollectionKeyDoesNotSuppressExactMarketplaceProduct() {
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(
                for: card(
                    game: .magic,
                    variant: .foil,
                    productID: "1234567",
                    collectionKey: "magic:printing#foil#treatment=surgefoil"
                )
            )?.absoluteString,
            "https://www.tcgplayer.com/product/1234567?Printing=Foil"
        )
    }

    func testKnownPrintingsMapToTCGplayersOwnVocabulary() {
        XCTAssertEqual(TCGplayerLinkBuilder.printingName(variantID: PhysicalVariant.normal.id, game: .pokemon), "Normal")
        XCTAssertEqual(TCGplayerLinkBuilder.printingName(variantID: PhysicalVariant.holo.id, game: .pokemon), "Holofoil")
        XCTAssertEqual(TCGplayerLinkBuilder.printingName(variantID: PhysicalVariant.reverse.id, game: .pokemon), "Reverse Holofoil")
        XCTAssertEqual(TCGplayerLinkBuilder.printingName(variantID: PhysicalVariant.nonfoil.id, game: .magic), "Normal")
        XCTAssertEqual(TCGplayerLinkBuilder.printingName(variantID: PhysicalVariant.foil.id, game: .magic), "Foil")
    }

    func testAnUnmappedFinishStillOpensTheRightProductWithoutInventingAPrinting() {
        // A Master Ball parallel has no printing name this app can be sure of.
        // Dropping the filter is right; guessing one is not.
        let masterBall = PhysicalVariant(id: "masterball", label: "Master Ball")
        let url = TCGplayerLinkBuilder.url(for: card(variant: masterBall, productID: "247241"))

        XCTAssertEqual(url?.absoluteString, "https://www.tcgplayer.com/product/247241")
    }

    // MARK: - What it refuses to do

    func testNoMarketplaceIdentityMeansNoLink() {
        // Case 5: the button is hidden rather than guessed at.
        XCTAssertNil(TCGplayerLinkBuilder.url(for: card()))
    }

    func testNameAndSetAreNeverUsedToBuildASearch() {
        // The card has a name, set, set code and collector number — everything
        // a search URL would need — and still produces nothing. A search can
        // land on the wrong reprint, which is worse than no button because it
        // looks authoritative.
        let searchable = card(name: "Charizard", variant: .holo)
        let url = TCGplayerLinkBuilder.url(for: searchable)

        XCTAssertNil(url)
        XCTAssertNil(TCGplayerLinkBuilder.productURL(productID: nil, variantID: PhysicalVariant.holo.id, game: .pokemon))
    }

    func testNonNumericOrEmptyProductIdentityIsRejected() {
        for identity in ["", "  ", "abc", "247241x", "247-241", "0", "000", "١٢٣", "１２３", "-1", "1/2"] {
            XCTAssertNil(
                TCGplayerLinkBuilder.url(for: card(productID: identity)),
                "accepted \(identity)"
            )
        }
    }

    func testProviderURLIsAcceptedOnlyWhenItIsActuallyTCGplayerOverHTTPS() {
        let rejected = [
            "http://www.tcgplayer.com/product/1",   // not https
            "https://tcgplayer.com.evil.example/x", // lookalike host
            "https://www.ebay.com/itm/1",
            "not a url at all",
            "https://www.tcgplayer.com/search/all/product?q=card",
            "https://www.tcgplayer.com/product/0",
            "https://www.tcgplayer.com/product/١٢٣",
            "https://www.tcgplayer.com/product/123abc",
            "https://user:password@www.tcgplayer.com/product/1",
            "https://www.tcgplayer.com:8443/product/1",
            "https://tcgplayer-cdn.tcgplayer.com/product/1",
            ""
        ]
        for raw in rejected {
            XCTAssertNil(TCGplayerLinkBuilder.providerURL(raw), "accepted \(raw)")
        }

        XCTAssertNotNil(TCGplayerLinkBuilder.providerURL("https://tcgplayer.com/product/1"))
        XCTAssertNotNil(TCGplayerLinkBuilder.providerURL("https://www.tcgplayer.com/product/1"))
    }

    func testTheSKUIsPersistedButNeverUsedAsTheDestination() {
        // A SKU is product plus language, printing *and* condition. The
        // collection does not record the condition of the copy owned, so the
        // link must not claim to.
        let owned = card(productID: "247241", skuID: "8675309")
        let url = TCGplayerLinkBuilder.url(for: owned)

        XCTAssertEqual(owned.tcgplayerSKUID, "8675309")
        XCTAssertFalse(url?.absoluteString.contains("8675309") ?? true)
    }

    func testBrowseMagicUsesExactScryfallProductOrPurchaseURL() throws {
        let withID = try browseMagic(tcgplayerID: "12345")
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(for: withID, variant: nil)?.absoluteString,
            "https://www.tcgplayer.com/product/12345"
        )

        let withURL = try browseMagic(tcgplayerID: "null")
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(for: withURL, variant: nil)?.absoluteString,
            "https://www.tcgplayer.com/product/67890"
        )
    }

    func testBrowsePokemonRequiresAnUnambiguousProductWithoutASelectedFinish() throws {
        let pokemon = try browsePokemon()
        let card = IdentifiedCard.pokemon(pokemon, setCode: "SVP")

        XCTAssertEqual(TCGplayerLinkBuilder.url(for: card, variant: .firstEdition)?.path, "/product/102")
        XCTAssertNil(TCGplayerLinkBuilder.url(for: card, variant: .firstEdition, pokemonPrintRun: .unlimited))

        XCTAssertNil(TCGplayerLinkBuilder.url(for: card, variant: nil))
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(for: card, variant: .holo)?.absoluteString,
            "https://www.tcgplayer.com/product/100?Printing=Holofoil"
        )
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(for: card, variant: .reverse)?.absoluteString,
            "https://www.tcgplayer.com/product/101?Printing=Reverse%20Holofoil"
        )
        XCTAssertNil(
            TCGplayerLinkBuilder.url(
                for: card, variant: .holo, pokemonPrintRun: .shadowless
            )
        )
        XCTAssertEqual(
            TCGplayerLinkBuilder.url(
                for: card, variant: .normal, pokemonPrintRun: .firstEdition
            )?.absoluteString,
            "https://www.tcgplayer.com/product/102"
        )
    }

    func testMagicSeparateEtchedProductNeverBorrowsOrdinaryProductOrPurchaseURI() throws {
        func source(_ fields: String) throws -> IdentifiedCard {
            .magic(try JSONDecoder().decode(ScryfallCard.self, from: Data("""
            {"id":"printing", "name":"Test", "set":"tst", "set_name":"Test", "collector_number":"1",
             "lang":"en", "digital":false, "purchase_uris":{"tcgplayer":"https://www.tcgplayer.com/product/100"},
             \(fields)}
            """.utf8)))
        }
        let separate = try source(#""finishes":["nonfoil","foil","etched"],"tcgplayer_id":100,"tcgplayer_etched_id":200"#)
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: separate, variant: .normal)?.path, "/product/100")
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: separate, variant: .etched)?.path, "/product/200")
        XCTAssertNil(TCGplayerLinkBuilder.url(for: separate, variant: nil))
        XCTAssertNil(TCGplayerLinkBuilder.url(for: separate, variant: .reverse))
        let onlyEtched = try source(#""finishes":["etched"],"tcgplayer_id":null,"tcgplayer_etched_id":200"#)
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: onlyEtched, variant: nil)?.path, "/product/200")
        XCTAssertNil(TCGplayerLinkBuilder.url(for: onlyEtched, variant: .foil))
        let shared = try source(#""finishes":["foil","etched"],"tcgplayer_id":100"#)
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: shared, variant: .etched)?.path, "/product/100")
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: shared, variant: nil)?.path, "/product/100")
        let missingOrdinary = try source(#""finishes":["foil","etched"],"tcgplayer_id":null,"tcgplayer_etched_id":200"#)
        XCTAssertNil(TCGplayerLinkBuilder.url(for: missingOrdinary, variant: nil))
        XCTAssertEqual(TCGplayerLinkBuilder.url(for: missingOrdinary, variant: .foil)?.path, "/product/100")
    }

    private func browseMagic(tcgplayerID: String) throws -> IdentifiedCard {
        let json = """
        {
          "id": "printing", "name": "Test Card", "set": "tst",
          "set_name": "Test Set", "collector_number": "1", "lang": "en",
          "digital": false, "tcgplayer_id": \(tcgplayerID),
          "purchase_uris": { "tcgplayer": "https://www.tcgplayer.com/product/67890" }
        }
        """
        return .magic(try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8)))
    }

    private func browsePokemon() throws -> TCGdexCard {
        let json = """
        {
          "id": "svp-1", "localId": "1", "name": "Test Card",
          "set": { "id": "svp", "name": "Test Set",
                   "cardCount": { "total": 2, "official": 2 } },
          "variants_detailed": [
            { "type": "holo", "languages": ["en"],
              "thirdParty": { "tcgplayer": 100 } },
            { "type": "reverse", "languages": ["en"],
              "thirdParty": { "tcgplayer": 101 } },
            { "type": "firstEdition", "languages": ["en"],
              "thirdParty": { "tcgplayer": 102 } }
          ]
        }
        """
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }
}
