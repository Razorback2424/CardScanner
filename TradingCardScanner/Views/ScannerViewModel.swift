import Combine
import Foundation
import SwiftData
import UIKit

extension ScanIdentifier {
    /// Modern and Magic receipts keep their existing catalog-formatted text.
    /// Historical subsets retain the denominator actually printed on the card,
    /// which cannot be reconstructed from the containing set's official count.
    func scannerDisplayIdentifier(for card: IdentifiedCard) -> String {
        if case .pokemonHistorical = self { return displayIdentifier }
        return card.identifier
    }
}

enum ScanPurpose: String, CaseIterable, Identifiable, Hashable {
    case collection
    case priceCheck

    var id: String { rawValue }
    var title: String { self == .collection ? "Collection" : "Price Check" }
    var statusText: String {
        self == .collection ? "Scans are added automatically" : "Value only · Nothing is added"
    }
}

/// Immutable intent attached at confirmation time. A completion may route only
/// according to this captured value, never according to the picker later shown.
struct ScanRequest: Identifiable, Equatable {
    let id: UUID
    let identifier: ScanIdentifier
    let purpose: ScanPurpose
    let generation: Int

    init(
        id: UUID = UUID(),
        identifier: ScanIdentifier,
        purpose: ScanPurpose,
        generation: Int
    ) {
        self.id = id
        self.identifier = identifier
        self.purpose = purpose
        self.generation = generation
    }
}

struct ResolvedScan {
    let request: ScanRequest
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    let pokemonPrintRun: PokemonPrintRun?
    let options: [PhysicalVariant]
}

struct PriceCheckResult: Identifiable {
    let id = UUID()
    let resolvedScan: ResolvedScan
    var quote: PriceLookup
    var checkedAt: Date
    var refreshFailed = false
    var isRefreshing = false

    var card: IdentifiedCard { resolvedScan.card }
    var resolved: ResolvedVariant { resolvedScan.resolved }
    var pokemonPrintRun: PokemonPrintRun? { resolvedScan.pokemonPrintRun }

    var display: PriceDisplay {
        switch quote {
        case let .price(price):
            return PriceDisplay(
                amount: price.unitMarketPriceUSD,
                currencyCode: price.currencyCode,
                source: price.source,
                sourceUpdatedAt: price.sourceUpdatedAt,
                fetchedAt: price.fetchedAt,
                lastCheckedAt: checkedAt,
                refreshFailed: refreshFailed
            )
        case let .unavailable(source):
            return PriceDisplay(
                source: source,
                fetchedAt: checkedAt,
                lastCheckedAt: checkedAt,
                refreshFailed: refreshFailed
            )
        }
    }
}

/// One card that made it into the collection during this session.
struct RecentScan: Identifiable, Equatable {
    let id: UUID
    let identifier: ScanIdentifier
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    let pokemonPrintRun: PokemonPrintRun?
    /// Every variant this printing could physically have been, kept so the same
    /// question can be re-asked later without another catalog round trip.
    let options: [PhysicalVariant]
    let mutation: CollectionMutation

    init(
        id: UUID = UUID(),
        identifier: ScanIdentifier,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun? = nil,
        options: [PhysicalVariant],
        mutation: CollectionMutation
    ) {
        self.id = id
        self.identifier = identifier
        self.card = card
        self.resolved = resolved
        self.pokemonPrintRun = pokemonPrintRun
        self.options = options
        self.mutation = mutation
    }

    private var stampedRelease: PokemonStampedReleaseCatalog.Entry? {
        PokemonStampedReleaseCatalog.entry(
            providerID: card.providerID,
            variantID: resolved.variant?.id
        )
    }

    var thumbnailURL: URL? {
        stampedRelease.flatMap {
            JustTCGV1Client.productImageURL(tcgplayerID: $0.tcgplayerProductID)
        } ?? card.thumbnailImageURL
    }

    var displayImageURL: URL? {
        stampedRelease.flatMap {
            JustTCGV1Client.productImageURL(tcgplayerID: $0.tcgplayerProductID)
        } ?? card.displayImageURL
    }
    var displaySetName: String {
        stampedRelease.map { "Trick or Trade \($0.year)" } ?? card.setName
    }

    static func == (lhs: RecentScan, rhs: RecentScan) -> Bool {
        lhs.id == rhs.id && lhs.resolved == rhs.resolved
    }
}

