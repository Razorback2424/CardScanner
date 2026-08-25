import XCTest
@testable import TradingCardScanner

/// Importing graded slabs and sealed products.
///
/// Both used to be dropped on purpose — correctly, while the app had no way to
/// represent them. Every grade string below is taken verbatim from a real
/// marketplace export.
final class ImportedItemKindTests: XCTestCase {

    // MARK: - Grade parsing

    /// The fourteen graded rows from a live export, in the exporter's own
    /// spelling.
    func testRealExportGradeStrings() {
        let cases: [(String, GradingCompany, String?, String?)] = [
            ("PSA 10.0 GEM - MT", .psa, "10", "GEM - MT"),
            ("PSA 9.0 MINT",      .psa, "9",  "MINT"),
            ("CGC 10.0 Gem Mint", .cgc, "10", "Gem Mint"),
            ("CGC 9.0 Mint",      .cgc, "9",  "Mint"),
            ("CGC 5.0 Excellent", .cgc, "5",  "Excellent"),
            ("CGC 9.5 Mint+",     .cgc, "9.5", "Mint+")
        ]

        for (raw, company, value, label) in cases {
            guard let parsed = ImportedGradeParser.parse(raw) else {
                return XCTFail("failed to parse \(raw)")
            }
            XCTAssertEqual(parsed.company, company, raw)
            XCTAssertEqual(parsed.grade.value, value, raw)
            XCTAssertEqual(parsed.grade.label, label, raw)
        }
    }

    /// `10.0` is a ten. `9.5` is not, and must not round to one — which is why
    /// grades are text.
    func testWholeNumbersLoseTheDecimalAndHalvesDoNot() {
        XCTAssertEqual(ImportedGradeParser.parse("PSA 10.0 GEM - MT")?.grade.value, "10")
        XCTAssertEqual(ImportedGradeParser.parse("CGC 9.5 Mint+")?.grade.value, "9.5")
        XCTAssertEqual(
            ImportedGradeParser.parse("PSA 10.0 GEM - MT")?.grade.display(company: .psa),
            "PSA 10 GEM - MT"
        )
    }

    /// 4,425 of the 4,442 rows say this, and every one is an ordinary card.
    func testUngradedIsNotAGrade() {
        XCTAssertFalse(ImportedGradeParser.isGraded("Ungraded"))
        XCTAssertFalse(ImportedGradeParser.isGraded("ungraded"))
        XCTAssertFalse(ImportedGradeParser.isGraded(""))
        XCTAssertFalse(ImportedGradeParser.isGraded(nil))
        XCTAssertNil(ImportedGradeParser.parse("Ungraded"))

        XCTAssertTrue(ImportedGradeParser.isGraded("PSA 10.0 GEM - MT"))
    }

    /// A grade with no number is a real state, not a parse failure.
    func testAuthenticSlabsHaveNoNumber() {
        guard let parsed = ImportedGradeParser.parse("CGC Authentic") else {
            return XCTFail("Authentic is a grade")
        }
        XCTAssertNil(parsed.grade.value)
        XCTAssertEqual(parsed.grade.label, "Authentic")
        XCTAssertEqual(parsed.grade.display(company: .cgc), "CGC Authentic")
    }

    /// An unrecognised grader is not silently downgraded to a raw card — the
    /// row is skipped so it stays visible in the skipped-rows export.
    func testUnknownGraderDoesNotParse() {
        XCTAssertNil(ImportedGradeParser.parse("WOTC 10"))
        XCTAssertNil(ImportedGradeParser.parse("10"))
        XCTAssertTrue(
            ImportedGradeParser.isGraded("WOTC 10"),
            "still graded, just unreadable — which is why the row is skipped rather than imported raw"
        )
    }

    // MARK: - Import

    private func portfolioCSV(_ rows: [String]) -> Data {
        let header = "Category,Set,Product Name,Card Number,Rarity,Variance,Grade,Quantity,Market Price,Watchlist"
        return Data((([header] + rows).joined(separator: "\n") + "\n").utf8)
    }

    /// A graded Charizard and a raw Charizard are two holdings, and the import
    /// must not merge them into one quantity.
    func testGradedAndRawOfTheSameCardStayApart() throws {
        let csv = portfolioCSV([
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,Holofoil,Ungraded,2,100.00,false",
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,Holofoil,PSA 9.0 MINT,1,400.00,false"
        ])
        let plan = try CollectionCSV.parse(csv)
        let entries = plan.entries

        XCTAssertEqual(entries.count, 2, "a slab is not the raw card")
        XCTAssertEqual(Set(entries.map(\.collectionKey)).count, 2)

        let graded = try XCTUnwrap(entries.first { $0.itemKind == .gradedCard })
        XCTAssertEqual(graded.gradingCompany, .psa)
        XCTAssertEqual(graded.grade?.value, "9")
        XCTAssertTrue(graded.collectionKey.hasPrefix("graded:"))
        // A slab has no raw finish; carrying one would badge it "Holofoil".
        XCTAssertNil(graded.variant)

        let raw = try XCTUnwrap(entries.first { $0.itemKind == .rawCard })
        XCTAssertEqual(raw.quantity, 2)
        XCTAssertEqual(raw.variant, .holo)
    }

