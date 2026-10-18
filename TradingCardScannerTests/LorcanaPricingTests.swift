import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

private actor LorcanaTestPriceSource: LorcanaMarketPriceSource {
    private(set) var calls = 0
    private(set) var minimum: Date?
    var waiting = false
    private var failure: URLError.Code?
    private var noQuote = false
    private(set) var healthyFetches: Set<String> = []
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() { waiting = true }
    func resume() { waiting = false; continuation?.resume(); continuation = nil }
    func fail(with code: URLError.Code?) { failure = code }
    func setUnavailable(_ value: Bool) { noQuote = value }
    func recordHealthyFetch(_ id: String) { healthyFetches.insert(id) }
    func quote(mapping: LorcanaMarketMapping, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup {
        calls += 1; minimum = minimumFetchedAt
        if let failure { throw URLError(failure) }
        if noQuote { return .unavailable(.tcgCSV) }
        if waiting { await withCheckedContinuation { continuation = $0 } }
        return .price(.init(unitMarketPriceUSD: 8.16, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(mapping.productID):\(mapping.providerVariantID)",
            sourceUpdatedAt: nil, fetchedAt: .now))
    }
}

private final class LorcanaPricingProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

/// Synthetic physical review evidence exercises contracts, never catalog coverage.
@MainActor
final class LorcanaPricingTests: XCTestCase {
    func testMarketHistoryUsesReviewedLorcanaProductAndFinishMapping() async throws {
        let registry = try registry(mappings: [mapping()])
        let runtimes = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry).runtime])
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        let foil = await CardMarketHistoryRequest(card: card, variant: .foil, printRun: nil)
            .resolvingMarketMapping(in: runtimes)
        XCTAssertEqual(foil.lookups, [.tcgplayerID("510153")])
        XCTAssertEqual(foil.providerPrinting, "Holofoil")
        let normal = await CardMarketHistoryRequest(card: card, variant: .normal, printRun: nil)
            .resolvingMarketMapping(in: runtimes)
        XCTAssertTrue(normal.lookups.isEmpty, "An unmapped finish must not borrow the foil product")
    }

    private let now = Date.now
    private let canonical = UUID(uuidString: "82000000-0000-0000-0000-000000000001")!
    private func id(_ index: Int = 1) -> UUID {
        UUID(uuidString: String(format: "9200000A-0000-0000-0000-%012d", index))!
    }
    private func mapping(finish: LorcanaPhysicalFinish = .foil, product: Int = 510153,
                         references: [String] = ["fixture:market-review", "fixture:product-capture"]) -> LorcanaMarketMapping {
        .init(finish: finish, groupID: 22937, productID: product, productName: "Fixture Elsa",
            productNumber: "207/204", providerVariantID: finish == .normal ? "Normal" : "Holofoil",
            market: "us", currency: "USD", condition: "aggregate", evidenceReferences: references)
    }
    private func manifest(mappings: [LorcanaMarketMapping]? = nil, special: Bool = false,
                          complete: Bool = true) throws -> LorcanaPhysicalCatalogManifest {
        let footer = try LorcanaPrintedIdentity(collectorNumber: "207", denominator: "204", language: "en", printedSetMarker: "1")
        let alias = LorcanaSourceAlias(provider: "fixture", id: "family")
        let printings = (1...(special ? 2 : 1)).map { index in
            LorcanaPhysicalPrinting(id: id(index), identity: .init(canonicalCardID: canonical, footer: footer,
                artworkID: canonical, distributionID: "booster", stamp: index == 1 ? nil : "Fixture Stamp",
                size: .standard, layout: "normal"), providerSetCode: "TFC", setName: "Fixture First Chapter",
                artworkLabel: "Original", distributionLabel: "Fixture Booster", imageURL: nil, status: .verified,
                identityEvidence: LorcanaPhysicalEvidenceKind.allCases.map { .init(kind: $0, reference: "fixture:\($0.rawValue)") },
                finishes: [.init(finish: .normal, evidenceReferences: ["fixture:normal"]),
                           .init(finish: .foil, evidenceReferences: ["fixture:foil"])],
                finishUniverseEvidenceReference: "fixture:finishes", sourceAliases: [alias],
                marketMappings: index == 1 ? mappings : nil)
        }
        return .init(schemaVersion: 2, reviewedAt: now.addingTimeInterval(-2),
            printFamilies: [.init(footer: footer, providerSetCode: "TFC", name: "Fixture Elsa", version: nil,
                rarity: "Fixture", layout: "normal", sourceAliases: [alias], footerEvidenceReference: "fixture:footer")],
            canonicalCards: [.init(id: canonical, name: "Fixture Elsa", version: nil, relationshipEvidenceReferences: ["fixture:canonical"])],
            physicalPrintings: printings, universes: [.init(footer: footer, printingIDs: printings.map(\.id), isComplete: complete,
                evidenceReference: complete ? "fixture:universe" : nil)], corrections: [])
    }
    private func registry(mappings: [LorcanaMarketMapping]? = nil, special: Bool = false,
                          complete: Bool = true) throws -> LorcanaCatalogRegistry {
        try .init(manifest: manifest(mappings: mappings, special: special, complete: complete))
    }
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let config = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }
    private func runtimes(_ registry: LorcanaCatalogRegistry, source: any LorcanaMarketPriceSource,
                          coordinator: LorcanaCatalogCoordinator? = nil) throws -> CardGameRuntimeContainer {
        let runtime = LorcanaGameRuntime(registry: registry, coordinator: coordinator).runtime
        return try .init(runtimes: [.init(descriptor: .init(game: .lorcana, displayName: "Disney Lorcana", sortOrder: 3,
            capabilities: [.scan, .browse, .pricing, .collectionWrite]), variantPolicy: runtime.variantPolicy,
            pricing: LorcanaPriceAdapter(registry: registry, coordinator: coordinator, source: source),
            recognizer: runtime.recognizer, catalog: runtime.catalog, browse: runtime.browse, importer: runtime.importer,
            priceAuthority: runtime.priceAuthority, activationSource: coordinator, requiresLaunchActivation: false)])
    }
    private func signed(_ manifest: LorcanaPhysicalCatalogManifest, revision: Int,
                        key: Curve25519.Signing.PrivateKey) throws -> LorcanaCatalogReleaseEnvelope {
        try LorcanaCatalogSignature.sign(.init(schemaVersion: 1, gameID: "lorcana", revision: revision,
            generatedAt: now, catalog: manifest), keyID: "lorcana-pricing-fixture", privateKey: key)
    }
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func testMappingsRoundTripWithoutChangingPhysicalOwnershipAndCanonicalizeEvidence() throws {
        let original = try registry()
        let mapped = try LorcanaCatalogRegistry(manifest: manifest(mappings: [mapping()]), previous: original)
        let reversed = try registry(mappings: [mapping(references: ["fixture:product-capture", "fixture:market-review"])])
        XCTAssertEqual(mapped.generation, reversed.generation)
        XCTAssertNotEqual(mapped.generation, original.generation)
        XCTAssertEqual(LorcanaPriceAdapter.mappingIdentity(mapping()), LorcanaPriceAdapter.mappingIdentity(mapping(references: ["fixture:product-capture", "fixture:market-review"])))
        let before = try LorcanaCatalogAdapter(registry: original).resolution(forPrintingID: id()).card
        let after = try LorcanaCatalogAdapter(registry: mapped).resolution(forPrintingID: id()).card
        XCTAssertEqual(before.collectionKey(variant: .foil), after.collectionKey(variant: .foil))
        let oldBytes = try JSONEncoder().encode(manifest())
        XCTAssertFalse(String(decoding: oldBytes, as: UTF8.self).contains("marketMappings"))
        XCTAssertEqual(try LorcanaCatalogRegistry(data: oldBytes).generation, original.generation)
        let withdrawn = try LorcanaCatalogRegistry(manifest: manifest(), previous: mapped)
        XCTAssertTrue(LorcanaPriceAdapter.priceAuthority(withdrawn).identityByPriceKey.isEmpty)
    }

    func testInvalidAndDuplicateMappingsFailClosed() throws {
        let bytes = try JSONEncoder().encode(manifest(mappings: [mapping()]))
        for (field, value) in [("currency", "EUR"), ("market", "eu"), ("condition", "NM"),
                               ("providerVariantID", "Normal"), ("productName", ""), ("productNumber", "1/204")] {
            var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var prints = object["physicalPrintings"] as! [[String: Any]]
            var mappings = prints[0]["marketMappings"] as! [[String: Any]]
            mappings[0][field] = value; prints[0]["marketMappings"] = mappings; object["physicalPrintings"] = prints
            XCTAssertThrowsError(try LorcanaCatalogRegistry(data: JSONSerialization.data(withJSONObject: object)), field)
        }
        XCTAssertThrowsError(try registry(mappings: [mapping(), mapping()]))
        XCTAssertThrowsError(try registry(mappings: [mapping(product: 0)]))
        XCTAssertThrowsError(try registry(mappings: [mapping(references: [])]))
        var duplicate = try manifest(mappings: [mapping()], special: true)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(duplicate)) as! [String: Any]
        var prints = object["physicalPrintings"] as! [[String: Any]]
        prints[1]["marketMappings"] = prints[0]["marketMappings"]; object["physicalPrintings"] = prints
        XCTAssertThrowsError(try LorcanaCatalogRegistry(data: JSONSerialization.data(withJSONObject: object)))
        duplicate = try manifest(mappings: [mapping()], complete: false)
        XCTAssertTrue(LorcanaPriceAdapter.priceAuthority(try .init(manifest: duplicate)).identityByPriceKey.isEmpty)
    }

    func testExactResolvedAndStoredRefreshWithholdOtherFinishesAndSpecialPrintings() async throws {
        let registry = try registry(mappings: [mapping()], special: true), source = LorcanaTestPriceSource()
        let adapter = LorcanaPriceAdapter(registry: registry, source: source)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        let quote = try await adapter.refresh(.init(identity: .legacy(card), variant: .foil, pokemonPrintRun: nil,
            catalogRefreshOverride: { XCTFail("Lorcana must not use catalog/name fallback"); return .unavailable(nil) }))
        guard case let .price(price) = quote else { return XCTFail() }
        XCTAssertEqual(price.unitMarketPriceUSD, 8.16)
        XCTAssertEqual(price.catalogIdentity, LorcanaPriceAdapter.mappingIdentity(mapping()))
        let stored = try await adapter.refreshStoredPrinting(card.providerID, variant: .foil)
        guard case .price = stored else { return XCTFail() }
        let normal = try await adapter.refreshStoredPrinting(card.providerID, variant: .normal)
        let special = try await adapter.refreshStoredPrinting(id(2).uuidString.lowercased(), variant: .foil)
        XCTAssertEqual(normal, .unavailable(nil)); XCTAssertEqual(special, .unavailable(nil))
        XCTAssertFalse(adapter.allowsProviderFallback)
        let calls = await source.calls; XCTAssertEqual(calls, 2)
        for printingID in [card.providerID.uppercased(), "lorcanajson:en:1", UUID().uuidString.lowercased()] {
            do { _ = try await adapter.refreshStoredPrinting(printingID, variant: .foil); XCTFail() }
            catch PriceQuoteError.identityMismatch {}
        }
        let wrong = GamePriceIdentity(game: .lorcana, printingID: card.providerID, setID: card.setID,
            displaySetCode: card.setCode, cardNumber: "1", language: "en")
        do { _ = try await adapter.refresh(.init(identity: wrong, variant: .foil, pokemonPrintRun: nil, catalogRefreshOverride: nil)); XCTFail() }
        catch PriceQuoteError.identityMismatch {}
        do { _ = try await adapter.refreshStoredPrinting(card.providerID, variant: nil); XCTFail() }
        catch PriceQuoteError.identityMismatch {}
    }

    func testCapabilityAbsencePreventsProviderRequestsAndDiscoveryRemainsUnpriced() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource()
        var runtime = LorcanaGameRuntime(registry: registry); runtime.pricingEnabled = false
        let gameRegistry = try CardGameRuntimeContainer(runtimes: [runtime.runtime]).registry
        let service = PriceQuoteService(registry: gameRegistry,
            adapters: try .init(adapters: [LorcanaPriceAdapter(registry: registry, source: source)]))
        XCTAssertFalse(service.supportsPricing(for: .lorcana))
        XCTAssertNil(runtime.runtime.pricing)
        do { _ = try await service.refreshStoredPrinting(game: .lorcana, printingID: id().uuidString.lowercased(), variant: .foil); XCTFail() }
        catch PriceQuoteError.pricingUnsupported {}
        let calls = await source.calls; XCTAssertEqual(calls, 0)
        XCTAssertTrue(CardGameRuntimeContainer.appDefaults().makePriceQuoteService().supportsPricing(for: .lorcana))
    }

    func testBrowseDetailAndSortReuseExactAdapter() async throws {
        let registry = try registry(mappings: [mapping()], special: true), source = LorcanaTestPriceSource()
        let runtimes = try runtimes(registry, source: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = BrowseCatalog(cache: CatalogCacheStore(root: root), gameRegistry: runtimes.registry,
            gameBrowseAdapters: try .init(adapters: [LorcanaBrowseAdapter(registry: registry)]),
            priceQuoteService: runtimes.makePriceQuoteService())
        let sets = try await catalog.sets(for: .lorcana), set = try XCTUnwrap(sets.first)
        let page = try await catalog.cards(in: set, cursor: nil)
        let summary = try XCTUnwrap(page.items.first { $0.providerID == id().uuidString.lowercased() })
        var prices: [String: Double] = [:]
        var missingMappings: Set<String> = []
        for await update in catalog.sortPriceUpdates(for: page.items) {
            prices = update.prices
            missingMappings = update.missingMappingIDs
            XCTAssertTrue(update.unresolvedIDs.isEmpty, "Missing mappings are not request failures")
        }
        XCTAssertEqual(prices[summary.id], 8.16); XCTAssertEqual(prices.count, 1)
        XCTAssertFalse(missingMappings.contains(summary.id), "An available exact finish still prices the printing")
        let unpriced = try XCTUnwrap(page.items.first { $0.providerID == id(2).uuidString.lowercased() })
        XCTAssertTrue(missingMappings.contains(unpriced.id))
        let quote = try await catalog.price(for: summary, variant: .foil)
        guard case let .price(price) = quote else { return XCTFail() }
        XCTAssertEqual(price.unitMarketPriceUSD, prices[summary.id])
        do { _ = try await catalog.price(for: summary, variant: .normal); XCTFail("Expected mapping gap") }
        catch PriceQuoteError.mappingUnavailable {}
    }

    func testPriceCheckRefreshUsesReferenceQuotesWithoutCollectionWrites() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource(), container = try container()
        let runtimes = try await runtimes(registry, source: source).bound(to: container)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        let identifier = try LorcanaRecognitionAdapter.identifier(XCTUnwrap(registry.physicalCatalog?.manifest.printFamilies.first?.footer), generation: registry.generation)
        let scan = ResolvedScan(request: .init(subject: .init(identifier: identifier), purpose: .priceCheck, generation: 0),
            card: card, resolved: .init(variant: .foil, resolution: .userConfirmed), pokemonPrintRun: nil,
            options: [.normal, .foil], catalogRetrievedAt: now)
        let coordinator = PriceCheckCoordinator(context: container.mainContext, quoteService: runtimes.makePriceQuoteService())
        let result = coordinator.present(scan)
        guard case let .quote(.price(price)) = await coordinator.refresh(result) else { return XCTFail() }
        XCTAssertEqual(price.unitMarketPriceUSD, 8.16)
        XCTAssertEqual(QuoteCache(context: container.mainContext).quote(game: .lorcana, printingID: card.providerID,
            variantID: "foil")?.effectiveAmount, 8.16)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        let unmappedScan = ResolvedScan(request: scan.request, card: card,
            resolved: .init(variant: .normal, resolution: .userConfirmed), pokemonPrintRun: nil,
            options: [.normal, .foil], catalogRetrievedAt: now)
        let unmappedResult = coordinator.present(unmappedScan)
        let unmappedOutcome = await coordinator.refresh(unmappedResult)
        XCTAssertEqual(unmappedOutcome, .failed(.mappingUnavailable))
        let calls = await source.calls
        XCTAssertEqual(calls, 1, "A mapping gap cannot query an unrelated provider finish")
        XCTAssertNil(QuoteCache(context: container.mainContext).quote(game: .lorcana,
            printingID: card.providerID, variantID: "normal"))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testScannerSaveQueuesExactPricing() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource(), container = try container()
        let bound = try await runtimes(registry, source: source).bound(to: container)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
            catalog: bound.makeCardCatalog(), unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        let identifier = try LorcanaRecognitionAdapter.identifier(XCTUnwrap(registry.physicalCatalog?.manifest.printFamilies.first?.footer), generation: registry.generation)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: identifier), nil)
        let pending = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(pending)
        model.choose(.foil)
        let key = PriceRecord.key(game: .lorcana, printingID: id().uuidString.lowercased(), variantID: "foil")
        let priced = await waitUntil { PriceStore(context: ModelContext(container)).record(forKey: key)?.effectiveUnitMarketPriceUSD == 8.16 }
        XCTAssertTrue(priced); XCTAssertEqual(model.successCount, 1)
    }

    func testCollectionRefreshAndRelaunchKeepMappedAndUnmappedOwnershipSeparate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try registry(mappings: [mapping()], special: true), source = LorcanaTestPriceSource()
        let runtimes = try runtimes(registry, source: source), container = try container(url: root.appendingPathComponent("collection.store"))
        let bound = try await runtimes.bound(to: container)
        let store = CollectionStore(context: container.mainContext)
        for index in [1, 2] {
            let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id(index)).card
            _ = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        }
        let legacyPrices = PriceStore(context: container.mainContext)
        for index in [1, 2] {
            XCTAssertTrue(legacyPrices.recordUnsupportedProvider(game: .lorcana,
                printingID: id(index).uuidString.lowercased(), variantID: "foil"))
        }
        XCTAssertTrue(legacyPrices.save())
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        let outcome = await worker.run(.init(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: false,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
        guard case let .completed(result) = outcome else { return XCTFail("Expected completed refresh") }
        XCTAssertEqual(result.failed, 0, "Mapped games must not also enter the legacy fetch path")
        XCTAssertEqual(result.missingMappings, 1)
        let reopened = try self.container(url: root.appendingPathComponent("collection.store"))
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).count, 2)
        let prices = PriceStore(context: reopened.mainContext)
        XCTAssertEqual(prices.record(forKey: PriceRecord.key(game: .lorcana, printingID: id().uuidString.lowercased(), variantID: "foil"))?.effectiveUnitMarketPriceUSD, 8.16)
        XCTAssertNil(prices.record(forKey: PriceRecord.key(game: .lorcana, printingID: id().uuidString.lowercased(), variantID: "foil"))?.lastFailureAt)
        XCTAssertNil(prices.record(forKey: PriceRecord.key(game: .lorcana, printingID: id(2).uuidString.lowercased(), variantID: "foil"))?.effectiveUnitMarketPriceUSD)
        let missing = try XCTUnwrap(prices.record(forKey: PriceRecord.key(game: .lorcana,
            printingID: id(2).uuidString.lowercased(), variantID: "foil")))
        XCTAssertEqual(missing.lastFailureReasonRaw, PricingDiagnosticReason.missingMarketMapping.rawValue)
        XCTAssertNil(missing.lastFailureAt)
    }

    func testSignedWithdrawalRejectsInFlightQuoteAndPreservesManualValues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey(), initial = try manifest(mappings: [mapping()])
        let registry = try LorcanaCatalogRegistry(manifest: initial)
        let store = try LorcanaCatalogReleaseStore(root: root, keys: ["lorcana-pricing-fixture": key.publicKey],
            bundledEnvelope: signed(initial, revision: 1, key: key), now: now)
        let coordinator = LorcanaCatalogCoordinator(store: store), source = LorcanaTestPriceSource(), container = try container()
        let runtimes = try await runtimes(registry, source: source, coordinator: coordinator).bound(to: container)
        let service = runtimes.makePriceQuoteService(), printing = id().uuidString.lowercased()
        let quote = try await service.refreshStoredPrinting(game: .lorcana, printingID: printing, variant: .foil)
        let prices = PriceStore(context: container.mainContext)
        XCTAssertTrue(prices.store(quote, game: .lorcana, printingID: printing, variantID: "foil")); XCTAssertTrue(prices.save())
        _ = QuoteCache(context: container.mainContext).store(quote, game: .lorcana, printingID: printing, variantID: "foil")
        let manual = PriceLookup.price(.init(unitMarketPriceUSD: 22, currencyCode: "USD", source: .importedCSV,
            sourceVariantID: "owner-entered", sourceUpdatedAt: nil, fetchedAt: .now))
        XCTAssertTrue(prices.store(manual, game: .lorcana, printingID: printing, variantID: "normal")); XCTAssertTrue(prices.save())
        await source.pause()
        let old = Task { try await service.refreshStoredPrinting(game: .lorcana, printingID: printing, variant: .foil) }
        for _ in 0..<300 { if await source.calls == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        let calls = await source.calls; XCTAssertEqual(calls, 2)
        guard case .activated = await coordinator.activate(try signed(manifest(), revision: 2, key: key), now: now) else { return XCTFail() }
        let snapshot = await runtimes.runtime(for: .lorcana)?.activationSource?.currentSnapshot()
        XCTAssertTrue(snapshot?.priceAuthority?.identityByPriceKey.isEmpty == true)
        await source.resume()
        do { _ = try await old.value; XCTFail("Withdrawn in-flight mapping must not return a quote") }
        catch PriceQuoteError.identityMismatch {}
        let fresh = ModelContext(container)
        let withdrawn = try XCTUnwrap(PriceStore(context: fresh).record(forKey: PriceRecord.key(game: .lorcana, printingID: printing, variantID: "foil")))
        XCTAssertNil(withdrawn.effectiveUnitMarketPriceUSD); XCTAssertNotNil(withdrawn.invalidatedAt)
        let reference = try XCTUnwrap(QuoteCache(context: fresh).quote(game: .lorcana, printingID: printing, variantID: "foil"))
        XCTAssertNil(reference.effectiveAmount)
        reference.apply(quote, at: .now); XCTAssertNil(reference.effectiveAmount)
        XCTAssertEqual(PriceStore(context: fresh).record(forKey: PriceRecord.key(game: .lorcana, printingID: printing, variantID: "normal"))?.effectiveUnitMarketPriceUSD, 22)
        do { _ = try await service.refreshStoredPrinting(game: .lorcana, printingID: printing, variant: .foil); XCTFail("Expected mapping gap") }
        catch PriceQuoteError.mappingUnavailable {}
    }

    func testMappingChangeWithdrawsOldReceiptsAndFetchesNewIdentity() async throws {
        let first = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource(), container = try container()
        let printing = id().uuidString.lowercased(), prices = PriceStore(context: container.mainContext)
        let old = try await LorcanaPriceAdapter(registry: first, source: source).refreshStoredPrinting(printing, variant: .foil)
        XCTAssertTrue(prices.store(old, game: .lorcana, printingID: printing, variantID: "foil")); XCTAssertTrue(prices.save())
        let next = try LorcanaCatalogRegistry(manifest: manifest(mappings: [mapping(product: 510154)]), previous: first)
        let bound = try await runtimes(next, source: source).bound(to: container)
        let key = PriceRecord.key(game: .lorcana, printingID: printing, variantID: "foil")
        let withdrawn = try XCTUnwrap(PriceStore(context: ModelContext(container)).record(forKey: key))
        XCTAssertNil(withdrawn.effectiveUnitMarketPriceUSD)
        let watermark = try XCTUnwrap(withdrawn.invalidatedAt)
        let staleStore = PriceStore(context: ModelContext(container), checkpointsInFreshContext: true)
        _ = staleStore.store(old, game: .lorcana, printingID: printing, variantID: "foil"); _ = staleStore.save()
        XCTAssertNil(PriceStore(context: ModelContext(container)).record(forKey: key)?.effectiveUnitMarketPriceUSD)
        guard case let .price(price) = try await bound.makePriceQuoteService().refreshStoredPrinting(game: .lorcana,
            printingID: printing, variant: .foil) else { return XCTFail() }
        XCTAssertEqual(price.catalogIdentity, LorcanaPriceAdapter.mappingIdentity(mapping(product: 510154)))
        XCTAssertEqual(price.sourceVariantID, "tcgplayer:510154:Holofoil")
        let minimum = await source.minimum; XCTAssertEqual(minimum, watermark)
    }

    func testFeedValidatesExactProductLaneAndPreservesReceiptAcrossRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LorcanaPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LorcanaPricingProtocol.self]
        LorcanaPricingProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasPrefix("/tcgplayer/71/22937/"))
            return Data((request.url!.lastPathComponent == "products"
                ? #"{"success":true,"errors":[],"results":[{"productId":510153,"categoryId":71,"groupId":22937,"name":"Fixture Elsa","extendedData":[{"name":"Number","value":"207/204"}]}]}"#
                : #"{"success":true,"errors":[],"results":[{"productId":510153,"subTypeName":"Normal","marketPrice":9000},{"productId":510153,"subTypeName":"Holofoil","marketPrice":8.16}]}"#).utf8)
        }
        let source = LorcanaTCGCSVPriceSource(transport: .init(session: URLSession(configuration: config), cacheDirectory: root))
        guard case let .price(price) = try await source.quote(mapping: mapping(), generation: "fixture", minimumFetchedAt: nil) else { return XCTFail() }
        XCTAssertEqual(price.unitMarketPriceUSD, 8.16); XCTAssertNil(price.sourceUpdatedAt)
        LorcanaPricingProtocol.handler = { _ in XCTFail("Relaunch must use the retained receipt"); return Data() }
        let relaunched = LorcanaTCGCSVPriceSource(transport: .init(session: URLSession(configuration: config), cacheDirectory: root))
        let cached = try await relaunched.quote(mapping: mapping(), generation: "fixture", minimumFetchedAt: nil)
        XCTAssertEqual(cached, .price(price))
        do { _ = try await source.quote(mapping: mapping(product: 99), generation: "fixture", minimumFetchedAt: nil); XCTFail() }
        catch PriceQuoteError.identityMismatch {}
    }

    func testColdFoilDoesNotBorrowNormalOrHolofoilAndDuplicateRowsReject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LorcanaPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LorcanaPricingProtocol.self]
        let cold = try JSONDecoder().decode(LorcanaMarketMapping.self,
            from: Data(String(decoding: JSONEncoder().encode(mapping()), as: UTF8.self).replacingOccurrences(of: "Holofoil", with: "Cold Foil").utf8))
        XCTAssertNoThrow(try registry(mappings: [cold]))
        for mode in ["exact", "missing", "duplicate", "wrong-category", "wrong-number"] {
            LorcanaPricingProtocol.handler = { request in
                if request.url!.lastPathComponent == "products" {
                    let category = mode == "wrong-category" ? 68 : 71
                    let number = mode == "wrong-number" ? "1/204" : "207/204"
                    return Data("{\"success\":true,\"errors\":[],\"results\":[{\"productId\":510153,\"categoryId\":\(category),\"groupId\":22937,\"name\":\"Fixture Elsa\",\"extendedData\":[{\"name\":\"Number\",\"value\":\"\(number)\"}]}]}".utf8)
                }
                var rows: [[String: Any]] = [["productId": 510153, "subTypeName": "Normal", "marketPrice": 900],
                    ["productId": 510153, "subTypeName": "Holofoil", "marketPrice": 999]]
                let lane: [String: Any] = ["productId": 510153, "subTypeName": "Cold Foil", "marketPrice": 0.16]
                if mode != "missing" { rows.append(lane) }
                if mode == "duplicate" { rows.append(lane) }
                return try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": rows])
            }
            let source = LorcanaTCGCSVPriceSource(transport: .init(session: URLSession(configuration: config),
                cacheDirectory: root.appendingPathComponent(mode)))
            do {
                let quote = try await source.quote(mapping: cold, generation: "fixture", minimumFetchedAt: nil)
                if mode == "exact", case let .price(price) = quote { XCTAssertEqual(price.unitMarketPriceUSD, 0.16) }
                else if mode == "missing" { XCTAssertEqual(quote, .unavailable(.tcgCSV)) }
                else { XCTFail("Expected exact lane rejection: \(mode)") }
            } catch PriceQuoteError.identityMismatch {
                XCTAssertTrue(["duplicate", "wrong-category", "wrong-number"].contains(mode))
            }
        }
    }

    func testOfflineBatchStopsAfterFirstUnreachableRequestAndCanRetry() async throws {
        let registry = try registry(mappings: [mapping(finish: .normal), mapping()])
        let source = LorcanaTestPriceSource(), host = try container()
        let bound = try await runtimes(registry, source: source).bound(to: host)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        for variant in [PhysicalVariant.normal, .foil] {
            _ = try CollectionStore(context: host.mainContext).add(card, resolved: .init(variant: variant, resolution: .userConfirmed))
        }
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        let request = PriceRefreshRequest(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false)
        await source.fail(with: .notConnectedToInternet)
        guard case let .completed(failed) = await worker.run(request, progress: { _ in }, shouldContinue: nil) else { return XCTFail() }
        let calls = await source.calls
        XCTAssertEqual(calls, 1, "Unreachable host must not be retried for every owned finish")
        XCTAssertTrue(failed.providerUnreachable)
        XCTAssertEqual(failed.failed, 1)
        await source.fail(with: nil)
        guard case let .completed(recovered) = await worker.run(request, progress: { _ in }, shouldContinue: nil) else { return XCTFail() }
        XCTAssertEqual(recovered.priced, 2)
        XCTAssertFalse(recovered.providerUnreachable)
        XCTAssertEqual(try ModelContext(host).fetch(FetchDescriptor<CollectedCard>()).count, 2)
    }

    func testMappedHostFailureDoesNotStopHealthyPokemonBatches() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource()
        let host = try container()
        let lorcana = try XCTUnwrap(runtimes(registry, source: source).runtime(for: .lorcana))
        let pokemon = try XCTUnwrap(CardGameRuntimeContainer.appDefaults().runtime(for: .pokemon))
        let bound = try await CardGameRuntimeContainer(runtimes: [lorcana, pokemon]).bound(to: host)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        _ = try CollectionStore(context: host.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        for index in 0..<10 {
            host.mainContext.insert(CollectedCard(collectionKey: "pokemon:healthy-\(index)#normal", game: .pokemon,
                providerID: "healthy-\(index)", name: "Healthy fixture", setName: "Fixture", setCode: "healthy",
                cardNumber: String(index), rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: .normal, variantResolution: .userConfirmed))
        }
        try host.mainContext.save()
        await source.fail(with: .notConnectedToInternet)
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        await worker.setPokemonFetchOverrideForTesting { printing in
            await source.recordHealthyFetch(printing.printingID)
            return .pokemon(TCGdexCard(id: printing.printingID, localId: "1", name: "Healthy fixture", image: nil,
                rarity: nil, set: .init(id: "healthy", name: "Fixture", cardCount: .init(total: 10, official: 10)),
                variants: nil, pricing: nil, variantsDetailed: nil), setCode: "healthy")
        }
        guard case let .completed(result) = await worker.run(.init(usesPriceFallback: false, includeImported: true,
            forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
            markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil) else { return XCTFail() }
        let healthy = await source.healthyFetches
        XCTAssertEqual(healthy.count, 10)
        XCTAssertTrue(result.providerUnreachable)
        XCTAssertEqual(try ModelContext(host).fetch(FetchDescriptor<CollectedCard>()).count, 11)
    }

    func testExplicitNoQuoteCountsAsCompletedProviderCheck() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource()
        let host = try container(), bound = try await runtimes(registry, source: source).bound(to: host)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        _ = try CollectionStore(context: host.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        await source.setUnavailable(true)
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        guard case let .completed(result) = await worker.run(.init(usesPriceFallback: false, includeImported: true,
            forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
            markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil) else { return XCTFail() }
        XCTAssertTrue(result.checkedUnstampedProvider)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.priced, 0)
        let record = PriceStore(context: ModelContext(host)).record(forKey:
            PriceRecord.key(game: .lorcana, printingID: card.physicalPrintingID, variantID: "foil"))
        XCTAssertNotNil(record?.lastSuccessfulCheckAt)
        XCTAssertNil(record?.effectiveUnitMarketPriceUSD)
    }

    func testInvalidFeedCannotPoisonDiskCacheAcrossRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LorcanaPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LorcanaPricingProtocol.self]
        let product: [String: Any] = ["productId": 510153, "categoryId": 71, "groupId": 22937,
            "name": "Fixture Elsa", "extendedData": [["name": "Number", "value": "207/204"]]]
        let price: [String: Any] = ["productId": 510153, "subTypeName": "Holofoil", "marketPrice": 8.16]
        func envelope(_ rows: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": rows])
        }
        let goodProducts = try envelope([product]), goodPrices = try envelope([price])
        for mode in ["duplicate-products", "wrong-category", "wrong-group", "duplicate-lanes", "negative", "overflow"] {
            var products = [product], prices = [price]
            switch mode {
            case "duplicate-products": products.append(product)
            case "wrong-category": products[0]["categoryId"] = 68
            case "wrong-group": products[0]["groupId"] = 1
            case "duplicate-lanes": prices.append(price)
            case "negative": prices[0]["marketPrice"] = -1
            default: prices[0]["marketPrice"] = 1e20
            }
            let badProducts = try envelope(products), badPrices = try envelope(prices)
            let directory = root.appendingPathComponent(mode)
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            LorcanaPricingProtocol.handler = { request in
                request.url!.lastPathComponent == "products" ? badProducts : badPrices
            }
            let source = LorcanaTCGCSVPriceSource(transport: .init(session: session, cacheDirectory: directory))
            do {
                _ = try await source.quote(mapping: mapping(), generation: "cache-validation", minimumFetchedAt: nil)
                XCTFail("Invalid feed must be rejected: \(mode)")
            } catch {}
            LorcanaPricingProtocol.handler = { request in
                request.url!.lastPathComponent == "products" ? goodProducts : goodPrices
            }
            let reopened = LorcanaTCGCSVPriceSource(transport: .init(session: session, cacheDirectory: directory))
            do {
                guard case let .price(recovered) = try await reopened.quote(mapping: mapping(), generation: "cache-validation", minimumFetchedAt: nil) else { XCTFail(); continue }
                XCTAssertEqual(recovered.unitMarketPriceUSD, 8.16)
            } catch { XCTFail("Rejected feed must not persist for the daily cache window: \(mode): \(error)") }

            // Also repair a malformed snapshot persisted by an older app version.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let legacy = try JSONSerialization.data(withJSONObject: ["products": products, "prices": prices,
                "fetchedAt": Date.now.timeIntervalSinceReferenceDate, "catalogGeneration": "cache-validation"])
            try legacy.write(to: directory.appendingPathComponent("71-22937.json"), options: .atomic)
            let upgraded = LorcanaTCGCSVPriceSource(transport: .init(session: session, cacheDirectory: directory))
            do {
                guard case let .price(recovered) = try await upgraded.quote(mapping: mapping(), generation: "cache-validation", minimumFetchedAt: nil) else { XCTFail(); continue }
                XCTAssertEqual(recovered.unitMarketPriceUSD, 8.16)
            } catch { XCTFail("Legacy invalid snapshot must be replaced: \(mode): \(error)") }
        }
    }

    func testValidNullAndZeroPricesRetainDailyCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LorcanaPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LorcanaPricingProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        LorcanaPricingProtocol.handler = { request in
            Data((request.url!.lastPathComponent == "products"
                ? #"{"success":true,"errors":[],"results":[{"productId":510153,"categoryId":71,"groupId":22937,"name":"Fixture Elsa","extendedData":[{"name":"Number","value":"207/204"}]}]}"#
                : #"{"success":true,"errors":[],"results":[{"productId":510153,"subTypeName":"Normal","marketPrice":0},{"productId":510153,"subTypeName":"Holofoil","marketPrice":null}]}"#).utf8)
        }
        let source = LorcanaTCGCSVPriceSource(transport: .init(session: session, cacheDirectory: root))
        let absent = try await source.quote(mapping: mapping(), generation: "valid", minimumFetchedAt: nil)
        XCTAssertEqual(absent, .unavailable(.tcgCSV))
        LorcanaPricingProtocol.handler = { _ in XCTFail("Valid null/zero feed must remain reusable"); throw URLError(.notConnectedToInternet) }
        let reopened = LorcanaTCGCSVPriceSource(transport: .init(session: session, cacheDirectory: root))
        guard case let .price(zero) = try await reopened.quote(mapping: mapping(finish: .normal), generation: "valid", minimumFetchedAt: nil) else { return XCTFail() }
        XCTAssertEqual(zero.unitMarketPriceUSD, 0)
        let cachedAbsent = try await reopened.quote(mapping: mapping(), generation: "valid", minimumFetchedAt: nil)
        XCTAssertEqual(cachedAbsent, absent)
    }

    func testCancelledRefreshDoesNotRecordProviderFailureAndCanResume() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource()
        let host = try container(), bound = try await runtimes(registry, source: source).bound(to: host)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        _ = try CollectionStore(context: host.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed), quantity: 3)
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        let request = PriceRefreshRequest(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false)
        await source.fail(with: .cancelled)
        _ = await worker.run(request, progress: { _ in }, shouldContinue: nil)
        let key = PriceRecord.key(game: .lorcana, printingID: card.physicalPrintingID, variantID: "foil")
        XCTAssertNil(PriceStore(context: ModelContext(host)).record(forKey: key)?.lastFailureAt)
        XCTAssertNil(PriceStore(context: ModelContext(host)).record(forKey: key)?.lastSuccessfulCheckAt)
        await source.fail(with: nil)
        _ = await worker.run(request, progress: { _ in }, shouldContinue: nil)
        XCTAssertEqual(PriceStore(context: ModelContext(host)).record(forKey: key)?.effectiveUnitMarketPriceUSD, 8.16)
        XCTAssertEqual(try ModelContext(host).fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 3)
    }

    func testInterruptedCollectionWorkerCanResumeWithoutPublishingAbandonedQuote() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource()
        let host = try container(), bound = try await runtimes(registry, source: source).bound(to: host)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        _ = try CollectionStore(context: host.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        let request = PriceRefreshRequest(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false)
        await source.pause()
        let interrupted = Task { await worker.run(request, progress: { _ in }, shouldContinue: nil) }
        for _ in 0..<300 {
            if await source.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let calls = await source.calls
        XCTAssertEqual(calls, 1)
        interrupted.cancel()
        await source.resume()
        _ = await interrupted.value
        let key = PriceRecord.key(game: .lorcana, printingID: card.physicalPrintingID, variantID: "foil")
        XCTAssertNil(PriceStore(context: ModelContext(host)).record(forKey: key)?.effectiveUnitMarketPriceUSD)
        XCTAssertNil(PriceStore(context: ModelContext(host)).record(forKey: key)?.lastFailureAt)
        _ = await worker.run(request, progress: { _ in }, shouldContinue: nil)
        XCTAssertEqual(PriceStore(context: ModelContext(host)).record(forKey: key)?.effectiveUnitMarketPriceUSD, 8.16)
        XCTAssertEqual(try ModelContext(host).fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testProviderFailureKeepsLastGoodPriceAndOwnedCopiesAcrossRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("collection.store")
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource()
        let host = try container(url: url), bound = try await runtimes(registry, source: source).bound(to: host)
        let card = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id()).card
        let collection = CollectionStore(context: host.mainContext)
        for (variant, count) in [(PhysicalVariant.normal, 2), (.foil, 3)] {
            _ = try collection.add(card, resolved: .init(variant: variant, resolution: .userConfirmed), quantity: count)
        }
        let oldDate = Date.now.addingTimeInterval(-3 * 86_400)
        let prices = PriceStore(context: host.mainContext)
        var price = NormalizedPrice(unitMarketPriceUSD: 7.25, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:510153:Holofoil", sourceUpdatedAt: nil, fetchedAt: oldDate)
        price.catalogIdentity = LorcanaPriceAdapter.mappingIdentity(mapping())
        XCTAssertTrue(prices.store(.price(price), game: .lorcana, printingID: card.physicalPrintingID, variantID: "foil", at: oldDate))
        XCTAssertTrue(prices.save())
        await source.fail(with: .notConnectedToInternet)
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(bound.makePriceQuoteService())
        _ = await worker.run(.init(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
        let reopened = try container(url: url)
        let key = PriceRecord.key(game: .lorcana, printingID: card.physicalPrintingID, variantID: "foil")
        let retained = try XCTUnwrap(PriceStore(context: reopened.mainContext).record(forKey: key))
        XCTAssertEqual(retained.effectiveUnitMarketPriceUSD, 7.25)
        XCTAssertEqual(retained.fetchedAt, oldDate)
        XCTAssertNotNil(retained.lastFailureAt)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.variantID!, $0.quantity) }), ["normal": 2, "foil": 3])
        await source.fail(with: nil)
        let service = try await runtimes(registry, source: source).bound(to: reopened).makePriceQuoteService()
        let recovered = try await service.refreshStoredPrinting(game: .lorcana, printingID: card.physicalPrintingID, variant: .foil)
        let reopenedPrices = PriceStore(context: reopened.mainContext)
        XCTAssertTrue(reopenedPrices.store(recovered, game: .lorcana, printingID: card.physicalPrintingID, variantID: "foil"))
        XCTAssertTrue(reopenedPrices.save())
        XCTAssertEqual(reopenedPrices.record(forKey: key)?.effectiveUnitMarketPriceUSD, 8.16)
        XCTAssertNil(reopenedPrices.record(forKey: key)?.lastFailureAt)
    }

    func testTransportInterruptionCanRetryImmediatelyAfterConnectionRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LorcanaPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LorcanaPricingProtocol.self]
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cancelled] {
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let source = LorcanaTCGCSVPriceSource(transport: .init(session: session,
                cacheDirectory: root.appendingPathComponent(String(code.rawValue))))
            LorcanaPricingProtocol.handler = { _ in throw URLError(code) }
            do {
                _ = try await source.quote(mapping: mapping(), generation: "recovery", minimumFetchedAt: nil)
                XCTFail("Expected the interrupted request to fail")
            } catch let error as URLError { XCTAssertEqual(error.code, code) }
            LorcanaPricingProtocol.handler = { request in
                Data((request.url!.lastPathComponent == "products"
                    ? #"{"success":true,"errors":[],"results":[{"productId":510153,"categoryId":71,"groupId":22937,"name":"Fixture Elsa","extendedData":[{"name":"Number","value":"207/204"}]}]}"#
                    : #"{"success":true,"errors":[],"results":[{"productId":510153,"subTypeName":"Holofoil","marketPrice":8.16}]}"#).utf8)
            }
            do {
                let result = try await source.quote(mapping: mapping(), generation: "recovery", minimumFetchedAt: nil)
                guard case let .price(price) = result else { XCTFail("Expected a recovered quote"); continue }
                XCTAssertEqual(price.unitMarketPriceUSD, 8.16)
            } catch { XCTFail("Recovered connection must not inherit a provider cooldown: \(code): \(error)") }
        }
    }

    func testMalformedFeedStillUsesProviderCooldown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); LorcanaPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LorcanaPricingProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let source = LorcanaTCGCSVPriceSource(transport: .init(session: session, cacheDirectory: root))
        LorcanaPricingProtocol.handler = { _ in Data("not a valid feed".utf8) }
        do { _ = try await source.quote(mapping: mapping(), generation: "recovery", minimumFetchedAt: nil); XCTFail() }
        catch is DecodingError {}
        LorcanaPricingProtocol.handler = { _ in XCTFail("Rejected feed retains its cooldown"); return Data() }
        do { _ = try await source.quote(mapping: mapping(), generation: "recovery", minimumFetchedAt: nil); XCTFail() }
        catch PriceQuoteError.providerUnavailable {}
    }

    func testBoundStoredRefreshPropagatesPersistedWithdrawalWatermark() async throws {
        let registry = try registry(mappings: [mapping()]), source = LorcanaTestPriceSource(), container = try container()
        let bound = try await runtimes(registry, source: source).bound(to: container)
        let printing = id().uuidString.lowercased(), watermark = Date.now.addingTimeInterval(-1)
        let record = PriceRecord(key: PriceRecord.key(game: .lorcana, printingID: printing, variantID: "foil"),
            game: .lorcana, printingID: printing, variantID: "foil")
        record.invalidatedAt = watermark; container.mainContext.insert(record); try container.mainContext.save()
        _ = try await bound.makePriceQuoteService().refreshStoredPrinting(game: .lorcana, printingID: printing, variant: .foil)
        let minimum = await source.minimum; XCTAssertEqual(minimum, watermark)
    }

    #if DEBUG && LOCAL_ONLY_SIGNING
    func testNormalAppRegistersReviewedPricingAndPreservesDiscoveryAndSealed() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        XCTAssertEqual(catalog.cardsByID.count, 3_582)
        XCTAssertEqual(catalog.products.count, 177)
        XCTAssertEqual(catalog.registry.physicalCatalog?.manifest.physicalPrintings.count, 1_749)
        XCTAssertEqual(LorcanaPriceAdapter.priceAuthority(catalog.registry).identityByPriceKey.count, 3_364)
        let module = try XCTUnwrap(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana))
        XCTAssertTrue(module.descriptor.capabilities.contains(.pricing))
        XCTAssertTrue(module.descriptor.capabilities.contains(.collectionWrite))
        let bound = try await CardGameRuntimeContainer.appDefaults().bound(to: container())
        XCTAssertTrue(bound.makePriceQuoteService().supportsPricing(for: .lorcana))
        guard case let .identified(subject) = LorcanaDiscoveryRecognizer(catalog: catalog).identify([.init(text: "1/204 EN 1")]),
              case let .resolved(resolution) = try await catalog.lookup(subject.identifier) else { return XCTFail() }
        let card = resolution.card
        XCTAssertNotNil(UUID(uuidString: card.providerID))
        XCTAssertEqual(card.name, "Ariel - On Human Legs")
        try await catalog.validateAcquisition(subject.identifier, printingID: card.providerID, automatic: true)
        // Full title search and footer lookup share the same UUID/finish authority.
        let page = try await catalog.search(query: "Ariel", setIDs: [], cursor: nil)
        let summary = try XCTUnwrap(page.items.first { $0.providerID == card.providerID })
        let details = try await catalog.details(for: summary)
        XCTAssertEqual(details.card.collectionKey(variant: .foil), card.collectionKey(variant: .foil))
        XCTAssertNil(details.collectionWriteUnavailableReason)
        let heldPage = try await catalog.search(query: "Elsa", setIDs: [], cursor: nil)
        let heldSummary = try XCTUnwrap(heldPage.items.first { $0.collectorNumber == "210" })
        let heldDetails = try await catalog.details(for: heldSummary)
        XCTAssertNotNil(heldDetails.collectionWriteUnavailableReason)
        guard case let .identified(held) = LorcanaDiscoveryRecognizer(catalog: catalog).identify([.init(text: "210/204 EN 9")]),
              case let .needsPrintingChoice(_, candidates) = try await catalog.lookup(held.identifier) else { return XCTFail() }
        do {
            try await catalog.validateAcquisition(held.identifier, printingID: try XCTUnwrap(candidates.first).id, automatic: false)
            XCTFail("Later unreviewed Enchanted cannot inherit the first-eight-set policy")
        } catch CatalogLookupError.catalogIncomplete {}
    }

    func testNormalAppScannerSavesReviewedPrintingThroughBoundAuthority() async throws {
        let host = try container()
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let module = catalog.runtime
        let runtime = CardGameRuntime(descriptor: module.descriptor, variantPolicy: module.variantPolicy,
            pricing: LorcanaPriceAdapter(registry: catalog.registry, source: LorcanaTestPriceSource()),
            recognizer: module.recognizer, catalog: module.catalog, browse: module.browse, importer: module.importer,
            priceAuthority: module.priceAuthority, requiresLaunchActivation: false)
        let bound = try await CardGameRuntimeContainer(runtimes: [runtime]).bound(to: host)
        let model = bound.makeScannerModel()
        model.start(context: host.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        guard case let .identified(subject) = LorcanaDiscoveryRecognizer(catalog: catalog).identify([.init(text: "1/204 EN 1")]) else { return XCTFail() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let ready = await waitUntil { model.pendingChoice != nil }; XCTAssertTrue(ready)
        model.choose(.normal)
        let saved = await waitUntil { model.successCount == 1 }; XCTAssertTrue(saved)
        let rows = try host.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count,1)
        XCTAssertEqual(rows.first?.game, "lorcana")
    }

    func testAll132EnchantedPrintingsResolveAndImportAsTheirOwnFoilIdentity() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let physical = try XCTUnwrap(catalog.registry.physicalCatalog)
        let enchanted = physical.manifest.physicalPrintings.filter { $0.identity.distributionID.hasPrefix("enchanted-expansion-") }
        XCTAssertEqual(enchanted.count, 132)
        let importer = LorcanaImportAdapter(registry: catalog.registry)
        for printing in enchanted {
            let footer = printing.identity.footer
            guard case let .identified(subject) = LorcanaDiscoveryRecognizer(catalog: catalog).identify([.init(text: footer.displayIdentifier)]),
                  case let .resolved(resolution) = try await catalog.lookup(subject.identifier) else {
                return XCTFail("Enchanted footer must resolve: \(footer)")
            }
            let card = resolution.card
            XCTAssertEqual(card.providerID, printing.id.uuidString.lowercased())
            XCTAssertEqual(card.variantEvidence.catalogVariants, [.foil])
            try await catalog.validateAcquisition(subject.identifier, printingID: card.providerID, automatic: true)
            let csv = "game,provider_id,card_name,card_number,finish,quantity\nlorcana,\(card.providerID),Enchanted,\(footer.displayIdentifier),foil,1\n"
            let entry = try XCTUnwrap(CollectionCSV.parse(Data(csv.utf8)).entries.first)
            try importer.validate(entry)
            XCTAssertEqual(entry.collectionKey, card.collectionKey(variant: .foil))
            let mapping = try XCTUnwrap(printing.marketMappings?.first)
            XCTAssertEqual(mapping.providerVariantID, "Holofoil")
            XCTAssertEqual(mapping.finish, .foil)
            XCTAssertEqual(printing.marketMappings?.count, 1)
        }
    }

    func testLiveNormalAppMultiSetPricing() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let bytes = try? Data(contentsOf: documents.appendingPathComponent("lorcana-live-pricing-acceptance.json")),
              let options = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let expiry = options["expiresAt"] as? Double, expiry > Date.now.timeIntervalSince1970,
              expiry < Date.now.addingTimeInterval(7_200).timeIntervalSince1970,
              let seed = Bundle.main.url(forResource: "market", withExtension: "json", subdirectory: "LorcanaCatalogSeed"),
              options["marketCatalogSHA256"] as? String == SHA256.hash(data: try Data(contentsOf: seed)).map({ String(format: "%02x", $0) }).joined()
        else { throw XCTSkip("Normal workflow live acceptance requires a seed-bound opt-in") }
        let host = try container()
        let bound = try await CardGameRuntimeContainer.appDefaults().bound(to: host)
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let service = bound.makePriceQuoteService()
        var observations: [[String: Any]] = []
        for code in 1...8 {
            let eligible = catalog.registry.physicalCatalog?.manifest.physicalPrintings.filter {
                $0.providerSetCode == String(code) && !($0.marketMappings ?? []).isEmpty
            } ?? []
            let printing = try XCTUnwrap(eligible.min {
                Int($0.identity.footer.collectorNumber)! < Int($1.identity.footer.collectorNumber)!
            })
            let card = try LorcanaCatalogAdapter(registry: catalog.registry).resolution(forPrintingID: printing.id).card
            for variant in [PhysicalVariant.normal, .foil] {
                guard case let .price(price) = try await service.refresh(card: card, variant: variant, pokemonPrintRun: nil)
                else { return XCTFail("Missing live quote for set \(code) / \(variant.id)") }
                let mapping = try XCTUnwrap(printing.marketMappings?.first { $0.finish.rawValue == variant.id })
                XCTAssertEqual(price.sourceVariantID, "tcgplayer:\(mapping.productID):\(mapping.providerVariantID)")
                XCTAssertEqual(price.catalogIdentity, LorcanaPriceAdapter.mappingIdentity(mapping))
                XCTAssertEqual(price.currencyCode,"USD")
                observations.append(["set":code,"name":card.name,"printingID":card.providerID,"finish":variant.id,
                    "amountUSD":price.unitMarketPriceUSD,"lane":price.sourceVariantID,
                    "fetchedAt":ISO8601DateFormatter().string(from:price.fetchedAt)])
            }
            _ = try CollectionStore(context: host.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        }
        XCTAssertEqual(try host.mainContext.fetch(FetchDescriptor<CollectedCard>()).count,8)
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(service)
        _ = await worker.run(.init(usesPriceFallback: false,includeImported: true,forceUnsupportedRetry: true,
            sortOldestFirst: false,maximumTargetCount: nil,markRecentlyCheckedIfEmpty: false),progress:{_ in},shouldContinue:nil)
        XCTAssertEqual(try ModelContext(host).fetch(FetchDescriptor<PriceRecord>()).filter { $0.effectiveUnitMarketPriceUSD != nil }.count,8)
        try JSONSerialization.data(withJSONObject:["catalogGeneration":catalog.generation,"observations":observations],options:[.prettyPrinted,.sortedKeys])
            .write(to:documents.appendingPathComponent("lorcana-normal-live-results.json"),options:.atomic)
    }

    /// Revalidates every enabled lane using fresh group feeds through the shared
    /// quote service. Null market values are availability, never identity evidence.
    func testLiveAllMappedPrintingPrices() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let bytes = try? Data(contentsOf: documents.appendingPathComponent("lorcana-live-pricing-acceptance.json")),
              let options = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let expiry = options["expiresAt"] as? Double, expiry > Date.now.timeIntervalSince1970,
              expiry < Date.now.addingTimeInterval(7_200).timeIntervalSince1970,
              let seed = Bundle.main.url(forResource: "market", withExtension: "json", subdirectory: "LorcanaCatalogSeed"),
              options["marketCatalogSHA256"] as? String == SHA256.hash(data: try Data(contentsOf: seed)).map({ String(format: "%02x", $0) }).joined()
        else { throw XCTSkip("All-mapping live acceptance requires a seed-bound opt-in") }

        let startedAt = Date.now
        let root = documents.appendingPathComponent("LorcanaAllMappedLive-" + UUID().uuidString)
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let printings = try XCTUnwrap(catalog.registry.physicalCatalog).manifest.physicalPrintings
            .filter { !($0.marketMappings ?? []).isEmpty }.sorted { $0.id.uuidString < $1.id.uuidString }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = LorcanaTCGCSVPriceSource(transport: .init(session: session,
            cacheDirectory: root.appendingPathComponent("feed")))
        let bound = try await runtimes(catalog.registry, source: source).bound(to: container())
        let service = bound.makePriceQuoteService()
        var observations: [[String: Any]] = []
        var priced = 0, unavailable = 0
        for printing in printings {
            let card = try LorcanaCatalogAdapter(registry: catalog.registry).resolution(forPrintingID: printing.id).card
            for mapping in printing.marketMappings ?? [] {
                let variant: PhysicalVariant = mapping.finish == .normal ? .normal : .foil
                let quote = try await service.refresh(card: card, variant: variant, pokemonPrintRun: nil)
                var observation: [String: Any] = ["printingID": card.physicalPrintingID,
                    "set": printing.providerSetCode, "finish": variant.id,
                    "productID": mapping.productID, "lane": mapping.providerVariantID]
                switch quote {
                case let .price(price):
                    XCTAssertEqual(price.sourceVariantID, "tcgplayer:\(mapping.productID):\(mapping.providerVariantID)")
                    XCTAssertEqual(price.catalogIdentity, LorcanaPriceAdapter.mappingIdentity(mapping))
                    XCTAssertEqual(price.source, .tcgCSV)
                    XCTAssertEqual(price.currencyCode, "USD")
                    XCTAssertGreaterThanOrEqual(price.fetchedAt, startedAt)
                    XCTAssertTrue(price.unitMarketPriceUSD.isFinite && price.unitMarketPriceUSD >= 0)
                    observation["amountUSD"] = price.unitMarketPriceUSD
                    priced += 1
                case let .unavailable(provider):
                    XCTAssertEqual(provider, .tcgCSV)
                    observation["unavailable"] = true
                    unavailable += 1
                }
                observations.append(observation)
            }
        }
        XCTAssertFalse(printings.isEmpty)
        XCTAssertEqual(observations.count, printings.reduce(0) { $0 + ($1.marketMappings?.count ?? 0) })
        try JSONSerialization.data(withJSONObject: ["catalogGeneration": catalog.generation,
            "priced": priced, "unavailable": unavailable, "observations": observations], options: [.sortedKeys])
            .write(to: documents.appendingPathComponent("lorcana-all-mapped-live-results.json"), options: .atomic)
        print("LORCANA_ALL_MAPPED_LIVE printings=\(printings.count) priced=\(priced) unavailable=\(unavailable)")
    }

    func testPublicReviewSeedKeepsSizeAndMarketAuthoritySeparate() throws {
        let manifest = try LorcanaReviewLaunch.pricingManifest()
        let registry = try LorcanaCatalogRegistry(manifest: manifest)
        let standard = try XCTUnwrap(manifest.physicalPrintings.first { $0.identity.size == .standard })
        let oversized = try XCTUnwrap(manifest.physicalPrintings.first { $0.identity.size == .oversized })
        XCTAssertEqual(standard.marketMappings?.map(\.providerVariantID), ["Normal", "Cold Foil"])
        XCTAssertEqual(Set(standard.marketMappings?.map(\.productID) ?? []), [485364])
        XCTAssertTrue((oversized.marketMappings ?? []).isEmpty)
        XCTAssertEqual(LorcanaPriceAdapter.priceAuthority(registry).identityByPriceKey.count, 2)
        let withdrawn = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.pricingManifest(withdrawn: true), previous: registry)
        XCTAssertNotEqual(registry.generation, withdrawn.generation)
        XCTAssertTrue(LorcanaPriceAdapter.priceAuthority(withdrawn).identityByPriceKey.isEmpty)
        let before = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: standard.id).card
        let after = try LorcanaCatalogAdapter(registry: withdrawn).resolution(forPrintingID: standard.id).card
        XCTAssertEqual(before.collectionKey(variant: .foil), after.collectionKey(variant: .foil))
        XCTAssertTrue(LorcanaReviewLaunch.isEnabled(arguments: ["-ui_debug_route", "LorcanaPricingReview"]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest, root: root, storageDirectory: "LorcanaPricingReview")
        XCTAssertEqual(kit.collectionDirectory.lastPathComponent, "LorcanaPricingReview")
        XCTAssertThrowsError(try LorcanaLocalReviewKit.make(manifest: manifest, root: root, storageDirectory: "../"))
    }

    /// Explicit short-lived file opt-in prevents normal/offline test runs from
    /// making provider requests. The file binds acceptance to this exact seed.
    func testLivePublicReviewPricingWorkflow() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let optIn = documents.appendingPathComponent("lorcana-live-pricing-acceptance.json")
        guard let data = try? Data(contentsOf: optIn),
              let options = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = options["expiresAt"] as? Double, expiry > Date.now.timeIntervalSince1970,
              expiry < Date.now.addingTimeInterval(7_200).timeIntervalSince1970,
              let seedURL = Bundle.main.url(forResource: "pricing-review", withExtension: "json", subdirectory: "LorcanaCatalogSeed"),
              options["catalogSHA256"] as? String == SHA256.hash(data: try Data(contentsOf: seedURL)).map({ String(format: "%02x", $0) }).joined()
        else { throw XCTSkip("Live Lorcana acceptance requires an unexpired, seed-bound local opt-in") }

        let root = documents.appendingPathComponent("LorcanaLivePricing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.pricingManifest())
        let standard = try XCTUnwrap(registry.physicalCatalog?.manifest.physicalPrintings.first { $0.identity.size == .standard })
        let oversized = try XCTUnwrap(registry.physicalCatalog?.manifest.physicalPrintings.first { $0.identity.size == .oversized })
        let source = LorcanaTCGCSVPriceSource(transport: .init(session: URLSession(configuration: .ephemeral),
                                                            cacheDirectory: root.appendingPathComponent("feed")))
        let host = try container(url: root.appendingPathComponent("collection.store"))
        let bound = try await runtimes(registry, source: source).bound(to: host)
        let service = bound.makePriceQuoteService(), catalog = LorcanaCatalogAdapter(registry: registry)
        let base = try catalog.resolution(forPrintingID: standard.id).card
        let special = try catalog.resolution(forPrintingID: oversized.id).card
        let normal = try await service.refreshStoredPrinting(game: .lorcana, printingID: base.providerID, variant: .normal)
        let foil = try await service.refreshStoredPrinting(game: .lorcana, printingID: base.providerID, variant: .foil)
        guard case let .price(normalPrice) = normal, case let .price(foilPrice) = foil else { return XCTFail("Live base prices unavailable") }
        XCTAssertEqual(normalPrice.sourceVariantID, "tcgplayer:485364:Normal")
        XCTAssertEqual(foilPrice.sourceVariantID, "tcgplayer:485364:Cold Foil")
        XCTAssertEqual(normalPrice.currencyCode, "USD"); XCTAssertNil(foilPrice.sourceUpdatedAt)
        XCTAssertEqual(normalPrice.fetchedAt, foilPrice.fetchedAt)
        XCTAssertEqual(foilPrice.catalogIdentity, LorcanaPriceAdapter.mappingIdentity(try XCTUnwrap(standard.marketMappings?.last)))
        do { _ = try await service.refreshStoredPrinting(game: .lorcana, printingID: special.providerID, variant: .foil); XCTFail("Expected mapping gap") }
        catch PriceQuoteError.mappingUnavailable {}

        let identifier = try LorcanaRecognitionAdapter.identifier(standard.identity.footer, generation: registry.generation)
        let scan = ResolvedScan(request: .init(subject: .init(identifier: identifier), purpose: .priceCheck, generation: 0),
            card: base, resolved: .init(variant: .foil, resolution: .userConfirmed), pokemonPrintRun: nil,
            options: [.normal, .foil], catalogRetrievedAt: now)
        let priceCheck = PriceCheckCoordinator(context: host.mainContext, quoteService: service)
        guard case let .quote(.price(checked)) = await priceCheck.refresh(priceCheck.present(scan)) else { return XCTFail() }
        XCTAssertEqual(checked, foilPrice)
        XCTAssertTrue(try host.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)

        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: service, catalog: bound.makeCardCatalog(),
            unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: host.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: identifier), nil)
        let printingReady = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(printingReady)
        let choice = try XCTUnwrap(model.pendingIdentityChoice)
        let candidate = try XCTUnwrap(choice.displayCandidates.first { $0.id == base.providerID })
        model.choose(candidate)
        let finishReady = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(finishReady)
        model.choose(.foil)
        let priceKey = PriceRecord.key(game: .lorcana, printingID: base.providerID, variantID: "foil")
        let savedPriceReady = await waitUntil { PriceStore(context: ModelContext(host)).record(forKey: priceKey)?.effectiveUnitMarketPriceUSD == foilPrice.unitMarketPriceUSD }
        XCTAssertTrue(savedPriceReady)
        XCTAssertEqual(model.successCount, 1)
        _ = try CollectionStore(context: host.mainContext).add(special, resolved: .init(variant: .foil, resolution: .userConfirmed))

        let browse = BrowseCatalog(cache: CatalogCacheStore(root: root.appendingPathComponent("browse")), gameRegistry: bound.registry,
            gameBrowseAdapters: try .init(adapters: [LorcanaBrowseAdapter(registry: registry)]), priceQuoteService: service)
        let sets = try await browse.sets(for: .lorcana)
        let set = try XCTUnwrap(sets.first)
        let page = try await browse.cards(in: set, cursor: nil)
        let summary = try XCTUnwrap(page.items.first { $0.providerID == base.providerID })
        let browseQuote = try await browse.price(for: summary, variant: .foil)
        XCTAssertEqual(browseQuote, foil)
        let worker = PriceRefreshModelActor(modelContainer: host)
        await worker.configureGamePricing(service)
        _ = await worker.run(.init(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
        let reopened = try container(url: root.appendingPathComponent("collection.store"))
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).count, 2)
        let persisted = PriceStore(context: reopened.mainContext)
        XCTAssertEqual(persisted.record(forKey: priceKey)?.effectiveUnitMarketPriceUSD, foilPrice.unitMarketPriceUSD)
        XCTAssertNil(persisted.record(forKey: PriceRecord.key(game: .lorcana, printingID: special.providerID, variantID: "foil"))?.effectiveUnitMarketPriceUSD)

        let offlineConfig = URLSessionConfiguration.ephemeral; offlineConfig.protocolClasses = [LorcanaPricingProtocol.self]
        LorcanaPricingProtocol.handler = { _ in XCTFail("Relaunch must retain the live receipt without network"); throw URLError(.notConnectedToInternet) }
        defer { LorcanaPricingProtocol.handler = nil }
        let offline = LorcanaPriceAdapter(registry: registry, source: LorcanaTCGCSVPriceSource(transport:
            .init(session: URLSession(configuration: offlineConfig), cacheDirectory: root.appendingPathComponent("feed"))))
        let cached = try await offline.refreshStoredPrinting(base.providerID, variant: .foil)
        XCTAssertEqual(cached, foil)

        let withdrawn = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.pricingManifest(withdrawn: true), previous: registry)
        let withdrawnRuntime = try await runtimes(withdrawn, source: source).bound(to: reopened)
        XCTAssertNil(PriceStore(context: ModelContext(reopened)).record(forKey: priceKey)?.effectiveUnitMarketPriceUSD)
        do { _ = try await withdrawnRuntime.makePriceQuoteService().refreshStoredPrinting(game: .lorcana, printingID: base.providerID, variant: .foil); XCTFail("Expected mapping gap") }
        catch PriceQuoteError.mappingUnavailable {}
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).count, 2)

        let report: [String: Any] = ["passed": true, "catalogGeneration": registry.generation,
            "normalUSD": normalPrice.unitMarketPriceUSD, "foilUSD": foilPrice.unitMarketPriceUSD,
            "fetchedAt": ISO8601DateFormatter().string(from: foilPrice.fetchedAt), "source": "tcgCSV",
            "normalLane": normalPrice.sourceVariantID, "foilLane": foilPrice.sourceVariantID,
            "unmappedOversized": true, "withdrawalPreservesOwnedRows": true, "artifactDirectory": root.lastPathComponent]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: documents.appendingPathComponent("lorcana-live-pricing-results.json"), options: .atomic)
    }
    #endif
}
