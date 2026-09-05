import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

private actor ScannerFetchGate {
    private var hasStarted = false
    private var waiter: CheckedContinuation<Void, Never>?

    func markStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        waiter?.resume()
        waiter = nil
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiter = continuation
        }
    }
}

private struct ScannerStubPokemonSource: PokemonCardSource {
    let cardsByLocalID: [String: TCGdexCard]
    let delayNanoseconds: UInt64
    let fetchGate: ScannerFetchGate?

    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        await fetchGate?.markStarted()
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let exact = cardsByLocalID[localID] {
            return exact
        }
        if let numeric = Int(localID),
           let normalized = cardsByLocalID.values.first(where: { Int($0.localId) == numeric }) {
            return normalized
        }
        return cardsByLocalID.values.first!
    }

    func fetchPokemonTCGCard(
        setID: String,
        cardNumber: String
    ) async throws -> PokemonTCGAPICard? {
        nil
    }
}

/// ScannerViewModel is the orchestration boundary for the camera, catalog,
/// persistence, and the choice sheets. These tests drive its callbacks directly
/// so the state-machine contracts can be checked without a camera or network.
@MainActor
final class ScannerViewModelTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testPendingChoiceBlocksLaterConfirmedEncounterUntilAnswer() async throws {
        let model = try makeModel(
            variants: [.normal, .holo],
            secondaryVariants: [.normal, .holo]
        )
        let identifier = scannerIdentifier()
        let secondIdentifier = scannerIdentifier(cardNumber: "002")
        let firstEncounter = UUID()
        let secondEncounter = UUID()

        confirm(model, identifier, encounterID: firstEncounter)
        let firstChoiceAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(firstChoiceAppeared)
        XCTAssertEqual(model.pendingChoice?.request.encounterID, firstEncounter)

        confirm(model, secondIdentifier, encounterID: secondEncounter)
        await settle()

        XCTAssertEqual(model.pendingChoice?.request.encounterID, firstEncounter)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertEqual(model.successCount, 0)

        model.choose(.normal)
        let firstCommitAfterAnswer = await waitUntil {
            model.recent.count == 1 && model.pendingChoice?.request.encounterID == secondEncounter
        }
        XCTAssertTrue(firstCommitAfterAnswer)
        XCTAssertEqual(model.pendingChoice?.identifier, secondIdentifier)
        XCTAssertEqual(model.pendingChoice?.card.id, "pokemon:test-set-002")

