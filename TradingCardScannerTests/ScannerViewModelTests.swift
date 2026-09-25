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

private actor ScannerCatalogFailureSwitch {
    private var shouldFail = true

    func isFailureEnabled() -> Bool { shouldFail }
    func allowSuccess() { shouldFail = false }
}

private enum ScannerCollectionAddGateError: Error {
    case failed
}

private actor ScannerCollectionAddGate {
    enum Outcome {
        case success
        case failure
    }

    private var outcome: Outcome
    private var bypassGateAfterSwitch = false
    private let successfulAddsBeforeBlocking: Int
    private var addCount = 0
    private var hasStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(outcome: Outcome, successfulAddsBeforeBlocking: Int = 0) {
        self.outcome = outcome
        self.successfulAddsBeforeBlocking = successfulAddsBeforeBlocking
    }

    func add(_ candidate: CollectionCommitCandidate) async throws -> CollectionMutation {
        _ = candidate
        addCount += 1
        if addCount <= successfulAddsBeforeBlocking {
            return CollectionMutation(
                collectionKey: "scanner-test",
                activityID: nil,
                didInsert: true
            )
        }
        if bypassGateAfterSwitch {
            return CollectionMutation(
                collectionKey: "scanner-test",
                activityID: nil,
                didInsert: true
            )
        }
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            releaseWaiter = continuation
        }
        if case .failure = outcome {
            throw ScannerCollectionAddGateError.failed
        }
        return CollectionMutation(
            collectionKey: "scanner-test",
            activityID: nil,
            didInsert: true
        )
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func allowSuccess() {
        outcome = .success
        bypassGateAfterSwitch = true
    }

    func count() -> Int {
        addCount
    }
}

private struct ScannerStubPokemonSource: PokemonCardSource {
    enum Failure: Sendable {
        case transient
        case providerUnavailable
    }

    let cardsByLocalID: [String: TCGdexCard]
    let delayNanoseconds: UInt64
    let fetchGate: ScannerFetchGate?
    let catalogMiss: Bool
    let failure: Failure?
    let failureSwitch: ScannerCatalogFailureSwitch?

    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        await fetchGate?.markStarted()
        if let failure, await failureSwitch?.isFailureEnabled() ?? true {
            switch failure {
            case .transient: throw TCGdexError.badResponse
            case .providerUnavailable: throw ScryfallError.providerUnavailable
            }
        }
        if catalogMiss {
            throw TCGdexError.cardNotFound
        }
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
        if let failure, await failureSwitch?.isFailureEnabled() ?? true {
            switch failure {
            case .transient:
                throw TCGdexError.badResponse
            case .providerUnavailable:
                throw ScryfallError.providerUnavailable
            }
        }
        return nil
    }
}

private struct ScannerStubGradedResolver: ScannedGradedResolving {
    let outcome: ScannedGradedOutcome
    let recorder: ScannerPrintRunRecorder?
    let gate: ScannerGradedResolverGate?

    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome {
        await recorder?.record(pokemonPrintRun)
        await gate?.pause()
        return outcome
    }
}

