import CryptoKit
import XCTest
@testable import TradingCardScanner

private enum SliceFFixture {
    static let keyID = "slice-f"
    static let privateKey = Curve25519.Signing.PrivateKey()

    static var pinnedKey: PokemonCatalogSignatureVerifier.PinnedKey {
        .init(id: keyID, publicKey: privateKey.publicKey)
    }

    static func descriptor(
        providerSetID: String = "sv99",
        printedCode: String = "TST",
        officialCount: Int = 2
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerSetID,
            displayName: "Synthetic Test Set",
            releaseDate: "2026-01-01",
            releaseOrder: 100,
            recognitionKind: .expansion,
            printedCode: printedCode,
            officialCount: officialCount,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: true,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
        )
    }

    static func release(revision: Int = 1) -> PokemonCatalogRelease {
        PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [descriptor()]
        )
    }

    static func envelope(revision: Int = 1) throws -> PokemonCatalogReleaseEnvelope {
        try PokemonCatalogSignatureVerifier.sign(
            release: release(revision: revision),
            privateKey: privateKey,
            keyID: keyID
        )
    }

    static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PokemonCatalogSliceF-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class SliceFURLProtocol: URLProtocol {
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

final class PokemonCatalogSliceFTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = SliceFFixture.temporaryRoot()
        SliceFURLProtocol.handler = nil
    }

    override func tearDown() {
        SliceFURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeClient(
        diagnostics: PokemonCatalogRolloutDiagnostics,
        envelope: PokemonCatalogReleaseEnvelope
    ) throws -> PokemonCatalogUpdateClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SliceFURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let data = try JSONEncoder().encode(envelope)
        SliceFURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "\"slice-f\""]
            )!
            return (response, data)
        }
        return PokemonCatalogUpdateClient(
            session: session,
            baseURL: URL(string: "https://catalog.test")!,
            diagnostics: diagnostics
        )
    }

    func testBundledValidationOnlyVerifiesAndDiscardsRemoteRelease() async throws {
        let diagnostics = PokemonCatalogRolloutDiagnostics()
        await diagnostics.reset()
        let envelope = try SliceFFixture.envelope()
        let client = try makeClient(diagnostics: diagnostics, envelope: envelope)
        let store = PokemonCatalogReleaseStore(root: root)
        let coordinator = PokemonCatalogCoordinator(
            store: store,
            client: client,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .bundledValidationOnly,
            diagnostics: diagnostics
        )

        let result = await coordinator.refresh()
        guard case .validated(let validation) = result else {
            return XCTFail("Expected validation-only result, got \(result)")
        }
        XCTAssertEqual(validation.revision, 1)
        XCTAssertEqual(validation.descriptorCount, 1)
        XCTAssertEqual(validation.supportedDescriptorCount, 1)
        let coordinatorRevision = await coordinator.revision
        let storeRevision = await store.activeRevision
        let currentExists = await store.slotFileExists(.current)
        XCTAssertNil(coordinatorRevision)
        XCTAssertNil(storeRevision)
        XCTAssertFalse(currentExists)

        let snapshot = await diagnostics.snapshot()
        XCTAssertEqual(snapshot.mode, .bundledValidationOnly)
        XCTAssertEqual(snapshot.validationCount, 1)
        XCTAssertEqual(snapshot.activationCount, 0)
        XCTAssertEqual(snapshot.lastOutcome, "validated-and-discarded")
        XCTAssertGreaterThan(snapshot.networkRequestCount, 0)
        XCTAssertEqual(snapshot.lastDiskBytes, 0)
        XCTAssertNotNil(snapshot.lastLaunchLoadDuration)
        XCTAssertNotNil(snapshot.lastValidationDuration)
    }

    func testRemoteAuthorityRequiresExplicitModeAndActivatesSyntheticRelease() async throws {
        let diagnostics = PokemonCatalogRolloutDiagnostics()
        await diagnostics.reset()
        let envelope = try SliceFFixture.envelope()
        let client = try makeClient(diagnostics: diagnostics, envelope: envelope)
        let store = PokemonCatalogReleaseStore(root: root)
        let coordinator = PokemonCatalogCoordinator(
            store: store,
            client: client,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )

        let result = await coordinator.refresh()
        guard case .activated(let event) = result else {
            return XCTFail("Expected explicit remote activation, got \(result)")
        }
        XCTAssertEqual(event.revision, 1)
        let mode = await coordinator.currentRolloutMode
        let providerID = await coordinator.registry.expansion(forPrintedCode: "TST")?.providerSetID
        let storeRevision = await store.activeRevision
        let currentExists = await store.slotFileExists(.current)
        XCTAssertEqual(mode, .remoteAuthority)
        XCTAssertEqual(providerID, "sv99")
        XCTAssertEqual(storeRevision, 1)
        XCTAssertTrue(currentExists)

        let snapshot = await diagnostics.snapshot()
        XCTAssertEqual(snapshot.activationCount, 1)
        XCTAssertEqual(snapshot.validationCount, 0)
        XCTAssertEqual(snapshot.lastOutcome, "activated")
        XCTAssertGreaterThan(snapshot.lastDiskBytes ?? 0, 0)
        XCTAssertNotNil(snapshot.lastLaunchLoadDuration)
        XCTAssertNotNil(snapshot.lastActivationDuration)
    }

    func testValidationOnlyIgnoresAPreviouslyPersistedRemoteRelease() async throws {
        let persistedStore = PokemonCatalogReleaseStore(root: root)
        let release = SliceFFixture.release()
        let envelope = try SliceFFixture.envelope()
        let registry = PokemonCatalogRegistry(release: release)
        _ = try await persistedStore.activate(
            envelope: envelope,
            release: release,
            registry: registry
        )

        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .bundledValidationOnly
        )
        await coordinator.loadPersistedOrBundled()

        let revision = await coordinator.revision
        let remoteCode = await coordinator.registry.expansion(forPrintedCode: "TST")
        XCTAssertNil(revision)
        XCTAssertNil(remoteCode)
    }

    func testRolloutModeAndPinnedKeyConfigurationFailClosed() throws {
        XCTAssertEqual(
            PokemonCatalogRolloutMode.from(rawValue: "remote_authority"),
            .remoteAuthority
        )
        XCTAssertEqual(
            PokemonCatalogRolloutMode.from(rawValue: "unknown"),
            .bundledValidationOnly
        )

        let encoded = Base64URL.encode(SliceFFixture.privateKey.publicKey.rawRepresentation)
        let keys = PokemonCatalogSignatureVerifier.configuredPinnedKeys(
            from: "slice-f:\(encoded)"
        )
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys.first?.id, SliceFFixture.keyID)
        XCTAssertTrue(
            PokemonCatalogSignatureVerifier.configuredPinnedKeys(from: "slice-f:not-a-key").isEmpty
        )
    }

    func testCatalogOriginAllowlistSeparatesProductionAndStagingHosts() {
        XCTAssertTrue(
            PokemonCatalogUpdateClient.isAllowedCatalogOrigin(
                PokemonCatalogUpdateClient.productionBaseURL,
                expectedHost: "catalog.scan-stash.com"
            )
        )
        XCTAssertTrue(
            PokemonCatalogUpdateClient.isAllowedCatalogOrigin(
                PokemonCatalogUpdateClient.stagingBaseURL,
                expectedHost: "catalog-staging.scan-stash.com"
            )
        )
        XCTAssertFalse(
            PokemonCatalogUpdateClient.isAllowedCatalogOrigin(
                PokemonCatalogUpdateClient.stagingBaseURL,
                expectedHost: "catalog.scan-stash.com"
            )
        )
        XCTAssertFalse(
            PokemonCatalogUpdateClient.isAllowedCatalogOrigin(
                URL(string: "https://attacker.example")!
            )
        )
        XCTAssertFalse(
            PokemonCatalogUpdateClient.isAllowedCatalogOrigin(
                URL(string: "http://catalog.scan-stash.com")!
            )
        )
        XCTAssertFalse(
            PokemonCatalogUpdateClient.isAllowedCatalogOrigin(
                URL(string: "https://catalog.scan-stash.com/unexpected-path")!
            )
        )
    }
}
