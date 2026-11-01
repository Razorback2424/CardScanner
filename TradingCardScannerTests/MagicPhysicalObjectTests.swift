import XCTest
@testable import TradingCardScanner

/// Physical-object identity for tokens and art cards.
///
/// Token fixtures come from data already in this repository:
/// - MSH: `Merfolk // Doombot` at `6 // 18` is verified against JustTCG and
///   matches Scryfall's TMSH face numbers. The two Clue #17 pairings are the
///   repository's existing MSH fixture.
/// - GRN Guild Kit and Modern Event Deck 2014: TCGplayer's listings in
///   `TestFixtures/TradingCards/SetPricingAudit/magic-product-proof.json`.
/// Coverage claims are asserted by each fixture to exercise the rule; they are
/// not claims about the real sets.
final class MagicPhysicalObjectTests: XCTestCase {

    // MARK: - Token fixtures

    private func face(_ set: String, _ number: String) -> MagicTokenFaceID {
        MagicTokenFaceID(setCode: set, number: number)
    }

    private func card(_ faces: (String, String, String)..., ids: Set<String> = []) -> MagicPhysicalToken {
        MagicPhysicalToken(
            faces: faces.map { MagicTokenFace(setCode: $0.0, number: $0.1, name: $0.2) },
            tcgplayerProductIDs: ids
        )!
    }

    private var merfolkDoombot: MagicPhysicalToken {
        card(("TMSH", "6", "Merfolk"), ("TMSH", "18", "Doombot"), ids: ["703230"])
    }
    private var soldierClue: MagicPhysicalToken {
        card(("TMSH", "4", "Soldier"), ("TMSH", "17", "Clue"))
    }
    private var insectClue: MagicPhysicalToken {
        card(("TMSH", "12", "Insect"), ("TMSH", "17", "Clue"))
    }

    private func mshCatalog(coverage: [String: MagicTokenPairingCoverage] = ["TMSH": .complete]) -> MagicTokenProductCatalog {
        MagicTokenProductCatalog(products: [merfolkDoombot, soldierClue, insectClue], coverage: coverage)
    }

    // MARK: - One face

    /// One face, one card, and the catalog has verified it lists every card
    /// in the set: nothing to ask.
    func testUniqueFaceResolvesWithoutAskingAnything() {
        guard case let .resolved(product) = mshCatalog().resolve(face: face("TMSH", "18")) else {
            return XCTFail("Doombot #18 appears on exactly one card")
        }
        XCTAssertEqual(product.name, "Merfolk // Doombot")
        XCTAssertEqual(product.key.storageKey, "TMSH:6|TMSH:18")
        XCTAssertEqual(product.tcgplayerProductIDs, ["703230"])
    }

    /// Scanning Clue perfectly still does not say which physical token it is,
    /// and no better OCR could. The pairing is not a property of the face.
    func testAmbiguousFaceAsksForTheReverseRatherThanGuessing() {
        let resolution = mshCatalog().resolve(face: face("TMSH", "17"))
        XCTAssertEqual(resolution, .needsReverse(candidates: [soldierClue, insectClue], catalogIsExhaustive: true))
    }

    /// Without a verified coverage claim, a single listing is evidence but not
    /// an answer: the same face may also be on cardboard nobody has listed.
    func testWithoutVerifiedCoverageAUniqueListingIsEvidenceNotAnAnswer() {
        let coverages: [[String: MagicTokenPairingCoverage]] = [[:], ["TMSH": .partial]]
        for coverage in coverages {
            XCTAssertEqual(
                mshCatalog(coverage: coverage).resolve(face: face("TMSH", "18")),
                .needsReverse(candidates: [merfolkDoombot], catalogIsExhaustive: false)
            )
        }
    }

    /// A completeness claim that does not know the face has just been shown
    /// to be wrong for that face.
    func testCompleteCoverageThatDoesNotKnowTheFaceIsNotTrusted() {
        XCTAssertEqual(
            mshCatalog().resolve(face: face("TMSH", "99")),
            .needsReverse(candidates: [], catalogIsExhaustive: false)
        )
    }

    // MARK: - Two faces

    /// The reverse is evidence, not a question. Two faces intersect to one card.
    func testReverseScanResolvesTheExactProduct() {
        XCTAssertEqual(mshCatalog().resolve(face: face("TMSH", "17"), reverse: face("TMSH", "12")),
                       .resolved(insectClue))
    }

