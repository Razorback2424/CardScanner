import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

/// All fixture review references are synthetic; they prove contracts only.
enum YuGiOhFixture {
    static func object(count: Int = 1, complete: Bool = true, auto: Bool = true, identical: Bool = false,
                       editions: [String] = ["yugioh1stEdition", "yugiohUnlimited"], priced: [String] = ["yugioh1stEdition"]) -> [String: Any] {
        let rows: [[String: Any]] = (1...count).map { index in
            ["id": DeterministicUUID.make(namespace: "yugioh-printing:", material: "tcgplayer:2:\(index)").uuidString.lowercased(),
             "c": "RA02-EN037", "g": 23416, "k": 0, "r": identical ? "Rare" : "Rare \(index)", "p": index,
             "pn": "Fixture Card \(index)", "e": editions, "ec": complete, "ee": "synthetic:physical-edition-review",
             "pe": priced, "img": "https://example.com/\(index)_200w.jpg"]
        }
        return ["schemaVersion": 1, "generation": "yugioh-en-fixture", "capturedAt": "2026-10-20T00:00:00Z",
            "sets": [["g": 23416, "n": "Fixture Set", "a": "RA02", "d": "2024-05-24"]],
            "cards": [["id": "81000000-0000-0000-0000-000000000001", "n": "Fixture Card", "pc": [66011101]]],
            "printings": rows, "incompleteCodes": [], "autoEligibleCodes": auto && count == 1 && complete ? ["RA02-EN037"] : []]
    }
    static func catalog(count: Int = 1, complete: Bool = true, auto: Bool = true, identical: Bool = false,
                        editions: [String] = ["yugioh1stEdition", "yugiohUnlimited"], priced: [String] = ["yugioh1stEdition"]) throws -> YuGiOhCatalog {
        try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object(count: count, complete: complete, auto: auto,
            identical: identical, editions: editions, priced: priced)))
    }
    static func identifier(_ catalog: YuGiOhCatalog) throws -> ScanIdentifier {
        try YuGiOhRecognitionAdapter.identifier(code: "RA02-EN037", generation: catalog.generation)
    }
    static func subject(_ catalog: YuGiOhCatalog, _ edition: PrintedEditionEvidence = .absent) throws -> ScanSubject {
        .init(identifier: try identifier(catalog), printedEdition: edition)
    }
    static func evidence(_ editions: [PhysicalVariant], complete: Bool = true) -> VariantEvidence {
        .init(game: .yuGiOh, setID: "fixture", cardNumber: "RA02-EN037", catalogVariants: editions, physicalCoverageVerified: complete)
    }
}

