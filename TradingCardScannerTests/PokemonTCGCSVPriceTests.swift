import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

final class PokemonTCGCSVPriceTests: XCTestCase {
    func testReviewedArtworkCoversAnniversarySetsAndEnergyWithoutNumberGuessing() {
        XCTAssertEqual(PokemonTCGCSVMapping.entries.count, 196)
        for entry in PokemonTCGCSVMapping.entries {
            let source = CatalogCardArtworkSource(game: .pokemon, setCode: entry.setID,
                collectorNumber: "unrelated display number", thumbnailURL: nil, imageURL: nil,
                prefersFullSize: true, limitlessArtworkAuthorized: false,
                providerID: entry.cardID, providerSetID: entry.setID)
            XCTAssertEqual(source.primaryURL?.absoluteString,
                "https://tcgplayer-cdn.tcgplayer.com/product/\(entry.productID)_in_1000x1000.jpg", entry.cardID)
            XCTAssertEqual(source.fallbacks.count, 1)
            let conflicting = CatalogCardArtworkSource(game: .pokemon, setCode: entry.setID,
                collectorNumber: entry.printedNumber, thumbnailURL: nil, imageURL: nil,
                prefersFullSize: true, limitlessArtworkAuthorized: false,
                providerID: entry.cardID, providerSetID: "unrelated-set")
            XCTAssertNil(conflicting.primaryURL)
        }
    }

    @MainActor
    func testStampedHistoryUsesReviewedFinishInsteadOfStoredOriginalProduct() {
        for entry in PokemonStampedReleaseCatalog.entries {
            let card = CollectedCard(collectionKey: "\(entry.providerID)#\(entry.variant.id)", game: .pokemon,
                providerID: entry.providerID, name: "Stamped card", setName: "Original expansion",
                setCode: "", cardNumber: "1", rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: entry.variant, variantResolution: .userConfirmed)
            card.tcgplayerProductID = "original-expansion-product"
            card.justTCGVariantID = "original-expansion-listing"
            card.pokemonPrintRunRaw = PokemonPrintRun.unlimited.rawValue
            let request = CardMarketHistoryRequest(card: card)
            XCTAssertEqual(request.exactProductID, entry.tcgplayerProductID)
            XCTAssertEqual(request.lookups, [.tcgplayerID(entry.tcgplayerProductID)])
            XCTAssertEqual(request.providerPrinting, entry.printing)
            XCTAssertNil(request.marketVariantID)
            XCTAssertEqual(card.tcgplayerProductID, "original-expansion-product", "History never rewrites ownership")
        }
    }

