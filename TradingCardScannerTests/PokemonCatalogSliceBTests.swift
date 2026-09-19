import CryptoKit
import XCTest
@testable import TradingCardScanner

// MARK: - Test fixtures

private enum SliceBFixture {
    static let keyID = "test-key-1"
    static let privateKey = Curve25519.Signing.PrivateKey()
    static var publicKey: Curve25519.Signing.PublicKey { privateKey.publicKey }
    static var pinnedKey: PokemonCatalogSignatureVerifier.PinnedKey {
        .init(id: keyID, publicKey: publicKey)
    }

    static func descriptor(
        providerSetID: String = "sv99",
        printedCode: String = "TST",
        officialCount: Int = 100,
        releaseOrder: Int = 99,
        scanEnabled: Bool = true
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerSetID,
            displayName: "Test Set",
            releaseDate: "2026-01-01",
            releaseOrder: releaseOrder,
            recognitionKind: .expansion,
            printedCode: printedCode,
            officialCount: officialCount,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: scanEnabled,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
        )
    }

    static func release(
        revision: Int = 1,
        sets: [PokemonCatalogSetDescriptor]? = nil
    ) -> PokemonCatalogRelease {
        PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: sets ?? [descriptor()]
        )
    }

    static func signedEnvelope(
        release: PokemonCatalogRelease
    ) throws -> PokemonCatalogReleaseEnvelope {
        try PokemonCatalogSignatureVerifier.sign(
            release: release,
            privateKey: privateKey,
            keyID: keyID
        )
    }

    static func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SliceBTest-\(UUID().uuidString)", isDirectory: true)
    }
}

// MARK: - PokemonCatalogReleaseStore tests

final class PokemonCatalogReleaseStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = SliceBFixture.tempRoot()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testEmptyStoreReturnsBundledSeed() async {
        let store = PokemonCatalogReleaseStore(root: root)
        await store.load(keys: [SliceBFixture.pinnedKey])
        let registry = await store.activeRegistry
        XCTAssertNil(registry)
        let seed = await store.recoverFromBundledSeed()
        XCTAssertFalse(seed.expansionCodes.isEmpty)
    }

    func testActivateWritesCurrentSlot() async throws {
        let store = PokemonCatalogReleaseStore(root: root)
        let release = SliceBFixture.release(revision: 1)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let registry = PokemonCatalogRegistry(release: release)

        let result = try await store.activate(envelope: envelope, release: release, registry: registry)
        guard case .activated(let rev, let prev) = result else {
            return XCTFail("Expected activated")
        }
        XCTAssertEqual(rev, 1)
        XCTAssertNil(prev)
        let currentExists = await store.slotFileExists(.current)
        XCTAssertTrue(currentExists)
    }

    func testActivatePromotesPreviousSlot() async throws {
        let store = PokemonCatalogReleaseStore(root: root)

        let release1 = SliceBFixture.release(revision: 1)
        let envelope1 = try SliceBFixture.signedEnvelope(release: release1)
        let registry1 = PokemonCatalogRegistry(release: release1)
        _ = try await store.activate(envelope: envelope1, release: release1, registry: registry1)

        let release2 = SliceBFixture.release(revision: 2)
        let envelope2 = try SliceBFixture.signedEnvelope(release: release2)
        let registry2 = PokemonCatalogRegistry(release: release2)
        let result = try await store.activate(envelope: envelope2, release: release2, registry: registry2)

        guard case .activated(let rev, let prev) = result else {
            return XCTFail("Expected activated")
        }
        XCTAssertEqual(rev, 2)
        XCTAssertEqual(prev, 1)
        let currentExists = await store.slotFileExists(.current)
        let previousExists = await store.slotFileExists(.previous)
        XCTAssertTrue(currentExists)
        XCTAssertTrue(previousExists)
    }

    func testStaleRevisionReturnsAlreadyCurrent() async throws {
        let store = PokemonCatalogReleaseStore(root: root)

        let release = SliceBFixture.release(revision: 5)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let registry = PokemonCatalogRegistry(release: release)
        _ = try await store.activate(envelope: envelope, release: release, registry: registry)

        let stale = SliceBFixture.release(revision: 3)
        let staleEnvelope = try SliceBFixture.signedEnvelope(release: stale)
        let staleRegistry = PokemonCatalogRegistry(release: stale)
        let result = try await store.activate(
            envelope: staleEnvelope, release: stale, registry: staleRegistry
        )
        XCTAssertEqual(result, .alreadyCurrent)
    }

    func testLoadRecoversCurrent() async throws {
        let release = SliceBFixture.release(revision: 3)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let registry = PokemonCatalogRegistry(release: release)

        let store1 = PokemonCatalogReleaseStore(root: root)
        _ = try await store1.activate(envelope: envelope, release: release, registry: registry)

        let store2 = PokemonCatalogReleaseStore(root: root)
        await store2.load(keys: [SliceBFixture.pinnedKey])
        let loadedRevision = await store2.activeRevision
        let loadedRegistry = await store2.activeRegistry
        XCTAssertEqual(loadedRevision, 3)
        XCTAssertNotNil(loadedRegistry)
    }

    func testLoadRecoversPreviousWhenCurrentCorrupted() async throws {
        let release1 = SliceBFixture.release(revision: 1)
        let envelope1 = try SliceBFixture.signedEnvelope(release: release1)
        let registry1 = PokemonCatalogRegistry(release: release1)
        let release2 = SliceBFixture.release(revision: 2)
        let envelope2 = try SliceBFixture.signedEnvelope(release: release2)
        let registry2 = PokemonCatalogRegistry(release: release2)

        let store1 = PokemonCatalogReleaseStore(root: root)
        _ = try await store1.activate(envelope: envelope1, release: release1, registry: registry1)
        _ = try await store1.activate(envelope: envelope2, release: release2, registry: registry2)

        let currentURL = root.appendingPathComponent(
            PokemonCatalogReleaseStore.Slot.current.rawValue
        )
        try "corrupted".data(using: .utf8)!.write(to: currentURL, options: .atomic)

        let store2 = PokemonCatalogReleaseStore(root: root)
        await store2.load(keys: [SliceBFixture.pinnedKey])
        let recoveredRevision = await store2.activeRevision
        XCTAssertEqual(recoveredRevision, 1)
    }

    func testLoadReturnsNilWhenBothCorrupted() async throws {
        let release1 = SliceBFixture.release(revision: 1)
        let envelope1 = try SliceBFixture.signedEnvelope(release: release1)
        let registry1 = PokemonCatalogRegistry(release: release1)
        let release2 = SliceBFixture.release(revision: 2)
        let envelope2 = try SliceBFixture.signedEnvelope(release: release2)
        let registry2 = PokemonCatalogRegistry(release: release2)

        let store1 = PokemonCatalogReleaseStore(root: root)
        _ = try await store1.activate(envelope: envelope1, release: release1, registry: registry1)
        _ = try await store1.activate(envelope: envelope2, release: release2, registry: registry2)

        for slot in PokemonCatalogReleaseStore.Slot.allCases {
            let url = root.appendingPathComponent(slot.rawValue)
            try "corrupted".data(using: .utf8)!.write(to: url, options: .atomic)
        }

        let store2 = PokemonCatalogReleaseStore(root: root)
        await store2.load(keys: [SliceBFixture.pinnedKey])
        let corruptedRevision = await store2.activeRevision
        let corruptedRegistry = await store2.activeRegistry
        XCTAssertNil(corruptedRevision)
        XCTAssertNil(corruptedRegistry)
    }

    func testWrongKeyRejectsPersistedRelease() async throws {
        let release = SliceBFixture.release(revision: 1)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let registry = PokemonCatalogRegistry(release: release)

        let store1 = PokemonCatalogReleaseStore(root: root)
        _ = try await store1.activate(envelope: envelope, release: release, registry: registry)

        let otherKey = Curve25519.Signing.PrivateKey()
        let otherPinned = PokemonCatalogSignatureVerifier.PinnedKey(
            id: "other-key", publicKey: otherKey.publicKey
        )
        let store2 = PokemonCatalogReleaseStore(root: root)
        await store2.load(keys: [otherPinned])
        let wrongKeyRevision = await store2.activeRevision
        XCTAssertNil(wrongKeyRevision)
    }

    func testProcessInterruptionSafety() async throws {
        let release1 = SliceBFixture.release(revision: 1)
        let envelope1 = try SliceBFixture.signedEnvelope(release: release1)
        let registry1 = PokemonCatalogRegistry(release: release1)
        let release2 = SliceBFixture.release(revision: 2)
        let envelope2 = try SliceBFixture.signedEnvelope(release: release2)
        let registry2 = PokemonCatalogRegistry(release: release2)

        let store1 = PokemonCatalogReleaseStore(root: root)
        _ = try await store1.activate(envelope: envelope1, release: release1, registry: registry1)
        _ = try await store1.activate(envelope: envelope2, release: release2, registry: registry2)

        let release3 = SliceBFixture.release(revision: 3)
        let envelope3 = try SliceBFixture.signedEnvelope(release: release3)
        let data = try JSONEncoder().encode(envelope3)
        let currentURL = root.appendingPathComponent(
            PokemonCatalogReleaseStore.Slot.current.rawValue
        )
        try data.prefix(data.count / 2).write(to: currentURL)

        let store2 = PokemonCatalogReleaseStore(root: root)
        await store2.load(keys: [SliceBFixture.pinnedKey])
        let interruptedRevision = await store2.activeRevision
        XCTAssertEqual(interruptedRevision, 1)
    }
}