private actor YuGiOhTestPriceSource: YuGiOhMarketPriceSource {
    var available = false
    var calls: [String] = []
    func enable() { available = true }
    func quote(printing: YuGiOhCatalog.Printing, edition: YuGiOhEdition, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup {
        calls.append("2:\(printing.set.groupID):\(printing.productID):\(edition.tcgplayerSubtype)")
        guard available else { return .unavailable(.tcgCSV) }
        return .price(.init(unitMarketPriceUSD: 12.34, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(printing.productID):\(edition.tcgplayerSubtype)", sourceUpdatedAt: nil, fetchedAt: .now))
    }
}

private final class YuGiOhPricingProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class YuGiOhPricingTests: XCTestCase {
    func testMissingSeedLaneCanBecomeAvailableWithoutReplacingSeed() async throws {
        let catalog = try YuGiOhFixture.catalog(), p = try XCTUnwrap(catalog.printingByID.values.first)
        XCTAssertFalse(p.pricedEditions.contains(.unlimited))
        let source = YuGiOhTestPriceSource(), adapter = YuGiOhPriceAdapter(catalog: catalog, source: source)
        let missing = try await adapter.refreshStoredPrinting(p.idString, variant: .yugiohUnlimited)
        guard case .unavailable = missing else { return XCTFail() }
        await source.enable()
        let fresh = try await adapter.refreshStoredPrinting(p.idString, variant: .yugiohUnlimited)
        guard case let .price(price) = fresh else { return XCTFail() }
        XCTAssertEqual(price.unitMarketPriceUSD, 12.34)
        XCTAssertEqual(price.catalogIdentity, "tcgcsv:2:23416:1:Unlimited")
        let calls = await source.calls
        XCTAssertEqual(calls, ["2:23416:1:Unlimited", "2:23416:1:Unlimited"])
        XCTAssertEqual(YuGiOhPriceAdapter.priceAuthority(catalog).identityByPriceKey.count, 2)
        do { _ = try await adapter.refreshStoredPrinting(p.idString, variant: .yugiohLimited); XCTFail() }
        catch PriceQuoteError.identityMismatch {}
    }
    func testTransportMissingNullAndLaterMarketQuoteNeverSubstitutes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-prices-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root); YuGiOhPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [YuGiOhPricingProtocol.self]
        var mode = 0, priceRequests = 0
        YuGiOhPricingProtocol.handler = { request in
            if request.url!.path.hasSuffix("products") {
                return Data(#"{"success":true,"errors":[],"results":[{"productId":1,"categoryId":2,"groupId":23416,"name":"Fixture Card 1","extendedData":[{"name":"Number","value":"RA02-EN037"}]}]}"#.utf8)
            }
            priceRequests += 1
            let target: [String: Any] = ["productId": 1, "subTypeName": "Unlimited", "marketPrice": mode == 2 ? 42 : NSNull(), "lowPrice": 1, "midPrice": 2]
            let rows: [[String: Any]] = mode == 0 ? [["productId": 1, "subTypeName": "1st Edition", "marketPrice": 99]] : [target]
            return try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": rows])
        }
        let transport = TCGCSVProductPriceSource(session: URLSession(configuration: config), cacheDirectory: root)
        var watermark: Date? = nil
        for next in 0...2 {
            mode = next
            let quote = try await transport.quote(category: 2, group: 23416, productID: 1, name: "Fixture Card 1", number: "RA02-EN037", lane: "Unlimited", generation: "fixture", minimumFetchedAt: watermark)
            if next < 2 { guard case .unavailable(.tcgCSV) = quote else { return XCTFail() } }
            else { guard case let .price(price) = quote else { return XCTFail() }; XCTAssertEqual(price.unitMarketPriceUSD, 42) }
            watermark = .now
        }
        XCTAssertEqual(priceRequests, 3, "Each mode must be a newly fetched response, including the null lane")
        do { _ = try await transport.quote(category: 2, group: 23416, productID: 1, name: "Fixture Card 1", number: "RA02-EN037", lane: "Reverse Holofoil", generation: nil, minimumFetchedAt: nil); XCTFail() }
        catch PriceQuoteError.identityMismatch {}
    }
}

@MainActor
final class YuGiOhImportTests: XCTestCase {
    func testExactImportContracts() throws {
        let catalog = try YuGiOhFixture.catalog(), adapter = YuGiOhImportAdapter(catalog: catalog)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        func entry(finish: String = "yugioh1stEdition", provider: String? = nil, key: String = "") throws -> CollectionCSVEntry {
            let csv = "game,provider_id,card_name,card_number,finish,quantity\(key.isEmpty ? "" : ",collection_key")\nyu-gi-oh,\(provider ?? p.idString),Fixture Card,RA02-EN037,\(finish),1\(key.isEmpty ? "" : "," + key)\n"
            return try XCTUnwrap(CollectionCSV.parse(Data(csv.utf8)).entries.first)
        }
        XCTAssertNoThrow(try adapter.validate(entry()))
        XCTAssertThrowsError(try adapter.validate(entry(finish: "")))
        XCTAssertThrowsError(try adapter.validate(entry(finish: "yugiohLimited")))
        XCTAssertThrowsError(try adapter.validate(entry(provider: "not-a-uuid")))
        XCTAssertThrowsError(try adapter.validate(entry(key: "yu-gi-oh:wrong#yugioh1stEdition")))
        let unknown = YuGiOhImportAdapter(catalog: try YuGiOhFixture.catalog(complete: false))
        XCTAssertThrowsError(try unknown.validate(entry()))
    }
}

@MainActor
final class YuGiOhWorkflowTests: XCTestCase {
    private func container(_ url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema([CollectedCard.self, CollectionActivity.self, InventoryEvent.self, PriceRecord.self, ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }
    func testScanPrintingEditionSaveRefreshCSVImportAndPersistenceChain() async throws {
        try await runChain(printedEdition: false)
    }
    func testObservedEditionScanThroughPersistenceChain() async throws {
        try await runChain(printedEdition: true)
    }
    private func runChain(printedEdition: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-chain-\(UUID())")
        // SwiftData actors can outlive local containers; leave isolated stores
        // in the simulator's temporary directory rather than unlink open SQLite files.
        let catalog = try YuGiOhFixture.catalog(count: 2), source = YuGiOhTestPriceSource()
        let module = YuGiOhGameRuntime(catalog: catalog).runtime
        let runtime = CardGameRuntime(descriptor: module.descriptor, variantPolicy: module.variantPolicy,
            pricing: YuGiOhPriceAdapter(catalog: catalog, source: source), recognizer: module.recognizer,
            catalog: module.catalog, browse: module.browse, importer: module.importer,
            priceAuthority: module.priceAuthority, requiresLaunchActivation: false)
        let runtimes = try CardGameRuntimeContainer(runtimes: [runtime])
        let original = try container(root.appendingPathComponent("source.store")), bound = try await runtimes.bound(to: original)
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
            catalog: bound.makeCardCatalog(), unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        let recognizer = YuGiOhRecognitionAdapter(catalog: catalog)
        let lines = [RecognizedLine(text: "RA02-EN037")] + (printedEdition ? [.init(text: "1st Edition")] : [])
        guard case let .identified(subject) = recognizer.identify(lines) else { return XCTFail() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let pending = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(pending)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let choice = try XCTUnwrap(model.pendingIdentityChoice?.printingCandidates.first)
        model.choose(choice)
        if !printedEdition {
            let editionPending = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(editionPending)
            XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            model.choose(.yugiohUnlimited)
        }
        let edition: PhysicalVariant = printedEdition ? .yugiohFirstEdition : .yugiohUnlimited
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        let row = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        let key = "yu-gi-oh:\(choice.id)#\(edition.id)"
        XCTAssertEqual(row.collectionKey, key); XCTAssertEqual(row.catalogProviderID, choice.id)
        await source.enable()
        let fresh = try await YuGiOhPriceAdapter(catalog: catalog, source: source).refreshStoredPrinting(choice.id, variant: edition)
        let prices = PriceStore(context: original.mainContext)
        XCTAssertTrue(prices.store(fresh, game: .yuGiOh, printingID: choice.id, variantID: edition.id)); XCTAssertTrue(prices.save())
        let priceKey = PriceRecord.key(game: .yuGiOh, printingID: choice.id, variantID: edition.id)
        XCTAssertEqual(prices.record(forKey: priceKey)?.effectiveUnitMarketPriceUSD, 12.34)
        let csv = try await CollectionCSV.exportIsolated(from: original)
        let targetURL = root.appendingPathComponent("target.store"), target = try container(targetURL)
        let targetBound = try await runtimes.bound(to: target)
        let plan = try CollectionCSV.parse(Data(csv.text.utf8))
        let adapters = await targetBound.currentImportAdapters()
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        let result: CollectionCSVImportResult
        do {
            result = try await CollectionCSV.applyIsolated(plan, to: target, exclusiveToken: token, gameRegistry: targetBound.registry, gameImportAdapters: adapters)
            CollectionWriteSerializer.endExclusive(token)
        } catch { CollectionWriteSerializer.endExclusive(token); throw error }
        XCTAssertEqual(result.importedQuantity, 1); XCTAssertTrue(result.failedRows.isEmpty)
        let reopened = try container(targetURL), reloaded = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(reloaded.collectionKey, key); XCTAssertEqual(reloaded.catalogProviderID, choice.id)
        XCTAssertEqual(reloaded.variantID, edition.id)
        let reopenedSource = try container(root.appendingPathComponent("source.store"))
        XCTAssertEqual(PriceStore(context: reopenedSource.mainContext).record(forKey: priceKey)?.effectiveUnitMarketPriceUSD, 12.34)
    }
    func testConflictCannotWriteBeforeResolutionAndRetryPreservesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-conflict-\(UUID())")
        let catalog = try YuGiOhFixture.catalog(), store = try container(root.appendingPathComponent("collection.store"))
        let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: store)
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(), catalog: bound.makeCardCatalog(),
            unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: store.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), try YuGiOhFixture.subject(catalog, conflict), nil)
        let filed = await waitUntil { !model.unresolvedScans.isEmpty && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(filed); XCTAssertNil(model.pendingChoice)
        XCTAssertTrue(try store.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(model.unresolvedScans.first?.subject.printedEdition.isConflict == true)
        if let row = model.unresolvedScans.first { model.resolveUnresolved(id: row.id, choice: .retryLookup) }
        let retried = await waitUntil { !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(retried)
        XCTAssertTrue(try store.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(model.unresolvedScans.first?.subject.printedEdition.isConflict == true)
    }

    func testRefilingSameRecoveryRecordRetainsConflictWhileNewEncounterIsClean() throws {
        let catalog = try YuGiOhFixture.catalog()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-records-\(UUID())")
        let runtimes = try CardGameRuntimeContainer(runtimes: [catalog.runtime])
        let model = ScannerViewModel(gameRegistry: runtimes.registry, priceQuoteService: runtimes.makePriceQuoteService(),
            catalog: runtimes.makeCardCatalog(), unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        model.fileUnresolvedForTesting(try YuGiOhFixture.subject(catalog, conflict), reason: .noConfirmedMatch)
        let id = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.fileUnresolvedForTesting(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)), reason: .noConfirmedMatch, matchingID: id)
        XCTAssertTrue(model.unresolvedScans.first?.subject.printedEdition.isConflict == true)
        model.fileUnresolvedForTesting(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)), reason: .noConfirmedMatch)
        XCTAssertEqual(model.unresolvedScans.count, 2)
        XCTAssertEqual(model.unresolvedScans.last?.subject.printedEdition, .observed(.yugiohFirstEdition))
    }

    func testPriceCheckConflictResumesWithoutCollectionOrRecoveryWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-price-check-\(UUID())")
        let catalog = try YuGiOhFixture.catalog(), store = try container(root.appendingPathComponent("collection.store"))
        let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: store)
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(), catalog: bound.makeCardCatalog(),
            unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: store.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        model.setPurpose(.priceCheck)
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), try YuGiOhFixture.subject(catalog, conflict), nil)
        let handled = await waitUntil { model.note != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(handled); XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        XCTAssertTrue(try store.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }
}

