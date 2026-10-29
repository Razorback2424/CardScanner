import Foundation
import CryptoKit
import SwiftData
import XCTest
@testable import TradingCardScanner

private final class YuGiOhDeliveryGateProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (YuGiOhDeliveryGateProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}
    func respond(_ bytes: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
}
private actor YuGiOhDeliveryGate {
    var request: YuGiOhDeliveryGateProtocol?
    var calls = 0
    func enter(_ request: YuGiOhDeliveryGateProtocol) { self.request = request; calls += 1 }
    func respond(_ bytes: Data) { request?.respond(bytes) }
}

final class YuGiOhCandidateDeliveryTests: XCTestCase {
    func testBuilderPublisherFixtureDecodesAndVerifiesInRealAppLoader() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "approved-wire", withExtension: "json", subdirectory: "YuGiOhDelivery"))
        let bytes = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(YuGiOhCandidateEnvelope.self, from: bytes)
        let publicBytes = try XCTUnwrap(Data(base64Encoded: "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="))
        let (manifest, snapshot) = try YuGiOhCandidateVerifier.verify(envelope,
            keys: ["yugioh-fixture": Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)], now: .now, state: .approved)
        XCTAssertEqual(manifest.revision, 1)
        XCTAssertEqual(snapshot.catalog.generation, "yugioh-en-rehearsal-1")
        XCTAssertFalse(snapshot.catalog.printingByID.isEmpty)
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(envelope,
            keys: ["yugioh-fixture": Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)], now: .now), "Approved and candidate channels are distinct")
    }

    func testNetworkRefreshCoalescesAndCancellationCannotActivateSuspendedDownload() async throws {
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bundle = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        object["generation"] = "yugioh-en-coalesced"
        let approved = try envelope(object, revision: 1, key: key, state: .approved, parent: YuGiOhReleaseWire.hash(bundle))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-coalesced-\(UUID())")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [YuGiOhDeliveryGateProtocol.self]
        let endpoint = URL(string: "https://example.com/yugioh/v1/current.json")!
        let coordinator = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bundle, endpoint: endpoint, configuration: config)
        let gate = YuGiOhDeliveryGate(), started = expectation(description: "download suspended")
        let joined = expectation(description: "second caller joined same download")
        YuGiOhDeliveryGateProtocol.handler = { request in Task { await gate.enter(request); started.fulfill() } }
        defer { YuGiOhDeliveryGateProtocol.handler = nil }
        await coordinator.setCoalescingObserverForTesting { joined.fulfill() }
        let first = Task { await coordinator.refresh() }
        await fulfillment(of: [started], timeout: 5)
        let second = Task { await coordinator.refresh() }
        await fulfillment(of: [joined], timeout: 5)
        await gate.respond(try JSONEncoder().encode(approved))
        guard case .activated(1) = await first.value, case .activated(1) = await second.value else { return XCTFail() }
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        let cancelled = try YuGiOhCatalogCoordinator(root: root.appendingPathComponent("cancelled"), keys: keys,
            bundledBytes: bundle, endpoint: endpoint, configuration: config)
        let cancelGate = YuGiOhDeliveryGate(), cancelStarted = expectation(description: "cancel at deterministic network barrier")
        YuGiOhDeliveryGateProtocol.handler = { request in Task { await cancelGate.enter(request); cancelStarted.fulfill() } }
        let pending = Task { await cancelled.refresh() }
        await fulfillment(of: [cancelStarted], timeout: 5)
        pending.cancel()
        guard case .rejected = await pending.value else { return XCTFail() }
        let retained = await cancelled.catalog()
        XCTAssertNil(retained.publicationRevision)
        XCTAssertEqual(retained.generation, "yugioh-en-fixture")
    }

    func testProductionBootstrapRejectsFixtureKeysAndUnapprovedOrigins() throws {
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(try YuGiOhCatalogBootstrap.productionKeys("yugioh-production-review:\(key)").count, 1)
        for text in ["", "yugioh-fixture:\(key)", "yugioh-production-review:invalid",
                     "yugioh-production-a:\(key),yugioh-production-b:\(key)",
                     "yugioh-production-test:11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="] {
            XCTAssertThrowsError(try YuGiOhCatalogBootstrap.productionKeys(text))
        }
        XCTAssertThrowsError(try YuGiOhCatalogBootstrap.productionKeys(nil))
        for url in ["http://scanstash-catalog-prod.web.app", "https://example.com", "https://catalog.scan-stash.com/candidate",
                    "https://user@catalog.scan-stash.com", "https://catalog.scan-stash.com?candidate=1"] {
            XCTAssertThrowsError(try YuGiOhCatalogBootstrap.productionEndpoint(url))
        }
        XCTAssertEqual(try YuGiOhCatalogBootstrap.productionEndpoint("https://scanstash-catalog-prod.web.app").path, "/yugioh/v1/current.json")
    }

    func testApprovedNetworkRejectsSignedCandidateThenRecoversAndReopensOffline() async throws {
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        object["generation"] = "yugioh-en-network-approved"
        let candidate = try envelope(object, revision: 1, key: key)
        let approved = try envelope(object, revision: 1, key: key, state: .approved, parent: YuGiOhReleaseWire.hash(bytes))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-network-\(UUID())")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [YuGiOhPricingProtocol.self]
        var response = try JSONEncoder().encode(candidate), calls = 0
        YuGiOhPricingProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/yugioh/v1/current.json")
            calls += 1
            return response
        }
        defer { YuGiOhPricingProtocol.handler = nil }
        let coordinator = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bytes,
            endpoint: URL(string: "https://example.com/yugioh/v1/current.json")!, configuration: configuration)
        guard case .rejected = await coordinator.refresh() else { return XCTFail("Signed candidate is not network approval") }
        let fallback = await coordinator.catalog()
        XCTAssertEqual(fallback.generation, "yugioh-en-fixture")
        response = try JSONEncoder().encode(approved)
        guard case .activated(1) = await coordinator.refresh() else { return XCTFail() }
        XCTAssertEqual(calls, 2)
        let reopened = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bytes)
        let offline = await reopened.catalog()
        XCTAssertEqual(offline.generation, "yugioh-en-network-approved")
        guard case .disabled = await reopened.refresh() else { return XCTFail("No configured endpoint must remain offline") }
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testApprovedCoordinatorAdoptsCatalogAndPriceAuthorityOnlyAfterSuccessfulContainerSave() async throws {
        let key = Curve25519.Signing.PrivateKey()
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let bundled = try YuGiOhCatalog(data: bytes)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-coordinator-\(UUID())")
        let coordinator = try YuGiOhCatalogCoordinator(root: root, keys: ["yugioh-fixture": key.publicKey], bundledBytes: bytes)
        let schema = Schema([CollectedCard.self, CollectionActivity.self, InventoryEvent.self, PriceRecord.self, ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let bound = try await CardGameRuntimeContainer(runtimes: [YuGiOhGameRuntime(catalog: bundled, coordinator: coordinator).runtime]).bound(to: container)
        let source = try XCTUnwrap(bound.runtime(for: .yuGiOh)?.activationSource as? CollectionAuthorizedActivationSource)
        let printing = try XCTUnwrap(bundled.printingByID.values.first)
        let card = try YuGiOhCatalogAdapter(catalog: bundled).resolution(forPrintingID: printing.id).card
        let store = CollectionStore(context: container.mainContext)
        _ = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed))
        let prices = PriceStore(context: container.mainContext)
        let priceKey = PriceRecord.key(game: .yuGiOh, printingID: printing.idString, variantID: YuGiOhEdition.first.rawValue)
        XCTAssertTrue(prices.store(.price(.init(unitMarketPriceUSD: 7, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "fixture", sourceUpdatedAt: bundled.capturedAt, fetchedAt: bundled.capturedAt,
            catalogIdentity: YuGiOhPriceAdapter.mappingIdentity(printing, .first))), game: .yuGiOh,
            printingID: printing.idString, variantID: YuGiOhEdition.first.rawValue))
        XCTAssertTrue(prices.save())
        var next = object
        next["generation"] = "yugioh-en-coordinator-next"
        var rows = next["printings"] as! [[String: Any]]
        rows[0]["e"] = ["yugiohUnlimited"]
        rows[0]["m"] = (rows[0]["m"] as! [[String: Any]]).filter { $0["e"] as? String == "yugiohUnlimited" }
        next["printings"] = rows
        let approved = try envelope(next, revision: 1, key: key, state: .approved, parent: YuGiOhReleaseWire.hash(bytes))
        _ = try await coordinator.activate(approved)
        source.setBeforeSaveForTesting { _ in throw CocoaError(.fileWriteUnknown) }
        let rejected = await source.currentSnapshot()
        XCTAssertNil(rejected)
        XCTAssertFalse(try XCTUnwrap(prices.record(forKey: priceKey)).isInvalidated)
        XCTAssertNoThrow(try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed)), "Failed authority adoption retains the previous catalog")
        source.setBeforeSaveForTesting(nil)
        let snapshot = await source.currentSnapshot()
        let accepted = try XCTUnwrap(snapshot)
        XCTAssertEqual(accepted.revision, 1)
        XCTAssertNil(accepted.priceAuthority?.identityByPriceKey[priceKey])
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed)))
        let durable = ModelContext(container)
        XCTAssertTrue(try XCTUnwrap(durable.fetch(FetchDescriptor<PriceRecord>()).first).isInvalidated)
        let oldIdentifier = try YuGiOhFixture.identifier(bundled)
        do { try await accepted.catalog.validateLookupContext(oldIdentifier); XCTFail("Stale picker must be rejected") }
        catch CatalogLookupError.staleCatalog {}
        let imported = await bound.currentImportAdapters()
        XCTAssertNotNil(imported.adapter(for: .yuGiOh))
        let active = await coordinator.catalog()
        XCTAssertTrue(active.historicalPricingNotice.contains("verified periodic snapshot"))
        XCTAssertEqual(active.capturedAt, bundled.capturedAt)
        XCTAssertEqual(try durable.fetch(FetchDescriptor<CollectedCard>()).reduce(0) { $0 + $1.quantity }, 2)
        XCTAssertTrue(bound.registry.supports(.yuGiOh, .collectionWrite))
        var retired = next
        retired["generation"] = "yugioh-en-coordinator-browse-only"
        rows[0]["e"] = [] as [String]
        rows[0]["m"] = [] as [[String: Any]]
        retired["printings"] = rows
        let second = try envelope(retired, revision: 2, key: key, state: .approved, parent: YuGiOhReleaseWire.hash(approved.catalog))
        _ = try await coordinator.activate(second)
        _ = await source.currentSnapshot()
        XCTAssertFalse(bound.registry.supports(.yuGiOh, .collectionWrite))
        XCTAssertFalse(bound.registry.supports(.yuGiOh, .scan))
        XCTAssertTrue(bound.registry.supports(.yuGiOh, .browse))
        XCTAssertEqual(try store.setQuantity(1, forCollectionKey: card.collectionKey(variant: .yugiohFirstEdition), expectedCurrent: 2), 1,
            "Previously authorized holdings remain maintainable when every edition is retired")
    }

    func testRealBundledCandidatePassesSignedHashAdmissionAndProvenanceChecks() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String:Any])
        let key = Curve25519.Signing.PrivateKey()
        let candidate = try envelope(object, revision: 1, key: key)
        let (manifest, snapshot) = try YuGiOhCandidateVerifier.verify(candidate, keys: ["yugioh-fixture":key.publicKey], now: .now)
        XCTAssertEqual(snapshot.catalog.printingByID.count, 46_542)
        XCTAssertEqual(snapshot.catalog.printingByID.values.filter(\.explicitSelectionSupported).count, 46_303)
        XCTAssertEqual(manifest.generation, snapshot.catalog.generation)
    }

    private func envelope(_ object: [String: Any], revision: Int, key: Curve25519.Signing.PrivateKey,
                          state: YuGiOhPublicationState = .candidate, parent: String? = nil,
                          parentRevision: Int? = nil) throws -> YuGiOhCandidateEnvelope {
        var object = object
        object["policyVersion"] = YuGiOhCandidateVerifier.policy
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let generation = object["generation"] as! String
        var manifest = YuGiOhCandidateManifest(schemaVersion: state == .approved ? 2 : 1, revision: revision, generation: generation,
            policyVersion: YuGiOhCandidateVerifier.policy, path: "yugioh/v1/releases/\(state == .approved ? String(revision) : generation)/catalog.json",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), bytes: bytes.count,
            status: state.rawValue, capturedAt: object["capturedAt"] as! String)
        manifest.parentSHA256 = parent
        manifest.parentRevision = parentRevision
        manifest.reviewID = state == .approved ? "fixture-review-\(revision)" : nil
        let payload = try JSONEncoder().encode(manifest)
        return .init(keyID: "yugioh-fixture", payload: YuGiOhCandidateVerifier.encodeURL(payload),
            signature: YuGiOhCandidateVerifier.encodeURL(try key.signature(for: payload)), catalog: bytes)
    }

    func testNetworkCatchUpFreshSkippedMissingMalformedAndReopen() async throws {
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bundle = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var releases: [YuGiOhCandidateEnvelope] = []
        var parent = YuGiOhReleaseWire.hash(bundle)
        for revision in 1...3 {
            object["generation"] = "yugioh-en-catchup-\(revision)"
            let release = try envelope(object, revision: revision, key: key, state: .approved,
                parent: parent, parentRevision: revision > 1 ? revision - 1 : nil)
            releases.append(release); parent = YuGiOhReleaseWire.hash(release.catalog)
        }
        let encoded = try releases.map { try JSONEncoder().encode($0) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [YuGiOhPricingProtocol.self]
        let endpoint = URL(string: "https://example.com/yugioh/v1/current.json")!
        var paths: [String] = []
        var failure: String? = nil
        YuGiOhPricingProtocol.handler = { request in
            let path = request.url!.path; paths.append(path)
            if path.contains("/releases/1/") {
                if failure == "missing" { throw URLError(.fileDoesNotExist) }
                if failure == "malformed" { return Data("{}".utf8) }
                if failure == "wrong-parent" { return encoded[1] }
                return encoded[0]
            }
            if path.contains("/releases/2/") { return encoded[1] }
            return encoded[2]
        }
        defer { YuGiOhPricingProtocol.handler = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-catchup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for mode in ["missing", "malformed", "wrong-parent"] {
            failure = mode
            let coordinator = try YuGiOhCatalogCoordinator(root: root.appendingPathComponent(mode), keys: keys,
                bundledBytes: bundle, endpoint: endpoint, configuration: config)
            guard case .rejected = await coordinator.refresh() else { return XCTFail(mode) }
            let retained = await coordinator.catalog()
            XCTAssertNil(retained.publicationRevision)
        }
        failure = nil; paths = []
        let fresh = try YuGiOhCatalogCoordinator(root: root.appendingPathComponent("fresh"), keys: keys,
            bundledBytes: bundle, endpoint: endpoint, configuration: config)
        guard case .activated(3) = await fresh.refresh() else { return XCTFail("Fresh bundle must catch up") }
        XCTAssertEqual(paths, [endpoint.path, "/yugioh/v1/releases/2/catalog-release.json", "/yugioh/v1/releases/1/catalog-release.json"])
        let skippedRoot = root.appendingPathComponent("skipped")
        let skipped = try YuGiOhCatalogCoordinator(root: skippedRoot, keys: keys, bundledBytes: bundle,
            endpoint: endpoint, configuration: config)
        _ = try await skipped.activate(releases[0])
        paths = []
        guard case .activated(3) = await skipped.refresh() else { return XCTFail("R1 must catch up past R2") }
        XCTAssertEqual(paths.count, 2)
        let reopened = try YuGiOhCatalogCoordinator(root: skippedRoot, keys: keys, bundledBytes: bundle)
        let recovered = await reopened.catalog()
        XCTAssertEqual(recovered.publicationRevision, 3)
    }

    func testSignedMalformedMembershipRejectedByActualLoader() throws {
        let key = Curve25519.Signing.PrivateKey()
        for attack in ["type", "negative", "listing", "duplicate", "product", "card", "automatic"] {
            var object = YuGiOhFixture.providerSupportedObject()
            var rows = object["printings"] as! [[String: Any]]
            var members = rows[0]["m"] as! [[String: Any]]
            switch attack {
            case "type": members[0]["t"] = "unknownSource"
            case "negative": members[0]["q"] = -1
            case "listing": members[0]["t"] = "providerListing"; members[0]["q"] = 10
            case "duplicate": members.append(members[0])
            case "product": rows[0]["p"] = 0
            case "card": rows[0]["k"] = -1
            default: object["autoEligibleCodes"] = ["MISSING-EN001"]
            }
            rows[0]["m"] = members; object["printings"] = rows
            let release = try envelope(object, revision: 1, key: key, state: .approved,
                parent: String(repeating: "a", count: 64))
            XCTAssertThrowsError(try YuGiOhCatalog(data: release.catalog), attack)
            XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(release, keys: ["yugioh-fixture": key.publicKey],
                now: .now, state: .approved), attack)
        }
    }

    func testCancelledAncestorDownloadReopensAndRetriesFromDurableParent() async throws {
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bundle = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var releases: [YuGiOhCandidateEnvelope] = []
        var parent = YuGiOhReleaseWire.hash(bundle)
        for revision in 1...3 {
            object["generation"] = "yugioh-en-interrupted-\(revision)"
            let release = try envelope(object, revision: revision, key: key, state: .approved,
                parent: parent, parentRevision: revision > 1 ? revision - 1 : nil)
            releases.append(release); parent = YuGiOhReleaseWire.hash(release.catalog)
        }
        let head = try JSONEncoder().encode(releases[2]), ancestor = try JSONEncoder().encode(releases[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-interrupted-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [YuGiOhDeliveryGateProtocol.self]
        let endpoint = URL(string: "https://example.com/yugioh/v1/current.json")!
        let coordinator = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bundle,
            endpoint: endpoint, configuration: config)
        _ = try await coordinator.activate(releases[0])
        let suspended = expectation(description: "missing ancestor download suspended")
        YuGiOhDeliveryGateProtocol.handler = { request in
            if request.request.url?.path == endpoint.path { request.respond(head) }
            else { suspended.fulfill() }
        }
        defer { YuGiOhDeliveryGateProtocol.handler = nil }
        let refresh = Task { await coordinator.refresh() }
        await fulfillment(of: [suspended], timeout: 5)
        refresh.cancel()
        guard case .rejected = await refresh.value else { return XCTFail() }
        YuGiOhDeliveryGateProtocol.handler = { request in
            request.respond(request.request.url?.path == endpoint.path ? head : ancestor)
        }
        let reopened = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bundle,
            endpoint: endpoint, configuration: config)
        let retained = await reopened.catalog()
        XCTAssertEqual(retained.publicationRevision, 1)
        guard case .activated(3) = await reopened.refresh() else { return XCTFail() }
    }

    func testAncestorTraversalIsBoundedAndRetainsBundleAtLimit() async throws {
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bundle = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var responses: [String: Data] = [:], parent = YuGiOhReleaseWire.hash(bundle)
        for revision in 1...33 {
            object["generation"] = "yugioh-en-bounded-\(revision)"
            let release = try envelope(object, revision: revision, key: key, state: .approved,
                parent: parent, parentRevision: revision > 1 ? revision - 1 : nil)
            responses["/yugioh/v1/releases/\(revision)/catalog-release.json"] = try JSONEncoder().encode(release)
            parent = YuGiOhReleaseWire.hash(release.catalog)
        }
        responses["/yugioh/v1/current.json"] = responses["/yugioh/v1/releases/33/catalog-release.json"]
        var calls = 0
        YuGiOhPricingProtocol.handler = { request in
            calls += 1
            return try XCTUnwrap(responses[request.url!.path])
        }
        defer { YuGiOhPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [YuGiOhPricingProtocol.self]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-bounded-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try YuGiOhCatalogCoordinator(root: root, keys: keys, bundledBytes: bundle,
            endpoint: URL(string: "https://example.com/yugioh/v1/current.json")!, configuration: config)
        guard case .rejected = await coordinator.refresh() else { return XCTFail() }
        XCTAssertEqual(calls, 32)
        let retained = await coordinator.catalog()
        XCTAssertNil(retained.publicationRevision)
    }

    func testApprovedParentContinuityAndSameSnapshotReviewedCorrections() async throws {
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        var object = YuGiOhFixture.providerSupportedObject()
        object["capturedAt"] = "2026-10-20T21:00:00Z"
        let bundleBytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let bundled = try YuGiOhCatalog(data: bundleBytes)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-approved-\(UUID())")
        let store = try YuGiOhCandidateReleaseStore(root: root, keys: keys, bundled: bundled,
            state: .approved, bundledSHA256: YuGiOhReleaseWire.hash(bundleBytes))
        let candidate = try envelope(object, revision: 1, key: key)
        do { _ = try await store.stage(candidate); XCTFail("A signed candidate is not approved") } catch {}
        var parent = YuGiOhReleaseWire.hash(bundleBytes)
        var last: YuGiOhCandidateEnvelope?
        for revision in 1...3 {
            var corrected = object
            corrected["generation"] = "yugioh-en-reviewed-\(revision)"
            let next = try envelope(corrected, revision: revision, key: key, state: .approved, parent: parent)
            let result = try await store.stage(next)
            XCTAssertEqual(result, .activated(revision: revision, previousRevision: revision == 1 ? nil : revision - 1))
            let snapshot = await store.snapshot()
            XCTAssertEqual(snapshot.catalog.capturedAt, bundled.capturedAt, "Review does not invent a provider observation")
            XCTAssertEqual(snapshot.catalog.printingByID.values.first?.editions, bundled.printingByID.values.first?.editions)
            parent = YuGiOhReleaseWire.hash(next.catalog)
            last = next
        }
        var fourth = object; fourth["generation"] = "yugioh-en-reviewed-4"
        let badParent = try envelope(fourth, revision: 4, key: key, state: .approved, parent: String(repeating: "0", count: 64))
        do { _ = try await store.stage(badParent); XCTFail("Unapproved parent must not advance head") } catch {}
        let collision = try envelope(fourth, revision: 3, key: key, state: .approved, parent: parent)
        do { _ = try await store.stage(collision); XCTFail() } catch SignedCatalogStoreError.revisionCollision {}
        let reopened = try YuGiOhCandidateReleaseStore(root: root, keys: keys, bundled: bundled,
            state: .approved, bundledSHA256: YuGiOhReleaseWire.hash(bundleBytes))
        let active = await reopened.snapshot()
        XCTAssertEqual(active.catalog.generation, "yugioh-en-reviewed-3")
        XCTAssertEqual(active.catalog.capturedAt, bundled.capturedAt)
        let current = try XCTUnwrap(last)
        for (field, value) in [("schemaVersion", 99 as Any), ("policyVersion", "unknown"), ("status", "candidate_not_deployed"),
                               ("path", "../catalog.json"), ("bytes", 1), ("sha256", String(repeating: "0", count: 64)),
                               ("reviewID", ""), ("parentSHA256", "missing")] {
            var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(YuGiOhReleaseWire.decodeURL(current.payload))) as? [String: Any])
            manifest[field] = value
            let payload = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            let forged = YuGiOhCandidateEnvelope(keyID: current.keyID, payload: YuGiOhReleaseWire.encodeURL(payload),
                signature: YuGiOhReleaseWire.encodeURL(try key.signature(for: payload)), catalog: current.catalog)
            XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(forged, keys: keys, now: .now, state: .approved), field)
        }
        let badSignature = YuGiOhCandidateEnvelope(keyID: current.keyID, payload: current.payload,
            signature: YuGiOhReleaseWire.encodeURL(Data(repeating: 0, count: 64)), catalog: current.catalog)
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(badSignature, keys: keys, now: .now, state: .approved))
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(current, keys: [:], now: .now, state: .approved))
    }

    func testSignedLocalStagingRejectsTamperingAndRollbacksAndRecoversPrevious() async throws {
        // Ephemeral fixture key; no publisher credential or production trust pin.
        let key = Curve25519.Signing.PrivateKey(), keys = ["yugioh-fixture": key.publicKey]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-delivery-\(UUID())")
        let bundle = try YuGiOhFixture.catalog()
        let store = try YuGiOhCandidateReleaseStore(root: root, keys: keys, bundled: bundle)
        var object = YuGiOhFixture.object()
        object["generation"] = "yugioh-en-delivery1"
        object["capturedAt"] = "2026-10-21T00:00:00Z"
        let first = try envelope(object, revision: 1, key: key)
        let staged = try await store.stage(first)
        XCTAssertEqual(staged, .activated(revision: 1, previousRevision: nil))
        let before = await store.snapshot()
        XCTAssertEqual(before.catalog.generation, "yugioh-en-delivery1")
        let tampered = YuGiOhCandidateEnvelope(keyID: first.keyID, payload: first.payload, signature: first.signature, catalog: Data("{}".utf8))
        do { _ = try await store.stage(tampered); XCTFail() } catch {}
        object["generation"] = "yugioh-en-delivery2"
        object["capturedAt"] = "2026-10-21T01:00:00Z"
        let second = try envelope(object, revision: 2, key: key)
        _ = try await store.stage(second)
        do { _ = try await store.stage(first); XCTFail() } catch SignedCatalogStoreError.revisionRollback {}
        let after = await store.snapshot()
        XCTAssertEqual(after.catalog.generation, "yugioh-en-delivery2")
        // The catalog and pricing authority are adopted as a single value.
        XCTAssertEqual(after.priceAuthority.identityByPriceKey.count, YuGiOhPriceAdapter.priceAuthority(after.catalog).identityByPriceKey.count)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("yugioh-candidate-current.json"))
        let reopened = try YuGiOhCandidateReleaseStore(root: root, keys: keys, bundled: bundle)
        let recovered = await reopened.snapshot()
        XCTAssertEqual(recovered.catalog.generation, "yugioh-en-delivery1")
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("yugioh-candidate-previous.json"))
        let empty = try YuGiOhCandidateReleaseStore(root: root, keys: keys, bundled: bundle)
        let fallback = await empty.snapshot()
        XCTAssertEqual(fallback.catalog.generation, bundle.generation)
    }

    func testSignedStaleIdentityDriftUnknownKeysAndFutureCandidatesFailClosed() throws {
        let key = Curve25519.Signing.PrivateKey()
        let original = try YuGiOhFixture.catalog()
        var object = YuGiOhFixture.object()
        object["capturedAt"] = "2026-10-19T00:00:00Z"
        let stale = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.validateTransition(from: original, to: stale))
        object["capturedAt"] = "2026-10-22T00:00:00Z"
        let future = try envelope(object, revision: 2, key: key)
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(future, keys: ["yugioh-fixture":key.publicKey], now: original.capturedAt))
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.verify(future, keys: [:], now: .now))
        var rows = object["printings"] as! [[String:Any]]
        rows[0]["pn"] = "Changed identity"
        object["printings"] = rows
        object["generation"] = "yugioh-en-drift"
        let changed = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try YuGiOhCandidateVerifier.validateTransition(from: original, to: changed))
    }
}