/// The inline fork. Shown over the live camera, answered with one tap that means
/// both "this variant" and "continue" — never a variant question followed by a
/// separate confirmation, because the first tap already expressed the intent.
struct PendingVariantChoice: Identifiable, Equatable {
    let id = UUID()
    let request: ScanRequest
    let card: IdentifiedCard
    let options: [PhysicalVariant]
    let pokemonPrintRun: PokemonPrintRun?
    /// Set when Finish Lock named a variant this printing does not exist in. The
    /// lock is evidence, not an override, so the user is told rather than obeyed.
    let lockDidNotApply: PhysicalVariant?

    var identifier: ScanIdentifier { request.identifier }

    static func == (lhs: PendingVariantChoice, rhs: PendingVariantChoice) -> Bool { lhs.id == rhs.id }
}

/// Historical print run is independent of finish and is resolved before any
/// collection mutation. Only sets with documented separate runs create this
/// question.
struct PendingPrintRunChoice: Identifiable, Equatable {
    let id = UUID()
    let request: ScanRequest
    let card: IdentifiedCard
    let options: [PokemonPrintRun]

    var identifier: ScanIdentifier { request.identifier }

    static func == (lhs: PendingPrintRunChoice, rhs: PendingPrintRunChoice) -> Bool { lhs.id == rhs.id }
}

struct PendingIdentityChoice: Identifiable, Equatable {
    let id = UUID()
    let request: ScanRequest
    let evidence: PokemonHistoricalScanEvidence
    let candidates: [PokemonCatalogCardIdentity]

    var identifier: ScanIdentifier { request.identifier }

    static func == (lhs: PendingIdentityChoice, rhs: PendingIdentityChoice) -> Bool { lhs.id == rhs.id }
}

/// A failed scan kept for the lifetime of the scanner session. The warning chip
/// opens these details; it never doubles as a destructive clear action.
struct UnresolvedScan: Identifiable, Equatable {
    let id = UUID()
    let identifier: ScanIdentifier

    var titleCandidates: [String] {
        guard case let .pokemonHistorical(evidence) = identifier else { return [] }
        return evidence.titleCandidates
    }

    /// What makes two failures the same physical card.
    ///
    /// A historical identifier carries every title observation, and title OCR
    /// wobbles frame to frame — "nintend" and "nintendo" a frame apart — so one
    /// unreadable card produced two evidence values and two rows in the list.
    /// The printed number is the stable part, and within a scanning session it
    /// is what identifies the card in the user's hand.
    private var mergeKey: String {
        switch identifier {
        case let .pokemonHistorical(evidence):
            return "historical:\(evidence.number.displayIdentifier)"
        default:
            return "identifier:\(identifier.displayIdentifier)"
        }
    }

    /// Adds a failure to the list, folding it into an existing row for the same
    /// card and keeping every distinct reading so the user can see what it read.
    static func merging(
        _ scans: [UnresolvedScan],
        with identifier: ScanIdentifier
    ) -> [UnresolvedScan] {
        let incoming = UnresolvedScan(identifier: identifier)
        guard let index = scans.firstIndex(where: { $0.mergeKey == incoming.mergeKey }) else {
            return scans + [incoming]
        }
        var merged = scans
        merged[index] = merged[index].absorbing(incoming)
        return merged
    }

    private func absorbing(_ other: UnresolvedScan) -> UnresolvedScan {
        guard case let .pokemonHistorical(mine) = identifier,
              case let .pokemonHistorical(theirs) = other.identifier else { return self }
        let titles = Array(Set(mine.titleCandidates + theirs.titleCandidates)).sorted()
        return UnresolvedScan(
            identifier: .pokemonHistorical(
                PokemonHistoricalScanEvidence(number: mine.number, titleCandidates: titles)
            )
        )
    }

    private var number: PokemonPrintedNumberEvidence? {
        guard case let .pokemonHistorical(evidence) = identifier else { return nil }
        return evidence.number
    }
}

/// The transparent receipt. Visible by default, interactive only if something is
/// wrong — it never asks the user to approve what already happened.
struct ScanReceipt: Identifiable, Equatable {
    let id = UUID()
    let scanID: RecentScan.ID
    let name: String
    let identifier: String
    let variantLabel: String
    let thumbnailURL: URL?

