import XCTest
@testable import TradingCardScanner

/// Physical-object identity for tokens and art cards.
///
/// Every fixture here is taken from live data: the MSH token faces from
/// Scryfall's TMSH set, the paired product from JustTCG's catalogue, and the
/// three art-card pools from Scryfall's AMSH listing.
final class MagicPhysicalObjectTests: XCTestCase {

    // MARK: - Tokens

    /// Verified against JustTCG: `Merfolk // Doombot Double-Sided Token`,
    /// number `6 // 18`, which matches Scryfall's TMSH face numbers exactly.
    private func mshProducts() -> [MagicPhysicalToken] {
        [
            MagicPhysicalToken(
                frontNumber: "6", backNumber: "18",
                name: "Merfolk // Doombot Double-Sided Token",
                marketProductID: "47655647-e912-52ac-8b9b-2634b5c65104",
                tcgplayerID: "703230"
            ),
            // Clue #17 is the case that motivates the whole design: it is the
            // back of more than one physical token.
            MagicPhysicalToken(
                frontNumber: "4", backNumber: "17",
                name: "Soldier // Clue Double-Sided Token",
                marketProductID: "p-soldier-clue", tcgplayerID: nil
            ),
            MagicPhysicalToken(
                frontNumber: "12", backNumber: "17",
                name: "Insect // Clue Double-Sided Token",
                marketProductID: "p-insect-clue", tcgplayerID: nil
            )
        ]
    }

    /// One face, one product: nothing to ask.
    func testUniqueFaceResolvesWithoutAskingAnything() {
        let index = MagicTokenProductIndex(products: mshProducts())

        guard case let .resolved(product) = index.resolve(faceNumber: "18") else {
            return XCTFail("Doombot #18 appears in exactly one product")
        }
        XCTAssertEqual(product.pairedNumber, "6 // 18")
        XCTAssertEqual(product.tcgplayerID, "703230")
    }