/// All fixture review references are synthetic; they prove contracts only.
enum YuGiOhFixture {
    static func object(count: Int = 1, complete: Bool = true, auto: Bool = true, identical: Bool = false,
                       editions: [String] = ["yugioh1stEdition", "yugiohUnlimited"], priced: [String] = ["yugioh1stEdition"]) -> [String: Any] {
        let rows: [[String: Any]] = (1...count).map { index in
            ["id": DeterministicUUID.make(namespace: "yugioh-printing:", material: "tcgplayer:2:\(index)").uuidString.lowercased(),
             "c": "RA02-EN037", "g": 23416, "k": 0, "r": identical ? "Rare" : "Rare \(index)", "p": index,
             "pn": identical ? "Fixture Card" : "Fixture Card \(index)", "e": editions, "ec": complete, "ee": "synthetic:physical-edition-review",
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
    static func providerSupportedObject() -> [String: Any] {
        var object = object(complete: false, auto: false)
        var rows = object["printings"] as! [[String: Any]]
        rows[0]["m"] = ["yugioh1stEdition", "yugiohUnlimited"].map {
            ["e": $0, "t": "providerListing", "h": String(repeating: "a", count: 64), "s": "2026-10-20T20:05:18+0000"]
        }
        object["printings"] = rows
        object["incompleteCodes"] = ["RA02-EN037"]
        return object
    }
    static func mp24Object() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var row = try XCTUnwrap((object["printings"] as? [[String: Any]])?.first { $0["c"] as? String == "MP24-EN372" })
        let card = (object["cards"] as! [[String: Any]])[row["k"] as! Int]
        row["k"] = 0
        object["cards"] = [card]; object["printings"] = [row]
        object["sets"] = (object["sets"] as! [[String: Any]]).filter { $0["g"] as? Int == 23481 }
        object["autoEligibleCodes"] = ["MP24-EN372"]; object["incompleteCodes"] = []
        return object
    }
    static func subject(_ catalog: YuGiOhCatalog, _ edition: PrintedEditionEvidence = .absent) throws -> ScanSubject {
        .init(identifier: try identifier(catalog), printedEdition: edition)
    }
    static func evidence(_ editions: [PhysicalVariant], complete: Bool = true) -> VariantEvidence {
        .init(game: .yuGiOh, setID: "fixture", cardNumber: "RA02-EN037", catalogVariants: editions, physicalCoverageVerified: complete)
    }
}

private actor YuGiOhNoticeSource: GameCatalogActivationSource {
    nonisolated let game = CardGame.yuGiOh
    private var catalog: YuGiOhCatalog?
    func install(_ value: YuGiOhCatalog) { catalog = value }
    func currentSnapshot() -> GameCatalogSnapshot? {
        guard let catalog else { return nil }
        return .init(revision: catalog.publicationRevision ?? 0, catalog: YuGiOhCatalogAdapter(catalog: catalog),
            recognizer: YuGiOhRecognitionAdapter(catalog: catalog), variantPolicy: YuGiOhVariantPolicy())
    }
    func activationSnapshots() -> AsyncStream<GameCatalogSnapshot> { AsyncStream { $0.finish() } }
}

private actor YuGiOhRecoveryPreflightGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct SuspendedYuGiOhRecoveryAdapter: GameCatalogAdapter {
    let base: YuGiOhCatalogAdapter
    let gate: YuGiOhRecoveryPreflightGate
    var game: CardGame { base.game }
    var generation: String { base.generation }
    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome { try await base.lookup(identifier) }
    func lookupPrintingChoices(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome? {
        await gate.hold()
        return try await base.lookup(identifier)
    }
    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        try await base.resolve(candidate, for: identifier)
    }
    func validateVariantCorrection(printingID: String, variantID: String?) throws {
        try base.validateVariantCorrection(printingID: printingID, variantID: variantID)
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
            let data = MarketMirrorFixture.stamped(try Self.handler!(request))
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class YuGiOhPricingTests: XCTestCase {
    func testDailyMirrorPricesAnUnpricedSeedEditionAndKeepsOfflineSnapshotDates() async throws {
        var object = YuGiOhFixture.object()
        var rows = object["printings"] as! [[String: Any]]
        rows[0]["m"] = [["e": "yugioh1stEdition", "t": "providerMarket", "q": 7,
                          "h": String(repeating: "a", count: 64), "s": "2026-10-20T20:05:18Z", "st": "providerSnapshot"]]
        object["printings"] = rows
        let catalog = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        let printing = try XCTUnwrap(catalog.printingByID.values.first)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); YuGiOhPricingProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [YuGiOhPricingProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let source = YuGiOhDailyPriceSource(transport: .init(baseURL: MarketMirrorFixture.baseURL,
            session: session, cacheDirectory: root))
        let adapter = YuGiOhPriceAdapter(catalog: catalog, source: source)
        var amount: Double? = 42
        YuGiOhPricingProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, MarketMirrorFixture.baseURL.host)
            if request.url?.lastPathComponent == "products" {
                return try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": [[
                    "productId": printing.productID, "categoryId": 2, "groupId": printing.set.groupID,
                    "name": printing.productName, "extendedData": [["name": "Number", "value": printing.code]]]]])
            }
            return try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": [
                ["productId": printing.productID, "subTypeName": "1st Edition", "marketPrice": 999],
                ["productId": printing.productID, "subTypeName": "Unlimited", "marketPrice": amount.map { $0 as Any } ?? NSNull()]]])
        }
        guard case let .price(fresh) = try await adapter.refreshStoredPrinting(printing.idString, variant: .yugiohUnlimited)
        else { return XCTFail("A missing seed quote must be discoverable from the daily mirror") }
        XCTAssertEqual(fresh.unitMarketPriceUSD, 42)
        XCTAssertEqual(fresh.catalogIdentity, YuGiOhPriceAdapter.mappingIdentity(printing, .unlimited))
        XCTAssertEqual(fresh.sourceVariantID, "tcgplayer:\(printing.productID):Unlimited")
        XCTAssertNil(fresh.sourceUpdatedAt)
        amount = nil
        let absent = try await adapter.refreshStoredPrinting(printing.idString, variant: .yugiohUnlimited, minimumFetchedAt: .now)
        XCTAssertEqual(absent, .unavailable(.tcgCSV), "A fresh null lane cannot borrow another edition or an older bundle")

        let offline = YuGiOhPriceAdapter(catalog: catalog, source: YuGiOhDailyPriceSource(transport:
            .init(baseURL: nil, session: session, cacheDirectory: root.appendingPathComponent("offline"))))
        let historical = try await YuGiOhBundledPriceSource().quote(printing: printing, edition: .first,
            generation: catalog.generation, minimumFetchedAt: nil)
        let offlinePrice = try await offline.refreshStoredPrinting(printing.idString, variant: .yugiohFirstEdition)
        guard case var .price(expected) = historical else { return XCTFail("Expected a dated bundle quote") }
        expected.catalogIdentity = YuGiOhPriceAdapter.mappingIdentity(printing, .first)
        XCTAssertEqual(offlinePrice, .price(expected))
        do {
            _ = try await offline.refreshStoredPrinting(printing.idString, variant: .yugiohFirstEdition, minimumFetchedAt: .now)
            XCTFail("An old bundle cannot fulfill a current-check watermark")
        } catch PriceQuoteError.providerUnavailable {}

        for mode in ["identity", "cancelled"] {
            let strict = YuGiOhPriceAdapter(catalog: catalog, source: YuGiOhDailyPriceSource(transport:
                .init(baseURL: MarketMirrorFixture.baseURL, session: session, cacheDirectory: root.appendingPathComponent(mode))))
            YuGiOhPricingProtocol.handler = { request in
                if mode == "cancelled" { throw URLError(.cancelled) }
                if request.url?.lastPathComponent == "products" {
                    return try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": [[
                        "productId": printing.productID, "categoryId": 2, "groupId": printing.set.groupID,
                        "name": "A different product", "extendedData": [["name": "Number", "value": printing.code]]]]])
                }
                return try JSONSerialization.data(withJSONObject: ["success": true, "errors": [], "results": [[
                    "productId": printing.productID, "subTypeName": "1st Edition", "marketPrice": 99]]])
            }
            do {
                _ = try await strict.refreshStoredPrinting(printing.idString, variant: .yugiohFirstEdition)
                XCTFail("Identity rejection and cancellation cannot return the old bundle")
            } catch PriceQuoteError.identityMismatch { XCTAssertEqual(mode, "identity") }
            catch is CancellationError { XCTAssertEqual(mode, "cancelled") }
        }
    }

    @MainActor
    func testPricingNoticeDescribesActiveSourceAndNeverFallsBackFromUnavailableAuthority() async throws {
        let bundled = try YuGiOhFixture.catalog()
        var object = YuGiOhFixture.object()
        object["generation"] = "yugioh-en-approved-wording"
        object["capturedAt"] = "2026-10-21T00:00:00Z"
        var approved = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        approved.publicationRevision = 1
        let base = bundled.runtime
        let source = YuGiOhNoticeSource()
        let runtime = CardGameRuntime(descriptor: base.descriptor, variantPolicy: base.variantPolicy,
            catalog: base.catalog, activationSource: source)
        let runtimes = try CardGameRuntimeContainer(runtimes: [runtime])
        let unavailable = await YuGiOhCatalog.activePricingNotice(in: runtimes)
        XCTAssertEqual(unavailable, YuGiOhCatalog.unavailablePricingNotice)
        await source.install(bundled)
        let bundleText = await YuGiOhCatalog.activePricingNotice(in: runtimes)
        XCTAssertEqual(bundleText, bundled.currentPricingNotice)
        XCTAssertTrue(bundleText.contains("a bundled snapshot"))
        await source.install(approved)
        let approvedText = await YuGiOhCatalog.activePricingNotice(in: runtimes)
        XCTAssertEqual(approvedText, approved.currentPricingNotice)
        XCTAssertTrue(approvedText.contains("a verified periodic snapshot"))
        XCTAssertFalse(approvedText.contains("bundled"))
        XCTAssertNotEqual(bundleText, approvedText)
    }

    func testRealListingOnlyPairAndBundledSnapshotNeverPretendLiveRefresh() async throws {
        let catalog = try YuGiOhCatalog.bundled.get()
        let p = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 21792 })
        let schema = Schema([PriceRecord.self, ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let prices = PriceStore(context: container.mainContext)
        let historical = catalog.capturedAt.addingTimeInterval(-3600)
        let key = PriceRecord.key(game: .yuGiOh, printingID: p.idString, variantID: YuGiOhEdition.first.rawValue)
        XCTAssertTrue(prices.store(.price(.init(unitMarketPriceUSD: 7, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "historical-fixture", sourceUpdatedAt: historical, fetchedAt: historical)), game: .yuGiOh,
            printingID: p.idString, variantID: YuGiOhEdition.first.rawValue, at: historical))
        XCTAssertTrue(prices.save())
        let successful = prices.record(forKey: key)?.lastSuccessfulCheckAt
        let coverage = try container.mainContext.fetchCount(FetchDescriptor<PriceCheckDay>())
        for watermark: Date? in [nil, .now] {
            do {
                let quote = try await YuGiOhPriceAdapter(catalog: catalog).refreshStoredPrinting(p.idString,
                    variant: .yugiohFirstEdition, minimumFetchedAt: watermark)
                _ = prices.store(quote, game: .yuGiOh, printingID: p.idString, variantID: YuGiOhEdition.first.rawValue)
                XCTFail("A historical missing quote must not stamp a successful current check")
            } catch PriceQuoteError.providerUnavailable {
                XCTAssertTrue(prices.recordFailure(game: .yuGiOh, printingID: p.idString, variantID: YuGiOhEdition.first.rawValue))
            }
            XCTAssertTrue(prices.save())
            XCTAssertEqual(prices.record(forKey: key)?.lastSuccessfulCheckAt, successful)
            XCTAssertEqual(prices.record(forKey: key)?.effectiveUnitMarketPriceUSD, 7)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PriceCheckDay>()), coverage)
        }
        let other = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 476160 })
        let result = try await YuGiOhPriceAdapter(catalog: catalog).refreshStoredPrinting(other.idString, variant: .yugiohUnlimited)
        guard case let .price(price) = result else { return XCTFail() }
        XCTAssertLessThan(price.fetchedAt, catalog.capturedAt)
        XCTAssertEqual(price.fetchedAt, price.sourceUpdatedAt)
        XCTAssertTrue(prices.store(result, game: .yuGiOh, printingID: other.idString, variantID: YuGiOhEdition.unlimited.rawValue))
        XCTAssertTrue(prices.save())
        let positiveKey = PriceRecord.key(game: .yuGiOh, printingID: other.idString, variantID: YuGiOhEdition.unlimited.rawValue)
        XCTAssertEqual(prices.record(forKey: positiveKey)?.lastSuccessfulCheckAt, price.fetchedAt)
        do {
            _ = try await YuGiOhPriceAdapter(catalog: catalog).refreshStoredPrinting(other.idString,
                variant: .yugiohUnlimited, minimumFetchedAt: .now)
            XCTFail("A historical bundle cannot fulfill a live refresh")
        } catch PriceQuoteError.providerUnavailable {}
    }
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
        let transport = TCGCSVProductPriceSource(baseURL: MarketMirrorFixture.baseURL, session: URLSession(configuration: config), cacheDirectory: root)
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
final class YuGiOhMarketHistoryTests: XCTestCase {
    private func withService(protocolClass: AnyClass = YuGiOhPricingProtocol.self,
                             _ body: (CardMarketHistoryService, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-history-\(UUID())")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            YuGiOhPricingProtocol.handler = nil
            YuGiOhDeliveryGateProtocol.handler = nil
            defaults.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://yugioh-history.invalid")!
        settings.minimumRequestInterval = 0
        let service = CardMarketHistoryService(transport: .init(configuration: settings, session: session,
            ledger: .init(defaults: defaults), pacer: .init(), apiKeyOverride: "fixture"), root: root)
        try await body(service, root)
    }

    func testHistoryResolvesAllEditionsFromCatalogWithoutRequiringASnapshotPrice() async throws {
        let catalog = try YuGiOhFixture.catalog(editions: YuGiOhEdition.allCases.map(\.rawValue), priced: [])
        let runtimes = try CardGameRuntimeContainer(runtimes: [catalog.runtime])
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
        for edition in YuGiOhEdition.allCases {
            var request = CardMarketHistoryRequest(card: card, variant: edition.variant, printRun: nil)
            request.exactProductID = "untrusted-stored-product"
            request.marketVariantID = "untrusted-stored-variant"
            let resolved = await request.resolvingMarketMapping(in: runtimes)
            XCTAssertTrue(resolved.requiresCatalogMapping)
            XCTAssertEqual(resolved.lookups, [.tcgplayerID(String(p.productID))])
            XCTAssertEqual(resolved.providerPrinting, edition.tcgplayerSubtype)
            XCTAssertNil(resolved.marketVariantID)
            let owned = CollectedCard(card: card, resolved: .init(variant: edition.variant, resolution: .userConfirmed))
            owned.tcgplayerProductID = "stale-product"
            owned.justTCGVariantID = "stale-variant"
            let collectionRequest = await CardMarketHistoryRequest(card: owned).resolvingMarketMapping(in: runtimes)
            XCTAssertEqual(collectionRequest.historyIdentity, resolved.historyIdentity,
                "Catalog and collection detail must share the same exact-edition cache")
            XCTAssertEqual(collectionRequest.lookups, resolved.lookups)
            XCTAssertNil(collectionRequest.marketVariantID)
            let unavailable = await request.resolvingMarketMapping(in: nil)
            XCTAssertNil(unavailable.exactProductID)
            XCTAssertTrue(unavailable.lookups.isEmpty)
        }
        for variant: PhysicalVariant? in [nil, .normal] {
            let unresolved = await CardMarketHistoryRequest(card: card, variant: variant, printRun: nil)
                .resolvingMarketMapping(in: runtimes)
            XCTAssertNil(unresolved.exactProductID)
        }
    }

    func testEditionHistoriesStaySeparateAndReusePersistedCache() async throws {
        try await withService { service, root in
            let catalog = try YuGiOhFixture.catalog(editions: YuGiOhEdition.allCases.map(\.rawValue))
            let runtimes = try CardGameRuntimeContainer(runtimes: [catalog.runtime])
            let p = try XCTUnwrap(catalog.printingByID.values.first)
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
            var calls = 0
            YuGiOhPricingProtocol.handler = { request in
                calls += 1
                let url = try XCTUnwrap(request.url)
                XCTAssertEqual(url.path, "/v1/cards")
                let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    .queryItems!.map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(query["tcgplayerId"], String(p.productID))
                XCTAssertEqual(query["include_price_history"], "true")
                XCTAssertEqual(query["priceHistoryDuration"], "1y")
                XCTAssertNil(query["variantId"])
                return Data("""
                {"data":[{"tcgplayerId":"\(p.productID)","variants":[
                  {"printing":"Unlimited","condition":"Near Mint","priceHistory":[{"p":2,"t":1700000000}]},
                  {"printing":"1st Edition","condition":"Damaged","priceHistory":[{"p":999,"t":1700000000}]},
                  {"printing":"1st Edition","condition":"Near Mint","language":"Japanese","priceHistory":[{"p":888,"t":1700000000}]},
                  {"printing":"1st Edition","condition":"Near Mint","language":"English","priceHistory":[{"p":1,"t":1700000000}]},
                  {"printing":"Limited","condition":"Near Mint","priceHistory":[{"p":3,"t":1700000000}]}
                ]}]}
                """.utf8)
            }
            for (edition, expected) in [(YuGiOhEdition.first, 1.0), (.unlimited, 2.0), (.limited, 3.0)] {
                let request = CardMarketHistoryRequest(card: card, variant: edition.variant, printRun: nil)
                let points = try await service.history(for: request, runtimes: runtimes)
                XCTAssertEqual(points.map(\.p), [expected])
                let repeated = try await service.history(for: request, runtimes: runtimes)
                XCTAssertEqual(repeated, points)
                let reopened = CardMarketHistoryService(root: root)
                let saved = await reopened.cached(request, runtimes: runtimes)
                XCTAssertEqual(saved, points)
                let offline = try await reopened.history(for: request, runtimes: runtimes)
                XCTAssertEqual(offline, points)
            }
            XCTAssertEqual(calls, 3)
        }
    }

    func testWrongAmbiguousAndForeignListingsNeverBecomeHistory() async throws {
        try await withService { service, _ in
            let catalog = try YuGiOhFixture.catalog()
            let runtimes = try CardGameRuntimeContainer(runtimes: [catalog.runtime])
            let p = try XCTUnwrap(catalog.printingByID.values.first)
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
            let request = CardMarketHistoryRequest(card: card, variant: .yugiohFirstEdition, printRun: nil)
            let exact = #"{"printing":"1st Edition","condition":"Near Mint","priceHistory":[{"p":42,"t":1700000000}]}"#
            let attacks = [
                exact.replacingOccurrences(of: "1st Edition", with: "Unlimited"),
                exact.replacingOccurrences(of: "Near Mint", with: "Lightly Played"),
                exact.replacingOccurrences(of: "\"condition\"", with: "\"missingCondition\""),
                exact.replacingOccurrences(of: "\"printing\"", with: "\"language\":\"Japanese\",\"printing\""),
                exact.replacingOccurrences(of: "\"printing\"", with: "\"currency\":\"EUR\",\"printing\""),
                exact.replacingOccurrences(of: "\"printing\"", with: "\"type\":\"graded\",\"printing\""),
                exact + "," + exact
            ]
            for (index, variants) in attacks.enumerated() {
                YuGiOhPricingProtocol.handler = { _ in
                    Data("{\"data\":[{\"tcgplayerId\":\"\(p.productID)\",\"variants\":[\(variants)]}]}".utf8)
                }
                do {
                    _ = try await service.history(for: request, now: Date.now.addingTimeInterval(Double(index) * 90000), runtimes: runtimes)
                    XCTFail("Invalid provider listing must not be used: \(index)")
                } catch CardMarketHistoryService.HistoryError.noListing {}
                let cached = await service.cached(request, runtimes: runtimes)
                XCTAssertTrue(cached.isEmpty)
            }
            YuGiOhPricingProtocol.handler = { _ in
                Data("{\"data\":[{\"tcgplayerId\":\"wrong-product\",\"variants\":[\(exact)]}]}".utf8)
            }
            do {
                _ = try await service.history(for: request, now: Date.now.addingTimeInterval(900000), runtimes: runtimes)
                XCTFail("A different product must not satisfy the catalog mapping")
            } catch CardMarketHistoryService.HistoryError.noListing {}
        }
    }

    func testCatalogWithdrawalHidesCachedHistoryAndCannotUseStoredVendorHandles() async throws {
        try await withService { service, _ in
            let catalog = try YuGiOhFixture.catalog()
            let p = try XCTUnwrap(catalog.printingByID.values.first)
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
            let source = YuGiOhNoticeSource()
            await source.install(catalog)
            let base = catalog.runtime
            let runtimes = try CardGameRuntimeContainer(runtimes: [.init(descriptor: base.descriptor,
                variantPolicy: base.variantPolicy, catalog: base.catalog, activationSource: source)])
            var request = CardMarketHistoryRequest(card: card, variant: .yugiohFirstEdition, printRun: nil)
            request.marketVariantID = "stale-variant"
            var calls = 0
            YuGiOhPricingProtocol.handler = { _ in
                calls += 1
                return Data("""
                {"data":[{"tcgplayerId":"\(p.productID)","variants":[{"printing":"1st Edition","condition":"Near Mint","priceHistory":[{"p":12,"t":1700000000}]}]}]}
                """.utf8)
            }
            let points = try await service.history(for: request, runtimes: runtimes)
            XCTAssertEqual(points.map(\.p), [12])
            // The same physical printing is retained, but its first-edition
            // membership is withdrawn by the newly active catalog.
            await source.install(try YuGiOhFixture.catalog(editions: [YuGiOhEdition.unlimited.rawValue]))
            let hidden = await service.cached(request, runtimes: runtimes)
            XCTAssertTrue(hidden.isEmpty)
            do {
                _ = try await service.history(for: request, runtimes: runtimes)
                XCTFail("Withdrawn edition must fail before requesting a provider")
            } catch CardMarketHistoryService.HistoryError.noListing {}
            XCTAssertEqual(calls, 1)
        }
    }

    func testMissingCredentialsReportsSettingsRecoveryWithoutMakingARequest() async throws {
        try await withService { _, root in
            let catalog = try YuGiOhFixture.catalog()
            let runtimes = try CardGameRuntimeContainer(runtimes: [catalog.runtime])
            let p = try XCTUnwrap(catalog.printingByID.values.first)
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
            let service = CardMarketHistoryService(transport: .init(apiKeyOverride: ""), root: root)
            do {
                _ = try await service.history(for: .init(card: card, variant: .yugiohFirstEdition, printRun: nil), runtimes: runtimes)
                XCTFail("Missing credentials must not become a missing-listing answer")
            } catch JustTCGTransport.TransportError.missingCredentials {
                XCTAssertTrue(JustTCGTransport.TransportError.missingCredentials.localizedDescription.contains("Settings"))
            }
        }
    }

    func testCatalogChangeDuringHistoryRequestCannotPublishOrCacheItsResponse() async throws {
        try await withService(protocolClass: YuGiOhDeliveryGateProtocol.self) { service, _ in
            let catalog = try YuGiOhFixture.catalog()
            let p = try XCTUnwrap(catalog.printingByID.values.first)
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
            let source = YuGiOhNoticeSource()
            await source.install(catalog)
            let base = catalog.runtime
            let runtimes = try CardGameRuntimeContainer(runtimes: [.init(descriptor: base.descriptor,
                variantPolicy: base.variantPolicy, catalog: base.catalog, activationSource: source)])
            let request = CardMarketHistoryRequest(card: card, variant: .yugiohFirstEdition, printRun: nil)
            let gate = YuGiOhDeliveryGate()
            let started = expectation(description: "History response suspended")
            YuGiOhDeliveryGateProtocol.handler = { request in
                Task { await gate.enter(request); started.fulfill() }
            }
            let pending = Task { try await service.history(for: request, runtimes: runtimes) }
            await fulfillment(of: [started], timeout: 5)
            await source.install(try YuGiOhFixture.catalog(editions: [YuGiOhEdition.unlimited.rawValue]))
            await gate.respond(Data("""
            {"data":[{"tcgplayerId":"\(p.productID)","variants":[{"printing":"1st Edition","condition":"Near Mint","priceHistory":[{"p":12,"t":1700000000}]}]}]}
            """.utf8))
            do { _ = try await pending.value; XCTFail("Obsolete response published") }
            catch is CancellationError {}
            await source.install(catalog)
            let cached = await service.cached(request, runtimes: runtimes)
            XCTAssertTrue(cached.isEmpty, "An obsolete response must not have been cached")
        }
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
    func testMP24WriterRejectsContradictionWithdrawalAndStaleGenerationWithoutPartialWrites() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-MP24-write-\(UUID())/collection.store")
        let original = try container(url), catalog = try YuGiOhCatalog.bundled.get()
        let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let p = try XCTUnwrap(catalog.printingsByCode["MP24-EN372"]?.first)
        let card = try adapter.resolution(forPrintingID: p.id).card
        let identifier = try YuGiOhRecognitionAdapter.identifier(code: p.code, generation: catalog.generation)
        func candidate(_ evidence: PrintedEditionEvidence) -> CollectionCommitCandidate {
            .init(resolvedScan: .init(request: .init(subject: .init(identifier: identifier, printedEdition: evidence),
                purpose: .collection, generation: 0), card: card,
                resolved: .init(variant: .yugiohFirstEdition, resolution: .printedLabel), pokemonPrintRun: nil,
                options: [.yugiohFirstEdition]))
        }
        let writer = ScannerCollectionWriter(modelContainer: original)
        for evidence in [PrintedEditionEvidence.absent, .observed(.yugiohLimited),
                         .merged([.observed(.yugiohFirstEdition), .observed(.yugiohLimited)])] {
            do { _ = try await writer.add(candidate(evidence)); XCTFail("Unsupported acquisition must be rejected") } catch {}
        }
        var object = try YuGiOhFixture.mp24Object()
        object["generation"] = "yugioh-en-withdrawn"
        object["autoEligibleCodes"] = []
        var rows = object["printings"] as! [[String: Any]]
        rows[0].removeValue(forKey: "pf"); rows[0]["e"] = []; rows[0]["m"] = []
        object["printings"] = rows
        let withdrawn = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        let withdrawalBound = try await CardGameRuntimeContainer(runtimes: [withdrawn.runtime]).bound(to: original)
        do { _ = try await writer.add(candidate(.observed(.yugiohFirstEdition))); XCTFail("Old authority must not commit") } catch {}
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        // Retry after a fresh authority installation succeeds without a partial
        // event from any rejected attempt. These are isolated test stores.
        let retryBound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        _ = try await writer.add(candidate(.observed(.yugiohFirstEdition)))
        XCTAssertEqual(try original.mainContext.fetchCount(FetchDescriptor<CollectedCard>()), 1)
        XCTAssertEqual(try original.mainContext.fetchCount(FetchDescriptor<InventoryEvent>()), 1)
        withExtendedLifetime((bound, withdrawalBound, retryBound)) {}
    }
    func testAutomaticAndEditionOnlyAcrossModernAndLegacyCatalogReopen() async throws {
        for (code, observed) in ["MP24-EN372", "DUNE-EN051", "PSV-001"].flatMap({ code in [true, false].map { (code, $0) } }) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-MP24-\(UUID())/collection.store")
            let catalog = try YuGiOhCatalog.bundled.get(), original = try container(url)
            let printing = try XCTUnwrap(catalog.printingsByCode[code]?.first)
            let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
            let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
                catalog: bound.makeCardCatalog(), unresolvedScanStore: UnresolvedScanStore(fileURL: url.deletingLastPathComponent().appendingPathComponent("recovery.json")))
            model.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
            defer { model.viewDisappeared() }
            let lines: [RecognizedLine] = [.init(text: code, confidence: 0.99)]
                + (observed ? [.init(text: "1st Edition", confidence: 0.99)] : [])
            guard case let .identified(subject) = YuGiOhRecognitionAdapter(catalog: catalog).identify(lines) else { return XCTFail() }
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
            let settled = await waitUntil { observed ? model.successCount == 1 : model.pendingChoice != nil }
            XCTAssertTrue(settled)
            XCTAssertNil(model.pendingIdentityChoice)
            if !observed {
                XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
                XCTAssertEqual(model.pendingChoice?.options, printing.editions.map(\.variant))
                model.choose(.yugiohFirstEdition)
                let saved = await waitUntil { model.successCount == 1 }
                XCTAssertTrue(saved)
            }
            XCTAssertNil(model.pendingChoice)
            let rows = try original.mainContext.fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.quantity, 1)
            XCTAssertEqual(rows.first?.variantID, "yugioh1stEdition")
            XCTAssertEqual(rows.first?.identityResolutionRaw, IdentityResolution.printedIdentifier.rawValue)
            XCTAssertEqual(rows.first?.variantResolutionRaw, (observed ? VariantResolution.printedLabel : .userConfirmed).rawValue)
            XCTAssertEqual(try original.mainContext.fetchCount(FetchDescriptor<InventoryEvent>()), 1)
            let reopened = try container(url)
            let restored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(restored.collectionKey, "yu-gi-oh:\(printing.idString)#yugioh1stEdition")
            XCTAssertEqual(restored.quantity, 1)
        }
    }
    func testMixedGameMultiQuantityCSVReopenResumeAndAdditionalCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-mixed-csv-\(UUID())")
        let source = try container(root.appendingPathComponent("source.store"))
        let catalog = try YuGiOhCatalog.bundled.get()
        let pokemon = CardGameRuntime(descriptor: PokemonGameRuntime.descriptor,
            variantPolicy: PokemonVariantPolicy(), catalog: PokemonCatalogAdapter())
        let runtimes = try CardGameRuntimeContainer(runtimes: [pokemon, catalog.runtime])
        _ = try await runtimes.bound(to: source)
        let store = CollectionStore(context: source.mainContext)
        for (product, variant, quantity) in [(21792, PhysicalVariant.yugiohFirstEdition, 2),
                                            (21792, .yugiohUnlimited, 3), (26366, .yugiohLimited, 4)] {
            let printing = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == product })
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: printing.id).card
            _ = try store.add(card, resolved: .init(variant: variant, resolution: .userConfirmed), quantity: quantity)
        }
        let eevee = IdentifiedCard.pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"sv08.5-001","localId":"001","name":"Eevee","set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":180,"official":131}}}"#.utf8)), setCode: "PRE")
        _ = try store.add(eevee, resolved: .init(variant: .normal, resolution: .userConfirmed), quantity: 5)
        let exported = try await CollectionCSV.exportIsolated(from: source)
        let plan = try CollectionCSV.parse(Data(exported.text.utf8))
        XCTAssertEqual(plan.entries.count, 4)
        XCTAssertEqual(plan.totalQuantity, 14)
        let targetURL = root.appendingPathComponent("target.store")
        let target = try container(targetURL)
        let bound = try await runtimes.bound(to: target)
        let adapters = await bound.currentImportAdapters()
        func apply(_ plan: CollectionCSVImportPlan) async throws -> CollectionCSVImportResult {
            let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
            defer { CollectionWriteSerializer.endExclusive(token) }
            return try await CollectionCSV.applyIsolated(plan, to: target, exclusiveToken: token,
                gameRegistry: bound.registry, gameImportAdapters: adapters)
        }
        let imported = try await apply(plan)
        XCTAssertEqual(imported.importedQuantity, 14)
        XCTAssertTrue(imported.failedRows.isEmpty)
        func verify(_ multiple: Int) throws {
            let reopened = try container(targetURL)
            let originals = try source.mainContext.fetch(FetchDescriptor<CollectedCard>())
            let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, 4)
            for original in originals {
                let row = try XCTUnwrap(rows.first { $0.collectionKey == original.collectionKey })
                XCTAssertEqual(row.game, original.game)
                XCTAssertEqual(row.providerID, original.providerID)
                XCTAssertEqual(row.catalogProviderID, original.catalogProviderID)
                XCTAssertEqual(row.variantID, original.variantID)
                XCTAssertEqual(row.quantity, original.quantity * multiple)
            }
            let events = try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>())
            XCTAssertEqual(events.reduce(0) { $0 + $1.deltaQuantity }, 14 * multiple)
            XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>()).reduce(0) { $0 + $1.deltaQuantity }, 14 * multiple)
        }
        try verify(1)
        let resumed = try await apply(plan)
        XCTAssertEqual(resumed.alreadyImportedEntries, 4)
        XCTAssertEqual(resumed.importedQuantity, 0)
        try verify(1)
        let additional = plan.importingAgainAsAdditionalCopies()
        defer { CollectionCSV.finishImportAgainRun(additional) }
        let extra = try await apply(additional)
        XCTAssertEqual(extra.importedQuantity, 14)
        try verify(2)
        let extraResume = try await apply(additional)
        XCTAssertEqual(extraResume.importedQuantity, 0)
        try verify(2)
        let printing = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 21792 })
        do {
            _ = try await YuGiOhPriceAdapter(catalog: catalog).refreshStoredPrinting(printing.idString, variant: .yugiohFirstEdition)
            XCTFail("Listing-only First Edition must remain unvalued")
        } catch PriceQuoteError.providerUnavailable {}
    }

    func testSuspendedCollectionRecoveryPreflightRejectsCancellationAndChangedAuthority() async throws {
        for changeAuthority in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-preflight-\(UUID())")
            let original = try container(root.appendingPathComponent("collection.store"))
            let catalog = try YuGiOhFixture.catalog(count: 2, auto: false)
            let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
            let service = bound.makeCardCatalog()
            let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
                catalog: service, unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
            model.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), try YuGiOhFixture.subject(catalog), nil)
            let appeared = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(appeared)
            let candidate = try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates.first)
            model.dismissIdentityChoice()
            let row = try XCTUnwrap(model.unresolvedScans.first)
            let gate = YuGiOhRecoveryPreflightGate()
            await service.install(SuspendedYuGiOhRecoveryAdapter(base: .init(catalog: catalog), gate: gate))
            let preflight = Task { await model.prepareUnresolvedResolution(id: row.id, choice: .printing(candidate)) }
            await gate.waitUntilStarted()
            if changeAuthority {
                var object = YuGiOhFixture.object(count: 2, auto: false)
                object["generation"] = "yugioh-en-replacement"
                let replacement = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
                await service.install(YuGiOhCatalogAdapter(catalog: replacement))
            } else { preflight.cancel() }
            await gate.release()
            let prepared = await preflight.value
            XCTAssertFalse(prepared, "The collection recovery preflight itself was suspended")
            if changeAuthority {
                model.resolveUnresolved(id: row.id, choice: .printing(candidate))
                let rejected = await waitUntil { model.unresolvedResolutionErrors[row.id] != nil && !model.isIdentificationProcessingForTesting }
                XCTAssertTrue(rejected)
            }
            XCTAssertNil(model.pendingChoice)
            XCTAssertEqual(model.unresolvedScans.map(\.id), [row.id])
            model.viewDisappeared()
            let reopened = try container(root.appendingPathComponent("collection.store"))
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        }
    }

    func testMalformedDurableLineageOverflowRejectsWithoutTrapping() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-overflow-\(UUID())/collection.store")
        let original = try container(url), catalog = try YuGiOhFixture.catalog()
        _ = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let printing = try XCTUnwrap(catalog.printingByID.values.first)
        let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: printing.id).card
        let store = CollectionStore(context: original.mainContext)
        let acquisition = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed))
        let correction = try XCTUnwrap(store.recordVariantCorrection(for: card, from: .yugiohFirstEdition,
            to: .init(variant: .yugiohUnlimited, resolution: .userConfirmed), previousCollectionKey: acquisition.collectionKey,
            previousLedgerOperationIDs: acquisition.ledgerOperationIDs, activityID: acquisition.activityID))
        let from = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).first { $0.leg == .from })
        from.deltaQuantity = Int.max
        // Simulate malformed data on disk, bypassing the normal mutation gate.
        try original.mainContext.save()
        let reopened = try container(url)
        let recoveredStore = CollectionStore(context: reopened.mainContext)
        XCTAssertFalse(recoveredStore.hasValidLineage(correction.ledgerOperationIDs, for: correction.collectionKey, quantity: 1))
        XCTAssertThrowsError(try recoveredStore.undo(correction))
    }
    func testCyclicCorrectionUndoAfterRetirementReopensWithExactInverseLineage() async throws {
        try await cyclicCorrectionUndo(browseOnly: false, sibling: false)
    }

    func testBrowseOnlyCyclicCorrectionUndoPreservesDurableSiblingAndRetriesFailure() async throws {
        try await cyclicCorrectionUndo(browseOnly: true, sibling: true)
    }

    private func cyclicCorrectionUndo(browseOnly: Bool, sibling: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-cycle-\(UUID())/collection.store")
        let original = try container(url), catalog = try YuGiOhFixture.catalog()
        _ = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: XCTUnwrap(catalog.printingByID.values.first).id).card
        let store = CollectionStore(context: original.mainContext)
        var mutation = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed))
        for (from, to) in [(PhysicalVariant.yugiohFirstEdition, PhysicalVariant.yugiohUnlimited), (.yugiohUnlimited, .yugiohFirstEdition)] {
            mutation = try XCTUnwrap(store.recordVariantCorrection(for: card, from: from,
                to: .init(variant: to, resolution: .userConfirmed), previousCollectionKey: mutation.collectionKey,
                previousLedgerOperationIDs: mutation.ledgerOperationIDs, activityID: mutation.activityID))
        }
        if sibling {
            _ = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed))
            try splitDurablePosition(in: original.mainContext)
        }
        let before = try original.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        let beforeIDs = Set(before.map(\.eventID))
        let contributors = Set(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.persistentModelID))
        let historyIDs = Set(try original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).map(\.id))
        var retiredObject = YuGiOhFixture.providerSupportedObject()
        var retiredRows = retiredObject["printings"] as! [[String: Any]]
        retiredRows[0]["e"] = browseOnly ? [] : ["yugiohUnlimited"]
        retiredRows[0]["m"] = (retiredRows[0]["m"] as! [[String: Any]]).filter { !browseOnly && $0["e"] as? String == "yugiohUnlimited" }
        retiredObject["printings"] = retiredRows
        let retired = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: retiredObject))
        let bound = try await CardGameRuntimeContainer(runtimes: [retired.runtime]).bound(to: original)
        XCTAssertEqual(bound.registry.supports(.yuGiOh, .collectionWrite), !browseOnly)
        for attack in 0..<9 {
            try store.undo(mutation, savesChanges: false)
            let pending = original.mainContext.insertedModelsArray.compactMap { $0 as? InventoryEvent }
            let positive = try XCTUnwrap(pending.first { $0.collectionKey == mutation.collectionKey && $0.deltaQuantity > 0 })
            switch attack {
            case 0: positive.reversesEventID = nil
            case 1: positive.reversesEventID = UUID()
            case 2: positive.reversesEventID = pending.first { $0.deltaQuantity < 0 }?.reversesEventID
            case 3:
                let otherLeg = try XCTUnwrap(pending.first { $0.collectionKey != mutation.collectionKey })
                original.mainContext.delete(otherLeg)
            case 4: positive.deltaQuantity = 2
            case 5: positive.priceStorageKey = "forged-identity"
            case 6:
                // Same -1 net at A, but a fresh acquisition paired with a
                // disposal must never acquire retired-edition permission.
                positive.kindRaw = InventoryEventKind.acquire.rawValue
                positive.reversesEventID = nil
                let negative = try XCTUnwrap(pending.first { $0.collectionKey == mutation.collectionKey && $0.deltaQuantity < 0 })
                negative.kindRaw = InventoryEventKind.dispose.rawValue
                negative.deltaQuantity = -2
                negative.reversesEventID = nil
                let redundant = try XCTUnwrap(pending.first { $0.collectionKey == mutation.collectionKey && $0.eventID != positive.eventID && $0.eventID != negative.eventID })
                original.mainContext.delete(redundant)
            case 7:
                let row = try XCTUnwrap(original.mainContext.deletedModelsArray.compactMap { $0 as? CollectedCard }.first
                    ?? original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
                let lookalike = CollectedCard(collectionKey: row.collectionKey, game: .yuGiOh,
                    providerID: row.providerID, name: row.name, setName: row.setName, setCode: row.setCode,
                    cardNumber: row.cardNumber, rarity: row.rarity, imageURL: nil, thumbnailURL: nil,
                    variant: .yugiohFirstEdition, variantResolution: .userConfirmed, quantity: 1)
                lookalike.catalogProviderID = row.catalogProviderID
                original.mainContext.insert(lookalike)
            default:
                let acquisition = try XCTUnwrap(original.mainContext.changedModelsArray.compactMap { $0 as? CollectionActivity }.first { $0.id == mutation.activityID })
                acquisition.ledgerOperationIDs.removeLast()
            }
            XCTAssertThrowsError(try store.validatePendingGameWrites(), "Rejected forged/partial inverse attack \(attack)")
            original.mainContext.rollback()
        }
        var reachedSave = false
        let failing = CollectionStore(context: original.mainContext, beforeSaveForTesting: { _ in
            reachedSave = true
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertThrowsError(try failing.undo(mutation))
        XCTAssertTrue(reachedSave, "Valid inverses must pass final authority before injected save failure")
        XCTAssertEqual(Set(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.persistentModelID)), contributors)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).reduce(0) { $0 + $1.quantity }, sibling ? 2 : 1)
        XCTAssertEqual(Set(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).map(\.eventID)), beforeIDs)
        XCTAssertEqual(Set(try original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).map(\.id)), historyIDs)
        try store.undo(mutation)
        XCTAssertThrowsError(try store.undo(mutation))
        let reopened = try container(url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).reduce(0) { $0 + $1.quantity }, sibling ? 1 : 0)
        let events = try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        let inverse = events.filter { $0.reversesEventID != nil }
        XCTAssertEqual(inverse.count, 5)
        let targets = before.filter { mutation.ledgerOperationIDs.contains($0.operationID) }
        XCTAssertEqual(Set(inverse.compactMap(\.reversesEventID)), Set(targets.map(\.eventID)))
        for event in inverse {
            let target = try XCTUnwrap(targets.first { $0.eventID == event.reversesEventID })
            XCTAssertEqual(event.collectionKey, target.collectionKey)
            XCTAssertEqual(event.priceStorageKey, target.priceStorageKey)
            XCTAssertEqual(event.deltaQuantity, -target.deltaQuantity)
            XCTAssertEqual(event.kind, target.kind)
            XCTAssertEqual(event.leg, target.leg)
        }
        XCTAssertEqual(events.filter { $0.collectionKey == card.collectionKey(variant: .yugiohFirstEdition) }.reduce(0) { $0 + $1.deltaQuantity }, sibling ? 1 : 0)
        XCTAssertEqual(events.filter { $0.collectionKey == card.collectionKey(variant: .yugiohUnlimited) }.reduce(0) { $0 + $1.deltaQuantity }, 0)
        let activities = try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.filter { $0.kind == .undone }.count, 1)
        XCTAssertEqual(activities.first { $0.id == mutation.activityID }?.remainingQuantity, 0)
        XCTAssertEqual(Set(try XCTUnwrap(activities.first { $0.kind == .undone }).ledgerOperationIDs), Set(inverse.map(\.operationID)))
    }

    /// Model the supported CloudKit shape: two durable physical rows, one
    /// logical acquisition/history claim. No ledger event is invented by merge.
    private func splitDurablePosition(in context: ModelContext) throws {
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first { $0.cardGame == .yuGiOh })
        XCTAssertEqual(row.quantity, 2)
        row.quantity = 1
        let duplicate = CollectedCard(collectionKey: row.collectionKey, game: row.cardGame,
            providerID: row.providerID, name: row.name, setName: row.setName, setCode: row.setCode,
            cardNumber: row.cardNumber, rarity: row.rarity, imageURL: row.imageURL,
            thumbnailURL: row.thumbnailURL, variant: .yugiohFirstEdition,
            variantResolution: .userConfirmed, quantity: 1)
        duplicate.catalogProviderID = row.catalogProviderID
        context.insert(duplicate)
        try context.save()
        XCTAssertEqual(try ModelContext(context.container).fetch(FetchDescriptor<CollectedCard>()).filter { $0.cardGame == .yuGiOh }.count, 2)
    }

    func testDurableDuplicateRemovalRollbackRetryReopenAndExactRestore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-duplicates-\(UUID())/collection.store")
        let original = try container(url), catalog = try YuGiOhFixture.catalog()
        _ = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed), quantity: 2)
        try splitDurablePosition(in: original.mainContext)
        let rows = try original.mainContext.fetch(FetchDescriptor<CollectedCard>())
        let ids = Set(rows.map(\.persistentModelID))
        let retired = try YuGiOhFixture.catalog(complete: false, auto: false, editions: [], priced: [])
        _ = try await CardGameRuntimeContainer(runtimes: [retired.runtime]).bound(to: original)
        let failing = CollectionStore(context: original.mainContext, beforeSaveForTesting: { _ in throw CocoaError(.fileWriteUnknown) })
        XCTAssertThrowsError(try failing.remove(rows[0]))
        let rolledBack = try original.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(rolledBack.map(\.persistentModelID)), ids)
        XCTAssertEqual(rolledBack.map(\.quantity).sorted(), [1, 1])
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count, 1)
        let snapshot = try store.remove(rolledBack[0])
        XCTAssertEqual(snapshot.quantity, 2)
        let reopened = try container(url)
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let events = try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.reduce(0) { $0 + $1.deltaQuantity }, 0)
        let history = try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>())
        let removal = try XCTUnwrap(history.first { $0.kind == .removed })
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(removal.signedQuantity, -2)
        let savedSnapshot = try JSONDecoder().decode(RemovedCardSnapshot.self, from: XCTUnwrap(removal.removalSnapshotData))
        XCTAssertEqual(savedSnapshot.quantity, 2)
        XCTAssertEqual(savedSnapshot.operationID, snapshot.operationID)
        let forgedRestore = CollectionStore(context: original.mainContext, beforeSaveForTesting: { context in
            let restored = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
            let lookalike = CollectedCard(collectionKey: restored.collectionKey, game: .yuGiOh,
                providerID: restored.providerID, name: restored.name, setName: restored.setName,
                setCode: restored.setCode, cardNumber: restored.cardNumber, rarity: restored.rarity,
                imageURL: nil, thumbnailURL: nil, variant: .yugiohFirstEdition,
                variantResolution: .userConfirmed, quantity: 2)
            lookalike.catalogProviderID = restored.catalogProviderID
            context.insert(lookalike)
            XCTAssertThrowsError(try CollectionStore(context: context).validatePendingGameWrites(),
                "A disposal inverse cannot authorize two inserted restoration rows")
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertThrowsError(try forgedRestore.restore(snapshot))
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 2)
        try store.restore(snapshot)
        let restoredEvents = try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count
        let restoredActivities = try original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count
        XCTAssertThrowsError(try store.restore(snapshot))
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, restoredEvents)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count, restoredActivities)
        let restored = try container(url)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [2])
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<InventoryEvent>()).reduce(0) { $0 + $1.deltaQuantity }, 2)
    }

    func testRetiredDuplicateReductionConservesLedgerAndRejectsIncrease() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-reduction-\(UUID())/collection.store")
        let original = try container(url), catalog = try YuGiOhFixture.catalog()
        _ = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        let card = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed), quantity: 2)
        try splitDurablePosition(in: original.mainContext)
        _ = try await CardGameRuntimeContainer(runtimes: [YuGiOhFixture.catalog(complete: false, auto: false, editions: [], priced: []).runtime]).bound(to: original)
        let key = card.collectionKey(variant: .yugiohFirstEdition)
        XCTAssertEqual(try store.setQuantity(1, forCollectionKey: key, expectedCurrent: 2), 1)
        XCTAssertThrowsError(try store.setQuantity(2, forCollectionKey: key, expectedCurrent: 1))
        let reopened = try container(url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [1])
        let events = try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.reduce(0) { $0 + $1.deltaQuantity }, 1)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count, 2)
    }

    func testMixedBrowseOnlyDuplicateDeleteAllCancellationFailureAndReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-bulk-\(UUID())/collection.store")
        let original = try container(url), catalog = try YuGiOhFixture.catalog()
        _ = try await CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime, catalog.runtime]).bound(to: original)
        let store = CollectionStore(context: original.mainContext)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        _ = try store.add(YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id).card,
            resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed), quantity: 2)
        let pokemon = IdentifiedCard.pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"sv08.5-001","localId":"001","name":"Eevee","set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":180,"official":131}}}"#.utf8)), setCode: "PRE")
        _ = try store.add(pokemon, resolved: .init(variant: .normal, resolution: .userConfirmed))
        try splitDurablePosition(in: original.mainContext)
        _ = try await CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime, YuGiOhFixture.catalog(complete: false, auto: false, editions: [], priced: []).runtime]).bound(to: original)
        let ids = Set(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.persistentModelID))
        XCTAssertFalse(try store.deleteAll(shouldContinue: { false }))
        var checks = 0
        XCTAssertFalse(try store.deleteAll(shouldContinue: { checks += 1; return checks < 3 }))
        XCTAssertEqual(Set(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.persistentModelID)), ids)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 2)
        var saveAttempts = 0
        let failing = CollectionStore(context: original.mainContext, beforeSaveForTesting: { _ in saveAttempts += 1; throw CocoaError(.fileWriteUnknown) })
        XCTAssertThrowsError(try failing.deleteAll())
        XCTAssertEqual(saveAttempts, 1)
        XCTAssertEqual(Set(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.persistentModelID)), ids)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 2)
        let checked = CollectionStore(context: original.mainContext, beforeSaveForTesting: { _ in saveAttempts += 1 })
        XCTAssertTrue(try checked.deleteAll())
        XCTAssertEqual(saveAttempts, 2, "One save for the entire mixed collection")
        let reopened = try container(url)
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let events = try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.reduce(0) { $0 + $1.deltaQuantity }, 0)
        let removals = try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>()).filter { $0.kind == .removed }
        XCTAssertEqual(removals.count, 2)
        XCTAssertEqual(removals.map(\.signedQuantity).sorted(), [-2, -1])
        for removal in removals {
            let snapshot = try JSONDecoder().decode(RemovedCardSnapshot.self, from: XCTUnwrap(removal.removalSnapshotData))
            XCTAssertEqual(snapshot.quantity, -removal.signedQuantity)
        }
    }

    func testRealDCRStaleChoiceRetainsFamilyAndCancellationCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-stale-\(UUID())")
        let catalog = try YuGiOhCatalog.bundled.get(), original = try container(root.appendingPathComponent("collection.store"))
        let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let service = bound.makeCardCatalog()
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
            catalog: service, unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        let identifier = try YuGiOhRecognitionAdapter.identifier(code: "DCR-EN000", generation: catalog.generation)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: identifier), nil)
        let appeared = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(appeared)
        let candidates = try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates)
        let supported = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 487277 })
        let choice = try XCTUnwrap(candidates.first { $0.id == supported.idString })
        await service.install(YuGiOhCatalogAdapter(catalog: try YuGiOhFixture.catalog()))
        model.choose(choice)
        let recovered = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(recovered)
        XCTAssertEqual(model.pendingIdentityChoice?.displayCandidates, candidates)
        XCTAssertTrue(model.scanAcknowledgement?.message?.contains("no longer available") == true)
        model.dismissIdentityChoice()
        let unresolved = try XCTUnwrap(model.unresolvedScans.first)
        XCTAssertEqual(unresolved.printingCandidates, candidates)
        await service.install(YuGiOhCatalogAdapter(catalog: catalog))
        model.resolveUnresolved(id: unresolved.id, choice: .printing(choice))
        let edition = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(edition)
        model.choose(.yugiohUnlimited)
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.providerID, supported.idString)
    }

    func testDCRRecoveryAvailabilityReloadLegacyAuthorityAndDirectActions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-recovery-\(UUID())")
        let catalog = try YuGiOhCatalog.bundled.get(), original = try container(root.appendingPathComponent("collection.store"))
        let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let service = bound.makeCardCatalog()
        let recovery = UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json"))
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
            catalog: service, unresolvedScanStore: recovery)
        model.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        let identifier = try YuGiOhRecognitionAdapter.identifier(code: "DCR-EN000", generation: catalog.generation)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: identifier), nil)
        let appeared = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(appeared)
        let family = try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates)
        let discoveryID = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 476802 }).idString
        let supportedID = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 487277 }).idString
        let discovery = try XCTUnwrap(family.first { $0.id == discoveryID })
        let supported = try XCTUnwrap(family.first { $0.id == supportedID })
        let evidence = PhysicalPrintingCandidate.selectionEvidenceByID(among: family)
        XCTAssertNotNil(discovery.acquisitionUnavailableReason)
        XCTAssertTrue(UnresolvedScanDetailView.compactChoiceDisabled(discovery, evidence: evidence[discovery.id], requiresEnglish: false, englishConfirmed: false))
        XCTAssertFalse(UnresolvedScanDetailView.compactChoiceDisabled(supported, evidence: evidence[supported.id], requiresEnglish: false, englishConfirmed: false))
        XCTAssertTrue(UnresolvedScanDetailView.compactChoiceDisabled(supported, evidence: evidence[supported.id], requiresEnglish: true, englishConfirmed: false))
        model.dismissIdentityChoice()
        let row = try XCTUnwrap(model.unresolvedScans.first)
        let blocked = await model.prepareUnresolvedResolution(id: row.id, choice: .printing(discovery))
        XCTAssertFalse(blocked, "False keeps the recovery sheet open")
        XCTAssertEqual(model.unresolvedResolutionErrors[row.id], discovery.acquisitionUnavailableReason)
        model.resolveUnresolved(id: row.id, choice: .printing(discovery))
        XCTAssertNil(model.pendingChoice)
        XCTAssertEqual(model.unresolvedScans.first?.printingCandidates, family)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)

        // Persist/reload through the same recovery actor. Remove the optional
        // field to model a legacy saved choice, not a trusted new candidate.
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(discovery)) as? [String: Any])
        legacyObject.removeValue(forKey: "acquisitionUnavailableReason")
        let legacy = try JSONDecoder().decode(PhysicalPrintingCandidate.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        var legacyRow = row
        legacyRow.printingCandidates = family.map { $0.id == discoveryID ? legacy : $0 }
        // Drain the view model's queued save before writing the legacy fixture.
        try? await Task.sleep(for: .milliseconds(300))
        let persisted = await recovery.save([legacyRow])
        XCTAssertTrue(persisted)
        model.viewDisappeared()
        let reloaded = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
            catalog: service, unresolvedScanStore: recovery)
        reloaded.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { reloaded.viewDisappeared() }
        let loaded = await waitUntil { reloaded.unresolvedScans.count == 1 }
        XCTAssertTrue(loaded)
        XCTAssertEqual(reloaded.unresolvedScans.first?.printingCandidates, legacyRow.printingCandidates)
        XCTAssertNil(legacy.acquisitionUnavailableReason)
        let legacyBlocked = await reloaded.prepareUnresolvedResolution(id: row.id, choice: .printing(legacy))
        XCTAssertFalse(legacyBlocked)
        XCTAssertTrue(reloaded.unresolvedResolutionErrors[row.id]?.contains("retry lookup") == true)
        reloaded.resolveUnresolved(id: row.id, choice: .printing(legacy))
        let failedDirect = await waitUntil {
            reloaded.unresolvedResolutionErrors[row.id]?.contains("could not be resolved") == true
                && !reloaded.isIdentificationProcessingForTesting
        }
        XCTAssertTrue(failedDirect)
        XCTAssertEqual(reloaded.unresolvedScans.first?.printingCandidates, legacyRow.printingCandidates)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)

        await service.install(YuGiOhCatalogAdapter(catalog: try YuGiOhFixture.catalog()))
        let staleBlocked = await reloaded.prepareUnresolvedResolution(id: row.id, choice: .printing(supported))
        XCTAssertFalse(staleBlocked)
        XCTAssertEqual(reloaded.unresolvedScans.count, 1)
        reloaded.resolveUnresolved(id: row.id, choice: .printing(supported))
        let staleDirect = await waitUntil {
            reloaded.unresolvedResolutionErrors[row.id]?.contains("could not be resolved") == true
                && !reloaded.isIdentificationProcessingForTesting
        }
        XCTAssertTrue(staleDirect)
        XCTAssertEqual(reloaded.unresolvedScans.first?.printingCandidates, legacyRow.printingCandidates)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        await service.install(YuGiOhCatalogAdapter(catalog: catalog))
        let cancelled = Task { await reloaded.prepareUnresolvedResolution(id: row.id, choice: .printing(supported)) }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertFalse(cancelledResult)
        XCTAssertEqual(reloaded.unresolvedScans.count, 1)
        let ready = await reloaded.prepareUnresolvedResolution(id: row.id, choice: .printing(supported))
        XCTAssertTrue(ready)
        XCTAssertNil(reloaded.unresolvedResolutionErrors[row.id])
        reloaded.resolveUnresolved(id: row.id, choice: .printing(supported))
        let edition = await waitUntil { reloaded.pendingChoice != nil && !reloaded.isIdentificationProcessingForTesting }
        XCTAssertTrue(edition)
        reloaded.choose(.yugiohUnlimited)
        let saved = await waitUntil { reloaded.successCount == 1 }
        XCTAssertTrue(saved)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [1])
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
        XCTAssertTrue(reloaded.unresolvedScans.isEmpty)
    }

    func testAcceptanceRecoveryPreservesPreexistingNormalBytesAcrossDismissAndClear() async throws {
        XCTAssertEqual(YuGiOhAcceptanceLaunch.storageDirectory(arguments: ["-ui_debug_route", "YuGiOhAcceptance", "-ui_debug_state", "csv-import"]), "YuGiOhCSVImportAcceptance")
        XCTAssertEqual(YuGiOhAcceptanceLaunch.storageDirectory(arguments: ["-ui_debug_route", "YuGiOhAcceptance", "-ui_debug_state", "mixed-csv-source"]), "YuGiOhMixedCSVSourceAcceptance")
        XCTAssertEqual(YuGiOhAcceptanceLaunch.storageDirectory(arguments: ["-ui_debug_route", "YuGiOhAcceptance", "-ui_debug_state", "mixed-csv-import"]), "YuGiOhMixedCSVImportAcceptance")
        XCTAssertEqual(YuGiOhAcceptanceLaunch.storageDirectory(arguments: ["-ui_debug_route", "WholeCardScanner", "-ui_debug_state", "csv-import"]), "YuGiOhAcceptance")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-isolation-\(UUID())")
        let catalog = try YuGiOhCatalog.bundled.get()
        let normalURL = root.appendingPathComponent("Scanner/unresolved-scans.json")
        let normal = UnresolvedScanStore(fileURL: normalURL)
        let subject = ScanSubject(identifier: try YuGiOhRecognitionAdapter.identifier(code: "LOB-001", generation: catalog.generation))
        let normalSaved = await normal.save([UnresolvedScan(subject: subject, reason: .interrupted)])
        XCTAssertTrue(normalSaved)
        let bytes = try Data(contentsOf: normalURL)
        let isolated = UnresolvedScanStore(fileURL: YuGiOhAcceptanceLaunch.recoveryFileURL(applicationSupport: root))
        let original = try container(root.appendingPathComponent("acceptance.store"))
        let bound = try await CardGameRuntimeContainer(runtimes: [catalog.runtime]).bound(to: original)
        let model = ScannerViewModel(gameRegistry: bound.registry, priceQuoteService: bound.makePriceQuoteService(),
            catalog: bound.makeCardCatalog(), unresolvedScanStore: isolated)
        model.start(context: original.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        let loaded = await waitUntil { !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(loaded)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let pending = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(pending)
        model.dismissIdentityChoice()
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertEqual(try Data(contentsOf: normalURL), bytes)
        model.dismissUnresolved(id: try XCTUnwrap(model.unresolvedScans.first?.id))
        model.fileUnresolvedForTesting(subject, reason: .interrupted)
        model.clearUnresolvedScans()
        // Drain the store's serial actor after queued recovery persistence.
        try? await Task.sleep(for: .milliseconds(300))
        _ = await isolated.load()
        XCTAssertEqual(try Data(contentsOf: normalURL), bytes)
        let outcome = YuGiOhRecognitionAdapter(catalog: catalog).identify(YuGiOhAcceptanceLaunch.Sample.unknown.lines)
        XCTAssertEqual(outcome, .nothing)
        XCTAssertEqual(YuGiOhAcceptanceLaunch.diagnostic(for: outcome),
            "Recognition diagnostic: no catalog match. No card was identified or added.")
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testDiscoveryRuntimeAllowsDurableDeleteRestoreButRejectsAcquisition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-retired-\(UUID())")
        let url = root.appendingPathComponent("collection.store"), original = try container(url)
        let initial = try YuGiOhFixture.catalog()
        _ = try await CardGameRuntimeContainer(runtimes: [initial.runtime]).bound(to: original)
        let p = try XCTUnwrap(initial.printingByID.values.first)
        let card = try YuGiOhCatalogAdapter(catalog: initial).resolution(forPrintingID: p.id).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed), quantity: 2)
        let discovery = try YuGiOhFixture.catalog(complete: false, auto: false, editions: [], priced: [])
        let discoveryBound = try await CardGameRuntimeContainer(runtimes: [discovery.runtime]).bound(to: original)
        let row = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed)))
        row.quantity += 1
        XCTAssertThrowsError(try store.validatePendingGameWrites())
        original.mainContext.rollback()
        let csv = "game,provider_id,card_name,card_number,finish,quantity\nyu-gi-oh,\(p.idString),Fixture Card,RA02-EN037,yugioh1stEdition,3\n"
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let importers = await discoveryBound.currentImportAdapters()
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        do {
            let result = try await CollectionCSV.applyIsolated(plan, to: original, exclusiveToken: token,
                gameRegistry: discoveryBound.registry, gameImportAdapters: importers)
            CollectionWriteSerializer.endExclusive(token)
            XCTAssertEqual(result.importedQuantity, 0)
            XCTAssertFalse(result.failedRows.isEmpty)
        } catch {
            CollectionWriteSerializer.endExclusive(token)
            throw error
        }
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
        let failure = CollectionStore(context: original.mainContext, beforeSaveForTesting: { _ in
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertThrowsError(try failure.remove(row))
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<InventoryEvent>()).reduce(0) { $0 + $1.deltaQuantity }, 2)
        let snapshot = try store.remove(row)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        try store.restore(snapshot)
        XCTAssertThrowsError(try store.restore(snapshot))
        let reopened = try container(url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).reduce(0) { $0 + $1.deltaQuantity }, 2)
    }

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
    func testDurableEditionCorrectionAfterCoverageBecomesUnknownAtFinalSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-maintenance-\(UUID())")
        let url = root.appendingPathComponent("collection.store"), original = try container(url)
        let initial = try YuGiOhFixture.catalog(), adapter = YuGiOhCatalogAdapter(catalog: initial)
        _ = try await CardGameRuntimeContainer(runtimes: [initial.runtime]).bound(to: original)
        let p = try XCTUnwrap(initial.printingByID.values.first)
        let card = try adapter.resolution(forPrintingID: p.id).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed), quantity: 2)
        let activity = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectionActivity>()).first { $0.signedQuantity > 0 })
        try splitDurablePosition(in: original.mainContext)
        var updated = YuGiOhFixture.providerSupportedObject()
        updated["generation"] = "yugioh-en-maintenance"
        var retiredRows = updated["printings"] as! [[String: Any]]
        retiredRows[0]["e"] = ["yugiohUnlimited"]
        retiredRows[0]["m"] = (retiredRows[0]["m"] as! [[String: Any]]).filter { $0["e"] as? String == "yugiohUnlimited" }
        retiredRows.append((YuGiOhFixture.object(count: 2, auto: false)["printings"] as! [[String:Any]])[1])
        updated["printings"] = retiredRows
        let newer = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: updated))
        XCTAssertTrue(newer.autoEligibleCodes.isEmpty)
        let supportedBound = try await CardGameRuntimeContainer(runtimes: [newer.runtime]).bound(to: original)
        XCTAssertTrue(supportedBound.registry.supports(.yuGiOh, .collectionWrite))
        let row = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        let forged = CollectedCard(collectionKey: row.collectionKey, game: .yuGiOh,
            providerID: p.idString, name: row.name, setName: row.setName, setCode: row.setCode,
            cardNumber: row.cardNumber, rarity: row.rarity, imageURL: nil, thumbnailURL: nil,
            variant: .yugiohFirstEdition, variantResolution: .userConfirmed, quantity: 2)
        original.mainContext.insert(forged)
        XCTAssertThrowsError(try store.validatePendingGameWrites(), "An existing-looking inserted row has no durable maintenance authority")
        original.mainContext.rollback()
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .yugiohFirstEdition, resolution: .userConfirmed)))
        XCTAssertThrowsError(try store.setQuantity(3, forCollectionKey: row.collectionKey, expectedCurrent: 2))
        let plan = try CollectionCSV.parse(Data("game,provider_id,card_name,card_number,finish,quantity\nyu-gi-oh,\(p.idString),Fixture Card,RA02-EN037,yugioh1stEdition,1\n".utf8))
        let importers = await supportedBound.currentImportAdapters()
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        do {
            let result = try await CollectionCSV.applyIsolated(plan, to: original, exclusiveToken: token,
                gameRegistry: supportedBound.registry, gameImportAdapters: importers)
            CollectionWriteSerializer.endExclusive(token)
            XCTAssertEqual(result.importedQuantity, 0)
            XCTAssertFalse(result.failedRows.isEmpty)
        } catch {
            CollectionWriteSerializer.endExclusive(token)
            throw error
        }
        XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity).sorted(), [1, 1])
        XCTAssertThrowsError(try store.recordVariantCorrection(for: row, to: .init(variant: .yugiohLimited, resolution: .userConfirmed),
            activityID: activity.id, quantity: 2))
        let corrected = try store.recordVariantCorrection(forCollectionKey: row.collectionKey,
            to: .init(variant: .yugiohUnlimited, resolution: .userConfirmed), activityID: activity.id, quantity: 2)
        XCTAssertNotNil(corrected)
        let reopened = try container(url)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.quantity, 2)
        XCTAssertEqual(rows.first?.variantID, "yugiohUnlimited")
        let events = try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 3, "One acquisition and exactly two correction legs")
        XCTAssertEqual(events.reduce(0) { $0 + $1.deltaQuantity }, 2)
        XCTAssertEqual(events.filter { $0.collectionKey == card.collectionKey(variant: .yugiohFirstEdition) }.reduce(0) { $0 + $1.deltaQuantity }, 0)
        XCTAssertEqual(events.filter { $0.collectionKey == card.collectionKey(variant: .yugiohUnlimited) }.reduce(0) { $0 + $1.deltaQuantity }, 2)
        let history = try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(history.count, 2, "Retarget the acquisition and append one correction")
        XCTAssertEqual(history.filter { $0.kind == .corrected }.count, 1)
        let maintained = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        let removed = try store.remove(maintained)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        try store.restore(removed)
        let restored = try container(url)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<InventoryEvent>()).reduce(0) { $0 + $1.deltaQuantity }, 2)
    }
    func testScanPrintingEditionSaveRefreshCSVImportAndPersistenceChain() async throws {
        try await runChain(printedEdition: false)
    }
    func testObservedEditionScanThroughPersistenceChain() async throws {
        try await runChain(printedEdition: true)
    }
    func testRealOlderSeedScanChoiceOwnershipExportImportReopen() async throws {
        try await runChain(printedEdition: true, realProductID: 21792)
    }
    func testRealReissueSeedScanChoiceOwnershipExportImportReopen() async throws {
        try await runChain(printedEdition: false, realProductID: 476160)
    }
    func testRealMixedDiscoverySiblingScanChoiceOwnershipExportImportReopen() async throws {
        try await runChain(printedEdition: false, realProductID: 487277)
    }
    func testRealModernAlternateArtWorkflow() async throws {
        try await runChain(printedEdition: true, realProductID: 550852)
    }
    func testRealExceptionalCodeLimitedWorkflow() async throws {
        try await runChain(printedEdition: true, realProductID: 26366, printedVariant: .yugiohLimited)
    }
    func testRealEarlyEuropeanCodeWorkflow() async throws {
        try await runChain(printedEdition: true, realProductID: 229392)
    }
    private func runChain(printedEdition: Bool, realProductID: Int? = nil, printedVariant: PhysicalVariant = .yugiohFirstEdition) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("YGO-chain-\(UUID())")
        // SwiftData actors can outlive local containers; leave isolated stores
        // in the simulator's temporary directory rather than unlink open SQLite files.
        let catalog = try realProductID == nil ? YuGiOhFixture.catalog(count: 2) : YuGiOhCatalog.bundled.get()
        let targetPrinting = catalog.printingByID.values.first { $0.productID == realProductID }
        let source = YuGiOhTestPriceSource()
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
        let lines = [RecognizedLine(text: targetPrinting?.code ?? "RA02-EN037")] + (printedEdition ? [.init(text: printedVariant == .yugiohLimited ? "Limited Edition" : "1st Edition")] : [])
        guard case let .identified(subject) = recognizer.identify(lines) else { return XCTFail() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let pending = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(pending)
        XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let choice = try XCTUnwrap(model.pendingIdentityChoice?.printingCandidates.first { realProductID == nil || $0.id == targetPrinting?.idString })
        if let discovery = model.pendingIdentityChoice?.printingCandidates.first(where: { $0.acquisitionUnavailableReason != nil }) {
            model.choose(discovery)
            XCTAssertNotNil(model.pendingIdentityChoice)
            XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        }
        model.choose(choice)
        if !printedEdition {
            let editionPending = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(editionPending)
            XCTAssertTrue(try original.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            model.choose(.yugiohUnlimited)
        }
        let edition: PhysicalVariant = printedEdition ? printedVariant : .yugiohUnlimited
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        let row = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        let scanOrder = row.setReleaseOrder
        let browse = YuGiOhBrowseAdapter(catalog: catalog)
        let sets = try await browse.sets()
        let set = try XCTUnwrap(sets.first { realProductID == nil || $0.catalogID.providerID == "tcgplayer-group:\(targetPrinting!.set.groupID)" })
        let page = try await browse.cards(in: set, cursor: nil)
        var items = page.items, next = page.nextCursor
        while !items.contains(where: { $0.providerID == choice.id }), let cursor = next {
            let following = try await browse.cards(in: set, cursor: cursor)
            items += following.items; next = following.nextCursor
        }
        let summary = try XCTUnwrap(items.first { $0.providerID == choice.id })
        let details = try await browse.details(for: summary)
        XCTAssertEqual(scanOrder, set.releaseOrder, "Scan and Browse Add must share epoch-day order")
        XCTAssertEqual(details.card.setReleaseOrder, set.releaseOrder)
        XCTAssertEqual(scanOrder, realProductID == nil ? 19_867 : 0)
        let browseStore = try container(root.appendingPathComponent("browse.store"))
        _ = try await runtimes.bound(to: browseStore)
        _ = try CollectionStore(context: browseStore.mainContext).add(details.card,
            resolved: .init(variant: edition, resolution: .userConfirmed),
            identityResolution: .catalogSelected, setReleaseOrder: set.releaseOrder, matchCatalogAliases: true)
        let browseRow = try XCTUnwrap(browseStore.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(browseRow.setReleaseOrder, scanOrder)
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
        let targetRuntimes: CardGameRuntimeContainer
        if realProductID != nil {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed"))
            var updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String:Any])
            updated["generation"] = catalog.generation + "-import"
            var printings = updated["printings"] as! [[String:Any]]
            for index in printings.indices {
                printings[index]["pe"] = [String]()
                var evidence = printings[index]["m"] as? [[String:Any]] ?? []
                for lane in evidence.indices { evidence[lane]["q"] = NSNull() }
                printings[index]["m"] = evidence
            }
            updated["printings"] = printings
            let changed = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: updated))
            targetRuntimes = try CardGameRuntimeContainer(runtimes: [changed.runtime])
        } else { targetRuntimes = runtimes }
        let targetBound = try await targetRuntimes.bound(to: target)
        let plan = try CollectionCSV.parse(Data(csv.text.utf8))
        let adapters = await targetBound.currentImportAdapters()
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        let result: CollectionCSVImportResult
        do {
            result = try await CollectionCSV.applyIsolated(plan, to: target, exclusiveToken: token, gameRegistry: targetBound.registry, gameImportAdapters: adapters)
            CollectionWriteSerializer.endExclusive(token)
        } catch { CollectionWriteSerializer.endExclusive(token); throw error }
        XCTAssertEqual(result.importedQuantity, 1); XCTAssertTrue(result.failedRows.isEmpty)
        let imported = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(imported.setReleaseOrder, scanOrder, "Local import must restore sorting even when artwork is already present")
        // Settings runs this after local CSV insertion to restore catalog metadata.
        let normalizer = targetBound.makeCollectionNormalizer()
        await normalizer.normalizeImportedCards(in: target)
        let reopened = try container(targetURL), reloaded = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(reloaded.collectionKey, key); XCTAssertEqual(reloaded.catalogProviderID, choice.id)
        XCTAssertEqual(reloaded.variantID, edition.id)
        XCTAssertEqual(reloaded.setReleaseOrder, scanOrder, "CSV import must preserve the same set order")
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
        XCTAssertEqual(model.scanAcknowledgement?.phase, .failed)
        XCTAssertTrue(model.scanAcknowledgement?.message?.contains("Conflicting edition evidence") == true)
        XCTAssertTrue(model.scanAcknowledgement?.canRetryScan == true)
        XCTAssertEqual(model.activeScanIntervalCountForTesting, 0)
        XCTAssertTrue(try store.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(model.unresolvedScans.first?.subject.printedEdition.isConflict == true)
        if let row = model.unresolvedScans.first { model.resolveUnresolved(id: row.id, choice: .retryLookup) }
        let retried = await waitUntil { !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(retried)
        XCTAssertNotEqual(model.scanAcknowledgement?.phase, .recognized)
        XCTAssertEqual(model.activeScanIntervalCountForTesting, 0)
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
    func testPrintingFamilyProvenanceIsValidatedAndOldCatalogDefaultsUnavailable() throws {
        let source = try YuGiOhFixture.mp24Object()
        for attack in ["hash", "count", "scope", "art", "quarantine", "duplicate", "missing"] {
            var object = source
            var rows = object["printings"] as! [[String: Any]]
            var authority = rows[0]["pf"] as! [String: Any]
            switch attack {
            case "hash": authority["sha256"] = "invalid"
            case "count": authority["count"] = 0
            case "scope": rows[0]["c"] = "LOB-001"
            case "art": rows[0]["art"] = "Alternate Art"
            case "quarantine": rows[0]["ir"] = "conflictingIdentity"
            case "duplicate": var other = rows[0]; other["id"] = UUID().uuidString.lowercased(); other["p"] = 999999; rows.append(other)
            default: rows[0].removeValue(forKey: "pf")
            }
            if attack != "missing" { rows[0]["pf"] = authority }
            object["printings"] = rows
            XCTAssertThrowsError(try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object)), attack)
        }
        var old = source
        var rows = old["printings"] as! [[String: Any]]
        rows[0].removeValue(forKey: "pf"); old["printings"] = rows; old["autoEligibleCodes"] = []
        let decoded = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.autoEligibleCodes.isEmpty)
        XCTAssertNil(decoded.printingByID.values.first?.familyEvidence)
        XCTAssertFalse(try XCTUnwrap(decoded.printingByID.values.first).coverageVerified)
    }
    func testQuarantinedReviewedSingletonDoesNotPoisonSafeSiblingInActualLoader() throws {
        var object = YuGiOhFixture.object(count: 2, auto: false)
        var rows = object["printings"] as! [[String: Any]]
        rows[0]["ir"] = "invalidProductAssociation"
        object["printings"] = rows
        let catalog = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(catalog.printingByID.values.filter(\.explicitSelectionSupported).count, 1)
        object["printings"] = [rows[0]]
        object["autoEligibleCodes"] = ["RA02-EN037"]
        XCTAssertThrowsError(try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object)))
    }

    func testNullSubtypeObservationDoesNotContradictIndependentlyReviewedMembership() throws {
        let catalog = try YuGiOhFixture.catalog(editions: ["yugioh1stEdition"], priced: ["yugiohUnlimited"])
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        XCTAssertEqual(p.editions, [.first]); XCTAssertEqual(p.pricedEditions, [.unlimited])
        XCTAssertNoThrow(try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: p.id))
    }
    func testUnsupportedEditionCannotBeSmuggledIntoSupportedMembership() throws {
        var object = YuGiOhFixture.providerSupportedObject()
        var rows = object["printings"] as! [[String: Any]]
        rows[0]["e"] = ["yugioh1stEdition", "yugiohUnlimited", "yugiohLimited"]
        object["printings"] = rows
        XCTAssertThrowsError(try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object)))
    }
    func testFullSeedPartitionAndIndependentFactsThroughRealLoader() throws {
        let catalog = try YuGiOhCatalog.bundled.get()
        let rows = Array(catalog.printingByID.values)
        XCTAssertEqual(rows.count, 46_542)
        XCTAssertEqual(rows.filter(\.explicitSelectionSupported).count, 46_303)
        XCTAssertEqual(rows.filter { !$0.explicitSelectionSupported }.count, 239)
        XCTAssertEqual(catalog.autoEligibleCodes.count, 260)
        XCTAssertTrue(catalog.autoEligibleCodes.contains("MP24-EN372"))
        XCTAssertTrue(rows.allSatisfy { !$0.coverageVerified })
        XCTAssertEqual(rows.reduce(0) { $0 + $1.membership.count }, 59_965)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.membership.filter { $0.q != nil }.count }, 58_264)
        XCTAssertEqual(rows.flatMap(\.membership).filter { $0.t == "providerListing" }.count, 1_701)
        XCTAssertTrue(catalog.printingByID.values.contains { $0.code == "IOC-SE1" && $0.editions == [.limited] })
        let blueEyes = rows.filter { [476160,486054].contains($0.productID) }
        XCTAssertEqual(Set(blueEyes.map(\.id)).count, 2)
        XCTAssertEqual(Set(blueEyes.map { $0.set.groupID }).count, 2)
        for p in rows {
            XCTAssertTrue(p.card.passcodes.allSatisfy { $0 > 0 && $0 <= 99_999_999 })
        }
    }
    func testFourSetPricingSamplePreservesExactProductsEditionsAndSourceDates() async throws {
        let catalog = try YuGiOhCatalog.bundled.get()
        let adapter = YuGiOhPriceAdapter(catalog: catalog)
        XCTAssertFalse(YuGiOhGameRuntime.capabilities(for: catalog).contains(.gradedPricing))
        var groups = Set<Int>()
        for code in ["LOB-001", "PSV-000", "RA02-EN037", "MP24-EN001"] {
            let printing = try XCTUnwrap(catalog.printingsByCode[code]?.filter {
                $0.explicitSelectionSupported && $0.membership.contains { $0.q != nil }
            }.sorted { $0.idString < $1.idString }.first)
            let membership = try XCTUnwrap(printing.membership.first { $0.q != nil })
            groups.insert(printing.set.groupID)
            guard case let .price(price) = try await adapter.refreshStoredPrinting(printing.idString,
                variant: membership.e.variant) else { return XCTFail("Missing snapshot quote for \(code)") }
            XCTAssertEqual(price.sourceVariantID, "tcgplayer:\(printing.productID):\(membership.e.tcgplayerSubtype)", code)
            XCTAssertEqual(price.unitMarketPriceUSD, membership.q, code)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = try XCTUnwrap(membership.s.flatMap { ISO8601DateFormatter().date(from: $0) ?? formatter.date(from: $0) })
            XCTAssertEqual(price.fetchedAt, date, code)
            let card = try YuGiOhCatalogAdapter(catalog: catalog).resolutionForExistingHolding(printing.id).card
            do {
                _ = try await adapter.refresh(.init(identity: .init(game: .yuGiOh, printingID: card.providerID,
                    setID: "different-set", displaySetCode: card.setCode, cardNumber: card.cardNumber,
                    language: card.language), variant: membership.e.variant, pokemonPrintRun: nil, catalogRefreshOverride: nil))
                XCTFail("Wrong set must not borrow \(code)'s product")
            } catch PriceQuoteError.identityMismatch {}
        }
        XCTAssertEqual(groups.count, 4)
    }

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
    func testAppDefaultsEnablesSupportedCatalog() {
        let defaults = CardGameRuntimeContainer.appDefaults()
        let registry = defaults.registry
        for capability: CardGameCapabilities in [.scan, .browse, .pricing, .collectionWrite] {
            XCTAssertTrue(registry.supports(.yuGiOh, capability))
        }
        XCTAssertFalse(defaults.unavailableGames.contains { $0.game == .yuGiOh })
    }
    func testCodeMatcherAgreesWithOriginalPatternForBundledAndEdgeCodes() throws {
        func original(_ code: String) -> Bool {
            if ["IOC-SE1", "IOC-SE2", "IOC-SE3", "IOC-SE4"].contains(code) { return true }
            return code.range(of: "^[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})$", options: .regularExpression) != nil
        }
        let url = try XCTUnwrap(YuGiOhBundledLaunch.seedURL())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let codes = try XCTUnwrap(object["printings"] as? [[String: Any]]).compactMap { $0["c"] as? String }
        XCTAssertFalse(codes.isEmpty)
        let edges = ["", "-", "A-001", "AB-001", "ABCD-001", "ABCDE-001", "AB-00", "AB-0001", "AB-E00", "AB-EN00",
                     "AB-EX001", "AB-ENE01", "AB-E0A1", "ab-001", "AB_001", "AB-001-", "AB--001", "ÄB-001",
                     "AB-\u{0661}\u{0662}\u{0663}", "IOC-SE5", "IOC-SE1"]
        for code in codes + edges {
            XCTAssertEqual(YuGiOhCatalog.validCode(code), original(code), code)
        }
    }
    func testBundledLaunchCacheRegistersWithoutDecodingAndMatchesEagerRuntime() async throws {
        let suite = "YuGiOhBundledLaunchTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(YuGiOhBundledLaunch.cachedManifest(defaults: defaults))
        // A miss takes the eager, validated path and records this build's facts.
        let eager = try YuGiOhBundledLaunch.runtime(defaults: defaults)
        let manifest = try XCTUnwrap(YuGiOhBundledLaunch.cachedManifest(defaults: defaults))
        let bundled = try YuGiOhCatalog.bundled.get()
        XCTAssertTrue(YuGiOhCatalog.bundledHandle.isLoaded, "bundled and bundledHandle share one decoded copy")
        XCTAssertEqual(manifest.generation, bundled.generation)
        XCTAssertEqual(CardGameCapabilities(rawValue: manifest.capabilities), eager.descriptor.capabilities)

        let lazy = YuGiOhCatalog(knownGeneration: manifest.generation) { try YuGiOhBundledLaunch.loadSeed() }
        let runtime = YuGiOhGameRuntime(catalog: lazy,
            knownCapabilities: CardGameCapabilities(rawValue: manifest.capabilities)).runtime
        XCTAssertEqual(runtime.descriptor.capabilities, eager.descriptor.capabilities)
        XCTAssertEqual(runtime.catalog?.generation, bundled.generation)
        XCTAssertEqual(runtime.browse?.generation, bundled.generation)
        XCTAssertNotNil(runtime.priceAuthority)
        XCTAssertFalse(lazy.isLoaded, "Registering a cached catalog must not decode it")

        let sets = try await XCTUnwrap(runtime.browse).sets()
        XCTAssertTrue(lazy.isLoaded)
        XCTAssertEqual(sets.count, Set(bundled.printingByID.values.map(\.set.groupID)).count)
        let copy = lazy
        XCTAssertEqual(copy.printingByID.count, bundled.printingByID.count)
        XCTAssertEqual(runtime.priceAuthority?.identityByPriceKey,
                       YuGiOhPriceAdapter.priceAuthority(bundled).identityByPriceKey)
    }
    func testBundledLaunchCacheMissesForAnotherBuildAndClears() throws {
        let suite = "YuGiOhBundledLaunchTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let other = YuGiOhBundledLaunch.Manifest(buildKey: "another-build", generation: "yugioh-en-other",
                                                 capabilities: CardGameCapabilities.browse.rawValue)
        defaults.set(try JSONEncoder().encode(other), forKey: YuGiOhBundledLaunch.defaultsKey)
        XCTAssertNil(YuGiOhBundledLaunch.cachedManifest(defaults: defaults))
        YuGiOhBundledLaunch.store(generation: "yugioh-en-current", capabilities: [.browse], defaults: defaults)
        XCTAssertEqual(YuGiOhBundledLaunch.cachedManifest(defaults: defaults)?.generation, "yugioh-en-current")
        YuGiOhBundledLaunch.clear(defaults: defaults)
        XCTAssertNil(YuGiOhBundledLaunch.cachedManifest(defaults: defaults))
        YuGiOhBundledLaunch.store(generation: "yugioh-en-current", capabilities: [], defaults: defaults)
        XCTAssertNil(YuGiOhBundledLaunch.cachedManifest(defaults: defaults), "An unusable catalog is never cached")
    }
    func testFailedDeferredLoadFailsClosed() {
        let failing = YuGiOhCatalog(knownGeneration: "yugioh-en-cached") { throw YuGiOhCatalog.LoadError.invalidSchema }
        XCTAssertEqual(failing.generation, "yugioh-en-cached")
        XCTAssertTrue(failing.printingByID.isEmpty)
        XCTAssertTrue(failing.printingsByCode.isEmpty)
        XCTAssertThrowsError(try failing.loaded())
        XCTAssertThrowsError(try YuGiOhCatalogAdapter(catalog: failing).resolution(forPrintingID: UUID()))
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
    func testLowConfidencePositiveEditionRequiresAnAnswer() throws {
        let adapter = YuGiOhRecognitionAdapter(catalog: try YuGiOhFixture.catalog())
        for confidence in [Float(0.2), .nan, .infinity] {
            guard case let .identified(subject) = adapter.identify([.init(text: "RA02-EN037"),
                .init(text: "1st Edition", confidence: confidence)]) else { return XCTFail() }
            XCTAssertEqual(subject.printedEdition, .unreadable)
        }
        guard case let .identified(subject) = adapter.identify([.init(text: "RA02-EN037"),
            .init(text: "1st Edition", confidence: 0.99)]) else { return XCTFail() }
        XCTAssertEqual(subject.printedEdition, .observed(.yugiohFirstEdition))
    }
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

@MainActor
final class YuGiOhResolutionTests: XCTestCase {
    func testGameWideEditionPolicyIsIndependentOfReleaseAndRarity() async throws {
        let catalog = try YuGiOhCatalog.bundled.get(), adapter = YuGiOhCatalogAdapter(catalog: catalog)
        for code in ["MP24-EN372", "DUNE-EN051", "PSV-001"] {
            let p = try XCTUnwrap(catalog.printingsByCode[code]?.first)
            let identifier = try YuGiOhRecognitionAdapter.identifier(code: code, generation: catalog.generation)
            guard case let .resolved(resolution) = try await adapter.lookup(identifier) else { return XCTFail(code) }
            let evidence = resolution.card.variantEvidence
            XCTAssertFalse(evidence.physicalCoverageVerified)
            XCTAssertEqual(VariantResolver.resolveAcquisition(evidence, printedEdition: .observed(.yugiohFirstEdition)),
                .resolved(.init(variant: .yugiohFirstEdition, resolution: .printedLabel)), code)
            guard case .needsChoice = VariantResolver.resolveAcquisition(evidence, printedEdition: .absent) else { return XCTFail(code) }
            try await adapter.validateAcquisition(identifier, printingID: p.idString, automatic: true)
        }
        for edition in YuGiOhEdition.allCases {
            let evidence = VariantEvidence(game: .yuGiOh, setID: "any-release", cardNumber: "any-code",
                catalogVariants: [edition.variant], physicalCoverageVerified: false, explicitMembershipSupported: true)
            XCTAssertEqual(VariantResolver.resolveAcquisition(evidence, printedEdition: .observed(edition.variant)),
                .resolved(.init(variant: edition.variant, resolution: .printedLabel)))
            XCTAssertEqual(VariantResolver.resolveAcquisition(evidence, printedEdition: .absent),
                .needsChoice(options: [edition.variant], lockDidNotApply: nil))
        }
    }
    func testMP24SaveRevalidatesActualEvidenceAndCurrentFamilyAuthority() async throws {
        let catalog = try YuGiOhCatalog.bundled.get(), adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let p = try XCTUnwrap(catalog.printingsByCode["MP24-EN372"]?.first)
        let identifier = try YuGiOhRecognitionAdapter.identifier(code: p.code, generation: catalog.generation)
        let card = try adapter.resolution(forPrintingID: p.id).card
        func candidate(_ evidence: PrintedEditionEvidence, _ resolution: VariantResolution = .printedLabel,
                       _ variant: PhysicalVariant = .yugiohFirstEdition) -> CollectionCommitCandidate {
            .init(resolvedScan: .init(request: .init(subject: .init(identifier: identifier, printedEdition: evidence),
                purpose: .collection, generation: 0), card: card,
                resolved: .init(variant: variant, resolution: resolution), pokemonPrintRun: nil,
                options: card.variantEvidence.catalogVariants))
        }
        let positive = candidate(.observed(.yugiohFirstEdition))
        XCTAssertNoThrow(try adapter.validateAcquisition(positive))
        XCTAssertNoThrow(try adapter.validateAcquisition(candidate(.absent, .userConfirmed)))
        for bad in [candidate(.absent), candidate(.unreadable), candidate(.observed(.yugiohLimited)),
                    candidate(.merged([.observed(.yugiohLimited), .observed(.yugiohFirstEdition)])),
                    candidate(.observed(.yugiohFirstEdition), .finishLock)] {
            XCTAssertThrowsError(try adapter.validateAcquisition(bad))
        }
        let withdrawn = try replacementOfMP24()
        XCTAssertThrowsError(try YuGiOhCatalogAdapter(catalog: withdrawn).validateAcquisition(positive))
        let canceled = Task { try adapter.validateAcquisition(positive) }
        canceled.cancel()
        do { try await canceled.value; XCTFail("Cancellation must reject acquisition") } catch is CancellationError {}
    }

    private func replacementOfMP24() throws -> YuGiOhCatalog {
        // A generation replacement retains the UUID but cannot inherit the old
        // scan's authority, even if the exact edition remains supported.
        var object = try YuGiOhFixture.mp24Object()
        object["generation"] = "yugioh-en-replaced-family"
        object["autoEligibleCodes"] = []
        var rows = object["printings"] as! [[String: Any]]
        for i in rows.indices { rows[i].removeValue(forKey: "pf") }
        object["printings"] = rows
        return try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
    }
    func testRealDCRFamilyKeepsUnsupportedDiscoveryDisabled() async throws {
        let catalog = try YuGiOhCatalog.bundled.get(), adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let identifier = try YuGiOhRecognitionAdapter.identifier(code: "DCR-EN000", generation: catalog.generation)
        guard case let .needsPrintingChoice(_, candidates) = try await adapter.lookup(identifier) else { return XCTFail() }
        let unsupported = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 476802 })
        let supported = try XCTUnwrap(catalog.printingByID.values.first { $0.productID == 487277 })
        XCTAssertNotNil(candidates.first { $0.id == unsupported.idString }?.acquisitionUnavailableReason)
        XCTAssertNil(candidates.first { $0.id == supported.idString }?.acquisitionUnavailableReason)
        do { _ = try await adapter.resolve(adapter.candidate(unsupported), for: identifier); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
        _ = try await adapter.resolve(adapter.candidate(supported), for: identifier)
    }

    func testProviderSupportedNonExhaustiveSelectionRequiresExplicitEdition() async throws {
        let catalog = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: YuGiOhFixture.providerSupportedObject()))
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        let identifier = try YuGiOhFixture.identifier(catalog)
        guard case .needsPrintingChoice = try await adapter.lookup(identifier) else { return XCTFail() }
        let card = try adapter.resolution(forPrintingID: p.id).card
        XCTAssertFalse(card.variantEvidence.physicalCoverageVerified)
        XCTAssertTrue(card.variantEvidence.explicitMembershipSupported)
        guard case let .needsChoice(options, _) = VariantResolver.gate(card.variantEvidence, printedEdition: .absent) else { return XCTFail() }
        XCTAssertEqual(Set(options), [.yugiohFirstEdition, .yugiohUnlimited])
        guard case .needsChoice = VariantResolver.resolve(card.variantEvidence, finishLock: .yugiohUnlimited) else { return XCTFail() }
        XCTAssertEqual(VariantResolver.gate(card.variantEvidence, printedEdition: .observed(.yugiohFirstEdition)),
            .resolved(.init(variant: .yugiohFirstEdition, resolution: .printedLabel)))
        try await adapter.validateAcquisition(identifier, printingID: p.idString, automatic: false)
        do { try await adapter.validateAcquisition(identifier, printingID: p.idString, automatic: true); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
    }
    func testIncompleteCoverageAllowsExactSelectionButNeverForgedChoice() async throws {
        var object = YuGiOhFixture.object(auto: false)
        object["incompleteCodes"] = ["RA02-EN037"]
        let catalog = try YuGiOhCatalog(data: JSONSerialization.data(withJSONObject: object))
        let adapter = YuGiOhCatalogAdapter(catalog: catalog), identifier = try YuGiOhFixture.identifier(catalog)
        let p = try XCTUnwrap(catalog.printingByID.values.first)
        guard case .needsPrintingChoice = try await adapter.lookup(identifier) else { return XCTFail() }
        try await adapter.validateAcquisition(identifier, printingID: p.idString, automatic: false)
        do { try await adapter.validateAcquisition(identifier, printingID: p.idString, automatic: true); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
        XCTAssertNoThrow(try adapter.resolution(forPrintingID: p.id))
        XCTAssertNoThrow(try adapter.identifierForCatalogSelection(printingID: p.idString, original: identifier))
        _ = try await adapter.resolve(adapter.candidate(p), for: identifier)
        let browseSets = try await YuGiOhBrowseAdapter(catalog: catalog).sets()
        XCTAssertFalse(browseSets.isEmpty)
        let csv = "game,provider_id,card_name,card_number,finish,quantity\nyu-gi-oh,\(p.idString),Fixture Card,RA02-EN037,yugioh1stEdition,1\n"
        let entry = try XCTUnwrap(CollectionCSV.parse(Data(csv.utf8)).entries.first)
        XCTAssertNoThrow(try YuGiOhImportAdapter(catalog: catalog).validate(entry))
        XCTAssertNoThrow(try YuGiOhImportAdapter(catalog: catalog).localMetadata(for: entry))
        XCTAssertNoThrow(try adapter.validateCollectionMutation(printingID: p.idString, catalogProviderID: p.idString,
            variantID: "yugioh1stEdition", itemKindRaw: CollectionItemKind.rawCard.rawValue,
            collectionKey: "yu-gi-oh:\(p.idString)#yugioh1stEdition"))
        XCTAssertNoThrow(try adapter.validateVariantCorrection(printingID: p.idString, variantID: "yugiohUnlimited"))
        XCTAssertNoThrow(try adapter.resolutionForExistingHolding(p.id))
        let forged = PhysicalPrintingCandidate(id: p.idString, game: .yuGiOh, canonicalCardID: p.card.id.uuidString.lowercased(),
            language: "en", catalogGeneration: catalog.generation, name: "forged", printedIdentifier: p.code)
        do { _ = try await adapter.resolve(forged, for: identifier); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
    }
    func testDiscoveryCatalogRetainsMaintenanceAdapters() throws {
        for catalog in [try YuGiOhFixture.catalog(complete: false), try YuGiOhCatalog.bundled.get()] {
            let runtime = catalog.runtime
            XCTAssertTrue(runtime.descriptor.capabilities.contains(.browse))
            XCTAssertNotNil(runtime.recognizer); XCTAssertNotNil(runtime.catalog); XCTAssertNotNil(runtime.browse)
            XCTAssertNotNil(runtime.importer); XCTAssertNotNil(runtime.pricing); XCTAssertNotNil(runtime.priceAuthority)
        }
        let discoveryOnly = try YuGiOhFixture.catalog(complete: false).runtime
        XCTAssertEqual(discoveryOnly.descriptor.capabilities, [.browse])
        XCTAssertTrue(try YuGiOhFixture.catalog().runtime.descriptor.capabilities.contains(.collectionWrite))
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
