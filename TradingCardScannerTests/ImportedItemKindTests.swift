import XCTest
import SwiftData
import CryptoKit
import OnePieceCatalogCore
@testable import TradingCardScanner

/// Importing graded slabs and sealed products.
///
/// Both used to be dropped on purpose — correctly, while the app had no way to
/// represent them. Every grade string below is taken verbatim from a real
/// marketplace export.
final class ImportedItemKindTests: XCTestCase {
    func testPortfolioPriceAcceptsSupportedUSDFormatsAndDatedHeader() throws {
        for (cell, amount) in [("0.00", 0.0), ("12.50", 12.5), ("$1,234.56", 1234.56),
                               ("1,234.56", 1234.56), ("0.0042", 0.0042)] {
            let plan = try CollectionCSV.parse(priceCSV(columns: [("Market Price", cell)]))
            XCTAssertEqual(plan.entries.first?.importedMarketPriceUSD, amount, cell)
            XCTAssertEqual(plan.totalQuantity, 2)
        }
        let plan = try CollectionCSV.parse(priceCSV(columns: [("Market Price (As of 2026-10-26)", "$12.50")]))
        let entry = try XCTUnwrap(plan.entries.first)
        XCTAssertEqual(entry.importedMarketPriceUSD, 12.5)
        XCTAssertEqual(entry.importedPriceAsOf, ISO8601DateFormatter().date(from: "2026-10-26T00:00:00Z"))
    }

    func testPortfolioPriceRejectsForeignAndMalformedCellsWithoutDroppingInventory() throws {
        for cell in ["€12.50", "£12.50", "CAD 12.50", "12.50 EUR", "12,50", "1.234,56",
                     "12abc50", "1,23.45", "1,234,56", "-12.50", "NaN", "inf", "1e3", ""] {
            let plan = try CollectionCSV.parse(priceCSV(columns: [("Market Price", cell)]))
            XCTAssertNil(plan.entries.first?.importedMarketPriceUSD, cell)
            XCTAssertNil(plan.entries.first?.importedPriceAsOf, cell)
            XCTAssertEqual(plan.totalQuantity, 2, cell)
            XCTAssertEqual(plan.skippedRows, 0, cell)
        }
        for currency in ["EUR", "CAD", "GBP"] {
            let plan = try CollectionCSV.parse(priceCSV(columns: [("Market Price", "$12.50"), ("Currency", currency)]))
            XCTAssertNil(plan.entries.first?.importedMarketPriceUSD, currency)
        }
        let usd = try CollectionCSV.parse(priceCSV(columns: [("Market Price", "$12.50"), ("Currency", "USD")]))
        XCTAssertEqual(usd.entries.first?.importedMarketPriceUSD, 12.5)
    }

    func testPortfolioPriceRejectsCompetingOrUnsupportedColumnsInEitherOrder() throws {
        for pair in [[("Market Price", "12.50"), ("Market Price EUR", "99.00")],
                     [("Market Price", "12.50"), ("Market Price (As of 2026-10-26)", "99.00")],
                     [("Market Price", "12.50"), ("market-price", "99.00")]] {
            for columns in [pair, Array(pair.reversed())] {
                let plan = try CollectionCSV.parse(priceCSV(columns: columns))
                XCTAssertNil(plan.entries.first?.importedMarketPriceUSD, "\(columns)")
                XCTAssertEqual(plan.totalQuantity, 2)
            }
        }
        for header in ["Market Price EUR", "Market Price Change"] {
            let plan = try CollectionCSV.parse(priceCSV(columns: [(header, "12.50")]))
            XCTAssertNil(plan.entries.first?.importedMarketPriceUSD, header)
        }
    }