    /// The person may present either side first.
    func testScanOrderDoesNotMatter() {
        let catalog = mshCatalog()
        XCTAssertEqual(
            catalog.resolve(face: face("TMSH", "17"), reverse: face("TMSH", "4")),
            catalog.resolve(face: face("TMSH", "4"), reverse: face("TMSH", "17"))
        )
        XCTAssertEqual(catalog.resolve(face: face("TMSH", "4"), reverse: face("TMSH", "17")), .resolved(soldierClue))
    }

    /// Merfolk and Clue are never printed on one card. A complete set can say
    /// so, which means the second face is a different card. An incomplete one
    /// cannot, and only a person can.
    func testFacesNeverPrintedTogetherAreDifferentCardsOnlyWhenCoverageSaysSo() {
        XCTAssertEqual(mshCatalog().resolve(face: face("TMSH", "6"), reverse: face("TMSH", "17")), .differentCards)
        XCTAssertEqual(mshCatalog(coverage: [:]).resolve(face: face("TMSH", "6"), reverse: face("TMSH", "17")),
                       .uncataloguedPair)
    }

    /// Reading the same side twice says nothing about the other side.
    func testSameFaceTwiceIsNotEvidence() {
        XCTAssertEqual(mshCatalog().resolve(face: face("TMSH", "17"), reverse: face("TMSH", "0017")), .sameFace)
    }

    // MARK: - Identity

    /// Leading zeros are presentation and case is OCR noise. A letter prefix
    /// and a suffix are identity.
    func testLeadingZerosAndCaseAreNotIdentity() {
        XCTAssertEqual(face("tmsh", "0017"), face("TMSH", "17"))
        XCTAssertEqual(MagicTokenFaceID.normalize("H013"), "H13")
        XCTAssertEqual(MagicTokenFaceID.normalize("0009b"), "9B")
        XCTAssertEqual(MagicTokenFaceID.normalize("★"), "★")
        XCTAssertNotEqual(face("TLTR", "H13"), face("TLTR", "13"))
    }

    /// Identity is set and number, never the name. MSH prints `Soldier` at both
    /// #3 and #4, and those pair differently.
    func testFaceIdentityIsTheNumberNotTheName() {
        XCTAssertNotEqual(MagicTokenFace(setCode: "TMSH", number: "3", name: "Soldier").id,
                          MagicTokenFace(setCode: "TMSH", number: "0004", name: "Soldier").id)
    }

    /// TCGplayer's RNA Guild Kit listing prints `Ooze // Frog Lizard` at
    /// `9 // 6` and `Dragon // Goblin` at `5 // 6`. Two different faces carry
    /// `6`, so a number-only key would claim those cards share a side. The set
    /// codes here are placeholders; the collision is the listing's.
    func testSetIsPartOfFaceIdentity() {
        let ooze = card(("TAAA", "9", "Ooze"), ("TAAA", "6", "Frog Lizard"))
        let dragon = card(("TBBB", "5", "Dragon"), ("TBBB", "6", "Goblin"))
        let catalog = MagicTokenProductCatalog(products: [ooze, dragon], coverage: ["TAAA": .complete, "TBBB": .complete])

        XCTAssertEqual(catalog.resolve(face: face("TAAA", "6")), .resolved(ooze))
        XCTAssertEqual(catalog.resolve(face: face("TBBB", "6")), .resolved(dragon))
    }

    /// Two listings of one pair are one object. The difference between them is
    /// a finish or packaging fact the finish resolver owns; it must never turn
    /// into a request to flip a card that has already been flipped.
    func testTwoListingsOfOneCardAreOneObject() {
        let nonfoil = card(("TMSH", "6", "Merfolk"), ("TMSH", "18", "Doombot"), ids: ["a"])
        let foil = card(("TMSH", "18", "Doombot"), ("TMSH", "6", "Merfolk"), ids: ["b"])
        let catalog = MagicTokenProductCatalog(products: [nonfoil, foil], coverage: ["TMSH": .complete])

        guard case let .resolved(product) = catalog.resolve(face: face("TMSH", "6"), reverse: face("TMSH", "18")) else {
            return XCTFail("one pair is one card, however many times it is listed")
        }
        XCTAssertEqual(product.tcgplayerProductIDs, ["a", "b"])
        XCTAssertEqual(product.name, "Merfolk // Doombot", "the first listing's display order is kept")
        XCTAssertEqual(catalog.resolve(face: face("TMSH", "18")), .resolved(product))
    }