    static func == (lhs: ScanReceipt, rhs: ScanReceipt) -> Bool { lhs.id == rhs.id }
}

/// A short, non-blocking note beside the scan band. Never a dialog: one awkward
/// card must not be able to derail a hundred-card session.
struct ScanNote: Identifiable, Equatable {
    enum Tone: Equatable { case info, problem }

    let id = UUID()
    let text: String
    let tone: Tone

    static func == (lhs: ScanNote, rhs: ScanNote) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published private(set) var purpose: ScanPurpose = .collection
    @Published private(set) var pendingChoice: PendingVariantChoice?
    @Published private(set) var pendingPrintRunChoice: PendingPrintRunChoice?
    @Published private(set) var pendingIdentityChoice: PendingIdentityChoice?
    @Published private(set) var receipt: ScanReceipt?
    @Published private(set) var recent: [RecentScan] = []
    @Published private(set) var note: ScanNote?
    @Published var priceCheckResult: PriceCheckResult?
    /// Cards whose identity was read but which could not be resolved. Counted so
    /// the session can end with an honest total instead of a stream of alerts.
    @Published private(set) var unresolvedScans: [UnresolvedScan] = []
    var unresolvedCount: Int { unresolvedScans.count }
    /// True only once a lookup has been outstanding long enough to be worth
    /// mentioning. With the speculative fetch already in flight most lookups
    /// finish before this ever flips, and a spinner that blinks on every card
    /// would be noise rather than reassurance.
    @Published private(set) var isSlowIdentifying = false
    /// Increments on every successful add so the preview can flash the band.
    @Published private(set) var successCount = 0
    /// One lock per game, because a Pokémon lock says nothing about a Magic card
    /// and the scanner no longer knows which is coming next. Only the lock for
    /// the game of the card just identified is ever consulted.
    @Published private(set) var finishLocks: [CardGame: PhysicalVariant] = [:]

    let scanner = CardScanner()

    private let catalog = CardCatalog()
    private let feedback = ScanFeedback()
    private let scryfall = ScryfallService()

    private var store: CollectionStore?
    private var prices: PriceStore?
    private var priceCheckCoordinator: PriceCheckCoordinator?
    private var noteTask: Task<Void, Never>?
    private var receiptTask: Task<Void, Never>?
    private var magicDirectoryTask: Task<Void, Never>?
    /// The best directory available in this process. It begins with the bundled
    /// snapshot and is replaced after a successful live refresh. Keeping the
    /// actual definitions prevents a later view appearance from downgrading the
    /// scanner back to the snapshot.
    private var magicSetDefinitions = MagicSetSnapshot.definitions
    private var hasRefreshedMagicDirectory = false
    private var identificationsInFlight = 0
    private var slowLookupTask: Task<Void, Never>?
    /// Confirmations are consumed in physical scan order. Catalog prefetching can
    /// still overlap the network work, but only one result is allowed to mutate
    /// session UI at a time so an unanswered finish choice cannot be overwritten
    /// by a later card whose request happened to finish first.
    private var identificationQueue: [ScanRequest] = []
    private var isProcessingIdentification = false
    private var identificationTask: Task<Void, Never>?
    private var activeIdentificationRequestID: UUID?
    private var resolutionTask: Task<Void, Never>?
    private var quoteRefreshTask: Task<Void, Never>?
    private var scanGeneration = 0
    /// Enough to take back the most recent add, including the question that was
    /// asked at the time so undo can re-ask it.
    private var lastAdd: RecentScan?

    /// The receipt is an undo affordance, not a fleeting toast. It remains
    /// available through the next card's recognition until a new add replaces
    /// it, the person takes another scanner action, or five seconds pass.
    private static let receiptLifetime: Duration = .seconds(5)
    private static let slowLookupThreshold: Duration = .milliseconds(400)
    private static let noteLifetime: Duration = .milliseconds(2600)

    init() {
        scanner.onPlausibleCandidate = { [weak self] identifier in
            guard let self else { return }
            // Speculation only. Nothing downstream may act on this.
            Task { await self.catalog.prefetch(identifier) }
        }

        scanner.onConfirmedCandidate = { [weak self] identifier in
            guard let self else { return }
            Task { self.enqueueIdentification(identifier) }
        }

        scanner.onLatchHolding = { [weak self] _ in
            Task { @MainActor in
                self?.show(ScanNote(text: "Already added — lift the card for the next one", tone: .info))
            }
        }
    }

