import Combine
import XCTest
import SwiftData
@testable import TradingCardScanner

private extension PriceLookup {
    var value: Double? {
        guard case let .price(quote) = self else { return nil }
        return quote.unitMarketPriceUSD
    }
}

private actor UpgradeProbeTransport: PokemonBrowseTransport {
    let provider: TCGdexSetCatalog
    var detailRequests = 0
    var setRequests = 0
    init(provider: TCGdexSetCatalog) { self.provider = provider }
    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        [try JSONDecoder().decode(TCGdexBrowseSet.self, from: Data(#"{"id":"me02.5","name":"Ascended Heroes","cardCount":{"total":2,"official":2}}"#.utf8))]
    }
    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        setRequests += 1
        return provider
    }
    func fetchCard(id: String) async throws -> TCGdexCard {
        detailRequests += 1
        throw URLError(.notConnectedToInternet)
    }
}

private actor BlisterFamilyProbeTransport: PokemonBrowseTransport {
    let provider: TCGdexSetCatalog
    var detailRequests = 0
    var setRequests = 0
    init(provider: TCGdexSetCatalog) { self.provider = provider }
    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        let object: [String: Any] = ["id": provider.id, "name": provider.name,
            "cardCount": ["total": provider.cardCount?.total ?? 1, "official": provider.cardCount?.official ?? 1]]
        return [try JSONDecoder().decode(TCGdexBrowseSet.self, from: JSONSerialization.data(withJSONObject: object))]
    }
    func fetchSet(id: String) async throws -> TCGdexSetCatalog { setRequests += 1; return provider }
    func fetchCard(id: String) async throws -> TCGdexCard {
        detailRequests += 1
        throw URLError(.notConnectedToInternet)
    }
}

