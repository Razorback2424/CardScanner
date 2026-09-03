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
    /// What choosing this mode actually does. Shown where the choice is made
    /// rather than permanently on the camera: it is the thing you need at the
    /// moment of deciding, and noise once you are scanning.
    var statusText: String {
        self == .collection ? "Scans are added automatically" : "Value only · Nothing is added"
    }
    var symbolName: String {
        self == .collection ? "rectangle.stack.badge.plus" : "tag"
    }
}

/// A scanner-domain encounter. Its id is created by `CardScanner` at the exact
/// frame that produced a confirmed OCR observation; generation is only for
/// invalidating asynchronous identification work.
struct ScanEncounter: Identifiable, Equatable, Sendable {
    let encounterID: UUID
    let identifier: ScanIdentifier
    let generation: Int
    let heldRepeatAuthorizationID: UUID?

    var id: UUID { encounterID }
}

/// Immutable intent attached at confirmation time. A completion may route only
/// according to this captured value, never according to the picker later shown.
struct ScanRequest: Identifiable, Equatable {
    let id: UUID
    let identifier: ScanIdentifier
    let purpose: ScanPurpose
    let generation: Int
    let encounterID: UUID
    let heldRepeatAuthorizationID: UUID?

    init(
        id: UUID = UUID(),
        identifier: ScanIdentifier,
        purpose: ScanPurpose,
        generation: Int,
        encounterID: UUID = UUID(),
        heldRepeatAuthorizationID: UUID? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.purpose = purpose
        self.generation = generation
        self.encounterID = encounterID
        self.heldRepeatAuthorizationID = heldRepeatAuthorizationID
    }
}

struct ResolvedScan {
    let request: ScanRequest
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    let pokemonPrintRun: PokemonPrintRun?
    let options: [PhysicalVariant]
}

/// The fully resolved value that may be detached from generation-owned work.
/// Once constructed, collection routing and duplicate confirmation no longer
/// depend on an identification task or its generation.
struct CollectionCommitCandidate {
    let requestID: UUID
    let identifier: ScanIdentifier
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    let pokemonPrintRun: PokemonPrintRun?
    let options: [PhysicalVariant]
    let price: PriceLookup
    let encounterID: UUID
    let heldRepeatAuthorizationID: UUID?

    init(resolvedScan: ResolvedScan) {
        requestID = resolvedScan.request.id
        identifier = resolvedScan.request.identifier
        card = resolvedScan.card
        resolved = resolvedScan.resolved
        pokemonPrintRun = resolvedScan.pokemonPrintRun
        options = resolvedScan.options
        price = CardPricing.price(
            for: resolvedScan.card,
            variant: resolvedScan.resolved.variant,
            pokemonPrintRun: resolvedScan.pokemonPrintRun
        )
        encounterID = resolvedScan.request.encounterID
        heldRepeatAuthorizationID = resolvedScan.request.heldRepeatAuthorizationID
    }

    var identity: ConsecutiveScanIdentity {
        ConsecutiveScanIdentity(card: card)
    }

    private init(
        requestID: UUID,
        identifier: ScanIdentifier,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun?,
        options: [PhysicalVariant],
        price: PriceLookup,
        encounterID: UUID,
        heldRepeatAuthorizationID: UUID?
    ) {
        self.requestID = requestID
        self.identifier = identifier
        self.card = card
        self.resolved = resolved
        self.pokemonPrintRun = pokemonPrintRun
        self.options = options
        self.price = price
        self.encounterID = encounterID
        self.heldRepeatAuthorizationID = heldRepeatAuthorizationID
    }
}

struct ConsecutiveScanIdentity: Equatable, Hashable, Sendable {
    /// `IdentifiedCard.id` intentionally excludes finish and Pokémon print-run
    /// selection. Those are physical variant details, while this key answers
    /// whether the resolved card printing is the same card encounter.
    let canonicalID: String

    init(card: IdentifiedCard) {
        canonicalID = card.id
    }

    init(canonicalID: String) {
        self.canonicalID = canonicalID
    }
}

enum CollectionCandidateRoutingDecision: Equatable {
    case automatic
    case duplicate(SpatialResetProof)
    case suppress
}

/// Pure identity/evidence policy. Persistence and UI ownership stay in the
/// view model, while this rule can be exercised with a fake clock and values in
/// tests without a camera, catalog, or collection store.
enum CollectionCandidateRoutingPolicy {
    static func decision(
        for identity: ConsecutiveScanIdentity,
        previous: CommittedSessionScan?,
        proofs: [SpatialResetProof]
    ) -> CollectionCandidateRoutingDecision {
        guard let previous else { return .automatic }
        guard identity == previous.identity else { return .automatic }

        guard let proof = proofs.first(where: { proof in
            if let presentationToken = proof.presentationToken {
                return presentationToken == previous.presentationToken
            }
            return proof.encounterID == previous.encounterID
        }) else {
            return .suppress
        }
        return .duplicate(proof)
    }
}

/// The held-card offer is allowed to name a committed presentation, but it may
/// not become actionable for an encounter that has not committed yet. This keeps
/// the prompt from racing the identification that makes it meaningful.
struct HeldDuplicatePublicationHistoryEntry: Equatable, Sendable {
    let committed: CommittedSessionScan
    let suppressionKey: ScanSuppressionKey
}

enum HeldDuplicateOfferPublicationDecision: Equatable {
    case deferUntilCommit
    case publish(previous: HeldDuplicatePublicationHistoryEntry)
    case suppress
}

/// Pure publication policy for the latch's nonblocking duplicate affordance.
/// Persistence acknowledgement is represented by an entry for the current
/// encounter; the caller still owns the UI offer and the actual commit.
enum HeldDuplicateOfferPublicationPolicy {
    static func decision(
        for suppressionKey: ScanSuppressionKey,
        encounterID: UUID,
        history: [HeldDuplicatePublicationHistoryEntry]
    ) -> HeldDuplicateOfferPublicationDecision {
        // A same-key historical commit is not enough to make the current
        // encounter actionable. The card that owns this latch signal must have
        // committed first; otherwise the prompt can race its own identification.
        guard let current = history.last(where: { $0.committed.encounterID == encounterID }) else {
            return .deferUntilCommit
        }
        if current.suppressionKey == suppressionKey {
            return .publish(previous: current)
        }
        return .suppress
    }
}