    @MainActor
    func testSavedClassicArtworkSurvivesProjectionAndImportedOwnershipKeys() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let entries = PokemonTCGCSVMapping.entries.filter { $0.setID == "30th-c" }
        for entry in entries {
            let card = CollectedCard(collectionKey: "csv:\(entry.cardID)#holo", game: .pokemon,
                providerID: "csv:\(entry.cardID)", name: entry.productName,
                setName: "30th Classic Collection", setCode: "30C", cardNumber: entry.printedNumber,
                rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .holo,
                variantResolution: .userConfirmed)
            card.catalogProviderID = entry.cardID
            context.insert(card)
            let detail = CatalogCardArtworkSource(collectedCard: card, prefersFullSize: true)
            XCTAssertEqual(detail.primaryURL?.absoluteString,
                "https://tcgplayer-cdn.tcgplayer.com/product/\(entry.productID)_in_1000x1000.jpg")
        }
        try context.save()
        let actor = await CollectionProjectionActor.makeBackground(modelContainer: container)
        let snapshot = await actor.snapshot()
        XCTAssertEqual(snapshot.rows.count, 30)
        for entry in entries {
            let row = try XCTUnwrap(snapshot.rowsByCollectionKey["csv:\(entry.cardID)#holo"])
            XCTAssertEqual(row.catalogProviderID, entry.cardID)
            let grid = CatalogCardArtworkSource(collectionRow: row, prefersFullSize: true)
            XCTAssertEqual(grid.primaryURL?.absoluteString,
                "https://tcgplayer-cdn.tcgplayer.com/product/\(entry.productID)_in_1000x1000.jpg")
        }
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
        saved.catalogProviderID = nil
        saved.providerID = "30th-c-005"
        XCTAssertTrue(CatalogCardArtworkSource(collectedCard: saved, prefersFullSize: true)
            .primaryURL?.absoluteString.contains("716159") == true, "Direct scans need no metadata migration")
        saved.game = CardGame.magic.rawValue
        XCTAssertNil(CatalogCardArtworkSource(collectedCard: saved, prefersFullSize: true).primaryURL)
    }

    @MainActor
    func testAnniversaryHistoryUsesReviewedProductForSavedAndBrowseCards() throws {
        for entry in PokemonTCGCSVMapping.entries where entry.setID != "mee" {
            let card = CollectedCard(collectionKey: "csv:\(entry.cardID)#holo", game: .pokemon,
                providerID: "csv:\(entry.cardID)", name: entry.productName, setName: "30th Classic Collection",
                setCode: "30C", cardNumber: entry.printedNumber, rarity: nil, imageURL: nil,
                thumbnailURL: nil, variant: .holo, variantResolution: .userConfirmed)
            card.catalogProviderID = entry.cardID
            card.tcgplayerProductID = "wrong-old-product"
            card.justTCGVariantID = "stale-old-listing"
            let saved = CardMarketHistoryRequest(card: card)
            let browse = CardMarketHistoryRequest(card: .pokemon(try Self.card(entry.cardID), setCode: "30C"),
                variant: .holo, printRun: nil)
            for request in [saved, browse] {
                XCTAssertEqual(request.lookups, [.tcgplayerID(String(entry.productID))], entry.cardID)
                XCTAssertEqual(request.exactProductID, String(entry.productID))
                XCTAssertEqual(request.providerPrinting, "Holofoil")
                XCTAssertNil(request.marketVariantID)
            }
            card.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
            XCTAssertNil(CardMarketHistoryRequest(card: card).providerPrinting)
            card.pokemonPrintRunRaw = nil
            card.variantID = PhysicalVariant.reverse.id
            XCTAssertNil(CardMarketHistoryRequest(card: card).providerPrinting)
            card.variantID = PhysicalVariant.holo.id
            card.game = CardGame.magic.rawValue
            XCTAssertNil(CardMarketHistoryRequest(card: card).providerPrinting)
        }
    }

    func testMirrorProvenancePreservesCaptureTimeAndRejectsMissingMixedStaleOrFutureMetadata() throws {
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let captured = now.addingTimeInterval(-3_600)
        let raw = Data(#"{"success":true,"errors":[],"results":[]}"#.utf8)
        let stamped = MarketMirrorFixture.stamped(raw, capturedAt: captured)
        let resolved = try TCGCSVPriceMirror.captureDate(products: stamped, prices: stamped, now: now)
        XCTAssertEqual(resolved.timeIntervalSince1970, captured.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertThrowsError(try TCGCSVPriceMirror.captureDate(products: raw, prices: stamped, now: now))
        let mixed = MarketMirrorFixture.stamped(raw, capturedAt: captured, build: "2026-02-01T00:00:00Z")
        XCTAssertThrowsError(try TCGCSVPriceMirror.captureDate(products: mixed, prices: stamped, now: now))
        XCTAssertThrowsError(try TCGCSVPriceMirror.captureDate(products: stamped, prices: stamped,
            expectedBuild: "2026-02-01T00:00:00Z", now: now))
        for date in [now.addingTimeInterval(60), now.addingTimeInterval(-86_400)] {
            let invalid = MarketMirrorFixture.stamped(raw, capturedAt: date)
            XCTAssertThrowsError(try TCGCSVPriceMirror.captureDate(products: invalid, prices: invalid, now: now))
        }
    }

    func testUpstreamAndUnconfiguredEndpointsNeverReachTheNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); TCGCSVTestURLProtocol.server = nil }
        let server = TCGCSVTestServer(routes: [:], now: .now)
        TCGCSVTestURLProtocol.server = server
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TCGCSVTestURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for base in [nil, URL(string: "https://tcgcsv.com"), URL(string: "https://www.tcgcsv.com")] as [URL?] {
            let source = TCGCSVProductPriceSource(baseURL: base, session: session, cacheDirectory: root)
            do {
                _ = try await source.quote(category: 71, group: 1, productID: 1, name: "Fixture", number: "1",
                    lane: "Normal", generation: "fixture", minimumFetchedAt: nil)
                XCTFail("Invalid mirror reached pricing")
            } catch {}
            let pokemon = PokemonTCGCSVPriceService(session: session, baseURL: base, cacheDirectory: root)
            do { _ = try await pokemon.snapshot(setID: "30th"); XCTFail("Invalid mirror reached Pokemon pricing") }
            catch {}
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    private func sourceData(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json")))
    }

    func testReviewedEnergyProductsAndChecklistRegenerationPreserveOldRows() async throws {
        let decoder = JSONDecoder()
        let data = try sourceData("mee-primary")
        struct Primary: Decodable { let set: TCGdexSetCatalog; let cards: [TCGdexCard] }
        let fixture = try decoder.decode(Primary.self, from: data)
        let store = PokemonChecklistStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let loaded = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(loaded)
        let oldEntry = try XCTUnwrap(snapshot.entry(forProviderID: "mee"))
        let old = try XCTUnwrap(snapshot.checklist(for: oldEntry.set.catalogID))
        let built = try XCTUnwrap(PokemonMasterSetChecklistBuilder.build(providerSet: fixture.set,
            baseSet: oldEntry.set, cardDetails: Dictionary(uniqueKeysWithValues: fixture.cards.map { ($0.id, $0) })).first)
        XCTAssertEqual(built.cards.count, 24)
        XCTAssertEqual(built.set.cardCount, 24)
        let original = old.filter { $0.providerID.hasPrefix("mee-") }
        XCTAssertEqual(built.cards.filter { $0.providerID.hasPrefix("mee-") }, original)
        XCTAssertEqual(Set(built.cards.map(\.collectorNumber)).count, 16)
        XCTAssertEqual(built.officialCount, 8, "Provider count is not a printed denominator on Energy")
        let energySnapshot = PokemonChecklistSnapshot.from(builtSets: [built])
        for number in ["005", "013", "015"] {
            XCTAssertTrue(PokemonOfflineCardFactory.candidates(in: energySnapshot,
                number: .init(localID: number, denominator: 8, scheme: .officialSet)).isEmpty,
                "An Energy provider count must never become a printed fraction")
        }
        XCTAssertEqual(PokemonReviewedEnergyCatalog.addingSummaries(built.cards, set: built.set), built.cards)
        let oldPayload = try XCTUnwrap(fixture.cards.first { $0.id == "mee-005" })
        guard case .needsChoice = VariantResolver.resolve(IdentifiedCard.pokemon(oldPayload, setCode: "MEE").variantEvidence) else {
            return XCTFail("Existing Energy Normal/Reverse uncertainty must still ask")
        }

        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: sourceData("mee-reviewed-products")) as? [String: Any])
        let products = try JSONSerialization.data(withJSONObject: records["products"]!)
        let finishes = try XCTUnwrap(records["finishes"] as? [[String: Any]])
        let prices = try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": finishes])
        let quoted = try PokemonTCGCSVPriceService.decodeSnapshot(products: products, prices: prices,
            setID: "mee", feedBuild: "reviewed-fixture", fetchedAt: date)
        XCTAssertTrue(quoted.valuesByCardID.isEmpty, "Recorded finishes contain no prices")
        for entry in PokemonReviewedEnergyCatalog.entries {
            XCTAssertEqual(quoted.quote(cardID: entry.cardID, variant: .holo, printRun: nil), .unavailable(.tcgCSV))
            XCTAssertNil(quoted.quote(cardID: entry.cardID, variant: .normal, printRun: nil))
            XCTAssertEqual(finishes.filter { $0["productId"] as? Int == entry.productID }.map { $0["subTypeName"] as? String }, ["Holofoil"])
        }

        // Opt-in bounded regeneration through the same checklist builder and
        // atomic publisher used for downloaded sets. No other set is fetched.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("MEE-GeneratedChecklist")
        let generated = PokemonChecklistSnapshot.from(builtSets: [built], generatedAt: Date(timeIntervalSince1970: 1_792_368_000))
        let target = PokemonChecklistStore(root: output, bundle: nil)
        try await target.publish(generated)
        let reread = await target.downloadedSnapshot()
        XCTAssertEqual(reread?.checklists[built.set.id], built.cards)
        print("MEE_GENERATED_CHECKLIST=\(output.path)")
    }

    @MainActor
    func testEnergyResolutionAndCollectionExportKeepExactPhysicalIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = PokemonCatalogAdapter(resolvedDiskCache: ResolvedPokemonCardCache(root: root))
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        struct PrimaryCards: Decodable { let cards: [TCGdexCard] }
        let oldPayload = try XCTUnwrap(JSONDecoder().decode(PrimaryCards.self,
            from: sourceData("mee-primary")).cards.first { $0.id == "mee-005" })
        let oldCard = IdentifiedCard.pokemon(oldPayload, setCode: "MEE")
        _ = try CollectionStore(context: context).add(oldCard,
            resolved: .init(variant: .normal, resolution: .userConfirmed), source: .scan)
        let oldKey = oldCard.collectionKey(variant: .normal)
        var keys = Set<String>()
        for (number, product, name) in [("013", 713252, "Basic Psychic Energy"), ("015", 713254, "Basic Darkness Energy")] {
            let identifier = try XCTUnwrap(ScanParser.parsePokemon("MEE EN \(number)"))
            guard case let .resolved(result) = try await adapter.lookup(identifier) else { return XCTFail("Expected exact Energy resolution") }
            let card = result.card
            XCTAssertEqual(card.providerID, "tcgplayer:\(product)")
            XCTAssertEqual(card.name, name)
            XCTAssertEqual(card.cardNumber, number)
            XCTAssertEqual(card.displayCardNumber, number)
            XCTAssertEqual(card.identifier, "MEE \(number)")
            XCTAssertEqual(card.providerPurchaseURL, "https://www.tcgplayer.com/product/\(product)")
            guard case let .resolved(variant) = VariantResolver.resolve(card.variantEvidence) else { return XCTFail("Unique reviewed finish should resolve") }
            XCTAssertEqual(variant.variant, .holo)
            guard case let .pokemon(payload, code) = card.legacyIdentity else { return XCTFail("Expected Pokemon") }
            XCTAssertEqual(code, "MEE")
            XCTAssertEqual(payload.catalogVariants, [.holo])
            XCTAssertEqual(payload.variantsDetailed?.first?.stamp, ["30th-anniversary"])
            XCTAssertTrue(payload.highImageURL?.absoluteString.contains("\(product)_200w.jpg") == true)
            XCTAssertNil(payload.pricing)
            let browseSet = CatalogSet(catalogID: .init(game: .pokemon, providerID: "mee"),
                name: payload.set.name, code: "MEE", logoURL: nil, symbolURL: nil,
                cardCount: 24, releaseDate: nil, sortRank: 0)
            let summary = try XCTUnwrap(PokemonReviewedEnergyCatalog.addingSummaries([], set: browseSet)
                .first { $0.providerID == card.providerID })
            let emptyQuote = PokemonTCGCSVSnapshot(schemaVersion: 1, setID: "mee", feedBuild: "missing",
                fetchedAt: date, validatedAt: date, valuesByCardID: [:])
            let browse = BrowseCatalog(cache: CatalogCacheStore(root: root.appendingPathComponent("browse-\(number)")),
                pokemonTransport: UnavailablePokemonTransport(), tcgCSVSource: RecordedTCGCSV(snapshot: emptyQuote),
                checklistStore: PokemonChecklistStore(root: root.appendingPathComponent("checklists-\(number)")))
            let detail = try await browse.details(for: summary)
            XCTAssertEqual(detail.card.providerID, card.providerID)
            XCTAssertEqual(detail.card.displayImageURL, card.displayImageURL)
            XCTAssertEqual(detail.card.variantEvidence.catalogVariants, [.holo])
            let holding = CollectedCard(card: card, resolved: .init(variant: .holo, resolution: .uniqueInCatalog))
            _ = try CollectionStore(context: context).add(card,
                resolved: .init(variant: .holo, resolution: .uniqueInCatalog), source: .scan)
            keys.insert(holding.collectionKey)
            let plan = try CollectionCSV.parse(Data(CollectionCSV.export([holding]).text.utf8))
            let entry = try XCTUnwrap(plan.entries.first)
            XCTAssertEqual(entry.collectionKey, holding.collectionKey)
            XCTAssertEqual(entry.variant, .holo)
            let refreshed = try await TCGdexService().fetchCard(id: "tcgplayer:\(product)")
            XCTAssertEqual(refreshed.id, card.providerID)
            let nextSession = PokemonCatalogAdapter(resolvedDiskCache: ResolvedPokemonCardCache(root: root))
            guard case let .resolved(repeated) = try await nextSession.lookup(identifier) else { return XCTFail("Expected repeat resolution") }
            XCTAssertEqual(repeated.card.collectionKey(variant: .holo), holding.collectionKey)
        }
        XCTAssertEqual(keys.count, 2)
        let sourceRows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(sourceRows.count, 3)
        XCTAssertTrue(sourceRows.contains { $0.collectionKey == oldKey && $0.providerID == "mee-005" })
        let importContainer = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let roundTrip = try CollectionCSV.parse(Data(CollectionCSV.export(sourceRows).text.utf8))
        _ = try CollectionCSV.apply(roundTrip, to: importContainer.mainContext)
        let importedRows = try importContainer.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(importedRows.map(\.collectionKey)), Set(sourceRows.map(\.collectionKey)))
        XCTAssertNil(PokemonReviewedEnergyCatalog.card(setID: "mee", localID: "005"))
        XCTAssertNil(PokemonReviewedEnergyCatalog.card(setID: "30th", localID: "013"))
        XCTAssertNil(PokemonReviewedEnergyCatalog.card(setID: "mee", localID: "999"))
    }
    private let date = Date(timeIntervalSince1970: 1_790_740_800)

    private func fixtures() throws -> [String: [String: Any]] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TCGCSV30th", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
    }

    private func snapshot(_ setID: String) throws -> PokemonTCGCSVSnapshot {
        let fixture = try XCTUnwrap(fixtures()[setID])
        return try PokemonTCGCSVPriceService.decodeSnapshot(
            products: JSONSerialization.data(withJSONObject: fixture["products"]!),
            prices: JSONSerialization.data(withJSONObject: fixture["prices"]!),
            setID: setID, feedBuild: "2026-09-29T20:05:57+0000", fetchedAt: date
        )
    }

    func testBrowseDetailsRetainSupplementalQuoteAndProvenanceWhenOffline() async throws {
        // Exercise both the fresh cache path and the expired-detail fallback.
        for elapsed in [60 * 60, 25 * 60 * 60] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let cache = CatalogCacheStore(root: root)
            let summary = Self.summary("30th-c-014")
            await cache.storeSets([CatalogSet(catalogID: summary.setID,
                name: "Test Set", code: "30C", logoURL: nil, symbolURL: nil,
                cardCount: 30, releaseDate: nil, sortRank: 1)], for: .pokemon)
            let state = BrowseSupplementState(snapshot: try snapshot("30th-c"))
            let catalog = BrowseCatalog(cache: cache,
                pokemonTransport: BrowseSupplementTransport(card: try Self.card(summary.providerID), state: state),
                tcgCSVSource: BrowseSupplementSource(state: state), now: { state.now })
            let first = try await catalog.details(for: summary)
            let originalQuote = CardPricing.price(for: first.card, variant: .holo, magicTreatments: [])
            guard case .price = originalQuote else { return XCTFail("Expected a supplemental quote") }

            state.goOffline(after: TimeInterval(elapsed))
            let retained = try await catalog.details(for: summary)
            XCTAssertEqual(retained.retrievedAt, first.retrievedAt)
            XCTAssertEqual(retained.card.marketPrices, first.card.marketPrices)
            XCTAssertEqual(CardPricing.price(for: retained.card, variant: .holo, magicTreatments: []), originalQuote)

            // A successful missing quote must replace the old positive result.
            let empty = PokemonTCGCSVSnapshot(schemaVersion: 1, setID: "30th-c", feedBuild: "empty",
                fetchedAt: state.now, validatedAt: state.now, valuesByCardID: [:])
            state.recover(with: empty)
            let updated = try await catalog.details(for: summary)
            XCTAssertTrue(updated.card.marketPrices.allSatisfy(\.isGap))
        }
    }

    func testAll188MappingsJoinExactProductsAndHolofoilPrices() throws {
        XCTAssertEqual(PokemonTCGCSVMapping.entries.count, 196)
        XCTAssertEqual(Set(PokemonTCGCSVMapping.entries.map(\.cardID)).count, 196)
        XCTAssertEqual(Set(PokemonTCGCSVMapping.entries.map(\.productID)).count, 196)
        for (setID, count) in [("30th", 158), ("30th-c", 30)] {
            let value = try snapshot(setID)
            XCTAssertEqual(value.valuesByCardID.count, count)
            XCTAssertTrue(value.valuesByCardID.keys.allSatisfy { PokemonTCGCSVMapping.byCardID[$0]?.setID == setID })
        }
    }

    func testClassicRepeatedNumeratorsKeepDifferentProductIdentities() throws {
        let value = try snapshot("30th-c")
        for id in ["30th-c-003", "30th-c-004", "30th-c-022", "30th-c-023", "30th-c-024"] {
            XCTAssertNotNil(value.valuesByCardID[id])
        }
        XCTAssertEqual(PokemonTCGCSVMapping.byCardID["30th-c-014"]?.productID, 716194)
        XCTAssertEqual(PokemonTCGCSVMapping.byCardID["30th-c-022"]?.printedNumber, "106/106")
        XCTAssertEqual(PokemonTCGCSVMapping.byCardID["30th-c-023"]?.printedNumber, "106/160")
    }

    func testQuoteNeverBorrowsHoloPriceForAnotherFinishOrPrinting() throws {
        let value = try snapshot("30th-c")
        for variant in [PhysicalVariant.normal, .reverse, .firstEdition, .masterBall] {
            XCTAssertNil(value.quote(cardID: "30th-c-014", variant: variant, printRun: nil))
        }
        XCTAssertNil(value.quote(cardID: "base1-58", variant: .holo, printRun: nil))
        XCTAssertNil(value.quote(cardID: "30th-c-014", variant: .holo, printRun: .shadowless))
        guard case let .price(price)? = value.quote(cardID: "30th-c-014", variant: .holo, printRun: nil) else {
            return XCTFail("Expected the exact Classic Holofoil quote")
        }
        XCTAssertEqual(price.source, .tcgCSV)
        XCTAssertNil(price.sourceUpdatedAt)
        XCTAssertEqual(price.fetchedAt, date)
        XCTAssertFalse(price.source.publishesSourceTimestamp)
    }

    func testWrongGroupNumberNameOrDuplicateProductFailsClosed() throws {
        let fixture = try XCTUnwrap(fixtures()["30th-c"])
        for change in 0..<4 {
            var products = fixture["products"] as! [String: Any]
            var rows = products["results"] as! [[String: Any]]
            switch change {
            case 0: rows[0]["groupId"] = 24722
            case 1: rows[0]["extendedData"] = [["name": "Number", "value": "4/103"]]
            case 2: rows[0]["name"] = "Unrelated Charizard"
            default: rows.append(rows[0])
            }
            products["results"] = rows
            XCTAssertThrowsError(try PokemonTCGCSVPriceService.decodeSnapshot(
                products: JSONSerialization.data(withJSONObject: products),
                prices: JSONSerialization.data(withJSONObject: fixture["prices"]!),
                setID: "30th-c", feedBuild: "build", fetchedAt: date
            ))
        }
    }

    func testNullMissingDuplicateAndNegativeMarkets() throws {
        let fixture = try XCTUnwrap(fixtures()["30th-c"])
        let products = try JSONSerialization.data(withJSONObject: fixture["products"]!)
        for change in 0..<4 {
            var prices = fixture["prices"] as! [String: Any]
            var rows = prices["results"] as! [[String: Any]]
            let index = try XCTUnwrap(rows.firstIndex { $0["productId"] as? Int == 716194 })
            switch change {
            case 0: rows[index]["marketPrice"] = NSNull()
            case 1: rows.remove(at: index)
            case 2: rows.append(rows[index])
            default: rows[index]["marketPrice"] = -1
            }
            prices["results"] = rows
            let data = try JSONSerialization.data(withJSONObject: prices)
            if change < 2 {
                let result = try PokemonTCGCSVPriceService.decodeSnapshot(
                    products: products, prices: data, setID: "30th-c", feedBuild: "build", fetchedAt: date
                )
                XCTAssertEqual(result.quote(cardID: "30th-c-014", variant: .holo, printRun: nil), .unavailable(.tcgCSV))
                XCTAssertEqual(result.valuesByCardID.count, 29)
            } else {
                XCTAssertThrowsError(try PokemonTCGCSVPriceService.decodeSnapshot(
                    products: products, prices: data, setID: "30th-c", feedBuild: "build", fetchedAt: date
                ))
            }
        }
    }

    func testPriceResponseRejectsDeclaredRowCountMismatches() throws {
        let fixture = try XCTUnwrap(fixtures()["30th-c"])
        let products = try JSONSerialization.data(withJSONObject: fixture["products"]!)
        let originalRows = (fixture["prices"] as! [String: Any])["results"] as! [[String: Any]]
        for declaredCount in [originalRows.count, originalRows.count - 2] {
            var prices = fixture["prices"] as! [String: Any]
            prices["results"] = originalRows.filter { $0["productId"] as? Int != 716194 }
            prices["totalItems"] = declaredCount

            XCTAssertThrowsError(try PokemonTCGCSVPriceService.decodeSnapshot(
                products: products, prices: JSONSerialization.data(withJSONObject: prices),
                setID: "30th-c", feedBuild: "build", fetchedAt: date
            )) { error in
                guard case PokemonTCGCSVError.invalidResponse = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testCompletePriceResponseWithDeclaredRowCountIsAccepted() throws {
        let fixture = try XCTUnwrap(fixtures()["30th-c"])
        var prices = fixture["prices"] as! [String: Any]
        prices["totalItems"] = (prices["results"] as! [[String: Any]]).count
        let result = try PokemonTCGCSVPriceService.decodeSnapshot(
            products: JSONSerialization.data(withJSONObject: fixture["products"]!),
            prices: JSONSerialization.data(withJSONObject: prices),
            setID: "30th-c", feedBuild: "build", fetchedAt: date
        )

        XCTAssertEqual(result.valuesByCardID.count, 30)
        XCTAssertNotNil(result.valuesByCardID["30th-c-014"])
    }

    func testPartialPriceFeedIsNotCachedAndExplicitRetryCanRecover() async throws {
        let validServer = try server()
        var routes = validServer.routes
        let pricePath = "/tcgplayer/3/24837/prices"
        var prices = try XCTUnwrap(JSONSerialization.jsonObject(with: routes[pricePath]!) as? [String: Any])
        let rows = prices["results"] as! [[String: Any]]
        prices["totalItems"] = rows.count
        prices["results"] = rows.filter { $0["productId"] as? Int != 716194 }
        routes[pricePath] = try JSONSerialization.data(withJSONObject: prices)
        let partialServer = TCGCSVTestServer(routes: routes, now: date)
        TCGCSVTestURLProtocol.server = partialServer
        defer { TCGCSVTestURLProtocol.server = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = makeService(server: partialServer, root: root)

        do {
            _ = try await service.snapshot(setID: "30th-c", retry: false)
            XCTFail("A partial feed must fail instead of confirming a missing price")
        } catch {
            guard case PokemonTCGCSVError.invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("30th-c.json").path))

        TCGCSVTestURLProtocol.server = validServer
        let recovered = try await service.snapshot(setID: "30th-c", retry: true)
        XCTAssertEqual(recovered.valuesByCardID.count, 30)
        XCTAssertNotNil(recovered.valuesByCardID["30th-c-014"])
    }

    func testReviewedFinishEvidenceCorrectsGeneratedNormalOnlyForMappedCards() throws {
        for id in ["30th-053", "30th-c-014"] {
            let card = try Self.card(id)
            XCTAssertEqual(card.catalogVariants, [.holo])
            XCTAssertEqual(VariantResolver.resolve(IdentifiedCard.pokemon(card, setCode: "30C").variantEvidence),
                           .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
        }
        XCTAssertEqual(try Self.card("other-053").catalogVariants, [.normal])
    }

    func testSupplementalPricesAppearInPureCardPricingAndPublishedPricePanel() throws {
        var card = try Self.card("30th-c-014")
        card.supplementalTCGCSV = try snapshot("30th-c")
        let identified = IdentifiedCard.pokemon(card, setCode: "30C")
        guard case .price = CardPricing.price(for: identified, variant: .holo, magicTreatments: []) else {
            return XCTFail("Expected the supplemental card detail price")
        }
        XCTAssertEqual(CardPricing.publishedPrices(for: identified).count, 1)
        XCTAssertFalse(CardPricing.publishedPrices(for: identified)[0].isGap)
        XCTAssertEqual(CardPricing.price(for: identified, variant: .normal, magicTreatments: []), .unavailable(.tcgplayer))
    }

    func testExistingUSDQuoteWinsOverSupplementalQuote() throws {
        var card = try Self.card("30th-c-014", priced: true)
        card.supplementalTCGCSV = try snapshot("30th-c")
        let lookup = CardPricing.price(for: .pokemon(card, setCode: "30C"), variant: .holo, magicTreatments: [])
        guard case let .price(price) = lookup else { return XCTFail("Expected catalog quote") }
        XCTAssertEqual(price.unitMarketPriceUSD, 123)
        XCTAssertEqual(price.source, .tcgplayer)
    }

    @MainActor
    func testCachedQuoteFillsLaterCatalogMissWithoutRestampingRetrievalOrHistory() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let store = PriceStore(context: context)
        let cached = try snapshot("30th-c")
        let quote = try XCTUnwrap(cached.quote(cardID: "30th-c-014", variant: .holo, printRun: nil))
        let missAt = cached.fetchedAt.addingTimeInterval(60)
        XCTAssertTrue(store.store(.unavailable(.tcgplayer), game: .pokemon,
                                  printingID: "30th-c-014", variantID: "holo", at: missAt))
        XCTAssertTrue(store.save())
        XCTAssertTrue(store.store(quote, game: .pokemon, printingID: "30th-c-014",
                                  variantID: "holo", at: missAt.addingTimeInterval(1)))
        XCTAssertTrue(store.save())
        let record = try XCTUnwrap(store.record(forKey: "pokemon:30th-c-014:holo"))
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, cached.valuesByCardID["30th-c-014"])
        XCTAssertEqual(record.source, .tcgCSV)
        XCTAssertEqual(record.fetchedAt, cached.fetchedAt)
        XCTAssertNil(record.sourceUpdatedAt)
        let observations = try context.fetch(FetchDescriptor<PriceObservation>())
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations.first?.receivedAt, cached.fetchedAt)
    }

    @MainActor
    func testCachedQuoteCannotReplaceNewerAmountOrReviveInvalidatedValue() throws {
        for invalidate in [false, true] {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                              configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let context = container.mainContext
            let store = PriceStore(context: context)
            let cached = try snapshot("30th-c")
            let quote = try XCTUnwrap(cached.quote(cardID: "30th-c-014", variant: .holo, printRun: nil))
            let newerAt = cached.fetchedAt.addingTimeInterval(60)
            let key = PriceRecord.key(game: .pokemon, printingID: "30th-c-014", variantID: "holo")
            XCTAssertTrue(store.store(.price(NormalizedPrice(
                unitMarketPriceUSD: 123, currencyCode: "USD", source: .tcgplayer,
                sourceVariantID: "holofoil", sourceUpdatedAt: nil, fetchedAt: newerAt
            )), game: .pokemon, printingID: "30th-c-014", variantID: "holo", at: newerAt))
            if invalidate {
                XCTAssertNotNil(PriceObservationLog(context: context).recordInvalidation(
                    instrumentKey: key, source: .tcgplayer, at: newerAt.addingTimeInterval(1)
                ))
            }
            XCTAssertTrue(store.save())
            let observationCount = try context.fetch(FetchDescriptor<PriceObservation>()).count
            let accepted = store.store(quote, game: .pokemon, printingID: "30th-c-014",
                                       variantID: "holo", at: newerAt.addingTimeInterval(2))
            XCTAssertEqual(accepted, !invalidate)
            let record = try XCTUnwrap(store.record(forKey: key))
            XCTAssertEqual(record.effectiveUnitMarketPriceUSD, invalidate ? nil : 123)
            XCTAssertEqual(record.isInvalidated, invalidate)
            XCTAssertEqual(record.fetchedAt, newerAt)
            XCTAssertEqual(try context.fetch(FetchDescriptor<PriceObservation>()).count, observationCount)
        }
    }

    func testDailyCacheCoalescesCallersAndSurvivesServiceRecreation() async throws {
        let server = try server()
        TCGCSVTestURLProtocol.server = server
        defer { TCGCSVTestURLProtocol.server = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = makeService(server: server, root: root)
        async let first = service.snapshot(setID: "30th-c", retry: false)
        async let second = service.snapshot(setID: "30th-c", retry: false)
        let values = try await (first, second)
        XCTAssertEqual(values.0.valuesByCardID, values.1.valuesByCardID)
        XCTAssertEqual(server.requests.count, 3)
        _ = try await makeService(server: server, root: root).snapshot(setID: "30th-c", retry: false)
        XCTAssertEqual(server.requests.count, 3)
        XCTAssertTrue(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.contains("ScanStash") == true })
    }

    func testUnchangedBuildRevalidatesWithoutRedownloadingOrRestampingQuote() async throws {
        let server = try server()
        TCGCSVTestURLProtocol.server = server
        defer { TCGCSVTestURLProtocol.server = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = makeService(server: server, root: root)
        let original = try await service.snapshot(setID: "30th", retry: false)
        server.advance(25 * 60 * 60)
        let validated = try await service.snapshot(setID: "30th", retry: false)
        XCTAssertEqual(server.requests.count, 4)
        XCTAssertEqual(validated.fetchedAt, original.fetchedAt)
        XCTAssertGreaterThan(validated.validatedAt, original.validatedAt)
    }

    func testCancellingOneWaiterDoesNotCancelSharedDownload() async throws {
        let server = try server()
        server.delay = 0.15
        TCGCSVTestURLProtocol.server = server
        defer { TCGCSVTestURLProtocol.server = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = makeService(server: server, root: root)
        let first = Task { try await service.snapshot(setID: "30th-c", retry: false) }
        for _ in 0..<100 where server.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let second = Task { try await service.snapshot(setID: "30th-c", retry: false) }
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let result = try await second.value
        XCTAssertEqual(result.valuesByCardID.count, 30)
        XCTAssertEqual(server.requests.count, 3)
    }

    func testFailureBackoffAndExplicitRetryPreservePriorSnapshot() async throws {
        let server = try server()
        TCGCSVTestURLProtocol.server = server
        defer { TCGCSVTestURLProtocol.server = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = makeService(server: server, root: root)
        let first = try await service.snapshot(setID: "30th-c", retry: false)
        server.advance(25 * 60 * 60)
        server.fail = true
        do { _ = try await service.snapshot(setID: "30th-c", retry: false); XCTFail("Expected failure") } catch {}
        let requestCount = server.requests.count
        do { _ = try await service.snapshot(setID: "30th-c", retry: false); XCTFail("Expected backoff") } catch {}
        XCTAssertEqual(server.requests.count, requestCount)
        server.fail = false
        let restored = try await service.snapshot(setID: "30th-c", retry: true)
        XCTAssertEqual(restored.valuesByCardID, first.valuesByCardID)
        XCTAssertEqual(restored.fetchedAt, first.fetchedAt)
    }

    @MainActor
    func testInteractiveFallbackWorksWithPaidFallbackDisabled() async throws {
        let old = UserDefaults.standard.object(forKey: "usesPriceFallback")
        UserDefaults.standard.set(false, forKey: "usesPriceFallback")
        defer { UserDefaults.standard.set(old, forKey: "usesPriceFallback") }
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let resolver = PriceFallbackQuoteResolver(context: container.mainContext,
                                                  tcgCSVSource: RecordedTCGCSV(snapshot: try snapshot("30th-c")))
        let result = await resolver.resolve(card: .pokemon(try Self.card("30th-c-014"), setCode: "30C"),
                                            variant: .holo, pokemonPrintRun: nil)
        guard case let .lookup(.price(price)) = result else { return XCTFail("Expected free exact-product quote") }
        XCTAssertEqual(price.source, .tcgCSV)
    }

    func testQuoteRefreshStillPricesKnownIdentityDuringCatalogOutage() async throws {
        let service = PriceQuoteService(tcgCSVSource: RecordedTCGCSV(snapshot: try snapshot("30th-c")),
                                       catalogRefreshOverride: { _, _, _ in throw URLError(.notConnectedToInternet) })
        let result = try await service.refresh(card: .pokemon(try Self.card("30th-c-014"), setCode: "30C"),
                                               variant: .holo, pokemonPrintRun: nil)
        guard case let .price(price) = result else { return XCTFail("Expected exact fallback quote") }
        XCTAssertEqual(price.source, .tcgCSV)
    }

    func testQuoteRefreshPropagatesCancellationAndIdentityMismatch() async throws {
        for error in [PriceQuoteError.identityMismatch, .providerUnavailable] {
            let service = PriceQuoteService(tcgCSVSource: RecordedTCGCSV(snapshot: try snapshot("30th-c")),
                                           catalogRefreshOverride: { _, _, _ in
                if case .identityMismatch = error { throw error }
                throw CancellationError()
            })
            do {
                _ = try await service.refresh(card: .pokemon(try Self.card("30th-c-014"), setCode: "30C"),
                                              variant: .holo, pokemonPrintRun: nil)
                XCTFail("Expected failure")
            } catch {}
        }
    }

    func testReviewedFinishRepairPreservesUserConfirmedChoices() throws {
        let card = IdentifiedCard.pokemon(try Self.card("30th-c-014"), setCode: "30C")
        XCTAssertEqual(PokemonFinishReconciliation.repair(
            storedVariantID: "normal", storedResolution: .uniqueInCatalog,
            itemKind: .rawCard, printRun: nil, card: card
        )?.variant, .holo)
        XCTAssertNil(PokemonFinishReconciliation.repair(
            storedVariantID: "normal", storedResolution: .userConfirmed,
            itemKind: .rawCard, printRun: nil, card: card
        ))
    }

    func testRecentLegacyMissDoesNotDelayNewSourceButTCGCSVMissKeepsNormalRetryInterval() {
        var target = PriceTarget(
            game: .pokemon, printingID: "30th-c-014", catalogPrintingID: "30th-c-014",
            setCode: "30C", variantID: "holo", importedIdentity: nil,
            catalogMetadataCheckedAt: nil, lastFailureAt: nil, hasPrice: false, lastCheckedAt: .now
        )
        target.lastPriceSource = .tcgplayer
        XCTAssertEqual(PriceRefreshController.staleTargets(from: [target], usesPriceFallback: false).count, 1)
        target.lastPriceSource = .tcgCSV
        XCTAssertTrue(PriceRefreshController.staleTargets(from: [target], usesPriceFallback: false).isEmpty)
    }

    func testBrowseBulkPricingDoesNotNeedCatalogOrLegacySetMatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = CatalogCacheStore(root: root)
        await cache.storePokemonBulkSetMatch(PokemonBulkSetMatch(secondarySetID: nil), for: "30th-c")
        let catalog = BrowseCatalog(cache: cache, pokemonTransport: UnavailablePokemonTransport(),
                                    tcgCSVSource: RecordedTCGCSV(snapshot: try snapshot("30th-c")))
        let summary = Self.summary("30th-c-014")
        var last: CatalogPriceUpdate?
        for await update in catalog.sortPriceUpdates(for: [summary]) { last = update }
        XCTAssertNotNil(last?.prices[summary.id])
        XCTAssertTrue(last?.resolvedIDs.contains(summary.id) == true)
    }

    func testLegacyChecklistNormalSlotBecomesHoloWithoutChangingIdentity() {
        var summary = Self.summary("30th-c-014")
        summary.masterSetVariant = .normal
        let set = CatalogSet(catalogID: summary.setID, name: summary.setName, code: "30C",
                             logoURL: nil, symbolURL: nil, cardCount: 30, releaseDate: nil, sortRank: 1)
        let corrected = BrowseCatalog.applyingSignedCardArtwork([summary], set: set)
        XCTAssertEqual(corrected.count, 1)
        XCTAssertEqual(corrected[0].providerID, summary.providerID)
        XCTAssertEqual(corrected[0].masterSetVariant, .holo)
    }

    @MainActor
    func testSavedGenesectReadsFallbackQuoteStoredUnderItsResolvedCatalogIdentity() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let startedAt = Date.now.addingTimeInterval(-60)
        // A normalized import keeps its local ownership/price identity. A
        // subsequent scanner fallback currently saves by the resolved card ID.
        let row = CollectedCard(collectionKey: "csv:genesect#holo", game: .pokemon,
            providerID: "csv:genesect", name: "Genesect EX", setName: "30th Classic Collection",
            setCode: "30TH-C", cardNumber: "11", rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: .holo, variantResolution: .userConfirmed)
        row.catalogProviderID = "30th-c-004"
        context.insert(row)
        _ = InventoryLedger(context: context).record(row, kind: .acquire,
            source: .scan, deltaQuantity: 1)
        let prices = PriceStore(context: context)
        XCTAssertTrue(prices.store(.unavailable(.tcgplayer), game: .pokemon,
            printingID: row.priceStorageID, variantID: "holo"))
        XCTAssertTrue(prices.save())
        let projectionActor = await CollectionProjectionActor.makeBackground(modelContainer: container)
        let initialProjection = await projectionActor.snapshot()
        let cachedRow = try XCTUnwrap(initialProjection.rowsByCollectionKey[row.collectionKey])
        XCTAssertEqual(cachedRow.priceStorageKey, row.priceKey)
        let quote = PriceLookup.price(NormalizedPrice(unitMarketPriceUSD: 8.06, currencyCode: "USD",
            source: .tcgCSV, sourceVariantID: "holofoil", sourceUpdatedAt: nil, fetchedAt: .now))
        XCTAssertTrue(prices.store(quote, game: .pokemon, printingID: "30th-c-004", variantID: "holo"))
        XCTAssertTrue(prices.save())

        let records = Dictionary(uniqueKeysWithValues: prices.allRecords().map { ($0.key, $0) })
        XCTAssertEqual(PriceStore.record(for: row, in: records)?.effectiveUnitMarketPriceUSD, 8.06)
        let reader = await PriceSnapshotModelActor.makeBackground(modelContainer: container)
        let snapshot = await reader.snapshot()
        let displayKey = try XCTUnwrap(snapshot.priceStorageKeyByCollectionKey[row.collectionKey])
        XCTAssertEqual(snapshot.prices[displayKey]?.amount, 8.06)
        XCTAssertNil(snapshot.diagnosticsByCollectionKey[row.collectionKey]?.unpricedReason)
        let channel = PriceSnapshotStore()
        channel.replace(with: snapshot)
        let displayedRow = channel.applying(to: cachedRow)
        XCTAssertEqual(displayedRow.priceStorageKey, displayKey)
        XCTAssertEqual(displayedRow.price.amount, 8.06)
        channel.replace(with: PriceSnapshot(prices: [:], diagnosticsByCollectionKey: [:],
            priceStorageKeyByCollectionKey: [row.collectionKey: row.priceKey]))
        XCTAssertNil(channel.applying(to: displayedRow).price.amount,
            "An empty selected instrument must not retain a cached alias quote")
        let replay = PortfolioReplaySnapshotBuilder.compute(context: ModelContext(container),
            epoch: startedAt, through: .now, timeZone: TimeZone(secondsFromGMT: 0)!).replay
        XCTAssertEqual(replay.live?.attribution.currentValue, Money(rounding: 8.06))
        XCTAssertEqual(replay.live?.additions[row.collectionKey], Money(rounding: 8.06))
        XCTAssertEqual(row.providerID, "csv:genesect")
        XCTAssertEqual(row.quantity, 1)

        // A later explicit withdrawal on the owned identity still wins over
        // the shared catalog quote; read-through must never revive it.
        let local = try XCTUnwrap(prices.record(forKey: row.priceKey))
        local.invalidate(at: .now)
        XCTAssertTrue(prices.save())
        XCTAssertEqual(PriceStore.priceStorageKey(for: row, in: records), row.priceKey)
        XCTAssertNil(PriceStore.record(for: row, in: records)?.effectiveUnitMarketPriceUSD)
    }

    @MainActor
    func testSharedCatalogQuotesCannotOverrideOwnedPriceOrReviveItsWithdrawal() throws {
        for withdraw in [false, true] {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let context = container.mainContext
            let epoch = Date.now.addingTimeInterval(-120)
            let row = CollectedCard(collectionKey: "csv:genesect#holo", game: .pokemon,
                providerID: "csv:genesect", name: "Genesect EX", setName: "30th Classic Collection",
                setCode: "30TH-C", cardNumber: "11", rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: .holo, variantResolution: .userConfirmed)
            row.catalogProviderID = "30th-c-004"
            context.insert(row)
            let prices = PriceStore(context: context)
            func store(_ amount: Double, id: String, seconds: TimeInterval) {
                let fetchedAt = epoch.addingTimeInterval(seconds)
                XCTAssertTrue(prices.store(.price(NormalizedPrice(unitMarketPriceUSD: amount,
                    currencyCode: "USD", source: .tcgCSV, sourceVariantID: "holofoil",
                    sourceUpdatedAt: nil, fetchedAt: fetchedAt)), game: .pokemon,
                    printingID: id, variantID: "holo", at: fetchedAt))
            }
            store(8, id: "30th-c-004", seconds: 10)
            _ = InventoryLedger(context: context).record(row, kind: .acquire, source: .scan,
                deltaQuantity: 1, occurredAt: epoch.addingTimeInterval(20))
            store(10, id: row.priceStorageID, seconds: 30)
            if withdraw {
                XCTAssertNotNil(PriceObservationLog(context: context).recordInvalidation(
                    instrumentKey: row.priceKey, source: .tcgCSV, at: epoch.addingTimeInterval(40)))
            }
            store(9, id: "30th-c-004", seconds: 50)
            XCTAssertTrue(prices.save())
            let records = Dictionary(uniqueKeysWithValues: prices.allRecords().map { ($0.key, $0) })
            XCTAssertEqual(PriceStore.record(for: row, in: records)?.effectiveUnitMarketPriceUSD, withdraw ? nil : 10)
            let replay = PortfolioReplaySnapshotBuilder.compute(context: ModelContext(container),
                epoch: epoch, through: .now, timeZone: TimeZone(secondsFromGMT: 0)!).replay
            XCTAssertEqual(replay.live?.attribution.currentValue, Money(rounding: withdraw ? 0 : 10))
            XCTAssertEqual(replay.live?.additions[row.collectionKey], Money(rounding: 8))
        }
    }

    @MainActor
    func testCatalogPriceReadThroughNeverCrossesFinishPrintRunOrItemKind() {
        let row = CollectedCard(collectionKey: "csv:genesect#holo", game: .pokemon,
            providerID: "csv:genesect", name: "Genesect EX", setName: "30th Classic Collection",
            setCode: "30TH-C", cardNumber: "11", rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: .holo, variantResolution: .userConfirmed)
        row.catalogProviderID = "30th-c-004"
        let key = PriceRecord.key(game: .pokemon, printingID: "30th-c-004", variantID: "holo")
        let price = PriceRecord(key: key, game: .pokemon, printingID: "30th-c-004", variantID: "holo")
        price.applyImported(amount: 8.06, sourceUpdatedAt: nil)
        let records = [key: price]
        XCTAssertEqual(PriceStore.record(for: row, in: records)?.effectiveUnitMarketPriceUSD, 8.06)
        for variant in [PhysicalVariant.reverse, .normal, nil] {
            row.variantID = variant?.id
            XCTAssertNil(PriceStore.record(for: row, in: records))
        }
        row.variantID = "holo"
        row.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        XCTAssertNil(PriceStore.record(for: row, in: records))
        row.pokemonPrintRunRaw = nil
        for kind in [CollectionItemKind.gradedCard, .sealedProduct] {
            row.itemKindRaw = kind.rawValue
            XCTAssertNil(PriceStore.record(for: row, in: records))
        }
    }

    @MainActor
    func testScannedGenesectRefreshPricesPortfolioAndCardsAddedUsingExactBrowseIdentity() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let startedAt = Date.now.addingTimeInterval(-60)
        // Scanning preserves the reprinted 11/101 while Browse uses slot 004.
        let card = TCGdexCard(id: "30th-c-004", localId: "11", name: "Genesect EX",
            image: nil, rarity: nil,
            set: TCGdexSetBrief(id: "30th-c", name: "30th Classic Collection",
                cardCount: TCGdexCardCount(total: 101, official: 101)),
            variants: nil, pricing: nil, variantsDetailed: nil)
        let identified = IdentifiedCard.pokemon(card, setCode: "30TH-C")
        _ = try CollectionStore(context: context).add(identified,
            resolved: .init(variant: .holo, resolution: .userConfirmed), source: .scan)
        let snapshot = PokemonTCGCSVSnapshot(schemaVersion: 1, setID: "30th-c", feedBuild: "genesect",
            fetchedAt: .now, validatedAt: .now, valuesByCardID: ["30th-c-004": 8.06])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let browse = BrowseCatalog(cache: CatalogCacheStore(root: root),
            pokemonTransport: UnavailablePokemonTransport(), tcgCSVSource: RecordedTCGCSV(snapshot: snapshot))
        let summary = CatalogCardSummary(game: .pokemon, providerID: card.id,
            setID: .init(game: .pokemon, providerID: card.set.id), setName: card.set.name,
            setCode: "30TH-C", name: card.name, collectorNumber: "004", thumbnailURL: nil,
            imageURL: nil, masterSetVariant: .holo)
        var browsePrice: Double?
        for await update in browse.sortPriceUpdates(for: [summary]) {
            browsePrice = update.prices[summary.id] ?? browsePrice
        }
        XCTAssertEqual(browsePrice, 8.06)
        let actor = PriceRefreshModelActor(modelContainer: container)
        await actor.setPokemonFetchOverrideForTesting { _ in throw URLError(.notConnectedToInternet) }
        await actor.setTCGCSVSourceForTesting(RecordedTCGCSV(snapshot: snapshot))
        let result = await actor.run(PriceRefreshRequest(
            usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: false,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false
        ), progress: { _ in }, shouldContinue: nil)
        guard case let .completed(report) = result else { return XCTFail("Expected completed refresh") }
        XCTAssertEqual(report.priced, 1)
        let readContext = ModelContext(container)
        let key = identified.collectionKey(variant: .holo)
        let row = try XCTUnwrap(readContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.collectionKey, key)
        XCTAssertEqual(row.cardNumber, "11")
        XCTAssertEqual(row.quantity, 1)
        XCTAssertEqual(PriceStore(context: readContext).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD, browsePrice)
        let computation = PortfolioReplaySnapshotBuilder.compute(context: readContext,
            epoch: startedAt, through: .now, timeZone: TimeZone(secondsFromGMT: 0)!)
        let live = try XCTUnwrap(computation.replay.live)
        XCTAssertEqual(live.attribution.currentValue, Money(rounding: 8.06))
        XCTAssertEqual(live.additions[key], Money(rounding: 8.06))
        XCTAssertEqual(live.addedQuantities[key], 1)
    }

    @MainActor
    func testCollectionRefreshUsesBulkWhenCatalogIsDownAndPaidFallbackDisabled() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let row = CollectedCard(collectionKey: "30th-c-014#holo", game: .pokemon, providerID: "30th-c-014",
                                name: "Pikachu", setName: "30th Celebration Classic Collection", setCode: "30C",
                                cardNumber: "014", rarity: nil, imageURL: nil, thumbnailURL: nil,
                                variant: .holo, variantResolution: .userConfirmed)
        context.insert(row)
        try context.save()
        let cached = try snapshot("30th-c")
        let prices = PriceStore(context: context)
        XCTAssertTrue(prices.store(.unavailable(.tcgplayer), game: .pokemon,
                                   printingID: row.priceStorageID, variantID: "holo",
                                   at: cached.fetchedAt.addingTimeInterval(60)))
        XCTAssertTrue(prices.save())
        let actor = PriceRefreshModelActor(modelContainer: container)
        await actor.setPokemonFetchOverrideForTesting { _ in throw URLError(.notConnectedToInternet) }
        await actor.setTCGCSVSourceForTesting(RecordedTCGCSV(snapshot: cached))
        let result = await actor.run(PriceRefreshRequest(
            usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: false,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false
        ), progress: { _ in }, shouldContinue: nil)
        guard case let .completed(report) = result else { return XCTFail("Expected completed refresh") }
        XCTAssertEqual(report.priced, 1, "Refresh report: \(report)")
        let record = PriceStore(context: ModelContext(container)).record(forKey: row.priceKey)
        XCTAssertEqual(record?.sourceRaw, PriceSource.tcgCSV.rawValue)
        XCTAssertNotNil(record?.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(record?.fetchedAt, cached.fetchedAt)
    }

    @MainActor
    func testCollectionMissingPriceRecordsCooldownInSyntheticAndCatalogOutageLanes() async throws {
        for hasPriorPrice in [false, true] {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                              configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let context = container.mainContext
            let row = CollectedCard(collectionKey: "30th-c-014#holo", game: .pokemon, providerID: "30th-c-014",
                                    name: "Pikachu", setName: "30th Celebration Classic Collection", setCode: "30C",
                                    cardNumber: "014", rarity: nil, imageURL: nil, thumbnailURL: nil,
                                    variant: .holo, variantResolution: .userConfirmed)
            context.insert(row)
            let prices = PriceStore(context: context)
            let previousAt = Date.now.addingTimeInterval(-PriceRefreshController.automaticRefreshInterval - 60)
            if hasPriorPrice {
                XCTAssertTrue(prices.store(.price(NormalizedPrice(
                    unitMarketPriceUSD: 123, currencyCode: "USD", source: .tcgCSV,
                    sourceVariantID: "holofoil", sourceUpdatedAt: nil, fetchedAt: previousAt
                )), game: .pokemon, printingID: row.priceStorageID, variantID: "holo", at: previousAt))
            }
            try context.save()
            let startedAt = Date.now
            let missing = PokemonTCGCSVSnapshot(schemaVersion: 1, setID: "30th-c", feedBuild: "test",
                                                fetchedAt: startedAt, validatedAt: startedAt, valuesByCardID: [:])
            let actor = PriceRefreshModelActor(modelContainer: container)
            await actor.setPokemonFetchOverrideForTesting { _ in throw URLError(.notConnectedToInternet) }
            await actor.setTCGCSVSourceForTesting(RecordedTCGCSV(snapshot: missing))
            let result = await actor.run(PriceRefreshRequest(
                usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: false,
                sortOldestFirst: true, maximumTargetCount: 3, markRecentlyCheckedIfEmpty: false
            ), progress: { _ in }, shouldContinue: nil)
            guard case let .completed(report) = result else { return XCTFail("Expected completed refresh") }
            XCTAssertEqual(report.priced, 0)
            XCTAssertFalse(report.persistenceFailed)
            let readContext = ModelContext(container)
            let record = try XCTUnwrap(PriceStore(context: readContext).record(forKey: row.priceKey))
            XCTAssertEqual(record.source, .tcgCSV)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(record.lastCheckedAt), startedAt)
            XCTAssertEqual(record.effectiveUnitMarketPriceUSD, hasPriorPrice ? 123 : nil)
            if hasPriorPrice { XCTAssertEqual(record.fetchedAt, previousAt) }
            XCTAssertEqual(try readContext.fetch(FetchDescriptor<PriceObservation>()).count, hasPriorPrice ? 1 : 0)
            let targets = try PriceRefreshTargets.make(context: readContext, usesPriceFallback: false, includeImported: true)
            XCTAssertTrue(PriceRefreshController.staleTargets(from: targets, usesPriceFallback: false).isEmpty)
            XCTAssertEqual(PriceRefreshController.staleTargets(
                from: targets, now: startedAt.addingTimeInterval(PriceRefreshController.automaticRefreshInterval + 60),
                usesPriceFallback: false
            ).count, 1)
        }
    }

    @MainActor
    func testAutomaticNormalCollectionFinishIsRepairedAndPricedInOneRefresh() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                          configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        _ = try CollectionStore(context: context).add(
            .pokemon(try Self.card("30th-c-014"), setCode: "30C"),
            resolved: ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog), source: .scan
        )
        let actor = PriceRefreshModelActor(modelContainer: container)
        await actor.setPokemonFetchOverrideForTesting { _ in throw URLError(.notConnectedToInternet) }
        await actor.setTCGCSVSourceForTesting(RecordedTCGCSV(snapshot: try snapshot("30th-c")))
        let result = await actor.run(PriceRefreshRequest(
            usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: false,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false
        ), progress: { _ in }, shouldContinue: nil)
        guard case let .completed(report) = result else { return XCTFail("Expected completed refresh") }
        XCTAssertEqual(report.repairedFinishes, 1)
        XCTAssertEqual(report.priced, 1)
        let readContext = ModelContext(container)
        let rows = try readContext.fetch(FetchDescriptor<CollectedCard>()).filter { $0.quantity > 0 }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].variantID, PhysicalVariant.holo.id)
        XCTAssertEqual(PriceStore(context: readContext).record(forKey: rows[0].priceKey)?.source, .tcgCSV)
    }

    private func server() throws -> TCGCSVTestServer {
        let fixtures = try fixtures()
        var routes = ["/last-updated.txt": Data("2026-09-29T20:05:57+0000".utf8)]
        for (id, group) in [("30th", 24722), ("30th-c", 24837)] {
            for suffix in ["products", "prices"] {
                routes["/tcgplayer/3/\(group)/\(suffix)"] = try JSONSerialization.data(withJSONObject: fixtures[id]![suffix]!)
            }
        }
        return TCGCSVTestServer(routes: routes, now: date)
    }

    private func makeService(server: TCGCSVTestServer, root: URL) -> PokemonTCGCSVPriceService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TCGCSVTestURLProtocol.self]
        return PokemonTCGCSVPriceService(session: URLSession(configuration: configuration),
                                        baseURL: URL(string: "https://pricing.example")!,
                                        cacheDirectory: root, now: { server.now }, spacing: 0)
    }

    private static func card(_ id: String, priced: Bool = false) throws -> TCGdexCard {
        let setID = id.hasPrefix("30th-c-") ? "30th-c" : String(id.split(separator: "-").dropLast().joined(separator: "-"))
        let pricing = priced ? #", "pricing":{"tcgplayer":{"holofoil":{"marketPrice":123}}}"# : #", "pricing":{"cardmarket":null,"tcgplayer":null}"#
        return try JSONDecoder().decode(TCGdexCard.self, from: Data("""
        {"id":"\(id)","localId":"\(id.suffix(3))","name":"Pikachu", "set":{"id":"\(setID)","name":"Test Set","cardCount":{"total":30,"official":0}},
        "variants":{"normal":true,"holo":false,"reverse":false,"firstEdition":false},"variants_detailed":[{"type":"normal","variantId":"generated"}]\(pricing)}
        """.utf8))
    }

    private static func summary(_ id: String) -> CatalogCardSummary {
        CatalogCardSummary(game: .pokemon, providerID: id, setID: CatalogSetID(game: .pokemon, providerID: "30th-c"),
                           setName: "30th Celebration Classic Collection", setCode: "30C", name: "Pikachu",
                           collectorNumber: "014", thumbnailURL: nil, imageURL: nil, masterSetVariant: .holo)
    }
}