    // MARK: - Session lifecycle

    func start(context: ModelContext) {
        store = CollectionStore(context: context)
        prices = PriceStore(context: context)
        priceCheckCoordinator = PriceCheckCoordinator(context: context)
        recent.removeAll()
        feedback.prepare()
        scanner.start()

        // Magic's OCR vocabulary is its set directory, so the compiled-in
        // snapshot goes in before the first frame rather than after a network
        // round trip. The camera is useful immediately, and offline.
        scanner.useMagicDefinitions(magicSetDefinitions)
        resumeRecognitionIfPossible()
        refreshMagicDirectory()
    }

    func viewDisappeared() {
        invalidatePendingScan()
        quoteRefreshTask?.cancel()
        scanner.stop()
    }

    func scenePhaseChanged(isActive: Bool) {
        guard !isActive else { return }
        invalidatePendingScan()
        quoteRefreshTask?.cancel()
        if priceCheckResult?.isRefreshing == true {
            priceCheckResult?.isRefreshing = false
        }
    }

    /// A sheet is the one place the scanner should stop looking: the user is
    /// deliberately elsewhere, and a card added behind a sheet would be a card
    /// nobody saw being added.
    func pauseForPresentation() {
        dismissReceipt()
        scanner.pauseRecognition()
    }

    func resumeAfterPresentation() {
        feedback.prepare()
        resumeRecognitionIfPossible()
    }

    func dismissPriceCheckResult() {
        quoteRefreshTask?.cancel()
        priceCheckResult = nil
        feedback.prepare()
        resumeRecognitionIfPossible()
    }

    // MARK: - Controls

    func setPurpose(_ newPurpose: ScanPurpose) {
        guard newPurpose != purpose else { return }

        invalidatePendingScan()
        purpose = newPurpose
        feedback.choiceMade()
        UIAccessibility.post(notification: .announcement, argument: "\(newPurpose.title). \(newPurpose.statusText)")
    }

    private func invalidatePendingScan() {
        // Cancellation is an invalidation boundary, not a reinterpretation.
        // Existing completions are allowed to finish their network work but can
        // no longer affect any UI or destination.
        scanGeneration += 1
        identificationTask?.cancel()
        activeIdentificationRequestID = nil
        isProcessingIdentification = false
        resolutionTask?.cancel()
        identificationQueue.removeAll()
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        receiptTask?.cancel()
        receipt = nil
        noteTask?.cancel()
        note = nil
        scanner.discardCurrentObservation()
    }

    func setFinishLock(_ variant: PhysicalVariant?, for game: CardGame) {
        finishLocks[game] = variant
        feedback.choiceMade()

        // A lock set while a question is on screen answers that question's
        // premise, so re-run it rather than leaving a stale menu up.
        if let pending = pendingChoice,
           pending.identifier.game == game,
           let variant,
           pending.options.contains(variant) {
            choose(variant)
        }
    }

    func finishLock(for game: CardGame) -> PhysicalVariant? {
        finishLocks[game]
    }

    var activeFinishLocks: [(game: CardGame, variant: PhysicalVariant)] {
        CardGame.allCases.compactMap { game in
            finishLocks[game].map { (game, $0) }
        }
    }

    // MARK: - The one tap

    func choose(_ variant: PhysicalVariant) {
        guard let pending = pendingChoice else { return }
        feedback.choiceMade()
        route(
            ResolvedScan(
                request: pending.request,
                card: pending.card,
                resolved: ResolvedVariant(variant: variant, resolution: .userConfirmed),
                pokemonPrintRun: pending.pokemonPrintRun,
                options: pending.options
            )
        )
        processNextIdentificationIfPossible()
    }

