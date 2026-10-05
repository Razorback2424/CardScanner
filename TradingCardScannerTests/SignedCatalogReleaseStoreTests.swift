import CryptoKit
import Foundation
import OnePieceCatalogCore
import XCTest
@testable import TradingCardScanner

private final class CatalogTransportProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], [Data]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (status, headers, chunks) = handler(request)
        guard status != 0 else { return } // Fixture that leaves a transfer pending.
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SignedCatalogUpdateClientTests: XCTestCase {
    private struct Envelope: Codable, Sendable { let revision: Int }
    private func client(limit: Int = 100) throws -> SignedCatalogUpdateClient<Envelope> {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogTransportProtocol.self]
        return try .init(endpoint: URL(string: "https://fixture.invalid/catalog.json")!,
                         configuration: configuration, maximumBytes: limit)
    }
    override func tearDown() { CatalogTransportProtocol.handler = nil; super.tearDown() }

    func testConditionalFetchAndExplicitReset() async throws {
        CatalogTransportProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "fixture-etag" { return (304, [:], []) }
            return (200, ["ETag": "fixture-etag"], [Data("{\"revision\":2}".utf8)])
        }
        let client = try client()
        guard case .fetched(let envelope) = try await client.fetch() else { return XCTFail() }
        XCTAssertEqual(envelope.revision, 2)
        guard case .notModified = try await client.fetch() else { return XCTFail() }
        await client.resetConditionalState()
        guard case .fetched = try await client.fetch() else { return XCTFail() }
    }

    func testAdvertisedAndStreamingPayloadLimitsRejectBeforeDecode() async throws {
        for headers in [["Content-Length": "101"], [:]] {
            CatalogTransportProtocol.handler = { _ in (200, headers, [Data(repeating: 32, count: 60), Data(repeating: 32, count: 41)]) }
            do { _ = try await client().fetch(); XCTFail() }
            catch SignedCatalogUpdateError.payloadTooLarge {}
        }
    }

    func testMalformedJSONAndUnsolicited304AreRejected() async throws {
        CatalogTransportProtocol.handler = { _ in (200, [:], [Data("bad JSON".utf8)]) }
        do { _ = try await client().fetch(); XCTFail() } catch is DecodingError {}
        CatalogTransportProtocol.handler = { _ in (304, [:], []) }
        do { _ = try await client().fetch(); XCTFail() }
        catch SignedCatalogUpdateError.unexpectedNotModified {}
    }

    func testUnsafeEndpointsAndRedirectResponseAreRejected() async throws {
        for value in ["http://fixture.invalid/catalog", "https://user:password@fixture.invalid/catalog",
                      "https://fixture.invalid:443/catalog", "https://fixture.invalid/catalog?redirect=elsewhere"] {
            XCTAssertThrowsError(try SignedCatalogUpdateClient<Envelope>(endpoint: URL(string: value)!))
        }
        CatalogTransportProtocol.handler = { _ in (302, ["Location": "https://elsewhere.invalid/catalog"], []) }
        do { _ = try await client().fetch(); XCTFail() }
        catch SignedCatalogUpdateError.badResponse(302) {}
    }

    func testCancelledTransferCompletesWithoutRetry() async throws {
        let started = expectation(description: "transfer started")
        CatalogTransportProtocol.handler = { _ in started.fulfill(); return (0, [:], []) }
        let client = try client()
        let task = Task { try await client.fetch() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError {}
    }
}

private final class CatalogWriteFault: @unchecked Sendable {
    enum Timing { case before, after }
    enum Failure: Error { case injected }
    private let lock = NSLock()
    private var fileName: String?
    private var timing = Timing.before
    func fail(_ fileName: String, timing: Timing = .before) {
        lock.lock(); self.fileName = fileName; self.timing = timing; lock.unlock()
    }
    func clear() { lock.lock(); fileName = nil; lock.unlock() }
    func write(_ bytes: Data, _ url: URL) throws {
        lock.lock(); let shouldFail = fileName == url.lastPathComponent; let timing = timing; lock.unlock()
        if shouldFail && timing == .before { throw Failure.injected }
        try bytes.write(to: url, options: .atomic)
        if shouldFail && timing == .after { throw Failure.injected }
    }
}