final class YuGiOhCatalogTests: XCTestCase {
    func testBundledCatalogAndDeterministicPrintingIDs() throws {
        let catalog = try YuGiOhCatalog.bundled.get()
        XCTAssertTrue(catalog.generation.hasPrefix("yugioh-en-"))
        XCTAssertGreaterThan(catalog.printingsByCode.count, 10000)
        for p in catalog.printingByID.values {
            XCTAssertEqual(p.id, DeterministicUUID.make(namespace: "yugioh-printing:", material: "tcgplayer:2:\(p.productID)"))
        }
        for code in ["RA02-EN037", "GENF-EN098", "LOB-001", "LOB-EN001", "L26D-ENM26"] {
            XCTAssertNotNil(catalog.printingsByCode[code], code)
        }
        XCTAssertEqual(catalog.printingsByCode["RA02-EN037"]?.count, 7)
        XCTAssertEqual(catalog.printingsByCode["GENF-EN098"]?.count, 2)
        XCTAssertNotEqual(catalog.printingsByCode["LOB-001"]?.first?.id, catalog.printingsByCode["LOB-EN001"]?.first?.id)
    }
    func testUnknownPhysicalCoverageRemainsSeparateFromObservedPrices() throws {
        let catalog = try YuGiOhFixture.catalog(complete: false, editions: [])
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        XCTAssertFalse(p.coverageVerified); XCTAssertTrue(p.editions.isEmpty)
        XCTAssertEqual(p.pricedEditions, [.first])
        XCTAssertThrowsError(try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id))
    }
    func testMalformedSeedsFailClosed() throws {
        for mutation in 0..<6 {
            var object = YuGiOhFixture.object()
            var rows = object["printings"] as! [[String: Any]]
            switch mutation {
            case 0: rows.append(rows[0])
            case 1: rows[0]["e"] = []
            case 2: rows[0]["e"] = ["future-edition"]
            case 3: object["schemaVersion"] = 9
            case 4: rows[0]["k"] = 999
            default: rows[0]["c"] = "LOB-JP001"
            }
            object["printings"] = rows
            XCTAssertThrowsError(try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object)), "mutation \(mutation)")
        }
    }
    func testCodesKeepRegionAndAlphanumericSuffix() {
        for code in ["LOB-001", "LOB-E001", "LOB-EN001", "L26D-ENM26"] { XCTAssertTrue(YuGiOhCatalog.validCode(code)) }
        for code in ["LOB-JP001", "LOB-ABC", "x-1", "LOB-EN001X"] { XCTAssertFalse(YuGiOhCatalog.validCode(code)) }
    }
    func testAppDefaultsRegistersAllCapabilities() {
        let registry = CardGameRuntimeContainer.appDefaults().registry
        for capability: CardGameCapabilities in [.scan, .browse, .pricing, .collectionWrite] {
            XCTAssertTrue(registry.supports(.yuGiOh, capability))
        }
    }
}