    @MainActor
    func testRejectedCSVPricesCannotSeedValuationOrLedgerEvidence() throws {
        for columns in [[("Market Price", "€12.50")], [("Market Price", "12,50")],
                        [("Market Price", "12.50"), ("Market Price EUR", "99.00")],
                        [("Market Price", "12.50"), ("market-price", "99.00")],
                        [("Market Price", "12.50"), ("Currency", "EUR")],
                        [("Market Price", "$1,234.56")]] {
            let plan = try CollectionCSV.parse(priceCSV(columns: columns))
            let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            _ = try CollectionCSV.apply(plan, to: container.mainContext)
            let fresh = ModelContext(container)
            let row = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(row.quantity, 2)
            let accepted = columns.count == 1 && columns[0].1 == "$1,234.56"
            XCTAssertEqual(PriceStore(context: fresh).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD,
                accepted ? 1234.56 : nil)
            let observations = try fresh.fetch(FetchDescriptor<PriceObservation>())
            XCTAssertEqual(observations.count, accepted ? 1 : 0)
            let events = try fresh.fetch(FetchDescriptor<InventoryEvent>())
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.unitPriceUSDTenThousandths, accepted ? 12_345_600 : nil)
            XCTAssertEqual(events.first?.deltaQuantity, 2)
        }
    }

    private func priceCSV(columns: [(String, String)]) -> Data {
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let headers = ["Category", "Set", "Product Name", "Card Number", "Variance", "Grade", "Quantity"] + columns.map(\.0)
        let cells = ["Pokemon", "Synthetic Set", "Synthetic Card", "1", "Normal", "Ungraded", "2"] + columns.map(\.1)
        return Data((headers.map(quoted).joined(separator: ",") + "\n" + cells.map(quoted).joined(separator: ",") + "\n").utf8)
    }


    func testBlankGameCellsRetainFormatDefaultsAndPortfolioAliases() throws {
        let pokemon = "game,provider_id,card_name,quantity\n ,base1-4,Charizard,1\n"
        let magic = "game,scryfall_uuid,name,quantity\n ,fixture-uuid,Lightning Bolt,1\n"
        XCTAssertEqual(try CollectionCSV.parse(Data(pokemon.utf8)).entries.first?.game, .pokemon)
        XCTAssertEqual(try CollectionCSV.parse(Data(magic.utf8)).entries.first?.game, .magic)
        for game in ["", "Magic: The Gathering", "magic"] {
            let csv = "category,game,set,product_name,card_number,rarity,grade,quantity,market_price,watchlist\nMagic: The Gathering,\(game),Alpha,Lightning Bolt,1,Common,Ungraded,1,0,false\n"
            XCTAssertEqual(try CollectionCSV.parse(Data(csv.utf8)).entries.first?.game, .magic, game)
        }
        let unknown = "game,provider_id,card_name,quantity\nfuture-game,fixture,Future Card,1\n"
        XCTAssertEqual(try CollectionCSV.parse(Data(unknown.utf8)).entries.first?.game.rawValue, "future-game")
    }

    @MainActor
    func testOnePieceSourceEvidenceCannotBeBypassedByProviderIDColumnAliases() throws {
        let registry = try retainedOnePieceImportRegistry()
        let printingID = "004fed82-16f2-4176-975d-a1a067277db3"
        let catalog = OnePieceCatalogAdapter(registry: registry)
        let card = try catalog.resolution(forPrintingID: XCTUnwrap(UUID(uuidString: printingID))).card
        XCTAssertEqual(card.cardNumber, "OP13-117")
        XCTAssertEqual(card.variantEvidence.catalogVariants, [.foil])
        let adapter = OnePieceImportAdapter(registry: registry)
        let adapters = try GameImportAdapterRegistry(adapters: [adapter])
        let policy = CardGameRegistry(descriptors: [.init(game: .onePiece, displayName: "One Piece", sortOrder: 0,
            capabilities: [.collectionWrite])])
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        CollectionStore.configureGames(policy, for: container)
        CollectionStore.configureCatalogAdapters(try .init(adapters: [catalog]), legacyCorrectionGames: [], for: container)

        let invalidEvidence: [[(String, String)]] = [
            [("item_kind", "gradedCard")],
            [("item_kind", "sealedProduct")],
            [("item_kind", "future-kind")],
            [("source_identity_conflict", "true")],
            [("grading_company", "PSA"), ("grade", "10")],
            [("certification_number", "fixture-cert")],
            [("justtcg_card_id", "fixture-card")],
            [("justtcg_variant_id", "fixture-variant")],
            [("justtcg_api_version", "v2")],
            [("pokemon_print_run", "unlimited")],
            [("magic_content_kind", "token")],
            [("magic_treatment_ids", "[\"surgefoil\"]")]
        ]
        for idColumn in ["provider_id", "tcgdex_id", "scryfall_uuid"] {
            let columns = [
                ("game", "one-piece"), (idColumn, printingID), ("card_name", card.name),
                ("card_number", "OP13-117"), ("finish", "foil"),
                ("quantity", idColumn == "scryfall_uuid" ? "0" : "1"), ("foil_quantity", "1")
            ]
            for evidence in invalidEvidence {
                let label = idColumn + ":" + evidence.map { $0.0 + "=" + $0.1 }.joined(separator: ",")
                let plan = try CollectionCSV.parse(sourceCSV(columns + evidence))
                let entry = try XCTUnwrap(plan.entries.first, label)
                XCTAssertEqual(plan.entries.count, 1, label)
                XCTAssertThrowsError(try adapter.validate(entry), label)
                let result = try CollectionCSV.apply(plan, to: container.mainContext,
                    gameRegistry: policy, gameImportAdapters: adapters)
                XCTAssertEqual(result.importedQuantity, 0, label)
                XCTAssertEqual(result.failedRows.count, 1, label)
                let fresh = ModelContext(container)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<CollectedCard>()).isEmpty, label)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<CollectionActivity>()).isEmpty, label)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<InventoryEvent>()).isEmpty, label)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<PriceRecord>()).isEmpty, label)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<PriceObservation>()).isEmpty, label)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<ReferenceQuote>()).isEmpty, label)
                XCTAssertTrue(try fresh.fetch(FetchDescriptor<ProductIdentity>()).isEmpty, label)
            }
        }

        // The exact retained raw printing still imports through the formerly
        // unsafe alias; rejecting every scryfall_uuid row would hide the bug.
        let valid = try CollectionCSV.parse(sourceCSV([
            ("game", "one-piece"), ("scryfall_uuid", printingID), ("card_name", card.name),
            ("card_number", "OP13-117"), ("quantity", "0"), ("foil_quantity", "2"),
            ("item_kind", "rawCard"), ("language", "ENG")
        ]))
        XCTAssertNoThrow(try adapter.validate(XCTUnwrap(valid.entries.first)))
        let imported = try CollectionCSV.apply(valid, to: container.mainContext,
            gameRegistry: policy, gameImportAdapters: adapters)
        XCTAssertEqual(imported.importedQuantity, 2)
        XCTAssertTrue(imported.failedRows.isEmpty)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.collectionKey, card.collectionKey(variant: .foil))
        XCTAssertEqual(rows.first?.quantity, 2)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CollectionActivity>()).count, 1)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testEveryCSVFormatRetainsSourceKindLanguageAndConflictEvidence() throws {
        let evidence = [("item_kind", "future-kind"), ("source_language", "ENG"),
                        ("source_identity_conflict", "true")]
        let formats: [[(String, String)]] = [
            [("game", "one-piece"), ("provider_id", "fixture"), ("card_name", "Fixture"), ("quantity", "1")],
            [("game", "one-piece"), ("scryfall_uuid", "fixture"), ("card_name", "Fixture"),
             ("quantity", "1"), ("foil_quantity", "1")],
            [("game", "one-piece"), ("category", "One Piece"), ("set", "Fixture Set"),
             ("product_name", "Fixture"), ("card_number", "OP13-117"), ("grade", "Ungraded"), ("quantity", "1")]
        ]
        for (index, columns) in formats.enumerated() {
            let plan = try CollectionCSV.parse(sourceCSV(columns + evidence))
            XCTAssertEqual(plan.entries.count, index == 1 ? 2 : 1)
            for entry in plan.entries {
                XCTAssertEqual(entry.sourceItemKindRaw, "future-kind")
                XCTAssertEqual(entry.sourceLanguage, "ENG")
                XCTAssertTrue(entry.conflictingSourceIdentity)
            }
        }
    }

    @MainActor
    func testMagicScryfallExportKeepsBothFinishQuantitiesAndTreatments() throws {
        let printingID = "d104b2d6-f8f1-4ae3-88d5-1f86f092e21c"
        let plan = try CollectionCSV.parse(sourceCSV([
            ("scryfall_uuid", printingID), ("name", "Fixture Magic Card"),
            ("set_code", "NEO"), ("collector_number", "1"), ("quantity", "2"), ("foil_quantity", "3"),
            ("magic_treatment_ids", "[\"surgefoil\"]"), ("language", "English")
        ]))
        XCTAssertEqual(plan.entries.count, 2)
        XCTAssertEqual(plan.entries.first { $0.variant == .nonfoil }?.quantity, 2)
        XCTAssertEqual(plan.entries.first { $0.variant == .foil }?.quantity, 3)
        for entry in plan.entries {
            XCTAssertEqual(entry.game, .magic)
            XCTAssertEqual(entry.itemKind, .rawCard)
            XCTAssertEqual(entry.magicTreatmentIDsRaw, entry.variant == .foil ? ["surgefoil"] : [])
            XCTAssertEqual(entry.imageURL, "https://api.scryfall.com/cards/\(printingID)?format=image&version=normal")
        }
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let result = try CollectionCSV.apply(plan, to: container.mainContext)
        XCTAssertEqual(result.importedQuantity, 5)
        XCTAssertTrue(result.failedRows.isEmpty)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.collectionKey)), Set(plan.entries.map(\.collectionKey)))
        XCTAssertEqual(Set(rows.compactMap(\.variantID)), Set(["nonfoil", "foil"]))
    }

    private func sourceCSV(_ columns: [(String, String)]) -> Data {
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return Data((columns.map { quote($0.0) }.joined(separator: ",") + "\n"
            + columns.map { quote($0.1) }.joined(separator: ",") + "\n").utf8)
    }

    private func retainedOnePieceImportRegistry() throws -> OnePieceCatalogRegistry {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("TradingCardScanner/OnePieceOwnerCatalog")
        let decoder = JSONDecoder()
        let pins = try decoder.decode([String: String].self,
            from: Data(contentsOf: directory.appendingPathComponent("public-keys.json")))
        let keys = try pins.mapValues {
            try Curve25519.Signing.PublicKey(rawRepresentation: XCTUnwrap(Data(base64Encoded: $0)))
        }
        let envelope = try decoder.decode(OnePieceCatalogReleaseEnvelope.self,
            from: Data(contentsOf: directory.appendingPathComponent("one-piece-owner-catalog.json")))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        return OnePieceCatalogRegistry(verifiedRelease: try OnePieceCatalogSignature.verify(
            envelope, trustedKeys: keys, now: now))
    }

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

    @MainActor
    func testCSVGradedPrintRunsImportAsSeparateHoldings() throws {
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity,item_kind,grading_company,grade,pokemon_print_run
        pokemon,base1-4,Charizard,Base Set,BS,4,1,gradedCard,psa,10,firstEdition
        pokemon,base1-4,Charizard,Base Set,BS,4,1,gradedCard,psa,10,unlimited
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        XCTAssertEqual(Set(plan.entries.map(\.collectionKey)).count, 2)
        let container = try ProductionRowFixtures.makeContainer()
        _ = try CollectionCSV.apply(plan, to: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).count, 2)
    }

    func testCheckedGradeParsing() {
        for (raw, value, label) in [
            ("PSA 10", Optional("10"), Optional<String>.none),
            ("PSA 10.0", "10", nil),
            ("BGS 9.5", "9.5", nil),
            ("PSA Authentic", nil, "Authentic"),
            ("BGS 10 Black Label", "10", "Black Label")
        ] {
            let parsed = ImportedGradeParser.parse(raw)
            XCTAssertNotNil(parsed, raw)
            XCTAssertEqual(parsed?.grade.value, value, raw)
            XCTAssertEqual(parsed?.grade.label, label, raw)
        }
        for raw in ["PSA inf", "PSA nan", "PSA 1e300"] {
            XCTAssertNil(ImportedGradeParser.parse(raw), raw)
        }
    }

    func testMalformedGradeIsSkippedWithoutDroppingSiblingRows() throws {
        let plan = try CollectionCSV.parse(portfolioCSV([
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,,PSA 10,1,900.00,false",
            "Pokemon,SV: 151,Blastoise ex,200/165,Rare,,PSA 1e300,1,400.00,false",
            "Pokemon,SV: 151,Venusaur ex,198/165,Rare,,BGS 9.5,1,300.00,false"
        ]))
        XCTAssertEqual(plan.entries.count, 2)
        XCTAssertEqual(plan.skippedRows, 1)
        XCTAssertTrue(plan.skippedCSVText?.contains("PSA 1e300") == true)
        XCTAssertEqual(Set(plan.entries.map(\.name)), ["Charizard ex", "Venusaur ex"])
    }

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

    func testZeroPortfolioPriceIsPreservedAsAnExplicitPrice() throws {
        let csv = portfolioCSV([
            "Pokemon,SV: 151,Charizard ex,199/165,Rare,,Ungraded,1,0.00,false"
        ])
        let entry = try XCTUnwrap(try CollectionCSV.parse(csv).entries.first)

        XCTAssertEqual(entry.importedMarketPriceUSD, 0)
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
            "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
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
            "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
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