/// Session-only committed history. It is separate from `recent` because recent
/// is a display rail and can be edited or replaced during review.
struct CommittedSessionScan: Identifiable, Equatable, Sendable {
    let id: RecentScan.ID
    let identity: ConsecutiveScanIdentity
    let presentationToken: UUID
    let encounterID: UUID
}

struct HeldDuplicateOffer: Identifiable, Equatable, Sendable {
    let offerID: UUID
    let previousScanID: RecentScan.ID
    let previousPresentationToken: UUID
    let encounterID: UUID
    let identity: ConsecutiveScanIdentity
    let suppressionKey: ScanSuppressionKey
    let cardName: String
    let printedIdentifier: String

    var id: UUID { offerID }
}

private struct HeldRepeatAuthorizationState: Equatable {
    let authorization: HeldRepeatAuthorization
    let offer: HeldDuplicateOffer
    let wasConsumedByEncounter: Bool

    init(
        authorization: HeldRepeatAuthorization,
        offer: HeldDuplicateOffer,
        wasConsumedByEncounter: Bool = false
    ) {
        self.authorization = authorization
        self.offer = offer
        self.wasConsumedByEncounter = wasConsumedByEncounter
    }
}

private struct DeferredHeldDuplicateOffer: Equatable {
    let identifier: ScanIdentifier
    let encounterID: UUID
}

private struct CatalogMissVerification: Equatable {
    let suppressionKey: ScanSuppressionKey
    var window = SuppressionKeyVerificationWindow()
}

struct PendingDuplicateConfirmation: Identifiable, Equatable {
    let promptID: UUID
    let candidate: CollectionCommitCandidate
    let encounterID: UUID
    let matchingSpatialResetProof: SpatialResetProof
    let previousScanID: RecentScan.ID
    let previousPresentationToken: UUID

    var id: UUID { promptID }

    init(
        promptID: UUID = UUID(),
        candidate: CollectionCommitCandidate,
        matchingSpatialResetProof: SpatialResetProof,
        previousScanID: RecentScan.ID,
        previousPresentationToken: UUID
    ) {
        self.promptID = promptID
        self.candidate = candidate
        encounterID = candidate.encounterID
        self.matchingSpatialResetProof = matchingSpatialResetProof
        self.previousScanID = previousScanID
        self.previousPresentationToken = previousPresentationToken
    }

    static func == (lhs: PendingDuplicateConfirmation, rhs: PendingDuplicateConfirmation) -> Bool {
        lhs.promptID == rhs.promptID
    }
}

struct PriceCheckResult: Identifiable {
    let id = UUID()
    let resolvedScan: ResolvedScan
    var quote: PriceLookup
    var checkedAt: Date
    var quoteState: PriceCheckQuoteState = .checking
    /// Presentation state only. The coordinator never starts work by itself so
    /// this flag lets the view model start exactly one refresh for this result.
    var shouldAutoRefresh = true
    var refreshFailed = false
    var isRefreshing = false

    var card: IdentifiedCard { resolvedScan.card }
    var resolved: ResolvedVariant { resolvedScan.resolved }
    var pokemonPrintRun: PokemonPrintRun? { resolvedScan.pokemonPrintRun }

    var hasUsableAmount: Bool {
        guard case let .price(price) = quote else { return false }
        return Money(rounding: price.unitMarketPriceUSD) != nil
    }

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

struct SuppressionKeyVerificationWindow: Equatable, Sendable {
    let matchesRequired: Int
    let windowSize: Int
    private var observations: [ScanSuppressionKey] = []

    init(matchesRequired: Int = 3, windowSize: Int = 5) {
        self.matchesRequired = max(1, matchesRequired)
        self.windowSize = max(windowSize, self.matchesRequired)
    }

    mutating func observe(_ identifier: ScanIdentifier) -> Bool {
        let key = identifier.suppressionKey
        observations.append(key)
        if observations.count > windowSize {
            observations.removeFirst(observations.count - windowSize)
        }

        guard observations.filter({ $0 == key }).count >= matchesRequired else {
            return false
        }
        reset()
        return true
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }
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
    private var mergeKey: ScanSuppressionKey { identifier.suppressionKey }

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

enum ScanCorrectionOutcome: Equatable {
    case saved
    case sourceMissing
    case failed

    var failureMessage: String? {
        switch self {
        case .saved:
            return nil
        case .sourceMissing:
            return "This scan is no longer in your collection"
        case .failed:
            return "Correction could not be saved"
        }
    }
}

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published private(set) var purpose: ScanPurpose = .collection
    @Published private(set) var pendingChoice: PendingVariantChoice?
    @Published private(set) var pendingPrintRunChoice: PendingPrintRunChoice?
    @Published private(set) var pendingIdentityChoice: PendingIdentityChoice?
    @Published private(set) var pendingDuplicateConfirmation: PendingDuplicateConfirmation?
    @Published private(set) var heldDuplicateOffer: HeldDuplicateOffer?
    @Published private(set) var receipt: ScanReceipt?
    @Published private(set) var recent: [RecentScan] = []
    /// Authoritative consecutive-scan history. `recent` is only the visual rail;
    /// duplicate correctness never depends on its ordering or contents.
    private(set) var committedSessionHistory: [CommittedSessionScan] = []
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
    private var fallbackQuoteResolver: PriceFallbackQuoteResolver?
    private var fallbackQuoteTasks: [String: Task<Void, Never>] = [:]
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
    private var activeQuoteRefreshID: UUID?
    private var scanGeneration = 0
    /// Proofs arrive independently of catalog resolution. A provisional proof
    /// is held by encounter id until its successful commit can associate it with
    /// a committed presentation.
    private var spatialResetProofs: [SpatialResetProof] = []
    /// Enough to take back the most recent add, including the question that was
    /// asked at the time so undo can re-ask it.
    private var lastAdd: RecentScan?
    private var heldRepeatAuthorizationState: HeldRepeatAuthorizationState?
    private var deferredHeldDuplicateOffer: DeferredHeldDuplicateOffer?
    private var catalogMissVerification: CatalogMissVerification?
#if DEBUG
    private var diagnosticEvents: [String] = []
#endif

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
            Task { @MainActor in
                guard self.catalogMissVerification?.suppressionKey != identifier.suppressionKey else {
                    return
                }
                await self.catalog.prefetch(identifier)
            }
        }

