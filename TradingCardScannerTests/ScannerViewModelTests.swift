import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

private actor ScannerFetchGate {
    private var hasStarted = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

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

    func hold() async {
        markStarted()
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
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
    private var capturedCandidates: [CollectionCommitCandidate] = []
    private var hasStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(outcome: Outcome, successfulAddsBeforeBlocking: Int = 0) {
        self.outcome = outcome
        self.successfulAddsBeforeBlocking = successfulAddsBeforeBlocking
    }

    func add(_ candidate: CollectionCommitCandidate) async throws -> CollectionMutation {
        capturedCandidates.append(candidate)
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

    func captured() -> [CollectionCommitCandidate] {
        capturedCandidates
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
    let fetchHoldGates: [String: ScannerFetchGate]
    let catalogMiss: Bool
    let failure: Failure?
    let failureSwitch: ScannerCatalogFailureSwitch?

    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        await fetchGate?.markStarted()
        await fetchHoldGates[Int(localID).map(String.init) ?? localID]?.hold()
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

private actor ScannerGradedLookupCounter {
    private var count = 0
    func isFirstCall() -> Bool { count += 1; return count == 1 }
}

private struct ScannerStubGradedResolver: ScannedGradedResolving {
    let outcome: ScannedGradedOutcome
    let subsequentOutcome: ScannedGradedOutcome?
    let recorder: ScannerPrintRunRecorder?
    let gate: ScannerGradedResolverGate?
    private let calls = ScannerGradedLookupCounter()

    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome {
        await recorder?.record(pokemonPrintRun)
        await gate?.pause()
        return await calls.isFirstCall() ? outcome : (subsequentOutcome ?? outcome)
    }
}

private actor ScannerGradedResolverGate {
    private var hasStarted = false
    private var allowsFutureCalls = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        if allowsFutureCalls { return }
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

    func release(andFutureCalls: Bool = false) {
        allowsFutureCalls = andFutureCalls
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

@MainActor
private final class ScannerGatedPriceCheckProvider: PriceCheckRefreshProvider {
    let gate = ScannerFetchGate()
    private(set) var calls = 0

    func refresh(card: IdentifiedCard, variant: PhysicalVariant?, pokemonPrintRun: PokemonPrintRun?) async -> PriceCheckRefreshOutcome {
        calls += 1
        let first = calls == 1
        if first { await gate.hold() }
        // Deliberately ignore cancellation, as a late transport response may.
        return .quote(.price(NormalizedPrice(unitMarketPriceUSD: first ? 999 : 4.43,
            currencyCode: "USD", source: .tcgplayer, sourceVariantID: "normal",
            sourceUpdatedAt: .now.addingTimeInterval(-12 * 24 * 60 * 60), fetchedAt: .now)))
    }
}

private actor ScannerPrintRunRecorder {
    private(set) var values: [PokemonPrintRun?] = []

    func record(_ value: PokemonPrintRun?) {
        values.append(value)
    }

    func snapshot() -> [PokemonPrintRun?] {
        values
    }
}

/// ScannerViewModel is the orchestration boundary for the camera, catalog,
/// persistence, and the choice sheets. These tests drive its callbacks directly
/// so the state-machine contracts can be checked without a camera or network.
private struct ScannerPrintingCatalogFixture: GameCatalogAdapter {
    let game = CardGame.onePiece
    let generation = "printing-fixture-1"
    let retrievedAt = Date(timeIntervalSince1970: 12345)

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        .needsPrintingChoice(
            canonical: .init(id: "one-piece:en:OP01-120", game: game, name: "Shanks",
                             printedIdentifier: "OP01-120", language: "en"),
            candidates: ["first-uuid", "second-uuid"].map { id in
                .init(id: id, game: game, canonicalCardID: "one-piece:en:OP01-120",
                      language: "en", catalogGeneration: generation, name: "Shanks",
                      printedIdentifier: "OP01-120", releaseLabel: id == "first-uuid" ? "Original release" : "Premium release",
                      treatmentLabel: nil, distributionLabel: nil, releaseDate: nil, thumbnailURL: nil)
            }
        )
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        let card = try ResolvedCatalogCard(
            game: game, physicalPrintingID: candidate.id, canonicalCardID: candidate.canonicalCardID,
            language: "en", name: "Shanks", setName: candidate.releaseLabel ?? "Release",
            setCode: "OP01", cardNumber: "OP01-120", printedIdentifier: "OP01-120",
            variantEvidence: .init(game: game, setID: "fixture", cardNumber: "OP01-120",
                                   catalogVariants: [.normal, .foil])
        )
        return .init(card, retrievedAt: retrievedAt, path: .cacheHit)
    }
}

@MainActor
final class ScannerViewModelTests: XCTestCase {
    private func printingIdentifier() throws -> ScanIdentifier {
        try .init(game: .onePiece, namespace: "numbered-card",
                  fields: [.init(key: "number", value: "OP01-120")], displayIdentifier: "OP01-120",
                  suppressionIdentity: "OP01-120", catalogGeneration: "printing-fixture-1")
    }

    func testGenericPrintingChoicePrecedesVariantAndPreservesCatalogTimestamp() async throws {
        let model = try makeModel(variants: [.normal], printingCatalog: ScannerPrintingCatalogFixture())
        confirm(model, try printingIdentifier(), encounterID: UUID())
        let appeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(appeared)
        XCTAssertNil(model.pendingChoice)
        XCTAssertTrue(model.recent.isEmpty)
        let choice = try XCTUnwrap(model.pendingIdentityChoice)
        XCTAssertEqual(choice.displayCandidates.count, 2)
        model.choose(choice.displayCandidates[1])
        let finishAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(finishAppeared)
        XCTAssertEqual(model.pendingChoice?.card.physicalPrintingID, "second-uuid")
        XCTAssertEqual(model.pendingChoice?.catalogRetrievedAt, Date(timeIntervalSince1970: 12345))
        XCTAssertEqual(model.pendingChoice?.identityResolution, .userSelectedPrinting)
        XCTAssertNil(model.pendingIdentityChoice)
        model.viewDisappeared()
    }

    func testClassicPhotoFootersOfferBothPrintingsBeforeFinishOrCollectionWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root)
        let classicSet = CatalogSet(
            catalogID: .init(game: .pokemon, providerID: "30th-c"),
            name: "30th Celebration Classic Collection", code: "30C",
            logoURL: nil, symbolURL: nil, cardCount: 30, releaseDate: nil, sortRank: 1
        )
        let classicCards = [("003", "Metagross"), ("014", "Pikachu")].map { number, name in
            CatalogCardSummary(
                game: .pokemon, providerID: "30th-c-\(number)", setID: classicSet.catalogID,
                setName: classicSet.name, setCode: classicSet.code, name: name,
                collectorNumber: number, thumbnailURL: nil, imageURL: nil, masterSetVariant: .normal
            )
        }
        try await store.replace(PokemonChecklistSnapshot(
            manifest: .init(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now, directoryFingerprint: "classic-photo-test",
                entries: [.init(
                    set: classicSet, providerID: "30th-c", officialCount: 30,
                    standardSlotCount: 30, expandedSlotCount: 30, resource: "classic.json"
                )]
            ),
            checklists: [classicSet.id: classicCards]
        ))
        let fixtures = [
            (footer: "11/113", title: "Metagross δ", original: "ex11-11", classic: "30th-c-003"),
            (footer: "11/113", title: "Metagross", original: "ex11-11", classic: "30th-c-003"),
            (footer: "58/102", title: "Pikachu", original: "base1-58", classic: "30th-c-014")
        ]
        for fixture in fixtures {
            let model = try makeModel(variants: [.normal], offline: PokemonOfflineCatalog(store: store))
            let identifier = try XCTUnwrap(PokemonHistoricalScanParser.parse(
                numberLines: [fixture.footer], titleLines: [fixture.title]
            ))
            confirm(model, identifier, encounterID: UUID())
            let appeared = await waitUntil { model.pendingIdentityChoice != nil }
            XCTAssertTrue(appeared, fixture.title)
            let choice = try XCTUnwrap(model.pendingIdentityChoice)
            XCTAssertEqual(Set(choice.candidates.map(\.providerID)), [fixture.original, fixture.classic])
            XCTAssertTrue(choice.displayCandidates.contains { $0.releaseLabel == "30th Classic · 2026" })
            XCTAssertNil(model.pendingChoice)
            XCTAssertNil(model.pendingPrintRunChoice)
            XCTAssertTrue(model.recent.isEmpty)
            let classic = try XCTUnwrap(choice.candidates.first { $0.providerID == fixture.classic })
            model.choose(classic)
            let saved = await waitUntil { model.recent.first?.card.providerID == fixture.classic }
            XCTAssertTrue(saved, fixture.title)
            XCTAssertEqual(model.recent.first?.card.variantEvidence.setID, "30th-c")
            XCTAssertEqual(model.recent.first?.card.displayCardNumber, fixture.footer)
            let rows = try context().fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.providerID, fixture.classic)
            XCTAssertEqual(rows.first?.identityResolution, .userSelectedPrinting)
            model.viewDisappeared()
        }
    }

    func testDismissedGenericPrintingChoicesRetainSeparateEncounters() async throws {
        let model = try makeModel(variants: [.normal], printingCatalog: ScannerPrintingCatalogFixture())
        let identifier = try printingIdentifier()
        let first = UUID()
        let second = UUID()
        confirm(model, identifier, encounterID: first)
        let firstAppeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(firstAppeared)
        model.dismissIdentityChoice()
        confirm(model, identifier, encounterID: second)
        let secondAppeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(secondAppeared)
        model.dismissIdentityChoice()
        XCTAssertEqual(Set(model.unresolvedScans.map(\.id)), Set([first, second]))
        XCTAssertEqual(model.unresolvedScans.map(\.identifier), [identifier, identifier])
        XCTAssertEqual(model.successCount, 0)
        model.viewDisappeared()
    }

    func testGenericRecoveryFailureKeepsPendingCommitAndAdditionalCopyConfirmation() throws {
        let model = try makeModel(variants: [.normal], printingCatalog: ScannerPrintingCatalogFixture())
        defer { model.viewDisappeared() }
        let subject = ScanSubject(identifier: try printingIdentifier())
        let card = try ResolvedCatalogCard(game: .onePiece, physicalPrintingID: "first-uuid",
            canonicalCardID: "one-piece:en:OP01-120", language: "en", name: "Shanks", setName: "Release",
            setCode: "OP01", cardNumber: "OP01-120", printedIdentifier: "OP01-120",
            variantEvidence: .init(game: .onePiece, setID: "fixture", cardNumber: "OP01-120", catalogVariants: [.normal]))
        let pending = CollectionCommitCandidate(resolvedScan: .init(request: .init(subject: subject,
            purpose: .collection, generation: 0), card: card, resolved: .init(variant: .normal, resolution: .userConfirmed),
            pokemonPrintRun: nil, options: [.normal]))
        model.fileUnresolvedForTesting(subject, reason: .saveFailed(inMemoryCandidateID: pending.requestID),
            isAdditionalCopy: true, pendingCommit: pending)
        let row = try XCTUnwrap(model.unresolvedScans.first)
        model.fileUnresolvedForTesting(subject, reason: .lookupFailed, matchingID: row.id)
        let retried = try XCTUnwrap(model.unresolvedScans.first)
        XCTAssertEqual(retried.id, row.id)
        XCTAssertTrue(retried.isAdditionalCopy)
        XCTAssertEqual(retried.pendingCommit?.requestID, pending.requestID)
        XCTAssertEqual(retried.createdAt, row.createdAt)
    }

    func testDismissingPokemonHistoricalChoiceDoesNotFileNewRecoveryRow() throws {
        let model = try makeModel(variants: [.normal])
        defer { model.viewDisappeared() }
        let identifier = ScanIdentifier.pokemonHistorical(.init(number: .init(localID: "001", denominator: 100,
            scheme: .officialSet), titleCandidates: []))
        model.handleHistoricalResolutionForTesting(.ambiguous([
            .init(providerID: "first-001", setID: "first", setName: "First", localID: "001", name: "Fixture Card"),
            .init(providerID: "second-001", setID: "second", setName: "Second", localID: "001", name: "Fixture Card")
        ]), subject: .init(identifier: identifier))
        XCTAssertNotNil(model.pendingIdentityChoice)
        model.dismissIdentityChoice()
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testGenericPrintingChoiceSurvivesStoreReloadAndRecoverySelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("unresolved.json")
        let store = UnresolvedScanStore(fileURL: fileURL)
        let adapter = ScannerPrintingCatalogFixture()
        let model = try makeModel(variants: [.normal], unresolvedScanStore: store, printingCatalog: adapter)
        confirm(model, try printingIdentifier(), encounterID: UUID())
        let appeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(appeared)
        model.dismissIdentityChoice()
        let row = try XCTUnwrap(model.unresolvedScans.first)
        XCTAssertEqual(row.printingCandidates.count, 2)
        let didSave = await store.save(model.unresolvedScans)
        XCTAssertTrue(didSave)
        let registered = try GameCatalogAdapterRegistry(adapters: [adapter])
        let restored = await UnresolvedScanStore(fileURL: fileURL).load(gameCatalogAdapters: registered)
        XCTAssertEqual(restored.first?.printingCandidates, row.printingCandidates)
        XCTAssertEqual(restored.first?.identifier, row.identifier)
        XCTAssertFalse(try XCTUnwrap(restored.first).isReadOnly)
        let unsupported = await UnresolvedScanStore(fileURL: fileURL).load()
        XCTAssertTrue(try XCTUnwrap(unsupported.first).isReadOnly)
        XCTAssertEqual(unsupported.first?.printingCandidates, row.printingCandidates)
        model.resolveUnresolved(id: row.id, choice: .printing(row.printingCandidates[0]))
        let finishAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(finishAppeared)
        XCTAssertEqual(model.pendingChoice?.card.physicalPrintingID, "first-uuid")
        XCTAssertEqual(model.pendingChoice?.request.unresolvedScanID, row.id)
        XCTAssertEqual(model.pendingChoice?.catalogRetrievedAt, adapter.retrievedAt)
        model.viewDisappeared()
    }
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

    func testRawFallbackCannotOverwriteConvertedGradedScan() async throws {
        let gradedVariant = GradedVariant(
            id: "converted-graded", cardID: "converted-card", company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            printing: "Normal",
            marketPriceUSD: 250, updatedAt: nil
        )
        let rawQuote = PriceLookup.price(NormalizedPrice(
            unitMarketPriceUSD: 12, currencyCode: "USD", source: .justTCG,
            sourceVariantID: "raw", sourceUpdatedAt: nil, fetchedAt: .now
        ))
        for outcome in [ScannedGradedOutcome.bound(gradedVariant), .unavailable] {
            let gate = ScannerGradedResolverGate()
            let model = try makeModel(
                variants: [.normal], gradedOutcome: outcome, gradedResolverGate: gate
            )
            let encounterID = UUID()
            confirm(model, scannerIdentifier(), encounterID: encounterID)
            let committed = await waitUntil { model.sessionScans.count == 1 }
            XCTAssertTrue(committed)
            let rawScan = try XCTUnwrap(model.sessionScans.first)
            // The same delivery path must still publish quotes to eligible raw scans.
            model.deliverFallbackQuoteForTesting(rawQuote, requestedScan: rawScan)
            XCTAssertEqual(model.recent.first?.price, rawQuote)

            let slab = try XCTUnwrap(gradedSubject(value: "10", label: "Gem Mint").slab)
            model.scanner.onPostCommitSlabEvidence?(encounterID, slab)
            let offered = await waitUntil { model.pendingSlabConversionOffer != nil }
            XCTAssertTrue(offered)
            await model.convertRawScanToGraded(scanID: rawScan.id)
            await gate.waitUntilStarted()
            let pendingPrice = try XCTUnwrap(model.sessionScans.first?.price)
            model.deliverFallbackQuoteForTesting(rawQuote, requestedScan: rawScan)
            XCTAssertEqual(model.sessionScans.first?.price, pendingPrice)
            XCTAssertEqual(model.recent.first?.price, pendingPrice)
            XCTAssertEqual(model.receipt?.price, pendingPrice)
            XCTAssertTrue(model.sessionScans.first?.isGradedPricePending == true)

            await gate.release()
            let completed = await waitUntil { model.sessionScans.first?.isGradedPricePending == false }
            XCTAssertTrue(completed)
            let finalPrice = try XCTUnwrap(model.sessionScans.first?.price)
            if case .bound = outcome {
                guard case let .price(price) = finalPrice else {
                    XCTFail("Expected graded price")
                    continue
                }
                XCTAssertEqual(price.unitMarketPriceUSD, 250)
            } else {
                XCTAssertEqual(finalPrice, pendingPrice)
            }
            model.deliverFallbackQuoteForTesting(rawQuote, requestedScan: rawScan)
            XCTAssertEqual(model.sessionScans.first?.price, finalPrice)
            XCTAssertEqual(model.recent.first?.price, finalPrice)
            XCTAssertEqual(model.receipt?.price, finalPrice)
            XCTAssertFalse(model.sessionScans.first?.isGradedPricePending == true)
        }
    }

    func testCatalogObserversReleaseReplacedModels() async throws {
        let pokemon = PokemonCatalogCoordinator(rolloutMode: .bundledValidationOnly)
        let magic = MagicCatalogCoordinator(rolloutMode: .legacyLive)
        for _ in 0..<3 {
            var model: ScannerViewModel? = try makeModel(
                variants: [.normal], catalogCoordinator: pokemon,
                magicCatalogCoordinator: magic
            )
            weak var releasedModel = model
            await settle()
            XCTAssertNotNil(releasedModel)
            model = nil
            let released = await waitUntil { releasedModel == nil }
            XCTAssertTrue(released, "Catalog stream waits must not retain the scanner model")
        }
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
            printing: "Normal",
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

    func testSlabBindingCompletesAfterSessionEndsDuringLookupWithoutChangingReplacementSession() async throws {
        for restartScanner in [false, true] {
            let variant = GradedVariant(id: "graded-after-lookup-departure", cardID: "graded-card",
                company: .psa, grade: CardGrade(value: "10", label: "Gem Mint"), printing: "Normal",
                marketPriceUSD: 250, updatedAt: nil)
            let gate = ScannerGradedResolverGate()
            let model = try makeModel(variants: [.normal], gradedOutcome: .bound(variant), gradedResolverGate: gate)
            let container = try XCTUnwrap(self.container)
            useSlabMode(model)
            confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
            await gate.waitUntilStarted()
            XCTAssertEqual(model.sessionScans.count, 1)
            model.endSession()
            if restartScanner {
                model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false)
                confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
                await assertEventually { model.sessionScans.count == 1 }
            }
            let scanIDs = model.sessionScans.map(\.id)
            let receipt = model.receipt
            let note = model.note
            await gate.release()

            let bound = await waitUntil {
                let verification = ModelContext(container)
                guard let row = try? verification.fetch(FetchDescriptor<CollectedCard>()).first(where: { $0.itemKind == .gradedCard }),
                      row.justTCGVariantID == variant.id else { return false }
                return PriceStore(context: verification).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD == 250
            }
            XCTAssertTrue(bound)
            XCTAssertEqual(model.sessionScans.map(\.id), scanIDs)
            XCTAssertEqual(model.recent.map(\.id), scanIDs)
            XCTAssertEqual(model.receipt?.scanID, receipt?.scanID)
            XCTAssertEqual(model.note?.text, note?.text)
            model.endSession()
        }
    }

    func testGradedCoverageCompletesAfterSessionEndsDuringLookup() async throws {
        let gate = ScannerGradedResolverGate()
        let coverage = GradedMarketCoverage(status: .gradeNotListed, variants: [], targetCompany: .psa,
            targetGrade: .init(value: "10", label: "Gem Mint"))
        let model = try makeModel(variants: [.normal], gradedOutcome: .gradeNotTracked(coverage), gradedResolverGate: gate)
        let container = try XCTUnwrap(self.container)
        useSlabMode(model)
        confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
        await gate.waitUntilStarted()
        model.endSession()
        await gate.release()

        let saved = await waitUntil {
            let verification = ModelContext(container)
            guard let row = try? verification.fetch(FetchDescriptor<CollectedCard>()).first else { return false }
            return PriceStore(context: verification).record(forKey: row.priceKey)?.gradedMarketCoverage == coverage
        }
        XCTAssertTrue(saved)
        XCTAssertTrue(model.sessionScans.isEmpty)
        XCTAssertNil(model.receipt)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testDepartedGradedLookupCannotWriteAfterStorageGenerationIsReplaced() async throws {
        let generation = CollectionStorageGeneration()
        generation.installReady(storeID: UUID())
        let variant = GradedVariant(id: "old-generation-listing", company: .psa,
            grade: .init(value: "10", label: "Gem Mint"), printing: "Normal", marketPriceUSD: 250, updatedAt: nil)
        let gate = ScannerGradedResolverGate()
        let model = try makeModel(variants: [.normal], gradedOutcome: .bound(variant),
            gradedResolverGate: gate, storageGeneration: generation)
        let container = try XCTUnwrap(self.container)
        useSlabMode(model)
        confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
        await gate.waitUntilStarted()
        model.endSession()
        generation.suspend()
        generation.installReady(storeID: UUID())
        model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false, storageGeneration: generation)
        await gate.release()
        await settle()

        let verification = ModelContext(container)
        XCTAssertNil(try verification.fetch(FetchDescriptor<CollectedCard>()).first?.justTCGVariantID)
        XCTAssertFalse(try verification.fetch(FetchDescriptor<PriceRecord>()).contains { $0.marketVariantID == variant.id })
        XCTAssertTrue(model.sessionScans.isEmpty)
        XCTAssertNil(model.receipt)
        model.endSession()
    }

    func testDepartedGradedLookupCannotRestoreAnUndoneOrCorrectedHolding() async throws {
        for correctFinish in [false, true] {
            let variant = GradedVariant(id: "obsolete-normal-listing", company: .psa,
                grade: .init(value: "10", label: "Gem Mint"), printing: "Normal", marketPriceUSD: 250, updatedAt: nil)
            let gate = ScannerGradedResolverGate()
            let model = try makeModel(variants: correctFinish ? [.normal, .holo] : [.normal],
                gradedOutcome: .bound(variant), gradedResolverGate: gate)
            let container = try XCTUnwrap(self.container)
            useSlabMode(model)
            confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
            await gate.waitUntilStarted()
            let scanID = try XCTUnwrap(model.sessionScans.first?.id)
            if correctFinish {
                let result = await model.correct(scanID: scanID, to: .holo)
                XCTAssertEqual(result, .saved)
            } else {
                let undone = await model.undoScan(scanID: scanID)
                XCTAssertTrue(undone)
            }
            model.endSession()
            await gate.release(andFutureCalls: true)
            await settle()

            let verification = ModelContext(container)
            let rows = try verification.fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, correctFinish ? 1 : 0)
            XCTAssertNil(rows.first?.justTCGVariantID)
            if correctFinish { XCTAssertEqual(rows.first?.variant, .holo) }
            XCTAssertFalse(try verification.fetch(FetchDescriptor<PriceRecord>()).contains { $0.marketVariantID == variant.id })
            XCTAssertTrue(model.sessionScans.isEmpty)
        }
    }

    func testSlabBindingCompletesAfterScannerSessionEndsDuringGateWait() async throws {
        let variant = GradedVariant(
            id: "graded-v2-after-session-end",
            cardID: "graded-card-after-session-end",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            printing: "Normal",
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
            printing: "Normal",
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

    func testLateCertificateRefinementCannotPublishIntoReplacementSession() async throws {
        enum Outcome: CaseIterable { case missing, duplicate, failure, saved }
        for outcome in Outcome.allCases {
            let gate = ScannerFetchGate()
            var didFinish = false
            let model = try makeModel(
                variants: [.normal],
                gradedOutcome: .unavailable,
                certificationRefinementOverride: { [weak self] scan, slab in
                    await gate.hold()
                    defer { didFinish = true }
                    switch outcome {
                    case .missing: return nil
                    case .duplicate:
                        return CollectionMutation(collectionKey: scan.mutation.collectionKey,
                                                  activityID: nil, didInsert: false, wasDuplicate: true)
                    case .failure: throw ScannerCollectionAddGateError.failed
                    case .saved:
                        let container = try XCTUnwrap(self).context().container
                        return try await ScannerCollectionWriter(modelContainer: container)
                            .refineGradedCertification(for: scan, to: slab)
                    }
                }
            )
            useSlabMode(model)
            let encounterID = UUID()
            let previous = gradedSubject(value: "10", label: "Gem Mint", certificationNumber: nil)
            let updated = gradedSubject(value: "10", label: "Gem Mint")
            confirm(model, previous, encounterID: encounterID)
            await assertEventually { model.sessionScans.count == 1 }
            model.scanner.onGradedSlabCertificationRefined?(encounterID, previous, updated)
            await gate.waitUntilStarted()

            // Exercise the actual bounded departure drain and queued reentry.
            model.viewDisappeared()
            model.start(context: try context(), isSceneActive: true,
                        startCamera: false, shouldRefreshMagicDirectory: false)
            await assertEventually { model.isScannerSessionActiveForTesting && model.sessionScans.isEmpty }
            confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
            await assertEventually { model.sessionScans.count == 1 }
            let newScan = try XCTUnwrap(model.sessionScans.first)
            let note = model.note
            let receipt = model.receipt
            await gate.release()
            await assertEventually { didFinish }
            await settle()
            XCTAssertEqual(model.successCount, 1)
            XCTAssertEqual(model.sessionScans.map(\.id), [newScan.id])
            XCTAssertEqual(model.recent.map(\.id), [newScan.id])
            XCTAssertEqual(model.receipt?.scanID, receipt?.scanID)
            XCTAssertEqual(model.note?.text, note?.text)
            if case .saved = outcome {
                let rows = try context().fetch(FetchDescriptor<CollectedCard>())
                XCTAssertTrue(rows.contains { $0.certificationNumber == "12345678" })
            }
            model.endSession()
        }
    }

    func testCertificateReadAfterCertlessSlabCommitDoesNotReassignCertificateWhileHeld() async throws {
        let variant = GradedVariant(
            id: "graded-v2-after-cert-refinement",
            cardID: "graded-card-after-cert-refinement",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            printing: "Normal",
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

    func testCertifiedRescanRefinesUnknownEditionAndReplacesIncompatiblePrice() async throws {
        for unknownFinish in [false, true] {
            let model = try makeModel(variants: [.normal],
                gradedOutcome: .bound(GradedVariant(id: "ordinary", company: .psa,
                    grade: CardGrade(value: "10"), printing: "Normal", marketPriceUSD: 90, updatedAt: nil)),
                gradedRecheckOutcome: .bound(GradedVariant(id: "first-edition", company: .psa,
                    grade: CardGrade(value: "10"), printing: "1st Edition", marketPriceUSD: 450, updatedAt: nil)),
                setProviderID: "base1")
            useSlabMode(model)
            let identifier = scannerIdentifier(setProviderID: "base1")
            let initial = ScanSubject(identifier: identifier, slab: GradedSlabEvidence(
                company: .psa, grade: CardGrade(value: "10"), certificationNumber: "RESCAN-CERT", labelCardText: [],
                printedFinish: .normal, printedPrintRun: .unlimited))
            confirm(model, initial, encounterID: UUID())
            await assertEventually {
                (try? self.context().fetch(FetchDescriptor<CollectedCard>()).first?.justTCGVariantID) == "ordinary"
            }
            let context = try context()
            let row = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
            row.pokemonPrintRunRaw = nil
            if unknownFinish {
                row.variantID = nil
                row.variantLabel = nil
            }
            try context.save()
            let eventCount = try context.fetchCount(FetchDescriptor<InventoryEvent>())
            let activityCount = try context.fetchCount(FetchDescriptor<CollectionActivity>())
            model.viewDisappeared()
            model.start(context: context, startCamera: false, shouldRefreshMagicDirectory: false)
            await assertEventually { model.isScannerSessionActiveForTesting }
            let refined = ScanSubject(identifier: identifier, slab: GradedSlabEvidence(
                company: .psa, grade: CardGrade(value: "10"), certificationNumber: "RESCAN-CERT", labelCardText: [],
                printedFinish: .normal, printedPrintRun: .firstEdition))
            confirm(model, refined, encounterID: UUID())
            await assertEventually {
                (try? self.context().fetch(FetchDescriptor<CollectedCard>()).first?.justTCGVariantID) == "first-edition"
            }
            let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(saved.pokemonPrintRun, .firstEdition)
            XCTAssertEqual(saved.variant, .normal)
            XCTAssertEqual(saved.quantity, 1)
            XCTAssertEqual(saved.certificationNumber, "RESCAN-CERT")
            XCTAssertEqual(PriceStore(context: context).record(forKey: saved.priceKey)?.effectiveUnitMarketPriceUSD, 450)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), eventCount)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionActivity>()), activityCount)
            XCTAssertTrue(model.recent.isEmpty, "A certified rescan must not create an acquisition receipt")
            model.viewDisappeared()
        }
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

    func testGradedFinishCorrectionRejectsIncompatibleLookupInEitherOrder() async throws {
        for correctBeforeLookup in [false, true] {
            let gate = correctBeforeLookup ? ScannerGradedResolverGate() : nil
            let variant = GradedVariant(id: "holo-only", company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"), printing: "Holofoil",
                marketPriceUSD: 250, updatedAt: nil)
            let model = try makeModel(variants: [.normal, .holo], gradedOutcome: .bound(variant),
                gradedResolverGate: gate)
            useSlabMode(model)
            confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
            let committed = await waitUntil { model.recent.count == 1 }
            XCTAssertTrue(committed)
            if let gate { await gate.waitUntilStarted() }
            else {
                let bound = await waitUntil { model.recent.first?.isGradedPricePending == false }
                XCTAssertTrue(bound)
            }
            let scanID = try XCTUnwrap(model.recent.first?.id)
            let result = await model.correct(scanID: scanID, to: .normal)
            XCTAssertEqual(result, .saved)
            if let gate { await gate.release(andFutureCalls: true) }
            let settled = await waitUntil { model.recent.first?.isGradedPricePending == false }
            XCTAssertTrue(settled)
            let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first { $0.collectionKey == model.recent.first?.mutation.collectionKey })
            XCTAssertNil(row.justTCGVariantID)
            XCTAssertEqual(row.quantity, 1)
            XCTAssertEqual(row.variant, .normal)
            if case .price = model.recent.first?.price { XCTFail("Holo quote survived Normal correction") }
            let records = try context().fetch(FetchDescriptor<PriceRecord>())
            XCTAssertFalse(records.contains { $0.marketVariantID == "holo-only" && $0.effectiveUnitMarketPriceUSD != nil })
            XCTAssertEqual(InventoryLedger.quantities(from: try context().fetch(FetchDescriptor<InventoryEvent>()))[row.collectionKey], 1)
        }
    }

    func testUnknownGradedScanGetsPriceOnlyAfterFinishCorrection() async throws {
        let gradedVariant = GradedVariant(
            id: "graded-v2-correction",
            cardID: "graded-card-correction",
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            printing: "Normal",
            marketPriceUSD: 250,
            updatedAt: nil
        )
        let model = try makeModel(
            variants: [.normal, .holo],
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
        let committed = await waitUntil {
            model.recent.count == 1 && model.recent.first?.isGradedPricePending == false
        }
        XCTAssertTrue(committed)
        if case .price = model.recent.first?.price { XCTFail("Unknown finish received a price") }
        let scanID = try XCTUnwrap(model.recent.first?.id)

        let correction = await model.correct(scanID: scanID, to: .normal)
        XCTAssertEqual(correction, .saved)
        await assertEventually {
            if case .price = model.recent.first?.price { return true }
            return false
        }
        guard case let .price(price) = model.recent.first?.price else {
            return XCTFail("graded correction should retain the previously resolved price")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 250)
        XCTAssertEqual(price.source, .justTCG)
    }

    func testUnknownGradedFinishCorrectionStaysUnpricedWhenRecheckUnavailable() async throws {
        let variant = GradedVariant(id: "normal-compatible", company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"), printing: "Normal",
            marketPriceUSD: 250, updatedAt: nil)
        let model = try makeModel(variants: [.normal, .holo], gradedOutcome: .bound(variant),
            gradedRecheckOutcome: .unavailable)
        useSlabMode(model)
        confirm(model, gradedSubject(value: "10", label: "Gem Mint"), encounterID: UUID())
        await assertEventually {
            model.recent.count == 1 && model.recent.first?.isGradedPricePending == false
        }
        let scanID = try XCTUnwrap(model.recent.first?.id)
        let result = await model.correct(scanID: scanID, to: .normal)
        XCTAssertEqual(result, .saved)
        await assertEventually { model.recent.first?.isGradedPricePending == false }
        if case .price = model.recent.first?.price { XCTFail("Unknown finish must not seed a retained quote") }
        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertNil(row.justTCGVariantID)
        XCTAssertEqual(row.quantity, 1)
        XCTAssertEqual(row.variant, .normal)
    }

    func testIncompatibleGradedCorrectionResolvesTheCorrectedFinishPrice() async throws {
        let grade = CardGrade(value: "10", label: "Gem Mint")
        let holo = GradedVariant(id: "holo-before-correction", company: .psa, grade: grade,
            printing: "Holofoil", marketPriceUSD: 250, updatedAt: nil)
        let normal = GradedVariant(id: "normal-after-correction", company: .psa, grade: grade,
            printing: "Normal", marketPriceUSD: 80, updatedAt: nil)
        let model = try makeModel(variants: [.normal, .holo], gradedOutcome: .bound(holo),
            gradedRecheckOutcome: .bound(normal))
        useSlabMode(model)
        confirm(model, gradedSubject(value: "10", label: "Gem Mint", finish: .holo), encounterID: UUID())
        await assertEventually {
            guard case let .price(price) = model.recent.first?.price else { return false }
            return price.unitMarketPriceUSD == 250 && model.recent.first?.isGradedPricePending == false
        }
        let scanID = try XCTUnwrap(model.recent.first?.id)
        let result = await model.correct(scanID: scanID, to: .normal)
        XCTAssertEqual(result, .saved)
        await assertEventually {
            guard case let .price(price) = model.recent.first?.price else { return false }
            return price.unitMarketPriceUSD == 80 && model.recent.first?.isGradedPricePending == false
        }
        let row = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.justTCGVariantID, normal.id)
        XCTAssertEqual(row.variant, .normal)
        XCTAssertEqual(row.quantity, 1)
        XCTAssertEqual(row.certificationNumber, "12345678")
        XCTAssertEqual(InventoryLedger.quantities(from: try context().fetch(FetchDescriptor<InventoryEvent>()))[row.collectionKey], 1)
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
            printing: "Normal",
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
        let presented = await waitUntil {
            model.priceCheckResult?.hasUsableAmount == true
                && model.priceCheckResult?.isRefreshing == false
        }
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

    func testREQ006RefreshedNonUSDQuoteIsRejectedAsProviderFailure() async throws {
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
                && result.display.currencyCode == "USD"
                && result.display.amount == nil
        }

        XCTAssertTrue(refreshedState)
        XCTAssertEqual(model.priceCheckResult?.quoteState, .providerUnavailable)
        XCTAssertEqual(model.priceCheckResult?.display.currencyCode, "USD")
        XCTAssertNil(model.priceCheckResult?.display.amount)
    }

    func testPriceCheckRepeatedTapsDismissalAndNewScanCannotPublishObsoleteRefresh() async throws {
        let provider = ScannerGatedPriceCheckProvider()
        let model = try makeModel(variants: [.normal], priceCheckProvider: provider)
        model.setPurpose(.priceCheck)
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await provider.gate.waitUntilStarted()
        XCTAssertTrue(model.priceCheckResult?.isRefreshing == true)
        model.refreshPriceCheckQuote()
        model.refreshPriceCheckQuote()
        XCTAssertEqual(provider.calls, 1)

        model.dismissPriceCheckResult()
        XCTAssertNil(model.priceCheckResult)
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
        await assertEventually { model.priceCheckResult?.display.amount == 4.43 && model.priceCheckResult?.isRefreshing == false }
        let currentID = try XCTUnwrap(model.priceCheckResult?.id)
        XCTAssertEqual(model.priceCheckResult?.quoteState, .stale)
        XCTAssertEqual(provider.calls, 2)
        await provider.gate.release()
        await settle()
        XCTAssertEqual(model.priceCheckResult?.id, currentID)
        XCTAssertEqual(model.priceCheckResult?.card.cardNumber, "002")
        XCTAssertEqual(model.priceCheckResult?.display.amount, 4.43)
        XCTAssertEqual(provider.calls, 2, "A stale result must not start an automatic refresh loop")
        let cached = try context().fetch(FetchDescriptor<ReferenceQuote>())
        XCTAssertFalse(cached.contains { $0.effectiveAmount == 999 }, "Dismissed requests must not write late cache results")
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

    func testAbandonedRetryExistenceCheckCannotPublishOrAuthorizeAWrite() async throws {
        for scenario in 0..<9 {
            let result = scenario % 3
            let addGate = ScannerCollectionAddGate(outcome: .failure)
            let model = try makeModel(variants: [.normal], collectionAddOverride: { try await addGate.add($0) })
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await addGate.waitUntilStarted()
            await addGate.release()
            await assertEventually { model.unresolvedScans.count == 1 }
            let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
            let existence = ScannerFetchGate()
            model.collectionContainsOverrideForTesting = { _ in
                await existence.hold()
                if result == 2 { throw ScannerCollectionAddGateError.failed }
                return result == 1
            }
            model.resolveUnresolved(id: rowID, choice: .retrySave)
            await existence.waitUntilStarted()
            switch scenario / 3 {
            case 0: model.setPurpose(.priceCheck)
            case 1: model.scenePhaseChanged(isActive: false)
            default:
                model.viewDisappeared()
                model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false)
            }
            await existence.release()
            await settle()
            XCTAssertEqual(model.unresolvedScans.map(\.id), [rowID])
            let count = await addGate.count()
            XCTAssertEqual(count, 1)
            XCTAssertNil(model.pendingDuplicateConfirmation)
            XCTAssertNil(model.scanAcknowledgement)
            model.viewDisappeared()
        }
    }

    func testHeldRepeatSurvivesRequiredFinishAndPrintRunChoices() async throws {
        for (vintage, cancel, interrupt) in [
            (false, false, false), (true, false, false),
            (false, true, false), (true, true, false),
            (false, false, true), (true, false, true)
        ] {
            let setID = vintage ? "base1" : "test-set"
            let model = try makeModel(variants: [.normal, .holo], setProviderID: setID)
            let subject = ScanSubject(identifier: scannerIdentifier(setProviderID: setID))
            let start = CFAbsoluteTimeGetCurrent()
            var firstEncounter: UUID?
            let original = model.scanner.onConfirmedSubjectCandidate
            model.scanner.onConfirmedSubjectCandidate = { context, id, subject, permit in
                if permit == nil { firstEncounter = id }
                original?(context, id, subject, permit)
            }
            model.scanner.drainProfileQueuesForTesting()
            model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 0.25)
            model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 0.5)
            if vintage {
                await assertEventually { model.pendingPrintRunChoice != nil }
                model.choose(.unlimited)
            }
            await assertEventually { model.pendingChoice != nil }
            model.choose(.normal)
            await assertEventually { model.recent.count == 1 }
            for offset in stride(from: 0.75, through: 2.5, by: 0.25) {
                model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + offset)
            }
            model.scanner.onLatchHolding?(subject, try XCTUnwrap(firstEncounter))
            await assertEventually { model.heldDuplicateOffer != nil }
            model.addAnotherHeldCopy()
            model.addAnotherHeldCopy()
            await settle()
            model.scanner.drainVisionQueueForTesting()
            model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 3)
            model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 3.25)
            if vintage {
                await assertEventually { model.pendingPrintRunChoice != nil }
                if interrupt {
                    model.scenePhaseChanged(isActive: false)
                    await settle()
                    XCTAssertEqual(model.recent.count, 1)
                    XCTAssertEqual(model.unresolvedScans.count, 1)
                    XCTAssertTrue(model.unresolvedScans.first?.isAdditionalCopy == true)
                    XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
                    model.viewDisappeared()
                    continue
                }
                if cancel {
                    model.dismissPrintRunChoice()
                    await settle()
                    XCTAssertEqual(model.recent.count, 1)
                    XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
                    model.viewDisappeared()
                    continue
                }
                model.choose(.unlimited)
            }
            await assertEventually { model.pendingChoice != nil }
            if interrupt {
                model.scenePhaseChanged(isActive: false)
                await settle()
                XCTAssertEqual(model.recent.count, 1)
                XCTAssertEqual(model.unresolvedScans.count, 1)
                XCTAssertTrue(model.unresolvedScans.first?.isAdditionalCopy == true)
                XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
                model.viewDisappeared()
                continue
            }
            if cancel {
                model.dismissChoice()
                await settle()
                XCTAssertEqual(model.recent.count, 1)
                XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
                model.viewDisappeared()
                continue
            }
            model.choose(.normal)
            await assertEventually { model.recent.count == 2 }
            XCTAssertEqual(model.successCount, 2)
            XCTAssertNil(model.pendingDuplicateConfirmation)
            model.viewDisappeared()
        }
    }

    func testLateAdditionalCopyCompletionCannotReviveOldSessionPrompt() async throws {
        for outcome in [ScannerCollectionAddGate.Outcome.success, .failure] {
            let gate = ScannerCollectionAddGate(outcome: outcome, successfulAddsBeforeBlocking: 1)
            let model = try makeModel(variants: [.normal], collectionAddOverride: { try await gate.add($0) })
            let first = UUID()
            confirm(model, scannerIdentifier(), encounterID: first)
            await assertEventually { model.recent.count == 1 }
            model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: first))
            await settle()
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await assertEventually { model.pendingDuplicateConfirmation != nil }
            model.addAnother()
            await gate.waitUntilStarted()
            model.viewDisappeared()
            model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false)
            try await Task.sleep(for: .milliseconds(2200))
            await gate.release()
            await settle()
            XCTAssertNil(model.pendingDuplicateConfirmation)
            XCTAssertNil(model.heldDuplicateOffer)
            XCTAssertTrue(model.recent.isEmpty)
            XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
            model.viewDisappeared()
        }
    }

    func testFailedAdditionalCopyCannotRevivePromptAfterSameSessionTransition() async throws {
        for transition in 0..<3 {
            let gate = ScannerCollectionAddGate(outcome: .failure, successfulAddsBeforeBlocking: 1)
            let model = try makeModel(variants: [.normal], collectionAddOverride: { try await gate.add($0) })
            let first = UUID()
            confirm(model, scannerIdentifier(), encounterID: first)
            await assertEventually { model.recent.count == 1 }
            model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: first))
            await settle()
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await assertEventually { model.pendingDuplicateConfirmation != nil }
            model.addAnother()
            await gate.waitUntilStarted()
            switch transition {
            case 0: model.setPurpose(.priceCheck)
            case 1: useSlabMode(model)
            default: model.scenePhaseChanged(isActive: false)
            }
            await gate.release()
            await assertEventually { model.unresolvedScans.count == 1 }
            await settle()
            XCTAssertNil(model.pendingDuplicateConfirmation)
            XCTAssertNil(model.heldDuplicateOffer)
            XCTAssertNil(model.scanAcknowledgement)
            XCTAssertEqual(model.scanner.isRecognitionPausedForTesting, transition == 2)
            XCTAssertTrue(model.unresolvedScans.first?.isAdditionalCopy == true)
            XCTAssertNotNil(model.unresolvedScans.first?.pendingCommit)
            XCTAssertEqual(model.recent.count, 1)
            model.viewDisappeared()
        }
    }

    func testHeldRepeatSaveFailureRepublishesOfferOnlyWhilePresentationIsCurrent() async throws {
        for transition in 0..<4 {
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
            switch transition {
            case 1: model.setPurpose(.priceCheck)
            case 2: useSlabMode(model)
            case 3: model.scenePhaseChanged(isActive: false)
            default: break
            }
            await addGate.release()

            if transition != 0 {
                await assertEventually { model.unresolvedScans.count == 1 }
                await settle()
                XCTAssertNil(model.heldDuplicateOffer)
                XCTAssertNil(model.pendingDuplicateConfirmation)
                XCTAssertNil(model.scanAcknowledgement)
                XCTAssertEqual(model.scanner.isRecognitionPausedForTesting, transition == 3)
                XCTAssertTrue(model.unresolvedScans.first?.isAdditionalCopy == true)
                XCTAssertNotNil(model.unresolvedScans.first?.pendingCommit)
                XCTAssertEqual(model.recent.count, 1)
                model.viewDisappeared()
                continue
            }
            let failed = await waitUntil {
                model.heldDuplicateOffer != nil && model.scanAcknowledgement?.phase == .failed
            }
            XCTAssertTrue(failed)
            XCTAssertNotNil(model.heldDuplicateOffer)
            XCTAssertEqual(model.scanAcknowledgement?.phase, .failed)
            XCTAssertFalse(model.scanAcknowledgement?.canRetryScan ?? true)
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
            model.viewDisappeared()
        }
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

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        await assertEventually {
            model.sessionScans.count == 3 && model.pendingDuplicateConfirmation == nil
        }

        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        await assertEventually { model.note?.text.contains("already added this session") == true }
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.sessionScans.count, 3)
    }

    func testNonconsecutiveCopyAfterTrackerLossUsesOrdinaryFinishPicker() async throws {
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

        // Losing tracking does not turn a nonconsecutive copy into a duplicate.
        model.scanner.invalidateSpatialContinuity()
        await settle()
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: replacingEncounter)
        await assertEventually { model.sessionScans.count == 2 }

        let repeatedEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: repeatedEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == repeatedEncounter }
        XCTAssertNil(model.pendingChoice?.duplicateChoiceContext)

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

    func testNonconsecutiveCopyAfterTrackerLossAddsWithFinishLock() async throws {
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
        await assertEventually { model.sessionScans.count == 3 }
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.sessionScans.first?.resolved.variant, .normal)
        XCTAssertEqual(model.successCount, 3)
    }

    func testNonconsecutiveCopyOnlyAsksForUnresolvedFinish() async throws {
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
        XCTAssertNil(model.pendingChoice?.duplicateChoiceContext)
        XCTAssertNil(model.pendingDuplicateConfirmation)

        // Only the ordinary finish choice is needed for this copy.
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

    func testNonconsecutiveCopyWithResolvedFinishAddsAutomatically() async throws {
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
            model.sessionScans.count == 3 && model.pendingDuplicateConfirmation == nil
        }
        await settle()
        XCTAssertEqual(model.successCount, 3)
    }

    func testDeclinedNonconsecutiveFinishChoiceDoesNotAddAndCanBeRetried() async throws {
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
        XCTAssertNil(model.pendingChoice?.duplicateChoiceContext)
        model.dismissChoice()
        await settle()
        XCTAssertEqual(model.sessionScans.count, 2)
        XCTAssertNil(model.pendingChoice)
        XCTAssertNil(model.pendingDuplicateConfirmation)

        let retryEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: retryEncounter)
        await assertEventually { model.pendingChoice?.request.encounterID == retryEncounter }
        XCTAssertNil(model.pendingChoice?.duplicateChoiceContext)
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

    func testOlderPresentationProofDoesNotPromptAfterAnotherCard() async throws {
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
        await assertEventually { model.sessionScans.count == 3 }
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.successCount, 3)
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

    func testAddingAnotherCopyOfNewerCardDoesNotPromptForOlderCard() async throws {
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
        await assertEventually { model.sessionScans.count == 4 }
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertEqual(model.successCount, 4)
    }

    func testHeldRepeatCommitDoesNotPromptForOlderUnrelatedCard() async throws {
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
        await assertEventually { model.sessionScans.count == 4 }
        XCTAssertNil(model.pendingDuplicateConfirmation)
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

    func testCameraConfirmationsContinueAfterEitherDuplicateAnswer() async throws {
        for addAnother in [true, false] {
            let model = try makeModel(variants: [.normal, .reverse], secondaryVariants: [.normal])
            model.setFinishLock(MagicFinishLock(finish: .normal), for: .pokemon)
            let firstEncounter = UUID()
            confirm(model, scannerIdentifier(), encounterID: firstEncounter)
            await assertEventually { model.sessionScans.count == 1 }
            model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: firstEncounter))
            await settle()
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await assertEventually { model.pendingDuplicateConfirmation != nil }
            XCTAssertTrue(model.scanner.isRecognitionPausedForTesting)

            if addAnother { model.addAnother() }
            else { model.chooseSameCard() }
            let expectedCount = addAnother ? 2 : 1
            await assertEventually {
                model.sessionScans.count == expectedCount && !model.isIdentificationProcessingForTesting
            }
            XCTAssertNil(model.pendingDuplicateConfirmation)
            XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)

            // Unlike confirm(), these observations exercise the real camera
            // confirmation window and its non-nil session/generation token.
            let next = ScanSubject(identifier: scannerIdentifier(cardNumber: "002"))
            let now = CFAbsoluteTimeGetCurrent()
            model.scanner.drainProfileQueuesForTesting()
            model.scanner.receiveFooterOutcomeForTesting(.identified(next), at: now)
            model.scanner.receiveFooterOutcomeForTesting(.identified(next), at: now + 0.25)
            await assertEventually { model.sessionScans.count == expectedCount + 1 }
            XCTAssertEqual(model.sessionScans.first?.card.cardNumber, "002")
            XCTAssertFalse(model.diagnosticEventsForTesting.contains("staleConfirmationDropped"))
            model.endSession()
        }
    }

    func testAutoLockedCopyFromTenCardsAgoAddsWithoutDuplicatePrompt() async throws {
        let model = try makeModel(variants: [.normal, .reverse], secondaryVariants: [.normal], tertiaryVariants: [.normal])
        model.setFinishLock(MagicFinishLock(finish: .normal), for: .pokemon)
        let firstEncounter = UUID()
        confirm(model, scannerIdentifier(), encounterID: firstEncounter)
        await assertEventually { model.sessionScans.count == 1 }
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: firstEncounter))
        await settle()

        for index in 0..<10 {
            confirm(model, scannerIdentifier(cardNumber: index.isMultiple(of: 2) ? "002" : "003"), encounterID: UUID())
            await assertEventually { model.sessionScans.count == index + 2 }
        }
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.sessionScans.count == 12 }
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertNil(model.pendingChoice)
        let cards = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.first(where: { $0.cardNumber == "001" })?.quantity, 2)
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
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .interrupted)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testInterruptionFilesActiveAndQueuedCardsExactlyOnce() async throws {
        let gate = ScannerFetchGate()
        let model = try makeModel(variants: [.normal], delayNanoseconds: 500_000_000, fetchGate: gate)
        for number in ["001", "002", "003"] {
            confirm(model, scannerIdentifier(cardNumber: number), encounterID: UUID())
        }
        await gate.waitUntilStarted()
        await settle()
        model.viewDisappeared()
        XCTAssertEqual(model.unresolvedScans.count, 3)
        XCTAssertTrue(model.unresolvedScans.allSatisfy { $0.reason == .interrupted })
        let ids = Set(model.unresolvedScans.map(\.id))
        model.endSession()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(Set(model.unresolvedScans.map(\.id)), ids)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testInterruptionDoesNotFileAnAuthorizedWrite() async throws {
        let gate = ScannerCollectionAddGate(outcome: .success)
        let model = try makeModel(variants: [.normal], collectionAddOverride: { try await gate.add($0) })
        let summaryStore = ScanSessionSummaryStore()
        model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false,
                    summaryStore: summaryStore)
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await gate.waitUntilStarted()
        model.viewDisappeared()
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        await gate.release()
        await assertEventually { summaryStore.summary?.addedCount == 1 }
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        let count = await gate.count()
        XCTAssertEqual(count, 1)
    }

    func testInterruptionImmediatelyAfterFinishAnswerPreservesTheRequest() async throws {
        let model = try makeModel(variants: [.normal, .holo])
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.pendingChoice != nil }

        model.choose(.normal)
        XCTAssertNil(model.pendingChoice)
        // Interrupt before the scheduled resolution task authorizes a write.
        model.scenePhaseChanged(isActive: false)

        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .interrupted)
        await settle()
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testInterruptionAfterFinishAnswerDoesNotFileAnAuthorizedWrite() async throws {
        let gate = ScannerCollectionAddGate(outcome: .success)
        let model = try makeModel(variants: [.normal, .holo], collectionAddOverride: { try await gate.add($0) })
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.pendingChoice != nil }
        model.choose(.normal)
        await gate.waitUntilStarted()

        model.scenePhaseChanged(isActive: false)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        await gate.release()
        await assertEventually { model.sessionScans.count == 1 }
        XCTAssertTrue(model.unresolvedScans.isEmpty)
    }

    func testDismissedChoiceAndPriceCheckDoNotBecomeInterruptedRows() async throws {
        let model = try makeModel(variants: [.normal, .holo])
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.pendingChoice != nil }
        model.dismissChoice()
        model.viewDisappeared()
        XCTAssertTrue(model.unresolvedScans.isEmpty)

        let gate = ScannerFetchGate()
        let priceModel = try makeModel(variants: [.normal], delayNanoseconds: 500_000_000, fetchGate: gate)
        priceModel.setPurpose(.priceCheck)
        confirm(priceModel, scannerIdentifier(), encounterID: UUID())
        await gate.waitUntilStarted()
        priceModel.viewDisappeared()
        XCTAssertTrue(priceModel.unresolvedScans.isEmpty)
    }

    func testDismissedChoiceRecordsVariantInterruptionInStudyLog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ScanMetricsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ScanSessionMetricsLog.enabledDefaultsKey)
        let log = ScanSessionMetricsLog(fileURL: directory.appendingPathComponent("metrics.json"))
        let model = try makeModel(variants: [.normal, .holo], sessionMetricsLog: log, metricsDefaults: defaults)
        let encounterID = UUID()
        confirm(model, scannerIdentifier(), encounterID: encounterID)
        await assertEventually { model.pendingChoice != nil }
        let cardName = try XCTUnwrap(model.pendingChoice?.card.name)
        model.dismissChoice()
        model.viewDisappeared()
        await assertEventually { model.canReloadCatalogs }
        let export = model.sessionMetricsExport
        await export.pendingWrites?.value
        let bytes = try await log.exportData()
        let payload = try ScanSessionMetricsLogTests.decode(bytes)
        let session = try XCTUnwrap(payload.sessions.first)
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(session.encounters.count, 1)
        XCTAssertEqual(session.encounters.first?.outcome, .choiceDismissed)
        XCTAssertEqual(session.encounters.first?.interruptions, [.variant])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(cardName))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(encounterID.uuidString))
        XCTAssertTrue(model.unresolvedScans.isEmpty, "Stage 0 preserves baseline behavior")
    }

    func testPurposeAndSubjectChangesFilePendingChoices() async throws {
        for switchPurpose in [true, false] {
            let model = try makeModel(variants: [.normal, .holo])
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await assertEventually { model.pendingChoice != nil }
            if switchPurpose { model.setPurpose(.priceCheck) }
            else { model.setSubjectMode(.slab) }
            XCTAssertEqual(model.unresolvedScans.count, 1)
            XCTAssertEqual(model.unresolvedScans.first?.reason, .interrupted)
            XCTAssertFalse(model.unresolvedScans.first?.candidates.isEmpty ?? true)
        }
    }

    func testInterruptedDuplicateRetryAsksAgainBeforeAdding() async throws {
        let model = try makeModel(variants: [.normal])
        let summaryStore = ScanSessionSummaryStore()
        model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false,
                    summaryStore: summaryStore)
        let encounter = UUID()
        confirm(model, scannerIdentifier(), encounterID: encounter)
        await assertEventually { model.recent.count == 1 }
        model.scanner.onSpatialResetProof?(SpatialResetProof(encounterID: encounter))
        await settle()
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.pendingDuplicateConfirmation != nil }
        model.viewDisappeared()
        let row = try XCTUnwrap(model.unresolvedScans.first)
        XCTAssertTrue(row.isAdditionalCopy)
        XCTAssertNotNil(row.pendingCommit)
        await assertEventually { summaryStore.summary != nil }
        model.start(context: context(), startCamera: false, shouldRefreshMagicDirectory: false)
        model.resolveUnresolved(id: row.id, choice: .retrySave)
        await assertEventually { model.pendingDuplicateConfirmation != nil }
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
        await assertEventually { !model.isIdentificationProcessingForTesting }
        model.addAnother()
        await assertEventually { model.unresolvedScans.isEmpty }
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
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

    func testCancelledLookupProgressClearsImmediatelyAndCannotClearANewerLookup() async throws {
        let first = ScannerFetchGate()
        let second = ScannerFetchGate()
        let model = try makeModel(variants: [.normal], fetchHoldGates: ["1": first, "2": second])
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await first.waitUntilStarted()
        let firstSpinner = await waitUntil { model.isSlowIdentifying }
        XCTAssertTrue(firstSpinner)

        model.setPurpose(.priceCheck)
        XCTAssertFalse(model.isSlowIdentifying, "A cancelled network task must not retain visible progress")
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
        await second.waitUntilStarted()
        let secondSpinner = await waitUntil { model.isSlowIdentifying }
        XCTAssertTrue(secondSpinner)

        await first.release()
        let oldCompletion = await waitUntil {
            model.diagnosticEventsForTesting.contains("staleIdentificationProgressIgnored")
        }
        XCTAssertTrue(oldCompletion)
        XCTAssertTrue(model.isSlowIdentifying, "Old cleanup must not hide the current request's progress")

        await second.release()
        let completed = await waitUntil { model.priceCheckResult != nil }
        XCTAssertTrue(completed)
        XCTAssertFalse(model.isSlowIdentifying)
        model.endSession()
    }

    func testCatalogMissFilesPromoWithNoCatalogEntryReasonImmediately() async throws {
        let model = try makeModel(variants: [.normal], catalogMiss: true)
        let identifier = try XCTUnwrap(ScanParser.parsePokemon("MEP 095"))
        let subject = ScanSubject(identifier: identifier)
        var plausibleReadCount = 0
        model.scanner.onPlausibleCandidate = { _ in plausibleReadCount += 1 }
        let start = CFAbsoluteTimeGetCurrent()
        model.scanner.receiveFooterOutcomeForTesting(
            .identified(subject),
            at: start + 0.25
        )
        model.scanner.receiveFooterOutcomeForTesting(
            .identified(subject),
            at: start + 0.5
        )

        let failed = await waitUntil {
            model.scanAcknowledgement?.phase == .failed
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(
            model.scanAcknowledgement?.message,
            "Read MEP 095, but the catalog could not resolve an exact printing. Nothing was added."
        )
        let filed = await waitUntil { model.unresolvedScans.count == 1 }
        XCTAssertTrue(filed, "a deterministic catalog miss is filed on the first failure")
        XCTAssertEqual(model.unresolvedScans.first?.subject, subject)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .noCatalogEntry)
        XCTAssertTrue(model.scanAcknowledgement?.canRetryScan == true)

        let firstPlausibleRead = await waitUntil { plausibleReadCount == 1 }
        XCTAssertTrue(firstPlausibleRead)
        let failedAcknowledgement = try XCTUnwrap(model.scanAcknowledgement)
        model.retryFailedScan(encounterID: failedAcknowledgement.encounterID)
        model.scanner.drainVisionQueueForTesting()
        model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 0.75)
        model.scanner.receiveFooterOutcomeForTesting(.identified(subject), at: start + 1.0)

        let sameCardAnnouncedAgain = await waitUntil { plausibleReadCount == 2 }
        XCTAssertTrue(
            sameCardAnnouncedAgain,
            "retry should clear the catalog-miss suppression and announce a fresh read of the same card"
        )
        let sameCardFailedAgain = await waitUntil {
            model.scanAcknowledgement?.phase == .failed
                && model.unresolvedScans.count == 1
        }
        XCTAssertTrue(sameCardFailedAgain)
        XCTAssertEqual(model.unresolvedScans.first?.reason, .noCatalogEntry)
    }

    func testFreshReadRetryEligibilityExcludesNonCameraFixableFailures() {
        let retryableErrors: [Error] = [
            TCGdexError.cardNotFound,
            TCGdexError.identityMismatch,
            ScryfallError.cardNotFound,
            ScryfallError.identityMismatch,
            PokemonHistoricalCatalogError.unsupported
        ]
        for error in retryableErrors {
            XCTAssertTrue(
                ScannerViewModel.canRetryIdentityScan(
                    failure: CardCatalog.classify(error),
                    error: error
                ),
                "a fresh read may change the outcome for \(error)"
            )
        }

        let nonRetryableErrors: [Error] = [
            TCGdexError.invalidURL,
            ScryfallError.invalidURL,
            ScryfallError.unsupportedPrinting,
            ScryfallError.badResponse,
            ScryfallError.providerUnavailable
        ]
        for error in nonRetryableErrors {
            XCTAssertFalse(
                ScannerViewModel.canRetryIdentityScan(
                    failure: CardCatalog.classify(error),
                    error: error
                ),
                "a camera retry cannot fix \(error)"
            )
        }
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
        XCTAssertFalse(transient.scanAcknowledgement?.canRetryScan ?? true)

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
        XCTAssertFalse(unavailable.scanAcknowledgement?.canRetryScan ?? true)
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
        XCTAssertTrue(model.scanAcknowledgement?.canRetryScan == true)
        XCTAssertEqual(model.successCount, 0)
        XCTAssertTrue(model.recent.isEmpty)
    }

    func testRetryFailedIdentityReadsSameCardAgainAndCommitsOnlyAfterNameAgrees() async throws {
        let model = try makeModel(variants: [.normal])
        let identifier = scannerIdentifier()
        let mismatched = ScanSubject(
            identifier: identifier,
            inferredNameReadings: ["pikachu"]
        )
        model.scanner.drainProfileQueuesForTesting()
        let start = CFAbsoluteTimeGetCurrent()
        model.scanner.receiveFooterOutcomeForTesting(.identified(mismatched), at: start + 0.25)
        model.scanner.receiveFooterOutcomeForTesting(.identified(mismatched), at: start + 0.5)

        let failed = await waitUntil {
            model.scanAcknowledgement?.phase == .failed
                && model.scanAcknowledgement?.canRetryScan == true
                && model.unresolvedScans.count == 1
        }
        XCTAssertTrue(failed)
        let failedAcknowledgement = try XCTUnwrap(model.scanAcknowledgement)
        let unresolvedID = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.scanner.drainVisionQueueForTesting()
        XCTAssertEqual(model.scanner.latchedSubjectForTesting, mismatched)

        model.retryFailedScan(encounterID: UUID())
        model.scanner.drainVisionQueueForTesting()
        XCTAssertEqual(model.scanAcknowledgement?.encounterID, failedAcknowledgement.encounterID)
        XCTAssertEqual(model.scanner.latchedSubjectForTesting, mismatched)

        model.retryFailedScan(encounterID: failedAcknowledgement.encounterID)
        model.scanner.drainVisionQueueForTesting()
        XCTAssertNil(model.scanAcknowledgement)
        XCTAssertNil(model.scanner.latchedSubjectForTesting)
        XCTAssertEqual(model.unresolvedScans.count, 1, "the failure record stays until a verified commit")

        model.scanner.receiveFooterOutcomeForTesting(.identified(mismatched), at: start + 0.75)
        model.scanner.receiveFooterOutcomeForTesting(.identified(mismatched), at: start + 1.0)

        let failedAgain = await waitUntil {
            model.scanAcknowledgement?.phase == .failed
                && model.scanAcknowledgement?.canRetryScan == true
                && model.unresolvedScans.count == 1
        }
        XCTAssertTrue(failedAgain)
        XCTAssertEqual(model.successCount, 0)
        XCTAssertEqual(model.unresolvedScans.first?.id, unresolvedID)
        let secondFailure = try XCTUnwrap(model.scanAcknowledgement)

        let corrected = ScanSubject(
            identifier: identifier,
            inferredNameReadings: ["Test Card"]
        )
        model.retryFailedScan(encounterID: failedAcknowledgement.encounterID)
        model.scanner.drainVisionQueueForTesting()
        XCTAssertEqual(model.scanAcknowledgement?.encounterID, secondFailure.encounterID)
        XCTAssertEqual(model.scanner.latchedSubjectForTesting, mismatched)

        model.retryFailedScan(encounterID: secondFailure.encounterID)
        model.scanner.drainVisionQueueForTesting()
        model.scanner.receiveFooterOutcomeForTesting(.identified(corrected), at: start + 1.25)
        model.scanner.receiveFooterOutcomeForTesting(.identified(corrected), at: start + 1.5)

        let committed = await waitUntil {
            model.successCount == 1 && model.unresolvedScans.isEmpty
        }
        XCTAssertTrue(committed)
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(model.successCount, 1)
    }

    func testPriceCheckNameMismatchDoesNotClaimToSaveNeedsAttention() async throws {
        let model = try makeModel(variants: [.normal])
        model.setPurpose(.priceCheck)
        let subject = ScanSubject(
            identifier: scannerIdentifier(),
            inferredNameReadings: ["pikachu"]
        )
        confirm(model, subject, encounterID: UUID())

        let failed = await waitUntil {
            model.note?.text == "Couldn't confirm which card this is. Nothing was added."
        }
        XCTAssertTrue(failed)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        XCTAssertEqual(
            model.note?.text,
            "Couldn't confirm which card this is. Nothing was added."
        )
    }

    func testPriceCheckCatalogMissDoesNotClaimToSaveNeedsAttention() async throws {
        let model = try makeModel(variants: [.normal], catalogMiss: true)
        model.setPurpose(.priceCheck)
        confirm(model, scannerIdentifier(), encounterID: UUID())

        let noteShown = await waitUntil {
            model.note?.text.contains("could not resolve an exact printing") == true
        }
        XCTAssertTrue(noteShown)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        XCTAssertFalse(model.note?.text.contains("Needs attention") == true)
    }

    func testCatalogSelectionResolvesRawAndSlabRowsWithOriginalEvidence() async throws {
        for game in CardGameRegistry.standard.games(supporting: .browse) {
            for isSlab in [false, true] {
                let model = try makeModel(variants: [.normal], gradedOutcome: .unavailable)
                let identifier: ScanIdentifier = game == .pokemon ? scannerIdentifier()
                    : .magic(setCode: "TST", collectorNumber: "001", language: "en")
                let subject = ScanSubject(identifier: identifier, slab: isSlab ? gradedSubject(value: "10", label: "Gem Mint").slab : nil)
                model.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch)
                let row = try XCTUnwrap(model.unresolvedScans.first)
                let details = try catalogRecoveryDetails(game: game)
                model.resolveUnresolved(id: row.id, choice: .catalog(details, printRun: nil, variant: nil))
                await assertEventually { model.sessionScans.count == 1 && model.unresolvedScans.isEmpty }
                let scan = try XCTUnwrap(model.sessionScans.first)
                XCTAssertEqual(scan.subject, subject)
                XCTAssertEqual(scan.card.id, details.card.id)
                let saved = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
                XCTAssertEqual(saved.quantity, 1)
                XCTAssertEqual(saved.itemKind, isSlab ? .gradedCard : .rawCard)
                XCTAssertEqual(saved.certificationNumber, subject.slab?.certificationNumber)
                model.endSession()
            }
        }
    }

    func testCatalogSelectionKeepsAdditionalCopyConfirmation() async throws {
        let model = try makeModel(variants: [.normal])
        let details = try catalogRecoveryDetails(game: .pokemon)
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.sessionScans.count == 1 }
        let subject = ScanSubject(identifier: scannerIdentifier())
        model.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch, isAdditionalCopy: true)
        let row = try XCTUnwrap(model.unresolvedScans.first)
        model.resolveUnresolved(id: row.id, choice: .catalog(details, printRun: nil, variant: .normal))
        await assertEventually { model.pendingDuplicateConfirmation != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
        model.addAnother()
        await assertEventually { model.unresolvedScans.isEmpty && model.sessionScans.count == 2 }
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
    }

    func testCatalogSelectionFailureRetainsSavedRowAndFinishCancellationWritesNothing() async throws {
        let model = try makeModel(variants: [.normal], collectionAddOverride: { _ in throw ScannerCollectionAddGateError.failed })
        let subject = ScanSubject(identifier: scannerIdentifier())
        model.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch)
        let id = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.resolveUnresolved(id: id, choice: .catalog(try catalogRecoveryDetails(game: .pokemon), printRun: nil, variant: .normal))
        await assertEventually { model.unresolvedScans.first?.pendingCommit != nil }
        XCTAssertEqual(model.unresolvedScans.first?.id, id)
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)

        let chooser = try makeModel(variants: [.normal, .holo])
        chooser.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch)
        let chooserID = try XCTUnwrap(chooser.unresolvedScans.first?.id)
        let details = try catalogRecoveryDetails(game: .pokemon, variants: [.normal, .holo])
        chooser.resolveUnresolved(id: chooserID, choice: .catalog(details, printRun: nil, variant: nil))
        await assertEventually { chooser.pendingChoice != nil }
        chooser.dismissChoice()
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertEqual(chooser.unresolvedScans.first?.id, chooserID)
    }

    func testCatalogSelectionCannotCommitAnUnsupportedFinish() async throws {
        let model = try makeModel(variants: [.normal])
        model.fileUnresolvedForTesting(ScanSubject(identifier: scannerIdentifier()), reason: .noConfirmedMatch)
        let id = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.resolveUnresolved(id: id, choice: .catalog(try catalogRecoveryDetails(game: .pokemon),
                                                      printRun: nil, variant: .masterBall))
        await assertEventually { model.sessionScans.count == 1 && model.unresolvedScans.isEmpty }
        XCTAssertEqual(model.sessionScans.first?.resolved.variant, .normal)
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.variantID, PhysicalVariant.normal.id)
    }

    func testCatalogFinishSelectionStillRequiresAVintagePrintRun() async throws {
        let model = try makeModel(variants: [.normal])
        let subject = ScanSubject(identifier: scannerIdentifier())
        model.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch)
        let id = try XCTUnwrap(model.unresolvedScans.first?.id)
        let details = try catalogRecoveryDetails(game: .pokemon, setID: "base1")
        model.resolveUnresolved(id: id, choice: .catalog(details, printRun: nil, variant: .normal))
        await assertEventually { model.pendingPrintRunChoice != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(try context().fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertEqual(model.unresolvedScans.first?.id, id)
        model.choose(.unlimited)
        await assertEventually { model.sessionScans.count == 1 && model.unresolvedScans.isEmpty }
        XCTAssertEqual(model.sessionScans.first?.pokemonPrintRun, .unlimited)
        XCTAssertEqual(model.sessionScans.first?.subject, subject)
    }

    func testCatalogFinishSelectionPreservesValidatedSlabEditionUnlessUserSelectsAnother() async throws {
        for selectedRun: PokemonPrintRun? in [nil, .unlimited] {
            let model = try makeModel(variants: [.normal], gradedOutcome: .unavailable)
            let subject = ScanSubject(identifier: scannerIdentifier(), slab: GradedSlabEvidence(
                company: .psa, grade: CardGrade(value: "10"), certificationNumber: "12345678",
                labelCardText: [], printedFinish: .normal, printedPrintRun: .firstEdition
            ))
            model.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch)
            let id = try XCTUnwrap(model.unresolvedScans.first?.id)
            model.resolveUnresolved(id: id, choice: .catalog(try catalogRecoveryDetails(game: .pokemon, setID: "base1"),
                                                          printRun: selectedRun, variant: .normal))
            await assertEventually { model.sessionScans.count == 1 && model.unresolvedScans.isEmpty }
            let saved = try XCTUnwrap(try context().fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(saved.itemKind, .gradedCard)
            XCTAssertEqual(saved.pokemonPrintRun, selectedRun ?? .firstEdition)
            XCTAssertEqual(model.sessionScans.first?.subject, subject)
            model.endSession()
        }
    }

    private func catalogRecoveryDetails(game: CardGame, variants: [PhysicalVariant] = [.normal],
                                        setID: String = "test-set") throws -> CatalogCardDetails {
        let card: IdentifiedCard
        if game == .pokemon {
            card = .pokemon(catalogCard(variants: variants, localID: "001", setID: setID), setCode: "TST")
        } else {
            let data = Data(#"{"id":"3f0a1f52-0000-4000-8000-000000000001","name":"Fixture","set":"tst","set_name":"Test Set","collector_number":"001","lang":"en","digital":false,"frame":"2015","released_at":"2026-02-06","finishes":["nonfoil"],"prices":{}}"#.utf8)
            card = .magic(try JSONDecoder().decode(ScryfallCard.self, from: data))
        }
        let set = CatalogSet(catalogID: CatalogSetID(game: game, providerID: setID),
                             name: "Test Set", code: "TST", logoURL: nil, symbolURL: nil,
                             cardCount: 10, releaseDate: nil, sortRank: 0)
        return CatalogCardDetails(card: card, set: set)
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
        XCTAssertNil(model.note, "The recovered scan must not still say it needs attention beside its Added receipt")
        XCTAssertEqual(model.transientRetryCountForTesting(for: scannerIdentifier().suppressionKey), 0)
    }

    func testFreshConfirmationClearsPreviousLookupWarningWhileResolving() async throws {
        let failureSwitch = ScannerCatalogFailureSwitch()
        let model = try makeModel(variants: [.normal], delayNanoseconds: 500_000_000,
            sourceFailure: .transient, failureSwitch: failureSwitch)
        confirm(model, scannerIdentifier(), encounterID: UUID())
        await assertEventually { model.scanAcknowledgement?.phase == .failed && model.note != nil }
        await failureSwitch.allowSuccess()
        let encounter = UUID()
        confirm(model, scannerIdentifier(), encounterID: encounter)
        XCTAssertNil(model.note, "An older warning must not accompany the new scan's spinner")
        XCTAssertEqual(model.scanAcknowledgement?.encounterID, encounter)
        await assertEventually { model.successCount == 1 }
        XCTAssertTrue(model.unresolvedScans.isEmpty)
    }

    func testLateLookupFailureDoesNotCoverNewerConfirmedCard() async throws {
        let first = ScannerFetchGate()
        let second = ScannerFetchGate()
        let failureSwitch = ScannerCatalogFailureSwitch()
        let model = try makeModel(variants: [.normal], fetchHoldGates: ["1": first, "2": second],
            sourceFailure: .transient, failureSwitch: failureSwitch)
        confirm(model, scannerIdentifier(cardNumber: "001"), encounterID: UUID())
        await first.waitUntilStarted()
        let nextEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: nextEncounter)
        await first.release()
        await second.waitUntilStarted()
        XCTAssertEqual(model.unresolvedScans.count, 1, "The earlier failure remains recoverable")
        XCTAssertEqual(model.scanAcknowledgement?.encounterID, nextEncounter)
        XCTAssertEqual(model.scanAcknowledgement?.phase, .recognized)
        XCTAssertNil(model.note, "An earlier card's failure must not label the current card as needing attention")
        await failureSwitch.allowSuccess()
        await second.release()
        await assertEventually { model.successCount == 1 }
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
        XCTAssertTrue(
            model.unresolvedScans.contains { $0.id == firstRowID },
            "the row must remain until the chosen printing is committed"
        )
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
        let duplicateSuppressed = await waitUntil {
            model.diagnosticEventsForTesting.contains("routingSuppressed")
                && !model.isIdentificationProcessingForTesting
        }
        XCTAssertTrue(
            duplicateSuppressed,
            "duplicate recovery did not suppress the already-added card; events=\(model.diagnosticEventsForTesting)"
        )
        XCTAssertTrue(model.unresolvedScans.contains { $0.id == secondRowID })
        XCTAssertEqual(model.successCount, 1)
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
    }

    func testChooseCardFromGradedRowPreservesSlabAndPrintedPrintRun() async throws {
        let fixture = try await makeHistoricalHeldRepeatFixture(
            firstSetProviderID: "base1",
            firstSetCode: "BAS"
        )
        let recorder = ScannerPrintRunRecorder()
        let addGate = ScannerCollectionAddGate(
            outcome: .success,
            successfulAddsBeforeBlocking: 1
        )
        let model = try makeModel(
            variants: [.normal],
            gradedOutcome: .unavailable,
            setProviderID: "base1",
            gradedRunRecorder: recorder,
            collectionAddOverride: { candidate in
                try await addGate.add(candidate)
            },
            offline: fixture.offline
        )
        let slab = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            labelCardText: ["FIRST HELD CARD"],
            printedPrintRun: .firstEdition
        )
        let subject = ScanSubject(
            identifier: .pokemonHistorical(
                PokemonHistoricalScanEvidence(
                    number: PokemonPrintedNumberEvidence(
                        localID: "001",
                        denominator: 100,
                        scheme: .officialSet
                    ),
                    titleCandidates: ["First Held Card"]
                )
            ),
            slab: slab
        )
        model.fileUnresolvedForTesting(subject, reason: .noConfirmedMatch)
        let row = try XCTUnwrap(model.unresolvedScans.first)
        let choices = await model.unresolvedCandidates(for: row.id)
        let choice = try XCTUnwrap(choices.first { $0.providerID == "base1-001" })

        model.resolveUnresolved(id: row.id, choice: .choose(choice))
        let committed = await waitUntil { model.successCount == 1 }

        XCTAssertTrue(committed)
        let candidates = await addGate.captured()
        XCTAssertEqual(candidates.first?.subject.slab, slab)
        XCTAssertEqual(candidates.first?.pokemonPrintRun, .firstEdition)
        let recordedRuns = await recorder.snapshot()
        XCTAssertEqual(recordedRuns, [.firstEdition])
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
                && !model.isIdentificationProcessingForTesting
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

    func testInterruptedRetrySaveRetainsCandidateAndDuplicateProtection() async throws {
        for interveningAdd in [false, true] {
            let gate = ScannerCollectionAddGate(outcome: .failure)
            let model = try makeModel(variants: [.normal], collectionAddOverride: { try await gate.add($0) })
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await gate.waitUntilStarted()
            await gate.release()
            await assertEventually {
                model.unresolvedScans.count == 1 && !model.isIdentificationProcessingForTesting
            }
            let row = try XCTUnwrap(model.unresolvedScans.first)
            let pending = try XCTUnwrap(row.pendingCommit)
            model.resolveUnresolved(id: row.id, choice: .retrySave)
            model.scenePhaseChanged(isActive: false)
            let retained = try XCTUnwrap(model.unresolvedScans.first)
            XCTAssertEqual(retained.reason, row.reason)
            XCTAssertEqual(retained.pendingCommit?.requestID, pending.requestID)
            await settle()
            let interruptedAttempts = await gate.count()
            XCTAssertEqual(interruptedAttempts, 1)

            if interveningAdd {
                let writer = ScannerCollectionWriter(modelContainer: context().container)
                _ = try await writer.add(pending)
            }
            await gate.allowSuccess()
            model.resolveUnresolved(id: row.id, choice: .retrySave)
            await assertEventually { model.unresolvedScans.isEmpty && !model.isIdentificationProcessingForTesting }
            let attempts = await gate.count()
            XCTAssertEqual(attempts, interveningAdd ? 1 : 2)
            if interveningAdd {
                XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
            } else {
                XCTAssertEqual(model.successCount, 1)
            }
            model.endSession()
        }
    }

    func testRetrySaveSuppressesACardAddedFromAnotherSurface() async throws {
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
        let failed = await waitUntil { model.unresolvedScans.count == 1 }
        XCTAssertTrue(failed)
        let row = try XCTUnwrap(model.unresolvedScans.first)
        let pending = try XCTUnwrap(row.pendingCommit)

        let writer = ScannerCollectionWriter(modelContainer: context().container)
        _ = try await writer.add(pending)
        model.resolveUnresolved(id: row.id, choice: .retrySave)
        let suppressed = await waitUntil {
            model.note?.text.contains("already in your collection") == true
                && !model.isIdentificationProcessingForTesting
        }

        XCTAssertTrue(suppressed)
        let addCount = await addGate.count()
        XCTAssertEqual(addCount, 1)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        XCTAssertEqual(try context().fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
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

    func testUnresolvedMergeAndReloadPreserveBacklogBeyondFifty() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UnresolvedScanStore(fileURL: directory.appendingPathComponent("unresolved.json"))
        let model = try makeModel(variants: [.normal], unresolvedScanStore: store)
        await model.reloadUnresolvedScansForTesting()
        for number in 1...55 {
            model.fileUnresolvedForTesting(
                ScanSubject(identifier: scannerIdentifier(cardNumber: String(number))),
                reason: .lookupFailed
            )
        }
        let ids = model.unresolvedScans.map(\.id)
        XCTAssertEqual(ids.count, 55)
        await store.save(model.unresolvedScans)
        await model.reloadUnresolvedScansForTesting()
        XCTAssertEqual(model.unresolvedScans.map(\.id), ids)
        model.fileUnresolvedForTesting(
            ScanSubject(identifier: scannerIdentifier(cardNumber: "1")), reason: .noCatalogEntry
        )
        XCTAssertEqual(model.unresolvedScans.count, 55)
        model.dismissUnresolved(id: ids[0])
        XCTAssertEqual(model.unresolvedScans.count, 54)
        XCTAssertEqual(model.unresolvedScans.last?.id, ids.last)
    }

    func testUnresolvedPersistenceFailureShowsScannerNote() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerUnresolvedWriteFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blockingFile)
        let store = UnresolvedScanStore(
            fileURL: blockingFile.appendingPathComponent("unresolved-scans.json"),
            readData: { _ in throw CocoaError(.fileReadNoSuchFile) }
        )
        let model = try makeModel(variants: [.normal], unresolvedScanStore: store)

        model.fileUnresolvedForTesting(
            ScanSubject(identifier: scannerIdentifier()),
            reason: .noCatalogEntry
        )

        let warned = await waitUntil {
            model.note?.text == "Needs attention could not be saved on this device."
        }
        XCTAssertTrue(warned)
    }

    func testFailedUnresolvedReloadPreservesBytesAndRuntimeWorkUntilRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerUnresolvedReadFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("unresolved-scans.json")
        let original = Data("[{truncated recovery evidence".utf8)
        try original.write(to: url)
        let store = UnresolvedScanStore(fileURL: url)
        let model = try makeModel(variants: [.normal], unresolvedScanStore: store)
        await model.reloadUnresolvedScansForTesting()
        XCTAssertTrue(model.note?.text.contains("could not be loaded") == true)

        model.fileUnresolvedForTesting(
            ScanSubject(identifier: scannerIdentifier(cardNumber: "001")), reason: .noCatalogEntry
        )
        model.fileUnresolvedForTesting(
            ScanSubject(identifier: scannerIdentifier(cardNumber: "002")), reason: .lookupFailed
        )
        let survivorID = try XCTUnwrap(model.unresolvedScans.last?.id)
        model.dismissUnresolved(id: try XCTUnwrap(model.unresolvedScans.first?.id))
        await model.reloadUnresolvedScansForTesting()
        XCTAssertEqual(model.unresolvedScans.map(\.id), [survivorID])
        XCTAssertEqual(try Data(contentsOf: url), original)

        // Simulate repaired storage; retry must merge the actionable runtime row.
        try Data("[]".utf8).write(to: url)
        await model.reloadUnresolvedScansForTesting()
        let saved = await waitUntil { (try? Data(contentsOf: url)) != Data("[]".utf8) }
        XCTAssertTrue(saved)
        let restored = await store.load()
        XCTAssertEqual(restored.map(\.id), [survivorID])
    }

    func testDismissedRowDoesNotReturnFromAnOverlappingCatalogReload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerDismissReload-\(UUID().uuidString)", isDirectory: true)
        let store = UnresolvedScanStore(
            fileURL: directory.appendingPathComponent("unresolved-scans.json")
        )
        let first = UnresolvedScan(
            subject: ScanSubject(identifier: scannerIdentifier(cardNumber: "001")),
            reason: .noCatalogEntry
        )
        let second = UnresolvedScan(
            subject: ScanSubject(identifier: scannerIdentifier(cardNumber: "002")),
            reason: .noCatalogEntry
        )
        await store.save([first, second])

        let model = try makeModel(variants: [.normal], unresolvedScanStore: store)
        let loaded = await waitUntil { model.unresolvedScans.count == 2 }
        XCTAssertTrue(loaded)
        model.dismissUnresolved(id: first.id)
        await model.reloadUnresolvedScansForTesting()

        XCTAssertEqual(model.unresolvedScans.map(\.id), [second.id])
        try? FileManager.default.removeItem(at: directory)
    }

    func testCandidateLoadDoesNotWriteIntoTheSlotOfADismissedRow() async throws {
        let model = try makeModel(variants: [.normal])
        let target = ScanSubject(identifier: .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: "001",
                    denominator: 109,
                    scheme: .officialSet
                ),
                titleCandidates: ["First Card"]
            )
        ))
        let survivor = ScanSubject(identifier: .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: "002",
                    denominator: 109,
                    scheme: .officialSet
                ),
                titleCandidates: ["Second Card"]
            )
        ))
        model.fileUnresolvedForTesting(target, reason: .noConfirmedMatch)
        model.fileUnresolvedForTesting(survivor, reason: .noConfirmedMatch)
        let targetID = try XCTUnwrap(model.unresolvedScans.first?.id)
        let survivorRow = try XCTUnwrap(model.unresolvedScans.last)
        model.unresolvedCandidatesWritebackHookForTesting = {
            model.dismissUnresolved(id: targetID)
        }

        let candidates = await model.unresolvedCandidates(for: targetID)

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertEqual(model.unresolvedScans.first?.id, survivorRow.id)
        XCTAssertEqual(model.unresolvedScans.first?.subject, survivorRow.subject)
    }

    func testUpdatingAPersistedUnresolvedRowCountsAsUnresolvedThisSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerExistingUnresolved-\(UUID().uuidString)", isDirectory: true)
        let store = UnresolvedScanStore(
            fileURL: directory.appendingPathComponent("unresolved-scans.json")
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "ASC",
            cardNumber: "001",
            printedTotal: 217,
            setDefinition: SetCodeMap.definitions["ASC"]!
        )
        let subject = ScanSubject(identifier: identifier)
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
        XCTAssertEqual(summaryStore.summary?.unresolvedCount, 1)
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
        XCTAssertEqual(
            model.scanAcknowledgement?.message,
            "Couldn't reach the catalog. Saved to Needs attention; automatic retries stopped."
        )
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

    func testDeferredRestartUsesLatestSceneActivity() async throws {
        for latestIsActive in [false, true] {
            let gate = ScannerCollectionAddGate(outcome: .success)
            let model = try makeModel(
                variants: [.normal], collectionAddOverride: { try await gate.add($0) }
            )
            confirm(model, scannerIdentifier(), encounterID: UUID())
            await gate.waitUntilStarted()
            model.viewDisappeared()
            model.start(
                context: context(), isSceneActive: !latestIsActive,
                startCamera: false, shouldRefreshMagicDirectory: false
            )
            model.scenePhaseChanged(isActive: latestIsActive)
            await gate.release()
            let restarted = await waitUntil { model.isScannerSessionActiveForTesting }
            XCTAssertTrue(restarted)
            XCTAssertEqual(model.scanner.isRecognitionPausedForTesting, !latestIsActive)
            await gate.allowSuccess()
            confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: UUID())
            if latestIsActive {
                let acquired = await waitUntil { model.sessionScans.count == 1 }
                XCTAssertTrue(acquired)
            } else {
                await settle()
                XCTAssertTrue(model.sessionScans.isEmpty)
            }
        }
    }

    func testPausedScannerReportsLiveFramesPeriodicallyUntilResumed() async {
        let scanner = CardScanner()
        var reports = 0
        scanner.onRecognitionPausedWhileLive = { reports += 1 }

        scanner.receivePausedFrameForTesting(at: 100)
        scanner.pauseRecognition(at: 100)
        scanner.receivePausedFrameForTesting(at: 102.9)
        scanner.receivePausedFrameForTesting(at: 103)
        scanner.receivePausedFrameForTesting(at: 105)
        scanner.receivePausedFrameForTesting(at: 106)
        await settle()
        XCTAssertEqual(reports, 2, "One report per interval while frames keep arriving paused.")

        scanner.resumeRecognition(at: 107)
        scanner.receivePausedFrameForTesting(at: 120)
        await settle()
        XCTAssertEqual(reports, 2, "A running scanner never reports a stall.")
    }

    func testLostSheetDismissalRecoversWhenFramesKeepArriving() async throws {
        let model = try makeModel(variants: [.normal])
        model.setApplicationActiveForTesting(true)
        model.pauseForPresentation()
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting)

        model.scanner.onRecognitionPausedWhileLive?()
        let resumed = await waitUntil { model.allowsRecognitionForTesting }
        XCTAssertTrue(resumed)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
        XCTAssertTrue(model.diagnosticEventsForTesting.contains("recognitionStallRecovered:presentation"))

        confirm(model, scannerIdentifier(), encounterID: UUID())
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed, "A recovered scanner must accept the next card.")
    }

    func testRequestedSheetKeepsRecognitionPausedWhenFramesArrive() async throws {
        let model = try makeModel(variants: [.normal])
        model.setApplicationActiveForTesting(true)
        model.setScannerSheetRequested(true)
        model.pauseForPresentation()

        model.scanner.onRecognitionPausedWhileLive?()
        await settle()
        XCTAssertFalse(model.allowsRecognitionForTesting)
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting)
    }

    func testLostSettingsDismissalRestoresScannerBulkWriteInterval() async throws {
        let coordinator = DerivedStateWriteCoordinator()
        let model = try makeModel(variants: [.normal], writeCoordinator: coordinator)
        model.setApplicationActiveForTesting(true)
        model.setScannerSheetRequested(true)
        model.pauseForSettingsPresentation()
        XCTAssertFalse(coordinator.isBulkWriteInFlight)
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting)

        // The binding cleared, but SwiftUI never delivered onDismiss.
        model.setScannerSheetRequested(false)
        model.scanner.onRecognitionPausedWhileLive?()
        let resumed = await waitUntil { model.allowsRecognitionForTesting }
        XCTAssertTrue(resumed)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
        XCTAssertTrue(coordinator.isBulkWriteInFlight)
        XCTAssertNil(coordinator.beginCollectionDelete(), "Recovered scanning still owns the write interval.")

        confirm(model, scannerIdentifier(), encounterID: UUID())
        let committed = await waitUntil { model.sessionScans.count == 1 }
        XCTAssertTrue(committed)

        // A late dismissal must not acquire a second interval that leaks at end.
        model.resumeAfterSettingsPresentation()
        model.endSession()
        XCTAssertFalse(coordinator.isBulkWriteInFlight)
    }

    func testSettingsRecoveryWaitsForExclusiveCollectionOperation() async throws {
        let coordinator = DerivedStateWriteCoordinator()
        let model = try makeModel(variants: [.normal], writeCoordinator: coordinator)
        model.setApplicationActiveForTesting(true)
        model.pauseForSettingsPresentation()
        let token = try XCTUnwrap(coordinator.beginCSVImport(totalEntries: 1))

        model.scanner.onRecognitionPausedWhileLive?()
        await settle()
        XCTAssertFalse(model.allowsRecognitionForTesting)
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting)

        coordinator.endCSVImport(token: token)
        XCTAssertFalse(coordinator.isBulkWriteInFlight, "Recovery must not acquire an interval during the import.")
        model.scanner.onRecognitionPausedWhileLive?()
        let resumed = await waitUntil { model.allowsRecognitionForTesting }
        XCTAssertTrue(resumed)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
        XCTAssertTrue(coordinator.isBulkWriteInFlight)
        model.endSession()
        XCTAssertFalse(coordinator.isBulkWriteInFlight)
    }

    func testLostInterruptionEndRecoversWhenFramesKeepArriving() async throws {
        let model = try makeModel(variants: [.normal])
        model.setApplicationActiveForTesting(true)
        model.scanner.onCameraInterruption?()
        let interrupted = await waitUntil { !model.allowsRecognitionForTesting }
        XCTAssertTrue(interrupted)
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting)

        model.scanner.onRecognitionPausedWhileLive?()
        let resumed = await waitUntil { model.allowsRecognitionForTesting }
        XCTAssertTrue(resumed)
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
        XCTAssertTrue(model.diagnosticEventsForTesting.contains("recognitionStallRecovered:cameraInterrupted"))
    }

    func testLiveFramesDoNotOverrideAVisibleChoiceOrAnInactiveApp() async throws {
        let model = try makeModel(variants: [.normal, .holo])
        model.setApplicationActiveForTesting(true)
        confirm(model, scannerIdentifier(), encounterID: UUID())
        let appeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(appeared)
        model.scanner.onRecognitionPausedWhileLive?()
        await settle()
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting, "A visible finish question owns the pause.")

        model.dismissChoice()
        XCTAssertFalse(model.scanner.isRecognitionPausedForTesting)
        model.setApplicationActiveForTesting(false)
        model.scenePhaseChanged(isActive: false, isBackgrounded: false)
        model.scanner.onRecognitionPausedWhileLive?()
        await settle()
        XCTAssertFalse(model.allowsRecognitionForTesting)
        XCTAssertTrue(model.scanner.isRecognitionPausedForTesting, "A system overlay owns the pause.")
    }

    func testInactiveOverlayPreservesPendingChoiceButBackgroundInvalidatesIt() async throws {
        let model = try makeModel(variants: [.normal, .holo])
        let encounterID = UUID()
        confirm(model, scannerIdentifier(), encounterID: encounterID)
        let appeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(appeared)

        model.scenePhaseChanged(isActive: false, isBackgrounded: false)
        XCTAssertEqual(model.pendingChoice?.request.encounterID, encounterID)
        model.scenePhaseChanged(isActive: true, isBackgrounded: false)
        XCTAssertEqual(model.pendingChoice?.request.encounterID, encounterID)
        model.choose(.normal)
        let committed = await waitUntil { model.recent.count == 1 }
        XCTAssertTrue(committed, "A preserved choice must still be actionable after returning.")

        let secondEncounter = UUID()
        confirm(model, scannerIdentifier(cardNumber: "002"), encounterID: secondEncounter)
        let secondAppeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(secondAppeared)
        model.scenePhaseChanged(isActive: false, isBackgrounded: false)
        model.scenePhaseChanged(isActive: false, isBackgrounded: true)
        XCTAssertNil(model.pendingChoice)
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

    func testHistoricalUnresolvedRowsMergeWithinButNotAcrossSessions() {
        let number = PokemonPrintedNumberEvidence(
            localID: "015",
            denominator: 198,
            scheme: .officialSet
        )
        let first = ScanSubject(identifier: .pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["FIRST CARD"])
        ))
        let second = ScanSubject(identifier: .pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["SECOND CARD"])
        ))
        let firstSession = UUID()
        var rows = UnresolvedScan.merging(
            [],
            with: first,
            reason: .lookupFailed,
            sessionID: firstSession
        )
        rows = UnresolvedScan.merging(
            rows,
            with: second,
            reason: .lookupFailed,
            sessionID: firstSession
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.titleCandidates, ["FIRST CARD", "SECOND CARD"])

        rows = UnresolvedScan.merging(
            rows,
            with: second,
            reason: .lookupFailed,
            sessionID: UUID()
        )
        XCTAssertEqual(rows.count, 2)

        let existingRowID = rows[0].id
        rows = UnresolvedScan.merging(
            rows,
            with: first,
            reason: .providerUnavailable,
            sessionID: UUID(),
            matchingID: existingRowID
        )
        XCTAssertEqual(rows.count, 2)
        let updatedRow = rows.first(where: { $0.id == existingRowID })
        XCTAssertEqual(updatedRow?.reason, .providerUnavailable)
        XCTAssertEqual(updatedRow?.mergeSessionID, firstSession)
    }

    func testCommitDoesNotClearAnAmbiguousHistoricalRowBySuggestionOrSharedDenominator() throws {
        let model = try makeModel(variants: [.normal])
        let subject = ScanSubject(identifier: .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: "015",
                    denominator: 198,
                    scheme: .officialSet
                ),
                titleCandidates: ["Example Card"]
            )
        ))
        let suggestion = PokemonCatalogCardIdentity(
            providerID: "test-set-015",
            setID: "sv01",
            setName: "Scarlet & Violet",
            localID: "015",
            name: "Example Card"
        )
        model.fileUnresolvedForTesting(
            subject,
            reason: .noConfirmedMatch,
            candidates: [suggestion]
        )
        let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        let card = IdentifiedCard.pokemon(
            catalogCard(variants: [.normal], localID: "015", setID: "sv01", officialCount: 198),
            setCode: "SVI"
        )

        model.clearResolvedUnresolvedRowsForTesting(
            for: card,
            officialCounts: ["sv01": 198, "swsh9": 198]
        )

        XCTAssertEqual(model.unresolvedScans.map(\.id), [rowID])
    }

    func testRecoveryCleanupPreservesDistinctPhysicalAcquisitionsAcrossReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UnresolvedScanStore(fileURL: directory.appendingPathComponent("recovery.json"))
        let model = try makeModel(variants: [.normal], gradedOutcome: .unavailable, unresolvedScanStore: store)
        let identifier = scannerIdentifier()
        let card = IdentifiedCard.pokemon(catalogCard(variants: [.normal], localID: "001"), setCode: "TST")
        for certificate in ["11111111", "22222222"] {
            let subject = ScanSubject(identifier: identifier, slab: GradedSlabEvidence(
                company: .psa, grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: certificate, labelCardText: []))
            let candidate = CollectionCommitCandidate(resolvedScan: ResolvedScan(
                request: ScanRequest(subject: subject, purpose: .collection, generation: 0),
                card: card, resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                pokemonPrintRun: nil, options: [.normal]))
            model.fileUnresolvedForTesting(subject, reason: .saveFailed(inMemoryCandidateID: candidate.requestID),
                pendingCommit: candidate)
        }
        model.fileUnresolvedForTesting(ScanSubject(identifier: identifier), reason: .lookupFailed,
            isAdditionalCopy: true)
        let resolved = try XCTUnwrap(model.unresolvedScans.first { $0.subject.slab?.certificationNumber == "11111111" })
        await model.waitForUnresolvedPersistenceForTesting()
        model.resolveUnresolved(id: resolved.id, choice: .retrySave)
        await assertEventually { model.sessionScans.count == 1 }
        await model.waitForUnresolvedPersistenceForTesting()
        let reloaded = await store.load()
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertTrue(reloaded.contains { $0.subject.slab?.certificationNumber == "22222222" })
        XCTAssertTrue(reloaded.contains { $0.isAdditionalCopy })
        let owned = try context().fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(owned.count, 1)
        XCTAssertEqual(owned.first?.certificationNumber, "11111111")
        confirm(model, identifier, encounterID: UUID())
        await assertEventually { model.sessionScans.count == 2 }
        await model.waitForUnresolvedPersistenceForTesting()
        let afterRawSuccess = await store.load()
        XCTAssertEqual(afterRawSuccess.count, 2)
        XCTAssertTrue(afterRawSuccess.contains { $0.subject.slab?.certificationNumber == "22222222" })
        XCTAssertTrue(afterRawSuccess.contains { $0.isAdditionalCopy })
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
        fetchHoldGates: [String: ScannerFetchGate] = [:],
        catalogMiss: Bool = false,
        gradedOutcome: ScannedGradedOutcome? = nil,
        gradedRecheckOutcome: ScannedGradedOutcome? = nil,
        setProviderID: String = "test-set",
        gradedRunRecorder: ScannerPrintRunRecorder? = nil,
        gradedResolverGate: ScannerGradedResolverGate? = nil,
        writeCoordinator: DerivedStateWriteCoordinator? = nil,
        priceCheckOutcome: PriceCheckRefreshOutcome? = nil,
        priceCheckProvider: (any PriceCheckRefreshProvider)? = nil,
        storageGeneration: CollectionStorageGeneration? = nil,
        collectionAddOverride: (@Sendable (CollectionCommitCandidate) async throws -> CollectionMutation)? = nil,
        certificationRefinementOverride: (@MainActor (RecentScan, GradedSlabEvidence) async throws -> CollectionMutation?)? = nil,
        sourceFailure: ScannerStubPokemonSource.Failure? = nil,
        failureSwitch: ScannerCatalogFailureSwitch? = nil,
        unresolvedScanStore: UnresolvedScanStore? = nil,
        sessionMetricsLog: ScanSessionMetricsLog? = nil,
        metricsDefaults: UserDefaults = .standard,
        offline: PokemonOfflineCatalog? = nil,
        printingCatalog: (any GameCatalogAdapter)? = nil,
        catalogCoordinator: PokemonCatalogCoordinator? = nil,
        magicCatalogCoordinator: MagicCatalogCoordinator? = nil
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
                fetchHoldGates: fetchHoldGates,
                catalogMiss: catalogMiss,
                failure: sourceFailure,
                failureSwitch: failureSwitch
            ),
            offline: offline ?? PokemonOfflineCatalog(store: checklistStore),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root,
                appVersion: "scanner-tests"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0),
            gameCatalogAdapters: try .init(adapters: printingCatalog.map { [$0] } ?? [])
        )
        let model = ScannerViewModel(
            scanner: CardScanner(),
            catalog: catalog,
            feedback: ScanFeedback(),
            gradedResolver: gradedOutcome.map {
                ScannerStubGradedResolver(
                    outcome: $0,
                    subsequentOutcome: gradedRecheckOutcome,
                    recorder: gradedRunRecorder,
                    gate: gradedResolverGate
                )
            }
                ?? ScannedGradedResolver(),
            priceCheckRefreshProvider: priceCheckProvider ?? priceCheckOutcome.map {
                ScannerStubPriceCheckProvider(outcome: $0)
            },
            catalogCoordinator: catalogCoordinator,
            magicCatalogCoordinator: magicCatalogCoordinator,
            unresolvedScanStore: unresolvedScanStore ?? UnresolvedScanStore(
                fileURL: root.appendingPathComponent("Scanner/unresolved-scans.json")
            ),
            sessionMetricsLog: sessionMetricsLog ?? ScanSessionMetricsLog(
                fileURL: root.appendingPathComponent("Scanner/scan-session-metrics.json")
            ),
            metricsDefaults: metricsDefaults,
            collectionAddOverride: collectionAddOverride,
            certificationRefinementOverride: certificationRefinementOverride
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
        includeFinishChoice: Bool = false,
        firstSetProviderID: String = "held-repeat-a",
        firstSetCode: String = "HRA"
    ) async throws -> (
        offline: PokemonOfflineCatalog,
        first: ScanSubject,
        second: ScanSubject
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TradingCardScannerHistoricalHeldRepeat-\(UUID().uuidString)", isDirectory: true)
        let store = PokemonChecklistStore(root: root, bundle: nil, bundledRoot: root)
        let firstSetID = CatalogSetID(game: .pokemon, providerID: firstSetProviderID)
        let secondSetID = CatalogSetID(game: .pokemon, providerID: "held-repeat-b")
        let firstSet = CatalogSet(
            catalogID: firstSetID,
            name: "Held Repeat A",
            code: firstSetCode,
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
            providerID: "\(firstSetProviderID)-001",
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
            providerID: "\(firstSetProviderID)-001",
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
        certificationNumber: String? = "12345678",
        finish: PhysicalVariant? = nil
    ) -> ScanSubject {
        ScanSubject(
            identifier: scannerIdentifier(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: value, label: label),
                certificationNumber: certificationNumber,
                labelCardText: [],
                printedFinish: finish
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
        setID: String = "test-set",
        officialCount: Int = 10
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
                cardCount: TCGdexCardCount(total: officialCount, official: officialCount)
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
