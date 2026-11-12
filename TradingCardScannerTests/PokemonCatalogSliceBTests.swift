import CryptoKit
import enum PokemonCatalogCore.PokemonCatalogJSON
import enum PokemonCatalogCore.PokemonCatalogProviderFingerprint
import struct PokemonCatalogCore.PokemonCatalogChecklistInput
import struct PokemonCatalogCore.PokemonCatalogProviderCard
import struct PokemonCatalogCore.PokemonCatalogProviderSet
import struct PokemonCatalogCore.PokemonCatalogSnapshot
import struct PokemonCatalogCore.PokemonCatalogSnapshotEntry
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
        scanEnabled: Bool = true,
        providerFingerprint: String? = nil
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
            providerFingerprint: providerFingerprint,
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

private struct OfflinePokemonCatalogTransport: PokemonBrowseTransport, PokemonCardSource {
    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] { throw unexpectedRequest() }
    func fetchSet(id: String) async throws -> TCGdexSetCatalog { throw unexpectedRequest() }
    func fetchCard(id: String) async throws -> TCGdexCard { throw unexpectedRequest() }
    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard { throw unexpectedRequest() }
    func fetchPokemonTCGCard(setID: String, cardNumber: String) async throws -> PokemonTCGAPICard? { throw unexpectedRequest() }

    private func unexpectedRequest() -> URLError {
        XCTFail("The installed signed catalog should serve this lookup offline")
        return URLError(.notConnectedToInternet)
    }
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
    func testUnnumberedEnergyAlwaysRequiresExplicitPrintingAndRevalidatesTheFamily() async throws {
        let registry = PokemonCatalogRegistry.bundledSeed
        let adapter = PokemonCatalogAdapter(source: OfflinePokemonCatalogTransport(), registry: registry)
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [adapter]))
        let coordinator = PokemonCatalogCoordinator(rolloutMode: .bundledValidationOnly)
        let expected: [(Int, String, String, Set<PhysicalVariant>)] = [
            (2013, "tcgplayer:135027", "Energy", [.normal, .holo]),
            (2017, "sm1-164", "SUM", [.normal, .reverse, .waveFoil]),
            (2019, "tcgplayer:184429", "TEU", [.normal, .reverse]),
            (2020, "tcgplayer:208034", "SSH", [.normal, .reverse]),
            (2022, "tcgplayer:264247", "Energy", [.normal, .reverse])
        ]
        var earlierChoice: PhysicalPrintingCandidate?
        for (year, providerID, setCode, finishes) in expected {
            let identifier = PokemonUnnumberedEnergyEvidence.identifier(year: year, generation: adapter.generation)
            guard case let .needsPrintingChoice(_, choices) = try await catalog.lookupOutcome(for: identifier) else {
                return XCTFail("A copyright year alone must never resolve one Energy type")
            }
            XCTAssertEqual(choices.count, year == 2022 ? 8 : 9)
            XCTAssertEqual(Set(choices.map(\.name)).count, choices.count)
            XCTAssertTrue(choices.allSatisfy { $0.thumbnailURL != nil && $0.printedIdentifier == "Unnumbered" })
            if let earlierChoice {
                do {
                    _ = try await catalog.resolvePrintingChoice(earlierChoice, for: identifier)
                    XCTFail("An Energy choice from a different year cannot be reused")
                } catch CatalogLookupError.invalidPrintingChoice { }
            }
            let selection = try XCTUnwrap(choices.first { $0.name == "Grass Energy" })
            earlierChoice = selection
            let result = try await catalog.resolvePrintingChoice(selection, for: identifier)
            XCTAssertEqual(result.card.providerID, providerID)
            XCTAssertEqual(result.card.setCode, setCode)
            XCTAssertEqual(result.card.displayCardNumber, "Unnumbered")
            XCTAssertEqual(Set(VariantResolver.options(for: result.card.variantEvidence)), finishes)
            guard case let .pokemon(payload, _) = result.card.legacyIdentity else { return XCTFail("Expected Pokémon evidence") }
            XCTAssertFalse(coordinator.acceptsAcquisition(payload, automaticIdentifier: identifier))
            XCTAssertTrue(coordinator.acceptsAcquisition(payload, automaticIdentifier: nil))
        }
        let unreviewedScan = PokemonUnnumberedEnergyEvidence.identifier(year: 2009, generation: adapter.generation)
        XCTAssertThrowsError(try adapter.prepareLookupIdentifier(unreviewedScan))
    }

    func testSignedChecklistCannotSupplyFinishesUnderThePreviousRegistry() async throws {
        let store = PokemonChecklistStore(root: root.appendingPathComponent("checklists"), bundle: nil)
        let coordinator = PokemonCatalogCoordinator(store: .init(root: root.appendingPathComponent("releases")),
            checklistStore: store, keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority)
        let set = PokemonCatalogProviderSet(id: "sv99", name: "Test Set",
            cards: [.init(id: "sv99-001", localID: "001", name: "Bulbasaur")],
            cardCount: .init(total: 1, official: 100))
        func stage(_ revision: Int, plainHolo: Bool) async throws -> PokemonCatalogRelease {
            let card = PokemonCatalogProviderCard(id: "sv99-001", localID: "001", name: "Bulbasaur", setID: set.id,
                variants: .init(firstEdition: false, holo: true, normal: false, reverse: false),
                variantsDetailed: [.init(type: "holo", subtype: nil, stamp: nil, foil: "cosmos", size: nil,
                    variantID: nil, languages: ["en"])], hasPlainHoloLane: plainHolo)
            let inputs = [set.id: PokemonCatalogChecklistInput(providerSet: set, cards: [card])]
            let fingerprint = try XCTUnwrap(PokemonCatalogProviderFingerprint.v1(providerSet: set, cardDetails: [card.id: card]))
            let release = PokemonCatalogRelease(revision: revision, generatedAt: .now,
                sets: [SliceBFixture.descriptor(providerFingerprint: fingerprint)],
                checklistInputSHA256: try PokemonCatalogChecklistInput.digest(inputs))
            let snapshot = try PokemonMasterSetChecklistBuilder.buildSigned(inputs,
                registry: .init(release: release), generatedAt: release.generatedAt)
            try await store.stageSignedSnapshot(snapshot, for: release)
            return release
        }

        let previous = try await stage(23, plainHolo: false)
        let next = try await stage(24, plainHolo: true)
        XCTAssertEqual(previous.sets.first?.providerFingerprint, next.sets.first?.providerFingerprint)
        XCTAssertNotEqual(previous.checklistInputSHA256, next.checklistInputSHA256)
        guard case .activated = await coordinator.activateEnvelope(try SliceBFixture.signedEnvelope(release: previous)) else {
            return XCTFail("Expected revision 23")
        }
        let registry = await coordinator.registry
        let definition = try XCTUnwrap(registry.pokemonSetDefinition(forPrintedCode: "TST"))
        let identifier = ScanIdentifier.pokemon(setCode: "TST", cardNumber: "001", printedTotal: 100, setDefinition: definition)
        let source = OfflinePokemonCatalogTransport()
        let catalog = CardCatalog(source: source, offline: .init(store: store),
            resolvedDiskCache: .init(root: root.appendingPathComponent("resolved")), registry: registry)
        let browse = BrowseCatalog(cache: .init(root: root.appendingPathComponent("cache")), pokemonTransport: source,
            checklistStore: store, catalogCoordinator: coordinator)
        let setID = CatalogSetID(game: .pokemon, providerID: set.id)
        let previousRows = await store.mergedChecklist(for: setID)
        let summary = try XCTUnwrap(previousRows?.first)
        let previousDetail = await browse.installedDetails(for: summary)
        XCTAssertEqual(previousDetail?.card.variantEvidence.catalogVariants.contains(.holo), false)

        // Hold the actual ordering between the store swap and registry publication.
        let staged = await store.activateSignedSnapshot(for: next)
        XCTAssertTrue(staged)
        do {
            _ = try await catalog.card(for: identifier)
            XCTFail("Scan must decline the checklist while its registry is still on revision 23")
        } catch CatalogLookupError.staleCatalog { }
        let mismatched = await browse.installedDetails(for: summary)
        XCTAssertNil(mismatched)

        guard case .activated = await coordinator.activateEnvelope(try SliceBFixture.signedEnvelope(release: next)) else {
            return XCTFail("Expected revision 24")
        }
        await catalog.updateRegistry(await coordinator.registry)
        let current = try await catalog.card(for: identifier)
        XCTAssertTrue(current.variantEvidence.catalogVariants.contains(.holo))
        let currentDetail = await browse.installedDetails(for: summary)
        XCTAssertEqual(currentDetail?.card.variantEvidence.catalogVariants.contains(.holo), true)
    }

    func testCreatorPackCompletesBrowseAndOfflineScanWithCertifiedNormal() async throws {
        let store = PokemonChecklistStore(root: root.appendingPathComponent("checklists"), bundle: .main)
        let catalog = CardCatalog(source: OfflinePokemonCatalogTransport(), offline: .init(store: store),
            resolvedDiskCache: .init(root: root.appendingPathComponent("resolved")), registry: .bundledSeed)
        let setID = CatalogSetID(game: .pokemon, providerID: "ex5.5")
        let checklist = await store.mergedChecklist(for: setID)
        let rows = try XCTUnwrap(checklist)
        let names = ["Treecko", "Wurmple", "Torchic", "Mudkip", "Pikachu"]
        XCTAssertEqual(Set(rows.map(\.name)), Set(names))
        XCTAssertEqual(rows.count, names.count)

        for (index, name) in names.enumerated() {
            let localID = String(index + 1)
            let providerID = "ex5.5-\(localID)"
            XCTAssertEqual(rows.first { $0.providerID == providerID }?.masterSetVariant, .normal)
            let number = PokemonPrintedNumberEvidence(localID: localID, denominator: 5, scheme: .officialSet)
            let evidence = PokemonHistoricalScanEvidence(number: number, titleCandidates: [name])
            let identified = try await catalog.card(for: .pokemonHistorical(evidence))
            XCTAssertEqual(identified.providerID, providerID)
            XCTAssertTrue(identified.variantEvidence.physicalCoverageVerified)
            XCTAssertEqual(VariantResolver.resolveAcquisition(identified.variantEvidence, printedEdition: .absent),
                .resolved(.init(variant: .normal, resolution: .uniqueInCatalog)))
        }
    }

    func testVivillonScanOffersBothArtworkChoicesAndResolvesTheSelectedPrintingOffline() async throws {
        let store = PokemonChecklistStore(root: root.appendingPathComponent("checklists"), bundle: .main)
        let catalog = CardCatalog(source: OfflinePokemonCatalogTransport(), offline: .init(store: store),
            resolvedDiskCache: .init(root: root.appendingPathComponent("resolved")), registry: .bundledSeed)
        let number = PokemonPrintedNumberEvidence(localID: "017", denominator: 146, scheme: .officialSet)
        let evidence = PokemonHistoricalScanEvidence(number: number, titleCandidates: ["Vivillon"])
        let identifier = ScanIdentifier.pokemonHistorical(evidence)
        var choices: [PokemonCatalogCardIdentity] = []
        do {
            _ = try await catalog.card(for: identifier)
            XCTFail("The shared footer and title cannot identify the artwork")
        } catch let PokemonHistoricalCatalogError.ambiguous(matches) {
            choices = matches
        }
        XCTAssertEqual(Set(choices.map(\.providerID)), ["xy1-17", "tcgplayer:90395"])
        XCTAssertEqual(Set(choices.map(\.choiceLabel)), ["XY · Meadow", "XY · High Plains"])
        XCTAssertEqual(Set(choices.compactMap(\.thumbnailURL)).count, 2)
        var ownershipKeys = Set<String>()
        for choice in choices {
            let card = try await catalog.card(for: choice, matching: evidence, recoverArtwork: false)
            XCTAssertEqual(card.providerID, choice.providerID)
            XCTAssertEqual(card.displayCardNumber, "17/146")
            ownershipKeys.insert(card.collectionKey(variant: .holo))
            let expected: Set<PhysicalVariant> = choice.providerID == "xy1-17" ? [.holo, .reverse, .pokemonFoilPattern("cosmos")] : [.holo, .reverse]
            XCTAssertEqual(Set(VariantResolver.options(for: card.variantEvidence)), expected)
        }
        XCTAssertEqual(ownershipKeys.count, 2)
    }

    func testSignedChecklistGatesActivationAndReopensWithoutNetwork() async throws {
        let cards: [PokemonCatalogProviderCard] = [
            .init(id: "me06-001", localID: "001", name: "Heracross", setID: "me06",
                variants: .init(firstEdition: false, holo: false, normal: true, reverse: true))
        ]
        let providerSet = PokemonCatalogProviderSet(id: "me06", name: "Delta Reign",
            cards: [.init(id: "me06-001", localID: "001", name: "Heracross")],
            cardCount: .init(total: 1, official: 103))
        let fingerprint = try XCTUnwrap(PokemonCatalogProviderFingerprint.v1(providerSet: providerSet,
            cardDetails: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })))
        let inputs = ["me06": PokemonCatalogChecklistInput(providerSet: providerSet, cards: cards)]
        let release = PokemonCatalogRelease(revision: 23, generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [SliceBFixture.descriptor(providerSetID: "me06", printedCode: "DLR", officialCount: 103,
                providerFingerprint: fingerprint)], checklistInputSHA256: try PokemonCatalogChecklistInput.digest(inputs))
        let entry = PokemonCatalogSnapshotEntry(providerSetID: "me06", displayName: "Delta Reign", printedCode: "DLR",
            officialCount: 103, releaseOrder: 99, providerFingerprint: fingerprint, cardCount: 1,
            resource: "sets/me06-\(fingerprint).json")
        let valid = try PokemonCatalogJSON.encode(PokemonCatalogCore.PokemonCatalogSnapshot(
            generatedAt: release.generatedAt, directoryFingerprint: "fixture", entries: [entry], checklists: [:],
            checklistInputs: inputs))
        let changedLane = PokemonCatalogProviderCard(id: "me06-001", localID: "001", name: "Heracross", setID: "me06",
            variants: cards[0].variants, hasPlainReverseLane: true)
        XCTAssertEqual(PokemonCatalogProviderFingerprint.v1(providerSet: providerSet, cardDetails: [changedLane.id: changedLane]),
                       fingerprint)
        let tampered = try PokemonCatalogJSON.encode(PokemonCatalogCore.PokemonCatalogSnapshot(
            generatedAt: release.generatedAt, directoryFingerprint: "fixture", entries: [entry], checklists: [:],
            checklistInputs: ["me06": .init(providerSet: providerSet, cards: [changedLane])]))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); MockURLProtocol.handler = nil }
        let client = PokemonCatalogUpdateClient(session: session)
        let releaseRoot = root.appendingPathComponent("releases")
        let checklistRoot = root.appendingPathComponent("checklists")
        let store = PokemonChecklistStore(root: checklistRoot, bundle: nil)
        let coordinator = PokemonCatalogCoordinator(store: .init(root: releaseRoot), checklistStore: store,
            client: client, keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority)
        let previous = try SliceBFixture.signedEnvelope(release: SliceBFixture.release(revision: 22))
        guard case .activated = await coordinator.activateEnvelope(previous) else { return XCTFail("Expected revision 22") }
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        var requests = 0
        var servedData = tampered
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/v1/releases/23/pokemon-catalog-snapshot.json")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            requests += 1
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                  headerFields: nil)), servedData)
        }
        guard case .rejected = await coordinator.activateEnvelope(envelope) else { return XCTFail("Expected invalid checklist rejection") }
        let retained = await coordinator.revision
        XCTAssertEqual(retained, 22)
        servedData = valid
        guard case .activated = await coordinator.activateEnvelope(envelope) else { return XCTFail("Expected revision 23") }

        let reopened = PokemonChecklistStore(root: checklistRoot, bundle: nil)
        let reopenedCoordinator = PokemonCatalogCoordinator(store: .init(root: releaseRoot), checklistStore: reopened,
            client: client, keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority)
        await reopenedCoordinator.loadPersistedOrBundled()
        let recovered = await reopenedCoordinator.revision
        XCTAssertEqual(recovered, 23)
        let offline = PokemonOfflineCatalog(store: reopened)
        let card = try await offline.cardWithSource(providerSetID: "me06", localID: "001", expectedOfficialCount: 103,
            registry: await reopenedCoordinator.registry, requiresExactFingerprint: true)
        XCTAssertEqual(card?.source, .signed)
        XCTAssertEqual(card?.card.catalogVariants, [.normal, .reverse])
        let id = CatalogSetID(game: .pokemon, providerID: "me06")
        let browse = BrowseCatalog(cache: CatalogCacheStore(root: root.appendingPathComponent("cache")),
            pokemonTransport: OfflinePokemonCatalogTransport(), checklistStore: reopened, catalogCoordinator: reopenedCoordinator)
        let search = try await browse.searchCards(named: "DLR 001/103", game: .pokemon, setIDs: [id], cursor: nil)
        XCTAssertEqual(search.items.map(\.providerID), ["me06-001"])
        await browse.refreshCatalogNow()
        XCTAssertEqual(requests, 2)

        let digest = try XCTUnwrap(release.checklistInputSHA256)
        let signedDirectory = checklistRoot.appendingPathComponent("signed-checklists/23-\(digest)")
        let entries = await reopened.mergedEntries()
        let nativeEntry = try XCTUnwrap(entries.first { $0.set.catalogID == id })
        let resource = signedDirectory.appendingPathComponent(nativeEntry.resource)
        try Data("[]".utf8).write(to: resource, options: .atomic)
        let repairedStore = PokemonChecklistStore(root: checklistRoot, bundle: nil)
        let repaired = PokemonCatalogCoordinator(store: .init(root: releaseRoot), checklistStore: repairedStore,
            client: client, keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority)
        await repaired.loadPersistedOrBundled()
        let fallback = await repaired.revision
        XCTAssertEqual(fallback, 22)
        guard case .activated = await repaired.activateEnvelope(envelope) else { return XCTFail("Expected revision recovery") }
        XCTAssertEqual(requests, 3)
        let restored = await repairedStore.mergedChecklist(for: id)
        XCTAssertEqual(Set(restored?.map(\.providerID) ?? []), ["me06-001"])

        // Losing the current checklist again must not turn its incomplete
        // revision into the backup when a newer release is installed.
        try FileManager.default.removeItem(at: signedDirectory)
        let next = try SliceBFixture.signedEnvelope(release: SliceBFixture.release(revision: 24))
        guard case .activated = await repaired.activateEnvelope(next) else { return XCTFail("Expected revision 24") }
        let reopenedReleases = PokemonCatalogReleaseStore(root: releaseRoot)
        await reopenedReleases.load(keys: [SliceBFixture.pinnedKey])
        let backup = await reopenedReleases.previousRelease
        XCTAssertEqual(backup?.release.revision, 22)
    }

    func testPreparedRevision23InstallsAndServesScanAndBrowseOfflineWhenRequested() async throws {
        let configured = ProcessInfo.processInfo.environment["POKEMON_CATALOG_CANDIDATE_ROOT"]
            ?? Bundle.main.object(forInfoDictionaryKey: "POKEMON_CATALOG_CANDIDATE_ROOT") as? String
        guard let configured, !configured.isEmpty else { throw XCTSkip("Provide the prepared revision 23 candidate directory") }
        let candidate = URL(fileURLWithPath: configured)
        let release = try PokemonCatalogJSON.decode(PokemonCatalogRelease.self,
            from: Data(contentsOf: candidate.appendingPathComponent("catalog-payload.json")))
        let bytes = try Data(contentsOf: candidate.appendingPathComponent("pokemon-catalog-snapshot.json"))
        let snapshot = try PokemonCatalogJSON.decode(PokemonCatalogCore.PokemonCatalogSnapshot.self, from: bytes)
        let inputs = try snapshot.verifiedChecklistInputs(for: release)
        XCTAssertEqual(release.revision, 23)
        XCTAssertEqual(inputs.count, 76)
        XCTAssertEqual(inputs.values.reduce(0) { $0 + $1.cards.count }, 6_850)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); MockURLProtocol.handler = nil }
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/v1/releases/23/pokemon-catalog-snapshot.json")
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), bytes)
        }
        let releaseRoot = root.appendingPathComponent("releases")
        let checklistRoot = root.appendingPathComponent("checklists")
        let coordinator = PokemonCatalogCoordinator(store: .init(root: releaseRoot),
            checklistStore: .init(root: checklistRoot, bundle: nil), client: .init(session: session),
            keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority)
        let envelope = try SliceBFixture.signedEnvelope(release: release)
        guard case .activated = await coordinator.activateEnvelope(envelope) else { return XCTFail("Expected complete revision 23 activation") }
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let store = PokemonChecklistStore(root: checklistRoot, bundle: nil)
        let reopened = PokemonCatalogCoordinator(store: .init(root: releaseRoot), checklistStore: store,
            client: .init(session: session), keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority)
        await reopened.loadPersistedOrBundled()
        let registry = await reopened.registry
        XCTAssertEqual(registry.revision, 23)
        let transport = OfflinePokemonCatalogTransport()
        let browse = BrowseCatalog(cache: .init(root: root.appendingPathComponent("browse")),
            pokemonTransport: transport, checklistStore: store, catalogCoordinator: reopened)
        var cardsBySet: [String: [CatalogCardSummary]] = [:]
        for set in try await browse.sets(for: .pokemon) {
            cardsBySet[set.providerID, default: []].append(contentsOf: try await browse.cards(in: set, cursor: nil).items)
        }
        for (id, checklist) in snapshot.checklists {
            XCTAssertEqual(Set(cardsBySet[id, default: []].map(\.providerID)), Set(checklist.map(\.providerCardID)), id)
        }

        let scanner = CardCatalog(source: transport, offline: .init(store: store, registry: registry),
            resolvedDiskCache: .init(root: root.appendingPathComponent("scanner")), registry: registry)
        let profile = PokemonScanProfile(registry: registry)
        for entry in PokemonBattleDeckFinishCatalog.entries {
            let slots = cardsBySet[entry.setID, default: []].filter { $0.providerID == entry.cardID }
            let deckSlots = slots.filter { $0.masterSetVariant == entry.variant }
            XCTAssertEqual(deckSlots.count, 1, entry.cardID)
            let summary = try XCTUnwrap(deckSlots.first, entry.cardID)
            XCTAssertTrue(summary.isExpandedMasterSetVariant, entry.cardID)
            let footer = "\(summary.setCode) EN \(entry.printedNumber)"
            let identifier = try XCTUnwrap(profile.parse(footer), footer)
            let scanned = try await scanner.card(for: identifier)
            let details = await browse.installedDetails(for: summary)
            let browsed = try XCTUnwrap(details?.card, entry.cardID)
            for card in [scanned, browsed] {
                XCTAssertEqual(card.providerID, entry.cardID)
                guard case let .needsChoice(options, _) = VariantResolver.resolve(card.variantEvidence) else {
                    return XCTFail("Expected the deck finish to be a distinct choice for \(entry.cardID)")
                }
                XCTAssertTrue(options.contains(entry.variant), entry.cardID)
                XCTAssertEqual(CardPricing.tcgplayerProductID(for: card, variant: entry.variant, printRun: nil),
                    entry.productID, entry.cardID)
            }
        }
        let delta = Dictionary(grouping: try XCTUnwrap(cardsBySet["me06"]), by: \.providerID)
        var finishCounts: [[String]: Int] = [:]
        for (id, slots) in delta {
            let number = try XCTUnwrap(slots.first?.collectorNumber)
            let identifier = try XCTUnwrap(profile.parse("DLR EN \(number)/103"), id)
            let card = try await scanner.card(for: identifier)
            XCTAssertEqual(card.providerID, id)
            let options = VariantResolver.options(for: card.variantEvidence).map(\.id).sorted()
            XCTAssertEqual(options, slots.compactMap { $0.masterSetVariant?.id }.sorted(), id)
            finishCounts[options, default: 0] += 1
        }
        XCTAssertEqual(finishCounts, [["normal", "reverse"]: 77, ["holo"]: 48, ["holo", "reverse"]: 10, ["normal"]: 6])
        let disputed = release.sets.flatMap { $0.additionalVariants ?? [] }.filter { $0.normalNeedsReview == true }
        XCTAssertEqual(disputed.count, 41)
        let slotsByID = Dictionary(grouping: cardsBySet.values.joined(), by: \.providerID)
        for variant in disputed {
            let matching = slotsByID[variant.providerCardID, default: []]
            XCTAssertEqual(matching.compactMap(\.masterSetVariant), [.holo], variant.providerCardID)
            let summary = try XCTUnwrap(matching.first)
            let identifier = try XCTUnwrap(profile.parse(summary.collectorNumber), variant.providerCardID)
            let card = try await scanner.card(for: identifier)
            XCTAssertEqual(card.providerID, variant.providerCardID)
            XCTAssertEqual(VariantResolver.options(for: card.variantEvidence), [.holo], variant.providerCardID)
        }
        await browse.refreshCatalogNow()
    }

    func testFailedActivationRefetchesWithoutValidators() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); MockURLProtocol.handler = nil }
        let envelope = try SliceBFixture.signedEnvelope(release: SliceBFixture.release(revision: 5))
        let data = try JSONEncoder().encode(envelope)
        var conditionalHeaders: [String?] = []
        MockURLProtocol.handler = { request in
            conditionalHeaders.append(request.value(forHTTPHeaderField: "If-None-Match"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["ETag": "catalog-v5", "Last-Modified": "today"])!, data)
        }
        // Inject a persistence failure without adding a production test hook.
        try Data("blocking file".utf8).write(to: root)
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            client: PokemonCatalogUpdateClient(session: session, baseURL: URL(string: "https://test.example.com")!),
            keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority
        )
        guard case .rejected = await coordinator.refresh() else { return XCTFail("blocked storage must reject activation") }
        try FileManager.default.removeItem(at: root)
        guard case .activated = await coordinator.refresh() else { return XCTFail("second refresh must activate") }
        XCTAssertEqual(conditionalHeaders.count, 2)
        XCTAssertTrue(conditionalHeaders.allSatisfy { $0 == nil })
    }

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

    func testConcurrentInitialLoadsAllWaitForThePersistedRegistry() async throws {
        let release = SliceBFixture.release(revision: 5)
        let store = PokemonCatalogReleaseStore(root: root)
        _ = try await store.activate(
            envelope: SliceBFixture.signedEnvelope(release: release),
            release: release, registry: PokemonCatalogRegistry(release: release)
        )
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority
        )
        let revisions = await withTaskGroup(of: Int?.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await coordinator.loadPersistedOrBundled()
                    return await coordinator.revision
                }
            }
            var revisions: [Int?] = []
            for await revision in group { revisions.append(revision) }
            return revisions
        }
        XCTAssertEqual(revisions, Array(repeating: Optional(5), count: 12))
    }

    func testConcurrentActivationsPublishMonotonicRegistriesAndAccurateChanges() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority
        )
        await coordinator.loadPersistedOrBundled()
        _ = await coordinator.activateEnvelope(try SliceBFixture.signedEnvelope(
            release: SliceBFixture.release(revision: 1)
        ))
        let envelopes = try (2...12).map { revision in
            try SliceBFixture.signedEnvelope(release: SliceBFixture.release(
                revision: revision, sets: [SliceBFixture.descriptor(officialCount: 99 + revision)]
            ))
        }
        let events = await withTaskGroup(of: PokemonCatalogCoordinator.RefreshResult.self) { group in
            for envelope in envelopes { group.addTask { await coordinator.activateEnvelope(envelope) } }
            var events: [PokemonCatalogCoordinator.ActivationEvent] = []
            for await result in group {
                if case let .activated(event) = result { events.append(event) }
            }
            return events.sorted { $0.revision < $1.revision }
        }
        var previous = 1
        for event in events {
            XCTAssertGreaterThan(event.revision, previous)
            XCTAssertEqual(event.previousRevision, previous)
            XCTAssertTrue(event.changedOfficialCountSetIDs.contains("sv99"))
            previous = event.revision
        }
        XCTAssertEqual(previous, 12)
        let revision = await coordinator.revision
        let registry = await coordinator.registry
        XCTAssertEqual(revision, 12)
        XCTAssertEqual(registry.officialCount(forProviderSetID: "sv99"), 111)
        let recovered = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey], rolloutMode: .remoteAuthority
        )
        await recovered.loadPersistedOrBundled()
        let recoveredRevision = await recovered.revision
        XCTAssertEqual(recoveredRevision, revision)
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

    func testProviderContentChangeDetectedSeparatelyFromAuthority() async throws {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceBFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let release1 = SliceBFixture.release(revision: 1, sets: [
            SliceBFixture.descriptor(providerFingerprint: "content-a")
        ])
        _ = await coordinator.activateEnvelope(
            try SliceBFixture.signedEnvelope(release: release1)
        )

        let release2 = SliceBFixture.release(revision: 2, sets: [
            SliceBFixture.descriptor(providerFingerprint: "content-b")
        ])
        let result = await coordinator.activateEnvelope(
            try SliceBFixture.signedEnvelope(release: release2)
        )
        guard case .activated(let event) = result else {
            return XCTFail("Expected activated")
        }
        XCTAssertTrue(event.contentChangedProviderSetIDs.contains("sv99"))
        XCTAssertTrue(event.changedOfficialCountSetIDs.isEmpty)
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
    func testResolvedCacheEntryInvalidationPreservesOtherEntriesInSameSetAfterRestart() async throws {
        let root = SliceBFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ResolvedPokemonCardCache(root: root, appVersion: "test")
        for (number, name) in [("58", "Pikachu"), ("4", "Charizard")] {
            let card = TCGdexCard(
                id: "base1-\(number)",
                localId: number,
                name: name,
                image: nil,
                rarity: nil,
                set: TCGdexSetBrief(
                    id: "base1", name: "Base Set", cardCount: .init(total: 102, official: 102)
                ),
                variants: .init(firstEdition: false, holo: false, normal: true, reverse: false, wPromo: nil),
                pricing: nil,
                variantsDetailed: nil
            )
            await cache.store(card: card, setCode: "BS", key: "historical-\(number)")
        }
        // Exercise cold-load invalidation and its persisted result.
        let coldCache = ResolvedPokemonCardCache(root: root, appVersion: "test")
        await coldCache.invalidateEntry(for: "historical-58")
        let restarted = ResolvedPokemonCardCache(root: root, appVersion: "test")
        let removed = await restarted.card(for: "historical-58")
        let preserved = await restarted.card(for: "historical-4")
        XCTAssertNil(removed)
        XCTAssertEqual(preserved?.card.id, "base1-4")
    }

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
