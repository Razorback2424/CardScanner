import CryptoKit
import struct PokemonCatalogCore.PokemonCatalogHumanInput
import XCTest
@testable import TradingCardScanner

private enum SliceCFixture {
    static let keyID = "slice-c-test-key"
    static let privateKey = Curve25519.Signing.PrivateKey()

    static var pinnedKey: PokemonCatalogSignatureVerifier.PinnedKey {
        .init(id: keyID, publicKey: privateKey.publicKey)
    }

    static func descriptor(
        providerSetID: String = "sv99",
        printedCode: String = "TST",
        officialCount: Int = 100,
        releaseOrder: Int = 99,
        displayName: String = "Test Set",
        scanEnabled: Bool = true
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
            scanEnabled: scanEnabled,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
        )
    }

    static func registry(
        revision: Int = 1,
        descriptors: [PokemonCatalogSetDescriptor]? = nil
    ) -> PokemonCatalogRegistry {
        PokemonCatalogRegistry(
            release: PokemonCatalogRelease(
                schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
                revision: revision,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sets: descriptors ?? [descriptor()]
            )
        )
    }

    static func signedEnvelope(
        registry: PokemonCatalogRegistry,
        revision: Int
    ) throws -> PokemonCatalogReleaseEnvelope {
        let release = PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: registry.descriptors
        )
        return try PokemonCatalogSignatureVerifier.sign(
            release: release,
            privateKey: privateKey,
            keyID: keyID
        )
    }

    static func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SliceCTest-\(UUID().uuidString)", isDirectory: true)
    }

    static func historicalFixture() -> (
        snapshot: PokemonChecklistSnapshot,
        evidence: PokemonHistoricalScanEvidence,
        set: CatalogSet
    ) {
        let setID = CatalogSetID(game: .pokemon, providerID: "sv99")
        let set = CatalogSet(
            catalogID: setID,
            name: "Test Set",
            code: "TST",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 100,
            releaseDate: nil,
            sortRank: 99
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv99-001",
            setID: setID,
            setName: set.name,
            setCode: set.code,
            name: "Test Card",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil
        )
        let entry = PokemonChecklistSnapshotEntry(
            set: set,
            providerID: "sv99",
            providerFingerprint: "slice-c-fixture",
            officialCount: 100,
            standardSlotCount: 100,
            expandedSlotCount: 100,
            resource: "sv99.json"
        )
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            directoryFingerprint: "slice-c-fixture",
            entries: [entry]
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: manifest,
            checklists: [set.id: [summary]]
        )
        let evidence = PokemonHistoricalScanEvidence(
            number: PokemonPrintedNumberEvidence(
                localID: "001",
                denominator: 100,
                scheme: .officialSet
            ),
            titleCandidates: ["test card"]
        )
        return (snapshot, evidence, set)
    }
}

@MainActor
final class PokemonCatalogSliceCTests: XCTestCase {
    func testBundled30thAuthorityMatchesPublisherInput() throws {
        struct Input: Decodable {
            let sets: [PokemonCatalogHumanInput]
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let input = try JSONDecoder().decode(
            Input.self,
            from: Data(contentsOf: repositoryRoot.appendingPathComponent("publisher/catalog-input.json"))
        )
        let registry = PokemonCatalogRegistry.bundledSeed
        let parentInput = try XCTUnwrap(input.sets.first { $0.providerSetID == "30th" })
        let parent = try XCTUnwrap(registry.descriptor(forProviderSetID: "30th"))
        XCTAssertEqual(parent.printedCode, parentInput.printedCode)
        XCTAssertEqual(parent.officialCount, parentInput.claimedOfficialCount)
        XCTAssertEqual(parent.releaseOrder, parentInput.releaseOrder)
        XCTAssertEqual(parent.recognitionKind, .expansion)
        XCTAssertTrue(parent.scanEnabled)
        XCTAssertEqual(registry.expansion(forPrintedCode: "30C")?.providerSetID, "30th")

        let classicInput = try XCTUnwrap(input.sets.first { $0.providerSetID == "30th-c" })
        let classic = try XCTUnwrap(registry.descriptor(forProviderSetID: "30th-c"))
        XCTAssertEqual(classic.parentProviderSetID, classicInput.parentProviderSetID)
        let bundledMembers = try XCTUnwrap(classic.membershipRecognition?.members)
        let publisherMembers = try XCTUnwrap(classicInput.membershipRecognition?.members)
        XCTAssertEqual(bundledMembers.count, 30)
        XCTAssertEqual(
            bundledMembers.sorted { $0.providerCardID < $1.providerCardID },
            publisherMembers.sorted { $0.providerCardID < $1.providerCardID }
        )
        XCTAssertEqual(registry.printedCode(forProviderSetID: "30th-c"), "30C")
        XCTAssertFalse(classic.scanEnabled)
    }

    func testFirstLaunchClassicChoiceRequiresChecklistBeforeOfflineResolution() async throws {
        let root = SliceCFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root)
        let bundled = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(bundled)
        let registry = PokemonCatalogRegistry.bundledSeed
        let number = PokemonPrintedNumberEvidence(localID: "58", denominator: 102, scheme: .officialSet)
        let candidate = try XCTUnwrap(PokemonHistoricalIdentityResolver.membershipIdentities(
            for: number,
            in: registry
        ).first { $0.providerID == "30th-c-014" })
        XCTAssertFalse(snapshot.manifest.entries.contains { $0.providerID == "30th-c" })
        XCTAssertNil(PokemonOfflineCardFactory.card(
            in: snapshot,
            candidate: candidate,
            number: number,
            registry: registry
        ))
    }

