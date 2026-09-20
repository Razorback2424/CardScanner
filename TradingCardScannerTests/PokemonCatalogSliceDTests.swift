import CryptoKit
import XCTest
@testable import TradingCardScanner

private enum SliceDFixture {
    static let keyID = "slice-d-test-key"
    static let privateKey = Curve25519.Signing.PrivateKey()

    static var pinnedKey: PokemonCatalogSignatureVerifier.PinnedKey {
        .init(id: keyID, publicKey: privateKey.publicKey)
    }

    static func descriptor(
        providerSetID: String = "sv99",
        printedCode: String = "TST",
        officialCount: Int = 1,
        releaseOrder: Int = 7,
        displayName: String = "Signed Test Set",
        logoURL: String? = "https://catalog.example/logo.png",
        symbolURL: String? = "https://catalog.example/symbol.png"
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerSetID,
            displayName: displayName,
            releaseDate: "2026-01-01",
            releaseOrder: releaseOrder,
            recognitionKind: .expansion,
            printedCode: printedCode,
            officialCount: officialCount,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: true,
            logoURL: logoURL,
            symbolURL: symbolURL,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
        )
    }

    static func release(
        revision: Int,
        descriptors: [PokemonCatalogSetDescriptor]
    ) -> PokemonCatalogRelease {
        PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: descriptors
        )
    }

    static func signedEnvelope(
        revision: Int,
        descriptors: [PokemonCatalogSetDescriptor]
    ) throws -> PokemonCatalogReleaseEnvelope {
        try PokemonCatalogSignatureVerifier.sign(
            release: release(revision: revision, descriptors: descriptors),
            privateKey: privateKey,
            keyID: keyID
        )
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SliceDTest-\(UUID().uuidString)", isDirectory: true)
    }

    static func row(id: String = "sv99", name: String = "Provider Set") throws -> TCGdexBrowseSet {
        try decode(TCGdexBrowseSet.self, """
        {
          "id": "\(id)",
          "name": "\(name)",
          "logo": "https://provider.example/logo",
          "symbol": "https://provider.example/symbol",
          "cardCount": {"total": 1, "official": 1, "normal": 1, "reverse": 0, "holo": 0, "firstEd": 0}
        }
        """)
    }

    static func provider() throws -> TCGdexSetCatalog {
        try decode(TCGdexSetCatalog.self, """
        {
          "id": "sv99",
          "name": "Provider Set",
          "cards": [{"id": "sv99-001", "localId": "001", "name": "Test Card", "image": "https://images.example/sv99-001"}],
          "logo": "https://provider.example/logo",
          "symbol": "https://provider.example/symbol",
          "releaseDate": "2026-01-01",
          "tcgOnline": null,
          "cardCount": {"total": 1, "official": 1, "normal": 1, "reverse": 0, "holo": 0, "firstEd": 0}
        }
        """)
    }

    static func card() throws -> TCGdexCard {
        try decode(TCGdexCard.self, """
        {
          "id": "sv99-001",
          "localId": "001",
          "name": "Test Card",
          "image": "https://images.example/sv99-001",
          "rarity": "Common",
          "set": {"id": "sv99", "name": "Provider Set", "cardCount": {"total": 1, "official": 1}},
          "variants": {"firstEdition": false, "holo": false, "normal": true, "reverse": false, "wPromo": false}
        }
        """)
    }

    static func snapshot(providerFingerprint: String = "slice-d-fixture") -> PokemonChecklistSnapshot {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv99"),
            name: "Signed Test Set",
            code: "TST",
            logoURL: URL(string: "https://catalog.example/logo.png"),
            symbolURL: URL(string: "https://catalog.example/symbol.png"),
            cardCount: 1,
            releaseDate: Date(timeIntervalSince1970: 1_767_225_600),
            sortRank: 7
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv99-001",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Test Card",
            collectorNumber: "001",
            thumbnailURL: URL(string: "https://images.example/sv99-001/low.png"),
            imageURL: URL(string: "https://images.example/sv99-001/high.png"),
            masterSetVariant: .normal,
            isSoleSlotForCard: true
        )
        let entry = PokemonChecklistSnapshotEntry(
            set: set,
            providerID: "sv99",
            providerFingerprint: providerFingerprint,
            officialCount: 1,
            standardSlotCount: 1,
            expandedSlotCount: 1,
            resource: "sets/sv99.json"
        )
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            directoryFingerprint: providerFingerprint,
            entries: [entry]
        )
        return PokemonChecklistSnapshot(
            manifest: manifest,
            checklists: [set.id: [summary]]
        )
    }

    static func coordinator(root: URL, descriptors: [PokemonCatalogSetDescriptor]) async throws -> PokemonCatalogCoordinator {
        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            client: PokemonCatalogUpdateClient(baseURL: URL(string: "https://catalog.example")!),
            keys: [pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()
        let revision = 1
        let envelope = try signedEnvelope(revision: revision, descriptors: descriptors)
        guard case .activated = await coordinator.activateEnvelope(envelope) else {
            throw SliceDTestError.activationFailed
        }
        return coordinator
    }
}

