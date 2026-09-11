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

private struct ScannerStubGradedResolver: ScannedGradedResolving {
    let outcome: ScannedGradedOutcome
    let recorder: ScannerPrintRunRecorder?

    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome {
        await recorder?.record(pokemonPrintRun)
        return outcome
    }
}

@MainActor
private final class ScannerStubPriceCheckProvider: PriceCheckRefreshProvider {
    let outcome: PriceCheckRefreshOutcome

    init(outcome: PriceCheckRefreshOutcome) {
        self.outcome = outcome
    }

    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceCheckRefreshOutcome {
        outcome
    }
}

private actor ScannerPrintRunRecorder {
    private(set) var values: [PokemonPrintRun?] = []

    func record(_ value: PokemonPrintRun?) {
        values.append(value)
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

    func testInFlightIDGuardSuppressesDuplicateUntilOriginalCompletes() {
        var guardState = InFlightIDGuard<UUID>()
        let id = UUID()

        XCTAssertTrue(guardState.begin(id))
        XCTAssertFalse(guardState.begin(id))

        guardState.end(id)
        XCTAssertTrue(guardState.begin(id))
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

    func testDismissingVariantChoiceClearsSavingAcknowledgementWithoutAdding() async throws {
        let fetchGate = ScannerFetchGate()
        let model = try makeModel(
            variants: [.normal, .holo],
            delayNanoseconds: 500_000_000,
            fetchGate: fetchGate
        )
        let encounterID = UUID()

        confirm(model, scannerIdentifier(), encounterID: encounterID)
        let acknowledged = await waitUntil {
            model.scanAcknowledgement?.encounterID == encounterID
                && model.scanAcknowledgement?.phase == .recognized
        }
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(model.scanAcknowledgement?.subject.identifier, scannerIdentifier())
        await fetchGate.waitUntilStarted()

        let choiceAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(choiceAppeared)
        XCTAssertEqual(model.scanAcknowledgement?.encounterID, encounterID)

        model.dismissChoice()

        let cancelled = await waitUntil {
            model.pendingChoice == nil && model.scanAcknowledgement == nil
        }
        XCTAssertTrue(cancelled)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertTrue(model.sessionScans.isEmpty)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
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

    func testUnboundSlabStillCommitsAsGradedAndKeepsCertificateIdentity() async throws {
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .unavailable
        )
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "12345678",
                labelCardText: ["CHARIZARD"]
            )
        )

        confirm(model, subject, encounterID: UUID())
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)

        let rows = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.itemKind, .gradedCard)
        XCTAssertEqual(rows.first?.gradingCompany, .psa)
        XCTAssertEqual(rows.first?.gradeRaw, "10")
        XCTAssertEqual(rows.first?.certificationNumber, "12345678")
        XCTAssertNil(rows.first?.justTCGVariantID)
        XCTAssertTrue(rows.first?.collectionKey.contains(":g:psa-") == true)
        XCTAssertEqual(model.recent.first?.subject.slab?.certificationNumber, "12345678")
    }

    func testGradedLabelPrintRunIsPassedBeforeVendorResolutionAndPrintedFinishIsPersisted() async throws {
        let recorder = ScannerPrintRunRecorder()
        let model = try makeModel(
            variants: [.normal, .holo],
            gradedOutcome: .unavailable,
            setProviderID: "base1",
            gradedRunRecorder: recorder
        )
        let subject = ScanSubject(
            identifier: scannerIdentifier(setProviderID: "base1"),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "12345678",
                labelCardText: ["HOLO"],
                printedFinish: .holo,
                printedPrintRun: .firstEdition
            )
        )

        confirm(model, subject, encounterID: UUID())
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)

        let observed = await recorder.values
        XCTAssertEqual(observed, [.firstEdition])
        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.pokemonPrintRun, .firstEdition)
        XCTAssertEqual(row.variant, .holo)
        XCTAssertEqual(row.variantResolution, .printedLabel)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingGradedVariantCorrection)
    }

    func testAmbiguousGradedFinishCommitsWithoutPausingAndCanBeCorrectedInPlace() async throws {
        let model = try makeModel(
            variants: [.normal, .holo],
            gradedOutcome: .unavailable
        )
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "87654321",
                labelCardText: ["CHARIZARD"]
            )
        )

        confirm(model, subject, encounterID: UUID())
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNotNil(model.pendingGradedVariantCorrection)
        XCTAssertNil(model.recent.first?.resolved.variant)
        XCTAssertNil(try context().fetch(FetchDescriptor<CollectedCard>()).first?.variant)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)

        model.chooseGradedVariant(.holo)
        let corrected = await waitUntil { model.recent.first?.resolved.variant == .holo }
        XCTAssertTrue(corrected)
        XCTAssertNil(model.pendingGradedVariantCorrection)
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.variant, .holo)
    }

    func testImpossibleGradedLabelPrintRunIsDroppedBeforeVendorAndPersistence() async throws {
        let recorder = ScannerPrintRunRecorder()
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .unavailable,
            setProviderID: "sv03",
            gradedRunRecorder: recorder
        )
        let subject = ScanSubject(
            identifier: scannerIdentifier(setProviderID: "sv03"),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "12345678",
                labelCardText: ["CHARIZARD"],
                printedPrintRun: .firstEdition
            )
        )

        confirm(model, subject, encounterID: UUID())
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)

        let observed = await recorder.values
        XCTAssertEqual(observed, [nil])
        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertNil(row.pokemonPrintRun)
    }

    func testCorrectedGradedScanKeepsItsResolvedPrice() async throws {
        let gradedVariant = GradedVariant(
            id: "graded-v2-correction",
            cardID: "graded-card-correction",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 250,
            updatedAt: nil
        )
        let model = try makeModel(
            variants: [.holo],
            gradedOutcome: .bound(gradedVariant)
        )
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "12345678",
                labelCardText: []
            )
        )

        confirm(model, subject, encounterID: UUID())
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)
        let scanID = try XCTUnwrap(model.recent.first?.id)

        let correction = await model.correct(scanID: scanID, to: .normal)
        XCTAssertEqual(correction, .saved)
        guard case let .price(price) = model.recent.first?.price else {
            return XCTFail("graded correction should retain the previously resolved price")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 250)
        XCTAssertEqual(price.source, .justTCG)
    }

    func testDifferentSlabsOfOnePrintingBothCommitWithoutSpatialProof() async throws {
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .unavailable
        )
        let psa10 = gradedSubject(value: "10", label: "Gem Mint")
        let psa9 = gradedSubject(value: "9", label: "Mint")

        confirm(model, psa10, encounterID: UUID())
        let firstCommitted = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(firstCommitted)

        // These slabs share the catalog printing, but not the physical-object
        // axis. A second grade must not be mistaken for the first card still
        // sitting in the scanner or require a spatial-exit proof.
        confirm(model, psa9, encounterID: UUID())
        let secondCommitted = await waitUntil { model.recent.count == 2 }
        XCTAssertTrue(secondCommitted)

        let rows = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.gradeRaw)), ["9", "10"])
        XCTAssertEqual(
            Set(model.recent.compactMap { $0.subject.slab?.grade.value }),
            ["9", "10"]
        )
    }

    func testBoundSlabUsesCanonicalGradedVariantKeyAndPrice() async throws {
        let variant = GradedVariant(
            id: "graded-v2-10",
            cardID: "graded-card-1",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 250,
            updatedAt: nil
        )
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .bound(variant)
        )
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: nil,
                labelCardText: []
            )
        )

        confirm(model, subject, encounterID: UUID())
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)

        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.justTCGVariantID, "graded-v2-10")
        XCTAssertEqual(row.justTCGCardID, "graded-card-1")
        XCTAssertEqual(row.collectionKey, "graded:pokemon:test-set-001:graded-v2-10")
        guard case let .price(price) = model.recent.first?.price else {
            return XCTFail("bound graded scan should carry the graded quote")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 250)
        XCTAssertEqual(price.source, .justTCG)
    }

    func testSlabPriceCheckUsesGradedQuoteWithoutAddingCollectionRow() async throws {
        let variant = GradedVariant(
            id: "graded-v2-price-check",
            cardID: "graded-card-price-check",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 300,
            updatedAt: nil
        )
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .bound(variant)
        )
        model.setPurpose(.priceCheck)
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "12345678",
                labelCardText: []
            )
        )

        confirm(model, subject, encounterID: UUID())
        let presented = await waitUntil { model.priceCheckResult != nil }
        XCTAssertTrue(presented)
        guard let result = model.priceCheckResult else {
            return XCTFail("graded Price Check should present a result")
        }
        guard case let .price(price) = result.quote else {
            return XCTFail("graded Price Check should use the graded quote")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 300)
        XCTAssertEqual(price.source, .justTCG)
        XCTAssertEqual(result.quoteState, .current)
        XCTAssertEqual(result.resolvedScan.request.subject.slab?.certificationNumber, "12345678")
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testREQ006RefreshedNonUSDQuoteRemainsChecking() async throws {
        let refreshedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let refreshed = PriceLookup.price(
            NormalizedPrice(
                unitMarketPriceUSD: 12,
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "reverse-holofoil",
                sourceUpdatedAt: refreshedAt,
                fetchedAt: refreshedAt
            )
        )
        let model = try makeModel(
            variants: [.normal],
            priceCheckOutcome: .quote(refreshed)
        )
        model.setPurpose(.priceCheck)

        confirm(model, scannerIdentifier(), encounterID: UUID())
        let appeared = await waitUntil { model.priceCheckResult != nil }
        XCTAssertTrue(appeared)
        let refreshedState = await waitUntil {
            guard let result = model.priceCheckResult else { return false }
            return !result.isRefreshing
                && result.display.currencyCode == "EUR"
                && result.display.amount == 12
        }

        XCTAssertTrue(refreshedState)
        XCTAssertEqual(model.priceCheckResult?.quoteState, .checking)
        XCTAssertEqual(model.priceCheckResult?.display.currencyCode, "EUR")
        XCTAssertEqual(model.priceCheckResult?.display.amount, 12)
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

    func testLeavingScanPublishesSummaryClearsSessionAndReturnsFresh() async throws {
        let model = try makeModel(variants: [.normal])
        let summaryStore = ScanSessionSummaryStore()
        model.start(
            context: context(),
            startCamera: false,
            shouldRefreshMagicDirectory: false,
            summaryStore: summaryStore
        )

        confirm(model, scannerIdentifier(), encounterID: UUID())
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)

        model.viewDisappeared()
        let finalized = await waitUntil { summaryStore.summary != nil }
        XCTAssertTrue(finalized)
        XCTAssertEqual(summaryStore.summary?.addedCount, 1)
        XCTAssertTrue(model.sessionScans.isEmpty)
        XCTAssertTrue(model.recent.isEmpty)

        // The next appearance does not inherit the prior visit's receipt,
        // duplicate lineage, or success animation counter.
        model.start(
            context: context(),
            startCamera: false,
            shouldRefreshMagicDirectory: false,
            summaryStore: summaryStore
        )
        XCTAssertTrue(model.sessionScans.isEmpty)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertEqual(model.successCount, 0)
    }

    func testBackgroundingDoesNotFinalizeTheVisibleScanSession() async throws {
        let model = try makeModel(variants: [.normal])
        let summaryStore = ScanSessionSummaryStore()
        model.start(
            context: context(),
            startCamera: false,
            shouldRefreshMagicDirectory: false,
            summaryStore: summaryStore
        )

        confirm(model, scannerIdentifier(), encounterID: UUID())
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)

        model.scenePhaseChanged(isActive: false)
        model.viewDisappeared()
        await settle()

        XCTAssertEqual(model.sessionScans.count, 1)
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertNil(summaryStore.summary)
    }

    func testLeavingScanWhileSceneInactiveClosesTheBulkWriteInterval() throws {
        let coordinator = DerivedStateWriteCoordinator()
        let model = try makeModel(
            variants: [.normal],
            writeCoordinator: coordinator
        )

        XCTAssertTrue(coordinator.isBulkWriteInFlight)
        model.scenePhaseChanged(isActive: false)
        model.viewDisappeared()

        XCTAssertFalse(coordinator.isBulkWriteInFlight)
    }

    func testExplicitScannerEndClosesTheBulkWriteInterval() throws {
        let coordinator = DerivedStateWriteCoordinator()
        let model = try makeModel(
            variants: [.normal],
            writeCoordinator: coordinator
        )

        XCTAssertTrue(coordinator.isBulkWriteInFlight)
        model.endSession()

        XCTAssertFalse(coordinator.isBulkWriteInFlight)
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

        XCTAssertFalse(window.observe(ScanSubject(identifier: identifier)))
        XCTAssertFalse(window.observe(ScanSubject(identifier: other)))
        XCTAssertFalse(window.observe(ScanSubject(identifier: identifier)))
        XCTAssertTrue(window.observe(ScanSubject(identifier: identifier)))
        XCTAssertFalse(window.observe(ScanSubject(identifier: identifier)))
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
            UnresolvedScan.merging([], with: ScanSubject(identifier: first)),
            with: ScanSubject(identifier: second)
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.titleCandidates, ["CHARIZARD", "STAGE 2"])
    }

    func testUnresolvedHistoricalMergeKeepsSlabEvidence() {
        let number = PokemonPrintedNumberEvidence(
            localID: "004",
            denominator: 102,
            scheme: .officialSet
        )
        let slab = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            labelCardText: []
        )
        let first = ScanSubject(
            identifier: .pokemonHistorical(
                PokemonHistoricalScanEvidence(number: number, titleCandidates: ["CHARIZARD"])
            ),
            slab: slab
        )
        let second = ScanSubject(
            identifier: .pokemonHistorical(
                PokemonHistoricalScanEvidence(
                    number: number,
                    titleCandidates: ["CHARIZARD", "STAGE 2"]
                )
            ),
            slab: slab
        )

        let merged = UnresolvedScan.merging(
            UnresolvedScan.merging([], with: first),
            with: second
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.subject.slab, slab)
    }

    private func makeModel(
        variants: [PhysicalVariant],
        secondaryVariants: [PhysicalVariant]? = nil,
        delayNanoseconds: UInt64 = 0,
        fetchGate: ScannerFetchGate? = nil,
        gradedOutcome: ScannedGradedOutcome? = nil,
        setProviderID: String = "test-set",
        gradedRunRecorder: ScannerPrintRunRecorder? = nil,
        writeCoordinator: DerivedStateWriteCoordinator? = nil,
        priceCheckOutcome: PriceCheckRefreshOutcome? = nil
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
                    "001": catalogCard(variants: variants, localID: "001", setID: setProviderID),
                    "002": catalogCard(
                        variants: secondaryVariants ?? variants,
                        localID: "002",
                        setID: setProviderID
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
            feedback: ScanFeedback(),
            gradedResolver: gradedOutcome.map {
                ScannerStubGradedResolver(outcome: $0, recorder: gradedRunRecorder)
            }
                ?? ScannedGradedResolver(),
            priceCheckRefreshProvider: priceCheckOutcome.map {
                ScannerStubPriceCheckProvider(outcome: $0)
            }
        )
        model.start(
            context: context,
            isSceneActive: true,
            startCamera: false,
            shouldRefreshMagicDirectory: false,
            writeCoordinator: writeCoordinator
        )
        return model
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            CollectionActivity.self,
            InventoryEvent.self,
            ReferenceQuote.self,
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
        confirm(model, ScanSubject(identifier: identifier), encounterID: encounterID)
    }

    private func confirm(
        _ model: ScannerViewModel,
        _ subject: ScanSubject,
        encounterID: UUID
    ) {
        model.scanner.onConfirmedSubjectCandidate?(nil, encounterID, subject, nil)
    }

    private func gradedSubject(
        value: String,
        label: String,
        certificationNumber: String? = "12345678"
    ) -> ScanSubject {
        ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: value, label: label),
                certificationNumber: certificationNumber,
                labelCardText: []
            )
        )
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

    private func fixtureSetDefinition(setID: String = "test-set") -> PokemonSetDefinition {
        PokemonSetDefinition(
            printedCode: "TST",
            tcgdexSetID: setID,
            officialCount: 10,
            releaseIndex: 0
        )
    }

    private func scannerIdentifier(
        cardNumber: String = "001",
        setProviderID: String = "test-set"
    ) -> ScanIdentifier {
        .pokemon(
            setCode: "TST",
            cardNumber: cardNumber,
            printedTotal: 10,
            setDefinition: fixtureSetDefinition(setID: setProviderID)
        )
    }

    private func catalogCard(
        variants: [PhysicalVariant],
        localID: String,
        setID: String = "test-set"
    ) -> TCGdexCard {
        TCGdexCard(
            id: "test-set-\(localID)",
            localId: localID,
            name: "Test Card",
            image: nil,
            rarity: "Common",
            set: TCGdexSetBrief(
                id: setID,
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
