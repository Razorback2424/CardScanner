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

    static func release(
        revision: Int = 1,
        officialCount: Int = 2
    ) -> PokemonCatalogRelease {
        PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [descriptor(officialCount: officialCount)]
        )
    }

    static func envelope(
        revision: Int = 1,
        officialCount: Int = 2
    ) throws -> PokemonCatalogReleaseEnvelope {
        try PokemonCatalogSignatureVerifier.sign(
            release: release(revision: revision, officialCount: officialCount),
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

    func testFreshCoordinatorTreatsIdenticalCurrentEnvelopeAsNotModified() async throws {
        let diagnostics = PokemonCatalogRolloutDiagnostics()
        await diagnostics.reset()
        let envelope = try SliceFFixture.envelope(revision: 1)

        let firstClient = try makeClient(diagnostics: diagnostics, envelope: envelope)
        let firstStore = PokemonCatalogReleaseStore(root: root)
        let firstCoordinator = PokemonCatalogCoordinator(
            store: firstStore,
            client: firstClient,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )
        guard case .activated = await firstCoordinator.refresh() else {
            return XCTFail("Expected initial revision-1 activation")
        }

        let freshClient = try makeClient(diagnostics: diagnostics, envelope: envelope)
        let freshStore = PokemonCatalogReleaseStore(root: root)
        let freshCoordinator = PokemonCatalogCoordinator(
            store: freshStore,
            client: freshClient,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )

        guard case .notModified = await freshCoordinator.refresh() else {
            return XCTFail("Expected the identical current envelope to be notModified")
        }

        let revision = await freshCoordinator.revision
        let storeRevision = await freshStore.activeRevision
        let previousExists = await freshStore.slotFileExists(.previous)
        XCTAssertEqual(revision, 1)
        XCTAssertEqual(storeRevision, 1)
        XCTAssertFalse(previousExists)

        let snapshot = await diagnostics.snapshot()
        XCTAssertEqual(snapshot.rejectionCount, 0)
        XCTAssertEqual(snapshot.activationCount, 1)
        XCTAssertEqual(snapshot.lastOutcome, "not-modified")
    }

    func testLowerRevisionIsRejectedWithoutRotatingCurrent() async throws {
        let diagnostics = PokemonCatalogRolloutDiagnostics()
        await diagnostics.reset()
        let currentEnvelope = try SliceFFixture.envelope(revision: 2)

        let firstClient = try makeClient(diagnostics: diagnostics, envelope: currentEnvelope)
        let firstStore = PokemonCatalogReleaseStore(root: root)
        let firstCoordinator = PokemonCatalogCoordinator(
            store: firstStore,
            client: firstClient,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )
        guard case .activated = await firstCoordinator.refresh() else {
            return XCTFail("Expected initial revision-2 activation")
        }

        let lowerEnvelope = try SliceFFixture.envelope(revision: 1)
        let freshClient = try makeClient(diagnostics: diagnostics, envelope: lowerEnvelope)
        let freshStore = PokemonCatalogReleaseStore(root: root)
        let freshCoordinator = PokemonCatalogCoordinator(
            store: freshStore,
            client: freshClient,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )

        guard case .rejected = await freshCoordinator.refresh() else {
            return XCTFail("Expected a lower revision to be rejected")
        }

        let revision = await freshCoordinator.revision
        let storeRevision = await freshStore.activeRevision
        let previousExists = await freshStore.slotFileExists(.previous)
        XCTAssertEqual(revision, 2)
        XCTAssertEqual(storeRevision, 2)
        XCTAssertFalse(previousExists)

        let snapshot = await diagnostics.snapshot()
        XCTAssertEqual(snapshot.rejectionCount, 1)
        XCTAssertEqual(snapshot.activationCount, 1)
    }

    func testSameRevisionDifferentEnvelopeIsRejectedWithoutRotation() async throws {
        let diagnostics = PokemonCatalogRolloutDiagnostics()
        await diagnostics.reset()
        let currentEnvelope = try SliceFFixture.envelope(revision: 1, officialCount: 2)

        let firstClient = try makeClient(diagnostics: diagnostics, envelope: currentEnvelope)
        let firstStore = PokemonCatalogReleaseStore(root: root)
        let firstCoordinator = PokemonCatalogCoordinator(
            store: firstStore,
            client: firstClient,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )
        guard case .activated = await firstCoordinator.refresh() else {
            return XCTFail("Expected initial revision-1 activation")
        }

        let conflictingEnvelope = try SliceFFixture.envelope(revision: 1, officialCount: 3)
        let freshClient = try makeClient(diagnostics: diagnostics, envelope: conflictingEnvelope)
        let freshStore = PokemonCatalogReleaseStore(root: root)
        let freshCoordinator = PokemonCatalogCoordinator(
            store: freshStore,
            client: freshClient,
            keys: [SliceFFixture.pinnedKey],
            rolloutMode: .remoteAuthority,
            diagnostics: diagnostics
        )

        guard case .rejected = await freshCoordinator.refresh() else {
            return XCTFail("Expected a conflicting same-revision envelope to be rejected")
        }

        let stored = await freshStore.activeRelease
        let previousExists = await freshStore.slotFileExists(.previous)
        XCTAssertEqual(stored?.envelope, currentEnvelope)
        XCTAssertFalse(previousExists)

        let snapshot = await diagnostics.snapshot()
        XCTAssertEqual(snapshot.rejectionCount, 1)
        XCTAssertEqual(snapshot.activationCount, 1)
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

    func testRefreshRejectsBeforeFetchingWhenPinnedKeysAreMissing() async throws {
        let diagnostics = PokemonCatalogRolloutDiagnostics()
        await diagnostics.reset()
        let envelope = try SliceFFixture.envelope()
        let client = try makeClient(diagnostics: diagnostics, envelope: envelope)
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            client: client,
            keys: [],
            rolloutMode: .bundledValidationOnly,
            diagnostics: diagnostics
        )

        let result = await coordinator.refresh()
        guard case .rejected(let error) = result,
              let verificationError = error as? PokemonCatalogSignatureVerifier.VerificationError,
              case .noPinnedKeysConfigured = verificationError else {
            return XCTFail("Expected a noPinnedKeysConfigured rejection, got \(result)")
        }

        let snapshot = await diagnostics.snapshot()
        XCTAssertEqual(snapshot.rejectionCount, 1)
        XCTAssertEqual(snapshot.networkRequestCount, 0)
    }

    func testCatalogConfigurationsProvideKeysForVerifyingModes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configDirectory = repositoryRoot.appendingPathComponent("Config", isDirectory: true)
        let configURLs = try FileManager.default.contentsOfDirectory(
            at: configDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "xcconfig" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(configURLs.isEmpty)

        let verifyingModes: [String: Set<String>] = [
            "POKEMON_CATALOG_ROLLOUT_MODE": [
                PokemonCatalogRolloutMode.bundledValidationOnly.rawValue,
                PokemonCatalogRolloutMode.remoteAuthority.rawValue
            ],
            "MAGIC_CATALOG_ROLLOUT_MODE": [
                MagicCatalogRolloutMode.remoteValidationOnly.rawValue,
                MagicCatalogRolloutMode.remoteAuthority.rawValue
            ]
        ]
        let pinnedKeyForMode = [
            "POKEMON_CATALOG_ROLLOUT_MODE": "POKEMON_CATALOG_PINNED_KEYS",
            "MAGIC_CATALOG_ROLLOUT_MODE": "MAGIC_CATALOG_PINNED_KEYS"
        ]

        for configURL in configURLs {
            var visited = Set<URL>()
            let settings = try effectiveXCConfigSettings(at: configURL, visited: &visited)

            for (modeKey, modes) in verifyingModes {
                guard let mode = settings[modeKey], modes.contains(mode) else { continue }
                let keyValue = settings[pinnedKeyForMode[modeKey]!]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                XCTAssertFalse(
                    keyValue?.isEmpty ?? true,
                    "\(configURL.lastPathComponent) enables \(mode) with no pinned keys"
                )
                XCTAssertFalse(
                    keyValue?.contains("$(") ?? true,
                    "\(configURL.lastPathComponent) leaves pinned keys unresolved"
                )
            }
        }

        let debugLocalURL = configDirectory.appendingPathComponent(
            "PokemonCatalogDebugLocal.xcconfig"
        )
        var debugLocalVisited = Set<URL>()
        let debugLocalSettings = try effectiveXCConfigSettings(
            at: debugLocalURL,
            visited: &debugLocalVisited
        )
        XCTAssertEqual(
            debugLocalSettings[PokemonCatalogRolloutMode.infoPlistKey],
            PokemonCatalogRolloutMode.remoteAuthority.rawValue,
            "The normal local Debug configuration must activate the signed remote catalog"
        )

        let projectFileURL = repositoryRoot
            .appendingPathComponent("TradingCardScanner.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.pbxproj")
        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)
        let xcBuildConfigurationSection = try XCTUnwrap(
            projectSection(
                in: projectContents,
                begin: "/* Begin XCBuildConfiguration section */",
                end: "/* End XCBuildConfiguration section */"
            )
        )
        XCTAssertFalse(
            xcBuildConfigurationSection.contains("POKEMON_CATALOG_"),
            "Pokemon catalog settings must come from xcconfig files, not project.pbxproj"
        )
        XCTAssertFalse(
            xcBuildConfigurationSection.contains("MAGIC_CATALOG_"),
            "Magic catalog settings must come from xcconfig files, not project.pbxproj"
        )

        let appConfigurationList = try XCTUnwrap(
            projectObjectBody(
                in: projectContents,
                marker: "/* Build configuration list for PBXNativeTarget \"TradingCardScanner\" */ = {"
            )
        )
        let appConfigurationIDs = appConfigurationList
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.contains("/*"), trimmed.hasSuffix(",") else { return nil }
                return trimmed.split(separator: " ", maxSplits: 1).first.map(String.init)
            }
        XCTAssertFalse(appConfigurationIDs.isEmpty)

        for configurationID in appConfigurationIDs {
            let body = try XCTUnwrap(
                projectObjectBody(
                    in: xcBuildConfigurationSection,
                    marker: "\(configurationID) /*"
                )
            )
            XCTAssertTrue(
                body.contains("baseConfigurationReference ="),
                "App configuration \(configurationID) must inherit an xcconfig"
            )
        }
    }

    private func projectSection(in contents: String, begin: String, end: String) -> String? {
        guard let beginRange = contents.range(of: begin),
              let endRange = contents.range(of: end, range: beginRange.upperBound..<contents.endIndex) else {
            return nil
        }
        return String(contents[beginRange.upperBound..<endRange.lowerBound])
    }

    private func projectObjectBody(in contents: String, marker: String) -> String? {
        guard let objectStart = contents.range(of: marker),
              let lineEnd = contents.range(
                  of: "\n",
                  range: objectStart.upperBound..<contents.endIndex
              ) else {
            return nil
        }
        let declaration = contents[objectStart.lowerBound..<lineEnd.lowerBound]
        guard declaration.contains(" = {") else { return nil }
        let bodyStart = lineEnd.upperBound
        guard let bodyEnd = contents.range(
            of: "\n\t\t};",
            range: bodyStart..<contents.endIndex
        ) else {
            return nil
        }
        return String(contents[bodyStart..<bodyEnd.lowerBound])
    }

    private func effectiveXCConfigSettings(
        at url: URL,
        visited: inout Set<URL>
    ) throws -> [String: String] {
        let normalizedURL = url.standardizedFileURL
        guard visited.insert(normalizedURL).inserted else { return [:] }

        let contents = try String(contentsOf: normalizedURL, encoding: .utf8)
        var settings: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//") else { continue }

            if line.hasPrefix("#include") {
                let quotedParts = line.split(separator: "\"", omittingEmptySubsequences: false)
                guard quotedParts.count >= 3 else { continue }
                let includeURL = normalizedURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(String(quotedParts[1]))
                let includedSettings = try effectiveXCConfigSettings(
                    at: includeURL,
                    visited: &visited
                )
                settings.merge(includedSettings) { _, includedValue in includedValue }
                continue
            }

            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            settings[String(key)] = String(value)
        }
        return settings
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