    /// Amonkhet's `Punchcard // Punchcard` carries one face on both sides. It
    /// is double-sided, and never the same object as a single-sided printing.
    func testIdenticalFacesOnBothSidesIsItsOwnObject() {
        let punchcard = card(("TAKH", "26", "Punchcard"), ("TAKH", "26", "Punchcard"))
        XCTAssertTrue(punchcard.isDoubleFaced)
        XCTAssertNotEqual(punchcard.key, MagicPhysicalTokenKey(faces: [face("TAKH", "26")]))
        XCTAssertEqual(punchcard.reverse(of: face("TAKH", "26"))?.name, "Punchcard")

        let catalog = MagicTokenProductCatalog(products: [punchcard], coverage: ["TAKH": .complete])
        XCTAssertEqual(catalog.resolve(face: face("TAKH", "26")), .resolved(punchcard))
    }

    func testStorageKeyRoundTripsAndIgnoresOrder() {
        let forward = MagicPhysicalTokenKey(faces: [face("TMSH", "6"), face("TMSH", "18")])
        let backward = MagicPhysicalTokenKey(faces: [face("TMSH", "18"), face("TMSH", "6")])
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward?.storageKey, "TMSH:6|TMSH:18", "binder order, not string order")
        XCTAssertEqual(MagicPhysicalTokenKey(storageKey: "TMSH:18|tmsh:0006"), forward)
        XCTAssertEqual(MagicPhysicalTokenKey(storageKey: "TMSH:17")?.isDoubleFaced, false)