private struct SupplementalFixtureAdapter: GameRecognitionAdapter {
    let game: CardGame
    var customWords: [String] { [] }
    let supplementalRegion: SupplementalTextRegion?
    var asks = true
    var returnIdentity = false
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool { asks }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        guard returnIdentity || lines.contains(where: { $0.text == "private band" }) else { return .nothing }
        let identifier = try! ScanIdentifier(game: game, namespace: "fixture", fields: [.init(key: "id", value: "1")], displayIdentifier: "1", suppressionIdentity: "1")
        return .identified(.init(identifier: identifier))
    }
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome {
        identify(footerLines + supplementalLines)
    }
}

final class GameRecognitionRegistrySupplementalTests: XCTestCase {
    func testSupplementalTextReachesOnlyOwningAdapter() throws {
        let region = SupplementalTextRegion(id: "fixture", cardRelativeRect: CGRect(x: 0, y: 0, width: 1, height: 0.1))
        let registry = try GameRecognitionRegistry(recognizers: [
            SupplementalFixtureAdapter(game: .yuGiOh, supplementalRegion: region),
            SupplementalFixtureAdapter(game: .magic, supplementalRegion: nil)])
        guard case let .identified(subject) = registry.identify(footerLines: [], supplementalLines: ["fixture": [.init(text: "private band")]]) else { return XCTFail("Leaking the band would make this ambiguous") }
        XCTAssertEqual(subject.game, .yuGiOh)
    }
    func testRegionsDeduplicateAndProfileSkipsAlreadyIdentifiedFrames() throws {
        let region = SupplementalTextRegion(id: "fixture", cardRelativeRect: CGRect(x: 0, y: 0, width: 1, height: 0.1))
        let adapters: [any GameRecognitionAdapter] = [SupplementalFixtureAdapter(game: .yuGiOh, supplementalRegion: region), SupplementalFixtureAdapter(game: .magic, supplementalRegion: region)]
        let registry = try GameRecognitionRegistry(recognizers: adapters)
        XCTAssertEqual(registry.supplementalRegions(afterFooterLines: []).count, 1)
        let profile = RecognitionProfile(additionalRecognizers: adapters)
        XCTAssertTrue(profile.supplementalRegions(afterFooterLines: [], outcome: .ambiguous).isEmpty)
        let notRequested = try GameRecognitionRegistry(recognizers: [SupplementalFixtureAdapter(game: .yuGiOh, supplementalRegion: region, asks: false)])
        XCTAssertTrue(notRequested.supplementalRegions(afterFooterLines: []).isEmpty)
    }
    func testCrossGameIdentitiesStayAmbiguous() throws {
        let registry = try GameRecognitionRegistry(recognizers: [SupplementalFixtureAdapter(game: .yuGiOh, supplementalRegion: nil, returnIdentity: true), SupplementalFixtureAdapter(game: .magic, supplementalRegion: nil, returnIdentity: true)])
        XCTAssertEqual(registry.identify(footerLines: [], supplementalLines: [:]), .ambiguous)
    }
}