private struct RecordedTCGCSV: PokemonTCGCSVPriceSource {
    let snapshot: PokemonTCGCSVSnapshot
    func snapshot(setID: String, retry: Bool) async throws -> PokemonTCGCSVSnapshot { snapshot }
}

private final class BrowseSupplementState: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = Date.now
    private var offline = false
    private var value: PokemonTCGCSVSnapshot

    init(snapshot: PokemonTCGCSVSnapshot) { value = snapshot }
    var now: Date { lock.withLock { instant } }
    var isOffline: Bool { lock.withLock { offline } }
    func goOffline(after elapsed: TimeInterval) {
        lock.withLock { instant.addTimeInterval(elapsed); offline = true }
    }
    func recover(with snapshot: PokemonTCGCSVSnapshot) {
        lock.withLock { value = snapshot; offline = false }
    }
    func snapshot() throws -> PokemonTCGCSVSnapshot {
        try lock.withLock {
            if offline { throw URLError(.notConnectedToInternet) }
            return value
        }
    }
}

private struct BrowseSupplementTransport: PokemonBrowseTransport {
    let card: TCGdexCard
    let state: BrowseSupplementState

    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] { [] }
    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        try JSONDecoder().decode(TCGdexSetCatalog.self,
            from: JSONSerialization.data(withJSONObject: [
                "id": card.set.id, "name": "Test Set",
                "cards": [["id": card.id, "localId": card.localId, "name": card.name]]
            ]))
    }
    func fetchCard(id: String) async throws -> TCGdexCard {
        if state.isOffline { throw URLError(.notConnectedToInternet) }
        return card
    }
}