        for invalid in ["", "TMSH", "TMSH:1|TMSH:2|TMSH:3", "TMSH:|TMSH:1", ":1", "TMSH:1|"] {
            XCTAssertNil(MagicPhysicalTokenKey(storageKey: invalid), invalid)
        }
        XCTAssertNil(MagicPhysicalTokenKey(faces: []))
    }

    // MARK: - Real multiplicity

    /// TCGplayer's GRN Guild Kit listing prints one Saproling face (#8) against
    /// three different backs. Scryfall's TGK1 confirms #11 is `Voja // Saproling`.
    /// The Selesnya and Golgari faces used here do not collide in that listing;
    /// its Boros and Dimir faces reuse numbers, which
    /// `testOneNumberNamingTwoFacesRefusesTheCatalog` covers.
    func testOneFaceAcrossManyBacks() {
        let voja = card(("TGK1", "8", "Saproling"), ("TGK1", "11", "Voja"), ids: ["179405"])
        let wurm = card(("TGK1", "8", "Saproling"), ("TGK1", "9", "Wurm"), ids: ["179415"])
        let elfKnight = card(("TGK1", "6", "Elf Knight"), ("TGK1", "8", "Saproling"), ids: ["179416"])
        let catalog = MagicTokenProductCatalog(products: [voja, wurm, elfKnight], coverage: ["TGK1": .complete])

        guard case let .needsReverse(candidates, exhaustive) = catalog.resolve(face: face("TGK1", "8")) else {
            return XCTFail("one Saproling face is on three cards")
        }
        XCTAssertTrue(exhaustive)
        XCTAssertEqual(candidates.compactMap { $0.reverse(of: face("TGK1", "8"))?.name }, ["Elf Knight", "Wurm", "Voja"])
        XCTAssertEqual(catalog.resolve(face: face("TGK1", "8"), reverse: face("TGK1", "11")), .resolved(voja))
        XCTAssertEqual(catalog.resolve(face: face("TGK1", "9")), .resolved(wurm))
    }

    /// Modern Event Deck 2014 pairs a planeswalker emblem with a token, and its
    /// Soldier face appears on two cards.
    func testEmblemsPairWithTokens() {
        let emblem = card(("TMD1", "4", "Emblem - Elspeth, Knight-Errant"), ("TMD1", "1", "Soldier"), ids: ["83374"])
        let myr = card(("TMD1", "3", "Myr"), ("TMD1", "2", "Spirit"), ids: ["83376"])
        let soldier = card(("TMD1", "1", "Soldier"), ("TMD1", "2", "Spirit"), ids: ["83377"])
        let catalog = MagicTokenProductCatalog(products: [emblem, myr, soldier], coverage: ["TMD1": .complete])

        XCTAssertEqual(catalog.resolve(face: face("TMD1", "4")), .resolved(emblem))
        XCTAssertEqual(catalog.resolve(face: face("TMD1", "1")),
                       .needsReverse(candidates: [soldier, emblem], catalogIsExhaustive: true))
        XCTAssertEqual(catalog.resolve(face: face("TMD1", "1"), reverse: face("TMD1", "4")), .resolved(emblem))
    }

    // MARK: - Published form

    private func catalogJSON(
        schemaVersion: Int = 1,
        generation: String = "fixture-1",
        sets: String = #"[{"code": "tmsh", "coverage": "complete"}]"#,
        products: String
    ) -> Data {
        Data("""
        {"schemaVersion": \(schemaVersion), "generation": "\(generation)", "sets": \(sets), "products": \(products)}
        """.utf8)
    }

    func testCatalogDecodesFromItsPublishedForm() throws {
        let catalog = try MagicTokenProductCatalog(jsonData: catalogJSON(products: """
        [
          {"faces": [{"set": "TMSH", "number": "0006", "name": "Merfolk"},
                     {"set": "TMSH", "number": "0018", "name": "Doombot"}],
           "tcgplayerProductIDs": ["703230"]},
          {"faces": [{"set": "TMSH", "number": "4", "name": "Soldier"},
                     {"set": "TMSH", "number": "17", "name": "Clue"}]},
          {"faces": [{"set": "TMSH", "number": "12", "name": "Insect"},
                     {"set": "TMSH", "number": "17", "name": "clue"}]}
        ]
        """))

        XCTAssertEqual(catalog.generation, "fixture-1")
        XCTAssertEqual(catalog.resolve(face: face("TMSH", "18")), .resolved(merfolkDoombot))
        XCTAssertEqual(catalog.products(containing: face("TMSH", "17")).count, 2,
                       "a face name differing only in case is the same face")
    }

    /// TCGplayer's GRN Guild Kit listing numbers `Soldier (002) // Goblin` at
    /// `2 // 4` and `Horror // Copy` at `2 // 1`. Read as one numbering space,
    /// #2 is two different faces. A catalog that cannot say what a face is
    /// cannot say what it pairs with, so the whole file is refused.
    func testOneNumberNamingTwoFacesRefusesTheCatalog() {
        let data = catalogJSON(sets: "[]", products: """
        [
          {"faces": [{"set": "TGK1", "number": "2", "name": "Soldier"}, {"set": "TGK1", "number": "4", "name": "Goblin"}]},
          {"faces": [{"set": "TGK1", "number": "2", "name": "Horror"}, {"set": "TGK1", "number": "1", "name": "Copy"}]}
        ]
        """)
        XCTAssertThrowsError(try MagicTokenProductCatalog(jsonData: data)) { error in
            XCTAssertEqual(error as? MagicTokenProductCatalogError, .conflictingFaceNames(face("TGK1", "2")))
        }
    }

    func testMalformedCatalogsAreRefused() {
        let oneFace = #"[{"faces": [{"set": "TMSH", "number": "17", "name": "Clue"}]}]"#
        let cases: [(Data, MagicTokenProductCatalogError)] = [
            (catalogJSON(schemaVersion: 2, products: oneFace), .unsupportedSchemaVersion(2)),
            (catalogJSON(generation: " ", products: oneFace), .missingGeneration),
            (catalogJSON(sets: #"[{"code": "TMSH", "coverage": "complete"}, {"code": "tmsh", "coverage": "partial"}]"#,
                         products: oneFace), .duplicateSetCoverage("TMSH")),
            (catalogJSON(products: "[{\"faces\": []}]"), .invalidProduct(index: 0)),
            (catalogJSON(products: """
            [{"faces": [{"set": "T", "number": "1", "name": "A"}, {"set": "T", "number": "2", "name": "B"},
                        {"set": "T", "number": "3", "name": "C"}]}]
            """), .invalidProduct(index: 0)),
            (catalogJSON(products: #"[{"faces": [{"set": "TMSH", "number": "17", "name": " "}]}]"#),
             .invalidProduct(index: 0)),
            (catalogJSON(products: #"[{"faces": [{"set": "TMSH", "number": "17", "name": "Clue"}], "tcgplayerProductIDs": [""]}]"#),
             .invalidProduct(index: 0))
        ]
        for (data, expected) in cases {
            XCTAssertThrowsError(try MagicTokenProductCatalog(jsonData: data)) { error in
                XCTAssertEqual(error as? MagicTokenProductCatalogError, expected)
            }
        }
    }

    /// Coverage is a reviewed claim. A value the build does not understand is
    /// not quietly read as either answer.
    func testUnknownCoverageValueIsRefused() {
        let data = catalogJSON(sets: #"[{"code": "TMSH", "coverage": "probably"}]"#,
                               products: #"[{"faces": [{"set": "TMSH", "number": "17", "name": "Clue"}]}]"#)
        XCTAssertThrowsError(try MagicTokenProductCatalog(jsonData: data))
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
