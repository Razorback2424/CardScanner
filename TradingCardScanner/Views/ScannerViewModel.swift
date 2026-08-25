import Combine
import Foundation
import SwiftData
import UIKit

/// One card that made it into the collection during this session.
struct RecentScan: Identifiable, Equatable {
    let id: UUID
    let identifier: ScanIdentifier
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    /// Every variant this printing could physically have been, kept so the same
    /// question can be re-asked later without another catalog round trip.
    let options: [PhysicalVariant]
    let mutation: CollectionMutation

    init(
        id: UUID = UUID(),
        identifier: ScanIdentifier,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        options: [PhysicalVariant],
        mutation: CollectionMutation
    ) {
        self.id = id
        self.identifier = identifier
        self.card = card
        self.resolved = resolved
        self.options = options
        self.mutation = mutation
    }

    var thumbnailURL: URL? { card.thumbnailImageURL }

    static func == (lhs: RecentScan, rhs: RecentScan) -> Bool {
        lhs.id == rhs.id && lhs.resolved == rhs.resolved
    }
}

/// The inline fork. Shown over the live camera, answered with one tap that means
/// both "this variant" and "save it" — never a variant question followed by a
/// separate confirmation, because the first tap already expressed the intent.
struct PendingVariantChoice: Identifiable, Equatable {
    let id = UUID()
    let identifier: ScanIdentifier
    let card: IdentifiedCard
    let options: [PhysicalVariant]
    /// Set when Finish Lock named a variant this printing does not exist in. The
    /// lock is evidence, not an override, so the user is told rather than obeyed.
    let lockDidNotApply: PhysicalVariant?

    static func == (lhs: PendingVariantChoice, rhs: PendingVariantChoice) -> Bool { lhs.id == rhs.id }
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
    @Published private(set) var pendingChoice: PendingVariantChoice?
    @Published private(set) var receipt: ScanReceipt?
    @Published private(set) var recent: [RecentScan] = []
    @Published private(set) var note: ScanNote?
    /// Cards whose identity was read but which could not be resolved. Counted so
    /// the session can end with an honest total instead of a stream of alerts.
    @Published private(set) var unresolvedCount = 0
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
    private var identificationQueue: [ScanIdentifier] = []
    private var isProcessingIdentification = false
    /// Enough to take back the most recent add, including the question that was
    /// asked at the time so undo can re-ask it.
    private var lastAdd: RecentScan?