    /// Walking away from a question writes nothing. The latch stays engaged, so
    /// the same card sitting in the band does not immediately ask again.
    func dismissChoice() {
        pendingChoice = nil
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    func choose(_ printRun: PokemonPrintRun) {
        guard let pending = pendingPrintRunChoice,
              pending.options.contains(printRun) else { return }
        feedback.choiceMade()
        pendingPrintRunChoice = nil
        resolveVariant(
            for: pending.request,
            card: pending.card,
            pokemonPrintRun: printRun
        )
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    func dismissPrintRunChoice() {
        pendingPrintRunChoice = nil
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    func choose(_ candidate: PokemonCatalogCardIdentity) {
        guard let pending = pendingIdentityChoice,
              pending.candidates.contains(candidate) else { return }
        feedback.choiceMade()

        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.beginIdentification()
            defer { self.endIdentification() }
            do {
                let card = try await self.catalog.card(
                    for: candidate,
                    matching: pending.evidence
                )
                guard !Task.isCancelled,
                      self.isCurrent(pending.request),
                      self.pendingIdentityChoice?.id == pending.id else { return }
                self.pendingIdentityChoice = nil
                self.resolvePrintRun(for: pending.request, card: card)
                self.resumeRecognitionIfPossible()
                self.processNextIdentificationIfPossible()
            } catch {
                guard !Task.isCancelled, self.isCurrent(pending.request) else { return }
                self.show(ScanNote(text: "Lookup failed — tap the set to retry", tone: .problem))
                self.feedback.problem()
            }
        }
    }

    func dismissIdentityChoice() {
        pendingIdentityChoice = nil
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    func undoLastAdd() {
        guard let store, let lastAdd else { return }

        do {
            try store.undo(lastAdd.mutation)
        } catch {
            show(ScanNote(text: "Undo could not be saved", tone: .problem))
            feedback.problem()
            return
        }
        recent.removeAll { $0.id == lastAdd.id }
        receipt = nil
        receiptTask?.cancel()
        feedback.undone()
        self.lastAdd = nil

        // "That wasn't Master Ball" is the actual reason people reach for undo,
        // so put the question back rather than making them re-present the card.
        let printRuns = PokemonMasterSetDefinition.printRuns(
            forSetProviderID: lastAdd.card.variantEvidence.setID
        )
        if !printRuns.isEmpty {
            pendingPrintRunChoice = PendingPrintRunChoice(
                request: ScanRequest(
                    identifier: lastAdd.identifier,
                    purpose: .collection,
                    generation: scanGeneration
                ),
                card: lastAdd.card,
                options: printRuns
            )
            scanner.pauseRecognition()
        } else if lastAdd.options.count > 1 {
            pendingChoice = PendingVariantChoice(
                request: ScanRequest(
                    identifier: lastAdd.identifier,
                    purpose: .collection,
                    generation: scanGeneration
                ),
                card: lastAdd.card,
                options: lastAdd.options,
                pokemonPrintRun: nil,
                lockDidNotApply: nil
            )
            scanner.pauseRecognition()
        }
    }

    func deleteRecentScan(_ scan: RecentScan) {
        guard let store else { return }

        do {
            try store.undo(scan.mutation)
        } catch {
            show(ScanNote(text: "Delete could not be saved", tone: .problem))
            feedback.problem()
            return
        }

        recent.removeAll { $0.id == scan.id }
        if lastAdd?.id == scan.id {
            lastAdd = nil
            receipt = nil
            receiptTask?.cancel()
        }
        feedback.undone()
    }

    func clearUnresolvedScans() {
        unresolvedScans.removeAll()
    }

    // MARK: - Corrections

    /// Re-answers the variant question for a card already in the collection,
    /// moving the copy from one row to the other.
    ///
    /// Takes an id rather than a value so a second correction in the same sitting
    /// moves the copy from where it actually is now, not from where it started.
    func correct(scanID: RecentScan.ID, to variant: PhysicalVariant) {
        guard let store,
              let scan = recent.first(where: { $0.id == scanID }),
              scan.resolved.variant != variant else { return }

        let corrected = ResolvedVariant(variant: variant, resolution: .userConfirmed)
        guard let mutation = try? store.recordVariantCorrection(
            for: scan.card,
            from: scan.resolved.variant,
            to: corrected,
            pokemonPrintRun: scan.pokemonPrintRun,
            previousCollectionKey: scan.mutation.collectionKey
        ) else { return }

        // Reuse the id so the rail thumbnail stays the same item rather than
        // animating out and back in for what the user experienced as an edit.
        let replacement = RecentScan(
            id: scan.id,
            identifier: scan.identifier,
            card: scan.card,
            resolved: corrected,
            pokemonPrintRun: scan.pokemonPrintRun,
            options: scan.options,
            mutation: mutation
        )

        if let index = recent.firstIndex(where: { $0.id == scan.id }) {
            recent[index] = replacement
        }
        if lastAdd?.id == scan.id {
            lastAdd = replacement
        }
        recordPrice(
            for: scan.card,
            variant: variant,
            pokemonPrintRun: scan.pokemonPrintRun
        )
        feedback.choiceMade()
    }

    /// Writes the price the identification already carried.
    ///
    /// `savingImmediately` exists because the price store and the collection
    /// store share one `ModelContext`: a caller that is about to write the card
    /// anyway can let that write's save carry this one too. Two saves in a row
    /// cost two passes over every `@Query` in the app — including the
    /// collection tab, which stays alive behind the scanner — and the second
    /// one lands inside the tap that is trying to animate the choice bar away.
    private func recordPrice(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun? = nil,
        savingImmediately: Bool = true
    ) {
        guard let prices else { return }
        prices.store(
            CardPricing.price(
                for: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            ),
            game: card.game,
            printingID: pokemonPrintRun.map { "\(card.providerID)@\($0.rawValue)" }
                ?? card.providerID,
            variantID: variant?.id
        )
        guard savingImmediately else { return }
        prices.save()
    }

    // MARK: - Identification

    private func enqueueIdentification(_ identifier: ScanIdentifier) {
        let request = ScanRequest(
            identifier: identifier,
            purpose: purpose,
            generation: scanGeneration
        )
        // Price Check is intentionally a one-card transaction. The confidence
        // threshold is unchanged; only after that threshold do we stop feeding
        // another candidate into the pipeline.
        if request.purpose == .priceCheck {
            scanner.pauseRecognition()
        }
        identificationQueue.append(request)
        processNextIdentificationIfPossible()
    }

    private func processNextIdentificationIfPossible() {
        guard !isProcessingIdentification,
              pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              !identificationQueue.isEmpty else { return }

        let request = identificationQueue.removeFirst()
        isProcessingIdentification = true
        activeIdentificationRequestID = request.id

        identificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.identify(request)
            guard self.activeIdentificationRequestID == request.id else { return }
            self.isProcessingIdentification = false
            self.identificationTask = nil
            self.activeIdentificationRequestID = nil
            self.processNextIdentificationIfPossible()
        }
    }

    private func identify(_ request: ScanRequest) async {
        beginIdentification()
        defer { endIdentification() }

        do {
            let card = try await catalog.card(for: request.identifier)
            guard !Task.isCancelled, isCurrent(request) else { return }
            // Undo can restore a finish question while this lookup is awaiting
            // the network. Put this already-cached result back at the front
            // instead of replacing the question the user is answering.
            guard pendingChoice == nil,
                  pendingPrintRunChoice == nil,
                  pendingIdentityChoice == nil else {
                identificationQueue.insert(request, at: 0)
                return
            }
            resolvePrintRun(for: request, card: card)
        } catch let error as PokemonHistoricalCatalogError {
            guard !Task.isCancelled, isCurrent(request) else { return }
            handleHistoricalResolution(error, request: request)
        } catch {
            guard !Task.isCancelled, isCurrent(request) else { return }
            handleLookupFailure(request, error)
        }
    }

    private func handleHistoricalResolution(
        _ error: PokemonHistoricalCatalogError,
        request: ScanRequest
    ) {
        switch error {
        case let .ambiguous(candidates):
            guard case let .pokemonHistorical(evidence) = request.identifier else {
                handleLookupFailure(request, error)
                return
            }
            receipt = nil
            receiptTask?.cancel()
            pendingIdentityChoice = PendingIdentityChoice(
                request: request,
                evidence: evidence,
                candidates: candidates
            )
            scanner.pauseRecognition()
            feedback.needsChoice()
        case .unsupported:
            handleLookupFailure(request, error)
        }
    }

    private func beginIdentification() {
        identificationsInFlight += 1
        guard identificationsInFlight == 1 else { return }

        slowLookupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.slowLookupThreshold)
            guard !Task.isCancelled, let self, self.identificationsInFlight > 0 else { return }
            self.isSlowIdentifying = true
        }
    }

