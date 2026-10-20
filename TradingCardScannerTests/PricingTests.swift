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

final class PricingTests: XCTestCase {
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
            ("M2-001", nil, "Holofoil - Japanese", true)
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
                let expected = PokemonMasterSetDefinition.requiredSlots(for: try XCTUnwrap(PokemonVariantRules.reviewedVariants(cardID: id)))
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