final class YuGiOhRecognitionTests: XCTestCase {
    func testTwoKnownCodesRemainAmbiguous() throws {
        var object = YuGiOhFixture.object(count: 2, auto: false)
        var rows = object["printings"] as! [[String: Any]]
        rows[1]["c"] = "LOB-001"; object["printings"] = rows
        let catalog = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(YuGiOhRecognitionAdapter(catalog: catalog).identify([.init(text: "RA02-EN037"), .init(text: "LOB-001")]), .ambiguous)
    }
    func testCodePositionRepairAndMembership() throws {
        let adapter = YuGiOhRecognitionAdapter(catalog: try YuGiOhFixture.catalog())
        let right = CGRect(x: 0.6, y: 0.3, width: 0.3, height: 0.1), left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.1)
        guard case .identified = adapter.identify(footerLines: [], supplementalLines: [.init(text: "RAO2-EN037", boundingBox: right)]) else { return XCTFail() }
        XCTAssertEqual(adapter.identify(footerLines: [], supplementalLines: [.init(text: "RA02-EN037", boundingBox: left)]), .nothing)
        guard case .identified = adapter.identify([.init(text: "RA02-EN037", boundingBox: left)]) else { return XCTFail() }
        XCTAssertEqual(adapter.identify([.init(text: "ZZ99-EN999")]), .nothing)
        XCTAssertEqual(adapter.identify([.init(text: "OP01-001")]), .nothing)
        XCTAssertEqual(adapter.identify([.init(text: "123/198")]), .nothing)
        XCTAssertEqual(adapter.identify([.init(text: "0123 R MKM • EN")]), .nothing)
    }
    func testPasscodesRejectOnlyContradictions() throws {
        let adapter = YuGiOhRecognitionAdapter(catalog: try YuGiOhFixture.catalog())
        for passcode in ["", "66011101"] {
            guard case .identified = adapter.identify([.init(text: "RA02-EN037"), .init(text: passcode)]) else { return XCTFail() }
        }
        guard case let .rejected(rejection) = adapter.identify([.init(text: "RA02-EN037"), .init(text: "12345678")]) else { return XCTFail() }
        XCTAssertTrue(rejection.blocksFallbackRecognition)
    }
    func testAmbiguousLimitedFragmentsNeverBecomeFirst() {
        for token in ["EDITION", "LIM EDITION", "MIT EDITION", "ITE EDITION", "T EDITION", "S EDITION", "I EDITION", "TED EDITION"] {
            XCTAssertEqual(YuGiOhRecognitionAdapter.edition(token), .unreadable, token)
        }
        for token in ["1st Edition", "1t Edition", "1\" Edition"] {
            XCTAssertEqual(YuGiOhRecognitionAdapter.edition(token), .observed(.yugiohFirstEdition))
        }
        XCTAssertEqual(YuGiOhRecognitionAdapter.edition("Limited Edition"), .observed(.yugiohLimited))
        XCTAssertEqual(YuGiOhRecognitionAdapter.edition("no stamp"), .absent)
    }
    func testSameFrameConflictSurvivesLaterFirstFrame() throws {
        let catalog = try YuGiOhFixture.catalog(), adapter = YuGiOhRecognitionAdapter(catalog: catalog)
        guard case let .identified(subject) = adapter.identify([.init(text: "RA02-EN037"), .init(text: "1st Edition"), .init(text: "Limited Edition")]) else { return XCTFail() }
        XCTAssertTrue(subject.printedEdition.isConflict)
        var window = CandidateConfirmationWindow()
        XCTAssertNil(window.observeSubject(subject))
        let confirmed = window.observeSubject(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))
        XCTAssertTrue(confirmed?.printedEdition.isConflict == true)
        XCTAssertEqual(confirmed?.suppressionKey, subject.suppressionKey)
    }
    func testTriggerAndMalformedBounds() throws {
        let adapter = YuGiOhRecognitionAdapter(catalog: try YuGiOhFixture.catalog())
        for token in ["KONAMI", "66011101", "EDITION"] { XCTAssertTrue(adapter.needsSupplementalText(afterFooterLines: [.init(text: token)])) }
        for token in ["123/198", "0123 R MKM • EN", ""] { XCTAssertFalse(adapter.needsSupplementalText(afterFooterLines: [.init(text: token)])) }
        XCTAssertEqual(adapter.identify([.init(text: "RA02-EN037", boundingBox: CGRect(x: -1, y: 0, width: 1, height: 1))]), .nothing)
        XCTAssertEqual(adapter.customWords, [])
    }
}