    private func endIdentification() {
        identificationsInFlight -= 1
        guard identificationsInFlight <= 0 else { return }
        identificationsInFlight = 0
        slowLookupTask?.cancel()
        isSlowIdentifying = false
    }

    private func resolvePrintRun(for request: ScanRequest, card: IdentifiedCard) {
        guard isCurrent(request) else { return }
        let options = card.game == .pokemon
            ? PokemonMasterSetDefinition.printRuns(forSetProviderID: card.variantEvidence.setID)
            : []
        guard !options.isEmpty else {
            resolveVariant(for: request, card: card, pokemonPrintRun: nil)
            return
        }

        receipt = nil
        receiptTask?.cancel()
        pendingPrintRunChoice = PendingPrintRunChoice(
            request: request,
            card: card,
            options: options
        )
        scanner.pauseRecognition()
        feedback.needsChoice()
    }

    private func resolveVariant(
        for request: ScanRequest,
        card: IdentifiedCard,
        pokemonPrintRun: PokemonPrintRun?
    ) {
        guard isCurrent(request) else { return }
        // The print run question was just answered, and TCGdex reports 1st
        // Edition as a finish as well as a run. Left in, it comes straight back
        // as a second bar naming the same edition the user already tapped.
        var evidence = card.variantEvidence
        if pokemonPrintRun != nil {
            evidence = evidence.excludingFirstEditionPseudoFinish()
        }

        switch VariantResolver.resolve(evidence, finishLock: finishLocks[card.game]) {
        case let .resolved(resolved):
            route(
                ResolvedScan(
                    request: request,
                    card: card,
                    resolved: resolved,
                    pokemonPrintRun: pokemonPrintRun,
                    options: VariantResolver.options(for: evidence)
                )
            )

        case let .needsChoice(options, lockDidNotApply):
            receipt = nil
            receiptTask?.cancel()
            pendingChoice = PendingVariantChoice(
                request: request,
                card: card,
                options: options,
                pokemonPrintRun: pokemonPrintRun,
                lockDidNotApply: lockDidNotApply
            )
            scanner.pauseRecognition()
            if let lockDidNotApply {
                show(ScanNote(text: "No \(lockDidNotApply.label) printing of this card", tone: .info))
            }
            feedback.needsChoice()
        }
    }