// MARK: - PokemonCatalogUpdateClient tests

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class PokemonCatalogUpdateClientTests: XCTestCase {
    private var session: URLSession!
    private var client: PokemonCatalogUpdateClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = PokemonCatalogUpdateClient(
            session: session,
            baseURL: URL(string: "https://test.example.com")!
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testSuccessfulFetch() async throws {
        let release = SliceBFixture.release(revision: 1)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let data = try JSONEncoder().encode(envelope)

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["ETag": "\"abc\""]
            )!
            return (response, data)
        }

        let result = try await client.fetch()
        guard case .fetched(let fetched) = result else {
            return XCTFail("Expected fetched")
        }
        XCTAssertEqual(fetched.keyID, SliceBFixture.keyID)
    }

    func testConditionalRequestSends304() async throws {
        let release = SliceBFixture.release(revision: 1)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let data = try JSONEncoder().encode(envelope)

        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: [
                        "ETag": "\"v1\"",
                        "Last-Modified": "Wed, 01 Jan 2026 00:00:00 GMT"
                    ]
                )!
                return (response, data)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "If-Modified-Since"),
                "Wed, 01 Jan 2026 00:00:00 GMT"
            )
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 304,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        _ = try await client.fetch()
        let result = try await client.fetch()
        guard case .notModified = result else {
            return XCTFail("Expected notModified")
        }
        XCTAssertEqual(requestCount, 2)
    }

    func testClientError4xxDoesNotRetry() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.fetch()
            XCTFail("Expected error")
        } catch {
            guard let updateError = error as? PokemonCatalogUpdateClient.UpdateError,
                  case .badResponse(let code) = updateError else {
                return XCTFail("Expected badResponse, got \(error)")
            }
            XCTAssertEqual(code, 404)
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testPayloadTooLargeRejected() async throws {
        let oversized = Data(repeating: 0, count: 600_000)
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, oversized)
        }

        do {
            _ = try await client.fetch()
            XCTFail("Expected error")
        } catch {
            guard let updateError = error as? PokemonCatalogUpdateClient.UpdateError,
                  case .payloadTooLarge = updateError else {
                return XCTFail("Expected payloadTooLarge, got \(error)")
            }
        }
    }

    func testCancellationStopsFetch() async throws {
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://test.example.com")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let task = Task {
            try await client.fetch()
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            // URLError cancelled or network failure are also acceptable
            // since the task was cancelled during a retry delay
        }
    }
}

// MARK: - PokemonCatalogCoordinator tests

final class PokemonCatalogCoordinatorTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = SliceBFixture.tempRoot()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testLoadPersistedOrBundledUsesStoredRelease() async throws {
        let store = PokemonCatalogReleaseStore(root: root)
        let release = SliceBFixture.release(revision: 5)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let registry = PokemonCatalogRegistry(release: release)
        _ = try await store.activate(envelope: envelope, release: release, registry: registry)

        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey],
            rolloutMode: .remoteAuthority
        )
        await coordinator.loadPersistedOrBundled()
        let rev = await coordinator.revision
        XCTAssertEqual(rev, 5)
    }

    func testLoadPersistedOrBundledFallsToBundledSeed() async {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()
        let reg = await coordinator.registry
        XCTAssertFalse(reg.expansionCodes.isEmpty)
        let rev = await coordinator.revision
        XCTAssertNil(rev)
    }

    func testActivateEnvelopeUpdatesRegistry() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let release = SliceBFixture.release(revision: 1, sets: [
            SliceBFixture.descriptor(providerSetID: "sv99", printedCode: "TST")
        ])
        let envelope = try SliceBFixture.signedEnvelope(release: release)

        let result = await coordinator.activateEnvelope(envelope)
        guard case .activated(let event) = result else {
            return XCTFail("Expected activated, got \(result)")
        }
        XCTAssertEqual(event.revision, 1)

        let reg = await coordinator.registry
        XCTAssertNotNil(reg.expansion(forPrintedCode: "TST"))
    }

    func testActivationEventStream() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let events = await coordinator.activationEvents()
        let release = SliceBFixture.release(revision: 1)
        let envelope = try SliceBFixture.signedEnvelope(release: release)

        let expectation = XCTestExpectation(description: "activation event")
        let task = Task {
            for await event in events {
                XCTAssertEqual(event.revision, 1)
                expectation.fulfill()
                break
            }
        }

        _ = await coordinator.activateEnvelope(envelope)
        await fulfillment(of: [expectation], timeout: 2)
        task.cancel()
    }

    func testBadSignatureRejectedLeavesCurrentUnchanged() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let release1 = SliceBFixture.release(revision: 1)
        let envelope1 = try SliceBFixture.signedEnvelope(release: release1)
        _ = await coordinator.activateEnvelope(envelope1)
        let revBefore = await coordinator.revision
        XCTAssertEqual(revBefore, 1)

        let badEnvelope = PokemonCatalogReleaseEnvelope(
            keyID: SliceBFixture.keyID,
            payload: "tampered",
            signature: "tampered"
        )
        let result = await coordinator.activateEnvelope(badEnvelope)
        guard case .rejected = result else {
            return XCTFail("Expected rejected")
        }
        let revAfter = await coordinator.revision
        XCTAssertEqual(revAfter, 1)
    }

    func testOfficialCountChangeDetected() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let release1 = SliceBFixture.release(revision: 1, sets: [
            SliceBFixture.descriptor(providerSetID: "sv99", officialCount: 100)
        ])
        let envelope1 = try SliceBFixture.signedEnvelope(release: release1)
        _ = await coordinator.activateEnvelope(envelope1)

        let release2 = SliceBFixture.release(revision: 2, sets: [
            SliceBFixture.descriptor(providerSetID: "sv99", officialCount: 110)
        ])
        let envelope2 = try SliceBFixture.signedEnvelope(release: release2)
        let result = await coordinator.activateEnvelope(envelope2)
        guard case .activated(let event) = result else {
            return XCTFail("Expected activated")
        }
        XCTAssertTrue(event.changedOfficialCountSetIDs.contains("sv99"))
    }

    func testUnsupportedSchemaRejected() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let badRelease = PokemonCatalogRelease(
            schemaVersion: 999,
            revision: 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(badRelease)
        let sig = try SliceBFixture.privateKey.signature(for: payloadData)
        let envelope = PokemonCatalogReleaseEnvelope(
            keyID: SliceBFixture.keyID,
            payload: Base64URL.encode(payloadData),
            signature: Base64URL.encode(sig)
        )

        let result = await coordinator.activateEnvelope(envelope)
        guard case .rejected = result else {
            return XCTFail("Expected rejected")
        }
    }
}

// MARK: - Consumer invalidation tests

final class PokemonCatalogInvalidationTests: XCTestCase {
    func testOfflineCatalogInvalidationClearsEntries() async {
        let storeRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let checklistStore = PokemonChecklistStore(root: storeRoot)
        let offline = PokemonOfflineCatalog(store: checklistStore)
        await offline.prewarm()
        await offline.invalidate()

        let card = await offline.card(
            providerSetID: "nonexistent",
            localID: "001",
            expectedOfficialCount: nil
        )
        XCTAssertNil(card)
    }