private enum SliceDTestError: Error {
    case activationFailed
    case missingSet(String)
    case missingCard(String)
    case failed
}

private actor SliceDTransport: PokemonBrowseTransport {
    private let rows: [TCGdexBrowseSet]
    private let sets: [String: TCGdexSetCatalog]
    private let cards: [String: TCGdexCard]
    private let shouldFailSetRequests: Bool
    private var setRequestIDs: [String: Int] = [:]

    init(
        rows: [TCGdexBrowseSet],
        sets: [String: TCGdexSetCatalog] = [:],
        cards: [String: TCGdexCard] = [:],
        shouldFailSetRequests: Bool = false
    ) {
        self.rows = rows
        self.sets = sets
        self.cards = cards
        self.shouldFailSetRequests = shouldFailSetRequests
    }

    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        rows
    }

    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        let key = id.lowercased()
        setRequestIDs[key, default: 0] += 1
        if shouldFailSetRequests { throw SliceDTestError.failed }
        guard let value = sets[key] else { throw SliceDTestError.missingSet(id) }
        return value
    }

    func fetchCard(id: String) async throws -> TCGdexCard {
        guard let value = cards[id.lowercased()] else { throw SliceDTestError.missingCard(id) }
        return value
    }

    func setRequestCount(_ id: String) -> Int {
        setRequestIDs[id.lowercased(), default: 0]
    }
}

final class PokemonCatalogSliceDTests: XCTestCase {
    func testProductionBrowseUsesRegistryAndPublishesAuthorizedContent() async throws {
        let root = SliceDFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = SliceDFixture.descriptor()
        let coordinator = try await SliceDFixture.coordinator(
            root: root.appendingPathComponent("releases"),
            descriptors: [descriptor]
        )
        let authorizedRow = try SliceDFixture.row()
        let unknownRow = try SliceDFixture.row(id: "sv-new", name: "Pending Provider Set")
        let transport = SliceDTransport(
            rows: [authorizedRow, unknownRow],
            sets: ["sv99": try SliceDFixture.provider()],
            cards: ["sv99-001": try SliceDFixture.card()]
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(
                root: root.appendingPathComponent("checklists"),
                bundle: nil
            ),
            catalogCoordinator: coordinator
        )

        await catalog.refreshCatalogNow()
        let sets = try await catalog.sets(for: .pokemon)
        let set = try XCTUnwrap(sets.first)
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(set.providerID, "sv99")
        XCTAssertEqual(set.name, "Signed Test Set")
        XCTAssertEqual(set.code, "TST")
        XCTAssertEqual(set.cardCount, 1)
        XCTAssertEqual(set.logoURL, descriptor.logoURL.flatMap(URL.init(string:)))
        XCTAssertEqual(set.symbolURL, descriptor.symbolURL.flatMap(URL.init(string:)))

        let page = try await catalog.cards(in: set, cursor: nil)
        let card = try XCTUnwrap(page.items.first)
        XCTAssertEqual(card.name, "Test Card")
        XCTAssertEqual(card.setCode, "TST")
        XCTAssertEqual(card.imageURL, URL(string: "https://images.example/sv99-001/high.png"))
        let unknownSetRequests = await transport.setRequestCount("sv-new")
        let browseRevision = await catalog.activeCatalogRevision()
        let coordinatorRevision = await coordinator.revision
        XCTAssertEqual(unknownSetRequests, 0)
        XCTAssertEqual(browseRevision, coordinatorRevision)
    }

    func testProviderOnlyDiscoveryUsesPendingCodeAndNeverActivates() throws {
        let row = try SliceDFixture.row(id: "sv-new", name: "Pending Provider Set")
        let registry = PokemonCatalogRegistry(
            release: SliceDFixture.release(
                revision: 1,
                descriptors: [SliceDFixture.descriptor()]
            )
        )

        let sets = PokemonMasterSetChecklistBuilder.baseSets(from: [row], registry: registry)
        let set = try XCTUnwrap(sets.first)
        XCTAssertEqual(set.code, "Code pending")
        XCTAssertNotEqual(set.code, "SV-NEW")
        XCTAssertNil(registry.descriptor(forProviderSetID: set.providerID))
    }

    func testFailedProviderRefreshPreservesPreviousBrowseDirectory() async throws {
        let root = SliceDFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = try await SliceDFixture.coordinator(
            root: root.appendingPathComponent("releases"),
            descriptors: [SliceDFixture.descriptor()]
        )
        let store = PokemonChecklistStore(
            root: root.appendingPathComponent("checklists"),
            bundle: nil
        )
        try await store.publish(SliceDFixture.snapshot())
        let transport = SliceDTransport(
            rows: [try SliceDFixture.row()],
            shouldFailSetRequests: true
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store,
            catalogCoordinator: coordinator
        )

        let before = try await catalog.sets(for: .pokemon)
        await catalog.refreshCatalogNow()
        let after = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(after, before)
        let setRequests = await transport.setRequestCount("sv99")
        XCTAssertEqual(setRequests, 1)
    }