    // MARK: - Resolved destinations

    private func route(_ resolvedScan: ResolvedScan) {
        guard isCurrent(resolvedScan.request) else { return }
        switch resolvedScan.request.purpose {
        case .collection:
            commitCollection(resolvedScan)
        case .priceCheck:
            presentPriceCheck(resolvedScan)
        }
    }

    /// The only resolved-scan destination with collection mutation authority.
    private func commitCollection(_ resolvedScan: ResolvedScan) {
        guard let store else { return }
        let identifier = resolvedScan.request.identifier
        let card = resolvedScan.card
        let resolved = resolvedScan.resolved
        let pokemonPrintRun = resolvedScan.pokemonPrintRun
        let options = resolvedScan.options

        // Pricing is secondary mutable metadata and must never be in the way of
        // "card added". Nothing here touches the network: the price rides along
        // in the catalog response the identification already made, and a card
        // whose response carried none simply waits for the next price refresh.
        //
        // Staged before the add rather than after it so the add's own save is
        // the only save this tap performs. Both stores hold the same context,
        // and nothing in the add reads a price record, so the order is free.
        recordPrice(
            for: card,
            variant: resolved.variant,
            pokemonPrintRun: pokemonPrintRun,
            savingImmediately: false
        )

        guard let mutation = try? store.add(
            card,
            resolved: resolved,
            source: .scan,
            pokemonPrintRun: pokemonPrintRun,
            matchCatalogAliases: pokemonPrintRun != nil
        ) else {
            show(ScanNote(text: "Card could not be saved", tone: .problem))
            feedback.problem()
            return
        }
        let scan = RecentScan(
            identifier: identifier,
            card: card,
            resolved: resolved,
            pokemonPrintRun: pokemonPrintRun,
            options: options,
            mutation: mutation
        )

        recent.insert(scan, at: 0)
        lastAdd = scan
        if pendingChoice?.request.id == resolvedScan.request.id {
            pendingChoice = nil
            resumeRecognitionIfPossible()
        }
        successCount += 1

        showReceipt(
            ScanReceipt(
                scanID: scan.id,
                name: card.name,
                identifier: identifier.scannerDisplayIdentifier(for: card),
                variantLabel: [pokemonPrintRun?.label, resolved.label]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                thumbnailURL: scan.thumbnailURL
            )
        )
        feedback.added()
    }