final class SignedCatalogReleaseStoreTests: XCTestCase {
    private struct Envelope: Codable, Equatable, Sendable { let revision: Int }
    private typealias Store = SignedCatalogReleaseStore<Envelope, Int, Int>
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SignedCatalogStore-\(UUID())") }
    private func store(_ root: URL, policy: Store.RevisionPolicy = .activeRelease,
                       fault: CatalogWriteFault? = nil) -> Store {
        Store(root: root, currentName: "current.json", previousName: "previous.json", revisionPolicy: policy,
            revision: { $0 }, encode: { try JSONEncoder().encode($0) }, writeData: { data, url in
                if let fault { try fault.write(data, url) } else { try data.write(to: url, options: .atomic) }
            })
    }
    private func entry(_ revision: Int) -> Store.StoredRelease {
        .init(envelope: .init(revision: revision), release: revision, registry: revision)
    }
    private func load(_ store: Store) async {
        await store.load(decodeAndVerify: { bytes in
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            return .init(envelope: envelope, release: envelope.revision, registry: envelope.revision)
        })
    }

    func testAtomicRotationKeepsExactVerifiedBytesAndReloadsCurrent() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        _ = try await store.activate(entry(1))
        let original = try Data(contentsOf: root.appendingPathComponent("current.json"))
        let result = try await store.activate(entry(2))
        XCTAssertEqual(result, .activated(revision: 2, previousRevision: 1))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("previous.json")), original)
        let fresh = self.store(root); await load(fresh)
        let revision = await fresh.activeRevision
        XCTAssertEqual(revision, 2)
        let size = await fresh.diskUsageBytes()
        XCTAssertGreaterThan(size, original.count)
    }

    func testFailedCurrentWriteRetainsMemoryCurrentAndRecoverableBackup() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fault = CatalogWriteFault(), store = store(root, fault: fault)
        _ = try await store.activate(entry(1))
        fault.fail("current.json")
        do { _ = try await store.activate(entry(2)); XCTFail("Expected failure") } catch CatalogWriteFault.Failure.injected {}
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 1)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        let fresh = self.store(root); await load(fresh)
        let recovered = await fresh.activeRevision
        XCTAssertEqual(recovered, 1)
    }

    func testFailedBackupWriteDoesNotReplaceCurrent() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fault = CatalogWriteFault(), store = store(root, fault: fault)
        _ = try await store.activate(entry(1)); _ = try await store.activate(entry(2))
        let original = try Data(contentsOf: root.appendingPathComponent("current.json"))
        fault.fail("previous.json")
        do { _ = try await store.activate(entry(3)); XCTFail("Expected failure") } catch CatalogWriteFault.Failure.injected {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("current.json")), original)
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 2)
    }

    func testWriterErrorAfterCommitIsConfirmedFromExactPersistedBytes() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fault = CatalogWriteFault(), store = store(root, fault: fault)
        _ = try await store.activate(entry(1))
        fault.fail("current.json", timing: .after)
        let result = try await store.activate(entry(2))
        XCTAssertEqual(result, .activated(revision: 2, previousRevision: 1))
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 2)
    }

    func testBackupUsesVerifiedMemoryBytesWhenDiskCurrentWasCorrupted() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        _ = try await store.activate(entry(1))
        let original = try Data(contentsOf: root.appendingPathComponent("current.json"))
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        _ = try await store.activate(entry(2))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("previous.json")), original)
    }

    func testDomainRevisionPoliciesRemainDistinctAfterPreviousSlotRecovery() async throws {
        for policy in [Store.RevisionPolicy.currentSlot, .activeRelease] {
            let root = root(); defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(Envelope(revision: 7)).write(to: root.appendingPathComponent("previous.json"))
            try Data("corrupt".utf8).write(to: root.appendingPathComponent("current.json"))
            let store = store(root, policy: policy); await load(store)
            let result = try await store.activate(entry(6))
            if policy == .currentSlot { XCTAssertEqual(result, .activated(revision: 6, previousRevision: nil)) }
            else { XCTAssertEqual(result, .alreadyCurrent) }
        }
    }

    func testEncodingFailureDoesNotRotateSlots() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root, currentName: "current.json", previousName: "previous.json",
            revisionPolicy: .activeRelease, revision: { $0 }, encode: { envelope in
                if envelope.revision == 2 { throw CatalogWriteFault.Failure.injected }
                return try JSONEncoder().encode(envelope)
            })
        _ = try await store.activate(entry(1))
        let original = try Data(contentsOf: root.appendingPathComponent("current.json"))
        do { _ = try await store.activate(entry(2)); XCTFail("Expected failure") } catch CatalogWriteFault.Failure.injected {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("current.json")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("previous.json").path))
    }

    func testConcurrentActivationsFinishAtHighestDurableRevision() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for revision in 1...40 {
                let entry = entry(revision)
                group.addTask { _ = try await store.activate(entry) }
            }
            try await group.waitForAll()
        }
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 40)
        let fresh = self.store(root); await load(fresh)
        let durable = await fresh.activeRevision
        XCTAssertEqual(durable, revision)
    }
}

final class OnePieceCatalogActivationTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private let keyID = "one-piece-activation-test"
    private var keys: [String: Curve25519.Signing.PublicKey] { [keyID: key.publicKey] }
    private let date = "2026-10-03T00:00:00Z"
    private var now: Date { ISO8601DateFormatter().date(from: date)! }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceActivation-\(UUID())") }
    private func uuid(_ value: Int) -> UUID { UUID(uuidString: String(format: "20000000-0000-4000-8000-%012x", value))! }
    private func envelope(_ revision: Int, printingIDs: [Int] = [1], name: String = "Fixture",
                          extraNumber: String? = nil) throws -> OnePieceCatalogReleaseEnvelope {
        let card = OnePieceCanonicalCard(printedNumber: "OP01-120", language: "en", name: name)
        let observation = OnePieceProviderNormalizer.observation(provider: .bandai, capture: .init(
            observationID: "fixture-discovery", sourceID: "fixture-row", sourceURL: URL(string: "https://fixture.invalid/card")!,
            observedAt: date, language: "en", payloadBytes: Data("fixture discovery".utf8), printedEvidence: ["number": "OP01-120"]))
        let cards = [card] + (extraNumber.map { [OnePieceCanonicalCard(printedNumber: $0, language: "en", name: "Future fixture")] } ?? [])
        let registry = OnePieceRegistryDocument(canonicalCards: cards,
            artworks: [.init(id: uuid(900), observationIDs: [observation.id])],
            printings: printingIDs.map { .init(id: uuid($0), canonicalCardID: card.id, artworkID: uuid(900), language: "en",
                supportedVariantIDs: ["normal"], status: .provisional) }, variants: [.init(id: "normal", label: "Normal")])
        let release = try OnePieceCatalogBuilder.build(registry: registry, observations: [observation],
            inventories: [.init(provider: "bandai", snapshotID: "fixture", paginationComplete: true, observationIDs: [observation.id])],
            revision: revision, generatedAt: date)
        return try OnePieceCatalogSignature.sign(release, keyID: keyID, privateKey: key)
    }

    func testSignedCurrentPreviousRecoveryAndBundleFallback() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let seed = try envelope(1)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: seed, now: now)
        _ = try await store.activate(envelope(2), now: now)
        _ = try await store.activate(envelope(3), now: now)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent(OnePieceCatalogReleaseStore.Slot.current.rawValue))
        let recovered = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: seed, now: now)
        await recovered.load(now: now)
        let revision = await recovered.activeRevision
        XCTAssertEqual(revision, 2)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent(OnePieceCatalogReleaseStore.Slot.previous.rawValue))
        let fallback = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: seed, now: now)
        await fallback.load(now: now)
        let fallbackRevision = await fallback.activeRevision
        XCTAssertEqual(fallbackRevision, 1)
    }

    private actor UpdateFixture: OnePieceCatalogUpdateFetching {
        var envelopes: [OnePieceCatalogReleaseEnvelope]
        private(set) var fetches = 0
        private(set) var resets = 0
        init(_ envelopes: [OnePieceCatalogReleaseEnvelope]) { self.envelopes = envelopes }
        func fetch() async throws -> SignedCatalogFetchResult<OnePieceCatalogReleaseEnvelope> {
            fetches += 1
            try await Task.sleep(for: .milliseconds(20))
            return .fetched(envelopes.removeFirst())
        }
        func resetConditionalState() { resets += 1 }
    }

    func testRefreshCoalescesAndActivatesOnlyVerifiedDurableRelease() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let client = UpdateFixture([try envelope(2)])
        let coordinator = OnePieceCatalogCoordinator(store: store, client: client, rolloutMode: .remoteAuthority)
        async let first = coordinator.refresh(now: now)
        async let second = coordinator.refresh(now: now)
        for result in await [first, second] {
            guard case .activation(.activated(let event)) = result else { return XCTFail() }
            XCTAssertEqual(event.revision, 2)
        }
        let fetches = await client.fetches
        XCTAssertEqual(fetches, 1)
        let revision = await coordinator.revision
        XCTAssertEqual(revision, 2)
    }

    func testRejectedUpdateClearsValidatorsAndRetainsCatalogUntilRetry() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let good = try envelope(2)
        let bad = OnePieceCatalogReleaseEnvelope(keyID: good.keyID, payload: good.payload, signature: "invalid")
        let client = UpdateFixture([bad, good])
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store, client: client, rolloutMode: .remoteAuthority)
        guard case .rejected = await coordinator.refresh(now: now) else { return XCTFail() }
        let retained = await coordinator.revision, resets = await client.resets
        XCTAssertEqual(retained, 1); XCTAssertEqual(resets, 1)
        guard case .activation(.activated) = await coordinator.refresh(now: now) else { return XCTFail() }
        let active = await coordinator.revision
        XCTAssertEqual(active, 2)
    }

    func testValidationOnlyAndDisabledRefreshNeverActivateRemoteRelease() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let client = UpdateFixture([try envelope(2)])
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let disabled = OnePieceCatalogCoordinator(store: store, client: client)
        guard case .disabled = await disabled.refresh(now: now) else { return XCTFail() }
        let requests = await client.fetches
        XCTAssertEqual(requests, 0)
        let validation = OnePieceCatalogCoordinator(store: store, client: client, rolloutMode: .remoteValidationOnly)
        guard case .validated(2) = await validation.refresh(now: now) else { return XCTFail() }
        let retained = await validation.revision, diskBytes = await store.diskUsageBytes()
        XCTAssertEqual(retained, 1); XCTAssertEqual(diskBytes, 0)
        XCTAssertEqual(OnePieceCatalogRolloutMode.from(rawValue: "future-mode"), .disabled)
    }

    func testLaunchRefreshRunsOnceAcrossRepeatedLifecycleCalls() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let client = UpdateFixture([try envelope(2)])
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store, client: client, rolloutMode: .remoteAuthority)
        async let first: Void = coordinator.refreshAtLaunch()
        async let second: Void = coordinator.refreshAtLaunch()
        _ = await (first, second)
        await coordinator.refreshAtLaunch()
        let fetches = await client.fetches, revision = await coordinator.revision
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(revision, 2)
    }

    func testRollbackAndSameRevisionDifferentPayloadAreRejected() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let baseline = try envelope(2)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: baseline, now: now)
        do { _ = try await store.activate(envelope(1), now: now); XCTFail("Rollback must fail") }
        catch SignedCatalogStoreError.revisionRollback {}
        do { _ = try await store.activate(envelope(2, name: "Different signed payload"), now: now); XCTFail("Revision collision must fail") }
        catch SignedCatalogStoreError.revisionCollision {}
        let same = try await store.activate(baseline, now: now)
        XCTAssertEqual(same, .alreadyCurrent)
    }

    func testTransitionRetainsPrintingIDsAddedByActualDurablePredecessor() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, now: now)
        _ = try await store.activate(envelope(1), now: now)
        _ = try await store.activate(envelope(3, printingIDs: [1, 2]), now: now)
        do { _ = try await store.activate(envelope(4, printingIDs: [1]), now: now); XCTFail("Must retain newest predecessor IDs") }
        catch let error as OnePieceCatalogValidationError {
            XCTAssertTrue(error.issues.contains { $0.code == "removedPermanentPrinting" })
        }
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 3)
    }

    func testFailedPersistDoesNotPublishActivationOrChangeCoordinatorSnapshot() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fault = CatalogWriteFault()
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now,
            writeData: { try fault.write($0, $1) })
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let events = await coordinator.activationEvents()
        var iterator = events.makeAsyncIterator()
        await coordinator.loadPersistedOrBundled(now: now)
        fault.fail(OnePieceCatalogReleaseStore.Slot.current.rawValue)
        let result = await coordinator.activateEnvelope(try envelope(2), now: now)
        guard case .rejected = result else { return XCTFail("Expected rejection") }
        let revision = await coordinator.revision
        XCTAssertEqual(revision, 1)
        let durable = await store.activeRevision
        XCTAssertEqual(durable, 1)
        fault.clear()
        let next = await coordinator.activateEnvelope(try envelope(3), now: now)
        guard case .activated = next else { return XCTFail("Expected successful retry") }
        let event = await iterator.next()
        XCTAssertEqual(event?.revision, 3, "Rejected revision must not have entered the activation stream")
    }

    func testMetadataActivationChangesGenerationWithoutVocabularyReset() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        await coordinator.loadPersistedOrBundled(now: now)
        let old = await coordinator.registry
        let result = await coordinator.activateEnvelope(try envelope(2, name: "Updated fixture name"), now: now)
        guard case let .activated(event) = result else { return XCTFail("Expected activation") }
        XCTAssertFalse(event.recognitionVocabularyChanged)
        XCTAssertNotEqual(event.registry.generation, old?.generation)
        let future = await coordinator.activateEnvelope(try envelope(3, name: "Updated fixture name", extraNumber: "OP99-001"), now: now)
        guard case let .activated(next) = future else { return XCTFail("Expected new-prefix activation") }
        XCTAssertTrue(next.recognitionVocabularyChanged)
    }

    func testConcurrentInitialSnapshotsAllObserveLoadedCatalog() async throws {
        let root = root()
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let revisions = await withTaskGroup(of: Int?.self, returning: [Int?].self) { group in
            for _ in 0..<40 {
                group.addTask { await coordinator.currentSnapshot()?.revision }
            }
            var revisions: [Int?] = []
            for await revision in group { revisions.append(revision) }
            return revisions
        }
        XCTAssertEqual(revisions.count, 40)
        XCTAssertTrue(revisions.allSatisfy { $0 == 1 }, "Initial readers must await the same load")
    }

    func testSlowActivationSubscriberKeepsOnlyLatestDurableGeneration() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try OnePieceCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: envelope(1), now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let events = await coordinator.activationEvents()
        for revision in 2...6 {
            guard case .activated = await coordinator.activateEnvelope(try envelope(revision), now: now) else {
                return XCTFail("Expected durable activation")
            }
        }
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event?.revision, 6)
        let active = await coordinator.currentSnapshot()
        XCTAssertEqual(active?.revision, 6)
    }
}