private struct BrowseSupplementSource: PokemonTCGCSVPriceSource {
    let state: BrowseSupplementState
    func snapshot(setID: String, retry: Bool) async throws -> PokemonTCGCSVSnapshot {
        try state.snapshot()
    }
}

private struct UnavailablePokemonTransport: PokemonBrowseTransport {
    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] { throw URLError(.notConnectedToInternet) }
    func fetchSet(id: String) async throws -> TCGdexSetCatalog { throw URLError(.notConnectedToInternet) }
    func fetchCard(id: String) async throws -> TCGdexCard { throw URLError(.notConnectedToInternet) }
}

private final class TCGCSVTestServer: @unchecked Sendable {
    private let lock = NSLock()
    let routes: [String: Data]
    private var clock: Date
    private var recorded: [URLRequest] = []
    private var shouldFail = false
    private var requestDelay: TimeInterval = 0
    init(routes: [String: Data], now: Date) { self.routes = routes; clock = now }
    var now: Date { lock.withLock { clock } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    var fail: Bool {
        get { lock.withLock { shouldFail } }
        set { lock.withLock { shouldFail = newValue } }
    }
    var delay: TimeInterval {
        get { lock.withLock { requestDelay } }
        set { lock.withLock { requestDelay = newValue } }
    }
    func advance(_ seconds: TimeInterval) { lock.withLock { clock.addTimeInterval(seconds) } }
    func response(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            recorded.append(request)
            let build = routes["/last-updated.txt"].flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return shouldFail ? (503, Data()) : (200,
                MarketMirrorFixture.stamped(routes[request.url!.path] ?? Data(), capturedAt: clock, build: build))
        }
    }
}

private final class TCGCSVTestURLProtocol: URLProtocol, @unchecked Sendable {
    static var server: TCGCSVTestServer?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let server = Self.server else { return client!.urlProtocol(self, didFailWithError: URLError(.badServerResponse)) }
        let (status, data) = server.response(request)
        if server.delay > 0 { Thread.sleep(forTimeInterval: server.delay) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