final class YuGiOhResolutionTests: XCTestCase {
    func testIncompleteIdentityAndForgedPrintingCannotAuthorizeAcquisition() async throws {
        var object = YuGiOhFixture.object(auto: false)
        object["incompleteCodes"] = ["RA02-EN037"]
        let catalog = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        let adapter = YuGiOhCatalogAdapter(catalog: catalog), identifier = try YuGiOhFixture.identifier(catalog)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        guard case .catalogIncomplete = try await adapter.lookup(identifier) else { return XCTFail() }
        for automatic in [false, true] {
            do { try await adapter.validateAcquisition(identifier, printingID: p.idString, automatic: automatic); XCTFail() }
            catch CatalogLookupError.invalidPrintingChoice {}
        }
        let forged = PhysicalPrintingCandidate(id: p.idString, game: .yuGiOh, canonicalCardID: p.card.id.uuidString.lowercased(),
            language: "en", catalogGeneration: catalog.generation, name: "forged", printedIdentifier: p.code)
        do { _ = try await adapter.resolve(forged, for: identifier); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
    }
    func testLookupAutomaticManualIncompleteAndIndistinguishable() async throws {
        for (count, auto, complete, identical) in [(1, true, true, false), (1, false, true, false), (7, false, true, false), (1, false, false, false), (2, false, true, true)] {
            let catalog = try YuGiOhFixture.catalog(count: count, complete: complete, auto: auto, identical: identical)
            let adapter = YuGiOhCatalogAdapter(catalog: catalog)
            let outcome = try await adapter.lookup(YuGiOhFixture.identifier(catalog))
            if !complete || identical { guard case .catalogIncomplete = outcome else { return XCTFail() } }
            else if auto { guard case .resolved = outcome else { return XCTFail() } }
            else { guard case let .needsPrintingChoice(_, candidates) = outcome else { return XCTFail() }; XCTAssertEqual(candidates.count, count); XCTAssertTrue(candidates.allSatisfy { $0.artworkID == nil }) }
        }
    }
    func testConflictNeverResolvesAgainstAnySingletonOrLock() {
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        for edition in YuGiOhEdition.allCases {
            XCTAssertEqual(VariantResolver.gate(YuGiOhFixture.evidence([edition.variant]), printedEdition: conflict), .needsChoice(options: [], lockDidNotApply: nil))
        }
    }
    func testCoverageUnknownRejectsSingletonAndLock() {
        let evidence = YuGiOhFixture.evidence([.yugiohFirstEdition], complete: false)
        XCTAssertEqual(VariantResolver.gate(evidence, printedEdition: .absent), .needsChoice(options: [], lockDidNotApply: nil))
        XCTAssertEqual(VariantResolver.resolve(evidence, finishLock: PhysicalVariant.yugiohFirstEdition), .needsChoice(options: [], lockDidNotApply: nil))
    }
    func testPositiveMarkerBeatsLockAndContradictionRequiresAttention() {
        let evidence = YuGiOhFixture.evidence([.yugiohFirstEdition, .yugiohUnlimited])
        XCTAssertEqual(VariantResolver.gate(evidence, printedEdition: .observed(.yugiohFirstEdition)), .resolved(.init(variant: .yugiohFirstEdition, resolution: .printedLabel)))
        XCTAssertEqual(VariantResolver.gate(evidence, printedEdition: .observed(.yugiohLimited)), .needsChoice(options: [], lockDidNotApply: nil))
        guard case .needsChoice = VariantResolver.gate(evidence, printedEdition: .unreadable) else { return XCTFail() }
        XCTAssertNil(VariantResolver.gate(evidence, printedEdition: .absent))
    }
    func testExistingGamesKeepAbsentEvidenceBehavior() {
        for game in [CardGame.pokemon, .magic, .lorcana, .onePiece] {
            XCTAssertNil(VariantResolver.gate(.init(game: game, setID: "fixture", cardNumber: "1", catalogVariants: [.normal]), printedEdition: .absent))
        }
    }
    func testGenerationAndExactMutationValidation() async throws {
        let catalog = try YuGiOhFixture.catalog(), adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let p = try XCTUnwrap(catalog.printingByID.values.first), card = try adapter.resolution(forPrintingID: p.id).card
        let stale = try YuGiOhRecognitionAdapter.identifier(code: p.code, generation: "old")
        XCTAssertThrowsError(try adapter.prepareLookupIdentifier(stale))
        try await adapter.validateAcquisition(YuGiOhFixture.identifier(catalog), printingID: p.idString, automatic: true)
        try adapter.validateCollectionMutation(printingID: p.idString, catalogProviderID: p.idString, variantID: "yugioh1stEdition", itemKindRaw: "rawCard", collectionKey: card.collectionKey(variant: .yugiohFirstEdition))
        XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: p.idString, variantID: "yugiohLimited"))
        XCTAssertThrowsError(try adapter.validateCollectionMutation(printingID: p.idString, catalogProviderID: nil, variantID: "yugioh1stEdition", itemKindRaw: "rawCard", collectionKey: "wrong"))
    }
}