    func testBundledClassicPikachuKeepsBaseSetScanAmbiguousAndAvailableAsChoice() {
        let registry = PokemonCatalogRegistry.bundledSeed
        let number = PokemonPrintedNumberEvidence(
            localID: "58",
            denominator: 102,
            scheme: .officialSet
        )
        let evidence = PokemonHistoricalScanEvidence(
            number: number,
            titleCandidates: ["pikachu"]
        )
        let classic = PokemonHistoricalIdentityResolver.membershipIdentities(
            for: evidence,
            in: registry
        )
        XCTAssertEqual(
            registry.membershipRecognition(forProviderSetID: "30th-c")?.members.count,
            30
        )
        XCTAssertEqual(classic.map(\.providerID), ["30th-c-014"])
        XCTAssertEqual(classic.first?.choiceLabel, "30th Classic · 2026")

        let setID = CatalogSetID(game: .pokemon, providerID: "base1")
        let set = CatalogSet(
            catalogID: setID,
            name: "Base Set — Unlimited",
            code: "BS",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 102,
            releaseDate: nil,
            sortRank: 1
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "base1-58",
            setID: setID,
            setName: set.name,
            setCode: set.code,
            name: "Pikachu",
            collectorNumber: "58",
            thumbnailURL: nil,
            imageURL: nil
        )
        let entry = PokemonChecklistSnapshotEntry(
            set: set,
            providerID: "base1",
            providerFingerprint: "base-fixture",
            officialCount: 102,
            standardSlotCount: 102,
            expandedSlotCount: 102,
            resource: "base1.json"
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "base-fixture",
                entries: [entry]
            ),
            checklists: [set.id: [summary]]
        )