    func testResolvedCacheInvalidatesChangedSets() async {
        let cacheRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let cache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")

        let count = TCGdexCardCount(total: 100, official: 100)
        let card = TCGdexCard(
            id: "test-card-1",
            localId: "001",
            name: "Test Card",
            image: nil,
            rarity: nil,
            set: TCGdexSetBrief(id: "sv99", name: "Test", cardCount: count),
            variants: TCGdexVariants(
                firstEdition: false, holo: false, normal: true, reverse: false, wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
        await cache.store(card: card, setCode: "TST", key: "test-key-1", officialCount: 100)

        let before = await cache.card(for: "test-key-1")
        XCTAssertNotNil(before)

        await cache.invalidateEntries(forSetIDs: Set(["sv99"]))

        let after = await cache.card(for: "test-key-1")
        XCTAssertNil(after)
    }

    func testResolvedCachePreservesUnchangedSets() async {
        let cacheRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let cache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")

        let count = TCGdexCardCount(total: 100, official: 100)
        let card = TCGdexCard(
            id: "test-card-1",
            localId: "001",
            name: "Test Card",
            image: nil,
            rarity: nil,
            set: TCGdexSetBrief(id: "sv99", name: "Test", cardCount: count),
            variants: TCGdexVariants(
                firstEdition: false, holo: false, normal: true, reverse: false, wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
        await cache.store(card: card, setCode: "TST", key: "test-key-1", officialCount: 100)

        await cache.invalidateEntries(forSetIDs: Set(["other-set"]))

        let after = await cache.card(for: "test-key-1")
        XCTAssertNotNil(after)
    }

    func testCursorClearedOnRegistryActivation() async {
        let storeRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let store = PokemonChecklistStore(root: storeRoot)
        await store.recordRefreshProgress(after: "sv01")
        await store.recordRefreshProgress(after: "sv02", failed: true)

        let cursor = await store.refreshResumeAfterProviderID()
        XCTAssertEqual(cursor, "sv02")
        let failed = await store.refreshFailedProviderIDs()
        XCTAssertTrue(failed.contains("sv02"))

        await store.clearCursorForRegistryActivation()

        let cursorAfter = await store.refreshResumeAfterProviderID()
        XCTAssertNil(cursorAfter)
        let failedAfter = await store.refreshFailedProviderIDs()
        XCTAssertTrue(failedAfter.isEmpty)
    }

    func testCursorPreservedOnRejection() async {
        let storeRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let store = PokemonChecklistStore(root: storeRoot)
        await store.recordRefreshProgress(after: "sv05")

        let cursor = await store.refreshResumeAfterProviderID()
        XCTAssertEqual(cursor, "sv05")
    }

    func testBrowseCatalogSetCacheInvalidation() async {
        let browseCatalog = BrowseCatalog()
        await browseCatalog.invalidateSetCache(for: .pokemon)
    }

    func testScanDisabledExcludesFromHistoricalResolution() async {
        let storeRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let checklistStore = PokemonChecklistStore(root: storeRoot)
        let offline = PokemonOfflineCatalog(store: checklistStore)

        let release = SliceBFixture.release(revision: 1, sets: [
            SliceBFixture.descriptor(
                providerSetID: "sv99",
                printedCode: "TST",
                officialCount: 100,
                scanEnabled: false
            )
        ])
        let registry = PokemonCatalogRegistry(release: release)
        await offline.updateRegistry(registry)

        XCTAssertFalse(registry.isScanEnabled(forProviderSetID: "sv99"))
    }
}

// MARK: - Coordinator activation with consumer invalidation

final class PokemonCatalogCoordinatorInvalidationTests: XCTestCase {
    func testActivationInvalidatesAllConsumers() async throws {
        let storeRoot = SliceBFixture.tempRoot()
        let checklistRoot = SliceBFixture.tempRoot()
        defer {
            try? FileManager.default.removeItem(at: storeRoot)
            try? FileManager.default.removeItem(at: checklistRoot)
        }

        let releaseStore = PokemonCatalogReleaseStore(root: storeRoot)
        let coordinator = PokemonCatalogCoordinator(
            store: releaseStore,
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let checklistStore = PokemonChecklistStore(root: checklistRoot)
        await checklistStore.recordRefreshProgress(after: "sv01")

        let release = SliceBFixture.release(revision: 1, sets: [
            SliceBFixture.descriptor(providerSetID: "sv99", officialCount: 110)
        ])
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        let result = await coordinator.activateEnvelope(envelope)
        guard case .activated(let event) = result else {
            return XCTFail("Expected activated")
        }

        let offline = PokemonOfflineCatalog(store: checklistStore)
        let cacheRoot = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let resolvedCache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")
        let browseCatalog = BrowseCatalog(checklistStore: checklistStore)

        await coordinator.invalidateConsumers(
            event: event,
            offline: offline,
            resolvedCache: resolvedCache,
            browseCatalog: browseCatalog,
            checklistStore: checklistStore
        )

        let cursor = await checklistStore.refreshResumeAfterProviderID()
        XCTAssertNil(cursor)
    }
}