        scanner.onObservedCandidate = { [weak self] identifier in
            Task { @MainActor in
                self?.observeCatalogMissVerification(identifier)
            }
        }

        scanner.onConfirmedCandidate = { [weak self] encounterID, identifier, authorizationID in
            guard let self else { return }
            Task { @MainActor in
                if let state = self.heldRepeatAuthorizationState,
                   authorizationID == Optional(state.authorization.id) {
                    // The scanner has consumed the one-shot permit. Keep its
                    // identity attached through print-run/finish resolution;
                    // the scanner-owned deadline has already been detached.
                    self.heldRepeatAuthorizationState = HeldRepeatAuthorizationState(
                        authorization: state.authorization,
                        offer: state.offer,
                        wasConsumedByEncounter: true
                    )
                } else if self.heldRepeatAuthorizationState != nil {
                    // Another confirmed card dismisses the old offer and any
                    // still-pending tap. The scanner has already cancelled its
                    // permit before emitting this encounter.
                    self.clearHeldRepeatState()
                }
                if let offer = self.heldDuplicateOffer,
                   offer.encounterID != encounterID ||
                   offer.suppressionKey != identifier.suppressionKey {
                    self.heldDuplicateOffer = nil
                    self.diagnostic("heldDuplicateOfferDismissedByDifferentCard")
                }
                if let deferred = self.deferredHeldDuplicateOffer,
                   deferred.encounterID != encounterID {
                    self.deferredHeldDuplicateOffer = nil
                }
                if let verification = self.catalogMissVerification,
                   verification.suppressionKey != identifier.suppressionKey {
                    self.catalogMissVerification = nil
                }
                self.enqueueIdentification(
                    identifier,
                    encounterID: encounterID,
                    heldRepeatAuthorizationID: authorizationID
                )
            }
        }

        scanner.onHeldRepeatAuthorizationTerminated = { [weak self] authorizationID, outcome in
            Task { @MainActor in
                guard let self,
                      self.heldRepeatAuthorizationState?.authorization.id == authorizationID else { return }
                switch outcome {
                case .consumed:
                    guard let state = self.heldRepeatAuthorizationState else { return }
                    self.heldRepeatAuthorizationState = HeldRepeatAuthorizationState(
                        authorization: state.authorization,
                        offer: state.offer,
                        wasConsumedByEncounter: true
                    )
                case .expired, .rejected, .cancelled:
                    self.heldRepeatAuthorizationState = nil
                    self.heldDuplicateOffer = nil
                }
            }
        }

        scanner.onSpatialResetProof = { [weak self] proof in
            Task { @MainActor in
                self?.receiveSpatialResetProof(proof)
            }
        }

        scanner.onCameraInterruption = { [weak self] in
            Task { @MainActor in
                self?.cameraInterruptionStarted()
            }
        }
        scanner.onCameraInterruptionEnded = { [weak self] in
            Task { @MainActor in
                self?.resumeRecognitionIfPossible()
            }
        }

        scanner.onLatchHolding = { [weak self] identifier, encounterID in
            Task { @MainActor in
                self?.offerHeldDuplicate(for: identifier, encounterID: encounterID)
            }
        }