    /// Two slabs of one card at different grades are different holdings.
    func testDifferentGradesOfOneCardAreDifferentHoldings() throws {
        let csv = portfolioCSV([
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,,PSA 9.0 MINT,1,400.00,false",
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,,PSA 10.0 GEM - MT,1,900.00,false"
        ])
        let entries = try CollectionCSV.parse(csv).entries

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.collectionKey)).count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.itemKind == .gradedCard })
    }

    /// Sealed products carry no collector number, which is what identifies them
    /// in an export.
    func testSealedProductsImportAsSealed() throws {
        let csv = portfolioCSV([
            "Pokemon,Prismatic Evolutions,Prismatic Evolutions Elite Trainer Box,,,,Ungraded,1,59.99,false",
            "Pokemon,SV: 151,151 Booster Bundle,,,,Ungraded,2,29.99,false"
        ])
        let entries = try CollectionCSV.parse(csv).entries

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.itemKind == .sealedProduct })
        XCTAssertTrue(entries.allSatisfy { $0.collectionKey.hasPrefix("sealed:") })
        // A booster box has no finish at all.
        XCTAssertTrue(entries.allSatisfy { $0.variant == nil })
        XCTAssertEqual(entries.first { $0.name.contains("Bundle") }?.quantity, 2)
    }

    /// The 4,425 ordinary rows must import exactly as they did before.
    func testOrdinaryRowsAreUnaffected() throws {
        let csv = portfolioCSV([
            "Pokemon,Mega Evolution Promos,Bulbasaur,037,Promo,Normal,Ungraded,1,32.11,false",
            "Pokemon,Black Bolt,Victini,012/086,Rare,Reverse Holofoil,Ungraded,3,4.50,false"
        ])
        let entries = try CollectionCSV.parse(csv).entries

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.itemKind == .rawCard })
        for entry in entries {
            XCTAssertFalse(entry.collectionKey.hasPrefix("graded:"))
            XCTAssertFalse(entry.collectionKey.hasPrefix("sealed:"))
        }
        XCTAssertEqual(entries.first { $0.name == "Victini" }?.variant, .reverse)
    }

    /// Imported prices are carried through, so a slab is not blank on arrival
    /// while it waits for a refresh to resolve its market identity.
    func testImportedGradedPriceIsKept() throws {
        let csv = portfolioCSV([
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,,PSA 9.0 MINT,1,400.00,false"
        ])
        let entry = try XCTUnwrap(try CollectionCSV.parse(csv).entries.first)

        XCTAssertEqual(entry.importedMarketPriceUSD, 400.00)
    }

    func testAppExportIdentifiersRoundTripForGradedAndSealedRows() throws {
        let header = [
            "game", "provider_id", "card_name", "set_name", "set_code",
            "card_number", "finish", "finish_name", "quantity", "item_kind",
            "justtcg_card_id", "justtcg_variant_id", "justtcg_api_version",
            "grading_company", "grade", "grade_label", "grading_qualifier",
            "certification_number", "market_region", "image_url"
        ].joined(separator: ",")
        let graded = [
            "pokemon", "base1-4", "Charizard", "Base Set", "BS", "4/102", "", "", "1",
            "gradedCard", "card-v2-uuid", "graded-v2-uuid", "v2", "psa", "10", "Gem Mint",
            "", "12345678", "US", ""
        ].joined(separator: ",")
        let sealed = [
            "pokemon", "sealed:pokemon:old", "Booster Box", "Base Set", "", "", "", "", "1",
            "sealedProduct", "product-v1-uuid", "sealed-v1-uuid", "v1", "", "", "", "", "", "US",
            "https://product-images.tcgplayer.com/fit-in/1000x1000/98580.jpg"
        ].joined(separator: ",")

        let entries = try CollectionCSV.parse(Data("\(header)\n\(graded)\n\(sealed)\n".utf8)).entries
        let slab = try XCTUnwrap(entries.first { $0.itemKind == .gradedCard })
        let box = try XCTUnwrap(entries.first { $0.itemKind == .sealedProduct })

        XCTAssertEqual(slab.justTCGCardID, "card-v2-uuid")
        XCTAssertEqual(slab.justTCGVariantID, "graded-v2-uuid")
        XCTAssertEqual(slab.certificationNumber, "12345678")
        XCTAssertEqual(slab.gradingCompany, .psa)
        XCTAssertEqual(slab.grade?.value, "10")
        XCTAssertTrue(slab.collectionKey.contains("graded-v2-uuid"))
        XCTAssertTrue(slab.collectionKey.contains("12345678"))

        XCTAssertEqual(box.justTCGCardID, "product-v1-uuid")
        XCTAssertEqual(box.justTCGVariantID, "sealed-v1-uuid")
        XCTAssertEqual(
            box.imageURL,
            "https://product-images.tcgplayer.com/fit-in/1000x1000/98580.jpg"
        )
        XCTAssertEqual(
            box.collectionKey,
            CollectedCard.sealedCollectionKey(
                game: .pokemon,
                productUUID: "product-v1-uuid",
                variantUUID: "sealed-v1-uuid"
            )
        )
    }
}