    /// The heart of it. Scanning Clue perfectly still does not say which
    /// physical token it is, and no better OCR could — the pairing is not a
    /// property of the face.
    func testAmbiguousFaceAsksForTheReverseRatherThanGuessing() {
        let index = MagicTokenProductIndex(products: mshProducts())

        guard case let .needsReverse(candidates) = index.resolve(faceNumber: "17") else {
            return XCTFail("Clue #17 is in two products and must not resolve")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(
            Set(candidates.map(\.pairedNumber)),
            ["4 // 17", "12 // 17"]
        )
    }

    /// The reverse is evidence, not a question. Two faces intersect to one
    /// product.
    func testReverseScanResolvesTheExactProduct() {
        let index = MagicTokenProductIndex(products: mshProducts())

        guard case let .resolved(product) = index.resolve(
            faceNumber: "17", reverseNumber: "12"
        ) else {
            return XCTFail("Clue #17 plus Insect #12 is exactly one product")
        }
        XCTAssertEqual(product.pairedNumber, "12 // 17")
    }

    /// The user may present either side first.
    func testScanOrderDoesNotMatter() {
        let index = MagicTokenProductIndex(products: mshProducts())

        let forward = index.resolve(faceNumber: "17", reverseNumber: "4")
        let reversed = index.resolve(faceNumber: "4", reverseNumber: "17")

        XCTAssertEqual(forward, reversed)
        guard case let .resolved(product) = forward else {
            return XCTFail("Expected a resolution")
        }
        XCTAssertEqual(product.pairedNumber, "4 // 17")
    }

    /// Leading zeros are presentation. `0017` and `17` are one face.
    func testLeadingZerosAreNotIdentity() {
        let index = MagicTokenProductIndex(products: mshProducts())

        XCTAssertEqual(
            index.resolve(faceNumber: "0017"),
            index.resolve(faceNumber: "17")
        )
    }

    /// A face the catalogue does not place in any product. The face is still
    /// known — it is the physical object that is not — so this is distinct from
    /// failing to read the card.
    func testUncataloguedFaceIsItsOwnAnswer() {
        let index = MagicTokenProductIndex(products: mshProducts())

        XCTAssertEqual(index.resolve(faceNumber: "99"), .unknownProduct)
        XCTAssertEqual(
            index.resolve(faceNumber: "6", reverseNumber: "17"),
            .unknownProduct,
            "Merfolk and Clue are not printed on the same card"
        )
    }

    /// Two faces that still do not decide it means the same pair exists as more
    /// than one product — a finish difference. Refusing beats pricing a foil as
    /// a nonfoil.
    func testTwoFacesThatStillDoNotDecideStillRefuse() {
        let index = MagicTokenProductIndex(products: [
            MagicPhysicalToken(frontNumber: "6", backNumber: "18", name: "nonfoil",
                               marketProductID: "a", tcgplayerID: nil),
            MagicPhysicalToken(frontNumber: "6", backNumber: "18", name: "foil",
                               marketProductID: "b", tcgplayerID: nil)
        ])

        guard case let .needsReverse(candidates) = index.resolve(
            faceNumber: "6", reverseNumber: "18"
        ) else {
            return XCTFail("two products for one pair must not silently resolve")
        }
        XCTAssertEqual(candidates.count, 2)
    }

    /// Identity is the number, never the name. MSH prints `Soldier` at both #3
    /// and #4, and those pair differently.
    func testFaceIdentityIsTheNumberNotTheName() {
        let three = MagicTokenFace(setCode: "TMSH", number: "3", name: "Soldier")
        let four = MagicTokenFace(setCode: "TMSH", number: "0004", name: "Soldier")

        XCTAssertNotEqual(three, four)
        XCTAssertEqual(four.normalizedNumber, "4")
    }

    // MARK: - Art cards

    /// The three pools, verified against the catalogue: 45 + 12 + 9 = 66, which
    /// is exactly what Scryfall lists for AMSH.
    func testThePrintedFractionNamesThePool() {
        XCTAssertEqual(
            ArtCardNumberParser.parse("02/45")?.collectorNumber, "2",
            "Collector Booster art cards are unsuffixed"
        )
        XCTAssertEqual(
            ArtCardNumberParser.parse("09/12")?.collectorNumber, "9b",
            "Scene Box art cards carry Scryfall's b suffix"
        )
        XCTAssertEqual(
            ArtCardNumberParser.parse("01/09")?.collectorNumber, "1c",
            "Thanos mosaic art cards carry c"
        )
        XCTAssertEqual(
            ArtCardPool.allCases.map(\.printedTotal).reduce(0, +), 66,
            "the three pools account for every AMSH print"
        )
    }

    func testAFractionOutsideItsPoolIsRejected() {
        XCTAssertNil(ArtCardNumberParser.parse("46/45"), "no 46th card in a 45 pool")
        XCTAssertNil(ArtCardNumberParser.parse("00/45"), "there is no card zero")
        XCTAssertNil(ArtCardNumberParser.parse("02/44"), "44 is not a known pool")
        XCTAssertNil(ArtCardNumberParser.parse("17"), "a bare number names no pool")
        XCTAssertNil(ArtCardNumberParser.parse(""))
    }

    /// The mosaic cards are explicitly never stamped, so the choice is not
    /// offered there — asking would invite recording something that does not
    /// exist.
    func testOnlyTheCollectorBoosterPoolCanBeStamped() {
        XCTAssertTrue(ArtCardPool.collectorBooster.supportsGoldStamp)
        XCTAssertFalse(ArtCardPool.mosaic.supportsGoldStamp)
        XCTAssertFalse(ArtCardPool.sceneBox.supportsGoldStamp)
    }

    /// The catalogue carries which stamp exists. The camera only ever confirms
    /// the one it already knows about.
    func testTreatmentsComeFromTheCatalogueNotTheCamera() {
        let stamped = MagicArtCard(
            setCode: "AMSH", collectorNumber: "2", name: "Captain America",
            pool: .collectorBooster, stampedTreatment: .goldSignature,
            marketProductID: "p-regular", stampedMarketProductID: "p-stamped"
        )
        let unstamped = MagicArtCard(
            setCode: "AMSH", collectorNumber: "1c", name: "Thanos",
            pool: .mosaic, stampedTreatment: nil,
            marketProductID: "p-thanos", stampedMarketProductID: nil
        )

        XCTAssertEqual(stamped.availableTreatments, [.normal, .goldSignature])
        XCTAssertEqual(unstamped.availableTreatments, [.normal])

        // Separate market identities: the stamped card is its own product, not a
        // printing of the regular one.
        XCTAssertEqual(stamped.marketProductID(for: .normal), "p-regular")
        XCTAssertEqual(stamped.marketProductID(for: .goldSignature), "p-stamped")
        XCTAssertNotEqual(
            stamped.marketProductID(for: .normal),
            stamped.marketProductID(for: .goldSignature)
        )
    }

    /// Both stamps read as one choice to the user, while staying distinct in
    /// storage — the marketplace lists them as different products.
    func testStampKindsStayDistinctButReadAsOneChoice() {
        XCTAssertNotEqual(ArtCardTreatment.goldSignature, .goldPlaneswalker)
        XCTAssertEqual(ArtCardTreatment.goldSignature.pickerLabel, "Gold stamped")
        XCTAssertEqual(ArtCardTreatment.goldPlaneswalker.pickerLabel, "Gold stamped")
        XCTAssertNotEqual(
            ArtCardTreatment.goldSignature.label,
            ArtCardTreatment.goldPlaneswalker.label
        )
        XCTAssertFalse(ArtCardTreatment.normal.isStamped)
    }
}
