import XCTest
@testable import TradingCardScanner

/// The marketplace link exists so someone can check the price we showed them.
/// A link that occasionally opens the wrong reprint would defeat that entirely,
/// so most of these tests are about what the builder refuses to do.
final class TCGplayerLinkTests: XCTestCase {

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
        for identity in ["", "  ", "abc", "247241x", "247-241"] {
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
}