        scanner.onLatchReleased = { [weak self] encounterID, suppressionKey in
            Task { @MainActor in
                guard let self else { return }
                if let offer = self.heldDuplicateOffer,
                   offer.suppressionKey == suppressionKey,
                   encounterID == nil || offer.encounterID == encounterID {
                    self.heldDuplicateOffer = nil
                }
                if let deferred = self.deferredHeldDuplicateOffer,
                   deferred.identifier.suppressionKey == suppressionKey,
                   encounterID == nil || deferred.encounterID == encounterID {
                    self.deferredHeldDuplicateOffer = nil
                }
                if self.catalogMissVerification?.suppressionKey == suppressionKey {
                    self.catalogMissVerification = nil
                }
            }
        }
    }

    // MARK: - Session lifecycle

    func start(context: ModelContext) {
        store = CollectionStore(context: context)
        prices = PriceStore(context: context)
        priceCheckCoordinator = PriceCheckCoordinator(context: context)
        fallbackQuoteResolver = PriceFallbackQuoteResolver(context: context)
        feedback.prepare()
        // Decode the merged Pokémon checklist and resolved-card cache before
        // the first confirmed frame needs either one.
        Task { await catalog.prewarm() }
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
        scanner.stop()
    }

    func scenePhaseChanged(isActive: Bool) {
        guard !isActive else { return }
        invalidatePendingScan()
    }

    private func cameraInterruptionStarted() {
        invalidatePendingScan()
        show(ScanNote(text: "Camera interrupted — scan again when it returns", tone: .info))
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
        cancelPriceCheckRefresh()
        priceCheckResult = nil
        feedback.prepare()
        resumeRecognitionIfPossible()
    }

    // MARK: - Controls

    func setPurpose(_ newPurpose: ScanPurpose) {
        guard newPurpose != purpose else { return }

        invalidatePendingScan()
        purpose = newPurpose
        resumeRecognitionIfPossible()
        feedback.choiceMade()
        UIAccessibility.post(notification: .announcement, argument: "\(newPurpose.title). \(newPurpose.statusText)")
    }

    private func invalidatePendingScan() {
        // Cancellation is an invalidation boundary, not a reinterpretation.
        // Existing completions are allowed to finish their network work but can
        // no longer affect any UI or destination.
        scanGeneration += 1
        cancelPriceCheckRefresh()
        identificationTask?.cancel()
        activeIdentificationRequestID = nil
        isProcessingIdentification = false
        resolutionTask?.cancel()
        identificationQueue.removeAll()
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        pendingDuplicateConfirmation = nil
        spatialResetProofs.removeAll()
        deferredHeldDuplicateOffer = nil
        catalogMissVerification = nil
        clearHeldRepeatState()
        receiptTask?.cancel()
        receipt = nil
        noteTask?.cancel()
        note = nil
        scanner.invalidateSpatialContinuity()
        scanner.pauseRecognition()
    }

    private func receiveSpatialResetProof(_ proof: SpatialResetProof) {
        guard !spatialResetProofs.contains(where: { $0.id == proof.id }) else { return }

        // Spatial proof is the stronger, one-shot duplicate path. A held-card
        // offer cannot remain actionable once that proof takes over. Keep an
        // already-tapped authorization alive: the proof may have been queued
        // by the old tracker just before the tap, or may belong to the newly
        // authorized encounter while catalog choices are still pending.
        heldDuplicateOffer = nil

        // A tracker can exit while its catalog resolution is still in flight.
        // Once that resolution has committed, attach the already-observed proof
        // to the new presentation token instead of losing the evidence at the
        // generation boundary.
        if proof.presentationToken == nil,
           let committed = committedSessionHistory.first(where: {
               $0.encounterID == proof.encounterID
           }) {
            spatialResetProofs.append(
                SpatialResetProof(
                    id: proof.id,
                    encounterID: proof.encounterID,
                    presentationToken: committed.presentationToken
                )
            )
        } else {
            spatialResetProofs.append(proof)
        }
    }

    /// Turns the latch's one-time held signal into a nonblocking offer only
    /// after the current encounter is acknowledged and the identification
    /// pipeline is idle. An older same-key presentation is never enough on its
    /// own because it could belong to an encounter still being resolved.
    /// The offer is a UI affordance; it does not itself change scanner state or
    /// collection quantity.
    private func offerHeldDuplicate(for identifier: ScanIdentifier, encounterID: UUID?) {
        guard purpose == .collection,
              heldDuplicateOffer == nil,
              heldRepeatAuthorizationState == nil,
              pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil,
              let encounterID else { return }

        let history = committedSessionHistory.compactMap { committed -> HeldDuplicatePublicationHistoryEntry? in
            guard let scan = recent.first(where: { $0.id == committed.id }) else { return nil }
            return HeldDuplicatePublicationHistoryEntry(
                committed: committed,
                suppressionKey: scan.identifier.suppressionKey
            )
        }

        switch HeldDuplicateOfferPublicationPolicy.decision(
            for: identifier.suppressionKey,
            encounterID: encounterID,
            history: history
        ) {
        case .deferUntilCommit:
            // The latch can announce while its newly confirmed encounter is
            // still resolving. Hold the signal until the same encounter has a
            // successful persistence acknowledgment; an offer for an
            // uncommitted card is not actionable.
            deferredHeldDuplicateOffer = DeferredHeldDuplicateOffer(
                identifier: identifier,
                encounterID: encounterID
            )
        case .suppress:
            return
        case .publish(let selected):
            guard let previousScan = recent.first(where: { $0.id == selected.committed.id }),
                  previousScan.identifier.suppressionKey == identifier.suppressionKey else {
                return
            }
            publishHeldDuplicateOffer(
                for: identifier,
                encounterID: encounterID,
                previous: selected.committed,
                previousScan: previousScan
            )
        }
    }

    private func publishHeldDuplicateOffer(
        for identifier: ScanIdentifier,
        encounterID: UUID,
        previous: CommittedSessionScan,
        previousScan: RecentScan
    ) {
        guard heldDuplicateOffer == nil,
              heldRepeatAuthorizationState == nil,
              pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil,
              identificationQueue.isEmpty,
              !isProcessingIdentification else { return }

        heldDuplicateOffer = HeldDuplicateOffer(
            offerID: UUID(),
            previousScanID: previous.id,
            previousPresentationToken: previous.presentationToken,
            encounterID: encounterID,
            identity: previous.identity,
            suppressionKey: identifier.suppressionKey,
            cardName: previousScan.card.name,
            printedIdentifier: previousScan.identifier.scannerDisplayIdentifier(for: previousScan.card)
        )
        diagnostic("heldDuplicateOfferPublished")
    }

    private func clearHeldRepeatState() {
        heldRepeatAuthorizationState = nil
        heldDuplicateOffer = nil
        scanner.cancelHeldRepeatAuthorization()
    }

    /// The safe answer to the duplicate question. It never mutates the
    /// collection, and it only rebinds the candidate tracker if that tracker is
    /// still continuous at the moment the answer is made.
    func chooseSameCard() {
        guard let pending = pendingDuplicateConfirmation else { return }
        pendingDuplicateConfirmation = nil
        spatialResetProofs.removeAll { $0.encounterID == pending.encounterID }

        guard let previous = committedSessionHistory.last,
              previous.id == pending.previousScanID,
              previous.presentationToken == pending.previousPresentationToken else {
            scanner.keepPresentationSuppressed(encounterID: pending.encounterID)
            resumeRecognitionIfPossible()
            processNextIdentificationIfPossible()
            return
        }

        scanner.rebindProvisionalPresentation(
            encounterID: pending.encounterID,
            presentationToken: previous.presentationToken
        )
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    /// Takes the pending value before writing, so repeated taps can observe it
    /// only once. This calls the authorized path directly and therefore cannot
    /// be intercepted by duplicate routing a second time.
    func addAnother() {
        guard let pending = pendingDuplicateConfirmation else { return }
        pendingDuplicateConfirmation = nil

        guard commitAuthorizedCollectionCandidate(
            pending.candidate,
            authorization: .addAnother
        ) else {
            pendingDuplicateConfirmation = pending
            scanner.pauseRecognition()
            return
        }

        // A different card commit is the boundary at which any unrelated
        // outstanding proof is no longer useful. The candidate's own proof is
        // carried by its tracker and may arrive after the commit.
        spatialResetProofs.removeAll { $0.encounterID != pending.encounterID }
    }

    /// Creates one short-lived, scanner-verified permit for the card that is
    /// still held. The offer is hidden immediately so a second tap cannot make
    /// another permit while the first verification is in flight.
    func addAnotherHeldCopy() {
        guard purpose == .collection,
              let offer = heldDuplicateOffer,
              heldRepeatAuthorizationState == nil,
              pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil else { return }

        let authorization = HeldRepeatAuthorization(
            expectedSuppressionKey: offer.suppressionKey,
            expiresAt: CFAbsoluteTimeGetCurrent() + 2.0
        )
        heldRepeatAuthorizationState = HeldRepeatAuthorizationState(
            authorization: authorization,
            offer: offer
        )
        heldDuplicateOffer = nil
        diagnostic("heldRepeatTapCreated")

        scanner.authorizeHeldRepeat(authorization) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.heldRepeatAuthorizationState?.authorization.id == authorization.id else { return }
                switch result {
                case .accepted:
                    self.diagnostic("heldRepeatAuthorizationAccepted")
                case .rejected(.expired), .rejected(.recognitionPaused):
                    self.heldRepeatAuthorizationState = nil
                    self.heldDuplicateOffer = offer
                    self.show(ScanNote(text: "Card changed — try again", tone: .info))
                    self.feedback.problem()
                case .rejected(.cardChanged):
                    self.heldRepeatAuthorizationState = nil
                    self.heldDuplicateOffer = offer
                    self.show(ScanNote(text: "Card changed — try again", tone: .info))
                    self.feedback.problem()
                }
            }
        }
    }

    /// Explicitly ends the scanner session. The app-level view model normally
    /// owns this history for its lifetime; this method is the only deliberate
    /// reset boundary.
    func endSession() {
        invalidatePendingScan()
        committedSessionHistory.removeAll()
        recent.removeAll()
        unresolvedScans.removeAll()
        lastAdd = nil
        scanner.stop()
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
        // Cleared here, the way every sibling `choose` clears its own pending
        // state, rather than left for `route` to clear on its way past.
        //
        // Routing has eight terminal outcomes and only three of them used to
        // clear this: an automatic commit that succeeded, the spatial-duplicate
        // prompt, and Price Check. The other five — a suppressed re-scan, a
        // commit that threw, and the three held-repeat rejections — left the
        // finish bar on screen showing a question the user had already
        // answered, with recognition still paused and the identification queue
        // stalled behind the `pendingChoice == nil` guard in
        // `processNextIdentificationIfPossible`. The answer has been consumed
        // by the time we route, so this is where it stops being pending.
        pendingChoice = nil
        route(
            ResolvedScan(
                request: pending.request,
                card: pending.card,
                resolved: ResolvedVariant(variant: variant, resolution: .userConfirmed),
                pokemonPrintRun: pending.pokemonPrintRun,
                options: pending.options
            )
        )
        // No-ops if routing raised a new question of its own — the duplicate
        // prompt, or a Price Check sheet. See `resumeRecognitionIfPossible`.
        resumeRecognitionIfPossible()
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

    /// One guarded undo path for the receipt, rail, and review sheet. The
    /// stable scan ID is resolved at tap time, so a corrected scan cannot undo
    /// an older value still held by a view.
    @discardableResult
    func undoScan(scanID: RecentScan.ID) -> Bool {
        guard let store else { return false }
        guard let scan = recent.first(where: { $0.id == scanID }) else {
            show(ScanNote(text: "Undo could not find that scan", tone: .problem))
            feedback.problem()
            return false
        }
        let removedHistoryEntry = committedSessionHistory.first { $0.id == scanID }

        do {
            try store.undo(scan.mutation)
        } catch {
            // Keep the receipt/review state intact so the person can retry after
            // a transient save or synchronization failure.
            show(ScanNote(text: "Undo could not be saved", tone: .problem))
            feedback.problem()
            return false
        }

        recent.removeAll { $0.id == scanID }
        removeCommittedHistory(for: scanID)
        spatialResetProofs.removeAll { $0.encounterID == removedHistoryEntry?.encounterID }

        if heldDuplicateOffer?.previousScanID == scanID ||
            heldRepeatAuthorizationState?.offer.previousScanID == scanID {
            clearHeldRepeatState()
        }
        if pendingDuplicateConfirmation?.previousScanID == scanID {
            pendingDuplicateConfirmation = nil
        }
        if lastAdd?.id == scanID {
            lastAdd = nil
        }
        if receipt?.scanID == scanID {
            receipt = nil
            receiptTask?.cancel()
        }
        if let removedHistoryEntry {
            scanner.restoreAcceptedPresentation(presentationToken: removedHistoryEntry.presentationToken)
        }
        feedback.undone()
        resumeRecognitionIfPossible()
        return true
    }

    func undoLastAdd() {
        guard let scanID = receipt?.scanID ?? lastAdd?.id else { return }
        undoScan(scanID: scanID)
    }

    func deleteRecentScan(_ scan: RecentScan) {
        undoScan(scanID: scan.id)
    }

    private func removeCommittedHistory(for scanID: RecentScan.ID) {
        committedSessionHistory.removeAll { $0.id == scanID }
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
    @discardableResult
    func correct(scanID: RecentScan.ID, to variant: PhysicalVariant) -> ScanCorrectionOutcome {
        guard let store else {
            show(ScanNote(text: "Correction could not be saved", tone: .problem))
            feedback.problem()
            return .failed
        }
        guard let scan = recent.first(where: { $0.id == scanID }),
              scan.resolved.variant != variant else { return .failed }

        let corrected = ResolvedVariant(variant: variant, resolution: .userConfirmed)
        let mutation: CollectionMutation?
        do {
            mutation = try store.recordVariantCorrection(
                for: scan.card,
                from: scan.resolved.variant,
                to: corrected,
                pokemonPrintRun: scan.pokemonPrintRun,
                previousCollectionKey: scan.mutation.collectionKey,
                previousLedgerOperationIDs: scan.mutation.ledgerOperationIDs,
                activityID: scan.mutation.activityID,
                quantity: 1
            )
        } catch {
            show(ScanNote(text: "Correction could not be saved", tone: .problem))
            feedback.problem()
            return .failed
        }
        guard let mutation else {
            show(ScanNote(text: "This scan is no longer in your collection", tone: .problem))
            feedback.problem()
            return .sourceMissing
        }

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
        let correctedLookup = CardPricing.price(
            for: scan.card,
            variant: variant,
            pokemonPrintRun: scan.pokemonPrintRun
        )
        recordPrice(
            for: scan.card,
            variant: variant,
            pokemonPrintRun: scan.pokemonPrintRun,
            lookup: correctedLookup
        )
        queueFallbackPrice(
            for: scan.card,
            variant: variant,
            pokemonPrintRun: scan.pokemonPrintRun,
            catalogLookup: correctedLookup
        )
        feedback.choiceMade()
        return .saved
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
        lookup: PriceLookup? = nil,
        savingImmediately: Bool = true
    ) {
        guard let prices else { return }
        prices.store(
            lookup ?? CardPricing.price(
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

    private func enqueueIdentification(
        _ identifier: ScanIdentifier,
        encounterID: UUID,
        heldRepeatAuthorizationID: UUID? = nil
    ) {
        let encounter = ScanEncounter(
            encounterID: encounterID,
            identifier: identifier,
            generation: scanGeneration,
            heldRepeatAuthorizationID: heldRepeatAuthorizationID
        )
        let request = ScanRequest(
            identifier: encounter.identifier,
            purpose: purpose,
            generation: encounter.generation,
            encounterID: encounter.encounterID,
            heldRepeatAuthorizationID: encounter.heldRepeatAuthorizationID
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
              pendingDuplicateConfirmation == nil,
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
            self.drainDeferredHeldDuplicateOfferIfPossible()
            self.processNextIdentificationIfPossible()
        }
    }

    private func identify(_ request: ScanRequest) async {
        beginIdentification()
        defer { endIdentification() }

        do {
            let card = try await catalog.card(for: request.identifier)
            guard !Task.isCancelled, isCurrent(request) else { return }
            if catalogMissVerification?.suppressionKey == request.identifier.suppressionKey {
                catalogMissVerification = nil
            }
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
            routeCollectionCandidate(CollectionCommitCandidate(resolvedScan: resolvedScan))
        case .priceCheck:
            presentPriceCheck(resolvedScan)
        }
    }

    /// A successful collection add is the only operation that appends session
    /// history. The display rail is updated from that same mutation, but is not
    /// consulted for duplicate correctness.
    private func appendCommittedScan(
        _ candidate: CollectionCommitCandidate,
        mutation: CollectionMutation
    ) {
        let scan = RecentScan(
            identifier: candidate.identifier,
            card: candidate.card,
            resolved: candidate.resolved,
            pokemonPrintRun: candidate.pokemonPrintRun,
            options: candidate.options,
            mutation: mutation
        )
        let committed = CommittedSessionScan(
            id: scan.id,
            identity: candidate.identity,
            presentationToken: UUID(),
            encounterID: candidate.encounterID
        )

        // Both are projections of the same successful store mutation.
        recent.insert(scan, at: 0)
        committedSessionHistory.append(committed)

        // A provisional tracker may have exited while the catalog request was
        // still pending. Keep that positive evidence, but rebind it to the
        // committed presentation token created by this successful mutation.
        let candidateProofs = spatialResetProofs.filter {
            $0.encounterID == candidate.encounterID
        }
        if candidate.heldRepeatAuthorizationID != nil {
            // A successful held-repeat commit establishes a new encounter. Any
            // proof belonging to an older presentation is no longer relevant
            // to the newly committed copy.
            spatialResetProofs.removeAll { $0.encounterID != candidate.encounterID }
        } else {
            spatialResetProofs.removeAll { $0.encounterID == candidate.encounterID }
        }
        spatialResetProofs.append(contentsOf: candidateProofs.map { proof in
            SpatialResetProof(
                id: proof.id,
                encounterID: proof.encounterID,
                presentationToken: proof.presentationToken ?? committed.presentationToken
            )
        })
        lastAdd = scan
        scanner.acceptedPresentation(
            encounterID: candidate.encounterID,
            presentationToken: committed.presentationToken
        )
        successCount += 1

        // The append is the persistence acknowledgement. The actual offer is
        // drained once the identification state also becomes idle; an automatic
        // commit reaches this method while `isProcessingIdentification` is still
        // true, and the publication guard must remain effective there too.
        drainDeferredHeldDuplicateOfferIfPossible()

        showReceipt(
            ScanReceipt(
                scanID: scan.id,
                name: candidate.card.name,
                identifier: candidate.identifier.scannerDisplayIdentifier(for: candidate.card),
                variantLabel: [candidate.pokemonPrintRun?.label, candidate.resolved.label]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                thumbnailURL: scan.thumbnailURL
            )
        )
        feedback.added()
    }

    private func drainDeferredHeldDuplicateOfferIfPossible() {
        guard identificationQueue.isEmpty,
              !isProcessingIdentification,
              pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil,
              let deferred = deferredHeldDuplicateOffer,
              let committed = committedSessionHistory.last(where: {
                  $0.encounterID == deferred.encounterID
              }),
              let scan = recent.first(where: { $0.id == committed.id }),
              scan.identifier.suppressionKey == deferred.identifier.suppressionKey else {
            return
        }

        deferredHeldDuplicateOffer = nil
        publishHeldDuplicateOffer(
            for: deferred.identifier,
            encounterID: deferred.encounterID,
            previous: committed,
            previousScan: scan
        )
    }

    enum CollectionCommitAuthorization {
        case automatic
        case addAnother
        case heldRepeat
    }

    /// Collection routing is identity-first. A matching identity can reach a
    /// prompt only with a one-shot proof tied to the previous presentation.
    /// No proof means suppression, never a reseed or collection mutation.
    private func routeCollectionCandidate(_ candidate: CollectionCommitCandidate) {
        if let authorizationID = candidate.heldRepeatAuthorizationID {
            routeHeldRepeatCandidate(candidate, authorizationID: authorizationID)
            return
        }

        let decision = CollectionCandidateRoutingPolicy.decision(
            for: candidate.identity,
            previous: committedSessionHistory.last,
            proofs: spatialResetProofs
        )

        switch decision {
        case .automatic:
            diagnostic("routingAutomatic")
            guard commitAuthorizedCollectionCandidate(candidate, authorization: .automatic) else { return }
            // A candidate may have exited before its successful commit. Keep
            // only that candidate's proof and discard evidence belonging to
            // older or unrelated presentations.
            spatialResetProofs.removeAll { $0.encounterID != candidate.encounterID }
        case .suppress:
            diagnostic("routingSuppressed")
            deferredHeldDuplicateOffer = nil
            scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
            spatialResetProofs.removeAll()
        case .duplicate(let proof):
            diagnostic("routingSpatialDuplicatePrompt")
            guard let previous = committedSessionHistory.last,
                  let proofIndex = spatialResetProofs.firstIndex(where: { $0.id == proof.id }) else {
                scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
                return
            }

            // Proofs are one-shot. The detached candidate owns the proof while
            // the user decides, independent of any generation-owned task.
            let proof = spatialResetProofs.remove(at: proofIndex)
            pendingChoice = nil
            pendingPrintRunChoice = nil
            pendingIdentityChoice = nil
            pendingDuplicateConfirmation = PendingDuplicateConfirmation(
                candidate: candidate,
                matchingSpatialResetProof: proof,
                previousScanID: previous.id,
                previousPresentationToken: previous.presentationToken
            )
            invalidateResolutionForDuplicatePrompt()
            scanner.pauseRecognition()
            feedback.needsChoice()
        }
    }

    /// Held-repeat candidates bypass duplicate interception only after the
    /// detached authorization is matched to the exact previous committed
    /// presentation and the resolved canonical identity. This deliberately
    /// resolves by stable scan ID rather than `committedSessionHistory.last`:
    /// the detached permit owns its original presentation, while foreign
    /// confirmations still terminate the permit before this guard can authorize
    /// anything.
    private func routeHeldRepeatCandidate(
        _ candidate: CollectionCommitCandidate,
        authorizationID: UUID
    ) {
        guard let state = heldRepeatAuthorizationState,
              state.authorization.id == authorizationID,
              state.wasConsumedByEncounter,
              candidate.identifier.suppressionKey == state.offer.suppressionKey,
              let previous = committedSessionHistory.first(where: {
                  $0.id == state.offer.previousScanID
              }),
              previous.presentationToken == state.offer.previousPresentationToken else {
            clearHeldRepeatState()
            scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
            diagnostic("routingHeldRepeatRejected")
            return
        }

        guard candidate.identity == state.offer.identity else {
            // The user's permit was for a different resolved card. It cannot
            // authorize this candidate, but this candidate still follows the
            // ordinary identity-first rules.
            clearHeldRepeatState()
            scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
            diagnostic("routingHeldRepeatIdentityMismatch")
            return
        }

        heldRepeatAuthorizationState = nil
        heldDuplicateOffer = nil

        guard commitAuthorizedCollectionCandidate(candidate, authorization: .heldRepeat) else {
            // The consumed permit is never restored. Publish a fresh offer and
            // make the next tap create a new scanner-owned authorization.
            heldDuplicateOffer = state.offer
            scanner.restoreHeldRepeatAfterFailure()
            diagnostic("routingHeldRepeatSaveFailed")
            return
        }
        diagnostic("routingHeldRepeatCommitted")
    }

    /// Takes a detached pending value before persistence starts. The caller for
    /// Add another therefore cannot re-enter duplicate interception, including
    /// on a double tap.
    private func commitAuthorizedCollectionCandidate(
        _ candidate: CollectionCommitCandidate,
        authorization: CollectionCommitAuthorization
    ) -> Bool {
        guard let store else { return false }

        // Pricing is secondary mutable metadata and must never be in the way of
        // "card added". Nothing here touches the network: the price rides along
        // in the catalog response the identification already made, and a card
        // whose response carried none simply waits for the next price refresh.
        //
        // Staged before the add rather than after it so the add's own save is
        // the only save this tap performs. Both stores hold the same context,
        // and nothing in the add reads a price record, so the order is free.
        recordPrice(
            for: candidate.card,
            variant: candidate.resolved.variant,
            pokemonPrintRun: candidate.pokemonPrintRun,
            lookup: candidate.price,
            savingImmediately: false
        )

        guard let mutation = try? store.add(
            candidate.card,
            resolved: candidate.resolved,
            source: .scan,
            pokemonPrintRun: candidate.pokemonPrintRun,
            matchCatalogAliases: candidate.pokemonPrintRun != nil
        ) else {
            show(ScanNote(text: "Card could not be saved", tone: .problem))
            feedback.problem()
            return false
        }

        // A catalog outage can leave a newly identified card with no usable
        // USD quote. The card is already safely saved; resolve its price in the
        // background through the same fallback path used by Price Check.
        queueFallbackPrice(
            for: candidate.card,
            variant: candidate.resolved.variant,
            pokemonPrintRun: candidate.pokemonPrintRun,
            catalogLookup: candidate.price
        )

        if pendingChoice?.request.id == candidate.requestID {
            pendingChoice = nil
        }
        appendCommittedScan(candidate, mutation: mutation)
        resumeRecognitionIfPossible()
        diagnostic("collectionCommit")
        return true
    }

    /// Price metadata is secondary to a successful collection mutation. This
    /// keeps the scanner responsive while still giving a newly added card a
    /// JustTCG quote as soon as the catalog provider is unavailable.
    private func queueFallbackPrice(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?,
        catalogLookup: PriceLookup
    ) {
        guard PriceFallbackQuoteResolver.needsFallback(catalogLookup),
              let prices,
              let resolver = fallbackQuoteResolver,
              PriceVendorCredentials.hasKey else { return }

        let printingID = pokemonPrintRun.map { "\(card.providerID)@\($0.rawValue)" }
            ?? card.providerID
        let key = PriceRecord.key(
            game: card.game,
            printingID: printingID,
            variantID: variant?.id
        )
        guard fallbackQuoteTasks[key] == nil else { return }

        let task = Task { @MainActor [weak self] in
            defer { self?.fallbackQuoteTasks[key] = nil }
            guard !Task.isCancelled else { return }

            switch await resolver.resolve(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            ) {
            case let .lookup(quote):
                guard !Task.isCancelled else { return }
                let identityKey = ProductIdentity.key(
                    game: card.game,
                    printingID: printingID,
                    variantID: variant?.id
                )
                let marketVariantID = ProductIdentityStore(context: prices.context)
                    .cachedVariantID(forKey: identityKey)
                prices.store(
                    quote,
                    game: card.game,
                    printingID: printingID,
                    variantID: variant?.id,
                    marketVariantID: marketVariantID
                )
                prices.save()
            case .failed:
                break
            }
        }
        fallbackQuoteTasks[key] = task
    }

    private func invalidateResolutionForDuplicatePrompt() {
        scanGeneration += 1
        identificationTask?.cancel()
        activeIdentificationRequestID = nil
        isProcessingIdentification = false
        resolutionTask?.cancel()
        identificationQueue.removeAll()
    }

    /// The Price Check coordinator intentionally has no `CollectionStore`.
    private func presentPriceCheck(_ resolvedScan: ResolvedScan) {
        guard let priceCheckCoordinator, isCurrent(resolvedScan.request) else { return }
        cancelPriceCheckRefresh()
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        scanner.pauseRecognition()
        let result = priceCheckCoordinator.present(resolvedScan)
        priceCheckResult = result
        if result.shouldAutoRefresh {
            refreshPriceCheckQuote()
        }
    }

    func refreshPriceCheckQuote() {
        guard var result = priceCheckResult, !result.isRefreshing else { return }
        result.isRefreshing = true
        result.shouldAutoRefresh = false
        result.quoteState = .checking
        result.refreshFailed = false
        priceCheckResult = result
        let resultID = result.id
        let refreshID = UUID()
        activeQuoteRefreshID = refreshID

        quoteRefreshTask?.cancel()
        quoteRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.activeQuoteRefreshID == refreshID {
                    self.quoteRefreshTask = nil
                }
            }
            guard let priceCheckCoordinator = self.priceCheckCoordinator else {
                guard self.activeQuoteRefreshID == refreshID,
                      var latest = self.priceCheckResult,
                      latest.id == resultID else { return }
                latest.isRefreshing = false
                latest.refreshFailed = true
                latest.quoteState = latest.hasUsableAmount
                    ? .lastKnown(.providerUnavailable)
                    : .providerUnavailable
                self.priceCheckResult = latest
                return
            }
            switch await priceCheckCoordinator.refresh(result) {
            case let .quote(refreshed):
                guard !Task.isCancelled,
                      self.activeQuoteRefreshID == refreshID,
                      var latest = self.priceCheckResult,
                      latest.id == resultID else { return }
                latest.quote = refreshed
                latest.checkedAt = .now
                latest.isRefreshing = false
                latest.refreshFailed = false
                latest.quoteState = .current
                self.priceCheckResult = latest
            case let .failed(issue):
                guard !Task.isCancelled,
                      self.activeQuoteRefreshID == refreshID,
                      var latest = self.priceCheckResult,
                      latest.id == resultID else { return }
                priceCheckCoordinator.recordRefreshFailure(for: latest)
                latest.checkedAt = .now
                latest.isRefreshing = false
                latest.refreshFailed = true
                latest.quoteState = latest.hasUsableAmount
                    ? .lastKnown(issue)
                    : Self.quoteState(for: issue)
                self.priceCheckResult = latest
            case .cancelled:
                guard !Task.isCancelled,
                      self.activeQuoteRefreshID == refreshID,
                      var latest = self.priceCheckResult,
                      latest.id == resultID else { return }
                latest.isRefreshing = false
                latest.refreshFailed = false
                latest.quoteState = latest.hasUsableAmount ? .current : .checking
                self.priceCheckResult = latest
            }
        }
    }

    private func cancelPriceCheckRefresh() {
        quoteRefreshTask?.cancel()
        quoteRefreshTask = nil
        activeQuoteRefreshID = nil
        guard var result = priceCheckResult, result.isRefreshing else { return }
        result.isRefreshing = false
        result.refreshFailed = false
        result.quoteState = result.hasUsableAmount ? .current : .checking
        priceCheckResult = result
    }

    private static func quoteState(for issue: PriceCheckRefreshIssue) -> PriceCheckQuoteState {
        switch issue {
        case .noExactPrice: return .noExactPrice
        case .providerUnavailable: return .providerUnavailable
        case .fallbackDisabled: return .fallbackDisabled
        case .fallbackUnconfigured: return .fallbackUnconfigured
        case let .rateLimited(retryAt): return .rateLimited(retryAt: retryAt)
        case let .budgetLimited(resetAt): return .budgetLimited(resetAt: resetAt)
        }
    }

    /// Settings and review sheets may be opened while a finish question is
    /// pending. Dismissing either sheet must not restart OCR behind that question.
    private func resumeRecognitionIfPossible() {
        guard priceCheckResult == nil else { return }
        guard pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil else { return }
        scanner.resumeRecognition()
    }

    private func isCurrent(_ request: ScanRequest) -> Bool {
        request.generation == scanGeneration
    }

    private func observeCatalogMissVerification(_ identifier: ScanIdentifier) {
        guard var verification = catalogMissVerification,
              verification.suppressionKey == identifier.suppressionKey else { return }

        guard !verification.window.observe(identifier) else {
            catalogMissVerification = nil
            unresolvedScans = UnresolvedScan.merging(unresolvedScans, with: identifier)
            show(
                ScanNote(
                    text: "Still can't confirm \(identifier.displayIdentifier) — set it aside",
                    tone: .problem
                )
            )
            return
        }
        catalogMissVerification = verification
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
            // The first deterministic miss is not enough to file a card: a
            // transient OCR/catalog boundary can still have produced the same
            // resolved identifier. The latch remains engaged while a fresh
            // three-of-five suppression-key window verifies the physical card.
            if catalogMissVerification?.suppressionKey != identifier.suppressionKey {
                catalogMissVerification = CatalogMissVerification(
                    suppressionKey: identifier.suppressionKey
                )
            }
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

    private func diagnostic(_ event: String) {
#if DEBUG
        diagnosticEvents.append(event)
        if diagnosticEvents.count > 64 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 64)
        }
#endif
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