    /// The Price Check coordinator intentionally has no `CollectionStore`.
    private func presentPriceCheck(_ resolvedScan: ResolvedScan) {
        guard let priceCheckCoordinator, isCurrent(resolvedScan.request) else { return }
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        scanner.pauseRecognition()
        priceCheckResult = priceCheckCoordinator.present(resolvedScan)
    }

    func refreshPriceCheckQuote() {
        guard var result = priceCheckResult, !result.isRefreshing else { return }
        result.isRefreshing = true
        result.refreshFailed = false
        priceCheckResult = result
        let resultID = result.id

        quoteRefreshTask?.cancel()
        quoteRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let priceCheckCoordinator = self.priceCheckCoordinator else { return }
            switch await priceCheckCoordinator.refresh(result) {
            case let .quote(refreshed):
                guard !Task.isCancelled,
                      var latest = self.priceCheckResult,
                      latest.id == resultID else { return }
                latest.quote = refreshed
                latest.checkedAt = .now
                latest.isRefreshing = false
                latest.refreshFailed = false
                self.priceCheckResult = latest
            case .failed(_):
                guard !Task.isCancelled,
                      var latest = self.priceCheckResult,
                      latest.id == resultID else { return }
                priceCheckCoordinator.recordRefreshFailure(for: latest)
                latest.isRefreshing = false
                latest.refreshFailed = true
                self.priceCheckResult = latest
            }
        }
    }

    /// Settings and review sheets may be opened while a finish question is
    /// pending. Dismissing either sheet must not restart OCR behind that question.
    private func resumeRecognitionIfPossible() {
        guard priceCheckResult == nil else { return }
        guard pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil else { return }
        scanner.resumeRecognition()
    }

    private func isCurrent(_ request: ScanRequest) -> Bool {
        request.generation == scanGeneration
    }

    private func handleLookupFailure(_ request: ScanRequest, _ error: Error) {
        let identifier = request.identifier
        feedback.problem()

        switch CardCatalog.classify(error) {
        case .transient:
            // Nothing is known to be wrong with the card, so let the very next
            // reading through instead of making the user re-present it.
            scanner.allowImmediateRetry()
            show(ScanNote(text: "Lookup failed — keep the card in the box", tone: .problem))

        case .notInCatalog:
            // Re-reading will fail identically. The latch holds, so this is asked
            // once and the session keeps moving.
            unresolvedScans = UnresolvedScan.merging(unresolvedScans, with: identifier)
            show(ScanNote(text: "Can't confirm \(identifier.displayIdentifier) — set it aside", tone: .problem))
        }

        // Price Check paused at confirmation to enforce its one-card contract;
        // a failed lookup has no result to present, so rearm it for a fresh card.
        if request.purpose == .priceCheck {
            resumeRecognitionIfPossible()
        }
    }

    // MARK: - Transient UI

    private func showReceipt(_ newReceipt: ScanReceipt) {
        receiptTask?.cancel()
        receipt = newReceipt

        receiptTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.receiptLifetime)
            guard !Task.isCancelled else { return }
            if self?.receipt?.id == newReceipt.id {
                self?.receipt = nil
            }
        }
    }

    private func dismissReceipt() {
        receiptTask?.cancel()
        receipt = nil
    }

    private func show(_ newNote: ScanNote) {
        noteTask?.cancel()
        note = newNote

        noteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.noteLifetime)
            guard !Task.isCancelled else { return }
            if self?.note?.id == newNote.id {
                self?.note = nil
            }
        }
    }

    // MARK: - Magic set directory

    /// Replaces the compiled-in snapshot with the live directory.
    ///
    /// Recognition is never paused for this. The snapshot already works, so the
    /// refresh only ever adds the sets released since it was generated, and a
    /// failure costs those sets rather than the feature — which is why it is
    /// silent. It retries on the next session if it did not succeed.
    private func refreshMagicDirectory() {
        guard !hasRefreshedMagicDirectory, magicDirectoryTask == nil else { return }

        magicDirectoryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.magicDirectoryTask = nil }

            guard let definitions = try? await self.scryfall.fetchSupportedSets(),
                  !definitions.isEmpty else { return }

            self.magicSetDefinitions = definitions
            self.hasRefreshedMagicDirectory = true
            self.scanner.useMagicDefinitions(definitions)
        }
    }
}