    /// How many thumbnails the rail keeps. Enough to glance at, few enough to
    /// stay out of the way.
    private static let recentLimit = 3
    private static let receiptLifetime: Duration = .milliseconds(1800)
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
        scanner.stop()
    }

    /// A sheet is the one place the scanner should stop looking: the user is
    /// deliberately elsewhere, and a card added behind a sheet would be a card
    /// nobody saw being added.
    func pauseForPresentation() {
        scanner.pauseRecognition()
    }

    func resumeAfterPresentation() {
        feedback.prepare()
        resumeRecognitionIfPossible()
    }

    // MARK: - Controls

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
        commit(
            identifier: pending.identifier,
            card: pending.card,
            resolved: ResolvedVariant(variant: variant, resolution: .userConfirmed),
            options: pending.options
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

    func undoLastAdd() {
        guard let store, let lastAdd else { return }

        store.undo(lastAdd.mutation)
        recent.removeAll { $0.id == lastAdd.id }
        receipt = nil
        receiptTask?.cancel()
        feedback.undone()
        self.lastAdd = nil

        // "That wasn't Master Ball" is the actual reason people reach for undo,
        // so put the question back rather than making them re-present the card.
        if lastAdd.options.count > 1 {
            pendingChoice = PendingVariantChoice(
                identifier: lastAdd.identifier,
                card: lastAdd.card,
                options: lastAdd.options,
                lockDidNotApply: nil
            )
            scanner.pauseRecognition()
        }
    }

    func clearUnresolvedCount() {
        unresolvedCount = 0
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
        guard let mutation = store.recordVariantCorrection(
            for: scan.card,
            from: scan.resolved.variant,
            to: corrected
        ) else { return }

        // Reuse the id so the rail thumbnail stays the same item rather than
        // animating out and back in for what the user experienced as an edit.
        let replacement = RecentScan(
            id: scan.id,
            identifier: scan.identifier,
            card: scan.card,
            resolved: corrected,
            options: scan.options,
            mutation: mutation
        )

        if let index = recent.firstIndex(where: { $0.id == scan.id }) {
            recent[index] = replacement
        }
        if lastAdd?.id == scan.id {
            lastAdd = replacement
        }
        recordPrice(for: scan.card, variant: variant)
        feedback.choiceMade()
    }

    private func recordPrice(for card: IdentifiedCard, variant: PhysicalVariant?) {
        guard let prices else { return }
        prices.store(
            CardPricing.price(for: card, variant: variant),
            game: card.game,
            printingID: card.providerID,
            variantID: variant?.id
        )
        prices.save()
    }

    // MARK: - Identification

    private func enqueueIdentification(_ identifier: ScanIdentifier) {
        identificationQueue.append(identifier)
        processNextIdentificationIfPossible()
    }

    private func processNextIdentificationIfPossible() {
        guard !isProcessingIdentification,
              pendingChoice == nil,
              !identificationQueue.isEmpty else { return }

        let identifier = identificationQueue.removeFirst()
        isProcessingIdentification = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.identify(identifier)
            self.isProcessingIdentification = false
            self.processNextIdentificationIfPossible()
        }
    }

    private func identify(_ identifier: ScanIdentifier) async {
        beginIdentification()
        defer { endIdentification() }

        do {
            let card = try await catalog.card(for: identifier)
            // Undo can restore a finish question while this lookup is awaiting
            // the network. Put this already-cached result back at the front
            // instead of replacing the question the user is answering.
            guard pendingChoice == nil else {
                identificationQueue.insert(identifier, at: 0)
                return
            }
            resolveVariant(for: identifier, card: card)
        } catch {
            handleLookupFailure(identifier, error)
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

    private func resolveVariant(for identifier: ScanIdentifier, card: IdentifiedCard) {
        let evidence = card.variantEvidence

        switch VariantResolver.resolve(evidence, finishLock: finishLocks[card.game]) {
        case let .resolved(resolved):
            commit(
                identifier: identifier,
                card: card,
                resolved: resolved,
                options: VariantResolver.options(for: evidence)
            )

        case let .needsChoice(options, lockDidNotApply):
            receipt = nil
            receiptTask?.cancel()
            pendingChoice = PendingVariantChoice(
                identifier: identifier,
                card: card,
                options: options,
                lockDidNotApply: lockDidNotApply
            )
            scanner.pauseRecognition()
            if let lockDidNotApply {
                show(ScanNote(text: "No \(lockDidNotApply.label) printing of this card", tone: .info))
            }
            feedback.needsChoice()
        }
    }

    private func commit(
        identifier: ScanIdentifier,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        options: [PhysicalVariant]
    ) {
        guard let store else { return }

        let mutation = store.add(card, resolved: resolved, source: .scan)
        let scan = RecentScan(
            identifier: identifier,
            card: card,
            resolved: resolved,
            options: options,
            mutation: mutation
        )

        // Pricing is secondary mutable metadata and must never be in the way of
        // "card added". Nothing here touches the network: the price rides along
        // in the catalog response the identification already made, and a card
        // whose response carried none simply waits for the next price refresh.
        recordPrice(for: card, variant: resolved.variant)

        recent.insert(scan, at: 0)
        if recent.count > Self.recentLimit {
            recent.removeLast(recent.count - Self.recentLimit)
        }
        lastAdd = scan
        if pendingChoice?.identifier == identifier {
            pendingChoice = nil
            resumeRecognitionIfPossible()
        }
        successCount += 1

        showReceipt(
            ScanReceipt(
                scanID: scan.id,
                name: card.name,
                identifier: card.identifier,
                variantLabel: resolved.label,
                thumbnailURL: card.thumbnailImageURL
            )
        )
        feedback.added()
    }

    /// Settings and review sheets may be opened while a finish question is
    /// pending. Dismissing either sheet must not restart OCR behind that question.
    private func resumeRecognitionIfPossible() {
        guard pendingChoice == nil else { return }
        scanner.resumeRecognition()
    }

    private func handleLookupFailure(_ identifier: ScanIdentifier, _ error: Error) {
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
            unresolvedCount += 1
            show(ScanNote(text: "Can't confirm \(identifier.displayIdentifier) — set it aside", tone: .problem))
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