private actor ScannerGradedResolverGate {
    private var hasStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            releaseWaiter = continuation
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            startWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
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

    func testPriceIdentityPreflightOnlyGatesUnboundCertifiedSlabPromotion() throws {
        let context = try makeContext()
        let container = context.container
        let grade = CardGrade(value: "10", label: "Gem Mint")
        let arguments = (
            game: CardGame.pokemon,
            providerID: "preflight-card",
            grade: grade,
            company: GradingCompany.psa,
            certificationNumber: Optional("12345678"),
            treatmentIDs: [String]()
        )

        XCTAssertFalse(PriceIdentityWritePreflight.requiresGradedPromotion(
            container: container,
            game: arguments.game,
            providerID: arguments.providerID,
            grade: arguments.grade,
            company: arguments.company,
            certificationNumber: arguments.certificationNumber,
            treatmentIDs: arguments.treatmentIDs
        ))

        let row = CollectedCard(
            collectionKey: "graded:pokemon:preflight-card:graded-variant:cert:12345678",
            game: .pokemon,
            providerID: "graded:pokemon:preflight-card:graded-variant:cert:12345678",
            name: "Preflight Card",
            setName: "Preflight Set",
            setCode: "PFT",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .imported
        )
        row.catalogProviderID = arguments.providerID
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        row.gradingCompanyRaw = arguments.company.rawValue
        row.gradeRaw = grade.value
        row.gradeLabel = grade.label
        row.certificationNumber = arguments.certificationNumber
        context.insert(row)
        try context.save()

        XCTAssertTrue(PriceIdentityWritePreflight.requiresGradedPromotion(
            container: container,
            game: arguments.game,
            providerID: arguments.providerID,
            grade: arguments.grade,
            company: arguments.company,
            certificationNumber: arguments.certificationNumber,
            treatmentIDs: arguments.treatmentIDs
        ))

        row.justTCGVariantID = "already-bound-variant"
        try context.save()
        XCTAssertFalse(PriceIdentityWritePreflight.requiresGradedPromotion(
            container: container,
            game: arguments.game,
            providerID: arguments.providerID,
            grade: arguments.grade,
            company: arguments.company,
            certificationNumber: arguments.certificationNumber,
            treatmentIDs: arguments.treatmentIDs
        ))
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

    func testPendingChoiceIsRestoredWhenIdentificationPipelineIsBusy() async throws {
        let model = try makeModel(variants: [.normal, .holo])
        let encounterID = UUID()

        confirm(model, scannerIdentifier(), encounterID: encounterID)
        let choiceAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(choiceAppeared)
        let requestID = try XCTUnwrap(model.pendingChoice?.request.id)

        model.setIdentificationInFlightForTesting(true)
        model.choose(.normal)
        await settle()

        XCTAssertEqual(model.pendingChoice?.request.id, requestID)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertTrue(model.sessionScans.isEmpty)

        model.setIdentificationInFlightForTesting(false)
        model.choose(.normal)
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed)
        XCTAssertNil(model.pendingChoice)
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
        useSlabMode(model)
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

    func testRawScanConvertsToGradedWithTheSameRecentScanID() async throws {
        let model = try makeModel(variants: [.normal], gradedOutcome: .unavailable)
        let encounterID = UUID()
        confirm(model, scannerIdentifier(), encounterID: encounterID)
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)
        let original = try XCTUnwrap(model.sessionScans.first)
        XCTAssertNil(original.subject.slab)
        XCTAssertEqual(model.successCount, 1)

        let evidence = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            labelCardText: ["CHARIZARD"]
        )
        model.scanner.onPostCommitSlabEvidence?(encounterID, evidence)
        let offerShown = await waitUntil { model.pendingSlabConversionOffer?.scanID == original.id }
        XCTAssertTrue(offerShown)

        await model.convertRawScanToGraded(scanID: original.id)
        let converted = await waitUntil {
            model.sessionScans.first?.id == original.id
                && model.sessionScans.first?.subject.slab == evidence
                && (try? self.context().fetch(FetchDescriptor<CollectedCard>()).first?.itemKind) == .gradedCard
        }
        XCTAssertTrue(converted)
        let rows = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.certificationNumber, "12345678")
        XCTAssertEqual(model.recent.first?.id, original.id)
        XCTAssertEqual(model.committedSessionHistory.first?.id, original.id)
        XCTAssertEqual(model.successCount, 1)
        XCTAssertNil(model.pendingSlabConversionOffer)
    }

    func testSlabPriceBindingStartsAfterUnboundCollectionCommit() async throws {
        let wasEnforced = CollectionWriteSerializer.enforcesOwnershipRule
        CollectionWriteSerializer.enforcesOwnershipRule = true
        defer { CollectionWriteSerializer.enforcesOwnershipRule = wasEnforced }

        let variant = GradedVariant(
            id: "graded-v2-after-save",
            cardID: "graded-card-after-save",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 250,
            updatedAt: nil
        )
        let gate = ScannerGradedResolverGate()
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .bound(variant),
            gradedResolverGate: gate
        )
        useSlabMode(model)
        confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())

        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)
        await gate.waitUntilStarted()
        let scan = try XCTUnwrap(model.sessionScans.first)
        let unboundRow = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(unboundRow.itemKind, .gradedCard)
        XCTAssertNil(unboundRow.justTCGVariantID)
        XCTAssertTrue(unboundRow.collectionKey.contains(":g:psa-10"))
        if case .price = scan.price {
            XCTFail("the initial collection commit must not wait for graded pricing")
        }

        await gate.release()
        let bound = await waitUntil {
            guard let scan = model.sessionScans.first,
                  let row = try? self.context().fetch(FetchDescriptor<CollectedCard>()).first,
                  row.justTCGVariantID == variant.id,
                  case let .price(price) = scan.price else { return false }
            return price.unitMarketPriceUSD == 250
        }
        XCTAssertTrue(bound)
        XCTAssertEqual(model.recent.first?.id, scan.id)
        XCTAssertEqual(model.receipt?.scanID, scan.id)
        guard case let .price(receiptPrice)? = model.receipt?.price else {
            return XCTFail("the receipt should receive the graded quote")
        }
        XCTAssertEqual(receiptPrice.unitMarketPriceUSD, 250)
    }

    func testSlabBindingCompletesAfterScannerSessionEndsDuringGateWait() async throws {
        let variant = GradedVariant(
            id: "graded-v2-after-session-end",
            cardID: "graded-card-after-session-end",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 250,
            updatedAt: nil
        )
        let resolverGate = ScannerGradedResolverGate()
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .bound(variant),
            gradedResolverGate: resolverGate
        )
        useSlabMode(model)

        let migration = MagicTreatmentMigrationCoordinator.shared
        let migrationToken = await migration.acquireExclusive()
        confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)
        await resolverGate.waitUntilStarted()
        await resolverGate.release()

        let bindingIsWaitingForGate = await waitUntil {
            PriceRefreshController.shared.isSuspendedForWrite
        }
        XCTAssertTrue(bindingIsWaitingForGate)

        model.endSession()
        migration.releaseExclusive(migrationToken)

        let durableBindingFinished = await waitUntil {
            (try? self.context().fetch(FetchDescriptor<CollectedCard>()).first?.justTCGVariantID)
                == variant.id
        }
        XCTAssertTrue(durableBindingFinished)
        XCTAssertTrue(model.sessionScans.isEmpty)
    }

    func testUndoDuringGradedLookupCannotRecreateTheRemovedSlab() async throws {
        let variant = GradedVariant(
            id: "graded-v2-undo-race",
            cardID: "graded-card-undo-race",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 250,
            updatedAt: nil
        )
        let gate = ScannerGradedResolverGate()
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .bound(variant),
            gradedResolverGate: gate
        )
        useSlabMode(model)
        confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)
        await gate.waitUntilStarted()
        let scanID = try XCTUnwrap(model.sessionScans.first?.id)

        let didUndo = await model.undoScan(scanID: scanID)
        XCTAssertTrue(didUndo)
        await gate.release()
        await settle()

        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(model.sessionScans.isEmpty)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertEqual(model.successCount, 1)
    }

    func testCertificateReadAfterCertlessSlabCommitDoesNotReassignCertificateWhileHeld() async throws {
        let variant = GradedVariant(
            id: "graded-v2-after-cert-refinement",
            cardID: "graded-card-after-cert-refinement",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            marketPriceUSD: 310,
            updatedAt: nil
        )
        let gate = ScannerGradedResolverGate()
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .bound(variant),
            gradedResolverGate: gate
        )
        useSlabMode(model)
        model.scanner.drainProfileQueuesForTesting()
        let identifier = scannerIdentifier()
        let certless = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: nil,
            labelCardText: ["CHARIZARD HOLO"]
        )
        let certified = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            labelCardText: ["CHARIZARD HOLO"]
        )

        XCTAssertNil(model.scanner.receiveSlabLabelEvidenceForTesting(
            certless,
            footerHasText: true,
            for: identifier,
            at: 0
        ))
        XCTAssertEqual(model.scanner.receiveSlabLabelEvidenceForTesting(
            certless,
            footerHasText: true,
            for: identifier,
            at: 1.5
        ), certless)
        model.scanner.receiveFooterOutcomeForTesting(.identified(ScanSubject(identifier: identifier)), at: 1.75)
        model.scanner.receiveFooterOutcomeForTesting(.identified(ScanSubject(identifier: identifier)), at: 2.0)

        let initialCommit = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(initialCommit)
        await gate.waitUntilStarted()
        var rows = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.certificationNumber)
        let originalCollectionKey = try XCTUnwrap(rows.first?.collectionKey)
        XCTAssertEqual(model.scanner.activeSlabEvidenceForTesting, certless)

        XCTAssertNil(model.scanner.receiveSlabLabelEvidenceForTesting(
            certified,
            footerHasText: true,
            for: identifier,
            at: 2.5
        ))
        XCTAssertEqual(model.scanner.lastSlabLabelReadAtForTesting, 2.5)
        XCTAssertNil(model.scanner.receiveSlabLabelEvidenceForTesting(
            certified,
            footerHasText: true,
            for: identifier,
            at: 3.0
        ))
        // A second copy can have the same footer, grader, and grade. Until the
        // held presentation ends, assigning its newly read certificate to the
        // certless row could silently overwrite the wrong physical copy.
        XCTAssertEqual(model.scanner.activeSlabEvidenceForTesting, certless)
        model.scanner.receiveFooterOutcomeForTesting(.identified(ScanSubject(identifier: identifier)), at: 3.1)

        rows = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.collectionKey, originalCollectionKey)
        XCTAssertEqual(rows.first?.itemKind, .gradedCard)
        XCTAssertNil(rows.first?.certificationNumber)
        XCTAssertNil(model.recent.first?.subject.slab?.certificationNumber)
        XCTAssertEqual(model.successCount, 1)
        XCTAssertEqual(model.scanner.latchedSubjectForTesting?.slab?.certificationNumber, nil)

        await gate.release()
        let reboundToCurrentKey = await waitUntil {
            guard let scan = model.sessionScans.first,
                  let row = try? self.context().fetch(FetchDescriptor<CollectedCard>()).first,
                  row.justTCGVariantID == variant.id,
                  case let .price(price) = scan.price else { return false }
            return price.unitMarketPriceUSD == 310
                && scan.mutation.collectionKey == row.collectionKey
        }
        XCTAssertTrue(reboundToCurrentKey)
    }

    func testGradedLabelPrintRunIsPersistedWithoutBlockingOnVendorResolution() async throws {
        let recorder = ScannerPrintRunRecorder()
        let gate = ScannerGradedResolverGate()
        let model = try makeModel(
            variants: [.normal, .holo],
            gradedOutcome: .unavailable,
            setProviderID: "base1",
            gradedRunRecorder: recorder,
            gradedResolverGate: gate
        )
        useSlabMode(model)
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
        await gate.waitUntilStarted()

        let observed = await recorder.values
        XCTAssertEqual(observed, [.firstEdition])
        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.pokemonPrintRun, .firstEdition)
        XCTAssertEqual(row.variant, .holo)
        XCTAssertEqual(row.variantResolution, .printedLabel)
        XCTAssertNil(row.justTCGVariantID)
        XCTAssertTrue(
            try context().fetch(FetchDescriptor<PriceCheckDay>()).isEmpty,
            "an offline/cache card identity without pricing data is not a provider check"
        )
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingGradedVariantCorrection)
        await gate.release()
    }

    func testAmbiguousGradedFinishCommitsWithoutPausingAndCanBeCorrectedInPlace() async throws {
        let model = try makeModel(
            variants: [.normal, .holo],
            gradedOutcome: .unavailable
        )
        useSlabMode(model)
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

    func testRawFinishCorrectionDoesNotPersistNoProviderPriceFailure() async throws {
        let model = try makeModel(variants: [.normal, .holo])
        confirm(model, scannerIdentifier(), encounterID: UUID())
        let choiceAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(choiceAppeared)
        model.choose(.holo)

        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)
        let scanID = try XCTUnwrap(model.sessionScans.first?.id)
        XCTAssertTrue(try context().fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        let outcome = await model.correct(scanID: scanID, to: .normal)
        XCTAssertEqual(outcome, .saved)

        XCTAssertTrue(
            try context().fetch(FetchDescriptor<PriceRecord>()).isEmpty,
            "finish correction must not record unavailable(nil) as a provider check"
        )
    }

    func testImpossibleGradedLabelPrintRunIsDroppedBeforePersistence() async throws {
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .unavailable,
            setProviderID: "sv03"
        )
        useSlabMode(model)
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
        useSlabMode(model)
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
        let committedAndBound = await waitUntil {
            guard let scan = model.recent.first,
                  scan.subject.slab != nil,
                  case let .price(price) = scan.price else { return false }
            return model.recent.count == 1
                && price.unitMarketPriceUSD == 250
                && price.source == .justTCG
        }
        XCTAssertTrue(committedAndBound)
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
        useSlabMode(model)
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
        useSlabMode(model)
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
        let committedAndBound = await waitUntil {
            guard let scan = model.recent.first,
                  case let .price(price) = scan.price,
                  let row = try? self.context().fetch(FetchDescriptor<CollectedCard>()).first,
                  row.justTCGVariantID == variant.id else { return false }
            return price.unitMarketPriceUSD == 250
        }
        XCTAssertTrue(committedAndBound)

        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.justTCGVariantID, "graded-v2-10")
        XCTAssertEqual(row.justTCGCardID, "graded-card-1")
        XCTAssertTrue(row.collectionKey.contains(":g:psa-10"))
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
        useSlabMode(model)
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
        XCTAssertNil(model.scanAcknowledgement)

        let cards = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.quantity, 1)
    }

    func testHeldRepeatWithStaleAuthorizationClearsAcknowledgementWithoutWriting() async throws {
        let model = try makeModel(variants: [.normal])
        let encounterID = UUID()

        confirm(
            model,
            scannerIdentifier(),
            encounterID: encounterID,
            authorizationID: UUID()
        )

        let terminal = await waitUntil {
            model.scanAcknowledgement == nil && model.recent.isEmpty
        }
        XCTAssertTrue(terminal)
        XCTAssertNil(model.scanAcknowledgement)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testHeldRepeatIdentityMismatchClearsAcknowledgementWithoutWriting() async throws {
        let fixture = try await makeHistoricalHeldRepeatFixture()
        let model = try makeModel(
            variants: [.normal],
            offline: fixture.offline
        )
        let start = CFAbsoluteTimeGetCurrent()
        var firstEncounterID: UUID?
        var authorizedEncounterID: UUID?
        let originalConfirmation = model.scanner.onConfirmedSubjectCandidate
        model.scanner.onConfirmedSubjectCandidate = { context, encounterID, subject, authorizationID in
            if authorizationID == nil {
                firstEncounterID = encounterID
            } else {
                authorizedEncounterID = encounterID
            }
            originalConfirmation?(context, encounterID, subject, authorizationID)
        }
        model.scanner.drainProfileQueuesForTesting()

        model.scanner.receiveFooterOutcomeForTesting(.identified(fixture.first), at: start + 0.25)
        model.scanner.receiveFooterOutcomeForTesting(.identified(fixture.first), at: start + 0.5)
        let firstCommit = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(firstCommit)
        await settle()

        guard let firstEncounterID else {
            XCTFail("The initial scanner confirmation did not produce an encounter ID")
            return
        }
        for offset in stride(from: 0.75, through: 2.5, by: 0.25) {
            model.scanner.receiveFooterOutcomeForTesting(.identified(fixture.first), at: start + offset)
        }
        model.scanner.onLatchHolding?(fixture.first, firstEncounterID)

        let offerAppeared = await waitUntil { model.heldDuplicateOffer != nil }
        XCTAssertTrue(offerAppeared)
        guard offerAppeared else { return }
        model.addAnotherHeldCopy()
        await settle()
        model.scanner.drainVisionQueueForTesting()
        model.scanner.receiveFooterOutcomeForTesting(.identified(fixture.second), at: start + 3.0)
        model.scanner.receiveFooterOutcomeForTesting(.identified(fixture.second), at: start + 3.25)

        let authorized = await waitUntil { authorizedEncounterID != nil }
        XCTAssertTrue(authorized)
        await settle()

        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(model.successCount, 1)
        XCTAssertNil(model.scanAcknowledgement)
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testStaleStorageGenerationBeforeWriteClearsAcknowledgementWithoutWriting() async throws {
        let generation = CollectionStorageGeneration()
        generation.installReady(storeID: UUID())
        let fetchGate = ScannerFetchGate()
        let model = try makeModel(
            variants: [.normal],
            delayNanoseconds: 300_000_000,
            fetchGate: fetchGate,
            storageGeneration: generation
        )

        confirm(model, scannerIdentifier(), encounterID: UUID())
        await fetchGate.waitUntilStarted()
        generation.suspend()

        let terminal = await waitUntil {
            model.scanAcknowledgement == nil && model.recent.isEmpty
        }
        XCTAssertTrue(terminal)
        XCTAssertNil(model.scanAcknowledgement)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testStaleStorageGenerationAfterWriteClearsAcknowledgementWithoutReceipt() async throws {
        let generation = CollectionStorageGeneration()
        generation.installReady(storeID: UUID())
        let addGate = ScannerCollectionAddGate(outcome: .success)
        let model = try makeModel(
            variants: [.normal],
            storageGeneration: generation,
            collectionAddOverride: { candidate in
                try await addGate.add(candidate)
            }
        )

        confirm(model, scannerIdentifier(), encounterID: UUID())
        await addGate.waitUntilStarted()
        XCTAssertEqual(model.scanAcknowledgement?.message, "Saving to your collection…")

        generation.suspend()
        await addGate.release()

        let terminal = await waitUntil {
            model.scanAcknowledgement == nil && model.recent.isEmpty
        }
        XCTAssertTrue(terminal)
        XCTAssertNil(model.scanAcknowledgement)
        XCTAssertTrue(model.recent.isEmpty)
        let addCount = await addGate.count()
        XCTAssertEqual(addCount, 1)
    }

    func testHeldRepeatSaveFailureRepublishesOfferAndKeepsFailureAcknowledgement() async throws {
        let addGate = ScannerCollectionAddGate(
            outcome: .failure,
            successfulAddsBeforeBlocking: 1
        )
        let model = try makeModel(
            variants: [.normal],
            collectionAddOverride: { candidate in
                try await addGate.add(candidate)
            }
        )
        let subject = ScanSubject(identifier: scannerIdentifier())
        let start = CFAbsoluteTimeGetCurrent()
        var firstEncounterID: UUID?
        let originalConfirmation = model.scanner.onConfirmedSubjectCandidate
        model.scanner.onConfirmedSubjectCandidate = { context, encounterID, confirmed, authorizationID in
            if authorizationID == nil {
                firstEncounterID = encounterID
            }
            originalConfirmation?(context, encounterID, confirmed, authorizationID)
        }
        model.scanner.drainProfileQueuesForTesting()

        model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 0.25)
        model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 0.5)
        let firstCommit = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(firstCommit)
        XCTAssertEqual(model.sessionScans.first?.subject.suppressionKey, subject.suppressionKey)
        XCTAssertEqual(model.committedSessionHistory.last?.encounterID, firstEncounterID)
        await settle()

        for offset in stride(from: 0.75, through: 2.5, by: 0.25) {
            model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + offset)
        }
        guard let firstEncounterID else {
            XCTFail("The initial scanner confirmation did not produce an encounter ID")
            return
        }
        model.scanner.onLatchHolding?(subject, firstEncounterID)

        let offerAppeared = await waitUntil { model.heldDuplicateOffer != nil }
        XCTAssertTrue(offerAppeared)
        guard offerAppeared else { return }
        model.addAnotherHeldCopy()
        await settle()
        model.scanner.drainVisionQueueForTesting()
        model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 3.0)
        model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 3.25)

        await addGate.waitUntilStarted()
        await addGate.release()

        let failed = await waitUntil {
            model.heldDuplicateOffer != nil && model.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(failed)
        XCTAssertNotNil(model.heldDuplicateOffer)
        XCTAssertEqual(model.scanAcknowledgement?.phase, .failed)
        XCTAssertEqual(
            model.scanAcknowledgement?.message,
            "Recognized, but saving failed. Saved to Needs attention to retry."
        )
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertEqual(
            model.unresolvedScans.first?.reason,
            .saveFailed(inMemoryCandidateID: model.unresolvedScans.first?.pendingCommit?.requestID)
        )
        XCTAssertEqual(model.recent.count, 1)
        let addCount = await addGate.count()
        XCTAssertEqual(addCount, 2)
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
        XCTAssertNil(model.scanAcknowledgement)
    }

    func testUnprovenRepeatInPrintRunSetIsRejectedBeforePrintRunChoice() async throws {
        let model = try makeModel(
            variants: [.normal],
            setProviderID: "base1"
        )
        let firstEncounter = UUID()

        confirm(
            model,
            scannerIdentifier(setProviderID: "base1"),
            encounterID: firstEncounter
        )
        await assertEventually { model.pendingPrintRunChoice?.request.encounterID == firstEncounter }
        XCTAssertEqual(model.pendingPrintRunChoice?.options, [.firstEdition, .shadowless, .unlimited])

        model.choose(.unlimited)
        await assertEventually { model.sessionScans.count == 1 }

        let repeatEncounter = UUID()
        confirm(
            model,
            scannerIdentifier(setProviderID: "base1"),
            encounterID: repeatEncounter
        )
        await assertEventually { model.note?.text.contains("already added this session") == true }
        XCTAssertNil(model.pendingPrintRunChoice)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.sessionScans.count, 1)
    }

    func testRepeatAfterAddingAnotherCopyIsRejectedWithoutFreshReplacement() async throws {
        let model = try makeModel(
            variants: [.normal],
            secondaryVariants: [.normal]
        )

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        await assertEventually { model.sessionScans.count == 1 }
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
        await assertEventually { model.sessionScans.count == 2 }

        let confirmedRepeat = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: confirmedRepeat)
        await assertEventually {
            model.pendingDuplicateConfirmation?.encounterID == confirmedRepeat
        }
        model.addAnother()
        await assertEventually {
            model.sessionScans.count == 3 && model.pendingDuplicateConfirmation == nil
        }

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        await assertEventually { model.note?.text.contains("already added this session") == true }
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.sessionScans.count, 3)
    }

    func testCommittedHistoryReplacementPromptsAfterTrackerLossWithFinishPicker() async throws {
        let model = try makeModel(
            variants: [.normal, .reverse],
            secondaryVariants: [.normal]
        )
        let firstEncounter = UUID()
        let replacingEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == firstEncounter }
        model.choose(.reverse)
        await assertEventually { model.sessionScans.count == 1 }

        // Model tracker loss before the next card is recognized. Committed
        // history must still permit the repeat to reach its confirmation prompt.
        model.scanner.invalidateSpatialContinuity()
        await settle()
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: replacingEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        let repeatedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == repeatedEncounter }
        XCTAssertEqual(model.pendingChoice?.duplicateChoiceContext?.previousFinishLabel, "Reverse")
        guard let choiceEvidence = model.pendingChoice?.duplicateChoiceContext?.evidence,
              case .committedReplacement(_) = choiceEvidence else {
            return XCTFail("the finish picker should include committed-history replacement evidence")
        }

        model.choose(.normal)
        await assertEventually {
            model.sessionScans.count == 3
                && model.pendingChoice == nil
                && model.pendingDuplicateConfirmation == nil
        }
        XCTAssertEqual(
            model.sessionScans.filter { $0.card.id == "pokemon:test-set-001" }.count,
            2
        )
        XCTAssertEqual(model.successCount, 3)
    }

    func testCommittedHistoryReplacementPromptsAfterTrackerLossWithFinishLock() async throws {
        let model = try makeModel(
            variants: [.normal, .reverse],
            secondaryVariants: [.normal]
        )
        let firstEncounter = UUID()
        let replacingEncounter = UUID()
        model.setFinishLock(MagicFinishLock(finish: .reverse), for: .pokemon)

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.sessionScans.count == 1 }
        XCTAssertEqual(model.sessionScans.first?.resolved.variant, .reverse)

        model.scanner.invalidateSpatialContinuity()
        await settle()
        model.setFinishLock(MagicFinishLock(finish: .normal), for: .pokemon)
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: replacingEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        let repeatedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually {
            model.pendingDuplicateConfirmation?.encounterID == repeatedEncounter
        }
        guard let confirmation = model.pendingDuplicateConfirmation else {
            return XCTFail("a finish-locked repeat should still ask before adding")
        }
        guard case .committedReplacement = confirmation.evidence else {
            return XCTFail("the prompt should use committed history after tracker loss")
        }
        XCTAssertEqual(confirmation.candidate.resolved.variant, .normal)
        XCTAssertEqual(confirmation.previousFinishLabel, "Reverse")

        model.addAnother()
        await assertEventually { model.sessionScans.count == 3 }
        XCTAssertEqual(model.successCount, 3)
    }

    func testCommittedHistoryReplacementCombinesRepeatAndFinishChoiceIntoOneAddAction() async throws {
        let model = try makeModel(
            variants: [.normal, .reverse],
            secondaryVariants: [.normal],
            tertiaryVariants: [.normal]
        )
        let firstEncounter = UUID()
        let secondEncounter = UUID()
        let thirdEncounter = UUID()
        let repeatedEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == firstEncounter }
        model.choose(.reverse)
        await assertEventually { model.sessionScans.count == 1 }
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: secondEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        confirm(model, scannerIdentifier(cardNumber: "003"), encounterID: thirdEncounter)
        await assertEventually { model.sessionScans.count == 3 }

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually {
            model.pendingChoice?.request.encounterID == repeatedEncounter
        }
        XCTAssertEqual(model.pendingChoice?.duplicateChoiceContext?.previousFinishLabel, "Reverse")
        XCTAssertNil(model.pendingDuplicateConfirmation)

        // The finish option explicitly says this is adding another copy, so
        // this single tap answers both the finish question and the repeat prompt.
        model.choose(.normal)
        await assertEventually {
            model.sessionScans.count == 4
                && model.pendingChoice == nil
                && model.pendingDuplicateConfirmation == nil
        }
        await settle()
        XCTAssertEqual(model.successCount, 4)
        XCTAssertEqual(
            model.sessionScans.filter { $0.card.id == "pokemon:test-set-001" }.count,
            2
        )
        XCTAssertEqual(
            model.sessionScans.filter {
                $0.card.id == "pokemon:test-set-001" && $0.resolved.variant == .normal
            }.count,
            1
        )
    }

    func testCommittedHistoryReplacementShowsAddAnotherPromptForResolvedFinish() async throws {
        let model = try makeModel(
            variants: [.normal],
            secondaryVariants: [.normal]
        )
        let firstEncounter = UUID()
        let replacingEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.sessionScans.count == 1 }
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: replacingEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        let repeatedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually {
            model.pendingDuplicateConfirmation?.encounterID == repeatedEncounter
        }
        guard let confirmation = model.pendingDuplicateConfirmation else {
            return XCTFail("the committed-history repeat should ask before adding")
        }
        guard case .committedReplacement(_) = confirmation.evidence else {
            return XCTFail("the prompt should use committed-history replacement evidence")
        }
        XCTAssertEqual(confirmation.previousFinishLabel, "Normal")

        model.addAnother()
        await assertEventually {
            model.sessionScans.count == 3 && model.pendingDuplicateConfirmation == nil
        }
        await settle()
        XCTAssertEqual(model.successCount, 3)
    }

    func testDeclinedHistoryReplacementDoesNotAddAndPromptsAgain() async throws {
        let model = try makeModel(
            variants: [.normal, .reverse],
            secondaryVariants: [.normal]
        )
        let firstEncounter = UUID()
        let replacingEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == firstEncounter }
        model.choose(.reverse)
        await assertEventually { model.sessionScans.count == 1 }
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: replacingEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        let declinedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: declinedEncounter)
        await assertEventually {
            model.pendingChoice?.request.encounterID == declinedEncounter
        }
        XCTAssertNotNil(model.pendingChoice?.duplicateChoiceContext)
        model.dismissChoice()
        await settle()
        XCTAssertEqual(model.sessionScans.count, 2)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingDuplicateConfirmation)

        let retryEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: retryEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == retryEncounter }
        XCTAssertNotNil(model.pendingChoice?.duplicateChoiceContext)
        model.dismissChoice()
        await settle()
        XCTAssertNil(model.pendingChoice)
        XCTAssertEqual(model.sessionScans.count, 2)
    }

    func testUncommittedReplacementDoesNotUnlockRepeatFinishChoice() async throws {
        let model = try makeModel(variants: [.normal, .reverse])
        let firstEncounter = UUID()
        let uncommittedReplacement = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == firstEncounter }
        model.choose(.reverse)
        await assertEventually { model.sessionScans.count == 1 }
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: uncommittedReplacement)
        await assertEventually {
            model.pendingChoice?.request.encounterID == uncommittedReplacement
        }
        model.dismissChoice()
        await settle()

        let repeatedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually { model.note?.text.contains("already added this session") == true }
        XCTAssertNil(model.pendingChoice)
        XCTAssertEqual(model.sessionScans.count, 1)
    }

    func testUndoingReplacingCardRemovesCommittedHistoryReplacementEvidence() async throws {
        let model = try makeModel(
            variants: [.normal, .reverse],
            secondaryVariants: [.normal]
        )
        let firstEncounter = UUID()
        let replacingEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == firstEncounter }
        model.choose(.reverse)
        await assertEventually { model.sessionScans.count == 1 }
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: replacingEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        let replacingScanID = try XCTUnwrap(
            model.sessionScans.first(where: { $0.card.id == "pokemon:test-set-002" })?.id
        )
        let didUndo = await model.undoScan(scanID: replacingScanID)
        XCTAssertTrue(didUndo)
        XCTAssertEqual(model.sessionScans.count, 1)

        let repeatedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually { model.note?.text.contains("already added this session") == true }
        XCTAssertNil(model.pendingChoice)
        XCTAssertEqual(model.sessionScans.count, 1)
    }

    func testOlderPresentationProofSurvivesAnotherCardAndSameCardChoiceNeverAdds() async throws {
        let model = try makeModel(variants: [.normal])
        let firstEncounter = UUID()
        let otherEncounter = UUID()
        let repeatedEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        let firstCommitted = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(firstCommitted)
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: firstEncounter))
        await settle()

        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: otherEncounter)
        let otherCommitted = await waitUntil { model.sessionScans.count == 2 }
        XCTAssertTrue(otherCommitted)

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        let duplicatePromptAppeared = await waitUntil { model.pendingDuplicateConfirmation != nil }
        XCTAssertTrue(duplicatePromptAppeared)
        XCTAssertEqual(model.pendingDuplicateConfirmation?.encounterID, repeatedEncounter)
        XCTAssertEqual(model.successCount, 2)

        model.chooseSameCard()
        await settle()

        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.sessionScans.count, 2)
        XCTAssertEqual(model.successCount, 2)
        XCTAssertNil(model.scanAcknowledgement)
    }

    func testUndoRemovesOnlyTheUndoneEncounterProofAndKeepsOlderProof() async throws {
        let model = try makeModel(variants: [.normal])
        let firstEncounter = UUID()
        let secondEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        let firstCommitted = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(firstCommitted)
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: firstEncounter))
        await settle()

        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: secondEncounter)
        let secondCommitted = await waitUntil { model.sessionScans.count == 2 }
        XCTAssertTrue(secondCommitted)
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: secondEncounter))
        await settle()

        let secondScanID = try XCTUnwrap(
            model.sessionScans.first(where: { $0.card.cardNumber == "002" })?.id
        )
        let didUndo = await model.undoScan(scanID: secondScanID)
        XCTAssertTrue(didUndo)
        XCTAssertEqual(model.sessionScans.count, 1)

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        let duplicatePromptAppeared = await waitUntil {
            model.pendingDuplicateConfirmation != nil
        }
        XCTAssertTrue(duplicatePromptAppeared)
        XCTAssertEqual(model.sessionScans.count, 1)
        model.chooseSameCard()
        await settle()
        XCTAssertEqual(model.sessionScans.count, 1)
    }

    func testAddingAnotherCopyOfNewerCardKeepsOlderPresentationProof() async throws {
        let model = try makeModel(variants: [.normal])
        let firstEncounter = UUID()
        let otherEncounter = UUID()

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        let firstCommitted = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(firstCommitted)
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: firstEncounter))
        await settle()

        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: otherEncounter)
        let otherCommitted = await waitUntil { model.sessionScans.count == 2 }
        XCTAssertTrue(otherCommitted)
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: otherEncounter))
        await settle()
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
        let newerDuplicatePrompt = await waitUntil { model.pendingDuplicateConfirmation != nil }
        XCTAssertTrue(newerDuplicatePrompt)

        model.addAnother()
        let newerSecondCopyCommitted = await waitUntil {
            model.sessionScans.count == 3 && model.pendingDuplicateConfirmation == nil
        }
        XCTAssertTrue(newerSecondCopyCommitted)

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        let olderDuplicatePrompt = await waitUntil { model.pendingDuplicateConfirmation != nil }
        XCTAssertTrue(olderDuplicatePrompt)
        model.chooseSameCard()
        await settle()

        XCTAssertEqual(model.sessionScans.count, 3)
        XCTAssertEqual(model.successCount, 3)
    }

    func testHeldRepeatCommitKeepsProofForOlderUnrelatedCard() async throws {
        let model = try makeModel(variants: [.normal])
        let firstEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: firstEncounter)
        let firstCommitted = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(firstCommitted)
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: firstEncounter))
        await settle()

        let otherIdentifier = scannerIdentifier(cardNumber: "002")
        let otherSubject = ScanSubject(identifier: otherIdentifier)
        let start = CFAbsoluteTimeGetCurrent()
        var otherEncounter: UUID?
        let originalConfirmation = model.scanner.onConfirmedSubjectCandidate
        model.scanner.onConfirmedSubjectCandidate = { context, encounterID, subject, authorizationID in
            if subject.identifier == otherIdentifier {
                otherEncounter = encounterID
            }
            originalConfirmation?(context, encounterID, subject, authorizationID)
        }
        model.scanner.drainProfileQueuesForTesting()
        model.scanner.receiveFooterOutcomeForTesting(.identified(otherSubject), at: start + 0.25)
        model.scanner.receiveFooterOutcomeForTesting(.identified(otherSubject), at: start + 0.5)
        let otherCommitted = await waitUntil { model.sessionScans.count == 2 }
        XCTAssertTrue(otherCommitted)
        guard let otherEncounter else {
            return XCTFail("the second card did not produce a scanner encounter")
        }

        for offset in stride(from: 0.75, through: 2.5, by: 0.25) {
            model.scanner.receiveFooterOutcomeForTesting(.identified(otherSubject), at: start + offset)
        }
        model.scanner.onLatchHolding?(otherSubject, otherEncounter)
        let heldOfferAppeared = await waitUntil { model.heldDuplicateOffer != nil }
        XCTAssertTrue(heldOfferAppeared)
        guard heldOfferAppeared else { return }

        model.addAnotherHeldCopy()
        await settle()
        model.scanner.drainVisionQueueForTesting()
        model.scanner.receiveFooterOutcomeForTesting(.identified(otherSubject), at: start + 3.0)
        model.scanner.receiveFooterOutcomeForTesting(.identified(otherSubject), at: start + 3.25)
        let heldRepeatCommitted = await waitUntil { model.sessionScans.count == 3 }
        XCTAssertTrue(heldRepeatCommitted)

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        let olderDuplicatePrompt = await waitUntil { model.pendingDuplicateConfirmation != nil }
        XCTAssertTrue(olderDuplicatePrompt)
        XCTAssertEqual(model.sessionScans.count, 3)
        model.chooseSameCard()
        await settle()
        XCTAssertEqual(model.sessionScans.count, 3)
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
        XCTAssertNil(model.scanAcknowledgement)

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

    func testReturningToScanDoesNotWaitForCancelledIdentification() async throws {
        let fetchGate = ScannerFetchGate()
        let model = try makeModel(
            variants: [.normal],
            delayNanoseconds: 500_000_000,
            fetchGate: fetchGate
        )

        confirm(model, scannerIdentifier(), encounterID: UUID())
        await fetchGate.waitUntilStarted()

        model.viewDisappeared()
        model.start(
            context: context(),
            startCamera: false,
            shouldRefreshMagicDirectory: false
        )
        try await Task.sleep(for: .milliseconds(200))

        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
        let resumed = await waitUntil { model.sessionScans.count == 1 }

        XCTAssertTrue(resumed)
        XCTAssertEqual(model.sessionScans.first?.card.id, "pokemon:test-set-002")
    }

    func testCatalogMissFilesPromoWithNoCatalogEntryReasonImmediately() async throws {
        let model = try makeModel(variants: [.normal], catalogMiss: true)
        let identifier = try XCTUnwrap(ScanParser.parsePokemon("MEP 095"))
        let subject = ScanSubject(identifier: identifier)
        model.scanner.receiveFooterOutcomeForTesting(
            .identified(subject),
            at: CFAbsoluteTimeGetCurrent() + 0.25
        )
        model.scanner.receiveFooterOutcomeForTesting(
            .identified(subject),
            at: CFAbsoluteTimeGetCurrent() + 0.5
        )

        let failed = await waitUntil {
            model.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(
            model.scanAcknowledgement?.message,
            "Read MEP 095, but the catalog has no card with that number. Nothing was added."
        )
        let filed = await waitUntil { model.unresolvedScans.count == 1 }
        XCTAssertTrue(filed, "a deterministic catalog miss is filed on the first failure")
        XCTAssertEqual(model.unresolvedScans.first?.subject, subject)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .noCatalogEntry)
    }

    func testTransientAndProviderFailuresFileImmediatelyWithSpecificMessages() async throws {
        let transient = try makeModel(variants: [.normal], sourceFailure: .transient)
        confirm(transient, scannerIdentifier(), encounterID: UUID())
        let transientFiled = await waitUntil {
            transient.unresolvedScans.count == 1
                && transient.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(transientFiled)
        XCTAssertEqual(transient.unresolvedScans.first?.reason, .lookupFailed)
        XCTAssertEqual(
            transient.scanAcknowledgement?.message,
            "Couldn't reach the catalog — retrying. Keep the card in view."
        )

        let unavailable = try makeModel(variants: [.normal], sourceFailure: .providerUnavailable)
        confirm(unavailable, scannerIdentifier(), encounterID: UUID())
        let unavailableFiled = await waitUntil {
            unavailable.unresolvedScans.count == 1
                && unavailable.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(unavailableFiled)
        XCTAssertEqual(unavailable.unresolvedScans.first?.reason, .providerUnavailable)
        XCTAssertEqual(
            unavailable.scanAcknowledgement?.message,
            "Not added — card lookup is unavailable right now. Try again later."
        )
    }

    func testInferredNameMismatchFilesCandidateAndDoesNotCommit() async throws {
        let model = try makeModel(variants: [.normal])
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            inferredNameReadings: ["pikachu"]
        )
        confirm(model, subject, encounterID: UUID())

        let filed = await waitUntil {
            model.unresolvedScans.count == 1 && model.scanAcknowledgement?.phase == .failed
        }

        XCTAssertTrue(filed)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .noConfirmedMatch)
        XCTAssertEqual(model.unresolvedScans.first?.candidates.first?.name, "Test Card")
        XCTAssertEqual(
            model.scanAcknowledgement?.message,
            "Couldn't confirm which card this is. Saved to Needs attention."
        )
        XCTAssertEqual(model.successCount, 0)
        XCTAssertTrue(model.recent.isEmpty)
    }

    func testSuccessfulRetryLookupCommitsAndClearsItsUnresolvedRow() async throws {
        let failureSwitch = ScannerCatalogFailureSwitch()
        let model = try makeModel(
            variants: [.normal],
            sourceFailure: .transient,
            failureSwitch: failureSwitch
        )
        confirm(model, scannerIdentifier(), encounterID: UUID())
        let filed = await waitUntil { model.unresolvedScans.count == 1 }
        XCTAssertTrue(filed)
        let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)

        await failureSwitch.allowSuccess()
        model.resolveUnresolved(id: rowID, choice: .retryLookup)
        let committed = await waitUntil {
            model.successCount == 1 && model.unresolvedScans.isEmpty
        }

        XCTAssertTrue(committed)
        XCTAssertEqual(model.recent.count, 1)
    }

    func testChooseFromNeedsAttentionReachesFinishPickerAndKeepsDuplicateProtection() async throws {
        let fixture = try await makeHistoricalHeldRepeatFixture(includeFinishChoice: true)
        let model = try makeModel(
            variants: [.normal],
            setProviderID: "held-repeat-a",
            offline: fixture.offline
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "HRA",
            cardNumber: "001",
            printedTotal: 100,
            setDefinition: PokemonSetDefinition(
                printedCode: "HRA",
                tcgdexSetID: "held-repeat-a",
                officialCount: 100,
                releaseIndex: 1
            )
        )
        let mismatchedSubject = ScanSubject(
            identifier: identifier,
            inferredNameReadings: ["pikachu"]
        )

        confirm(model, mismatchedSubject, encounterID: UUID())
        let firstFailure = await waitUntil {
            model.unresolvedScans.count == 1 && model.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(firstFailure)
        let firstFailureSettled = await waitUntil {
            !model.isIdentificationProcessingForTesting
        }
        XCTAssertTrue(firstFailureSettled)
        let firstRowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        let candidates = await model.unresolvedCandidates(for: firstRowID)
        XCTAssertEqual(candidates.count, 2)
        let selected = try XCTUnwrap(
            candidates.first { $0.providerID == "held-repeat-a-001" }
        )

        model.resolveUnresolved(id: firstRowID, choice: .choose(selected))
        let finishPicker = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(
            finishPicker,
            "picker did not appear; acknowledgement=\(model.scanAcknowledgement?.message ?? "none"), unresolved=\(model.unresolvedScans.map { $0.reason.detail }), pending print run=\(model.pendingPrintRunChoice != nil)"
        )
        XCTAssertEqual(
            Set(model.pendingChoice?.options ?? []),
            Set([.normal, .holo])
        )

        model.choose(.normal)
        let committed = await waitUntil {
            model.successCount == 1 && model.unresolvedScans.isEmpty
        }
        XCTAssertTrue(committed)
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(model.recent.first?.card.providerID, "held-repeat-a-001")
        await settle()

        let secondEncounterID = UUID()
        confirm(model, mismatchedSubject, encounterID: secondEncounterID)
        let secondFailure = await waitUntil {
            model.unresolvedScans.count == 1
                && model.scanAcknowledgement?.encounterID == secondEncounterID
                && model.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(secondFailure)
        let secondFailureSettled = await waitUntil {
            !model.isIdentificationProcessingForTesting
        }
        XCTAssertTrue(secondFailureSettled)
        let secondRowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.resolveUnresolved(id: secondRowID, choice: .choose(selected))
        let duplicateHandled = await waitUntil {
            model.pendingChoice != nil
                || model.pendingDuplicateConfirmation != nil
                || (!model.unresolvedScans.contains { $0.id == secondRowID }
                    && !model.isIdentificationProcessingForTesting)
        }
        XCTAssertTrue(
            duplicateHandled,
            "duplicate recovery did not route; acknowledgement=\(model.scanAcknowledgement?.message ?? "none"), row remains=\(model.unresolvedScans.contains { $0.id == secondRowID }), read-only=\(model.unresolvedScans.first?.isReadOnly ?? false), reason=\(model.unresolvedScans.first?.reason.detail ?? "none"), pending choice=\(model.pendingChoice != nil), duplicate prompt=\(model.pendingDuplicateConfirmation != nil), processing=\(model.isIdentificationProcessingForTesting)"
        )
        if model.pendingChoice != nil {
            XCTAssertNotNil(model.pendingChoice?.duplicateChoiceContext)
            model.choose(.normal)
            await settle()
        }
        XCTAssertEqual(model.successCount, 1)
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
    }

    func testRetrySaveUsesTheInMemoryCandidateAndClearsTheRow() async throws {
        let addGate = ScannerCollectionAddGate(outcome: .failure)
        let model = try makeModel(
            variants: [.normal],
            collectionAddOverride: { candidate in
                try await addGate.add(candidate)
            }
        )
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await addGate.waitUntilStarted()
        await addGate.release()
        let failed = await waitUntil {
            model.unresolvedScans.count == 1
                && model.unresolvedScans.first?.reason != nil
                && model.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(failed)
        let row = try XCTUnwrap(model.unresolvedScans.first)
        guard case .saveFailed = row.reason else {
            return XCTFail("collection write failure should retain a retry-save candidate")
        }
        XCTAssertNotNil(row.pendingCommit)

        await addGate.allowSuccess()
        model.resolveUnresolved(id: row.id, choice: .retrySave)
        let saved = await waitUntil {
            model.successCount == 1 && model.unresolvedScans.isEmpty
        }
        XCTAssertTrue(
            saved,
            "retry save did not finish; acknowledgement=\(model.scanAcknowledgement?.message ?? "none"), unresolved=\(model.unresolvedScans.map { $0.reason.detail })"
        )
        let addCount = await addGate.count()
        XCTAssertEqual(addCount, 2)
    }

    func testUnresolvedRowsSurviveViewDepartureAndStart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerUnresolvedPersistence-\(UUID().uuidString)", isDirectory: true)
        let store = UnresolvedScanStore(
            fileURL: directory.appendingPathComponent("unresolved-scans.json")
        )
        let model = try makeModel(
            variants: [.normal],
            catalogMiss: true,
            unresolvedScanStore: store
        )
        confirm(model, scannerIdentifier(), encounterID: UUID())
        let filed = await waitUntil { model.unresolvedScans.count == 1 }
        XCTAssertTrue(filed)
        await store.save(model.unresolvedScans)

        model.viewDisappeared()
        model.start(
            context: context(),
            startCamera: false,
            shouldRefreshMagicDirectory: false
        )
        let survived = await waitUntil { model.unresolvedScans.count == 1 }

        XCTAssertTrue(survived)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .noCatalogEntry)
        try? FileManager.default.removeItem(at: directory)
    }

    func testUpdatingAPersistedUnresolvedRowDoesNotCountItAsNewThisSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerExistingUnresolved-\(UUID().uuidString)", isDirectory: true)
        let store = UnresolvedScanStore(
            fileURL: directory.appendingPathComponent("unresolved-scans.json")
        )
        let subject = ScanSubject(
            identifier: .pokemonHistorical(
                PokemonHistoricalScanEvidence(
                    number: PokemonPrintedNumberEvidence(
                        localID: "001",
                        denominator: 102,
                        scheme: .officialSet
                    ),
                    titleCandidates: ["Test Card"]
                )
            )
        )
        let existingRowID = UUID()
        await store.save([
            UnresolvedScan(
                id: existingRowID,
                subject: subject,
                reason: .noCatalogEntry
            )
        ])
        let summaryStore = ScanSessionSummaryStore()
        let model = try makeModel(
            variants: [.normal],
            catalogMiss: true,
            unresolvedScanStore: store
        )
        model.start(
            context: context(),
            startCamera: false,
            shouldRefreshMagicDirectory: false,
            summaryStore: summaryStore
        )
        let loaded = await waitUntil { model.unresolvedScans.count == 1 }
        XCTAssertTrue(loaded)
        XCTAssertEqual(model.unresolvedScans.first?.id, existingRowID)

        model.fileUnresolvedForTesting(subject, reason: .lookupFailed)
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertEqual(model.unresolvedScans.first?.id, existingRowID)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .lookupFailed)

        model.viewDisappeared()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(summaryStore.summary)
        try? FileManager.default.removeItem(at: directory)
    }

    func testTransientAutomaticRetriesStopAtTwoPerKeyPerSession() async throws {
        let model = try makeModel(variants: [.normal], sourceFailure: .transient)
        let identifier = scannerIdentifier()
        for _ in 0..<3 {
            let encounterID = UUID()
            confirm(model, identifier, encounterID: encounterID)
            let failed = await waitUntil {
                model.scanAcknowledgement?.encounterID == encounterID
                    && model.scanAcknowledgement?.phase == .failed
                    && model.unresolvedScans.count == 1
            }
            XCTAssertTrue(failed)
            await settle()
        }
        XCTAssertEqual(model.transientRetryCountForTesting(for: identifier.suppressionKey), 2)
    }

    func testProviderUnavailableAcknowledgementSaysTryAgainLater() {
        XCTAssertEqual(CardCatalog.classify(ScryfallError.providerUnavailable), .providerUnavailable)
        XCTAssertEqual(
            ScannerViewModel.failureAcknowledgementMessage(
                for: .providerUnavailable,
                unresolvedReason: .noConfirmedMatch,
                displayIdentifier: "TST 1/10"
            ),
            "Not added — card lookup is unavailable right now. Try again later."
        )
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

    func testImportAndDeleteBulkOperationsAreMutuallyExclusive() throws {
        let coordinator = DerivedStateWriteCoordinator()
        let importToken = try XCTUnwrap(coordinator.beginCSVImport(totalEntries: 12))

        XCTAssertEqual(coordinator.activeExclusiveOperation, .csvImport)
        XCTAssertTrue(coordinator.isBulkWriteInFlight)
        XCTAssertNil(coordinator.beginCollectionDelete())
        coordinator.updateCSVImportProgress(
            CSVImportProgress(completedEntries: 4, totalEntries: 12),
            token: importToken
        )
        XCTAssertEqual(
            coordinator.csvImportProgress,
            CSVImportProgress(completedEntries: 4, totalEntries: 12)
        )

        coordinator.endCSVImport(token: importToken)
        XCTAssertNil(coordinator.activeExclusiveOperation)
        XCTAssertFalse(coordinator.isBulkWriteInFlight)
        XCTAssertNil(coordinator.csvImportProgress)

        let deleteToken = try XCTUnwrap(coordinator.beginCollectionDelete())
        XCTAssertEqual(coordinator.activeExclusiveOperation, .collectionDelete)
        XCTAssertNil(coordinator.beginCSVImport(totalEntries: 1))
        coordinator.endCollectionDelete(token: deleteToken)
        XCTAssertNil(coordinator.activeExclusiveOperation)
        XCTAssertFalse(coordinator.isBulkWriteInFlight)
    }

    func testSettingsReleasesAndRestoresScannerBulkWriteInterval() throws {
        let coordinator = DerivedStateWriteCoordinator()
        let model = try makeModel(
            variants: [.normal],
            writeCoordinator: coordinator
        )

        XCTAssertTrue(coordinator.isBulkWriteInFlight)
        model.pauseForSettingsPresentation()
        XCTAssertFalse(coordinator.isBulkWriteInFlight)

        let importToken = try XCTUnwrap(coordinator.beginCSVImport(totalEntries: 1))
        coordinator.endCSVImport(token: importToken)
        let deleteToken = try XCTUnwrap(coordinator.beginCollectionDelete())
        coordinator.endCollectionDelete(token: deleteToken)

        model.resumeAfterSettingsPresentation()
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
        guard case .duplicate(.spatialExit(_)) = CollectionCandidateRoutingPolicy.decision(
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
            UnresolvedScan.merging(
                [],
                with: ScanSubject(identifier: first),
                reason: .noConfirmedMatch
            ),
            with: ScanSubject(identifier: second),
            reason: .noConfirmedMatch
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
            UnresolvedScan.merging([], with: first, reason: .noConfirmedMatch),
            with: second,
            reason: .noConfirmedMatch
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.subject.slab, slab)
    }

    private func makeModel(
        variants: [PhysicalVariant],
        secondaryVariants: [PhysicalVariant]? = nil,
        tertiaryVariants: [PhysicalVariant]? = nil,
        delayNanoseconds: UInt64 = 0,
        fetchGate: ScannerFetchGate? = nil,
        catalogMiss: Bool = false,
        gradedOutcome: ScannedGradedOutcome? = nil,
        setProviderID: String = "test-set",
        gradedRunRecorder: ScannerPrintRunRecorder? = nil,
        gradedResolverGate: ScannerGradedResolverGate? = nil,
        writeCoordinator: DerivedStateWriteCoordinator? = nil,
        priceCheckOutcome: PriceCheckRefreshOutcome? = nil,
        storageGeneration: CollectionStorageGeneration? = nil,
        collectionAddOverride: (@Sendable (CollectionCommitCandidate) async throws -> CollectionMutation)? = nil,
        sourceFailure: ScannerStubPokemonSource.Failure? = nil,
        failureSwitch: ScannerCatalogFailureSwitch? = nil,
        unresolvedScanStore: UnresolvedScanStore? = nil,
        offline: PokemonOfflineCatalog? = nil
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
                    ),
                    "003": catalogCard(
                        variants: tertiaryVariants ?? variants,
                        localID: "003",
                        setID: setProviderID
                    )
                ],
                delayNanoseconds: delayNanoseconds,
                fetchGate: fetchGate,
                catalogMiss: catalogMiss,
                failure: sourceFailure,
                failureSwitch: failureSwitch
            ),
            offline: offline ?? PokemonOfflineCatalog(store: checklistStore),
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
                ScannerStubGradedResolver(
                    outcome: $0,
                    recorder: gradedRunRecorder,
                    gate: gradedResolverGate
                )
            }
                ?? ScannedGradedResolver(),
            priceCheckRefreshProvider: priceCheckOutcome.map {
                ScannerStubPriceCheckProvider(outcome: $0)
            },
            unresolvedScanStore: unresolvedScanStore ?? UnresolvedScanStore(
                fileURL: root.appendingPathComponent("Scanner/unresolved-scans.json")
            ),
            collectionAddOverride: collectionAddOverride
        )
        model.start(
            context: context,
            isSceneActive: true,
            startCamera: false,
            shouldRefreshMagicDirectory: false,
            writeCoordinator: writeCoordinator,
            storageGeneration: storageGeneration
        )
        return model
    }

    private func makeHistoricalHeldRepeatFixture(
        includeFinishChoice: Bool = false
    ) async throws -> (
        offline: PokemonOfflineCatalog,
        first: ScanSubject,
        second: ScanSubject
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TradingCardScannerHistoricalHeldRepeat-\(UUID().uuidString)", isDirectory: true)
        let store = PokemonChecklistStore(root: root, bundle: nil, bundledRoot: root)
        let firstSetID = CatalogSetID(game: .pokemon, providerID: "held-repeat-a")
        let secondSetID = CatalogSetID(game: .pokemon, providerID: "held-repeat-b")
        let firstSet = CatalogSet(
            catalogID: firstSetID,
            name: "Held Repeat A",
            code: "HRA",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 100,
            releaseDate: nil,
            sortRank: 1
        )
        let secondSet = CatalogSet(
            catalogID: secondSetID,
            name: "Held Repeat B",
            code: "HRB",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 100,
            releaseDate: nil,
            sortRank: 2
        )
        let firstSummary = CatalogCardSummary(
            game: .pokemon,
            providerID: "held-repeat-a-001",
            setID: firstSetID,
            setName: firstSet.name,
            setCode: firstSet.code,
            name: "First Held Card",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: includeFinishChoice ? .normal : nil
        )
        let firstHoloSummary = CatalogCardSummary(
            game: .pokemon,
            providerID: "held-repeat-a-001",
            setID: firstSetID,
            setName: firstSet.name,
            setCode: firstSet.code,
            name: "First Held Card",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .holo
        )
        let secondSummary = CatalogCardSummary(
            game: .pokemon,
            providerID: "held-repeat-b-001",
            setID: secondSetID,
            setName: secondSet.name,
            setCode: secondSet.code,
            name: "Second Held Card",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "scanner-held-repeat",
                entries: [
                    PokemonChecklistSnapshotEntry(
                        set: firstSet,
                        providerID: firstSet.providerID,
                        officialCount: 100,
                        standardSlotCount: 100,
                        expandedSlotCount: 100,
                        resource: "held-repeat-a.json"
                    ),
                    PokemonChecklistSnapshotEntry(
                        set: secondSet,
                        providerID: secondSet.providerID,
                        officialCount: 100,
                        standardSlotCount: 100,
                        expandedSlotCount: 100,
                        resource: "held-repeat-b.json"
                    )
                ]
            ),
            checklists: [
                firstSetID.id: includeFinishChoice ? [firstSummary, firstHoloSummary] : [firstSummary],
                secondSetID.id: [secondSummary]
            ]
        )
        try await store.replace(snapshot)

        let number = PokemonPrintedNumberEvidence(
            localID: "001",
            denominator: 100,
            scheme: .officialSet
        )
        func subject(named name: String) -> ScanSubject {
            ScanSubject(
                identifier: .pokemonHistorical(
                    PokemonHistoricalScanEvidence(
                        number: number,
                        titleCandidates: [CatalogIdentityNormalization.canonicalText(name)]
                    )
                )
            )
        }
        return (
            PokemonOfflineCatalog(store: store),
            subject(named: firstSummary.name),
            subject(named: secondSummary.name)
        )
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
        encounterID: UUID,
        authorizationID: UUID? = nil
    ) {
        confirm(
            model,
            ScanSubject(identifier: identifier),
            encounterID: encounterID,
            authorizationID: authorizationID
        )
    }

    private func confirm(
        _ model: ScannerViewModel,
        _ subject: ScanSubject,
        encounterID: UUID,
        authorizationID: UUID? = nil
    ) {
        model.scanner.onConfirmedSubjectCandidate?(nil, encounterID, subject, authorizationID)
    }

    private func useSlabMode(_ model: ScannerViewModel) {
        model.setSubjectMode(.slab)
        XCTAssertEqual(model.scanner.subjectModeForTesting, .slab)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
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

    private func assertEventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let didSucceed = await waitUntil(condition)
        XCTAssertTrue(didSucceed)
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