    func testSignedProviderFingerprintReconcilesOnlyTheStaleChecklist() async throws {
        let root = SliceDFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = try SliceDFixture.provider()
        let card = try SliceDFixture.card()
        let desiredFingerprint = try XCTUnwrap(
            PokemonMasterSetChecklistBuilder.canonicalFingerprint(
                of: provider,
                cardDetails: [card.id: card]
            )
        )
        let descriptor = SliceDFixture.descriptor()
            .withProviderFingerprint(desiredFingerprint)
        let coordinator = try await SliceDFixture.coordinator(
            root: root.appendingPathComponent("releases"),
            descriptors: [descriptor]
        )
        let checklistStore = PokemonChecklistStore(
            root: root.appendingPathComponent("checklists"),
            bundle: nil
        )
        try await checklistStore.publish(
            SliceDFixture.snapshot(providerFingerprint: "legacy-probe-only")
        )
        let transport = SliceDTransport(
            rows: [try SliceDFixture.row()],
            sets: ["sv99": provider],
            cards: [card.id: card]
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: checklistStore,
            catalogCoordinator: coordinator
        )

        await catalog.refreshCatalogNow()

        let entries = await checklistStore.mergedEntries()
        let entry = try XCTUnwrap(entries.first {
            $0.providerID.caseInsensitiveCompare("sv99") == .orderedSame
        })
        XCTAssertEqual(entry.providerFingerprint, desiredFingerprint)
        let dueTargets = await checklistStore.dueReconciliationTargets()
        XCTAssertEqual(dueTargets.count, 0)
        let page = try await catalog.cards(in: entry.set, cursor: nil)
        XCTAssertEqual(page.items.count, 1)
        let setRequestCount = await transport.setRequestCount("sv99")
        XCTAssertGreaterThanOrEqual(setRequestCount, 1)
    }

    func testReconciliationQueuePreservesIndependentFullSweepTimestamp() async throws {
        let root = SliceDFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root, bundle: nil)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        await store.markRefreshSucceeded(at: now)
        let initiallyNeedsSweep = await store.needsFullSweep(
            now: now.addingTimeInterval(1)
        )
        XCTAssertFalse(initiallyNeedsSweep)
        let targets = await store.synchronizeReconciliationTargets(
            desiredFingerprints: ["sv99": "signed-target"],
            at: now.addingTimeInterval(1)
        )
        XCTAssertEqual(targets.map(\.providerSetID), ["sv99"])
        let needsSweepAfterQueue = await store.needsFullSweep(
            now: now.addingTimeInterval(1)
        )
        XCTAssertFalse(needsSweepAfterQueue)
        await store.markReconciliationFailure(
            providerSetID: "sv99",
            desiredFingerprint: "signed-target",
            at: now.addingTimeInterval(1)
        )
        let dueAfterFailure = await store.dueReconciliationTargets(
            now: now.addingTimeInterval(2)
        )
        XCTAssertFalse(dueAfterFailure.contains {
            $0.providerSetID == "sv99"
        })
        let needsSweepAfterFailure = await store.needsFullSweep(
            now: now.addingTimeInterval(2)
        )
        XCTAssertFalse(needsSweepAfterFailure)
    }

    func testOlderReconciliationFailureCannotOverwriteNewerSignedTarget() async {
        let root = SliceDFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root, bundle: nil)

        _ = await store.synchronizeReconciliationTargets(
            desiredFingerprints: ["sv99": "old-target"]
        )
        _ = await store.synchronizeReconciliationTargets(
            desiredFingerprints: ["sv99": "new-target"]
        )
        await store.markReconciliationFailure(
            providerSetID: "sv99",
            desiredFingerprint: "old-target"
        )

        let targets = await store.dueReconciliationTargets()
        XCTAssertEqual(targets.map(\.desiredFingerprint), ["new-target"])
    }

    func testRollbackUsesRegistryOrderingAndRemovesLegacyUserDefaultsAuthority() async throws {
        let key = "pokemonCatalogReleaseOrder.v1"
        UserDefaults.standard.set(["sv99": 999], forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let root = SliceDFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let releaseOne = SliceDFixture.descriptor(releaseOrder: 7)
        let coordinator = try await SliceDFixture.coordinator(
            root: root.appendingPathComponent("releases"),
            descriptors: [releaseOne]
        )
        let store = PokemonChecklistStore(
            root: root.appendingPathComponent("checklists"),
            bundle: nil
        )
        try await store.publish(SliceDFixture.snapshot())
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: SliceDTransport(rows: []),
            checklistStore: store,
            catalogCoordinator: coordinator
        )

        let initial = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(initial.first?.sortRank, 7)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))

        let rollback = SliceDFixture.descriptor(releaseOrder: 2)
        let rollbackEnvelope = try SliceDFixture.signedEnvelope(
            revision: 2,
            descriptors: [rollback]
        )
        guard case .activated = await coordinator.activateEnvelope(rollbackEnvelope) else {
            return XCTFail("Rollback release was not activated")
        }

        let restored = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(restored.first?.sortRank, 2)
        let browseRevision = await catalog.activeCatalogRevision()
        let coordinatorRevision = await coordinator.revision
        XCTAssertEqual(browseRevision, coordinatorRevision)
    }
}