        model.choose(.normal)
        let secondCommitAfterAnswer = await waitUntil {
            model.recent.count == 2 && model.pendingChoice == nil
        }
        XCTAssertTrue(secondCommitAfterAnswer)
        XCTAssertEqual(model.successCount, 2)
    }

    func testAutomaticRouteCommitsCardAndLeavesNoPendingChoice() async throws {
        let model = try makeModel(variants: [.normal])

        confirm(model, scannerIdentifier(), encounterID: UUID())

        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.successCount, 1)
        XCTAssertEqual(model.recent.first?.resolved.variant, .normal)

        let cards = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.quantity, 1)
    }

    func testSameIdentityWithoutSpatialProofIsSuppressed() async throws {
        let model = try makeModel(variants: [.normal])
        let identifier = scannerIdentifier()

        confirm(model, identifier, encounterID: UUID())
        let firstCommit = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(firstCommit)

        confirm(model, identifier, encounterID: UUID())
        await settle()

        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(model.successCount, 1)
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertNil(model.pendingChoice)

        let cards = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.quantity, 1)
    }

    func testSpatialProofRoutesSameIdentityToDuplicateConfirmationAndSameCardDoesNotCommit() async throws {
        let model = try makeModel(variants: [.normal])
        let identifier = scannerIdentifier()
        let firstEncounter = UUID()
        let secondEncounter = UUID()

        confirm(model, identifier, encounterID: firstEncounter)
        let firstCommit = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(firstCommit)

        model.scanner.onSpatialResetProof?(
            SpatialResetProof(encounterID: firstEncounter)
        )
        await settle()
        confirm(model, identifier, encounterID: secondEncounter)

        let duplicatePromptAppeared = await waitUntil { model.pendingDuplicateConfirmation != nil }
        XCTAssertTrue(duplicatePromptAppeared)
        XCTAssertEqual(
            model.pendingDuplicateConfirmation?.encounterID,
            secondEncounter
        )
        XCTAssertEqual(model.recent.count, 1)

        model.chooseSameCard()
        await settle()

        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(model.successCount, 1)
    }

    func testSpatialProofAddAnotherCommitsSecondCopyToExistingPosition() async throws {
        let model = try makeModel(variants: [.normal])
        let identifier = scannerIdentifier()
        let firstEncounter = UUID()

        confirm(model, identifier, encounterID: firstEncounter)
        let firstCommit = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(firstCommit)

        model.scanner.onSpatialResetProof?(
            SpatialResetProof(encounterID: firstEncounter)
        )
        await settle()
        confirm(model, identifier, encounterID: UUID())
        let duplicatePromptAppeared = await waitUntil { model.pendingDuplicateConfirmation != nil }
        XCTAssertTrue(duplicatePromptAppeared)

        model.addAnother()
        let secondCommit = await waitUntil {
            model.recent.count == 2 && model.pendingDuplicateConfirmation == nil
        }
        XCTAssertTrue(secondCommit)
        XCTAssertEqual(model.successCount, 2)

        let cards = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.quantity, 2)
    }

    func testViewDisappearedInvalidatesLateCatalogCompletion() async throws {
        let fetchGate = ScannerFetchGate()
        let model = try makeModel(
            variants: [.normal],
            delayNanoseconds: 500_000_000,
            fetchGate: fetchGate
        )

        confirm(model, scannerIdentifier(), encounterID: UUID())
        await fetchGate.waitUntilStarted()
        model.viewDisappeared()

        try await Task.sleep(for: .milliseconds(650))

        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
    }

    func testChangingPurposeInvalidatesPendingCollectionChoice() async throws {
        let model = try makeModel(variants: [.normal, .holo])

        confirm(model, scannerIdentifier(), encounterID: UUID())
        let choiceAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(choiceAppeared)

        model.setPurpose(.priceCheck)

        XCTAssertEqual(model.purpose, .priceCheck)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingPrintRunChoice)
        XCTAssertTrue(model.recent.isEmpty)
    }

    func testPolicyRequiresMatchingSpatialEvidenceForDuplicateRouting() {
        let identity = ConsecutiveScanIdentity(canonicalID: "pokemon:test-set-001")
        let encounter = UUID()
        let presentation = UUID()
        let previous = CommittedSessionScan(
            id: UUID(),
            identity: identity,
            presentationToken: presentation,
            encounterID: encounter
        )

        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: identity,
                previous: previous,
                proofs: []
            ),
            .suppress
        )
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: identity,
                previous: previous,
                proofs: [SpatialResetProof(encounterID: UUID())]
            ),
            .suppress
        )

        let proof = SpatialResetProof(
            encounterID: UUID(),
            presentationToken: presentation
        )
        guard case .duplicate = CollectionCandidateRoutingPolicy.decision(
            for: identity,
            previous: previous,
            proofs: [proof]
        ) else {
            return XCTFail("matching presentation evidence should allow a duplicate prompt")
        }

        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: ConsecutiveScanIdentity(canonicalID: "pokemon:other"),
                previous: previous,
                proofs: []
            ),
            .automatic
        )
    }

    func testHeldDuplicateOfferDefersUntilItsEncounterCommits() {
        let identity = ConsecutiveScanIdentity(canonicalID: "pokemon:test-set-001")
        let encounter = UUID()
        let key = scannerIdentifier().suppressionKey
        let committed = CommittedSessionScan(
            id: UUID(),
            identity: identity,
            presentationToken: UUID(),
            encounterID: encounter
        )
        let entry = HeldDuplicatePublicationHistoryEntry(
            committed: committed,
            suppressionKey: key
        )

        XCTAssertEqual(
            HeldDuplicateOfferPublicationPolicy.decision(
                for: key,
                encounterID: UUID(),
                history: [entry]
            ),
            .deferUntilCommit
        )
        guard case .publish(let selected) = HeldDuplicateOfferPublicationPolicy.decision(
            for: key,
            encounterID: encounter,
            history: [entry]
        ) else {
            return XCTFail("a committed current encounter should publish the offer")
        }
        XCTAssertEqual(selected, entry)
    }

    func testSuppressionVerificationWindowRequiresThreeRecentMatches() {
        var window = SuppressionKeyVerificationWindow(matchesRequired: 3, windowSize: 5)
        let identifier = scannerIdentifier()
        let other = ScanIdentifier.pokemon(
            setCode: "TST",
            cardNumber: "002",
            printedTotal: 10,
            setDefinition: fixtureSetDefinition()
        )

        XCTAssertFalse(window.observe(identifier))
        XCTAssertFalse(window.observe(other))
        XCTAssertFalse(window.observe(identifier))
        XCTAssertTrue(window.observe(identifier))
        XCTAssertFalse(window.observe(identifier))
    }

    func testUnresolvedHistoricalReadingsMergeTitlesForOnePrintedNumber() {
        let number = PokemonPrintedNumberEvidence(
            localID: "004",
            denominator: 102,
            scheme: .officialSet
        )
        let first = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["CHARIZARD"])
        )
        let second = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: number,
                titleCandidates: ["CHARIZARD", "STAGE 2"]
            )
        )

        let merged = UnresolvedScan.merging(
            UnresolvedScan.merging([], with: first),
            with: second
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.titleCandidates, ["CHARIZARD", "STAGE 2"])
    }

    private func makeModel(
        variants: [PhysicalVariant],
        secondaryVariants: [PhysicalVariant]? = nil,
        delayNanoseconds: UInt64 = 0,
        fetchGate: ScannerFetchGate? = nil
    ) throws -> ScannerViewModel {
        let context = try makeContext()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TradingCardScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let checklistStore = PokemonChecklistStore(
            root: root,
            bundle: nil,
            bundledRoot: root
        )
        let catalog = CardCatalog(
            source: ScannerStubPokemonSource(
                cardsByLocalID: [
                    "001": catalogCard(variants: variants, localID: "001"),
                    "002": catalogCard(
                        variants: secondaryVariants ?? variants,
                        localID: "002"
                    )
                ],
                delayNanoseconds: delayNanoseconds,
                fetchGate: fetchGate
            ),
            offline: PokemonOfflineCatalog(store: checklistStore),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root,
                appVersion: "scanner-tests"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let model = ScannerViewModel(
            scanner: CardScanner(),
            catalog: catalog,
            feedback: ScanFeedback()
        )
        model.start(
            context: context,
            isSceneActive: true,
            startCamera: false,
            shouldRefreshMagicDirectory: false
        )
        return model
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            CollectionActivity.self,
            InventoryEvent.self,
            PriceObservation.self,
            PriceCheckDay.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func context() -> ModelContext {
        container!.mainContext
    }

    private func confirm(
        _ model: ScannerViewModel,
        _ identifier: ScanIdentifier,
        encounterID: UUID
    ) {
        model.scanner.onConfirmedCandidate?(encounterID, identifier, nil)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<600 {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func fixtureSetDefinition() -> PokemonSetDefinition {
        PokemonSetDefinition(
            printedCode: "TST",
            tcgdexSetID: "test-set",
            officialCount: 10,
            releaseIndex: 0
        )
    }

    private func scannerIdentifier(cardNumber: String = "001") -> ScanIdentifier {
        .pokemon(
            setCode: "TST",
            cardNumber: cardNumber,
            printedTotal: 10,
            setDefinition: fixtureSetDefinition()
        )
    }

    private func catalogCard(
        variants: [PhysicalVariant],
        localID: String
    ) -> TCGdexCard {
        TCGdexCard(
            id: "test-set-\(localID)",
            localId: localID,
            name: "Test Card",
            image: nil,
            rarity: "Common",
            set: TCGdexSetBrief(
                id: "test-set",
                name: "Test Set",
                cardCount: TCGdexCardCount(total: 10, official: 10)
            ),
            variants: TCGdexVariants(
                firstEdition: variants.contains(.firstEdition),
                holo: variants.contains(.holo),
                normal: variants.contains(.normal),
                reverse: variants.contains(.reverse),
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
    }
}