        XCTAssertNil(PokemonOfflineCardFactory.historicalCard(
            in: snapshot,
            evidence: evidence,
            registry: registry
        ))
        XCTAssertEqual(
            PokemonOfflineCardFactory.candidates(
                in: snapshot,
                number: number,
                registry: registry
            ).map(\.providerID),
            ["30th-c-014", "base1-58"]
        )
    }

    func testSelectedClassicPikachuResolvesFromOfflineChecklistUsingMembershipNumber() throws {
        let registry = PokemonCatalogRegistry.bundledSeed
        let number = PokemonPrintedNumberEvidence(
            localID: "58",
            denominator: 102,
            scheme: .officialSet
        )
        let candidate = try XCTUnwrap(PokemonHistoricalIdentityResolver.membershipIdentities(
            for: number,
            in: registry
        ).first { $0.providerID == "30th-c-014" })
        let setID = CatalogSetID(game: .pokemon, providerID: "30th-c")
        let set = CatalogSet(
            catalogID: setID,
            name: candidate.setName,
            code: "30C",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 30,
            releaseDate: nil,
            sortRank: 1
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "30th-c-014",
            setID: setID,
            setName: set.name,
            setCode: set.code,
            name: "Pikachu",
            collectorNumber: "014",
            thumbnailURL: nil,
            imageURL: nil
        )
        let entry = PokemonChecklistSnapshotEntry(
            set: set,
            providerID: "30th-c",
            providerFingerprint: "classic-fixture",
            officialCount: 30,
            standardSlotCount: 30,
            expandedSlotCount: 30,
            resource: "30th-c.json"
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "classic-fixture",
                entries: [entry]
            ),
            checklists: [set.id: [summary]]
        )

        guard case let .pokemon(card, setCode) = PokemonOfflineCardFactory.card(
            in: snapshot,
            candidate: candidate,
            number: number,
            registry: registry
        ) else {
            return XCTFail("Selected Classic Pikachu should resolve from its checklist row")
        }
        XCTAssertEqual(card.id, "30th-c-014")
        XCTAssertEqual(card.set.id, "30th-c")
        XCTAssertEqual(card.localId, "58")
        XCTAssertEqual(card.set.cardCount.official, 102)
        XCTAssertEqual(setCode, "30C")

        let wrongNumber = PokemonPrintedNumberEvidence(
            localID: "59",
            denominator: 102,
            scheme: .officialSet
        )
        XCTAssertNil(PokemonOfflineCardFactory.card(
            in: snapshot,
            candidate: candidate,
            number: wrongNumber,
            registry: registry
        ))
    }

    func test30thClassicCollectionSharesDisplayCodeWithoutClaimingScannerNamespace() {
        let expansion = SliceCFixture.descriptor(
            providerSetID: "30th",
            printedCode: "30C",
            officialCount: 128,
            releaseOrder: 22,
            displayName: "30th Celebration"
        )
        let classic = PokemonCatalogSetDescriptor(
            providerSetID: "30th-c",
            displayName: "30th Classic Collection",
            releaseDate: "2026-09-16",
            releaseOrder: 23,
            recognitionKind: .notScannable,
            printedCode: "30C",
            officialCount: nil,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: false,
            logoURL: nil,
            symbolURL: nil
        )
        let registry = SliceCFixture.registry(descriptors: [expansion, classic])

        XCTAssertEqual(registry.expansionCodes, ["30C"])
        XCTAssertEqual(registry.expansion(forPrintedCode: "30C")?.providerSetID, "30th")
        XCTAssertEqual(registry.printedCode(forProviderSetID: "30th-c"), "30C")
        XCTAssertFalse(registry.isScanEnabled(forProviderSetID: "30th-c"))

        let scanner = CardScanner()
        scanner.usePokemonRegistry(registry)
        scanner.drainProfileQueuesForTesting()
        guard case let .identified(subject) = scanner.recognitionOutcomeForTesting(["30C 001/128"]),
              case let .pokemon(_, _, _, definition) = subject.identifier else {
            return XCTFail("30C should resolve to the scannable 30th expansion")
        }
        XCTAssertEqual(definition.tcgdexSetID, "30th")
    }

    func testSignedActivationInstallsFixtureCodeWithoutRestart() async throws {
        let root = SliceCFixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = PokemonCatalogCoordinator(
            store: PokemonCatalogReleaseStore(root: root),
            client: PokemonCatalogUpdateClient(),
            keys: [SliceCFixture.pinnedKey]
        )
        await coordinator.loadPersistedOrBundled()

        let scanner = CardScanner()
        scanner.usePokemonRegistry(await coordinator.registry)
        scanner.drainProfileQueuesForTesting()
        XCTAssertEqual(scanner.recognitionOutcomeForTesting(["TST 001/100"]), .nothing)

        let events = await coordinator.activationEvents()
        let eventTask = Task { () -> PokemonCatalogCoordinator.ActivationEvent in
            for await event in events { return event }
            fatalError("Activation stream ended before the fixture event")
        }
        let release = SliceCFixture.registry(revision: 1)
        let envelope = try SliceCFixture.signedEnvelope(registry: release, revision: 1)
        let result = await coordinator.activateEnvelope(envelope)
        guard case .activated = result else {
            return XCTFail("Signed fixture release was not activated")
        }

        let event = await eventTask.value
        scanner.usePokemonRegistry(event.registry)
        scanner.drainProfileQueuesForTesting()

        guard case let .identified(subject) = scanner.recognitionOutcomeForTesting(["TST 001/100"]),
              case let .pokemon(code, localID, total, definition) = subject.identifier else {
            return XCTFail("Activated fixture code was not recognized")
        }
        XCTAssertEqual(code, "TST")
        XCTAssertEqual(localID, "001")
        XCTAssertEqual(total, 100)
        XCTAssertEqual(definition.tcgdexSetID, "sv99")
        XCTAssertTrue(scanner.customWordsForTesting.contains("TST"))
    }

    func testFixtureCodeIsRejectedBeforeActivationAndWhenDisabled() {
        let bundledProfile = PokemonScanProfile.bundledSeed
        XCTAssertNil(bundledProfile.parse(["TST 001/100"]))

        let scanner = CardScanner()
        scanner.usePokemonRegistry(SliceCFixture.registry())
        scanner.drainProfileQueuesForTesting()
        guard case .identified = scanner.recognitionOutcomeForTesting(["TST 001/100"]) else {
            return XCTFail("Enabled fixture should be recognized")
        }

        scanner.usePokemonRegistry(
            SliceCFixture.registry(
                revision: 2,
                descriptors: [SliceCFixture.descriptor(scanEnabled: false)]
            )
        )
        scanner.drainProfileQueuesForTesting()
        XCTAssertEqual(scanner.recognitionOutcomeForTesting(["TST 001/100"]), .nothing)
        XCTAssertFalse(scanner.customWordsForTesting.contains("TST"))
    }

    func testDisabledSetCannotMatchHistoricalDenominatorButRemainsBrowseVisible() {
        let fixture = SliceCFixture.historicalFixture()
        let enabled = SliceCFixture.registry()
        let disabled = SliceCFixture.registry(
            revision: 2,
            descriptors: [SliceCFixture.descriptor(scanEnabled: false)]
        )

        XCTAssertNotNil(
            PokemonOfflineCardFactory.historicalCard(
                in: fixture.snapshot,
                evidence: fixture.evidence,
                registry: enabled
            )
        )
        XCTAssertNil(
            PokemonOfflineCardFactory.historicalCard(
                in: fixture.snapshot,
                evidence: fixture.evidence,
                registry: disabled
            )
        )
        XCTAssertEqual(fixture.snapshot.sets.map(\.providerID), [fixture.set.providerID])
    }

    func testMetadataOnlyActivationPreservesConfirmationButVocabularyChangeResetsIt() {
        let v1 = SliceCFixture.registry(revision: 1)
        let v2 = SliceCFixture.registry(
            revision: 2,
            descriptors: [SliceCFixture.descriptor(displayName: "Renamed Test Set")]
        )
        let v3 = SliceCFixture.registry(
            revision: 3,
            descriptors: [
                SliceCFixture.descriptor(),
                SliceCFixture.descriptor(
                    providerSetID: "sv100",
                    printedCode: "NEW",
                    officialCount: 111,
                    releaseOrder: 100,
                    displayName: "New Test Set"
                )
            ]
        )

        let scanner = CardScanner()
        scanner.usePokemonRegistry(v1)
        scanner.drainProfileQueuesForTesting()
        XCTAssertNil(scanner.observeConfirmationForTesting(["TST 001/100"]))

        scanner.usePokemonRegistry(v2)
        scanner.drainProfileQueuesForTesting()
        XCTAssertNotNil(scanner.observeConfirmationForTesting(["TST 001/100"]))

        // Start a new partial window, then activate a materially different
        // vocabulary. The old observation must not combine with two readings
        // after the activation.
        scanner.usePokemonRegistry(v1)
        scanner.drainProfileQueuesForTesting()
        XCTAssertNil(scanner.observeConfirmationForTesting(["TST 001/100"]))
        scanner.usePokemonRegistry(v3)
        scanner.drainProfileQueuesForTesting()
        XCTAssertNil(scanner.observeConfirmationForTesting(["TST 001/100"]))
        XCTAssertNotNil(scanner.observeConfirmationForTesting(["TST 001/100"]))
    }

    func testDispatchedIdentifierRetainsTheDefinitionThatParsedIt() {
        let first = PokemonScanProfile(
            registry: SliceCFixture.registry()
        )
        let later = PokemonScanProfile(
            registry: SliceCFixture.registry(
                revision: 2,
                descriptors: [SliceCFixture.descriptor(officialCount: 101)]
            )
        )

        guard case let .pokemon(_, _, firstTotal, firstDefinition)? = first.parse("TST 001/100"),
              case let .pokemon(_, _, laterTotal, laterDefinition)? = later.parse("TST 001/101") else {
            return XCTFail("Fixture profiles did not produce their own identifiers")
        }
        XCTAssertEqual(firstTotal, 100)
        XCTAssertEqual(firstDefinition.officialCount, 100)
        XCTAssertEqual(laterTotal, 101)
        XCTAssertEqual(laterDefinition.officialCount, 101)
        XCTAssertNotEqual(firstDefinition, laterDefinition)
    }
}
