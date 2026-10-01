import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

final class PokemonTCGCSVPriceTests: XCTestCase {
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

    func testAll188MappingsJoinExactProductsAndHolofoilPrices() throws {
        XCTAssertEqual(PokemonTCGCSVMapping.entries.count, 188)
        XCTAssertEqual(Set(PokemonTCGCSVMapping.entries.map(\.cardID)).count, 188)
        XCTAssertEqual(Set(PokemonTCGCSVMapping.entries.map(\.productID)).count, 188)
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
            return shouldFail ? (503, Data()) : (200, routes[request.url!.path] ?? Data())
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