final class PricingTests: XCTestCase {
    @MainActor
    func testImportedValuationClockCannotOverrideAnExactProviderExpiry() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let store = PriceStore(context: container.mainContext)
        let now = Date.now
        let printing = "justtcg:v2:synthetic-imported-clock"
        XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 60, currencyCode: "USD", source: .importedCSV,
            sourceVariantID: "synthetic-import", sourceUpdatedAt: now, fetchedAt: now)), game: .pokemon,
            printingID: printing, variantID: "normal", at: now))
        let oldSale = now.addingTimeInterval(-1000)
        let receipt = GradedVariantBinding.storeUnboundVariantQuote(.init(id: "synthetic-imported-clock", company: .cgc,
            grade: .init(value: "10"), printing: "Normal", marketPriceUSD: nil, updatedAt: oldSale,
            quoteLifecycle: .init(status: "expired", lastPrice: 40, lastSaleAt: oldSale,
                priceExpiresAt: oldSale.addingTimeInterval(100))), game: .pokemon, variantID: "normal",
            treatmentIDs: [], store: store, at: now.addingTimeInterval(1))
        let record = try XCTUnwrap(store.record(forKey: receipt.priceKey))
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertTrue(record.isInvalidated)
        XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle.status, "expired")
    }

    @MainActor
    func testLaterFetchedOldExpiryCannotWithdrawNewerSaleAndEqualSaleExpiryStillCan() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let store = PriceStore(context: container.mainContext)
        let now = Date.now
        let oldSale = now.addingTimeInterval(-1000)
        let newSale = now.addingTimeInterval(-100)
        let fetched = now.addingTimeInterval(-50)
        func bind(status: String, sale: Date, amount: Double?, at checked: Date) -> GradedVariantBindingReceipt {
            GradedVariantBinding.storeUnboundVariantQuote(.init(id: "synthetic-cache-race", company: .cgc,
                grade: .init(value: "10", label: "Gem Mint"), printing: "Normal", marketPriceUSD: amount,
                updatedAt: sale, quoteLifecycle: .init(status: status, lastPrice: status == "expired" ? 40 : nil,
                    lastSaleAt: sale, priceExpiresAt: status == "expired" ? sale.addingTimeInterval(1) : now.addingTimeInterval(1000))),
                game: .pokemon, variantID: "normal", treatmentIDs: [], store: store, at: checked)
        }
        let positive = bind(status: "current", sale: newSale, amount: 60, at: fetched)
        let record = try XCTUnwrap(store.record(forKey: positive.priceKey))
        _ = bind(status: "expired", sale: oldSale, amount: nil, at: now)
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 60)
        XCTAssertEqual(record.sourceUpdatedAt, newSale)
        XCTAssertEqual(record.fetchedAt, fetched)
        XCTAssertEqual(record.exactGradedQuoteEvidence?.checkedAt, fetched)
        XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle.status, "current")
        XCTAssertFalse(record.isInvalidated)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).count, 1)
        _ = bind(status: "expired", sale: newSale, amount: nil, at: now.addingTimeInterval(1))
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertTrue(record.isInvalidated, "Expiry of the same sale is a valid later lifecycle transition")
        XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle.status, "expired")
    }

    @MainActor
    func testStaleExpiryCannotSupersedeNewerExactObservationWhileMutableRecordLags() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let store = PriceStore(context: context)
        let now = Date.now
        let oldSale = now.addingTimeInterval(-1000)
        let withdrawn = now.addingTimeInterval(-500)
        let newSale = now.addingTimeInterval(-100)
        let key = PriceRecord.key(game: .pokemon, printingID: "justtcg:v2:synthetic-observation-cache", variantID: "normal")
        let record = PriceRecord(key: key, game: .pokemon,
            printingID: "justtcg:v2:synthetic-observation-cache", variantID: "normal")
        record.sourceRaw = PriceSource.justTCG.rawValue
        record.sourceUpdatedAt = oldSale
        record.marketVariantID = "synthetic-observation-cache"
        record.invalidatedAt = withdrawn
        record.exactGradedQuoteEvidence = .init(variantID: "synthetic-observation-cache",
            lifecycle: .init(status: "expired", lastPrice: 40, lastSaleAt: oldSale, priceExpiresAt: withdrawn),
            checkedAt: withdrawn, sourceUpdatedAt: oldSale)
        context.insert(record)
        context.insert(PriceObservation(instrumentKey: key, kind: .marketUpdate, amount: Money(rounding: 60),
            source: .justTCG, sourceVariantID: "synthetic-observation-cache", marketVariantID: "synthetic-observation-cache",
            effectiveAt: newSale, receivedAt: newSale, isSourceStamped: true))
        _ = GradedVariantBinding.storeUnboundVariantQuote(.init(id: "synthetic-observation-cache", company: .cgc,
            grade: .init(value: "10"), printing: "Normal", marketPriceUSD: nil, updatedAt: oldSale,
            quoteLifecycle: .init(status: "expired", lastPrice: 40, lastSaleAt: oldSale, priceExpiresAt: withdrawn)),
            game: .pokemon, variantID: "normal", treatmentIDs: [], store: store, at: now)
        XCTAssertEqual(record.exactGradedQuoteEvidence?.checkedAt, withdrawn)
        XCTAssertEqual(record.invalidatedAt, withdrawn)
        XCTAssertEqual(InventoryLedger(context: context).valuation(forPriceKey: key).unitPrice, Money(rounding: 60))
    }

    @MainActor
    func testExactGradedExpiryWithdrawsValueWhileTimeoutRetainsItAndNewSaleCanRestoreIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("graded-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(url: root.appendingPathComponent("holdings.store"), cloudKitDatabase: .none)
        let now = Date.now
        let expires = now.addingTimeInterval(500)
        let current = JustTCGQuoteLifecycle(status: "current", lastPrice: nil, lastSaleAt: now,
            priceExpiresAt: expires)
        let expired = JustTCGQuoteLifecycle(status: "expired", lastPrice: 50, lastSaleAt: now,
            priceExpiresAt: expires)
        let grade = CardGrade(value: "10", label: "Gem Mint")
        let key = try autoreleasepool {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
            let store = PriceStore(context: container.mainContext)
            func bind(_ lifecycle: JustTCGQuoteLifecycle, price: Double?, at date: Date) -> GradedVariantBindingReceipt {
                GradedVariantBinding.storeUnboundVariantQuote(.init(id: "synthetic-lifecycle", company: .cgc,
                    grade: grade, printing: "Normal", marketPriceUSD: price, updatedAt: now,
                    quoteLifecycle: lifecycle), game: .pokemon, variantID: "normal", treatmentIDs: [], store: store, at: date)
            }
            let first = bind(current, price: 50, at: now)
            XCTAssertTrue(first.wasAccepted)
            let record = try XCTUnwrap(store.record(forKey: first.priceKey))
            XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 50)
            XCTAssertTrue(store.recordFailure(game: .pokemon, printingID: record.printingID,
                variantID: "normal", at: now.addingTimeInterval(1)))
            XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 50)
            XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle, current)
            let next = bind(expired, price: nil, at: now.addingTimeInterval(2))
            XCTAssertTrue(next.wasAccepted)
            XCTAssertNil(record.effectiveUnitMarketPriceUSD)
            XCTAssertTrue(record.isInvalidated)
            XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle.lastPrice, 50)
            XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle.lastSaleAt, now)
            XCTAssertNil(InventoryLedger(context: container.mainContext).valuation(forPriceKey: first.priceKey).unitPrice)
            let log = try container.mainContext.fetch(FetchDescriptor<PriceObservation>())
            XCTAssertEqual(log.count, 2)
            XCTAssertEqual(log.filter { $0.kind == .explicitInvalidation }.count, 1)
            XCTAssertTrue(store.save())
            return first.priceKey
        }
        let reopened = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
        let store = PriceStore(context: reopened.mainContext)
        let record = try XCTUnwrap(store.record(forKey: key))
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle, expired)
        XCTAssertNil(record.gradedMarketCoverage)
        let restored = GradedVariantBinding.storeUnboundVariantQuote(.init(id: "synthetic-lifecycle", company: .cgc,
            grade: grade, printing: "Normal", marketPriceUSD: 60, updatedAt: now.addingTimeInterval(3),
            quoteLifecycle: current), game: .pokemon, variantID: "normal", treatmentIDs: [], store: store,
            at: now.addingTimeInterval(3))
        XCTAssertTrue(restored.wasAccepted)
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 60)
        XCTAssertFalse(record.isInvalidated)
        let staleExpiry = ExactGradedQuoteEvidence(variantID: "synthetic-lifecycle", lifecycle: expired,
            checkedAt: now.addingTimeInterval(2))
        store.recordExactGradedQuoteEvidence(staleExpiry, forKey: key)
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 60)
        XCTAssertEqual(record.exactGradedQuoteEvidence?.lifecycle, current)
        let alreadyExpired = GradedVariantBinding.storeUnboundVariantQuote(.init(id: "synthetic-past-expiry", company: .cgc,
            grade: grade, printing: "Normal", marketPriceUSD: 99, updatedAt: now,
            quoteLifecycle: .init(status: "current", lastPrice: nil, lastSaleAt: now.addingTimeInterval(-1000),
                priceExpiresAt: now.addingTimeInterval(-1))), game: .pokemon, variantID: "normal",
            treatmentIDs: [], store: store, at: now)
        let expiredRecord = try XCTUnwrap(store.record(forKey: alreadyExpired.priceKey))
        XCTAssertNil(expiredRecord.effectiveUnitMarketPriceUSD)
        XCTAssertNil(expiredRecord.justTCGFetchedAt, "An elapsed quote cannot stamp a new current quote check")
    }

    func testLifecycleMetadataPreservesLegacyCoverageAndPublishedExpiryIsNeverCurrent() throws {
        let record = PriceRecord(key: "pokemon:justtcg:v2:synthetic:normal", game: .pokemon,
            printingID: "justtcg:v2:synthetic", variantID: "normal")
        let coverage = GradedMarketCoverage(status: .gradeNotListed)
        record.gradedMarketCoverageJSON = String(data: try JSONEncoder().encode(coverage), encoding: .utf8)
        XCTAssertEqual(record.gradedMarketCoverage?.status, .gradeNotListed)
        record.exactGradedQuoteEvidence = .init(variantID: "synthetic", lifecycle: .init(status: "current",
            lastPrice: nil, lastSaleAt: .now.addingTimeInterval(-1000), priceExpiresAt: .now.addingTimeInterval(-1)), checkedAt: .now)
        record.unitMarketPriceUSD = 40
        XCTAssertEqual(record.gradedMarketCoverage?.status, .gradeNotListed)
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertNil(InventoryLedger.resolveValuation(observation: nil, record: record).unitPrice)
        record.gradedMarketCoverage = nil
        XCTAssertNotNil(record.exactGradedQuoteEvidence)
        XCTAssertNil(record.gradedMarketCoverage)
        record.exactGradedQuoteEvidence = .init(variantID: "synthetic", lifecycle: .init(status: "unpriced",
            lastPrice: nil, lastSaleAt: nil, priceExpiresAt: nil), checkedAt: .now)
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
    }

    private func collisionSources() throws -> [TCGdexCard] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reported-physical-collisions",
            withExtension: "json", subdirectory: "TradingCards/PokemonCatalogCoverageAudit"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["cases"] as? [[String: Any]]).map {
            try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap($0["source"])))
        }
    }

    func testReviewedPhysicalObjectsKeepDittoSubtypeAndBothCosmosBasesDistinct() throws {
        let objects = PokemonReviewedPhysicalObjects.self
        for source in try collisionSources() {
            let identified = IdentifiedCard.pokemon(source, setCode: "")
            let finishes = try XCTUnwrap(objects.variants(cardID: source.id))
            XCTAssertEqual(source.catalogVariants, finishes)
            XCTAssertEqual(Set(finishes.map(\.id)).count, finishes.count)
            for finish in finishes {
                XCTAssertEqual(PhysicalVariant.resolving(finish.id), finish)
                let data = try JSONEncoder().encode(finish)
                XCTAssertEqual(try JSONDecoder().decode(PhysicalVariant.self, from: data), finish)
            }
            if source.id == "swsh10.5-059" {
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: objects.plainReverse, printRun: nil), 276982)
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: objects.peelableDitto, printRun: nil), 277788)
                XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: .reverse, printRun: nil))
                XCTAssertNil(CardPricing.price(for: identified, variant: .reverse, magicTreatments: []).value)
                XCTAssertEqual(source.detailedVariant(for: objects.plainReverse)?.subtype, nil)
                XCTAssertEqual(source.detailedVariant(for: objects.peelableDitto)?.subtype, "peelable-ditto")
            } else {
                XCTAssertEqual(source.detailedVariant(for: objects.cosmosHolo)?.type, "holo")
                XCTAssertEqual(source.detailedVariant(for: objects.cosmosReverse)?.type, "reverse")
                XCTAssertNil(source.detailedVariant(for: .pokemonFoilPattern("cosmos")))
                XCTAssertNil(CardPricing.price(for: identified, variant: .pokemonFoilPattern("cosmos"), magicTreatments: []).value)
            }
            for finish in [objects.plainReverse, objects.peelableDitto, objects.cosmosHolo, objects.cosmosReverse] {
                XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: finish, printRun: .firstEdition))
                XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: finish, printRun: .shadowless))
            }
        }
    }

    @MainActor
    func testAmbiguousPhysicalObjectsKeepOwnershipAndQuotesButAreUnpricedAfterStoreReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("physical-review-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(url: root.appendingPathComponent("holdings.store"), cloudKitDatabase: .none)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        try autoreleasepool {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
            let context = container.mainContext
            for source in try collisionSources() {
                let old: PhysicalVariant = source.id == "swsh10.5-059" ? .reverse : .pokemonFoilPattern("cosmos")
                for imported in [false, true] {
                    let id = imported ? "csv:\(source.id)" : source.id
                    let row = CollectedCard(collectionKey: "\(id):\(old.id)", game: .pokemon, providerID: id,
                        name: source.name, setName: source.set.name, setCode: source.set.id,
                        cardNumber: source.localId, rarity: nil, imageURL: nil, thumbnailURL: nil,
                        variant: old, variantResolution: .userConfirmed)
                    row.catalogProviderID = source.id
                    context.insert(row)
                    let store = PriceStore(context: context)
                    XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 12, currencyCode: "USD",
                        source: .tcgplayer, sourceVariantID: "legacy", sourceUpdatedAt: now, fetchedAt: now)),
                        game: .pokemon, printingID: row.priceStorageID, variantID: old.id, at: now))
                    XCTAssertNil(PokemonFinishReconciliation.repair(storedVariantID: old.id,
                        storedResolution: .userConfirmed, itemKind: .rawCard, printRun: nil,
                        card: .pokemon(source, setCode: "")))
                }
            }
            try context.save()
        }
        let reopened = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
        let cards = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        let records = try reopened.mainContext.fetch(FetchDescriptor<PriceRecord>())
        let observations = try reopened.mainContext.fetch(FetchDescriptor<PriceObservation>())
        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(records.count, 4)
        XCTAssertTrue(records.allSatisfy { $0.unitMarketPriceUSD == 12 && !$0.isInvalidated })
        XCTAssertEqual(observations.count, 4)
        let valuations = PortfolioReplaySnapshotBuilder.valuationIndex(observations: observations,
            records: records, reviewCards: cards)
        let reader = await PriceSnapshotModelActor.makeBackground(modelContainer: reopened)
        let snapshot = await reader.snapshot()
        let projection = await CollectionProjectionActor.makeBackground(modelContainer: reopened)
        let rows = await projection.snapshot()
        let presentation = PriceSnapshotStore()
        presentation.replace(with: snapshot)
        for card in cards {
            XCTAssertTrue(PokemonReviewedPhysicalObjects.requiresReview(card))
            XCTAssertEqual(card.variantResolution, .userConfirmed)
            XCTAssertEqual(card.quantity, 1)
            XCTAssertNil(valuations.valuation(for: valuations.priceStorageKey(for: card)).unitPrice)
            XCTAssertNil(snapshot.prices[card.priceKey]?.amount)
            XCTAssertNil(rows.rowsByCollectionKey[card.collectionKey]?.price.amount)
            XCTAssertEqual(snapshot.diagnosticsByCollectionKey[card.collectionKey]?.unpricedReason, .physicalIdentityReview)
            presentation.apply([.init(key: card.priceKey, display: .init(amount: 99, currencyCode: "USD", source: .tcgplayer,
                sourceUpdatedAt: now, fetchedAt: now))])
            XCTAssertNil(presentation.display(for: card.priceKey)?.amount)
        }
        let csv = CollectionCSV.exportUnpriced(cards, priceRecords: records)
        XCTAssertEqual(csv.text.split(separator: "\n").count, 5)
    }

    private func reportedParallelCases() throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reported-parallel-review",
            withExtension: "json", subdirectory: "TradingCards/PokemonCatalogCoverageAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(document["cases"] as? [[String: Any]])
    }

    func testEveryReviewedDailyFeedProductRequiresItsSourceIdentityAndExactHoloRun() throws {
        XCTAssertEqual(Set(PokemonTCGCSVMapping.entries.map(\.setID)), ["mee", "30th", "30th-c"])
        for entry in PokemonTCGCSVMapping.entries {
            let localID = entry.setID == "mee" ? entry.printedNumber : String(entry.cardID.dropFirst(entry.setID.count + 1))
            var source: [String: Any] = ["id": entry.cardID, "localId": localID, "name": entry.productName,
                "set": ["id": entry.setID, "name": "Reviewed fixture", "cardCount": ["official": 128, "total": 196]],
                "variants_detailed": [["type": "holo", "size": "standard"]]]
            func card(_ object: [String: Any]) throws -> IdentifiedCard {
                .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object)), setCode: "")
            }
            for run: PokemonPrintRun? in [nil, .unlimited] {
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: try card(source), variant: .holo, printRun: run), entry.productID, entry.cardID)
            }
            for run: PokemonPrintRun in [.firstEdition, .shadowless] {
                XCTAssertNil(CardPricing.tcgplayerProductID(for: try card(source), variant: .holo, printRun: run), entry.cardID)
            }
            for finish: PhysicalVariant in [.normal, .reverse, .pokemonFoilPattern("cosmos")] {
                XCTAssertNil(CardPricing.tcgplayerProductID(for: try card(source), variant: finish, printRun: nil), entry.cardID)
            }
            for (field, value) in [("name", "Unrelated Fixture"), ("localId", "99999"), ("id", "fixture-unknown")] {
                var wrong = source; wrong[field] = value
                XCTAssertNil(CardPricing.tcgplayerProductID(for: try card(wrong), variant: .holo, printRun: nil), entry.cardID + field)
            }
            var wrongSet = source
            wrongSet["set"] = ["id": "unrelated", "name": "Unrelated", "cardCount": ["official": 128, "total": 196]]
            XCTAssertNil(CardPricing.tcgplayerProductID(for: try card(wrongSet), variant: .holo, printRun: nil))
            source["variants_detailed"] = [["type": "holo", "thirdParty": ["tcgplayer": 999999]]]
            XCTAssertNil(CardPricing.tcgplayerProductID(for: try card(source), variant: .holo, printRun: nil), entry.cardID)
        }
    }

    @MainActor
    func testBlisterFamilySurvivesSavedChecklistUnchangedProbeOfflineScannerBrowseAndCollectionReopen() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reported-parallel-review",
            withExtension: "json", subdirectory: "TradingCards/PokemonCatalogCoverageAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let family = try XCTUnwrap(document["boundedRetailFamily"] as? [String: Any])
        let members = try XCTUnwrap(family["members"] as? [[String: Any]])
        XCTAssertEqual(Set(members.compactMap { $0["catalogID"] as? String }), ["me03-050", "me05-040", "me02.5-097"])
        let loaded = await PokemonChecklistStore.shared.bundledSnapshot()
        let bundle = try XCTUnwrap(loaded)
        let cosmos = PhysicalVariant.pokemonFoilPattern("cosmos")
        for member in members {
            let id = try XCTUnwrap(member["catalogID"] as? String)
            let expectedProduct = try XCTUnwrap(member["productID"] as? Int)
            let sourceEntry = try XCTUnwrap((try reportedParallelCases()).first { $0["catalogID"] as? String == id })
            let source = try JSONDecoder().decode(TCGdexCard.self,
                from: JSONSerialization.data(withJSONObject: XCTUnwrap(sourceEntry["source"])))
            let entry = try XCTUnwrap(bundle.entry(forProviderID: source.set.id))
            let rows = try XCTUnwrap(bundle.checklist(for: entry.set.catalogID))
            let old = rows.filter { !($0.providerID == id && $0.masterSetVariant == cosmos) }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("blister-family-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let probeObject: [String: Any] = ["id": source.set.id, "name": source.set.name,
                "cards": [["id": id, "localId": source.localId, "name": source.name]],
                "cardCount": ["total": source.set.cardCount.total, "official": source.set.cardCount.official]]
            let probe = try JSONDecoder().decode(TCGdexSetCatalog.self, from: JSONSerialization.data(withJSONObject: probeObject))
            let oldCounts = PokemonChecklistReviewedProjection.entry(entry, cards: old)
            let oldEntry = PokemonChecklistSnapshotEntry(set: oldCounts.set, providerID: entry.providerID,
                providerFingerprint: entry.providerFingerprint,
                providerProbeFingerprint: PokemonMasterSetChecklistBuilder.providerProbeFingerprint(of: probe),
                officialCount: entry.officialCount, standardSlotCount: oldCounts.standardSlotCount,
                expandedSlotCount: oldCounts.expandedSlotCount, resource: entry.resource)
            let manifest = PokemonChecklistSnapshotManifest(schemaVersion: bundle.manifest.schemaVersion,
                rulesVersion: bundle.manifest.rulesVersion, generatedAt: bundle.manifest.generatedAt,
                directoryFingerprint: bundle.manifest.directoryFingerprint, entries: [oldEntry])
            try await PokemonChecklistStore(root: root, bundle: nil).replace(.init(manifest: manifest, checklists: [entry.set.id: old]))
            let bytes = try Data(contentsOf: root.appendingPathComponent(entry.resource))
            let manifestBytes = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
            let reopened = PokemonChecklistStore(root: root, bundle: nil)
            for _ in 0..<2 {
                let loaded = await reopened.mergedChecklist(for: entry.set.catalogID)
                let repaired = try XCTUnwrap(loaded)
                XCTAssertEqual(repaired.filter { $0.providerID == id && $0.masterSetVariant == cosmos }.count, 1)
                XCTAssertEqual(repaired.count, old.count + 1)
                let directory = await reopened.mergedEntries()
                let projected = try XCTUnwrap(directory.first { $0.providerID == source.set.id })
                XCTAssertEqual(projected.expandedSlotCount, repaired.count)
                XCTAssertEqual(projected.standardSlotCount, repaired.filter { !$0.isExpandedMasterSetVariant }.count)
                XCTAssertEqual(projected.set.cardCount, repaired.count)
                XCTAssertEqual(projected.providerFingerprint, oldEntry.providerFingerprint)
                XCTAssertEqual(projected.providerProbeFingerprint, oldEntry.providerProbeFingerprint)
                await reopened.discardDecodedChecklists()
            }
            let offline = await PokemonOfflineCatalog(store: reopened).card(providerSetID: source.set.id,
                localID: source.localId, expectedOfficialCount: source.set.cardCount.official)
            let offlineCard = try XCTUnwrap(offline)
            let identified = IdentifiedCard.pokemon(offlineCard, setCode: entry.set.code)
            XCTAssertTrue(VariantResolver.options(for: identified.variantEvidence).contains(cosmos))
            XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: identified, variant: cosmos), [.tcgplayerID(String(expectedProduct))])
            XCTAssertNil(CardPricing.price(for: identified, variant: cosmos, magicTreatments: []).value)
            let code = ["me03": "POR", "me05": "PBL", "me02.5": "ASC"][source.set.id]!
            let identifier = try XCTUnwrap(PokemonScanProfile.bundledSeed.parse("\(code) EN \(source.localId)/\(source.set.cardCount.official)"))
            guard case let .pokemon(_, number, _, definition) = identifier.legacyIdentity else { return XCTFail("Expected photographed footer route") }
            XCTAssertEqual(definition.tcgdexSetID, source.set.id)
            XCTAssertEqual(Int(number), Int(source.localId))
            let transport = BlisterFamilyProbeTransport(provider: probe)
            let catalog = BrowseCatalog(cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
                pokemonTransport: transport, checklistStore: reopened)
            await catalog.refreshCatalogNow()
            let detailRequests = await transport.detailRequests
            let setRequests = await transport.setRequests
            XCTAssertEqual(setRequests, 1)
            XCTAssertEqual(detailRequests, 0, "An unchanged probe must keep the saved source bytes")
            let page = try await catalog.cards(in: entry.set, cursor: nil)
            XCTAssertTrue(page.items.contains { $0.providerID == id && $0.masterSetVariant == cosmos })
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(entry.resource)), bytes)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("manifest.json")), manifestBytes)
            let configuration = ModelConfiguration(url: root.appendingPathComponent("holdings.store"), cloudKitDatabase: .none)
            let key = try autoreleasepool {
                let container = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
                return try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
                    try CollectionStore(context: context).add(identified,
                        resolved: .init(variant: cosmos, resolution: .userConfirmed)).collectionKey
                }
            }
            let reloaded = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
            let saved = try XCTUnwrap(CollectionStore(context: reloaded.mainContext).card(forKey: key))
            XCTAssertEqual(saved.providerID, id)
            XCTAssertEqual(saved.variant, cosmos)
            XCTAssertEqual(saved.quantity, 1)
            XCTAssertNil(PriceStore(context: reloaded.mainContext).record(forKey: saved.priceKey)?.effectiveUnitMarketPriceUSD)
        }
    }

    func testReportedUnpricedIdentitiesKeepReviewAndCurrencySafeguards() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reported-unpriced-review",
            withExtension: "json", subdirectory: "TradingCards/PokemonCatalogCoverageAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for entry in try XCTUnwrap(document["cases"] as? [[String: Any]]) {
            let source = try XCTUnwrap(entry["source"] as? [String: Any])
            let provider = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: source))
            let card = IdentifiedCard.pokemon(provider, setCode: "")
            switch provider.id {
            case "30th-c-004":
                XCTAssertEqual(provider.catalogVariants, [.holo])
                for run: PokemonPrintRun? in [nil, .unlimited] {
                    XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: card, variant: .holo, pokemonPrintRun: run),
                        [.tcgplayerID("716158")], "Existing mapping must survive an unavailable daily feed")
                }
                for variant: PhysicalVariant in [.normal, .reverse, .pokemonFoilPattern("cosmos")] {
                    XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: card, variant: variant).isEmpty)
                }
                for run: PokemonPrintRun in [.firstEdition, .shadowless] {
                    XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: card, variant: .holo, pokemonPrintRun: run).isEmpty)
                }
            case "me02.5-155", "me02.5-178":
                let finish = provider.id == "me02.5-155"
                    ? PhysicalVariant.resolving("pokemonStamp|holo|pokemon-center|") : .reverse
                XCTAssertTrue(PokemonVariantRules.requiresPhysicalReview(cardID: provider.id, variant: finish))
                XCTAssertNil(CardPricing.price(for: card, variant: finish, magicTreatments: []).value)
                XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: card, variant: finish).isEmpty)
                XCTAssertNil(PokemonFinishReconciliation.repair(storedVariantID: finish.id,
                    storedResolution: .userConfirmed, itemKind: .rawCard, printRun: nil, card: card))
            case "sv10.5w-021":
                let tinsel = PhysicalVariant.pokemonFoilPattern("tinsel")
                XCTAssertTrue(provider.catalogVariants.contains(tinsel))
                XCTAssertNil(CardPricing.price(for: card, variant: tinsel, magicTreatments: []).value)
                XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: card, variant: tinsel).isEmpty)
                XCTAssertNil(ProductFinish.printing(for: tinsel), "A flat Holofoil quote is not exact Tinsel proof")
            case "ex7-78":
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: card, variant: .normal, printRun: nil), 89455)
            default: XCTFail("Unreviewed case in retained fixture")
            }
        }
    }

    func testReportedSpinarakGradedIdentityRequiresExactFinishGradeAndQualifier() throws {
        let identity = GradedCardIdentity(name: "Spinarak", setName: "Team Rocket Returns",
            collectorNumber: "78", catalogID: "ex7-78", finish: .normal)
        let query = Dictionary(uniqueKeysWithValues: JustTCGV2GradedClient.requestQuery(identity: identity,
            game: .pokemon, setSlug: "team-rocket-returns-pokemon", companies: [.cgc], grades: ["10.0"]))
        XCTAssertEqual(query["grading_company"], "CGC")
        XCTAssertEqual(query["grade"], "10")
        XCTAssertEqual(query["set"], "team-rocket-returns-pokemon")
        XCTAssertEqual(query["regions"], "NA")
        let body = #"{"id":"synthetic-spinarak","name":"Spinarak","number":"78/109","game":{"id":"pokemon"},"set":{"id":"team-rocket-returns-pokemon","name":"EX Team Rocket Returns"}}"#
        let card = try JSONDecoder().decode(JustTCGV2Card.self, from: Data(body.utf8))
        XCTAssertTrue(identity.matches(card, game: .pokemon, expectedSetSlug: "team-rocket-returns-pokemon"))
        XCTAssertFalse(identity.matches(card, game: .pokemon, expectedSetSlug: "team-rocket-pokemon"))
        let owned = GradedSlabEvidence(company: .cgc, grade: .init(value: "10", label: "Gem Mint"),
            certificationNumber: nil, labelCardText: [], printedFinish: .normal)
        let exact = GradedVariant(id: "synthetic-cgc10", company: .cgc, grade: owned.grade,
            printing: "Normal", marketPriceUSD: 40, updatedAt: nil)
        XCTAssertEqual(ScannedGradedResolver.matchingVariant(in: [exact], for: owned), exact)
        for grade in [CardGrade(value: "9", label: "Mint"), .init(value: "10", label: "Pristine"),
                      .init(value: "10", label: "Gem Mint", qualifier: "OC")] {
            let wrong = GradedVariant(id: "synthetic-other-grade", company: .cgc, grade: grade,
                printing: "Normal", marketPriceUSD: 99, updatedAt: nil)
            XCTAssertNil(ScannedGradedResolver.matchingVariant(in: [wrong], for: owned))
        }
        let reverse = GradedVariant(id: "synthetic-reverse", company: .cgc, grade: owned.grade,
            printing: "Reverse Holofoil", marketPriceUSD: 99, updatedAt: nil)
        XCTAssertNil(ScannedGradedResolver.matchingVariant(in: [reverse], for: owned))
    }

    func testReportedCosmosChoicesUseOnlyTheirExactReviewedProduct() throws {
        let cosmos = PhysicalVariant.pokemonFoilPattern("cosmos")
        for entry in try reportedParallelCases() {
            let source = try XCTUnwrap(entry["source"] as? [String: Any])
            let provider = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: source))
            let product = try XCTUnwrap(entry["product"] as? [String: Any])
            let productID = try XCTUnwrap(product["productId"] as? Int)
            let card = IdentifiedCard.pokemon(provider, setCode: "")
            XCTAssertTrue(VariantResolver.options(for: card.variantEvidence).contains(cosmos), provider.id)
            XCTAssertEqual(VariantResolver.resolve(card.variantEvidence, finishLock: cosmos),
                .resolved(.init(variant: cosmos, resolution: .finishLock)), provider.id)
            for run: PokemonPrintRun? in [nil, .unlimited] {
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: card, variant: cosmos, printRun: run), productID, provider.id)
                XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: card, variant: cosmos, pokemonPrintRun: run),
                    [.tcgplayerID(String(productID))], provider.id)
            }
            for run: PokemonPrintRun in [.firstEdition, .shadowless] {
                XCTAssertNil(CardPricing.tcgplayerProductID(for: card, variant: cosmos, printRun: run), provider.id)
            }
            XCTAssertNil(CardPricing.price(for: card, variant: cosmos, magicTreatments: []).value,
                "The retained catalog has no USD Cosmos quote; flat Holo/Reverse cannot substitute")
            XCTAssertNotEqual(CardPricing.tcgplayerProductID(for: card, variant: .normal, printRun: nil), productID)
            XCTAssertNotEqual(CardPricing.tcgplayerProductID(for: card, variant: .reverse, printRun: nil), productID)

            var conflict = source
            var details = source["variants_detailed"] as? [[String: Any]] ?? []
            details.append(["type": "holo", "foil": "cosmos", "size": "standard", "thirdParty": ["tcgplayer": 999999]])
            conflict["variants_detailed"] = details
            let conflicting = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: conflict))
            XCTAssertNil(CardPricing.tcgplayerProductID(for: .pokemon(conflicting, setCode: ""), variant: cosmos, printRun: nil))
            if PokemonReviewedParallelCatalog.entry(cardID: provider.id) != nil {
                for field in ["name", "localId"] {
                    var wrong = source
                    wrong[field] = field == "name" ? "Unrelated Card" : "999"
                    let mismatched = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: wrong))
                    XCTAssertNil(CardPricing.tcgplayerProductID(for: .pokemon(mismatched, setCode: ""), variant: cosmos, printRun: nil))
                }
            }
        }
    }

    func testReportedCosmosChecklistProjectionRepairsCachedSlotsIdempotently() async throws {
        let loaded = await PokemonChecklistStore.shared.bundledSnapshot()
        let snapshot = try XCTUnwrap(loaded)
        for parallel in PokemonReviewedParallelCatalog.entries {
            let set = try XCTUnwrap(snapshot.entry(forProviderID: parallel.setID))
            let rows = try XCTUnwrap(snapshot.checklist(for: set.set.catalogID))
            let old = rows.filter { !($0.providerID == parallel.catalogID && $0.masterSetVariant == PokemonReviewedParallelCatalog.variant) }
            let repaired = PokemonChecklistReviewedProjection.cards(old)
            XCTAssertTrue(repaired.contains { $0.providerID == parallel.catalogID
                && $0.masterSetVariant == PokemonReviewedParallelCatalog.variant && $0.isExpandedMasterSetVariant }, parallel.catalogID)
            XCTAssertEqual(PokemonChecklistReviewedProjection.cards(repaired), repaired)
            XCTAssertEqual(Set(repaired.map(\.providerID)), Set(old.map(\.providerID)))
            XCTAssertEqual(Set(repaired.filter { $0.providerID != parallel.catalogID && $0.masterSetVariant?.id == "cosmos" }
                .map(\.providerID)), Set(rows.filter { $0.providerID != parallel.catalogID && $0.masterSetVariant?.id == "cosmos" }
                .map(\.providerID)))
        }
    }

    func testReportedCosmosRefreshListingRejectsOtherPhysicalProductsAndAmbiguousConditions() throws {
        for entry in try reportedParallelCases() {
            let product = try XCTUnwrap(entry["product"] as? [String: Any])
            let productID = String(try XCTUnwrap(product["productId"] as? Int))
            let id = try XCTUnwrap(entry["catalogID"] as? String)
            let target = MarketPriceTarget(priceKey: id + ":cosmos", game: .pokemon, printingID: id,
                variantID: "cosmos", itemKind: .rawCard, marketVariantID: nil,
                lookupCandidates: [.tcgplayerID(productID)], currentAmount: nil, lastCheckedAt: nil,
                exactPhysicalProductID: productID)
            let nm = #"{"uuid":"synthetic-nm","condition":"Near Mint","printing":"Holofoil","price":2.34}"#
            let lp = #"{"uuid":"synthetic-lp","condition":"Lightly Played","printing":"Holofoil","price":1.20}"#
            func result(product: String, listings: String) throws -> JustTCGRefreshCoordinator.ExactLookupResult {
                let response = try JSONDecoder().decode(JustTCGBatchResponse.self,
                    from: Data("{\"data\":[{\"uuid\":\"synthetic-card\",\"tcgplayerId\":\"\(product)\",\"variants\":[\(listings)]}]}".utf8))
                return JustTCGRefreshCoordinator.exactListing(lookup: .tcgplayerID(productID), owners: [target], response: response)
            }
            guard case let .matched(_, listing) = try result(product: productID, listings: lp + "," + nm) else {
                return XCTFail("Exact Cosmos product must admit its single Near Mint listing: \(id)")
            }
            XCTAssertEqual(listing.variantId, "synthetic-nm")
            for wrongProduct in ["684431", "685555", "686505", "534142", "534143"] where wrongProduct != productID {
                if case .matched = try result(product: wrongProduct, listings: nm) { XCTFail("Wrong physical product priced \(id)") }
            }
            if case .matched = try result(product: productID, listings: lp) { XCTFail("Played listing priced \(id)") }
            if case .matched = try result(product: productID, listings: nm + "," + nm) { XCTFail("Ambiguous listing priced \(id)") }
        }
    }

    @MainActor
    func testPokemonCatalogRetainsNewerMarketDataAcrossDirectAndCheckpointWrites() throws {
        let checkedAt = Date.now
        let retrievedAt = checkedAt.addingTimeInterval(-2 * 24 * 60 * 60)
        let olderData = retrievedAt.addingTimeInterval(-10 * 24 * 60 * 60)
        let cases: [(PriceSource, Date?)] = [
            (.tcgplayer, olderData), (.justTCG, olderData), (.tcgCSV, olderData), (.justTCG, nil)
        ]
        for checkpoint in [false, true] {
            for (source, sourceDate) in cases {
                let (container, context) = try makePriceContext()
                let original = NormalizedPrice(unitMarketPriceUSD: 12, currencyCode: "USD", source: source,
                    sourceVariantID: "original", sourceUpdatedAt: source == .tcgCSV ? nil : retrievedAt,
                    fetchedAt: retrievedAt)
                let seed = PriceStore(context: context)
                XCTAssertTrue(seed.store(.price(original), game: .pokemon, printingID: "card", variantID: "normal", at: retrievedAt))
                XCTAssertTrue(seed.recordFailure(game: .pokemon, printingID: "card", variantID: "normal",
                    at: checkedAt.addingTimeInterval(-60)))
                XCTAssertTrue(seed.save())

                let readContext = ModelContext(container)
                readContext.autosaveEnabled = false
                let store = PriceStore(context: readContext, checkpointsInFreshContext: checkpoint)
                XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 8, currencyCode: "USD", source: .tcgplayer,
                    sourceVariantID: "normal", sourceUpdatedAt: sourceDate, fetchedAt: checkedAt)),
                    game: .pokemon, printingID: "card", variantID: "normal", at: checkedAt))
                XCTAssertTrue(store.save())

                let verification = ModelContext(container)
                let record = try XCTUnwrap(PriceStore(context: verification).record(forKey: "pokemon:card:normal"))
                XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 12)
                XCTAssertEqual(record.source, source)
                XCTAssertEqual(record.sourceVariantID, original.sourceVariantID)
                XCTAssertEqual(record.sourceUpdatedAt, original.sourceUpdatedAt)
                XCTAssertEqual(record.fetchedAt, retrievedAt)
                XCTAssertEqual(record.lastSuccessfulCheckAt, checkedAt)
                XCTAssertEqual(record.lastCheckedAt, checkedAt)
                XCTAssertNil(record.lastFailureAt)
                XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceObservation>()).count, 1)
                XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceCheckDay>()).count, 2)
            }
        }
    }

    @MainActor
    func testPokemonCatalogFreshnessGuardAllowsRestatementImportAndInvalidationRecovery() throws {
        let retrievedAt = Date.now.addingTimeInterval(-120)
        let sourceDate = retrievedAt.addingTimeInterval(-60)
        let cases: [(source: PriceSource, sourceOffset: TimeInterval, invalidated: Bool)] = [
            (.tcgplayer, 0, false), (.tcgplayer, 30, false),
            (.importedCSV, -30, false), (.tcgplayer, -30, true)
        ]
        for scenario in cases {
            let (container, context) = try makePriceContext()
            let store = PriceStore(context: context)
            XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 12, currencyCode: "USD",
                source: scenario.source, sourceVariantID: "normal",
                sourceUpdatedAt: sourceDate, fetchedAt: retrievedAt)),
                game: .pokemon, printingID: "card", variantID: "normal", at: retrievedAt))
            if scenario.invalidated {
                XCTAssertNotNil(PriceObservationLog(context: context).recordInvalidation(
                    instrumentKey: "pokemon:card:normal", source: .tcgplayer, at: retrievedAt.addingTimeInterval(10)))
            }
            let candidateDate = sourceDate.addingTimeInterval(scenario.sourceOffset)
            XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 8, currencyCode: "USD", source: .tcgplayer,
                sourceVariantID: "normal", sourceUpdatedAt: candidateDate, fetchedAt: retrievedAt.addingTimeInterval(60))),
                game: .pokemon, printingID: "card", variantID: "normal", at: retrievedAt.addingTimeInterval(60)))
            XCTAssertTrue(store.save())
            let record = try XCTUnwrap(store.record(forKey: "pokemon:card:normal"))
            XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 8)
            XCTAssertEqual(record.sourceUpdatedAt, candidateDate)
            XCTAssertFalse(record.isInvalidated)
            if scenario.sourceOffset == 0 {
                XCTAssertEqual(PriceObservationLog(context: context).newestObservation(instrumentKey: record.key)?.kind, .sourceRestatement)
            }
            withExtendedLifetime(container) {}
        }
    }

    @MainActor
    func testCollectionRefreshCannotRegressNewerPokemonMarketData() async throws {
        let (container, context) = try makePriceContext()
        let card = try pokemonCard()
        let row = CollectedCard(collectionKey: "pokemon:refresh:normal", game: .pokemon,
            providerID: card.providerID, name: card.name, setName: card.setName, setCode: card.setCode,
            cardNumber: card.cardNumber, rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: .normal, variantResolution: .userConfirmed)
        context.insert(row)
        let retrievedAt = Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
        let store = PriceStore(context: context)
        XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 12, currencyCode: "USD", source: .justTCG,
            sourceVariantID: "vendor-normal", sourceUpdatedAt: retrievedAt, fetchedAt: retrievedAt)),
            game: .pokemon, printingID: row.priceStorageID, variantID: row.variantID, at: retrievedAt))
        XCTAssertTrue(store.save())
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setPokemonFetchOverrideForTesting { _ in card }
        let outcome = await worker.run(.init(usesPriceFallback: false, includeImported: true,
            forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
            markRecentlyCheckedIfEmpty: false, gradedOnly: false), progress: { _ in }, shouldContinue: nil)
        guard case let .completed(result) = outcome else { return XCTFail("Expected completed refresh") }
        XCTAssertFalse(result.persistenceFailed)
        let fresh = ModelContext(container)
        let record = try XCTUnwrap(PriceStore(context: fresh).record(forKey: row.priceKey))
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 12)
        XCTAssertEqual(record.source, .justTCG)
        XCTAssertEqual(record.fetchedAt, retrievedAt)
        XCTAssertGreaterThan(try XCTUnwrap(record.lastCheckedAt), retrievedAt)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<PriceObservation>()).count, 1)
    }

    @MainActor
    func testPokemonCatalogCanRepairAnIneligibleLegacyPrice() throws {
        for amount in [-1, Double.greatestFiniteMagnitude] {
            let (container, context) = try makePriceContext()
            let originalAt = Date.now.addingTimeInterval(-60)
            let record = PriceRecord(key: "pokemon:card:normal", game: .pokemon, printingID: "card", variantID: "normal")
            record.unitMarketPriceUSD = amount
            record.sourceRaw = PriceSource.justTCG.rawValue
            record.sourceVariantID = "invalid-legacy-quote"
            record.sourceUpdatedAt = originalAt
            record.fetchedAt = originalAt
            context.insert(record)
            try context.save()

            let store = PriceStore(context: context)
            XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 8, currencyCode: "USD", source: .tcgplayer,
                sourceVariantID: "normal", sourceUpdatedAt: originalAt.addingTimeInterval(-24 * 60 * 60), fetchedAt: .now)),
                game: .pokemon, printingID: "card", variantID: "normal"))
            XCTAssertTrue(store.save())
            XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 8)
            XCTAssertEqual(record.source, .tcgplayer)
            withExtendedLifetime(container) {}
        }
    }

    @MainActor
    func testBoundGradedMissesAdvanceRetryStateWithoutChangingPriceEvidence() async throws {
        let outcomes: [GradedVariantLookupResult] = [.noProductMatch, .cardFoundWithoutGradedVariants,
            .matched([.init(id: "different-listing", company: .cgc, grade: .init(value: "10"),
                printing: "Normal", marketPriceUSD: 30, updatedAt: nil)])]
        for hasPrice in [false, true] {
            for outcome in outcomes {
                let (container, context) = try makePriceContext()
                let row = gradedImport(name: "Bound", catalogID: "ex7-78", finish: .normal)
                row.justTCGVariantID = "owned-listing"
                row.justTCGAPIVersion = "v2"
                context.insert(row)
                let originalAt = Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
                let store = PriceStore(context: context)
                if hasPrice {
                    XCTAssertTrue(store.store(.price(.init(unitMarketPriceUSD: 12, currencyCode: "USD", source: .justTCG,
                        sourceVariantID: "owned-listing", sourceUpdatedAt: originalAt, fetchedAt: originalAt)),
                        game: .pokemon, printingID: row.priceStorageID, variantID: row.variantID, at: originalAt))
                }
                XCTAssertTrue(store.save())
                let worker = PriceRefreshModelActor(modelContainer: container)
                await worker.setGradedLookupOverrideForTesting { _, _ in outcome }
                let request = PriceRefreshRequest(usesPriceFallback: false, includeImported: true,
                    forceUnsupportedRetry: false, sortOldestFirst: true, maximumTargetCount: nil,
                    markRecentlyCheckedIfEmpty: false, gradedOnly: true)
                guard case let .completed(result) = await worker.run(request, progress: { _ in }, shouldContinue: nil) else {
                    return XCTFail("Expected completed graded lookup")
                }
                XCTAssertEqual(result.gradedLookupMisses, 1)
                XCTAssertFalse(result.persistenceFailed)
                let verification = ModelContext(container)
                let record = try XCTUnwrap(PriceStore(context: verification).record(forKey: row.priceKey))
                XCTAssertEqual(record.effectiveUnitMarketPriceUSD, hasPrice ? 12 : nil)
                XCTAssertEqual(record.fetchedAt, hasPrice ? originalAt : nil)
                XCTAssertEqual(record.lastSuccessfulCheckAt, hasPrice ? originalAt : nil)
                XCTAssertEqual(record.lastFailureReasonRaw, PricingDiagnosticReason.gradedVariantUnavailable.rawValue)
                XCTAssertNil(record.lastFailureAt)
                XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceObservation>()).count, hasPrice ? 1 : 0)
                XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceCheckDay>()).count, hasPrice ? 1 : 0)
                let targets = try PriceRefreshTargets.make(context: verification, usesPriceFallback: false, includeImported: true)
                let attemptedAt = try XCTUnwrap(record.lastCheckedAt)
                XCTAssertTrue(PriceRefreshController.staleTargets(from: targets, now: attemptedAt.addingTimeInterval(1)).isEmpty)
                XCTAssertEqual(PriceRefreshController.staleTargets(from: targets,
                    now: attemptedAt.addingTimeInterval(PriceRefreshController.automaticRefreshInterval)).count, 1)
                let nextWorker = PriceRefreshModelActor(modelContainer: container)
                await nextWorker.setGradedLookupOverrideForTesting { _, _ in
                    XCTFail("A completed miss must not be requested again immediately")
                    return outcome
                }
                guard case .noTargets = await nextWorker.run(request, progress: { _ in }, shouldContinue: nil) else {
                    return XCTFail("Expected recent graded miss to be skipped")
                }
            }
        }
    }

    @MainActor
    func testSelectedMarketVariantRefreshDoesNotInferADifferentFinish() async throws {
        for candidateID in ["selected-holo", "different-holo"] {
            let (container, context) = try makePriceContext()
            let row = gradedImport(name: "Selected listing", catalogID: "ex7-78", finish: nil)
            row.justTCGVariantID = "selected-holo"
            row.justTCGAPIVersion = "v2"
            context.insert(row)
            try context.save()
            let worker = PriceRefreshModelActor(modelContainer: container)
            await worker.setGradedLookupOverrideForTesting { _, _ in
                .matched([GradedVariant(id: candidateID, company: .cgc, grade: .init(value: "10"),
                    printing: "Holofoil", marketPriceUSD: 123, updatedAt: nil)])
            }
            guard case let .completed(result) = await worker.run(gradedRequest(), progress: { _ in }, shouldContinue: nil) else {
                return XCTFail("Expected completed refresh")
            }
            XCTAssertEqual(result.priced, candidateID == "selected-holo" ? 1 : 0)
            let fresh = ModelContext(container)
            let saved = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(saved.justTCGVariantID, "selected-holo")
            XCTAssertNil(saved.variant)
        }
    }

    @MainActor
    func testUnknownFinishRefreshStaysUnboundUntilConfirmed() async throws {
        let (container, context) = try makePriceContext()
        let row = gradedImport(name: "Unknown finish", catalogID: "ex7-78", finish: nil)
        context.insert(row)
        try context.save()
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setGradedLookupOverrideForTesting { _, _ in
            .matched([GradedVariant(id: "sole-holo", company: .cgc, grade: .init(value: "10"),
                printing: "Holofoil", marketPriceUSD: 123, updatedAt: nil)])
        }
        for _ in 0..<2 {
            guard case let .completed(result) = await worker.run(gradedRequest(), progress: { _ in }, shouldContinue: nil) else {
                return XCTFail("Expected completed refresh")
            }
            XCTAssertEqual(result.priced, 0)
            let fresh = ModelContext(container)
            let saved = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertNil(saved.justTCGVariantID)
            XCTAssertNil(PriceStore(context: fresh).record(forKey: saved.priceKey)?.effectiveUnitMarketPriceUSD)
        }
        row.variantID = PhysicalVariant.holo.id
        try context.save()
        guard case let .completed(result) = await worker.run(gradedRequest(), progress: { _ in }, shouldContinue: nil) else {
            return XCTFail("Expected confirmed refresh")
        }
        XCTAssertEqual(result.priced, 1)
        let fresh = ModelContext(container)
        let saved = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(saved.justTCGVariantID, "sole-holo")
        XCTAssertEqual(PriceStore(context: fresh).record(forKey: saved.priceKey)?.effectiveUnitMarketPriceUSD, 123)
    }

    @MainActor
    func testPriceSnapshotPublishesOneBatchAndKeepsForeignPriceDiagnostics() {
        let store = PriceSnapshotStore()
        let keys = (0..<200).map { "price-\($0)" }
        store.replace(with: PriceSnapshot(prices: [:],
            diagnosticsByCollectionKey: Dictionary(uniqueKeysWithValues: keys.map {
                ($0, PriceSnapshotDiagnostics(unpricedReason: .noExactVariantPrice, artworkReason: .lookupPending))
            }), priceStorageKeyByCollectionKey: Dictionary(uniqueKeysWithValues: keys.map { ($0, $0) })))
        var pricePublications = 0
        var diagnosticPublications = 0
        let prices = store.$prices.dropFirst().sink { _ in pricePublications += 1 }
        let diagnostics = store.$diagnosticsByCollectionKey.dropFirst().sink { _ in diagnosticPublications += 1 }
        defer { prices.cancel(); diagnostics.cancel() }
        var deltas = keys.map { PriceDelta(key: $0, display: PriceDisplay(amount: 10, source: .tcgplayer)) }
        deltas.append(PriceDelta(key: keys[0], display: PriceDisplay(amount: 12, source: .tcgplayer)))
        deltas.append(PriceDelta(key: keys[199], display: PriceDisplay(amount: 9, currencyCode: "EUR", source: .cardmarket)))

        store.apply(deltas)

        XCTAssertEqual(pricePublications, 1, "A checkpoint must not invalidate the collection once per price")
        XCTAssertEqual(diagnosticPublications, 1)
        XCTAssertEqual(store.display(for: keys[0])?.amount, 12)
        XCTAssertNil(store.diagnosticsByCollectionKey[keys[0]]?.unpricedReason)
        XCTAssertEqual(store.diagnosticsByCollectionKey[keys[0]]?.artworkReason, .lookupPending)
        XCTAssertEqual(store.diagnosticsByCollectionKey[keys[199]]?.unpricedReason, .noExactVariantPrice)
        let revision = store.revision
        store.apply(Array(deltas.suffix(2)))
        XCTAssertEqual(pricePublications, 1, "Repeated values must not publish again")
        XCTAssertEqual(diagnosticPublications, 1)
        XCTAssertEqual(store.revision, revision)
    }

    @MainActor
    func testGradedIncompletePassesAggregateAndKeepAttentionAndPriorState() async throws {
        for unresolved in [false, true] {
            for mixed in [false, true] {
                let (container, context) = try makePriceContext()
                let row = gradedImport(name: "Attention", catalogID: "ex7-78", finish: .normal)
                row.justTCGVariantID = "prior-variant"
                row.justTCGAPIVersion = "v2"
                context.insert(row)
                let at = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
                let record = PriceRecord(key: row.priceKey, game: .pokemon, printingID: row.priceStorageID, variantID: row.variantID)
                record.apply(.init(unitMarketPriceUSD: 12, currencyCode: "USD", source: .justTCG,
                    sourceVariantID: "prior-variant", sourceUpdatedAt: at, fetchedAt: at))
                record.gradedMarketCoverage = .init(status: .cardNotTracked)
                context.insert(record)
                let coverage = record.gradedMarketCoverage
                if mixed { context.insert(gradedImport(name: "Success", catalogID: "ex7-79", finish: .normal)) }
                try context.save()
                let worker = PriceRefreshModelActor(modelContainer: container)
                await worker.setGradedLookupOverrideForTesting { identity, _ in
                    if identity.name == "Success" {
                        return .matched([GradedVariant(id: "success-variant", cardID: "success-card",
                            company: .cgc, grade: .init(value: "10"), printing: "Normal", marketPriceUSD: 20, updatedAt: nil)])
                    }
                    return unresolved ? .localIdentityUnresolved : .incompleteSearch
                }
                let outcome = await worker.run(gradedRequest(), progress: { _ in }, shouldContinue: nil)
                guard case let .completed(result) = outcome else { return XCTFail("Expected completed bounded pass") }
                XCTAssertEqual(result.gradedIncompleteChecks, unresolved ? 0 : 1)
                XCTAssertEqual(result.gradedUnresolvedIdentities, unresolved ? 1 : 0)
                XCTAssertEqual(result.priced, mixed ? 1 : 0)
                XCTAssertEqual(result.failed, 0)
                XCTAssertEqual(result.gradedLookupMisses, 0)
                XCTAssertEqual(result.gradedTransportFailures, 0)
                let summary = PriceRefreshController.Summary(checkedAt: result.checkedAt, priced: result.priced,
                    failed: result.failed, latestSourceUpdate: result.latestSourceUpdate,
                    checkedUnstampedProvider: result.checkedUnstampedProvider, changedPrices: result.changedPrices,
                    foundNothingNewer: result.foundNothingNewer,
                    gradedIncompleteChecks: result.gradedIncompleteChecks,
                    gradedUnresolvedIdentities: result.gradedUnresolvedIdentities)
                XCTAssertFalse(PriceRefreshController.isTransientSuccessStatus(.finished(summary)))
                let presentation = CollectionRefreshStatusResolver.presentation(for: .init(status: .finished(summary), fallbackStatus: .idle))
                XCTAssertEqual(presentation?.isWarning, true)
                XCTAssertEqual(presentation?.isTransient, false)
                XCTAssertTrue(presentation?.message.contains(unresolved ? "identities" : "incomplete") == true)
                XCTAssertTrue(portfolioPriceRefreshMessage(summary).contains(unresolved ? "identities" : "incomplete"))
                let fresh = PriceStore(context: ModelContext(container))
                let retained = try XCTUnwrap(fresh.record(forKey: row.priceKey))
                XCTAssertEqual(retained.unitMarketPriceUSD, 12)
                XCTAssertEqual(retained.source, .justTCG)
                XCTAssertEqual(retained.sourceVariantID, "prior-variant")
                XCTAssertEqual(retained.fetchedAt, at)
                XCTAssertEqual(retained.sourceUpdatedAt, at)
                XCTAssertEqual(retained.lastSuccessfulCheckAt, at)
                XCTAssertEqual(retained.gradedMarketCoverage, coverage)
                XCTAssertEqual(retained.lastFailureReasonRaw, (unresolved ? PricingDiagnosticReason.gradedIdentityUnresolved : .gradedSearchIncomplete).rawValue)
                XCTAssertNil(retained.lastFailureAt)
            }
        }
    }

    @MainActor
    func testAcceptedJapaneseGradedImportKnownFinishThroughRefreshSelection() async throws {
        for (catalogID, finish, printing, expected) in [
            ("M2-001", PhysicalVariant.holo as PhysicalVariant?, "Holofoil - Japanese", true),
            ("M2-001", .holo, "Normal - Japanese", false),
            ("M2-001", .holo, "Holofoil", false),
            ("ex7-78", .holo, "Holofoil - Japanese", false),
            ("ex7-78", .holo, "Holofoil", true),
            ("M2-001", nil, "Holofoil - Japanese", false)
        ] {
            let (container, context) = try makePriceContext()
            let row = gradedImport(name: "Imported", catalogID: catalogID, finish: finish)
            context.insert(row)
            try context.save()
            let worker = PriceRefreshModelActor(modelContainer: container)
            await worker.setGradedLookupOverrideForTesting { identity, game in
                XCTAssertEqual(identity.vendorGame(for: game) == .pokemonJapan, catalogID == "M2-001")
                return .matched([GradedVariant(id: "localized-variant", cardID: "localized-card", company: .cgc,
                    grade: .init(value: "10"), printing: printing, marketPriceUSD: 30, updatedAt: nil)])
            }
            guard case let .completed(result) = await worker.run(gradedRequest(), progress: { _ in }, shouldContinue: nil) else {
                return XCTFail("Expected completed import refresh")
            }
            XCTAssertEqual(result.priced, expected ? 1 : 0, "\(catalogID) / \(printing)")
            let fresh = ModelContext(container)
            let refreshed = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(refreshed.justTCGVariantID, expected ? "localized-variant" : nil)
        }
    }

    private func gradedRequest() -> PriceRefreshRequest {
        .init(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false, gradedOnly: true)
    }

    @MainActor
    func testGradedCoverageWriterRejectsAnOutcomeForThePreviousPhysicalIdentity() async throws {
        let (container, context) = try makePriceContext()
        let row = gradedImport(name: "Corrected", catalogID: "ex7-78", finish: .holo)
        context.insert(row)
        try context.save()
        let writer = ScannerCollectionWriter(modelContainer: container)
        let coverage = GradedMarketCoverage(status: .gradeNotListed)
        for identity in [GradedBindingIdentity(finishID: PhysicalVariant.normal.id, printRun: nil),
                         .init(finishID: PhysicalVariant.holo.id, printRun: .firstEdition)] {
            let rejected = try await writer.recordGradedMarketCoverage(collectionKey: row.collectionKey,
                coverage: coverage, expectedIdentity: identity)
            XCTAssertFalse(rejected)
        }
        let verification = ModelContext(container)
        XCTAssertNil(PriceStore(context: verification).record(forKey: row.priceKey))
        let accepted = try await writer.recordGradedMarketCoverage(collectionKey: row.collectionKey,
            coverage: coverage, expectedIdentity: .init(finishID: PhysicalVariant.holo.id, printRun: nil))
        XCTAssertTrue(accepted)
        XCTAssertEqual(PriceStore(context: ModelContext(container)).record(forKey: row.priceKey)?.gradedMarketCoverage, coverage)
    }

    @MainActor
    func testLabelOnlyGradedImportCanBindAndRefreshWithoutANumericGrade() async throws {
        let (container, context) = try makePriceContext()
        let row = gradedImport(name: "Authentic", catalogID: "ex7-78", finish: .normal)
        row.gradeRaw = nil
        row.gradeLabel = "Authentic"
        context.insert(row)
        try context.save()
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.setGradedLookupOverrideForTesting { _, _ in
            .matched([GradedVariant(id: "authentic-variant", cardID: "authentic-card", company: .cgc,
                grade: .init(value: nil, label: "Authentic"), printing: "Normal",
                marketPriceUSD: 30, updatedAt: nil)])
        }

        guard case let .completed(result) = await worker.run(gradedRequest(), progress: { _ in }, shouldContinue: nil) else {
            return XCTFail("Expected a completed graded refresh")
        }
        XCTAssertEqual(result.priced, 1)
        let fresh = ModelContext(container)
        let refreshed = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(refreshed.justTCGVariantID, "authentic-variant")
        XCTAssertNil(refreshed.gradeRaw)
        XCTAssertEqual(refreshed.gradeLabel, "Authentic")
        XCTAssertEqual(PriceStore(context: fresh).record(forKey: refreshed.priceKey)?.effectiveUnitMarketPriceUSD, 30)
    }

    private func gradedImport(name: String, catalogID: String, finish: PhysicalVariant?) -> CollectedCard {
        let row = CollectedCard(collectionKey: "graded:fixture:\(name)", game: .pokemon, providerID: "csv:\(name)",
            name: name, setName: "Team Rocket Returns", setCode: "TRR", cardNumber: "78", rarity: nil,
            imageURL: nil, thumbnailURL: nil, variant: finish, variantResolution: .imported)
        row.catalogProviderID = catalogID
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        row.gradingCompanyRaw = GradingCompany.cgc.rawValue
        row.gradeRaw = "10"
        return row
    }

    func testReadableOldOverlayProjectsReviewedSlotsOfflineWithoutChangingSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("upgrade-\(UUID())")
        let store = PokemonChecklistStore(root: root)
        let bundled = await store.bundledSnapshot()
        let bundle = try XCTUnwrap(bundled)
        let bundledEntry = try XCTUnwrap(bundle.entry(forProviderID: "me02.5"))
        let probe = try JSONDecoder().decode(TCGdexSetCatalog.self, from: Data(#"{"id":"me02.5","name":"Ascended Heroes","cards":[{"id":"me02.5-155","localId":"155","name":"Zekrom"},{"id":"me02.5-178","localId":"178","name":"Terapagos"}],"cardCount":{"total":2,"official":2}}"#.utf8))
        let entry = PokemonChecklistSnapshotEntry(set: bundledEntry.set, providerID: bundledEntry.providerID,
            providerFingerprint: bundledEntry.providerFingerprint,
            providerProbeFingerprint: PokemonMasterSetChecklistBuilder.providerProbeFingerprint(of: probe),
            officialCount: bundledEntry.officialCount, standardSlotCount: bundledEntry.standardSlotCount,
            expandedSlotCount: bundledEntry.expandedSlotCount, resource: bundledEntry.resource)
        let current = try XCTUnwrap(bundle.checklist(for: entry.set.catalogID))
        let ids: Set<String> = ["me02.5-155", "me02.5-178"]
        var old: [CatalogCardSummary] = []
        var seen = Set<String>()
        for row in current {
            guard ids.contains(row.providerID) else { old.append(row); continue }
            guard seen.insert(row.providerID).inserted else { continue }
            for variant in [PhysicalVariant.normal, .holo, .reverse] {
                var value = row
                value.masterSetVariant = variant
                value.isExpandedMasterSetVariant = false
                value.isSoleSlotForCard = true // stale metadata must also be repaired
                old.append(value)
            }
        }
        let manifest = PokemonChecklistSnapshotManifest(schemaVersion: bundle.manifest.schemaVersion,
            rulesVersion: bundle.manifest.rulesVersion, generatedAt: bundle.manifest.generatedAt,
            directoryFingerprint: bundle.manifest.directoryFingerprint, entries: [entry])
        try await store.replace(.init(manifest: manifest, checklists: [entry.set.id: old]))
        let resource = root.appendingPathComponent(entry.resource)
        let before = try Data(contentsOf: resource)
        let manifestBefore = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        // Reopen like an upgraded installation. No provider is available or needed.
        let upgraded = PokemonChecklistStore(root: root)
        for _ in 0..<2 {
            let loaded = await upgraded.mergedChecklist(for: entry.set.catalogID)
            let repaired = try XCTUnwrap(loaded)
            for id in ids {
                let rows = repaired.filter { $0.providerID == id }
                let expected = PokemonMasterSetDefinition.requiredSlots(
                    for: try XCTUnwrap(PokemonVariantRules.reviewedVariants(cardID: id)), setProviderID: entry.providerID)
                XCTAssertEqual(rows.compactMap(\.masterSetVariant), expected.map(\.variant))
                XCTAssertEqual(rows.map(\.isExpandedMasterSetVariant), expected.map(\.isExpanded))
                XCTAssertTrue(rows.allSatisfy { !$0.isSoleSlotForCard })
            }
            XCTAssertEqual(repaired.filter { !ids.contains($0.providerID) }, old.filter { !ids.contains($0.providerID) })
            let entries = await upgraded.mergedEntries()
            let metadata = try XCTUnwrap(entries.first { $0.set.id == entry.set.id })
            XCTAssertEqual(metadata.standardSlotCount, repaired.filter { !$0.isExpandedMasterSetVariant }.count)
            XCTAssertEqual(metadata.expandedSlotCount, repaired.count)
            XCTAssertEqual(metadata.set.cardCount, repaired.count)
            XCTAssertEqual(metadata.providerProbeFingerprint, entry.providerProbeFingerprint)
            XCTAssertEqual(metadata.providerFingerprint, entry.providerFingerprint)
            let merged = await upgraded.mergedSnapshot()
            XCTAssertEqual(merged?.checklist(for: entry.set.catalogID), repaired)
            await upgraded.discardDecodedChecklists()
        }
        XCTAssertEqual(try Data(contentsOf: resource), before)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("manifest.json")), manifestBefore)
        let transport = UpgradeProbeTransport(provider: probe)
        let catalog = BrowseCatalog(cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport, checklistStore: upgraded)
        await catalog.refreshCatalogNow()
        let setRequests = await transport.setRequests
        let detailRequests = await transport.detailRequests
        XCTAssertEqual(setRequests, 1)
        XCTAssertEqual(detailRequests, 0, "An unchanged probe must skip rebuilding the old overlay")
        let page = try await catalog.cards(in: entry.set, cursor: nil)
        XCTAssertEqual(Set(page.items.filter { $0.providerID == "me02.5-178" }.compactMap { $0.masterSetVariant?.id }),
            ["holo", "loveBall", "energy"])
        XCTAssertEqual(try Data(contentsOf: resource), before)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("manifest.json")), manifestBefore)
    }

    func testEveryHiddenFatesShinyVaultIdentityUsesReviewedHoloEvidence() async throws {
        let store = PokemonChecklistStore()
        let loaded = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(loaded)
        let entry = try XCTUnwrap(snapshot.entry(forProviderID: "sma"))
        let rows = try XCTUnwrap(snapshot.checklist(for: entry.set.catalogID))
        XCTAssertEqual(rows.count, 94)
        XCTAssertEqual(Set(rows.map(\.providerID)), Set((1...94).map { "sma-SV\($0)" }))
        for row in rows {
            let detail = try hiddenFatesNormalPlaceholder(id: row.providerID, name: row.name)
            let card = IdentifiedCard.pokemon(detail, setCode: "SMA")
            XCTAssertEqual(detail.catalogVariants, [.holo], row.providerID)
            XCTAssertEqual(card.variantEvidence.catalogVariants, [.holo], row.providerID)
            XCTAssertEqual(VariantResolver.resolve(card.variantEvidence),
                           .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)), row.providerID)
            XCTAssertEqual(row.masterSetVariant, .holo, row.providerID)
            XCTAssertTrue(row.isSoleSlotForCard, row.providerID)
            XCTAssertFalse(row.isExpandedMasterSetVariant, row.providerID)
            XCTAssertTrue(PokemonVariantRules.requiresPhysicalReview(cardID: row.providerID, variant: .normal))
            XCTAssertFalse(PokemonVariantRules.requiresPhysicalReview(cardID: row.providerID, variant: .holo))
            for provenance in [VariantResolution.uniqueInCatalog, .userConfirmed, .finishLock, .printedLabel, .imported] {
                XCTAssertNil(PokemonFinishReconciliation.repair(storedVariantID: "normal",
                    storedResolution: provenance, itemKind: .rawCard, printRun: nil, card: card))
            }
        }
        for unreviewed in ["sma-SV0", "sma-SV95", "sma-SV01", "sma-1", "sm115-1", "swsh4.5sv-SV001"] {
            XCTAssertNil(PokemonVariantRules.reviewedVariants(cardID: unreviewed), unreviewed)
        }
    }

    func testHiddenFatesRepairsPersistedNormalSlotsWithoutRewritingSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hidden-fates-upgrade-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root)
        let loaded = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(loaded)
        let entry = try XCTUnwrap(snapshot.entry(forProviderID: "sma"))
        let current = try XCTUnwrap(snapshot.checklist(for: entry.set.catalogID))
        let old = current.map { row in
            var value = row
            value.masterSetVariant = .normal
            return value
        }
        let manifest = PokemonChecklistSnapshotManifest(schemaVersion: snapshot.manifest.schemaVersion,
            rulesVersion: snapshot.manifest.rulesVersion, generatedAt: snapshot.manifest.generatedAt,
            directoryFingerprint: snapshot.manifest.directoryFingerprint, entries: [entry])
        try await store.replace(.init(manifest: manifest, checklists: [entry.set.id: old]))
        let resource = root.appendingPathComponent(entry.resource)
        let before = try Data(contentsOf: resource)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifestBefore = try Data(contentsOf: manifestURL)
        let upgraded = PokemonChecklistStore(root: root)
        for _ in 0..<2 {
            let loaded = await upgraded.mergedChecklist(for: entry.set.catalogID)
            let repaired = try XCTUnwrap(loaded)
            XCTAssertEqual(repaired.count, 94)
            XCTAssertEqual(Set(repaired.map(\.providerID)), Set(old.map(\.providerID)))
            XCTAssertTrue(repaired.allSatisfy { $0.masterSetVariant == .holo && $0.isSoleSlotForCard && !$0.isExpandedMasterSetVariant })
            XCTAssertEqual(PokemonChecklistReviewedProjection.cards(repaired), repaired)
            let entries = await upgraded.mergedEntries()
            let metadata = try XCTUnwrap(entries.first { $0.providerID == "sma" })
            XCTAssertEqual(metadata.set.cardCount, 94)
            XCTAssertEqual(metadata.standardSlotCount, 94)
            XCTAssertEqual(metadata.expandedSlotCount, 94)
            XCTAssertEqual(metadata.officialCount, entry.officialCount)
            XCTAssertEqual(metadata.providerFingerprint, entry.providerFingerprint)
            XCTAssertEqual(metadata.providerProbeFingerprint, entry.providerProbeFingerprint)
            await upgraded.discardDecodedChecklists()
        }
        XCTAssertEqual(try Data(contentsOf: resource), before)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBefore)
    }

    func testHiddenFatesUsesOnlyARealHoloQuoteAndRejectsTheOldNormalFinish() throws {
        let detail = try hiddenFatesNormalPlaceholder(id: "sma-SV1", name: "Scyther",
            pricing: ["tcgplayer": ["normal": ["marketPrice": 999], "holofoil": ["marketPrice": 7]]])
        let card = IdentifiedCard.pokemon(detail, setCode: "SMA")
        XCTAssertNil(CardPricing.price(for: card, variant: .normal, magicTreatments: []).value)
        XCTAssertEqual(CardPricing.price(for: card, variant: .holo, magicTreatments: []).value, 7)
        let missingQuote = IdentifiedCard.pokemon(try hiddenFatesNormalPlaceholder(id: "sma-SV1", name: "Scyther",
            pricing: ["tcgplayer": ["normal": ["marketPrice": 999]]]), setCode: "SMA")
        XCTAssertNil(CardPricing.price(for: missingQuote, variant: .holo, magicTreatments: []).value)
    }

    private func hiddenFatesNormalPlaceholder(id: String, name: String, pricing: [String: Any] = [:]) throws -> TCGdexCard {
        let object: [String: Any] = ["id": id, "localId": String(id.dropFirst("sma-".count)), "name": name,
            "set": ["id": "sma", "name": "Hidden Fates Shiny Vault", "cardCount": ["total": 94, "official": 94]],
            "variants": ["firstEdition": false, "holo": false, "normal": true, "reverse": false],
            "variants_detailed": [["type": "normal", "size": "standard", "variantId": "generated"]],
            "pricing": pricing]
        return try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testYellowARepairsBundledAndOldOfflineChecklistSlotsWithoutRewritingSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yellow-a-upgrade-\(UUID())")
        let store = PokemonChecklistStore(root: root)
        let bundled = await store.bundledSnapshot()
        let bundle = try XCTUnwrap(bundled)
        let entry = try XCTUnwrap(bundle.entry(forProviderID: "xya"))
        let current = try XCTUnwrap(bundle.checklist(for: entry.set.catalogID))
        let expected: [String: Set<PhysicalVariant>] = [
            "xya-24a": [.holo], "xya-28a": [.holo], "xya-54a": [.holo], "xya-55a": [.holo],
            "xya-92a": [.normal, .holo], "xya-107a": [.normal, .holo]
        ]
        func assertSlots(_ cards: [CatalogCardSummary], file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(cards.count, 8, file: file, line: line)
            XCTAssertEqual(Set(cards.map(\.providerID)), Set(expected.keys), file: file, line: line)
            for (id, variants) in expected {
                let rows = cards.filter { $0.providerID == id }
                XCTAssertEqual(Set(rows.compactMap(\.masterSetVariant)), variants, file: file, line: line)
                XCTAssertTrue(rows.allSatisfy { $0.isSoleSlotForCard == (variants.count == 1) }, file: file, line: line)
                XCTAssertTrue(rows.allSatisfy { !$0.isExpandedMasterSetVariant }, file: file, line: line)
            }
        }
        assertSlots(current)
        var seen = Set<String>()
        let old = current.compactMap { row -> CatalogCardSummary? in
            guard seen.insert(row.providerID).inserted else { return nil }
            var value = row
            value.masterSetVariant = .normal
            value.isExpandedMasterSetVariant = false
            value.isSoleSlotForCard = true
            return value
        }
        XCTAssertEqual(old.count, 6)
        let manifest = PokemonChecklistSnapshotManifest(schemaVersion: bundle.manifest.schemaVersion,
            rulesVersion: bundle.manifest.rulesVersion, generatedAt: bundle.manifest.generatedAt,
            directoryFingerprint: bundle.manifest.directoryFingerprint, entries: [entry])
        try await store.replace(.init(manifest: manifest, checklists: [entry.set.id: old]))
        let resource = root.appendingPathComponent(entry.resource)
        let before = try Data(contentsOf: resource)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifestBefore = try Data(contentsOf: manifestURL)
        let upgraded = PokemonChecklistStore(root: root)
        for _ in 0..<2 {
            let loaded = await upgraded.mergedChecklist(for: entry.set.catalogID)
            assertSlots(try XCTUnwrap(loaded))
            let entries = await upgraded.mergedEntries()
            let repaired = try XCTUnwrap(entries.first { $0.providerID == "xya" })
            XCTAssertEqual(repaired.set.cardCount, 8)
            XCTAssertEqual(repaired.standardSlotCount, 8)
            XCTAssertEqual(repaired.expandedSlotCount, 8)
            XCTAssertEqual(repaired.officialCount, entry.officialCount)
            XCTAssertEqual(repaired.providerFingerprint, entry.providerFingerprint)
            XCTAssertEqual(repaired.providerProbeFingerprint, entry.providerProbeFingerprint)
            let snapshot = await upgraded.mergedSnapshot()
            assertSlots(try XCTUnwrap(snapshot?.checklist(for: entry.set.catalogID)))
            await upgraded.discardDecodedChecklists()
        }
        XCTAssertEqual(try Data(contentsOf: resource), before)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBefore)
    }

    func testNilPrintRunSoleStampedHoloNeedsExactObjectQuoteAndProduct() throws {
        func card(extra: [[String: Any]] = [], product: Int? = 123, quoteProduct: Int = 123,
                  quote: Bool = true, normal: Bool = false, listing: String = "holofoil") throws -> IdentifiedCard {
            var detail: [String: Any] = ["type": "holo", "size": "standard", "stamp": ["set-logo"]]
            if let product { detail["thirdParty"] = ["tcgplayer": product] }
            if quote { detail["pricing"] = ["tcgplayer": [listing: ["marketPrice": 25, "productId": quoteProduct]]] }
            let object: [String: Any] = ["id": "mep-083", "localId": "083", "name": "Slowbro",
                "set": ["id": "mep", "name": "Mega Evolution Promos", "cardCount": ["total": 89, "official": 0]],
                "variants": ["firstEdition": false, "holo": true, "normal": normal, "reverse": false],
                "variants_detailed": [detail] + extra]
            return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object)), setCode: "MEP")
        }
        let sole = try card()
        XCTAssertEqual(sole.variantEvidence.catalogVariants, [.holo])
        XCTAssertEqual(CardPricing.price(for: sole, variant: .holo, magicTreatments: []).value, 25)
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: sole, variant: .holo, printRun: nil), 123)
        for run in [PokemonPrintRun.unlimited, .firstEdition, .shadowless] {
            XCTAssertNil(CardPricing.price(for: sole, variant: .holo, magicTreatments: [], pokemonPrintRun: run).value)
            XCTAssertNil(CardPricing.tcgplayerProductID(for: sole, variant: .holo, printRun: run))
        }
        for unsafe in [try card(extra: [["type": "holo", "stamp": ["staff"]]]),
                       try card(product: 999), try card(product: nil, quoteProduct: 0), try card(quote: false),
                       try card(normal: true), try card(listing: "reverse-holofoil")] {
            XCTAssertNil(CardPricing.price(for: unsafe, variant: .holo, magicTreatments: []).value)
            XCTAssertNil(CardPricing.tcgplayerProductID(for: unsafe, variant: .holo, printRun: nil))
        }
    }

    private func recordedPokemon(_ id: String) throws -> TCGdexCard {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: id, withExtension: "json",
            subdirectory: "TradingCards/PricingIdentity"))
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(contentsOf: url))
    }

    func testRecordedReportedObjectsKeepIdentityAndQuoteBoundaries() throws {
        let zekrom = try recordedPokemon("me02.5-155")
        let promo = try recordedPokemon("mep-031")
        let stamp = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .holo, stamps: ["pokemon-center"]))
        XCTAssertFalse(zekrom.catalogVariants.contains(stamp))
        XCTAssertTrue(promo.catalogVariants.contains(stamp))
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: .pokemon(promo, setCode: "MEP"), variant: stamp, printRun: .unlimited), 680481)
        XCTAssertNil(CardPricing.price(for: .pokemon(promo, setCode: "MEP"), variant: stamp, magicTreatments: []).value)
        XCTAssertNil(CardPricing.tcgplayerProductID(for: .pokemon(zekrom, setCode: "ASC"), variant: stamp, printRun: nil))
        let terapagos = try recordedPokemon("me02.5-178")
        XCTAssertEqual(Set(terapagos.catalogVariants.map(\.id)), ["holo", "loveBall", "energy"])
        XCTAssertFalse(terapagos.catalogVariants.contains(.reverse))
        let plain = try pokemonCard()
        XCTAssertTrue(plain.variantEvidence.catalogVariants.contains(.reverse))
    }

    @MainActor
    func testFreshPromoEvidenceConflictsWithStoredProductAndStoredStampIsNotProof() throws {
        let promo = IdentifiedCard.pokemon(try recordedPokemon("mep-031"), setCode: "MEP")
        let stamp = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .holo, stamps: ["pokemon-center"]))
        let row = CollectedCard(card: promo, resolved: .init(variant: stamp, resolution: .userConfirmed))
        row.tcgplayerProductID = "111"
        row.justTCGCardID = "outgoing"
        row.justTCGVariantID = "outgoing-variant"
        let stored = PriceFallbackCardInput(card: row, variant: stamp, pokemonPrintRun: .unlimited)
        XCTAssertNil(stored.exactPhysicalProductID)
        XCTAssertTrue(stored.lookupCandidates.isEmpty)
        var target = PriceTarget(game: .pokemon, printingID: "mep-031", catalogPrintingID: "mep-031",
            setCode: "MEP", variantID: stamp.id, importedIdentity: nil,
            catalogMetadataCheckedAt: nil, lastFailureAt: nil, hasPrice: false, lastCheckedAt: nil, justTCGFetchedAt: nil)
        target.tcgplayerProductID = "111"
        target.justTCGCardID = "outgoing"
        let candidate = PriceRefreshController.FallbackCandidate(target: target, card: promo)
        XCTAssertEqual(candidate.externalLookups, [.tcgplayerID("680481")])
        XCTAssertEqual(candidate.exactPhysicalProductID, "680481")
        XCTAssertFalse(candidate.permitsStoredHandles)
        PriceRefreshController.applyVendorBinding(to: row, productID: "680481", sku: "verified-sku",
            exactProductID: "680481", cardID: "verified-promo", variantID: "verified-stamped")
        XCTAssertEqual(row.tcgplayerProductID, "680481")
        XCTAssertEqual(row.justTCGCardID, "verified-promo")
        XCTAssertEqual(row.justTCGVariantID, "verified-stamped")
        XCTAssertEqual(row.tcgplayerURL, "https://www.tcgplayer.com/product/680481")
    }

    func testReviewedChecklistRegenerationUsesRecordedEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reviewed-checklist-\(UUID())")
        let store = PokemonChecklistStore(root: root)
        let bundled = await store.bundledSnapshot()
        let original = try XCTUnwrap(bundled)
        try await store.replace(original)
        try await PokemonChecklistSnapshotGenerator.rebuildReviewedCards(root: root,
            cards: [recordedPokemon("me02.5-155"), recordedPokemon("me02.5-178")])
        let downloaded = await PokemonChecklistStore(root: root, bundle: nil).downloadedSnapshot()
        let regenerated = try XCTUnwrap(downloaded)
        XCTAssertEqual(regenerated.manifest.entries.count, original.manifest.entries.count)
        let entry = try XCTUnwrap(regenerated.entry(forProviderID: "me02.5"))
        let summaries = try XCTUnwrap(regenerated.checklist(for: entry.set.catalogID))
        XCTAssertEqual(Set(summaries.filter { $0.providerID == "me02.5-178" }.compactMap { $0.masterSetVariant?.id }),
            ["holo", "loveBall", "energy"])
        XCTAssertEqual(summaries.filter { $0.providerID != "me02.5-155" && $0.providerID != "me02.5-178" }.count,
            original.checklist(for: entry.set.catalogID)?.filter { $0.providerID != "me02.5-155" && $0.providerID != "me02.5-178" }.count)
        print("Reviewed checklist regenerated at: \(root.path)")
    }

    @MainActor
    func testUSDExclusionExportRetainsNativeQuoteAndLatestFailureSeparately() throws {
        let (container, context) = try makePriceContext()
        defer { withExtendedLifetime(container) {} }
        let card = try pokemonCard()
        let first = CollectedCard(card: card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        first.quantity = 1
        let second = CollectedCard(card: card, resolved: .init(variant: .holo, resolution: .userConfirmed))
        let foreign = CollectedCard(card: card, resolved: .init(variant: .reverse, resolution: .userConfirmed))
        context.insert(first)
        context.insert(second)
        context.insert(foreign)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PriceRecord(key: foreign.priceKey, game: .pokemon, printingID: foreign.priceStorageID, variantID: foreign.variantID)
        record.apply(.init(unitMarketPriceUSD: 12.5, currencyCode: "EUR", source: .cardmarket,
            sourceVariantID: "synthetic-native", sourceUpdatedAt: at, fetchedAt: at))
        record.applyUnavailable(source: .tcgplayer, at: at.addingTimeInterval(60))
        XCTAssertEqual(record.fetchedAt, at)
        context.insert(record)
        let exported = CollectionCSV.exportUnpriced([first, second, foreign], priceRecords: [record]).text
        XCTAssertEqual(exported.split(separator: "\n").count, 4, "Two unpriced copies plus one EUR copy produce three rows")
        XCTAssertTrue(exported.contains("retained_native_amount,retained_native_currency"))
        XCTAssertTrue(exported.contains("12.5,EUR"))
        XCTAssertTrue(exported.contains(PricingDiagnosticReason.otherCurrency.rawValue))
        record.lastFailureReasonRaw = PricingDiagnosticReason.missingMarketMapping.rawValue
        record.recordFailure(at: at.addingTimeInterval(120))
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: foreign, record: record), .providerRequestFailed)
        XCTAssertEqual(record.fetchedAt, at)
        let failedExport = CollectionCSV.exportUnpriced([foreign], priceRecords: [record]).text
        let lines = failedExport.split(separator: "\n")
        let fields = Dictionary(uniqueKeysWithValues: zip(
            lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init),
            lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)))
        XCTAssertEqual(fields["valuation_exclusion_reason"], PricingDiagnosticReason.otherCurrency.rawValue)
        XCTAssertEqual(fields["latest_attempt_status"], "refresh_failed")
        XCTAssertEqual(fields["latest_attempt_reason"], PricingDiagnosticReason.providerRequestFailed.rawValue)
        XCTAssertEqual(fields["retained_native_amount"], "12.5")
        XCTAssertEqual(fields["retained_native_currency"], "EUR")
        XCTAssertEqual(fields["retained_quote_fetched_at"], ISO8601DateFormatter().string(from: at))
        XCTAssertEqual(fields["retained_quote_updated_at"], ISO8601DateFormatter().string(from: at))
        XCTAssertEqual(record.sourceUpdatedAt, at)
        XCTAssertEqual(record.fetchedAt, at)
        XCTAssertEqual(PricingDiagnostics.valuationExclusionReason(for: first, record: nil), .notChecked)
        let usd = PriceRecord(key: first.priceKey, game: .pokemon, printingID: first.priceStorageID, variantID: first.variantID)
        usd.apply(.init(unitMarketPriceUSD: 10, currencyCode: "USD", source: .tcgplayer,
            sourceVariantID: "normal", sourceUpdatedAt: at, fetchedAt: at))
        XCTAssertNil(PricingDiagnostics.valuationExclusionReason(for: first, record: usd))
        XCTAssertEqual(CollectionCSV.exportUnpriced([first], priceRecords: [usd]).text.split(separator: "\n").count, 1,
            "A successful USD row is excluded from the unpriced export")
        let neverPriced = CollectionCSV.exportUnpriced([second], priceRecords: []).text
        XCTAssertTrue(neverPriced.contains("never_checked"))
        XCTAssertTrue(neverPriced.contains(",not_checked,,,"))
    }

    @MainActor
    func testNewlyResolvedRawIdentityExplainsRetryWithoutOverridingInvalidQuotes() throws {
        let card = CollectedCard(card: try pokemonCard(),
            resolved: .init(variant: .normal, resolution: .userConfirmed))
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PriceRecord(key: card.priceKey, game: .pokemon,
            printingID: card.priceStorageID, variantID: card.variantID)
        record.recordFailure(at: checkedAt)
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .providerRequestFailed)
        card.catalogProviderID = card.providerID
        card.catalogMetadataCheckedAt = checkedAt
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .providerRequestFailed)
        card.catalogMetadataCheckedAt = checkedAt.addingTimeInterval(60)
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .identityResolvedAfterFailedCheck)
        record.lastFailureReasonRaw = PricingDiagnosticReason.invalidProviderQuote.rawValue
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .invalidProviderQuote)
        record.lastFailureReasonRaw = nil
        card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .providerRequestFailed,
            "Resolving the raw card does not establish a graded listing")
        card.itemKindRaw = CollectionItemKind.rawCard.rawValue
        card.catalogProviderID = "xya-24a"
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .providerRequestFailed,
            "An unsupported physical finish must not be described as ready to price")
    }

    @MainActor
    func testIncompleteAndFailedAttemptsRetainPriorGradedCoverageWithoutNegativeCaching() throws {
        let (container, context) = try makePriceContext()
        defer { withExtendedLifetime(container) {} }
        let card = CollectedCard(card: try pokemonCard(), resolved: .init(variant: .normal, resolution: .userConfirmed))
        card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        card.gradingCompanyRaw = GradingCompany.cgc.rawValue
        card.gradeRaw = "10"
        context.insert(card)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let store = PriceStore(context: context)
        XCTAssertTrue(store.recordGradedMarketCoverage(.init(status: .cardNotTracked),
            game: .pokemon, printingID: card.priceStorageID, variantID: card.variantID, at: at))
        let record = try XCTUnwrap(store.record(forKey: card.priceKey))
        for (index, reason) in [PricingDiagnosticReason.gradedSearchIncomplete, .gradedIdentityUnresolved].enumerated() {
            XCTAssertTrue(store.recordLookupStatus(reason, game: .pokemon, printingID: card.priceStorageID,
                variantID: card.variantID, at: at.addingTimeInterval(Double(index + 1) * 60)))
            XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), reason)
            XCTAssertEqual(record.lastSuccessfulCheckAt, at)
            XCTAssertEqual(record.gradedMarketCoverage?.status, .cardNotTracked)
        }
        XCTAssertTrue(store.recordFailure(game: .pokemon, printingID: card.priceStorageID,
            variantID: card.variantID, at: at.addingTimeInterval(180)))
        XCTAssertEqual(PricingDiagnostics.unpricedReason(for: card, record: record), .providerRequestFailed)
        XCTAssertEqual(record.gradedMarketCoverage?.status, .cardNotTracked)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testReportedExactObjectsDoNotBorrowPrices() throws {
        func card(_ id: String, _ details: String, flat: String = "") throws -> IdentifiedCard {
            let json = """
            {"id":"\(id)","localId":"178","name":"Fixture",
             "set":{"id":"me02.5","name":"Ascended Heroes","cardCount":{"total":200,"official":200}},
             "variants":{"normal":false,"holo":true,"reverse":true,"firstEdition":false},
             "variants_detailed":[\(details)]\(flat)}
            """
            return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "ASC")
        }
        let stamp = PokemonCatalogStampVariant.make(base: .holo, stamps: ["pokemon-center"], subtype: nil)
        let exact = #"{"type":"holo","stamp":["pokemon-center"],"thirdParty":{"tcgplayer":123},"pricing":{"tcgplayer":{"holofoil":{"marketPrice":25}}}}"#
        let stamped = try card("fixture-stamp", exact)
        for run: PokemonPrintRun? in [nil, .unlimited] {
            XCTAssertEqual(CardPricing.price(for: stamped, variant: stamp, magicTreatments: [], pokemonPrintRun: run).value, 25)
            XCTAssertEqual(CardPricing.tcgplayerProductID(for: stamped, variant: stamp, printRun: run), 123)
        }
        let conflict = try card("fixture-conflict", exact + "," + exact.replacingOccurrences(of: "123", with: "456"))
        XCTAssertNil(CardPricing.price(for: conflict, variant: stamp, magicTreatments: []).value)
        let missing = #"{"type":"holo","thirdParty":{"tcgplayer":123}}"#
        let flat = #", "pricing":{"tcgplayer":{"holofoil":{"productId":456,"marketPrice":99}}}"#
        XCTAssertNil(CardPricing.price(for: try card("me02.5-155", missing, flat: flat), variant: .holo, magicTreatments: []).value)
        let patterns = #"{"type":"holo"},{"type":"reverse","foil":"love-ball"},{"type":"reverse","foil":"energy"}"#
        let terapagos = try card("me02.5-178", patterns)
        guard case let .pokemon(provider, _) = terapagos.legacyIdentity else { return XCTFail() }
        XCTAssertFalse(provider.catalogVariants.contains(.reverse))
        XCTAssertNil(CardPricing.price(for: terapagos, variant: .reverse, magicTreatments: []).value)
        let sameProductFlat = flat.replacingOccurrences(of: "456", with: "123")
        XCTAssertEqual(CardPricing.price(for: try card("fixture-flat", missing, flat: sameProductFlat),
            variant: .holo, magicTreatments: []).value, 99)
        let internalConflict = exact.replacingOccurrences(of: #""marketPrice":25"#, with: #""productId":456,"marketPrice":25"#)
        XCTAssertNil(CardPricing.price(for: try card("fixture-internal-conflict", internalConflict),
            variant: stamp, magicTreatments: []).value)
        XCTAssertNil(CardPricing.tcgplayerProductID(for: try card("fixture-internal-conflict", internalConflict),
            variant: stamp, printRun: nil))
    }

    func testReviewedSetWideAnniversaryStampKeepsItsExactHoloQuote() throws {
        let json = #"{"id":"30th-001","localId":"001","name":"Exeggcute","set":{"id":"30th","name":"30th Celebration","cardCount":{"total":128,"official":128}},"variants_detailed":[{"type":"holo","stamp":["30th-anniversary"],"thirdParty":{"tcgplayer":716435},"pricing":{"tcgplayer":{"holofoil":{"productId":716435,"marketPrice":25}}}}]}"#
        let provider = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        XCTAssertEqual(provider.catalogVariants, [.holo])
        let card = IdentifiedCard.pokemon(provider, setCode: "30TH")
        XCTAssertEqual(CardPricing.price(for: card, variant: .holo, magicTreatments: [], pokemonPrintRun: .unlimited).value, 25)
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: card, variant: .holo, printRun: .unlimited), 716435)
    }

    @MainActor
    func testMappingGapPreservesQuoteAndDoesNotInventProviderChecksOrOwnership() throws {
        let (container, context) = try makePriceContext()
        defer { withExtendedLifetime(container) {} }
        let store = PriceStore(context: context)
        let at = Date.now.addingTimeInterval(-60)
        let quote = NormalizedPrice(unitMarketPriceUSD: 42, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "exact", sourceUpdatedAt: nil, fetchedAt: at)
        XCTAssertTrue(store.store(.price(quote), game: .pokemon, printingID: "fixture", variantID: "holo", at: at))
        XCTAssertTrue(store.save())
        let observations = try context.fetchCount(FetchDescriptor<PriceObservation>())
        let checks = try context.fetchCount(FetchDescriptor<PriceCheckDay>())
        let key = PriceRecord.key(game: .pokemon, printingID: "fixture", variantID: "holo")
        let successfulAt = store.record(forKey: key)?.lastSuccessfulCheckAt
        XCTAssertTrue(store.recordMissingMapping(game: .pokemon, printingID: "fixture", variantID: "holo"))
        XCTAssertTrue(store.save())
        let record = try XCTUnwrap(store.record(forKey: key))
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 42)
        XCTAssertEqual(record.lastSuccessfulCheckAt, successfulAt)
        XCTAssertNil(record.lastFailureAt)
        XCTAssertEqual(record.lastFailureReasonRaw, PricingDiagnosticReason.missingMarketMapping.rawValue)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PriceObservation>()), observations)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PriceCheckDay>()), checks)
    }
    @MainActor
    func testCachedBrowseDetailsCannotRestampAnOldPriceOverANewerQuote() throws {
        let (container, context) = try makePriceContext()
        defer { withExtendedLifetime(container) {} }
        let retrievedAt = Date.now.addingTimeInterval(-7_200)
        let card = try magicCard()
        let details = CatalogCardDetails(
            card: card,
            set: CatalogSet(
                catalogID: CatalogSetID(game: .magic, providerID: "ecl"),
                name: "Eclipse", code: "ECL", logoURL: nil, symbolURL: nil,
                cardCount: 1, releaseDate: nil, sortRank: 0
            ),
            retrievedAt: retrievedAt
        )
        let printingID = "cached-browse"
        let newerAt = Date.now.addingTimeInterval(-60)
        let initial = PriceStore(context: context)
        XCTAssertTrue(initial.store(.price(NormalizedPrice(
            unitMarketPriceUSD: 20, currencyCode: "USD", source: .scryfall,
            sourceVariantID: "usd_foil", sourceUpdatedAt: nil, fetchedAt: newerAt
        )), game: .magic, printingID: printingID, variantID: "foil", at: newerAt))
        XCTAssertTrue(initial.save())

        let readContext = ModelContext(container)
        readContext.autosaveEnabled = false
        let addPriceStore = PriceStore(context: readContext, checkpointsInFreshContext: true)
        let cachedLookup = CardPricing.price(
            for: details.card, variant: .foil, magicTreatments: [], at: details.retrievedAt
        )
        XCTAssertTrue(addPriceStore.store(cachedLookup, game: .magic, printingID: printingID,
                                          variantID: "foil", at: details.retrievedAt))
        XCTAssertTrue(addPriceStore.save())
        let verification = ModelContext(container)
        let record = try XCTUnwrap(PriceStore(context: verification).record(
            forKey: "magic:cached-browse:foil"
        ))
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 20)
        XCTAssertEqual(record.fetchedAt, newerAt)
        XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceObservation>()).count, 1)
    }

    @MainActor
    func testRefreshCheckpointRechecksSiblingWritesBeforeSaving() throws {
        for outcome in 0..<3 {
            let (container, seedContext) = try makePriceContext()
            let key = "magic:checkpoint:normal"
            let initialAt = Date.now.addingTimeInterval(-120)
            func quote(_ amount: Double, at date: Date) -> PriceLookup {
                .price(NormalizedPrice(
                    unitMarketPriceUSD: amount, currencyCode: "USD", source: .scryfall,
                    sourceVariantID: "usd", sourceUpdatedAt: nil, fetchedAt: date
                ))
            }
            let seed = PriceStore(context: seedContext)
            XCTAssertTrue(seed.store(quote(100, at: initialAt), game: .magic,
                                     printingID: "checkpoint", variantID: "normal", at: initialAt))
            XCTAssertTrue(seed.save())

            let readContext = ModelContext(container)
            readContext.autosaveEnabled = false
            let refresh = PriceStore(
                context: readContext, index: PriceRefreshDataIndex(context: readContext),
                checkpointsInFreshContext: true
            )
            XCTAssertEqual(refresh.record(forKey: key)?.effectiveUnitMarketPriceUSD, 100)
            let oldResponseAt = initialAt.addingTimeInterval(30)
            switch outcome {
            case 0:
                XCTAssertTrue(refresh.store(quote(150, at: oldResponseAt), game: .magic,
                                            printingID: "checkpoint", variantID: "normal", at: oldResponseAt))
            case 1:
                XCTAssertTrue(refresh.store(.unavailable(.scryfall), game: .magic,
                                            printingID: "checkpoint", variantID: "normal", at: oldResponseAt))
            default:
                XCTAssertTrue(refresh.recordFailure(game: .magic, printingID: "checkpoint",
                                                    variantID: "normal", at: oldResponseAt))
            }
            let sibling = PriceStore(context: ModelContext(container))
            let newerAt = initialAt.addingTimeInterval(60)
            XCTAssertTrue(sibling.store(quote(200, at: newerAt), game: .magic,
                                       printingID: "checkpoint", variantID: "normal", at: newerAt))
            XCTAssertTrue(sibling.save())
            XCTAssertTrue(refresh.save())
            let verification = ModelContext(container)
            let persisted = try XCTUnwrap(PriceStore(context: verification).record(forKey: key))
            XCTAssertEqual(persisted.effectiveUnitMarketPriceUSD, 200)
            XCTAssertEqual(persisted.fetchedAt, newerAt)
            XCTAssertEqual(refresh.record(forKey: key)?.effectiveUnitMarketPriceUSD, 200)
            XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceObservation>()).count, 2)
        }
    }

    @MainActor
    func testRefreshCheckpointCannotReviveSiblingInvalidation() throws {
        let (container, context) = try makePriceContext()
        let key = "magic:invalidated-checkpoint:normal"
        let quoteAt = Date.now.addingTimeInterval(-60)
        let initial = PriceStore(context: context)
        XCTAssertTrue(initial.store(.price(NormalizedPrice(
            unitMarketPriceUSD: 50, currencyCode: "USD", source: .scryfall,
            sourceVariantID: "usd", sourceUpdatedAt: nil, fetchedAt: quoteAt.addingTimeInterval(-30)
        )), game: .magic, printingID: "invalidated-checkpoint", variantID: "normal"))
        XCTAssertTrue(initial.save())
        let readContext = ModelContext(container)
        readContext.autosaveEnabled = false
        let refresh = PriceStore(
            context: readContext, index: PriceRefreshDataIndex(context: readContext),
            checkpointsInFreshContext: true
        )
        XCTAssertTrue(refresh.store(.price(NormalizedPrice(
            unitMarketPriceUSD: 100, currencyCode: "USD", source: .scryfall,
            sourceVariantID: "usd", sourceUpdatedAt: nil, fetchedAt: quoteAt
        )), game: .magic, printingID: "invalidated-checkpoint", variantID: "normal", at: quoteAt))
        XCTAssertNotNil(PriceObservationLog(context: context).recordInvalidation(
            instrumentKey: key, source: .scryfall, at: quoteAt.addingTimeInterval(30)
        ))
        try context.save()
        XCTAssertTrue(refresh.save())
        let verification = ModelContext(container)
        XCTAssertNil(PriceStore(context: verification).record(forKey: key)?.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(try verification.fetch(FetchDescriptor<PriceObservation>()).count, 2)
    }

    @MainActor
    private func makePriceContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return (container, container.mainContext)
    }

    func testEligibleUnitPriceIsTheSingleUSDGate() {
        XCTAssertEqual(
            PortfolioPriceEligibility.eligibleUnitPrice(amount: 12.3456, currencyCode: "USD"),
            Money(rounding: 12.3456)
        )
        XCTAssertNil(
            PortfolioPriceEligibility.eligibleUnitPrice(amount: 12.3456, currencyCode: "EUR")
        )
        XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: nil, currencyCode: "USD"))
        XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: .nan, currencyCode: "USD"))
        XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: -1, currencyCode: "USD"))
        XCTAssertEqual(PortfolioPriceEligibility.eligibleUnitPrice(amount: 0, currencyCode: "USD"), .zero)
    }

    @MainActor
    func testRejectedPreInvalidationQuoteDoesNotCreateCoverage() throws {
        let (container, context) = try makePriceContext()
        defer { withExtendedLifetime(container) {} }
        let key = "magic:coverage-invalidated:normal"
        let olderAt = Date.now.addingTimeInterval(-120)
        let price = NormalizedPrice(
            unitMarketPriceUSD: 100, currencyCode: "USD", source: .scryfall,
            sourceVariantID: "usd", sourceUpdatedAt: nil, fetchedAt: olderAt
        )
        let log = PriceObservationLog(context: context)
        XCTAssertEqual(log.ingest(.price(price), instrumentKey: key, marketVariantID: nil,
                                  recordsCoverage: false, at: olderAt), .append(.marketUpdate))
        XCTAssertNotNil(log.recordInvalidation(instrumentKey: key, source: .scryfall,
                                               at: olderAt.addingTimeInterval(60)))
        try context.save()
        XCTAssertEqual(log.ingest(.price(price), instrumentKey: key, marketVariantID: nil,
                                  at: olderAt), .ignoredAfterInvalidation)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceCheckDay>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PriceObservation>()).count, 2)
    }

    func testLegacyCardmarketObservationIsRetainedWithoutBecomingTheCurrentCardPrice() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PriceRecord(
            key: "pokemon:promo-078:cosmos",
            game: .pokemon,
            printingID: "promo-078",
            variantID: "cosmos"
        )
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 1.43,
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "cardmarket",
                sourceUpdatedAt: fetchedAt,
                fetchedAt: fetchedAt
            )
        )

        record.applyUnavailable(source: .tcgplayer, at: fetchedAt.addingTimeInterval(60))

        XCTAssertEqual(record.unitMarketPriceUSD, 1.43)
        XCTAssertEqual(record.currencyCode, "EUR")
        XCTAssertEqual(record.source, .cardmarket)
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertNil(record.display.amount)
        XCTAssertEqual(record.display.currencyCode, "USD")
        XCTAssertEqual(record.display.source, .cardmarket)
        XCTAssertEqual(record.display.state(now: fetchedAt.addingTimeInterval(60)), .unavailable)
    }

    @MainActor
    func testSharedPriceSnapshotWithholdsLegacyEURFromCurrentCardPrices() {
        let record = PriceRecord(
            key: "pokemon:promo-078:cosmos",
            game: .pokemon,
            printingID: "promo-078",
            variantID: "cosmos"
        )
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 1.43,
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "cardmarket",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        record.recordFailure(at: Date(timeIntervalSince1970: 1_800_000_060))

        let snapshot = PriceSnapshotStore()
        snapshot.apply([PriceDelta(key: record.key, display: record.display)])
        let displayed = snapshot.display(for: record.key)

        XCTAssertEqual(record.unitMarketPriceUSD, 1.43)
        XCTAssertEqual(record.currencyCode, "EUR")
        XCTAssertEqual(record.source, .cardmarket)
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(displayed?.currencyCode, "USD")
        XCTAssertNil(displayed?.amount)
        XCTAssertEqual(displayed?.source, .cardmarket)
        XCTAssertEqual(displayed?.state(), .unknown)
    }

    private func pokemonCard(
        variantsJSON: String = #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#,
        pricingJSON: String? = #"""
        { "tcgplayer": {
            "updated": "2026-08-23T13:07:00.000Z",
            "normal": { "marketPrice": 0.42 },
            "reverse-holofoil": { "marketPrice": 3.75 }
        } }
        """#
    ) throws -> IdentifiedCard {
        let pricing = pricingJSON.map { ", \"pricing\": \($0)" } ?? ""
        let json = """
        {
          "id": "sv08.5-074",
          "localId": "074",
          "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "variants": \(variantsJSON)\(pricing)
        }
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "PRE")
    }

    private func magicCard(promoType: String? = nil) throws -> IdentifiedCard {
        let promoTypes = promoType.map { ", \"promo_types\": [\"\($0)\"]" } ?? ""
        let json = """
        {
          "id": "3f0a1f52-0000-4000-8000-000000000001",
          "name": "Llanowar Elves",
          "set": "ecl", "set_name": "Eclipse", "collector_number": "218",
          "lang": "en", "digital": false, "frame": "2015"\(promoTypes),
          "released_at": "2026-02-06",
          "finishes": ["nonfoil", "foil"],
          "prices": { "usd": "1.25", "usd_foil": "6.40", "usd_etched": null }
        }
        """
        return .magic(try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8)))
    }

    // MARK: - A price belongs to printing *and* variant

    func testTCGplayerPayloadWithExplicitForeignCurrencyCannotBecomeUSD() throws {
        let card = try pokemonCard(pricingJSON:
            #"{"tcgplayer":{"unit":"EUR","normal":{"marketPrice":9.50}}}"#)
        XCTAssertEqual(CardPricing.price(for: card, variant: .normal, magicTreatments: []), .unavailable(.tcgplayer))
    }

    func testInvalidMarketAmountCannotFinishUSDLookup() throws {
        let card = try pokemonCard(pricingJSON:
            #"{"tcgplayer":{"unit":"USD","normal":{"marketPrice":-1}}}"#)
        XCTAssertEqual(CardPricing.price(for: card, variant: .normal, magicTreatments: []), .unavailable(.tcgplayer))
        for amount in [Double.nan, .infinity, -1] {
            XCTAssertNil(CatalogSortPriceResolution.cachedPrice(amount))
            let lookup = PriceLookup.price(.init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgplayer,
                sourceVariantID: "normal", sourceUpdatedAt: nil, fetchedAt: .now))
            XCTAssertTrue(PriceFallbackQuoteResolver.needsFallback(lookup))
        }
    }

    func testExactPokemonProductHandleIsAvailableEvenWhenMarketAmountIsMissing() throws {
        let card = try pokemonCard(pricingJSON:
            #"{"tcgplayer":{"unit":"USD","normal":{"productId":12345,"marketPrice":null}}}"#)
        XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: card, variant: .normal), [.tcgplayerID("12345")])
        XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: card, variant: .reverse).isEmpty)
        for run in [PokemonPrintRun.firstEdition, .shadowless] {
            XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: card, variant: .normal, pokemonPrintRun: run).isEmpty)
        }
    }

    func testDetailedProductHandlesRequireUniqueStandardEnglishPhysicalIdentity() throws {
        func card(_ rows: String) throws -> IdentifiedCard {
            let json = """
            {"id":"sv08.5-074","localId":"074","name":"Eevee",
             "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":180,"official":131}},
             "variants_detailed":[\(rows)]}
            """
            return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "PRE")
        }
        let plain = #"{"type":"holo","size":"standard","thirdParty":{"tcgplayer":12345}}"#
        let extras = #"{"type":"holo","size":"jumbo","thirdParty":{"tcgplayer":999}}, {"type":"holo","languages":["ja"],"thirdParty":{"tcgplayer":998}}, {"type":"holo","stamp":["1st-edition"],"thirdParty":{"tcgplayer":997}}"#
        XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: try card(plain + "," + extras), variant: .holo), [.tcgplayerID("12345")])
        let conflicting = #"{"type":"holo","size":"standard","thirdParty":{"tcgplayer":54321}}"#
        XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: try card(plain + "," + conflicting), variant: .holo).isEmpty)
        XCTAssertTrue(PriceFallbackQuoteResolver.directLookups(card: try card(extras), variant: .holo).isEmpty)
        let cosmos = #"{"type":"holo","foil":"cosmos","size":"standard","thirdParty":{"tcgplayer":694692},"pricing":{"tcgplayer":null}}"#
        XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: try card(cosmos),
            variant: .pokemonFoilPattern("cosmos")), [.tcgplayerID("694692")])
    }

    func testCurrentCardAndReferencePricesUseUSDForEveryGameAndRetainForeignEvidence() {
        for game in [CardGame.pokemon, .magic, .lorcana, .onePiece] {
            let foreign = NormalizedPrice(unitMarketPriceUSD: 19, currencyCode: "EUR", source: .cardmarket,
                sourceVariantID: "foreign", sourceUpdatedAt: nil, fetchedAt: .now)
            let record = PriceRecord(key: "fixture", game: game, printingID: "fixture", variantID: "normal")
            record.apply(foreign)
            let reference = ReferenceQuote(key: "fixture", game: game, printingID: "fixture", variantID: "normal")
            reference.apply(.price(foreign), at: .now)
            XCTAssertNil(record.display.amount)
            XCTAssertNil(reference.display.amount)
            XCTAssertEqual(record.display.currencyCode, "USD")
            XCTAssertEqual(reference.display.currencyCode, "USD")
            XCTAssertEqual(record.unitMarketPriceUSD, 19)
            XCTAssertEqual(reference.amount, 19)
            for enabled in [false, true] {
                XCTAssertFalse(PriceRefreshController.hasFinishedPrice(amount: 19, currencyCode: "EUR", usesFallback: enabled))
                XCTAssertTrue(PriceRefreshController.hasFinishedPrice(amount: 19, currencyCode: "USD", usesFallback: enabled))
            }
            let usd = NormalizedPrice(unitMarketPriceUSD: 21, currencyCode: "USD", source: .tcgplayer,
                sourceVariantID: "exact", sourceUpdatedAt: nil, fetchedAt: .now)
            record.apply(usd)
            reference.apply(.price(usd), at: .now)
            XCTAssertEqual(record.display.amount, 21)
            XCTAssertEqual(reference.display.amount, 21)
        }
    }

    func testReverseHoloReadsTheReverseHoloListing() throws {
        guard case let .price(price) = CardPricing.price(
            for: try pokemonCard(),
            variant: .reverse,
            magicTreatments: []
        ) else {
            return XCTFail("Expected a price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 3.75)
        XCTAssertEqual(price.sourceVariantID, "reverse-holofoil")
        XCTAssertEqual(price.source, .tcgplayer)
    }

    /// The heart of the pricing promise: a Master Ball parallel has no listing of
    /// its own, so it gets no price rather than the reverse holo's.
    func testUnmappedVariantIsUnavailableRatherThanBorrowingAnotherFinishesPrice() throws {
        let card = try pokemonCard()

        XCTAssertEqual(
            CardPricing.price(for: card, variant: .masterBall, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
        XCTAssertEqual(
            CardPricing.price(for: card, variant: .pokeBall, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
        XCTAssertNil(CardPricing.tcgplayerListing(for: .masterBall))
    }

    func testUnknownFinishGetsNoPrice() throws {
        XCTAssertEqual(
            CardPricing.price(for: try pokemonCard(), variant: nil, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
    }

    func testCardWithNoPricingAtAllIsUnavailable() throws {
        let card = try pokemonCard(pricingJSON: nil)

        XCTAssertEqual(
            CardPricing.price(for: card, variant: .reverse, magicTreatments: []),
            .unavailable(nil)
        )
        // Every catalog finish is still listed — as a stated gap. A card whose
        // finishes silently vanish reads as a card that has no finishes.
        XCTAssertFalse(card.marketPrices.isEmpty)
        XCTAssertTrue(card.marketPrices.allSatisfy(\.isGap))
        XCTAssertTrue(card.marketPrices.allSatisfy { $0.value == nil })
    }

    func testVintagePublishedPricesUseOnlyTheRequestedEdition() throws {
        let json = #"{"id":"base1-004","localId":"004","name":"Charizard","set":{"id":"base1","name":"Base Set","cardCount":{"total":102,"official":102}},"variants":{"firstEdition":true,"holo":true,"normal":false,"reverse":false},"pricing":{"tcgplayer":{"holofoil":{"marketPrice":100}}},"variants_detailed":[{"type":"holo","stamp":["1st-edition"],"pricing":{"tcgplayer":{"holofoil":{"marketPrice":500}}}}]}"#
        let card = IdentifiedCard.pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "BAS")
        let unlimited = CardPricing.publishedPrices(for: card, pokemonPrintRun: .unlimited)
        XCTAssertEqual(unlimited.map(\.variantID), [PhysicalVariant.holo.id])
        XCTAssertEqual(unlimited.compactMap(\.value), [100])
        let firstEdition = CardPricing.publishedPrices(for: card, pokemonPrintRun: .firstEdition)
        XCTAssertEqual(firstEdition.map(\.variantID), [PhysicalVariant.firstEdition.id])
        XCTAssertEqual(firstEdition.compactMap(\.value), [500])
        let shadowless = CardPricing.publishedPrices(for: card, pokemonPrintRun: .shadowless)
        XCTAssertTrue(shadowless.allSatisfy(\.isGap))
        XCTAssertTrue(shadowless.compactMap(\.value).isEmpty)
        let noEditionQuote = try pokemonCard()
        XCTAssertTrue(CardPricing.publishedPrices(for: noEditionQuote, pokemonPrintRun: .firstEdition).allSatisfy(\.isGap))
        XCTAssertEqual(CardPricing.price(for: card, variant: .normal, magicTreatments: [],
                                        pokemonPrintRun: .firstEdition), .unavailable(.tcgplayer))
    }

    func testUnlimitedDetailedPriceIgnoresOtherEditionsBeforeIt() throws {
        let json = #"{"id":"base1-004","localId":"004","name":"Charizard","set":{"id":"base1","name":"Base Set","cardCount":{"total":102,"official":102}},"variants":{"firstEdition":true,"holo":true,"normal":false,"reverse":false},"variants_detailed":[{"type":"holo","subtype":"shadowless","stamp":["1st-edition"],"pricing":{"tcgplayer":{"holofoil":{"marketPrice":500}}}},{"type":"holo","subtype":"shadowless","pricing":{"tcgplayer":{"holofoil":{"marketPrice":300}}}},{"type":"holo","subtype":"unlimited","pricing":{"tcgplayer":{"holofoil":{"marketPrice":100}}}}]}"#
        let card = IdentifiedCard.pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "BAS")
        XCTAssertEqual(CardPricing.publishedPrices(for: card, pokemonPrintRun: .unlimited).compactMap(\.value), [100])
        XCTAssertEqual(CardPricing.publishedPrices(for: card, pokemonPrintRun: .firstEdition).compactMap(\.value), [500])
        XCTAssertTrue(CardPricing.publishedPrices(for: card, pokemonPrintRun: .shadowless).allSatisfy(\.isGap))
    }

    func testEditionPricesIgnoreOtherSizesLanguagesAndStamps() throws {
        for run in [PokemonPrintRun.firstEdition, .unlimited] {
            let editionStamp = run == .firstEdition ? ["1st-edition"] : []
            func detail(_ extra: [String: Any], amount: Double) -> [String: Any] {
                var row: [String: Any] = [
                    "type": "holo", "stamp": editionStamp,
                    "pricing": ["tcgplayer": ["holofoil": ["marketPrice": amount]]]
                ]
                row.merge(extra) { _, replacement in replacement }
                return row
            }
            let otherObjects = [
                detail(["size": "jumbo"], amount: 900),
                detail(["languages": ["ja"]], amount: 800),
                detail(["stamp": editionStamp + ["staff"]], amount: 700)
            ]
            for includesExactQuote in [false, true] {
                let object: [String: Any] = [
                    "id": "base1-004", "localId": "004", "name": "Charizard",
                    "set": ["id": "base1", "name": "Base Set", "cardCount": ["total": 102, "official": 102]],
                    "pricing": ["tcgplayer": [String: Any]()],
                    "variants_detailed": otherObjects + (includesExactQuote ? [detail([:], amount: 100)] : [])
                ]
                let card = IdentifiedCard.pokemon(try JSONDecoder().decode(
                    TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object)
                ), setCode: "BAS")
                let lookup = CardPricing.price(for: card, variant: .holo, magicTreatments: [], pokemonPrintRun: run)
                if includesExactQuote {
                    guard case let .price(price) = lookup else { return XCTFail("Expected the exact quote for \(run)") }
                    XCTAssertEqual(price.unitMarketPriceUSD, 100)
                } else {
                    XCTAssertEqual(lookup, .unavailable(.tcgplayer))
                }
            }
        }
    }

    func testEditionOnlyQuoteCannotPriceAnUnknownOrSpecificFinish() throws {
        let json = #"{"id":"base1-004","localId":"004","name":"Charizard","set":{"id":"base1","name":"Base Set","cardCount":{"total":102,"official":102}},"variants_detailed":[{"type":"firstEdition","pricing":{"tcgplayer":{"holofoil":{"marketPrice":500}}}}]}"#
        let card = IdentifiedCard.pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "BAS")
        for variant: PhysicalVariant? in [nil, .normal, .holo] {
            XCTAssertEqual(CardPricing.price(for: card, variant: variant, magicTreatments: [],
                                            pokemonPrintRun: .firstEdition), .unavailable(.tcgplayer))
        }
        XCTAssertEqual(CardPricing.publishedPrices(for: card, pokemonPrintRun: .firstEdition).compactMap(\.value), [500])
    }

    func testPublishedPricesOnlyCoverVariantsTheCatalogSaysExist() throws {
        // The catalog publishes a holofoil price but says this printing has no
        // holo version, so the holo price is not advertised.
        let card = try pokemonCard(
            variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#,
            pricingJSON: #"""
            { "tcgplayer": {
                "normal": { "marketPrice": 0.42 },
                "holofoil": { "marketPrice": 99.0 },
                "reverse-holofoil": { "marketPrice": 3.75 }
            } }
            """#
        )

        XCTAssertEqual(card.marketPrices.compactMap(\.value), [0.42, 3.75])
        // The holo listing exists at the marketplace but not in this printing,
        // so it produces no row at all — priced or otherwise.
        XCTAssertEqual(card.marketPrices.count, 2)
    }

    // MARK: - Magic

    func testMagicFinishesMapOntoScryfallPriceKeys() throws {
        let card = try magicCard()

        guard case let .price(foil) = CardPricing.price(
            for: card,
            variant: .foil,
            magicTreatments: []
        ) else {
            return XCTFail("Expected a foil price")
        }
        XCTAssertEqual(foil.unitMarketPriceUSD, 6.40)
        XCTAssertEqual(foil.sourceVariantID, "usd_foil")
        // Scryfall publishes no "current through" stamp, so the app may only ever
        // report when it checked.
        XCTAssertNil(foil.sourceUpdatedAt)
        XCTAssertFalse(PriceSource.scryfall.publishesSourceTimestamp)
    }

    func testMagicEtchedIsUnavailableWhenScryfallHasNoNumberForIt() throws {
        XCTAssertEqual(
            CardPricing.price(for: try magicCard(), variant: .etched, magicTreatments: []),
            .unavailable(.scryfall)
        )

    }

    func testCatalogSortResolutionRequiresPricingSourceEvidenceForNegative() throws {
        let pokemonWithoutPricing = try pokemonCard(pricingJSON: nil)
        let unqueried = CardPricing.price(
            for: pokemonWithoutPricing,
            variant: .normal,
            magicTreatments: []
        )
        XCTAssertEqual(unqueried, .unavailable(nil))
        XCTAssertEqual(
            CatalogSortPriceResolution.exactLookup(unqueried),
            .unresolved
        )

        let checkedGap = CardPricing.price(
            for: try magicCard(),
            variant: .etched,
            magicTreatments: []
        )
        XCTAssertEqual(checkedGap, .unavailable(.scryfall))
        XCTAssertEqual(
            CatalogSortPriceResolution.exactLookup(checkedGap),
            .noUSDQuote
        )

        let priced = CardPricing.price(
            for: try pokemonCard(),
            variant: .reverse,
            magicTreatments: []
        )
        XCTAssertEqual(
            CatalogSortPriceResolution.exactLookup(priced),
            .priced(3.75)
        )
    }

    func testCachedNilPriceDoesNotResolveSlot() {
        XCTAssertNil(CatalogSortPriceResolution.cachedPrice(nil))
        XCTAssertEqual(
            CatalogSortPriceResolution.cachedPrice(2.5),
            .priced(2.5)
        )
    }

    func testAggregateSortResolutionUsesKnownPriceAndKeepsUnknownsRetryable() throws {
        XCTAssertEqual(
            CatalogSortPriceResolution.aggregate([
                .unavailable(.tcgplayer),
                .unavailable(nil)
            ]),
            .unresolved
        )
        XCTAssertEqual(
            CatalogSortPriceResolution.aggregate([
                .unavailable(.tcgplayer),
                .unavailable(.scryfall)
            ]),
            .noUSDQuote
        )
        XCTAssertEqual(
            CatalogSortPriceResolution.aggregate([
                .unavailable(nil),
                CardPricing.price(
                    for: try pokemonCard(),
                    variant: .normal,
                    magicTreatments: []
                )
            ]),
            .priced(0.42)
        )
    }

    func testMagicTreatmentUsesTheExactPrintingFoilPrice() throws {
        let card = try magicCard(promoType: "surgefoil")
        let foilTreatments = card.magicTreatments(for: .foil)
        let nonfoilTreatments = card.magicTreatments(for: .nonfoil)

        XCTAssertEqual(foilTreatments, [.surgeFoil])
        XCTAssertTrue(nonfoilTreatments.isEmpty)
        guard case let .price(foil) = CardPricing.price(
            for: card,
            variant: .foil,
            magicTreatments: foilTreatments
        ) else {
            return XCTFail("The exact treated printing should retain usd_foil")
        }
        XCTAssertEqual(foil.unitMarketPriceUSD, 6.40)
        XCTAssertEqual(foil.sourceVariantID, "usd_foil")
        guard case let .price(nonfoil) = CardPricing.price(
            for: card,
            variant: .nonfoil,
            magicTreatments: nonfoilTreatments
        ) else {
            return XCTFail("The nonfoil copy has no treatment and should retain usd")
        }
        XCTAssertEqual(nonfoil.unitMarketPriceUSD, 1.25)
        XCTAssertEqual(nonfoil.sourceVariantID, "usd")
    }

    func testUnclassifiedMagicTreatmentUsesTheExactPrintingPrice() throws {
        guard case let .price(price) = CardPricing.price(
            for: try magicCard(),
            variant: .foil,
            magicTreatments: [.unclassified("future-treatment")]
        ) else {
            return XCTFail("An exact printing price should not depend on the treatment enum")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 6.40)
    }

    func testPreviouslyStoredMagicTreatmentPriceRemainsEffectiveEvidence() {
        let record = PriceRecord(
            key: PriceRecord.key(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                treatmentIDs: ["surgefoil"]
            ),
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            magicTreatmentIDs: ["surgefoil"]
        )
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 6.40,
                currencyCode: "USD",
                source: .scryfall,
                sourceVariantID: "usd_foil",
                sourceUpdatedAt: nil,
                fetchedAt: .now
            )
        )

        // This is the regression guard: a price already stored under the
        // treatment-qualified key remains visible after the quarantine is lifted.
        XCTAssertEqual(record.unitMarketPriceUSD, 6.40)
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 6.40)
        XCTAssertEqual(record.display.amount, 6.40)
    }

    func testPreviouslyStoredMagicTreatmentObservationCanValuePortfolio() throws {
        // Model the row exactly as an older build could have left it: the
        // treatment marker is in the canonical key, while the mirrored model
        // column is still empty and the observation contains Scryfall's generic
        // usd_foil amount.
        let key = PriceRecord.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )
        let record = PriceRecord(
            key: key,
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        record.unitMarketPriceUSD = 6.40
        record.sourceRaw = PriceSource.scryfall.rawValue
        record.sourceVariantID = "usd_foil"
        record.fetchedAt = Date(timeIntervalSince1970: 100)

        let observedAmount = try XCTUnwrap(Money(rounding: 6.40))
        let observation = PriceObservation(
            instrumentKey: key,
            kind: .marketUpdate,
            amount: observedAmount,
            source: .scryfall,
            sourceVariantID: "usd_foil",
            marketVariantID: nil,
            effectiveAt: Date(timeIntervalSince1970: 100),
            receivedAt: Date(timeIntervalSince1970: 100),
            isSourceStamped: false
        )

        XCTAssertEqual(PortfolioEngine.observationEntry(from: observation).amount, observedAmount)
        XCTAssertEqual(
            InventoryLedger.resolveValuation(
                observation: observation,
                record: record
            ).unitPrice,
            observedAmount
        )
    }

    func testMagicReleaseDateDrivesSetOrdering() throws {
        XCTAssertGreaterThan(try magicCard().setReleaseOrder, 20_000)
    }

    // MARK: - Freshness is a separate fact from the price

    func testSourceTimestampIsPreferredOverFetchTimeForFreshness() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let sourceUpdated = Date(timeIntervalSince1970: 900_000)
        let display = PriceDisplay(
            amount: 42,
            source: .tcgplayer,
            sourceUpdatedAt: sourceUpdated,
            fetchedAt: fetched,
            lastCheckedAt: fetched
        )

        XCTAssertEqual(display.effectiveAsOf, sourceUpdated)
    }

    func testPriceGoesStaleAgainstTheSourceTimestampNotTheFetchTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Checked seconds ago, but the market data behind it is three days old.
        let display = PriceDisplay(
            amount: 42,
            source: .tcgplayer,
            sourceUpdatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            fetchedAt: now,
            lastCheckedAt: now
        )

        XCTAssertEqual(display.state(now: now), .stale)
    }

    func testNeverCheckedIsNotTheSameAsUnavailable() {
        XCTAssertEqual(PriceDisplay.unknown.state(), .unknown)

        let asked = PriceDisplay(amount: nil, source: .tcgplayer, fetchedAt: .now, lastCheckedAt: .now)
        XCTAssertEqual(asked.state(), .unavailable)
    }

    func testFailedFirstPriceCheckRemainsUnknown() {
        let failedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PriceRecord(
            key: "pokemon:sv08.5-074:reverse",
            game: .pokemon,
            printingID: "sv08.5-074",
            variantID: "reverse"
        )
        record.recordFailure(at: failedAt)

        XCTAssertEqual(record.display.state(now: failedAt), .unknown)
        XCTAssertTrue(record.display.refreshFailed)
    }

    func testNonJustTCGObservationsCannotMoveJustTCGDeltaEvidence() {
        let justTCGAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PriceRecord(
            key: "pokemon:sv08.5-074:reverse",
            game: .pokemon,
            printingID: "sv08.5-074",
            variantID: "reverse"
        )
        XCTAssertTrue(record.apply(NormalizedPrice(
            unitMarketPriceUSD: 5,
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: "justtcg-reverse",
            sourceUpdatedAt: justTCGAt,
            fetchedAt: justTCGAt
        )))
        record.justTCGFetchedAt = justTCGAt

        record.applyUnavailable(source: .tcgplayer, at: justTCGAt.addingTimeInterval(3_600))
        XCTAssertEqual(record.justTCGFetchedAt, justTCGAt)

        XCTAssertTrue(record.apply(NormalizedPrice(
            unitMarketPriceUSD: 6,
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: "browse-cached-variant",
            sourceUpdatedAt: justTCGAt,
            fetchedAt: justTCGAt.addingTimeInterval(7_200)
        )))
        XCTAssertNil(record.justTCGFetchedAt, "Browse quotes are not live refresh evidence")
    }

    /// Offline should not turn yesterday's price into nothing.
    func testFailedRefreshKeepsThePreviousPrice() {
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        let yesterday = Date.now.addingTimeInterval(-24 * 60 * 60)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42.81,
                currencyCode: "USD",
                source: .tcgplayer,
                sourceVariantID: "reverse-holofoil",
                sourceUpdatedAt: yesterday,
                fetchedAt: yesterday
            )
        )

        record.recordFailure(at: .now)

        XCTAssertEqual(record.unitMarketPriceUSD, 42.81)
        XCTAssertEqual(record.fetchedAt, yesterday)
        XCTAssertTrue(record.display.refreshFailed)
        XCTAssertTrue(record.display.detailAttribution.contains("The last price refresh failed. Showing the previous quote."))
        XCTAssertTrue(record.display.detailAttribution.contains { $0.contains("Last check attempted") })
        XCTAssertEqual(record.display.sourceUpdatedAt, yesterday)
    }

    @MainActor
    func testPriceStoreTreatsAnOlderQuoteAsAnAcceptedNoOp() throws {
            let (container, context) = try makePriceContext()
            let key = PriceRecord.key(
                game: .pokemon,
                printingID: "sv08.5-074",
                variantID: "reverse"
            )
            let latest = Date(timeIntervalSince1970: 1_800_000_000)
            let latestQuote = NormalizedPrice(
                unitMarketPriceUSD: 25,
                currencyCode: "USD",
                source: .tcgplayer,
                sourceVariantID: "reverse-holofoil",
                sourceUpdatedAt: latest,
                fetchedAt: latest
            )
            let store = PriceStore(context: context)
            XCTAssertTrue(store.store(
                .price(latestQuote),
                game: .pokemon,
                printingID: "sv08.5-074",
                variantID: "reverse",
                at: latest.addingTimeInterval(2 * 24 * 60 * 60)
            ))
            try context.save()

            let record = try XCTUnwrap(store.record(forKey: key))
            let observationsBefore = try context.fetch(FetchDescriptor<PriceObservation>())
            let checksBefore = try context.fetch(FetchDescriptor<PriceCheckDay>())
            XCTAssertEqual(observationsBefore.count, 1)
            XCTAssertEqual(checksBefore.count, 1)
            let log = PriceObservationLog(context: context)
            XCTAssertEqual(
                checksBefore[0].portfolioDay,
                PortfolioCalendar.day(containing: latest, in: log.timeZone),
                "priced coverage belongs to the quote's fetch day"
            )

            let delayedQuote = NormalizedPrice(
                unitMarketPriceUSD: 19,
                currencyCode: "USD",
                source: .tcgplayer,
                sourceVariantID: "reverse-holofoil",
                sourceUpdatedAt: latest.addingTimeInterval(-60),
                fetchedAt: latest.addingTimeInterval(-60)
            )
            XCTAssertTrue(store.store(
                .price(delayedQuote),
                game: .pokemon,
                printingID: "sv08.5-074",
                variantID: "reverse",
                at: latest.addingTimeInterval(3 * 24 * 60 * 60)
            ), "a stale quote is accepted as an intentional no-op")

            XCTAssertEqual(record.unitMarketPriceUSD, 25)
            XCTAssertEqual(record.fetchedAt, latest)
            XCTAssertEqual(try context.fetch(FetchDescriptor<PriceObservation>()).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<PriceCheckDay>()).count, 1)
            XCTAssertEqual(checksBefore[0].lastSuccessfulCheckAt, latest)
            withExtendedLifetime(container) {}
    }

    @MainActor
    func testClockRollbackAllowsPriceStoreToAcceptTheCurrentQuote() throws {
        let (container, context) = try makePriceContext()
        let store = PriceStore(context: context)
        let key = PriceRecord.key(game: .pokemon, printingID: "p", variantID: nil)
        let clockBeforeRollback = Date(timeIntervalSince1970: 1_800_000_000)
        let now = clockBeforeRollback.addingTimeInterval(-15 * 60)
        XCTAssertTrue(store.store(.price(NormalizedPrice(
            unitMarketPriceUSD: 30,
            currencyCode: "USD",
            source: .tcgplayer,
            sourceVariantID: "normal",
            sourceUpdatedAt: clockBeforeRollback,
            fetchedAt: clockBeforeRollback
        )), game: .pokemon, printingID: "p", variantID: nil, at: clockBeforeRollback))

        let quoteAfterRollback = NormalizedPrice(
            unitMarketPriceUSD: 31,
            currencyCode: "USD",
            source: .tcgplayer,
            sourceVariantID: "normal",
            sourceUpdatedAt: now,
            fetchedAt: now
        )
        let record = try XCTUnwrap(store.record(forKey: key))
        XCTAssertFalse(record.isStale(quoteAfterRollback, now: now))
        XCTAssertTrue(store.store(
            .price(quoteAfterRollback),
            game: .pokemon,
            printingID: "p",
            variantID: nil,
            at: now
        ))
        XCTAssertEqual(record.unitMarketPriceUSD, 31)
        XCTAssertEqual(record.fetchedAt, now)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PriceObservation>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PriceCheckDay>()).count, 1)
        withExtendedLifetime(container) {}
    }

    func testObservationRulesRejectAnOlderReceiptAsASecondGuard() {
        let latest = Date(timeIntervalSince1970: 1_800_000_000)
        let value = PriceObservationValue(
            amount: Money(rounding: 25),
            currencyCode: "USD",
            sourceRaw: PriceSource.tcgplayer.rawValue,
            sourceVariantID: "reverse-holofoil",
            marketVariantID: nil
        )
        let previous = PriceObservationRules.Previous(
            value: value,
            effectiveAt: latest,
            receivedAt: latest,
            isSourceStamped: true
        )
        let candidate = PriceObservationRules.Candidate(
            value: PriceObservationValue(
                amount: Money(rounding: 19),
                currencyCode: "USD",
                sourceRaw: PriceSource.tcgplayer.rawValue,
                sourceVariantID: "reverse-holofoil",
                marketVariantID: nil
            ),
            source: .tcgplayer,
            sourceUpdatedAt: latest.addingTimeInterval(-60),
            receivedAt: latest.addingTimeInterval(-60)
        )

        XCTAssertEqual(
            PriceObservationRules.decide(candidate: candidate, previous: previous),
            .ignoredOutOfOrder
        )
    }

    func testSuccessfulRefreshClearsAPreviousFailure() {
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        record.recordFailure(at: .now)
        record.applyUnavailable(source: .tcgplayer, at: .now)

        XCTAssertFalse(record.display.refreshFailed)
        XCTAssertEqual(record.display.state(), .unavailable)
    }

    // MARK: - Refresh scheduling

    /// A target that already has a price and was checked minutes ago is left
    /// alone; one that is overdue, or has never been asked about, is not.
    private func pricedTarget(
        _ printingID: String,
        variantID: String = "reverse",
        lastCheckedAt: Date?
    ) -> PriceTarget {
        PriceTarget(
            game: .pokemon,
            printingID: printingID,
            catalogPrintingID: nil,
            setCode: "PRE",
            variantID: variantID,
            importedIdentity: nil,
            catalogMetadataCheckedAt: nil,
            lastFailureAt: nil,
            hasPrice: true,
            lastCheckedAt: lastCheckedAt
        )
    }

    func testAutomaticRefreshSkipsPricesCheckedRecently() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let targets = [
            pricedTarget("a", lastCheckedAt: now.addingTimeInterval(-60)),
            pricedTarget("b", lastCheckedAt: now.addingTimeInterval(-12 * 60 * 60)),
            pricedTarget("c", variantID: "normal", lastCheckedAt: nil)
        ]

        XCTAssertEqual(
            PriceRefreshController.staleTargets(from: targets, now: now).map(\.printingID),
            ["b", "c"]
        )
    }

    func testManualPrimaryRefreshBypassesOnlyTheRecentCheckGate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let raw = pricedTarget("synthetic-meditite-099", variantID: "normal", lastCheckedAt: now.addingTimeInterval(-60))
        var sealed = raw
        sealed.itemKind = .sealedProduct
        var graded = raw
        graded.itemKind = .gradedCard
        let targets = [raw, sealed, graded]
        XCTAssertTrue(PriceRefreshController.staleTargets(from: targets, now: now).isEmpty)
        XCTAssertEqual(PriceRefreshController.staleTargets(from: targets, now: now, intent: .manual).map(\.itemKind), [.rawCard])
        XCTAssertTrue(PriceRefreshController.staleTargets(from: [raw], now: now, forceUnsupportedRetry: true).isEmpty,
            "Retrying unsupported work is not manual primary intent")
    }

    func testDetailAttributionKeepsOldSourceDateSeparateFromTodayAndFailure() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let old = today.addingTimeInterval(-6 * 86400)
        var quote = PriceDisplay(amount: 5, source: .tcgplayer, sourceUpdatedAt: old,
            fetchedAt: today, lastCheckedAt: today)
        XCTAssertEqual(quote.state(now: today), .stale)
        XCTAssertTrue(quote.detailAttribution.contains { $0.contains("price data as of") && $0.contains(old.formatted(date: .abbreviated, time: .shortened)) })
        XCTAssertTrue(quote.detailAttribution.contains { $0.contains("Last check attempted") && $0.contains(today.formatted(date: .abbreviated, time: .shortened)) })
        quote.refreshFailed = true
        XCTAssertEqual(quote.state(now: today), .stale)
        XCTAssertTrue(quote.detailAttribution.contains("The last price refresh failed. Showing the previous quote."))
        XCTAssertEqual(quote.amount, 5)
        quote.sourceUpdatedAt = nil
        XCTAssertTrue(quote.detailAttribution.contains { $0.contains("source date unavailable") })
        XCTAssertTrue(quote.detailAttribution.contains { $0.contains("Quote received") })
        quote.fetchedAt = nil
        quote.lastCheckedAt = nil
        XCTAssertFalse(quote.detailAttribution.joined().contains("unknown"))
        XCTAssertFalse(quote.detailAttribution.joined().contains("Quote received"))
    }

    /// Every owned copy of a printing-and-variant shares one price record, so a
    /// refresh asks once no matter how many copies are owned.
    func testPriceKeyIsPerPrintingAndVariant() {
        XCTAssertEqual(
            PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: "masterBall"),
            "pokemon:sv08.5-074:masterBall"
        )
        XCTAssertNotEqual(
            PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: "masterBall"),
            PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        )
    }

    // MARK: - Provider timestamps

    func testProviderTimestampsParseLeniently() {
        XCTAssertNotNil(FlexibleDate.parse("2026-08-23T13:07:00.000Z"))
        XCTAssertNotNil(FlexibleDate.parse("2026-08-23T13:07:00Z"))
        XCTAssertNotNil(FlexibleDate.parse("2026-08-23"))
        // An unrecognised format must not become a false freshness claim.
        XCTAssertNil(FlexibleDate.parse("last Tuesday"))
        XCTAssertNil(FlexibleDate.parse(""))
    }

    func testTCGdexUpdatedTimestampReachesThePrice() throws {
        guard case let .price(price) = CardPricing.price(
            for: try pokemonCard(),
            variant: .normal,
            magicTreatments: []
        ) else {
            return XCTFail("Expected a price")
        }

        XCTAssertNotNil(price.sourceUpdatedAt)
        XCTAssertNotEqual(price.sourceUpdatedAt, price.fetchedAt)
    }

    // MARK: - Parallel patterns (variants_detailed)

    /// Shaped exactly like TCGdex's live response for a Prismatic Evolutions
    /// card: three `reverse` entries, told apart only by `foil` and by the
    /// marketplace product id inside each entry's own pricing block.
    private func ballPatternCard() throws -> IdentifiedCard {
        let json = """
        {
          "id": "sv08.5-001",
          "localId": "001",
          "name": "Exeggcute",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": true, "reverse": true },
          "variants_detailed": [
            { "type": "normal", "size": "standard", "variantId": "endfynwn4n10gzq",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "normal": { "productId": 610356, "marketPrice": 0.02 } } } },
            { "type": "reverse", "size": "standard", "variantId": "cm4kqul3x1bwlz1f",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "reverse-holofoil": { "productId": 610356, "marketPrice": 0.16 } } } },
            { "type": "reverse", "size": "standard", "foil": "pokeball",
              "variantId": "3739bbtj3i910y5ynn9xc6ryf",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "holofoil": { "productId": 610536, "marketPrice": 0.32 } } } },
            { "type": "reverse", "size": "standard", "foil": "masterball",
              "variantId": "2asus05yghmpd1ud1sdmlq3as4e",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "holofoil": { "productId": 610637, "marketPrice": 1.04 } } } }
          ]
        }
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "PRE")
    }

    func testEachBallPatternGetsItsOwnPrice() throws {
        let card = try ballPatternCard()

        guard case let .price(pokeBall) = CardPricing.price(
                  for: card,
                  variant: .pokeBall,
                  magicTreatments: []
              ),
              case let .price(masterBall) = CardPricing.price(
                  for: card,
                  variant: .masterBall,
                  magicTreatments: []
              ) else {
            return XCTFail("Expected a price for each ball pattern")
        }

        XCTAssertEqual(pokeBall.unitMarketPriceUSD, 0.32)
        XCTAssertEqual(masterBall.unitMarketPriceUSD, 1.04)
        XCTAssertEqual(pokeBall.source, .tcgplayer)
    }

    /// The reason the flat pricing object could not do this job: three distinct
    /// objects, three distinct prices, none of them borrowed from another.
    func testBallPatternsDoNotShareThePlainReversePrice() throws {
        let card = try ballPatternCard()

        let amounts = [PhysicalVariant.reverse, .pokeBall, .masterBall].map { variant -> Double? in
            guard case let .price(price) = CardPricing.price(
                for: card,
                variant: variant,
                magicTreatments: []
            ) else { return nil }
            return price.unitMarketPriceUSD
        }

        XCTAssertEqual(amounts, [0.16, 0.32, 1.04])
        XCTAssertEqual(Set(amounts.compactMap { $0 }).count, 3)
    }

    func testParallelPatternsAppearAsCatalogVariants() throws {
        guard case let .pokemon(card, _) = try ballPatternCard().legacyIdentity else { return XCTFail("Expected Pokémon") }

        XCTAssertTrue(card.catalogVariants.contains(.pokeBall))
        XCTAssertTrue(card.catalogVariants.contains(.masterBall))
    }

    /// An unrecognised pattern is a real object this build cannot label. It must
    /// keep its own identity rather than answering to plain reverse, or a reverse
    /// holo would inherit a scarcer parallel's price.
    func testUnrecognisedFoilPatternDoesNotCollapseOntoReverse() throws {
        let json = """
        {
          "id": "sv08.5-002", "localId": "002", "name": "Vaporeon",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": false, "reverse": true },
          "variants_detailed": [
            { "type": "reverse", "size": "standard", "variantId": "cm4kqul3x1bwlz1f",
              "pricing": { "tcgplayer": { "reverse-holofoil": { "marketPrice": 0.20 } } } },
            { "type": "reverse", "size": "standard", "foil": "confetti",
              "variantId": "zzz", "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 88.0 } } } }
          ]
        }
        """
        let card = IdentifiedCard.pokemon(
            try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)),
            setCode: "PRE"
        )

        guard case let .price(reverse) = CardPricing.price(
            for: card,
            variant: .reverse,
            magicTreatments: []
        ) else {
            return XCTFail("Expected a reverse price")
        }
        XCTAssertEqual(reverse.unitMarketPriceUSD, 0.20)

        guard case let .price(confetti) = CardPricing.price(
            for: card,
            variant: PhysicalVariant.pokemonFoilPattern("confetti"),
            magicTreatments: []
        ) else {
            return XCTFail("Expected the unnamed pattern to keep its own price")
        }
        XCTAssertEqual(confetti.unitMarketPriceUSD, 88.0)
    }

    func testMultipleTCGdexStampsRemainOneExactPhysicalVariant() throws {
        let json = """
        {
          "id": "svp-999", "localId": "999", "name": "Test Promo",
          "set": { "id": "svp", "name": "Scarlet & Violet Promos",
                   "cardCount": { "total": 999, "official": 0 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "holo", "size": "standard", "languages": ["en"],
              "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 1.0 } } } },
            { "type": "holo", "size": "standard", "stamp": ["set-logo"],
              "languages": ["en"], "thirdParty": { "tcgplayer": 100 },
              "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 2.0 } } } },
            { "type": "holo", "size": "standard", "stamp": ["staff", "set-logo"],
              "languages": ["en"], "thirdParty": { "tcgplayer": 101 },
              "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 20.0 } } } }
          ]
        }
        """
        let pokemon = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        let options = pokemon.catalogVariants
        XCTAssertEqual(options.count, 3)
        XCTAssertTrue(options.contains(.holo))
        XCTAssertTrue(options.contains { $0.label == "Holo · Set Logo" })
        let staff = try XCTUnwrap(options.first { $0.label == "Holo · Set Logo + Staff" })
        XCTAssertEqual(PokemonCatalogStampVariant.decode(staff.id)?.stamps, ["set-logo", "staff"])
        XCTAssertEqual(pokemon.variantsDetailed?[2].thirdParty?.tcgplayer, 101)

        let card = IdentifiedCard.pokemon(pokemon, setCode: "SVP")
        XCTAssertEqual(
            VariantResolver.resolve(card.variantEvidence, finishLock: .holo),
            .resolved(ResolvedVariant(variant: .holo, resolution: .finishLock))
        )
        guard case let .price(price) = CardPricing.price(
            for: card,
            variant: staff,
            magicTreatments: []
        ) else {
            return XCTFail("Expected the Staff object's exact price")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 20.0)
        XCTAssertEqual(PhysicalVariant.named(staff.id), staff)
    }

    func testLoneStampedCatalogRecordDoesNotInventAChoice() throws {
        let json = """
        {
          "id": "mep-083", "localId": "083", "name": "Slowbro",
          "set": { "id": "mep", "name": "Mega Evolution Promos",
                   "cardCount": { "total": 89, "official": 0 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "holo", "size": "standard", "stamp": ["set-logo"] }
          ]
        }
        """
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.catalogVariants, [.holo])
    }

    func testFirstEditionStampStaysInExistingPrintRunArchitecture() throws {
        let json = """
        {
          "id": "base1-4", "localId": "4", "name": "Charizard",
          "set": { "id": "base1", "name": "Base Set",
                   "cardCount": { "total": 102, "official": 102 } },
          "variants": { "firstEdition": true, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "holo", "subtype": "unlimited", "size": "standard" },
            { "type": "holo", "subtype": "shadowless", "size": "standard",
              "stamp": ["1st-edition"] }
          ]
        }
        """
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.catalogVariants, [.holo, .firstEdition])
        XCTAssertFalse(card.catalogVariants.contains { $0.id.hasPrefix("pokemonStamp|") })
    }

    func testOfflineFirstEditionAndShadowlessCardsDoNotClaimAProviderCheck() throws {
        let card = try pokemonCard(
            variantsJSON: #"{ "firstEdition": true, "holo": true, "normal": false, "reverse": false }"#,
            pricingJSON: nil
        )

        XCTAssertEqual(
            CardPricing.price(
                for: card,
                variant: .holo,
                magicTreatments: [],
                pokemonPrintRun: .firstEdition
            ),
            .unavailable(nil),
            "offline checklist and disk-cache identities carry no provider evidence"
        )
        XCTAssertEqual(
            CardPricing.price(
                for: card,
                variant: .holo,
                magicTreatments: [],
                pokemonPrintRun: .shadowless
            ),
            .unavailable(nil)
        )
    }

    func testFirstEditionWithProviderPricingEvidenceRecordsAnUnsupportedListing() throws {
        XCTAssertEqual(
            CardPricing.price(
                for: try pokemonCard(),
                variant: .holo,
                magicTreatments: [],
                pokemonPrintRun: .firstEdition
            ),
            .unavailable(.tcgplayer),
            "provider data exists, but it has no first-edition listing"
        )
    }

    // MARK: - Cardmarket remains separate from canonical USD pricing

    private func promoCard(tcgplayerJSON: String = "null") throws -> IdentifiedCard {
        let json = """
        {
          "id": "mep-008", "localId": "008", "name": "Golduck",
          "set": { "id": "mep", "name": "Mega Evolution Promos",
                   "cardCount": { "total": 60, "official": 60 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "pricing": {
            "tcgplayer": \(tcgplayerJSON),
            "cardmarket": { "updated": "2026-08-24T08:03:06.951Z", "unit": "EUR",
                            "avg": 0.53, "trend": 0.49, "avg7": 0.47, "avg30": 0.52 }
          }
        }
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "MEP")
    }

    /// Cardmarket publishes a euro figure for the promo catalogue where
    /// TCGplayer publishes nothing. That number is not a weaker dollar price,
    /// it is a different marketplace in a different currency, and this app has
    /// no exchange-rate policy that could turn one into the other. So it is not
    /// consulted at all: the honest answer is that this finish has no USD quote.
    func testCardmarketIsNeverUsedAsAPriceWhenTCGplayerIsSilent() throws {
        XCTAssertEqual(
            CardPricing.price(for: try promoCard(), variant: .holo, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
    }

    /// The regression this rule exists for: a euro amount rendered beside
    /// dollar amounts in the same panel, inviting a comparison neither figure
    /// supports.
    func testNoPublishedPriceRowEverCarriesAForeignCurrencyAmount() throws {
        let published = try promoCard().marketPrices

        XCTAssertFalse(published.isEmpty)
        XCTAssertTrue(published.allSatisfy(\.isGap))
        for row in published {
            XCTAssertEqual(row.availability, .noUSDQuote(.tcgplayer))
        }
    }

    /// A gap is recorded where someone can act on it rather than only absent
    /// from the screen.
    func testAnUnpricedFinishIsRecordedAsACoverageGap() throws {
        PriceCoverageGapLog.shared.reset()
        defer { PriceCoverageGapLog.shared.reset() }

        _ = try promoCard().marketPrices

        let gaps = PriceCoverageGapLog.shared.currentGaps()
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.allSatisfy { $0.consultedSource == .tcgplayer })
        XCTAssertTrue(gaps.allSatisfy { $0.setCode == "MEP" })
    }

    func testTCGplayerStillWinsWhenItHasAPriceForTheVariant() throws {
        let card = try promoCard(tcgplayerJSON: #"{ "holofoil": { "marketPrice": 3.10 } }"#)

        guard case let .price(price) = CardPricing.price(
            for: card,
            variant: .holo,
            magicTreatments: []
        ) else {
            return XCTFail("Expected the TCGplayer price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 3.10)
        XCTAssertEqual(price.source, .tcgplayer)
        XCTAssertEqual(price.currencyCode, "USD")
    }

    func testDetailedCosmosVariantUsesItsTCGplayerUSDPrice() throws {
        let json = #"""
        {
          "id": "mep-078", "localId": "078", "name": "Toxel",
          "set": { "id": "mep", "name": "Mega Evolution Promos",
                   "cardCount": { "total": 80, "official": 80 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "reverse", "foil": "cosmos",
              "pricing": { "tcgplayer": {
                "updated": "2026-09-20T12:00:00.000Z",
                "holofoil": { "marketPrice": 2.34 }
              } }
            }
          ]
        }
        """#
        let card = IdentifiedCard.pokemon(
            try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)),
            setCode: "MEP"
        )

        guard case let .price(price) = CardPricing.price(
            for: card,
            variant: .pokemonFoilPattern("cosmos"),
            magicTreatments: []
        ) else {
            return XCTFail("Expected the detailed Cosmos TCGplayer price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 2.34)
        XCTAssertEqual(price.currencyCode, "USD")
        XCTAssertEqual(price.source, .tcgplayer)
    }
}

final class PriceHistoryChartModelTests: XCTestCase {
    func testDenseProviderHistoryKeepsEveryExactSampleAndDomain() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (0..<5000).map { index in
            JustTCGHistoryPoint(p: Double(index % 100 + 1) / 100, t: now.addingTimeInterval(Double(index - 5000) * 60).timeIntervalSince1970)
        }
        let model = PriceHistoryChartModel.market(points: points, range: .all, now: now)
        XCTAssertEqual(model.samples.count, points.count)
        XCTAssertEqual(model.segments.first?.samples.count, points.count)
        for (sample, point) in zip(model.samples, points) {
            XCTAssertEqual(sample.amount.doubleValue, point.p, accuracy: 0.000001)
            XCTAssertEqual(sample.date.timeIntervalSince1970, point.t)
        }
        let domain = model.yDomain
        XCTAssertGreaterThanOrEqual(domain.lowerBound, 0)
        XCTAssertLessThanOrEqual(domain.lowerBound, 0.01)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 1)
        XCTAssertEqual(model.sample(at: model.samples[2500].date), model.samples[2500])
    }
    func testMarketHistoryIsContinuousWithoutLocalChecksAndScrubsToProviderDates() throws {
        let points = [JustTCGHistoryPoint(p: 10, t: date(day: 0).timeIntervalSince1970),
                      JustTCGHistoryPoint(p: 15, t: date(day: 20).timeIntervalSince1970)]
        let model = PriceHistoryChartModel.market(points: points, range: .all, now: date(day: 21))
        XCTAssertEqual(model.samples.count, 2)
        XCTAssertEqual(model.segments.count, 1)
        XCTAssertFalse(model.hasGaps)
        XCTAssertEqual(model.checkedDayCount, 0)
        XCTAssertEqual(model.sample(at: date(day: 15))?.date, date(day: 20))
        XCTAssertEqual(model.sample(at: date(day: 15))?.amount, Money(rounding: 15))
        let week = PriceHistoryChartModel.market(points: points, range: .oneWeek, now: date(day: 21))
        XCTAssertEqual(week.samples.map(\.amount), [Money(rounding: 15)!])
    }

    private let instrumentKey = "pokemon:test-set-001:normal"
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    private var calendar: Calendar {
        PortfolioCalendar.calendar(in: timeZone)
    }

    private func date(day: Int, hour: Int = 1) -> Date {
        let secondsPerDay: TimeInterval = 24 * 60 * 60
        let offset = TimeInterval(day) * secondsPerDay + TimeInterval(hour) * 60 * 60
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return base.addingTimeInterval(offset)
    }

    private func observation(
        day: Int,
        amount: Double,
        kind: PriceObservationKind = .marketUpdate
    ) throws -> PriceObservation {
        PriceObservation(
            instrumentKey: instrumentKey,
            kind: kind,
            amount: try XCTUnwrap(Money(rounding: amount)),
            source: .tcgplayer,
            sourceVariantID: "normal",
            marketVariantID: "normal",
            effectiveAt: date(day: day),
            receivedAt: date(day: day),
            isSourceStamped: true
        )
    }

    private func checkDay(day: Int) -> PriceCheckDay {
        PriceCheckDay(
            instrumentKey: instrumentKey,
            portfolioDay: calendar.startOfDay(for: date(day: day)),
            lastSuccessfulCheckAt: date(day: day, hour: 2),
            source: .tcgplayer
        )
    }

    private func makeModel(
        observations: [PriceObservation],
        checks: [PriceCheckDay],
        nowDay: Int = 5,
        range: PortfolioHistoryRange = .all
    ) -> PriceHistoryChartModel {
        PriceHistoryChartModel.make(
            observations: observations,
            checkDays: checks,
            currencyCode: "USD",
            range: range,
            now: date(day: nowDay, hour: 12),
            timeZone: timeZone
        )
    }

    func testNoObservationShowsRecordingState() {
        let model = makeModel(observations: [], checks: [])

        XCTAssertTrue(model.samples.isEmpty)
        XCTAssertEqual(model.segments.count, 0)
    }

    func testScrubbingUncheckedDayDoesNotBorrowNearestPrice() throws {
        let model = makeModel(
            observations: [try observation(day: 0, amount: 10), try observation(day: 3, amount: 12)],
            checks: [checkDay(day: 0), checkDay(day: 3)]
        )
        XCTAssertNil(model.sample(at: date(day: 1, hour: 12)))
        XCTAssertNil(model.sample(at: date(day: 2, hour: 12)))
        XCTAssertEqual(model.sample(at: date(day: 3, hour: 1))?.amount, Money(rounding: 12))
        XCTAssertNil(model.sample(at: model.plotRangeStart.addingTimeInterval(-1)))
    }

    func testScrubbingCheckedSpanUsesRecordedStepRatherThanFuturePrice() throws {
        let model = makeModel(
            observations: [try observation(day: 0, amount: 10), try observation(day: 2, amount: 12)],
            checks: [checkDay(day: 0), checkDay(day: 1), checkDay(day: 2)]
        )
        XCTAssertEqual(model.sample(at: date(day: 1, hour: 12))?.amount, Money(rounding: 10))
        XCTAssertEqual(model.sample(at: date(day: 2, hour: 1))?.amount, Money(rounding: 12))
    }

    func testOneObservationRemainsAPointWithoutALine() throws {
        let model = makeModel(
            observations: [try observation(day: 0, amount: 10)],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        XCTAssertEqual(model.observationCount, 1)
        XCTAssertFalse(model.segments.contains { $0.samples.count > 1 })
        XCTAssertEqual(model.segments.count, 1)
    }

    func testCheckedDaysConnectChangedPricesWithAFlatStep() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 10),
                try observation(day: 2, amount: 12)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1), checkDay(day: 2)]
        )

        XCTAssertEqual(model.observationCount, 2)
        XCTAssertEqual(model.segments.count, 1)
        XCTAssertGreaterThanOrEqual(model.segments[0].samples.count, 3)
        XCTAssertFalse(model.hasGaps)
    }

    func testUncheckedDaysCreateAVisibleGap() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 10),
                try observation(day: 3, amount: 12)
            ],
            checks: [checkDay(day: 0), checkDay(day: 3)]
        )

        XCTAssertEqual(model.observationCount, 2)
        XCTAssertEqual(model.segments.count, 2)
        XCTAssertTrue(model.hasGaps)
        XCTAssertTrue(model.segments.allSatisfy { $0.samples.count == 1 })
    }

    func testClusteredObservationsUseTheirSpanForThePlotDomain() throws {
        let model = makeModel(
            observations: [
                try observation(day: 28, amount: 10),
                try observation(day: 29, amount: 12)
            ],
            checks: [checkDay(day: 28), checkDay(day: 29)],
            nowDay: 30,
            range: .oneMonth
        )

        let requestedSpan = model.rangeEnd.timeIntervalSince(model.rangeStart)
        let plotSpan = model.plotRangeEnd.timeIntervalSince(model.plotRangeStart)
        XCTAssertLessThan(plotSpan, requestedSpan * 0.5)
        XCTAssertTrue(model.isPlotRangeFitted)
        XCTAssertLessThanOrEqual(model.plotRangeStart, model.samples.first?.date ?? .distantFuture)
        XCTAssertGreaterThanOrEqual(model.plotRangeEnd, model.samples.last?.date ?? .distantPast)
        XCTAssertEqual(
            PriceHistoryChartModel.recommendedXAxisTickCount(
                for: plotSpan,
                isAccessibilitySize: false
            ),
            2
        )
        XCTAssertEqual(
            PriceHistoryChartModel.recommendedXAxisTickCount(
                for: plotSpan,
                isAccessibilitySize: true
            ),
            2
        )
        XCTAssertTrue(PriceHistoryChartModel.usesShortXAxisLabels(for: 36 * 60 * 60))
        XCTAssertFalse(PriceHistoryChartModel.usesShortXAxisLabels(for: 2 * 24 * 60 * 60))
    }

    func testSourceRestatementIsAnnotatedAsNonMarket() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 10),
                try observation(day: 1, amount: 9, kind: .sourceRestatement)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        XCTAssertEqual(model.samples.last?.annotationLabel, "Source restatement")
    }

    func testNearFlatExpensiveHistoryUsesMinimumVisualEnvelope() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 603.51),
                try observation(day: 1, amount: 603.00)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThanOrEqual(domain.upperBound - domain.lowerBound, 603.00 * 0.02)
        XCTAssertLessThanOrEqual(domain.lowerBound, 603.00)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 603.51)
    }

    func testMeaningfulDeclineStillDeterminesTheChartScale() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 100),
                try observation(day: 1, amount: 20)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThan(domain.upperBound - domain.lowerBound, 80)
        XCTAssertLessThanOrEqual(domain.lowerBound, 20)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 100)
    }

    func testFlatHistoryHasASensibleNonzeroDomain() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 42),
                try observation(day: 1, amount: 42)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThan(domain.upperBound, domain.lowerBound)
        XCTAssertLessThanOrEqual(domain.lowerBound, 42)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 42)
    }

    func testLowPricesNeverProduceANegativeDomain() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 0.01),
                try observation(day: 1, amount: 0.02)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThanOrEqual(domain.lowerBound, 0)
        XCTAssertGreaterThan(domain.upperBound, domain.lowerBound)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 0.02)
    }
}