final class YuGiOhRecoveryTests: XCTestCase {
    func testMergeAlgebraAndTaggedRoundTrip() throws {
        let a = PrintedEditionEvidence.observed(.yugiohFirstEdition), b = PrintedEditionEvidence.observed(.yugiohLimited)
        let conflict = PrintedEditionEvidence.merged([a, b])
        for values in [[a, b, .unreadable], [b, a, .absent], [conflict, a]] {
            XCTAssertTrue(PrintedEditionEvidence.merged(values).isConflict)
            XCTAssertEqual(PrintedEditionEvidence.merged([.merged(values), a]), .merged(values + [a]))
        }
        XCTAssertEqual(PrintedEditionEvidence.merged([.unreadable, a]).observed, [PhysicalVariant.yugiohFirstEdition])
        for value in [PrintedEditionEvidence.absent, .unreadable, a, conflict] {
            XCTAssertEqual(try JSONDecoder().decode(PrintedEditionEvidence.self, from: JSONEncoder().encode(value)), value)
        }
        let unknown = Data(#"{"kind":"evidence","variants":["future-edition"]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PrintedEditionEvidence.self, from: unknown), .unreadable)
    }
    func testConflictSurvivesWindowAgingAndExplicitNewEncounterClearsIt() throws {
        let catalog = try YuGiOhFixture.catalog()
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        var window = CandidateConfirmationWindow()
        _ = window.observeSubject(try YuGiOhFixture.subject(catalog, conflict))
        window.reset(preservingPrintedEdition: true)
        for _ in 0..<5 { _ = window.observeSubject(nil) }
        _ = window.observeSubject(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))
        XCTAssertTrue(window.observeSubject(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))?.printedEdition.isConflict == true)
        window.reset()
        _ = window.observeSubject(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))
        XCTAssertFalse(window.observeSubject(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))?.printedEdition.isConflict ?? true)
    }
    func testRecoveryAndRetryRetainConflictAndLegacyDefault() async throws {
        let catalog = try YuGiOhFixture.catalog(), adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        let subject = try YuGiOhFixture.subject(catalog, conflict)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("recovery.json")
        let stored = await UnresolvedScanStore(fileURL: url).save([.init(subject: subject, reason: .noConfirmedMatch)])
        XCTAssertTrue(stored)
        let adapters = try GameCatalogAdapterRegistry(adapters: [adapter])
        let loaded = await UnresolvedScanStore(fileURL: url).load(gameCatalogAdapters: adapters)
        let row = try XCTUnwrap(loaded.first)
        XCTAssertEqual(row.subject.printedEdition, conflict)
        let retry = ScanSubject(identifier: try adapter.identifierForRetry(row.identifier), printedEdition: row.subject.printedEdition)
        XCTAssertTrue(retry.printedEdition.isConflict)
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        object[0].removeValue(forKey: "printedEdition")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let legacy = await UnresolvedScanStore(fileURL: url).load(gameCatalogAdapters: adapters)
        XCTAssertEqual(legacy.first?.subject.printedEdition, .absent)
    }

    func testUnresolvedMergeOrderAndGroupingRetainPositiveConflict() throws {
        let catalog = try YuGiOhFixture.catalog()
        let first = UnresolvedScan(subject: try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)), reason: .lookupFailed)
        let limited = UnresolvedScan(subject: try YuGiOhFixture.subject(catalog, .observed(.yugiohLimited)), reason: .lookupFailed)
        let illegible = UnresolvedScan(subject: try YuGiOhFixture.subject(catalog, .unreadable), reason: .lookupFailed)
        XCTAssertTrue(first.absorbing(limited).absorbing(first).subject.printedEdition.isConflict)
        XCTAssertEqual(first.absorbing(limited).absorbing(illegible).subject.printedEdition,
            first.absorbing(limited.absorbing(illegible)).subject.printedEdition)
        XCTAssertEqual(limited.absorbing(first).subject.printedEdition, first.absorbing(limited).subject.printedEdition)
    }

    @MainActor
    func testVisionFailureRetainsConflictWhileClearingConfirmationCounts() throws {
        let catalog = try YuGiOhFixture.catalog(), scanner = CardScanner()
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        _ = scanner.observeConfirmationSubjectForTesting(try YuGiOhFixture.subject(catalog, conflict))
        scanner.receiveVisionFrameResultForTesting(error: NSError(domain: "YGO-test", code: 1))
        XCTAssertNil(scanner.observeConfirmationSubjectForTesting(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition))))
        XCTAssertTrue(scanner.observeConfirmationSubjectForTesting(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))?.printedEdition.isConflict == true)
    }

    @MainActor
    func testPhysicalExitClearsUnconfirmedEvidenceForNextCard() throws {
        let catalog = try YuGiOhFixture.catalog(), scanner = CardScanner()
        let conflict = PrintedEditionEvidence.merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])
        _ = scanner.observeConfirmationSubjectForTesting(try YuGiOhFixture.subject(catalog, conflict))
        scanner.receiveFooterOutcomeForTesting(.nothing, footerHasText: false, at: 100)
        scanner.receiveFooterOutcomeForTesting(.nothing, footerHasText: false, at: 103)
        _ = scanner.observeConfirmationSubjectForTesting(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))
        XCTAssertEqual(scanner.observeConfirmationSubjectForTesting(try YuGiOhFixture.subject(catalog, .observed(.yugiohFirstEdition)))?.printedEdition, .observed(.yugiohFirstEdition))
    }
}
