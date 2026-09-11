import Combine
import Foundation
import OSLog
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

enum ScanPurpose: String, CaseIterable, Identifiable, Hashable, Sendable {
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

/// Recognition may run only while the scanner is actually visible and the
/// app can present its result. Keeping these conditions together prevents a
/// lifecycle callback from restarting OCR behind a sheet or while another tab
/// owns the foreground.
struct ScannerRecognitionEligibility: Equatable {
    var isSceneActive = true
    var isScannerVisible = false
    var isBlockedByPresentation = false
    var isCameraInterrupted = false

    var allowsRecognition: Bool {
        isSceneActive &&
        isScannerVisible &&
        !isBlockedByPresentation &&
        !isCameraInterrupted
    }
}

/// Lifecycle identity captured by `CardScanner` on the same serial queue as
/// the confirmation frame. A late callback must match every field before it
/// can enter the current scanner session.
struct ScannerConfirmationToken: Equatable, Sendable {
    let sessionID: UUID
    let generation: Int
    let purpose: ScanPurpose
    let visibilityEpoch: UUID
}

/// A scanner-domain encounter. Its id is created by `CardScanner` at the exact
/// frame that produced a confirmed OCR observation; generation is only for
/// invalidating asynchronous identification work.
struct ScanEncounter: Identifiable, Equatable, Sendable {
    let encounterID: UUID
    let subject: ScanSubject
    let generation: Int
    let heldRepeatAuthorizationID: UUID?

    var id: UUID { encounterID }
    var identifier: ScanIdentifier { subject.identifier }
}

/// Immutable intent attached at confirmation time. A completion may route only
/// according to this captured value, never according to the picker later shown.
struct ScanRequest: Identifiable, Equatable {
    let id: UUID
    let subject: ScanSubject
    let purpose: ScanPurpose
    let generation: Int
    let encounterID: UUID
    let heldRepeatAuthorizationID: UUID?

    var identifier: ScanIdentifier { subject.identifier }

    init(
        id: UUID = UUID(),
        subject: ScanSubject,
        purpose: ScanPurpose,
        generation: Int,
        encounterID: UUID = UUID(),
        heldRepeatAuthorizationID: UUID? = nil
    ) {
        self.id = id
        self.subject = subject
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
    let catalogRetrievedAt: Date
    var gradedOutcome: ScannedGradedOutcome?

    init(
        request: ScanRequest,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun?,
        options: [PhysicalVariant],
        catalogRetrievedAt: Date = .now,
        gradedOutcome: ScannedGradedOutcome? = nil
    ) {
        self.request = request
        self.card = card
        self.resolved = resolved
        self.pokemonPrintRun = pokemonPrintRun
        self.options = options
        self.catalogRetrievedAt = catalogRetrievedAt
        self.gradedOutcome = gradedOutcome
    }
}

/// The fully resolved value that may be detached from generation-owned work.
/// Once constructed, collection routing and duplicate confirmation no longer
/// depend on an identification task or its generation.
struct CollectionCommitCandidate: Sendable {
    let requestID: UUID
    let subject: ScanSubject
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    let pokemonPrintRun: PokemonPrintRun?
    let options: [PhysicalVariant]
    let price: PriceLookup
    let catalogRetrievedAt: Date
    let encounterID: UUID
    let heldRepeatAuthorizationID: UUID?
    let gradedOutcome: ScannedGradedOutcome?

    var identifier: ScanIdentifier { subject.identifier }

    init(resolvedScan: ResolvedScan) {
        requestID = resolvedScan.request.id
        subject = resolvedScan.request.subject
        card = resolvedScan.card
        resolved = resolvedScan.resolved
        pokemonPrintRun = resolvedScan.pokemonPrintRun
        options = resolvedScan.options
        if resolvedScan.request.subject.slab != nil {
            switch resolvedScan.gradedOutcome {
            case let .bound(variant):
                if let amount = variant.marketPriceUSD {
                    price = .price(
                        NormalizedPrice(
                            unitMarketPriceUSD: amount,
                            currencyCode: "USD",
                            source: .justTCG,
                            sourceVariantID: variant.id,
                            sourceUpdatedAt: variant.updatedAt,
                            fetchedAt: resolvedScan.catalogRetrievedAt
                        )
                    )
                } else {
                    price = .unavailable(.justTCG)
                }
            case .unpricedGrade, .unmatchedProduct, .unavailable, .none:
                price = .unavailable(.justTCG)
            }
        } else {
            price = CardPricing.price(
                for: resolvedScan.card,
                variant: resolvedScan.resolved.variant,
                magicTreatments: resolvedScan.card.magicTreatments(for: resolvedScan.resolved.variant),
                pokemonPrintRun: resolvedScan.pokemonPrintRun,
                at: resolvedScan.catalogRetrievedAt
            )
        }
        catalogRetrievedAt = resolvedScan.catalogRetrievedAt
        encounterID = resolvedScan.request.encounterID
        heldRepeatAuthorizationID = resolvedScan.request.heldRepeatAuthorizationID
        gradedOutcome = resolvedScan.gradedOutcome
    }

    var identity: ConsecutiveScanIdentity {
        ConsecutiveScanIdentity(card: card, subject: subject)
    }

    private init(
        requestID: UUID,
        subject: ScanSubject,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun?,
        options: [PhysicalVariant],
        price: PriceLookup,
        catalogRetrievedAt: Date,
        encounterID: UUID,
        heldRepeatAuthorizationID: UUID?,
        gradedOutcome: ScannedGradedOutcome?
    ) {
        self.requestID = requestID
        self.subject = subject
        self.card = card
        self.resolved = resolved
        self.pokemonPrintRun = pokemonPrintRun
        self.options = options
        self.price = price
        self.catalogRetrievedAt = catalogRetrievedAt
        self.encounterID = encounterID
        self.heldRepeatAuthorizationID = heldRepeatAuthorizationID
        self.gradedOutcome = gradedOutcome
    }
}

struct ConsecutiveScanIdentity: Equatable, Hashable, Sendable {
    /// `IdentifiedCard.id` intentionally excludes finish and Pokémon print-run
    /// selection. Those are physical variant details, while this key answers
    /// whether the resolved card printing is the same card encounter.
    let canonicalID: String
    /// Grading is a physical-object axis, not a catalog-card axis. Keep it in
    /// the consecutive-session identity so PSA 10 and PSA 9 are not treated as
    /// the same already-committed presentation.
    let slabSuppressionFragment: String?

    init(card: IdentifiedCard, subject: ScanSubject? = nil) {
        canonicalID = card.id
        slabSuppressionFragment = subject?.slab?.suppressionFragment
    }

    init(canonicalID: String, slabSuppressionFragment: String? = nil) {
        self.canonicalID = canonicalID
        self.slabSuppressionFragment = slabSuppressionFragment
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
        history: [CommittedSessionScan] = [],
        proofs: [SpatialResetProof]
    ) -> CollectionCandidateRoutingDecision {
        // `previous` remains as a compatibility/default input for callers that
        // only have one committed item. The scanner supplies the bounded full
        // history so an older still-present printing cannot lose duplicate
        // protection merely because an unrelated card committed afterwards.
        let candidates = history.isEmpty
            ? previous.map { [$0] } ?? []
            : history
        guard let previous = candidates.reversed().first(where: { $0.identity == identity }) else {
            return .automatic
        }

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

/// A graded scan may commit before the label gives a catalog-supported finish.
/// This is intentionally a banner-sized value, not a pending scan choice: the
/// camera keeps recognizing while the user decides whether to correct it.
struct PendingGradedVariantCorrection: Identifiable, Equatable, Sendable {
    let scanID: RecentScan.ID
    let card: IdentifiedCard
    let cardName: String
    let options: [PhysicalVariant]

    var id: UUID { scanID }

    static func == (lhs: PendingGradedVariantCorrection, rhs: PendingGradedVariantCorrection) -> Bool {
        lhs.scanID == rhs.scanID
            && lhs.cardName == rhs.cardName
            && lhs.options == rhs.options
    }
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
    let subject: ScanSubject
    let encounterID: UUID

    var identifier: ScanIdentifier { subject.identifier }
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

    /// Settings can only resolve the two fallback availability states. Keep the
    /// last-known variants in the same family so returning from Settings can
    /// retry without requiring the user to discover Refresh Price first.
    var isBlockedOnFallbackSettings: Bool {
        switch quoteState {
        case .fallbackDisabled, .fallbackUnconfigured,
             .lastKnown(.fallbackDisabled), .lastKnown(.fallbackUnconfigured):
            return true
        default:
            return false
        }
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
    let subject: ScanSubject
    let card: IdentifiedCard
    let resolved: ResolvedVariant
    let pokemonPrintRun: PokemonPrintRun?
    let catalogRetrievedAt: Date
    /// Every variant this printing could physically have been, kept so the same
    /// question can be re-asked later without another catalog round trip.
    let options: [PhysicalVariant]
    /// The unit quote captured from the same catalog response as the resolved
    /// finish. Keeping it on the session projection prevents the receipt from
    /// silently looking up (or borrowing) another finish's value.
    let price: PriceLookup
    let mutation: CollectionMutation

    var identifier: ScanIdentifier { subject.identifier }

    init(
        id: UUID = UUID(),
        subject: ScanSubject,
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun? = nil,
        catalogRetrievedAt: Date = .now,
        options: [PhysicalVariant],
        mutation: CollectionMutation,
        price: PriceLookup = .unavailable(nil)
    ) {
        self.id = id
        self.subject = subject
        self.card = card
        self.resolved = resolved
        self.pokemonPrintRun = pokemonPrintRun
        self.catalogRetrievedAt = catalogRetrievedAt
        self.options = options
        self.price = price
        self.mutation = mutation
    }

    func updating(price: PriceLookup) -> RecentScan {
        RecentScan(
            id: id,
            subject: subject,
            card: card,
            resolved: resolved,
            pokemonPrintRun: pokemonPrintRun,
            catalogRetrievedAt: catalogRetrievedAt,
            options: options,
            mutation: mutation,
            price: price
        )
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

/// Small synchronous guard for actions whose work crosses an async boundary.
/// A repeated tap for the same stable ID is ignored until the first operation
/// has finished.
struct InFlightIDGuard<ID: Hashable> {
    private var activeIDs: Set<ID> = []

    mutating func begin(_ id: ID) -> Bool {
        activeIDs.insert(id).inserted
    }

    mutating func end(_ id: ID) {
        activeIDs.remove(id)
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
    let catalogRetrievedAt: Date
    /// Set when Finish Lock named a variant this printing does not exist in. The
    /// lock is evidence, not an override, so the user is told rather than obeyed.
    let lockDidNotApply: MagicFinishLock?

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
    let catalogRetrievedAt: Date

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

    mutating func observe(_ subject: ScanSubject) -> Bool {
        let key = subject.suppressionKey
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
    let subject: ScanSubject

    var identifier: ScanIdentifier { subject.identifier }

    init(subject: ScanSubject) {
        self.subject = subject
    }

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
    private var mergeKey: ScanSuppressionKey { subject.suppressionKey }

    /// Adds a failure to the list, folding it into an existing row for the same
    /// card and keeping every distinct reading so the user can see what it read.
    static func merging(
        _ scans: [UnresolvedScan],
        with subject: ScanSubject
    ) -> [UnresolvedScan] {
        let incoming = UnresolvedScan(subject: subject)
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
            subject: ScanSubject(
                identifier: .pokemonHistorical(
                    PokemonHistoricalScanEvidence(number: mine.number, titleCandidates: titles)
                ),
                slab: subject.slab
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
    let id: UUID
    let scanID: RecentScan.ID
    let name: String
    let identifier: String
    let variantLabel: String
    let treatmentDiagnostics: [MagicTreatmentDiagnostic]
    let thumbnailURL: URL?
    let price: PriceLookup
    let resolution: VariantResolution?

    init(
        id: UUID = UUID(),
        scanID: RecentScan.ID,
        name: String,
        identifier: String,
        variantLabel: String,
        treatmentDiagnostics: [MagicTreatmentDiagnostic],
        thumbnailURL: URL?,
        price: PriceLookup = .unavailable(nil),
        resolution: VariantResolution? = nil
    ) {
        self.id = id
        self.scanID = scanID
        self.name = name
        self.identifier = identifier
        self.variantLabel = variantLabel
        self.treatmentDiagnostics = treatmentDiagnostics
        self.thumbnailURL = thumbnailURL
        self.price = price
        self.resolution = resolution
    }

    func updating(price: PriceLookup) -> ScanReceipt {
        ScanReceipt(
            id: id,
            scanID: scanID,
            name: name,
            identifier: identifier,
            variantLabel: variantLabel,
            treatmentDiagnostics: treatmentDiagnostics,
            thumbnailURL: thumbnailURL,
            price: price,
            resolution: resolution
        )
    }

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

/// Presentation acknowledgement for a confirmed collection scan. Recognition
/// and persistence are separate states: the first is emitted at the OCR
/// confirmation boundary, while the second is emitted only after the writer's
/// transaction succeeds.
enum ScanAcknowledgementPhase: Equatable, Sendable {
    case recognized
    case failed
}

struct ScanAcknowledgement: Identifiable, Equatable, Sendable {
    let id: UUID
    let encounterID: UUID
    let subject: ScanSubject
    let phase: ScanAcknowledgementPhase
    let message: String?

    init(
        id: UUID = UUID(),
        encounterID: UUID,
        subject: ScanSubject,
        phase: ScanAcknowledgementPhase,
        message: String? = nil
    ) {
        self.id = id
        self.encounterID = encounterID
        self.subject = subject
        self.phase = phase
        self.message = message
    }
}

/// A value-only departure report. It intentionally contains no scanner model
/// reference so the global banner can observe one small app-level state change
/// without invalidating the tab hierarchy during a live scan.
struct ScanSessionSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let addedCount: Int
    let knownValue: Money
    let unpricedCount: Int
    let unresolvedCount: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        addedCount: Int,
        knownValue: Money,
        unpricedCount: Int,
        unresolvedCount: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.addedCount = addedCount
        self.knownValue = knownValue
        self.unpricedCount = unpricedCount
        self.unresolvedCount = unresolvedCount
        self.createdAt = createdAt
    }

    var message: String {
        var parts: [String] = []
        if addedCount > 0 {
            parts.append("\(addedCount) card\(addedCount == 1 ? "" : "s")")
            if knownValue.isZero, unpricedCount == addedCount {
                parts.append("value unavailable")
            } else if unpricedCount > 0 {
                // Keep the partial value explicit. The absence of the word
                // "added" here is intentional: the unpriced count is the
                // important qualification in the departure summary.
                parts.append("\(knownValue.formatted()) known value")
                parts.append("\(unpricedCount) unpriced")
            } else {
                parts.append("\(knownValue.formatted()) added")
            }
        }
        if unresolvedCount > 0 {
            parts.append("\(unresolvedCount) needs attention")
        }
        return parts.isEmpty ? "No cards added" : parts.joined(separator: " · ")
    }
}

@MainActor
final class ScanSessionSummaryStore: ObservableObject {
    @Published private(set) var summary: ScanSessionSummary?
    private var dismissTask: Task<Void, Never>?

    func publish(_ summary: ScanSessionSummary) {
        dismissTask?.cancel()
        self.summary = summary
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            guard self?.summary?.id == summary.id else { return }
            self?.summary = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        summary = nil
    }
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
    @Published private(set) var pendingGradedVariantCorrection: PendingGradedVariantCorrection?
    @Published private(set) var receipt: ScanReceipt?
    @Published private(set) var recent: [RecentScan] = []
    /// The complete successful session projection. `recent` is intentionally
    /// capped to the five-card inline rail and is never used for accounting.
    @Published private(set) var sessionScans: [RecentScan] = []
    /// Authoritative consecutive-scan history. `recent` is only the visual rail;
    /// duplicate correctness never depends on its ordering or contents.
    private(set) var committedSessionHistory: [CommittedSessionScan] = []
    @Published private(set) var note: ScanNote?
    @Published private(set) var scanAcknowledgement: ScanAcknowledgement?
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
    /// Increments on every successful add so the preview can show its green
    /// persistence acknowledgement.
    @Published private(set) var successCount = 0
    /// Increments at OCR confirmation so the preview can acknowledge that the
    /// card was consumed before catalog and persistence work finishes.
    @Published private(set) var recognitionCount = 0
    /// One lock per game, because a Pokémon lock says nothing about a Magic card
    /// and the scanner no longer knows which is coming next. Only the lock for
    /// the game of the card just identified is ever consulted.
    @Published private(set) var finishLocks: [CardGame: MagicFinishLock] = [:]

    let scanner: CardScanner

    /// The latch needs only its bounded recent window for duplicate routing.
    /// The UI rail keeps a few more cards for a useful visual history, but no
    /// scanner session should retain every decoded catalog payload forever.
    private static let committedHistoryLimit = CardLatch.recentlyConsumedLimit
    private static let recentScanLimit = 5

    private let catalog: CardCatalog
    private let feedback: ScanFeedback
    private let gradedResolver: ScannedGradedResolving
    private let scryfall = ScryfallService()

    private var collectionWriter: ScannerCollectionWriter?
    private var modelContainer: ModelContainer?
    private var priceCheckCoordinator: PriceCheckCoordinator?
    private var fallbackQuoteTasks: [String: Task<Void, Never>] = [:]
    /// One fallback response may serve copies in more than one scanner session
    /// while a departure is still draining. Keep the session fence beside the
    /// interested scan IDs so a late response can never recreate old state.
    private var fallbackQuoteScanIDs: [String: [UUID: Set<UUID>]] = [:]
    /// What the scanner was last given, so an unchanged directory costs a
    /// comparison rather than a regex compile. See `installMagicDefinitions`.
    private var installedMagicDefinitions: [MagicSetDefinition]?
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
    private var scannedGradedOutcomes: [UUID: ScannedGradedOutcome] = [:]
    private var oneCardScanIntervals: [UUID: OSSignpostIntervalState] = [:]
    private var quoteRefreshTask: Task<Void, Never>?
    private var activeQuoteRefreshID: UUID?
    /// SwiftUI clears a `.sheet(item:)` binding before invoking its dismissal
    /// callback. Retain the confirmed identity just long enough for that
    /// callback to arm the delayed re-check latch, including swipe dismissal.
    private var presentedPriceCheckSubject: ScanSubject?
    private var scanGeneration = 0
    private var recognitionEligibility = ScannerRecognitionEligibility()
    /// Changes whenever the visible scanner surface crosses a lifecycle or
    /// presentation boundary. It prevents a callback queued before a sheet or
    /// tab transition from being accepted after that transition.
    private var visibilityEpoch = UUID()
    /// Proofs arrive independently of catalog resolution. A provisional proof
    /// is held by encounter id until its successful commit can associate it with
    /// a committed presentation.
    private var spatialResetProofs: [SpatialResetProof] = []
    /// Enough to take back the most recent add, including the question that was
    /// asked at the time so undo can re-ask it.
    private var lastAdd: RecentScan?
    private var undoingScanIDs = InFlightIDGuard<RecentScan.ID>()
    private var heldRepeatAuthorizationState: HeldRepeatAuthorizationState?
    private var deferredHeldDuplicateOffer: DeferredHeldDuplicateOffer?
    private var catalogMissVerification: CatalogMissVerification? {
        didSet {
            scanner.updateCatalogMissSuppressionKey(catalogMissVerification?.suppressionKey)
        }
    }
    private weak var summaryStore: ScanSessionSummaryStore?
    private weak var writeCoordinator: DerivedStateWriteCoordinator?
    /// Keep the coordinator that actually opened the scanner interval. A tab
    /// revisit can supply a new environment object while finalization is still
    /// draining; ending through the current coordinator would strand the old
    /// one at depth one.
    private var activeScannerBulkWriteCoordinator: DerivedStateWriteCoordinator?
    private var scannerBulkWriteActive = false
    private var isScannerSessionActive = false
    /// A completion from an ended session must never publish into the next one.
    /// This token remains stable while finalization drains, then changes before
    /// the old projections are cleared.
    private var scannerSessionID = UUID()
    private var sessionFinalizationTask: Task<Void, Never>?
    /// Counts are keyed by session because a timed-out old writer may finish
    /// after a new session has started; one session's defer must not decrement
    /// another session's in-flight count.
    private var pendingWriteCounts: [UUID: Int] = [:]
    private static let sessionFinalizationDrainTimeout: TimeInterval = 2
    /// A tab can be revisited while the previous session is waiting for its
    /// last writer operation. Hold the new appearance until that old session
    /// has published its summary and cleared its projections.
    private struct PendingSessionStart {
        let container: ModelContainer
        let isSceneActive: Bool
        let startCamera: Bool
        let shouldRefreshMagicDirectory: Bool
        let summaryStore: ScanSessionSummaryStore?
        let writeCoordinator: DerivedStateWriteCoordinator?
    }
    private var pendingSessionStart: PendingSessionStart?
#if DEBUG
    private var diagnosticEvents: [String] = []
#endif

    /// The receipt is an undo affordance, not a fleeting toast. It remains
    /// available through the next card's recognition until a new add replaces
    /// it, the person takes another scanner action, or five seconds pass.
    private static let receiptLifetime: Duration = .seconds(5)
    private static let slowLookupThreshold: Duration = .milliseconds(400)
    private static let noteLifetime: Duration = .milliseconds(2600)

    init(
        scanner: CardScanner = CardScanner(),
        catalog: CardCatalog = CardCatalog(),
        feedback: ScanFeedback? = nil,
        gradedResolver: ScannedGradedResolving = ScannedGradedResolver()
    ) {
        self.scanner = scanner
        self.catalog = catalog
        self.feedback = feedback ?? ScanFeedback()
        self.gradedResolver = gradedResolver

        let catalog = self.catalog
        scanner.onPlausibleCandidate = { subject in
            // Speculation only. Nothing downstream may act on this. The
            // scanner already filters the active catalog-miss identity on its
            // vision queue, so starting the actor request needs no main-actor
            // hop.
            Task {
                await catalog.prefetch(subject.identifier)
            }
        }

        scanner.onObservedCandidate = { [weak self] subject in
            Task { @MainActor in
                self?.observeCatalogMissVerification(subject)
            }
        }

        let handleConfirmedCandidate: (ScannerConfirmationToken?, UUID, ScanSubject, UUID?) -> Void = { [weak self] token, encounterID, subject, authorizationID in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.isScannerSessionActive,
                      self.recognitionEligibility.allowsRecognition else {
                    self.diagnostic("staleConfirmationDropped")
                    return
                }
                if let token,
                   token != self.currentConfirmationToken {
                    self.diagnostic("staleConfirmationDropped")
                    return
                }
                if self.oneCardScanIntervals[encounterID] == nil {
                    self.oneCardScanIntervals[encounterID] = PerformanceSignpost.beginInterval(
                        "oneCardScan",
                        id: PerformanceSignpost.makeID(),
                        "encounter=\(encounterID.uuidString)"
                    )
                }
                if self.purpose == .collection {
                    // Keep the recognition acknowledgement visible across the
                    // identity and persistence gap. The message is upgraded to
                    // "Saving..." only once a collection write is authorized.
                    self.dismissReceipt()
                    self.scanAcknowledgement = ScanAcknowledgement(
                        encounterID: encounterID,
                        subject: subject,
                        phase: .recognized
                    )
                    self.recognitionCount += 1
                    self.feedback.recognized()
                    self.diagnostic("recognitionAcknowledgement")
                }
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
                   offer.suppressionKey != subject.suppressionKey {
                    self.heldDuplicateOffer = nil
                    self.diagnostic("heldDuplicateOfferDismissedByDifferentCard")
                }
                if let deferred = self.deferredHeldDuplicateOffer,
                   deferred.encounterID != encounterID {
                    self.deferredHeldDuplicateOffer = nil
                }
                if let verification = self.catalogMissVerification,
                   verification.suppressionKey != subject.suppressionKey {
                    self.catalogMissVerification = nil
                }
                self.enqueueIdentification(
                    subject,
                    encounterID: encounterID,
                    heldRepeatAuthorizationID: authorizationID,
                    purpose: token?.purpose,
                    generation: token?.generation
                )
            }
        }
        scanner.onConfirmedSubjectCandidate = handleConfirmedCandidate

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
                self?.recognitionEligibility.isCameraInterrupted = false
                self?.resumeRecognitionIfPossible()
            }
        }

        scanner.onLatchHolding = { [weak self] subject, encounterID in
            Task { @MainActor in
                self?.offerHeldDuplicate(for: subject, encounterID: encounterID)
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
                   deferred.subject.suppressionKey == suppressionKey,
                   encounterID == nil || deferred.encounterID == encounterID {
                    self.deferredHeldDuplicateOffer = nil
                }
                if self.catalogMissVerification?.suppressionKey == suppressionKey {
                    self.catalogMissVerification = nil
                }
            }
        }
    }

    private var currentConfirmationToken: ScannerConfirmationToken? {
        guard isScannerSessionActive,
              recognitionEligibility.allowsRecognition else { return nil }
        return ScannerConfirmationToken(
            sessionID: scannerSessionID,
            generation: scanGeneration,
            purpose: purpose,
            visibilityEpoch: visibilityEpoch
        )
    }

    private func updateScannerConfirmationContext() {
        scanner.updateConfirmationContext(currentConfirmationToken)
    }

    // MARK: - Session lifecycle

    func start(
        context: ModelContext,
        isSceneActive: Bool = true,
        startCamera: Bool = true,
        shouldRefreshMagicDirectory: Bool = true,
        summaryStore: ScanSessionSummaryStore? = nil,
        writeCoordinator: DerivedStateWriteCoordinator? = nil
    ) {
        self.summaryStore = summaryStore
        self.writeCoordinator = writeCoordinator ?? self.writeCoordinator
        if sessionFinalizationTask != nil {
            // `viewDisappeared()` has already stopped recognition, but its
            // finalizer may still be waiting for an in-flight durable write.
            // Starting the next session here would let the old completion
            // append into the new session's arrays.
            pendingSessionStart = PendingSessionStart(
                container: context.container,
                isSceneActive: isSceneActive,
                startCamera: startCamera,
                shouldRefreshMagicDirectory: shouldRefreshMagicDirectory,
                summaryStore: summaryStore,
                writeCoordinator: writeCoordinator ?? self.writeCoordinator
            )
            recognitionEligibility.isScannerVisible = true
            recognitionEligibility.isSceneActive = isSceneActive
            visibilityEpoch = UUID()
            updateScannerConfirmationContext()
            return
        }
        let beginsNewSession = !isScannerSessionActive
        if !isScannerSessionActive {
            isScannerSessionActive = true
            modelContainer = context.container
            collectionWriter = ScannerCollectionWriter(modelContainer: context.container)
        } else if collectionWriter == nil {
            modelContainer = context.container
            collectionWriter = ScannerCollectionWriter(modelContainer: context.container)
        }
        if beginsNewSession {
            scannerSessionID = UUID()
            visibilityEpoch = UUID()
            successCount = 0
            recognitionCount = 0
        }
        beginScannerBulkWriteIfNeeded()
        recognitionEligibility.isScannerVisible = true
        recognitionEligibility.isSceneActive = isSceneActive
        // A fresh visible scanner owns a new camera-session opportunity. If a
        // platform interruption ended while the tab was away, its stale
        // callback must not keep the new session paused forever.
        recognitionEligibility.isCameraInterrupted = false
        updateScannerConfirmationContext()
        // Price Check is an independent, network-paced persistence flow. Keep
        // its quote/price context separate so QuoteCache.save cannot commit or
        // roll back an in-flight collection mutation.
        priceCheckCoordinator = PriceCheckCoordinator(
            context: ModelContext(context.container)
        )
        feedback.prepare()
        // Decode the merged Pokémon checklist and resolved-card cache before
        // the first confirmed frame needs either one.
        Task { await catalog.prewarm() }
        if isSceneActive, startCamera {
            scanner.start()
        }

        // Magic's OCR vocabulary is its set directory, so the compiled-in
        // snapshot goes in before the first frame rather than after a network
        // round trip. The camera is useful immediately, and offline.
        installMagicDefinitions(magicSetDefinitions)
        resumeRecognitionIfPossible()
        if shouldRefreshMagicDirectory {
            refreshMagicDirectory()
        }
    }

    /// Leaving the Scan tab is the session boundary. Backgrounding the app is
    /// deliberately handled by `scenePhaseChanged` instead, so an OS lifecycle
    /// transition cannot publish a false departure report.
    /// `useMagicDefinitions` compiles the vocabulary regex on its dedicated
    /// background queue and only then hands it to the vision queue, which
    /// compares it against what is already installed. `start` runs on every
    /// Scan-tab appearance, so that comparison was being paid for with a
    /// compile. Answer the same question here, before the work.
    private func installMagicDefinitions(_ definitions: [MagicSetDefinition]) {
        guard installedMagicDefinitions != definitions else { return }
        installedMagicDefinitions = definitions
        scanner.useMagicDefinitions(definitions)
    }

    func viewDisappeared() {
        let shouldFinalize = isScannerSessionActive && recognitionEligibility.isSceneActive
        recognitionEligibility.isScannerVisible = false
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        guard shouldFinalize else {
            endScannerBulkWriteIfNeeded()
            scanner.stop()
            return
        }
        beginSessionFinalization()
    }

    private func beginSessionFinalization() {
        guard sessionFinalizationTask == nil else { return }

        // A write that has already reached the writer is allowed to finish. The
        // final report must describe durable state, not the state visible at the
        // instant the tab disappeared.
        let finalizingSessionID = scannerSessionID
        isScannerSessionActive = false
        invalidatePendingScan()
        scanner.endSession()

        sessionFinalizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date.now.addingTimeInterval(Self.sessionFinalizationDrainTimeout)
            // Cancellation is the invalidation fence. Do not await an
            // uncooperative identification task before starting the bounded
            // drain, because a hung provider would otherwise keep the next
            // scanner appearance blocked forever.
            while self.identificationTask != nil,
                  !Task.isCancelled,
                  Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            while self.pendingWriteCounts[finalizingSessionID, default: 0] > 0,
                  !Task.isCancelled,
                  Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }

            if self.pendingWriteCounts[finalizingSessionID, default: 0] > 0 {
                // A wedged local write must not make every later Scan visit
                // wait forever. Its eventual completion is fenced by the
                // session token below, so it cannot append into fresh state.
                PerformanceSignpost.signposter.emitEvent("scannerFinalizationTimedOut")
            }

            if let summary = self.makeSessionSummary() {
                self.summaryStore?.publish(summary)
            }
            self.scannerSessionID = UUID()
            if self.pendingWriteCounts[finalizingSessionID] == 0 {
                self.pendingWriteCounts.removeValue(forKey: finalizingSessionID)
            }
            self.clearSessionState()
            let pendingStart = self.pendingSessionStart
            self.pendingSessionStart = nil
            self.sessionFinalizationTask = nil
            self.endScannerBulkWriteIfNeeded()
            guard let pendingStart,
                  self.recognitionEligibility.isScannerVisible else { return }
            self.start(
                context: ModelContext(pendingStart.container),
                isSceneActive: pendingStart.isSceneActive,
                startCamera: pendingStart.startCamera,
                shouldRefreshMagicDirectory: pendingStart.shouldRefreshMagicDirectory,
                summaryStore: pendingStart.summaryStore,
                writeCoordinator: pendingStart.writeCoordinator
            )
        }
    }

    private func beginTrackedWrite(for sessionID: UUID) {
        pendingWriteCounts[sessionID, default: 0] += 1
    }

    private func endTrackedWrite(for sessionID: UUID) {
        guard let count = pendingWriteCounts[sessionID] else { return }
        if count <= 1 {
            pendingWriteCounts.removeValue(forKey: sessionID)
        } else {
            pendingWriteCounts[sessionID] = count - 1
        }
    }

    private func makeSessionSummary() -> ScanSessionSummary? {
        let addedCount = sessionScans.count
        let unresolvedCount = unresolvedScans.count
        guard addedCount > 0 || unresolvedCount > 0 else { return nil }

        let prices = sessionScans.compactMap { scan -> Money? in
            guard case let .price(price) = scan.price else { return nil }
            return Money(rounding: price.unitMarketPriceUSD)
        }
        return ScanSessionSummary(
            addedCount: addedCount,
            knownValue: prices.sum(),
            unpricedCount: sessionScans.count - prices.count,
            unresolvedCount: unresolvedCount
        )
    }

    private func clearSessionState() {
        for encounterID in Array(oneCardScanIntervals.keys) {
            endOneCardScan(encounterID: encounterID, outcome: "session-ended")
        }
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        pendingDuplicateConfirmation = nil
        heldDuplicateOffer = nil
        pendingGradedVariantCorrection = nil
        scanAcknowledgement = nil
        receipt = nil
        quoteRefreshTask?.cancel()
        quoteRefreshTask = nil
        activeQuoteRefreshID = nil
        priceCheckResult = nil
        presentedPriceCheckSubject = nil
        recent.removeAll()
        sessionScans.removeAll()
        committedSessionHistory.removeAll()
        unresolvedScans.removeAll()
        spatialResetProofs.removeAll()
        lastAdd = nil
        deferredHeldDuplicateOffer = nil
        catalogMissVerification = nil
        heldRepeatAuthorizationState = nil
    }

    private func beginScannerBulkWriteIfNeeded() {
        guard !scannerBulkWriteActive, let coordinator = writeCoordinator else { return }
        coordinator.beginBulkWrite()
        activeScannerBulkWriteCoordinator = coordinator
        scannerBulkWriteActive = true
    }

    private func endScannerBulkWriteIfNeeded() {
        guard scannerBulkWriteActive else { return }
        scannerBulkWriteActive = false
        activeScannerBulkWriteCoordinator?.endBulkWrite()
        activeScannerBulkWriteCoordinator = nil
    }

    func scenePhaseChanged(isActive: Bool) {
        recognitionEligibility.isSceneActive = isActive
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        if isActive {
            // Returning to the foreground is itself a valid recovery boundary;
            // recognition must not depend on AVCaptureSession delivering its
            // separate interruption-ended notification.
            recognitionEligibility.isCameraInterrupted = false
            updateScannerConfirmationContext()
            if recognitionEligibility.isScannerVisible {
                scanner.start()
                // `start()` restores the capture session, but it deliberately
                // does not change the recognition pause state. The inactive
                // transition pauses recognition before returning to the
                // background, so foreground recovery must pass through the
                // same eligibility gate as every other resume path.
                resumeRecognitionIfPossible()
            }
            if let result = priceCheckResult,
               result.quoteState == .checking,
               !result.isRefreshing {
                refreshPriceCheckQuote()
            }
            return
        }
        invalidatePendingScan()
    }

    private func cameraInterruptionStarted() {
        recognitionEligibility.isCameraInterrupted = true
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        invalidatePendingScan()
        show(ScanNote(text: "Camera interrupted — scan again when it returns", tone: .info))
    }

    /// A sheet is the one place the scanner should stop looking: the user is
    /// deliberately elsewhere, and a card added behind a sheet would be a card
    /// nobody saw being added.
    func pauseForPresentation() {
        recognitionEligibility.isBlockedByPresentation = true
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        dismissReceipt()
        scanner.pauseRecognition()
    }

    func resumeAfterPresentation() {
        recognitionEligibility.isBlockedByPresentation = false
        settingsDismissed()
    }

    /// Settings may be opened from either the scanner chrome or a nested Price
    /// Check result sheet. Re-read the live preference and credential state
    /// when either path closes; `shouldAutoRefresh` is intentionally one-shot
    /// and cannot represent this later user action.
    func settingsDismissed() {
        recognitionEligibility.isBlockedByPresentation = false
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        feedback.prepare()
        resumeRecognitionIfPossible()
        guard let result = priceCheckResult,
              !result.isRefreshing,
              result.isBlockedOnFallbackSettings,
              UserDefaults.standard.bool(forKey: "usesPriceFallback"),
              PriceVendorCredentials.hasKey else { return }
        refreshPriceCheckQuote()
    }

    func dismissPriceCheckResult() {
        recognitionEligibility.isBlockedByPresentation = false
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        let dismissedSubject = priceCheckResult?.resolvedScan.request.subject
            ?? presentedPriceCheckSubject
        cancelPriceCheckRefresh()
        priceCheckResult = nil
        presentedPriceCheckSubject = nil
        if let dismissedSubject {
            scanner.allowRecheck(of: dismissedSubject)
        }
        feedback.prepare()
        resumeRecognitionIfPossible()
    }

    // MARK: - Controls

    func setPurpose(_ newPurpose: ScanPurpose) {
        guard newPurpose != purpose else { return }

        invalidatePendingScan()
        purpose = newPurpose
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        resumeRecognitionIfPossible()
        feedback.choiceMade()
        UIAccessibility.post(notification: .announcement, argument: "\(newPurpose.title). \(newPurpose.statusText)")
    }

    private func invalidatePendingScan() {
        // Cancellation is an invalidation boundary, not a reinterpretation.
        // Existing completions are allowed to finish their network work but can
        // no longer affect any UI or destination.
        for encounterID in Array(oneCardScanIntervals.keys) {
            endOneCardScan(encounterID: encounterID, outcome: "invalidated")
        }
        scanGeneration += 1
        updateScannerConfirmationContext()
        cancelPriceCheckRefresh()
        identificationTask?.cancel()
        activeIdentificationRequestID = nil
        isProcessingIdentification = false
        resolutionTask?.cancel()
        identificationQueue.removeAll()
        scannedGradedOutcomes.removeAll()
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        pendingDuplicateConfirmation = nil
        pendingGradedVariantCorrection = nil
        spatialResetProofs.removeAll()
        deferredHeldDuplicateOffer = nil
        catalogMissVerification = nil
        clearHeldRepeatState()
        receiptTask?.cancel()
        receipt = nil
        noteTask?.cancel()
        note = nil
        scanAcknowledgement = nil
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
    private func offerHeldDuplicate(for subject: ScanSubject, encounterID: UUID?) {
        guard purpose == .collection,
              heldDuplicateOffer == nil,
              heldRepeatAuthorizationState == nil,
              pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil,
              let encounterID else { return }

        // Diagnostic only: this rebuilds a lookup from the whole session on
        // every latch-hold announcement. The metadata carries `sessionScans`'
        // size so an Instruments trace can show directly whether this
        // operation's cost grows with how long the current session has run,
        // rather than staying flat.
        let offerHeldDuplicateState = PerformanceSignpost.beginInterval(
            "offerHeldDuplicateRebuild",
            id: PerformanceSignpost.makeID(),
            "sessionScans=\(sessionScans.count)"
        )
        let recentByID = Dictionary(uniqueKeysWithValues: sessionScans.map { ($0.id, $0) })
        let history = committedSessionHistory.compactMap { committed -> HeldDuplicatePublicationHistoryEntry? in
            guard let scan = recentByID[committed.id] else { return nil }
            return HeldDuplicatePublicationHistoryEntry(
                committed: committed,
                suppressionKey: scan.subject.suppressionKey
            )
        }
        // The rebuild above is the O(sessionScans.count) part; everything after
        // this point is bounded by `committedSessionHistory`'s small cap, so the
        // interval closes here rather than at function exit.
        PerformanceSignpost.endInterval(
            "offerHeldDuplicateRebuild",
            offerHeldDuplicateState,
            "sessionScans=\(sessionScans.count)"
        )

        switch HeldDuplicateOfferPublicationPolicy.decision(
            for: subject.suppressionKey,
            encounterID: encounterID,
            history: history
        ) {
        case .deferUntilCommit:
            // The latch can announce while its newly confirmed encounter is
            // still resolving. Hold the signal until the same encounter has a
            // successful persistence acknowledgment; an offer for an
            // uncommitted card is not actionable.
            deferredHeldDuplicateOffer = DeferredHeldDuplicateOffer(
                subject: subject,
                encounterID: encounterID
            )
        case .suppress:
            return
        case .publish(let selected):
            guard let previousScan = sessionScans.first(where: { $0.id == selected.committed.id }),
                  previousScan.subject.suppressionKey == subject.suppressionKey else {
                return
            }
            publishHeldDuplicateOffer(
                for: subject,
                encounterID: encounterID,
                previous: selected.committed,
                previousScan: previousScan
            )
        }
    }

    private func publishHeldDuplicateOffer(
        for subject: ScanSubject,
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
            suppressionKey: subject.suppressionKey,
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
        endOneCardScan(encounterID: pending.encounterID, outcome: "same-card")
        spatialResetProofs.removeAll { $0.encounterID == pending.encounterID }

        guard let previous = committedSessionHistory.first(where: { $0.id == pending.previousScanID }),
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
        beginPendingResolution(requestID: pending.candidate.requestID) { [weak self] in
            guard let self else { return }
            guard await self.commitAuthorizedCollectionCandidate(
                pending.candidate,
                authorization: .addAnother
            ) else {
                self.pendingDuplicateConfirmation = pending
                self.scanner.pauseRecognition()
                return
            }

            // A different card commit is the boundary at which any unrelated
            // outstanding proof is no longer useful. The candidate's own proof is
            // carried by its tracker and may arrive after the commit.
            self.spatialResetProofs.removeAll { $0.encounterID != pending.encounterID }
        }
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

    /// Explicitly ends the scanner session without publishing a departure
    /// banner. The tab lifecycle uses `viewDisappeared()` so it can publish the
    /// net result before clearing the same state.
    func endSession() {
        endScannerBulkWriteIfNeeded()
        invalidatePendingScan()
        scannerSessionID = UUID()
        visibilityEpoch = UUID()
        updateScannerConfirmationContext()
        clearSessionState()
        isScannerSessionActive = false
        scanner.endSession()
    }

    func setFinishLock(_ lock: MagicFinishLock?, for game: CardGame) {
        finishLocks[game] = lock
        feedback.choiceMade()

        // A lock set while a question is on screen answers that question's
        // premise, so re-run it rather than leaving a stale menu up.
        if let pending = pendingChoice,
           pending.identifier.game == game,
           let lock,
           pending.options.contains(where: {
               $0.id.caseInsensitiveCompare(lock.finish.id) == .orderedSame
           }),
           lock.treatment.map({ pending.card.magicTreatments(for: lock.finish).contains($0) }) ?? true {
            choose(lock.finish)
        }
    }

    func clearFinishLocks() {
        guard !finishLocks.isEmpty else { return }
        finishLocks.removeAll()
        feedback.choiceMade()
    }

    func finishLock(for game: CardGame) -> MagicFinishLock? {
        finishLocks[game]
    }

    var activeFinishLocks: [(game: CardGame, lock: MagicFinishLock)] {
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
        let resolved = ResolvedScan(
            request: pending.request,
            card: pending.card,
            resolved: ResolvedVariant(variant: variant, resolution: .userConfirmed),
            pokemonPrintRun: pending.pokemonPrintRun,
            options: pending.options,
            catalogRetrievedAt: pending.catalogRetrievedAt
        )
        beginPendingResolution(requestID: pending.request.id) { [weak self] in
            guard let self else { return }
            await self.route(resolved)
        }
    }

    /// Walking away from a question writes nothing. The latch stays engaged, so
    /// the same card sitting in the band does not immediately ask again. The
    /// recognition acknowledgement belongs to this same encounter; remove it
    /// when the user cancels so a non-write cannot remain in the "Saving..."
    /// state indefinitely.
    func dismissChoice() {
        if let pending = pendingChoice {
            let requestID = pending.request.id
            scannedGradedOutcomes.removeValue(forKey: requestID)
            endOneCardScan(encounterID: pending.request.encounterID, outcome: "choice-dismissed")
            clearAcknowledgement(for: pending.request.encounterID)
        }
        pendingChoice = nil
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    func choose(_ printRun: PokemonPrintRun) {
        guard let pending = pendingPrintRunChoice,
              pending.options.contains(printRun) else { return }
        feedback.choiceMade()
        pendingPrintRunChoice = nil
        beginPendingResolution(requestID: pending.request.id) { [weak self] in
            guard let self else { return }
            await self.resolveVariant(
                for: pending.request,
                card: pending.card,
                pokemonPrintRun: printRun,
                catalogRetrievedAt: pending.catalogRetrievedAt
            )
        }
    }

    func dismissPrintRunChoice() {
        if let pending = pendingPrintRunChoice {
            let requestID = pending.request.id
            scannedGradedOutcomes.removeValue(forKey: requestID)
            endOneCardScan(encounterID: pending.request.encounterID, outcome: "print-run-dismissed")
            clearAcknowledgement(for: pending.request.encounterID)
        }
        pendingPrintRunChoice = nil
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    func choose(_ candidate: PokemonCatalogCardIdentity) {
        guard let pending = pendingIdentityChoice,
              pending.candidates.contains(candidate) else { return }
        feedback.choiceMade()

        pendingIdentityChoice = nil
        beginPendingResolution(requestID: pending.request.id) { [weak self] in
            guard let self else { return }
            self.beginIdentification()
            defer { self.endIdentification() }
            do {
                let card = try await self.catalog.card(
                    for: candidate,
                    matching: pending.evidence
                )
                guard !Task.isCancelled,
                      self.isCurrent(pending.request) else {
                    self.endOneCardScan(
                        encounterID: pending.request.encounterID,
                        outcome: "cancelled"
                    )
                    return
                }
                await self.resolvePrintRun(
                    for: pending.request,
                    card: card,
                    catalogRetrievedAt: .now,
                    labelPrintRun: pending.request.subject.slab?.printedPrintRun
                )
            } catch {
                guard !Task.isCancelled, self.isCurrent(pending.request) else {
                    self.endOneCardScan(
                        encounterID: pending.request.encounterID,
                        outcome: "cancelled"
                    )
                    return
                }
                self.show(ScanNote(text: "Lookup failed — tap the set to retry", tone: .problem))
                self.failAcknowledgement(
                    for: pending.request.encounterID,
                    message: "This card was recognized but was not added. Tap the set to retry."
                )
                self.feedback.problem()
            }
        }
    }

    func dismissIdentityChoice() {
        if let pending = pendingIdentityChoice {
            let requestID = pending.request.id
            scannedGradedOutcomes.removeValue(forKey: requestID)
            endOneCardScan(encounterID: pending.request.encounterID, outcome: "identity-dismissed")
            clearAcknowledgement(for: pending.request.encounterID)
        }
        pendingIdentityChoice = nil
        resumeRecognitionIfPossible()
        processNextIdentificationIfPossible()
    }

    /// One guarded undo path for the receipt, rail, and review sheet. The
    /// stable scan ID is resolved at tap time, so a corrected scan cannot undo
    /// an older value still held by a view.
    @discardableResult
    func undoScan(scanID: RecentScan.ID) async -> Bool {
        guard undoingScanIDs.begin(scanID) else { return false }
        defer { undoingScanIDs.end(scanID) }

        guard let collectionWriter else {
            show(ScanNote(text: "Undo could not be saved", tone: .problem))
            feedback.problem()
            return false
        }
        guard let scan = sessionScans.first(where: { $0.id == scanID }) else {
            show(ScanNote(text: "Undo could not find that scan", tone: .problem))
            feedback.problem()
            return false
        }
        let removedHistoryEntry = committedSessionHistory.first { $0.id == scanID }
        let writeSessionID = scannerSessionID

        // The scan exists here only because appendCommittedScan ran after its
        // add awaited the writer. That UI projection is the ordering fence:
        // the actor itself does not promise FIFO for separately awaiting calls.
        beginTrackedWrite(for: writeSessionID)
        defer { endTrackedWrite(for: writeSessionID) }
        do {
            try await collectionWriter.undo(scan.mutation)
        } catch {
            guard writeSessionID == scannerSessionID else { return false }
            // Keep the receipt/review state intact so the person can retry after
            // a transient save or synchronization failure.
            show(ScanNote(text: "Undo could not be saved", tone: .problem))
            feedback.problem()
            return false
        }
        guard writeSessionID == scannerSessionID else { return false }

        sessionScans.removeAll { $0.id == scanID }
        recent.removeAll { $0.id == scanID }
        removeCommittedHistory(for: scanID)
        spatialResetProofs.removeAll { $0.encounterID == removedHistoryEntry?.encounterID }

        if heldDuplicateOffer?.previousScanID == scanID ||
            heldRepeatAuthorizationState?.offer.previousScanID == scanID {
            clearHeldRepeatState()
        }
        if let pending = pendingDuplicateConfirmation,
           pending.previousScanID == scanID {
            endOneCardScan(encounterID: pending.encounterID, outcome: "duplicate-prompt-abandoned")
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
            clearAcknowledgement(for: removedHistoryEntry.encounterID)
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
        Task { @MainActor [weak self] in
            _ = await self?.undoScan(scanID: scanID)
        }
    }

    func deleteRecentScan(_ scan: RecentScan) {
        Task { @MainActor [weak self] in
            _ = await self?.undoScan(scanID: scan.id)
        }
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
    func correct(scanID: RecentScan.ID, to variant: PhysicalVariant) async -> ScanCorrectionOutcome {
        guard let collectionWriter else {
            show(ScanNote(text: "Correction could not be saved", tone: .problem))
            feedback.problem()
            return .failed
        }
        guard let scan = sessionScans.first(where: { $0.id == scanID }),
              scan.resolved.variant != variant else { return .failed }

        let corrected = ResolvedVariant(variant: variant, resolution: .userConfirmed)
        let correctedLookup: PriceLookup
        if scan.subject.slab != nil {
            correctedLookup = .unavailable(.justTCG)
        } else {
            correctedLookup = CardPricing.price(
                for: scan.card,
                variant: variant,
                magicTreatments: scan.card.magicTreatments(for: variant),
                pokemonPrintRun: scan.pokemonPrintRun,
                at: scan.catalogRetrievedAt
            )
        }

        let writeSessionID = scannerSessionID
        beginTrackedWrite(for: writeSessionID)
        defer { endTrackedWrite(for: writeSessionID) }

        let mutation: CollectionMutation?
        do {
            mutation = try await collectionWriter.correct(
                card: scan.card,
                from: scan.resolved.variant,
                to: corrected,
                pokemonPrintRun: scan.pokemonPrintRun,
                previousCollectionKey: scan.mutation.collectionKey,
                previousLedgerOperationIDs: scan.mutation.ledgerOperationIDs,
                activityID: scan.mutation.activityID,
                quantity: 1,
                price: correctedLookup,
                isGraded: scan.subject.slab != nil
            )
        } catch {
            guard writeSessionID == scannerSessionID else { return .failed }
            show(ScanNote(text: "Correction could not be saved", tone: .problem))
            feedback.problem()
            return .failed
        }
        guard writeSessionID == scannerSessionID else { return .failed }
        guard let mutation else {
            show(ScanNote(text: "This scan is no longer in your collection", tone: .problem))
            feedback.problem()
            return .sourceMissing
        }

        // Reuse the id so the rail thumbnail stays the same item rather than
        // animating out and back in for what the user experienced as an edit.
        let replacement = RecentScan(
            id: scan.id,
            subject: scan.subject,
            card: scan.card,
            resolved: corrected,
            pokemonPrintRun: scan.pokemonPrintRun,
            catalogRetrievedAt: scan.catalogRetrievedAt,
            options: scan.options,
            mutation: mutation,
            price: scan.subject.slab == nil ? correctedLookup : scan.price
        )

        if let index = sessionScans.firstIndex(where: { $0.id == scan.id }) {
            sessionScans[index] = replacement
        }
        if let index = recent.firstIndex(where: { $0.id == scan.id }) {
            recent[index] = replacement
        }
        if lastAdd?.id == scan.id {
            lastAdd = replacement
        }
        if scan.subject.slab == nil {
            queueFallbackPrice(
                for: scan.card,
                variant: variant,
                pokemonPrintRun: scan.pokemonPrintRun,
                catalogLookup: correctedLookup
            )
        }
        if pendingGradedVariantCorrection?.scanID == scan.id {
            pendingGradedVariantCorrection = nil
        }
        feedback.choiceMade()
        return .saved
    }

    /// Applies the one-tap correction from the non-blocking graded banner. The
    /// banner stays out of the recognition eligibility gates; only this write
    /// operation is serialized.
    func chooseGradedVariant(_ variant: PhysicalVariant) {
        guard let pending = pendingGradedVariantCorrection,
              pending.options.contains(variant) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.correct(scanID: pending.scanID, to: variant)
        }
    }

    func dismissGradedVariantCorrection() {
        pendingGradedVariantCorrection = nil
    }

    // MARK: - Identification

    private func enqueueIdentification(
        _ subject: ScanSubject,
        encounterID: UUID,
        heldRepeatAuthorizationID: UUID? = nil,
        purpose capturedPurpose: ScanPurpose? = nil,
        generation capturedGeneration: Int? = nil
    ) {
        let requestPurpose = capturedPurpose ?? purpose
        let requestGeneration = capturedGeneration ?? scanGeneration
        let encounter = ScanEncounter(
            encounterID: encounterID,
            subject: subject,
            generation: requestGeneration,
            heldRepeatAuthorizationID: heldRepeatAuthorizationID
        )
        let request = ScanRequest(
            subject: encounter.subject,
            purpose: requestPurpose,
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
            self.finishIdentificationRequest(request.id)
        }
    }

    /// User answers to a finish, print-run, or catalog-choice bar become part
    /// of the same ordered pipeline as automatic recognition. In particular, a
    /// later OCR confirmation cannot make a duplicate decision while this task
    /// is waiting for the writer's background transaction.
    private func beginPendingResolution(
        requestID: UUID,
        operation: @escaping () async -> Void
    ) {
        guard !isProcessingIdentification else { return }
        isProcessingIdentification = true
        activeIdentificationRequestID = requestID
        identificationTask = Task { @MainActor [weak self] in
            await operation()
            self?.finishIdentificationRequest(requestID)
        }
    }

    private func finishIdentificationRequest(_ requestID: UUID) {
        guard activeIdentificationRequestID == requestID else { return }
        isProcessingIdentification = false
        identificationTask = nil
        activeIdentificationRequestID = nil
        // A choice is cleared before its operation begins. If that operation
        // fails, there is no prompt left to keep the camera paused; resume at
        // the single pipeline boundary unless another terminal presentation
        // (Price Check or duplicate confirmation) still owns the screen.
        resumeRecognitionIfPossible()
        drainDeferredHeldDuplicateOfferIfPossible()
        processNextIdentificationIfPossible()
    }

    private func identify(_ request: ScanRequest) async {
        beginIdentification()
        defer { endIdentification() }
        let resolution: CardCatalog.CatalogResolution
        do {
            let catalogID = PerformanceSignpost.makeID()
            let catalogState = PerformanceSignpost.beginInterval(
                "catalogResolution",
                id: catalogID,
                "encounter=\(request.encounterID.uuidString)"
            )
            defer {
                PerformanceSignpost.endInterval(
                    "catalogResolution",
                    catalogState,
                    "encounter=\(request.encounterID.uuidString)"
                )
            }
            resolution = try await catalog.resolution(for: request.identifier)
        } catch let error as PokemonHistoricalCatalogError {
            guard !Task.isCancelled, isCurrent(request) else {
                endOneCardScan(encounterID: request.encounterID, outcome: "cancelled")
                return
            }
            handleHistoricalResolution(error, request: request)
            return
        } catch {
            guard !Task.isCancelled, isCurrent(request) else {
                endOneCardScan(encounterID: request.encounterID, outcome: "cancelled")
                return
            }
            handleLookupFailure(request, error)
            return
        }

        let card = resolution.card
        guard !Task.isCancelled, isCurrent(request) else {
            endOneCardScan(encounterID: request.encounterID, outcome: "cancelled")
            return
        }
        if catalogMissVerification?.suppressionKey == request.subject.suppressionKey {
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
        await resolvePrintRun(
            for: request,
            card: card,
            catalogRetrievedAt: resolution.retrievedAt,
            labelPrintRun: request.subject.slab?.printedPrintRun
        )
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

    private func resolvePrintRun(
        for request: ScanRequest,
        card: IdentifiedCard,
        catalogRetrievedAt: Date,
        labelPrintRun: PokemonPrintRun? = nil
    ) async {
        guard isCurrent(request) else {
            endOneCardScan(encounterID: request.encounterID, outcome: "cancelled")
            return
        }

        // A slab label is allowed to commit without a print-run prompt. If the
        // label supplied a run, use it now; if it did not, the graded path still
        // proceeds with nil rather than pausing the camera behind a raw-card
        // question.
        if let slab = request.subject.slab {
            let validatedPrintRun: PokemonPrintRun? = {
                guard let labelPrintRun,
                      card.game == .pokemon else { return nil }
                let catalogRuns = PokemonMasterSetDefinition.printRuns(
                    forSetProviderID: card.variantEvidence.setID
                )
                return catalogRuns.contains(labelPrintRun) ? labelPrintRun : nil
            }()
            let gradedOutcome = await gradedResolver.resolve(
                card: card,
                slab: slab,
                pokemonPrintRun: validatedPrintRun
            )
            guard !Task.isCancelled, isCurrent(request) else {
                endOneCardScan(encounterID: request.encounterID, outcome: "cancelled")
                return
            }
            scannedGradedOutcomes[request.id] = gradedOutcome
            await resolveVariant(
                for: request,
                card: card,
                pokemonPrintRun: validatedPrintRun,
                catalogRetrievedAt: catalogRetrievedAt
            )
            return
        }

        let options = card.game == .pokemon
            ? PokemonMasterSetDefinition.printRuns(forSetProviderID: card.variantEvidence.setID)
            : []
        guard !options.isEmpty else {
            await resolveVariant(
                for: request,
                card: card,
                pokemonPrintRun: nil,
                catalogRetrievedAt: catalogRetrievedAt
            )
            return
        }

        receipt = nil
        receiptTask?.cancel()
        pendingPrintRunChoice = PendingPrintRunChoice(
            request: request,
            card: card,
            options: options,
            catalogRetrievedAt: catalogRetrievedAt
        )
        scanner.pauseRecognition()
        feedback.needsChoice()
    }

    private func resolveVariant(
        for request: ScanRequest,
        card: IdentifiedCard,
        pokemonPrintRun: PokemonPrintRun?,
        catalogRetrievedAt: Date
    ) async {
        guard isCurrent(request) else {
            endOneCardScan(encounterID: request.encounterID, outcome: "cancelled")
            return
        }
        // The print run question was just answered, and TCGdex reports 1st
        // Edition as a finish as well as a run. Left in, it comes straight back
        // as a second bar naming the same edition the user already tapped.
        var evidence = card.variantEvidence
        if pokemonPrintRun != nil {
            evidence = evidence.excludingFirstEditionPseudoFinish()
        }

        switch VariantResolver.resolve(
            evidence,
            finishLock: finishLocks[card.game],
            printedFinish: request.subject.slab?.printedFinish
        ) {
        case let .resolved(resolved):
            await route(
                ResolvedScan(
                    request: request,
                    card: card,
                    resolved: resolved,
                    pokemonPrintRun: pokemonPrintRun,
                    options: VariantResolver.options(for: evidence),
                    catalogRetrievedAt: catalogRetrievedAt
                )
            )

        case let .needsChoice(options, lockDidNotApply):
            if request.subject.slab != nil {
                // The catalog and label could not agree on a unique finish. A
                // graded slab must still commit immediately; the banner offers
                // the same options later without pausing recognition.
                await route(
                    ResolvedScan(
                        request: request,
                        card: card,
                        resolved: ResolvedVariant(
                            variant: nil,
                            resolution: .catalogSilent
                        ),
                        pokemonPrintRun: pokemonPrintRun,
                        options: options,
                        catalogRetrievedAt: catalogRetrievedAt
                    )
                )
                return
            }
            receipt = nil
            receiptTask?.cancel()
            pendingChoice = PendingVariantChoice(
                request: request,
                card: card,
                options: options,
                pokemonPrintRun: pokemonPrintRun,
                catalogRetrievedAt: catalogRetrievedAt,
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

    private func route(_ resolvedScan: ResolvedScan) async {
        guard isCurrent(resolvedScan.request) else {
            endOneCardScan(
                encounterID: resolvedScan.request.encounterID,
                outcome: "cancelled"
            )
            return
        }
        var resolvedScan = resolvedScan
        if resolvedScan.gradedOutcome == nil {
            resolvedScan.gradedOutcome = scannedGradedOutcomes.removeValue(forKey: resolvedScan.request.id)
        } else {
            scannedGradedOutcomes.removeValue(forKey: resolvedScan.request.id)
        }
        switch resolvedScan.request.purpose {
        case .collection:
            await routeCollectionCandidate(CollectionCommitCandidate(resolvedScan: resolvedScan))
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
            subject: candidate.subject,
            card: candidate.card,
            resolved: candidate.resolved,
            pokemonPrintRun: candidate.pokemonPrintRun,
            catalogRetrievedAt: candidate.catalogRetrievedAt,
            options: candidate.options,
            mutation: mutation,
            price: candidate.price
        )
        let committed = CommittedSessionScan(
            id: scan.id,
            identity: candidate.identity,
            presentationToken: UUID(),
            encounterID: candidate.encounterID
        )

        // Both are projections of the same successful store mutation. The full
        // session list is kept for review and accounting; only the rail is capped.
        sessionScans.insert(scan, at: 0)
        recent.insert(scan, at: 0)
        if recent.count > Self.recentScanLimit {
            recent.removeLast(recent.count - Self.recentScanLimit)
        }
        committedSessionHistory.append(committed)
        if committedSessionHistory.count > Self.committedHistoryLimit {
            committedSessionHistory.removeFirst(
                committedSessionHistory.count - Self.committedHistoryLimit
            )
        }

        if candidate.subject.slab != nil,
           candidate.resolved.resolution == .catalogSilent,
           !candidate.options.isEmpty {
            pendingGradedVariantCorrection = PendingGradedVariantCorrection(
                scanID: scan.id,
                card: candidate.card,
                cardName: candidate.card.name,
                options: candidate.options
            )
        }

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
        // A newer OCR confirmation may already be waiting while this write is
        // finishing. Do not erase that newer acknowledgement when the older
        // card becomes durable.
        clearAcknowledgement(for: candidate.encounterID)
        scanner.acceptedPresentation(
            encounterID: candidate.encounterID,
            presentationToken: committed.presentationToken
        )
        successCount += 1
        PerformanceSignpost.emitEvent("successUIPublication", candidate.encounterID.uuidString)
        endOneCardScan(encounterID: candidate.encounterID, outcome: "success")

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
                variantLabel: [
                    candidate.subject.slab.map {
                        $0.grade.display(company: $0.company)
                    },
                    candidate.pokemonPrintRun?.label,
                    candidate.subject.slab == nil
                        ? candidate.card.finishAndTreatmentDisplayLabel(for: candidate.resolved.variant)
                        : nil
                ]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                treatmentDiagnostics: candidate.card.magicTreatmentDiagnostics,
                thumbnailURL: scan.thumbnailURL,
                price: candidate.price,
                resolution: candidate.resolved.resolution
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
              let scan = sessionScans.first(where: { $0.id == committed.id }),
              scan.subject.suppressionKey == deferred.subject.suppressionKey else {
            return
        }

        deferredHeldDuplicateOffer = nil
        publishHeldDuplicateOffer(
            for: deferred.subject,
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
    private func routeCollectionCandidate(_ candidate: CollectionCommitCandidate) async {
        if let authorizationID = candidate.heldRepeatAuthorizationID {
            await routeHeldRepeatCandidate(candidate, authorizationID: authorizationID)
            return
        }

        let decision = CollectionCandidateRoutingPolicy.decision(
            for: candidate.identity,
            previous: committedSessionHistory.last,
            history: committedSessionHistory,
            proofs: spatialResetProofs
        )

        switch decision {
        case .automatic:
            diagnostic("routingAutomatic")
            guard await commitAuthorizedCollectionCandidate(candidate, authorization: .automatic) else { return }
            // A candidate may have exited before its successful commit. Keep
            // only that candidate's proof and discard evidence belonging to
            // older or unrelated presentations.
            spatialResetProofs.removeAll { $0.encounterID != candidate.encounterID }
        case .suppress:
            diagnostic("routingSuppressed")
            deferredHeldDuplicateOffer = nil
            scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
            endOneCardScan(encounterID: candidate.encounterID, outcome: "suppressed")
            spatialResetProofs.removeAll()
        case .duplicate(let proof):
            diagnostic("routingSpatialDuplicatePrompt")
            guard let previous = committedSessionHistory.reversed().first(where: { committed in
                      committed.identity == candidate.identity
                          && (proof.presentationToken == committed.presentationToken
                              || (proof.presentationToken == nil
                                  && proof.encounterID == committed.encounterID))
                  }),
                  let proofIndex = spatialResetProofs.firstIndex(where: { $0.id == proof.id }) else {
                scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
                endOneCardScan(encounterID: candidate.encounterID, outcome: "duplicate-proof-missing")
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
    ) async {
        guard let state = heldRepeatAuthorizationState,
              state.authorization.id == authorizationID,
              state.wasConsumedByEncounter,
              candidate.subject.suppressionKey == state.offer.suppressionKey,
              let previous = committedSessionHistory.first(where: {
                  $0.id == state.offer.previousScanID
              }),
              previous.presentationToken == state.offer.previousPresentationToken else {
            clearHeldRepeatState()
            scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
            endOneCardScan(encounterID: candidate.encounterID, outcome: "held-repeat-rejected")
            diagnostic("routingHeldRepeatRejected")
            return
        }

        guard candidate.identity == state.offer.identity else {
            // The user's permit was for a different resolved card. It cannot
            // authorize this candidate, but this candidate still follows the
            // ordinary identity-first rules.
            clearHeldRepeatState()
            scanner.keepPresentationSuppressed(encounterID: candidate.encounterID)
            endOneCardScan(encounterID: candidate.encounterID, outcome: "held-repeat-mismatch")
            diagnostic("routingHeldRepeatIdentityMismatch")
            return
        }

        heldRepeatAuthorizationState = nil
        heldDuplicateOffer = nil

        guard await commitAuthorizedCollectionCandidate(candidate, authorization: .heldRepeat) else {
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
    ) async -> Bool {
        guard let collectionWriter else {
            if !failAcknowledgement(
                for: candidate.encounterID,
                message: "This card was recognized but could not be added. Try again."
            ) {
                show(
                    ScanNote(
                        text: "This card was recognized but could not be added. Try again.",
                        tone: .problem
                    )
                )
            }
            return false
        }

        let writeSessionID = scannerSessionID
        scanAcknowledgement = ScanAcknowledgement(
            encounterID: candidate.encounterID,
            subject: candidate.subject,
            phase: .recognized,
            message: "Saving to your collection…"
        )
        beginTrackedWrite(for: writeSessionID)
        defer { endTrackedWrite(for: writeSessionID) }

        do {
            let mutation = try await collectionWriter.add(candidate)
            guard writeSessionID == scannerSessionID else { return false }

            if mutation.wasDuplicate {
                show(ScanNote(text: "This certified card is already in your collection", tone: .info))
                clearAcknowledgement(for: candidate.encounterID)
                if pendingChoice?.request.id == candidate.requestID {
                    pendingChoice = nil
                }
                resumeRecognitionIfPossible()
                endOneCardScan(encounterID: candidate.encounterID, outcome: "certified-duplicate")
                diagnostic("certifiedDuplicateNoOp")
                return true
            }

            if let slab = candidate.subject.slab {
                if let outcome = candidate.gradedOutcome {
                    let message: String?
                    switch outcome {
                    case .bound:
                        message = nil
                    case .unpricedGrade:
                        message = "\(slab.grade.display(company: slab.company)) added — no graded price published"
                    case .unmatchedProduct:
                        message = "\(slab.grade.display(company: slab.company)) added — no vendor match"
                    case .unavailable:
                        message = "\(slab.grade.display(company: slab.company)) added — price pending"
                    }
                    if let message {
                        show(ScanNote(text: message, tone: .info))
                    }
                }
            }
            if pendingChoice?.request.id == candidate.requestID {
                pendingChoice = nil
            }
            appendCommittedScan(candidate, mutation: mutation)
            if candidate.subject.slab == nil {
                queueFallbackPrice(
                    for: candidate.card,
                    variant: candidate.resolved.variant,
                    pokemonPrintRun: candidate.pokemonPrintRun,
                    catalogLookup: candidate.price
                )
            }
            resumeRecognitionIfPossible()
            diagnostic(candidate.subject.slab == nil ? "collectionCommit" : "gradedCollectionCommit")
            return true
        } catch {
            guard writeSessionID == scannerSessionID else { return false }
            if !failAcknowledgement(
                for: candidate.encounterID,
                message: "This card was recognized but was not added. Try again."
            ) {
                show(
                    ScanNote(
                        text: "This card was recognized but was not added. Try again.",
                        tone: .problem
                    )
                )
            }
            feedback.problem()
            return false
        }
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
              let modelContainer,
              PriceVendorCredentials.hasKey else { return }

        let printingID = pokemonPrintRun.map { "\(card.providerID)@\($0.rawValue)" }
            ?? card.providerID
        let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: card.magicTreatments(for: variant)
        )
        let key = PriceRecord.key(
            game: card.game,
            printingID: printingID,
            variantID: variant?.id,
            treatmentIDs: treatmentIDs
        )
        let sessionID = scannerSessionID
        let interestedScanIDs = Set(
            sessionScans
                .filter { fallbackPriceKey(for: $0) == key }
                .map(\.id)
        )
        if fallbackQuoteTasks[key] != nil {
            fallbackQuoteScanIDs[key, default: [:]][sessionID, default: []]
                .formUnion(interestedScanIDs)
            return
        }
        fallbackQuoteScanIDs[key] = [sessionID: interestedScanIDs]

        // Price Check/fallback writes are independent of the scanner's main
        // context. The identity is a value snapshot, so no SwiftData model is
        // retained while the paced vendor request is in flight.
        let fallbackContext = ModelContext(modelContainer)
        let fallbackPrices = PriceStore(context: fallbackContext)
        let resolver = PriceFallbackQuoteResolver(context: fallbackContext)
        let task = Task { @MainActor [weak self] in
            defer {
                self?.fallbackQuoteTasks[key] = nil
                self?.fallbackQuoteScanIDs[key] = nil
            }
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
                    variantID: variant?.id,
                    treatmentIDs: treatmentIDs
                )
                let marketVariantID = ProductIdentityStore(context: fallbackContext)
                    .cachedVariantID(forKey: identityKey)
                guard fallbackPrices.store(
                    quote,
                    game: card.game,
                    printingID: printingID,
                    variantID: variant?.id,
                    marketVariantID: marketVariantID,
                    treatmentIDs: treatmentIDs
                ) else { return }
                guard fallbackPrices.save(),
                      let self else { return }
                self.applyFallbackQuote(
                    quote,
                    priceKey: key,
                    scanIDsBySession: self.fallbackQuoteScanIDs[key] ?? [:]
                )
            case .failed:
                break
            }
        }
        fallbackQuoteTasks[key] = task
    }

    private func fallbackPriceKey(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) -> String {
        let printingID = pokemonPrintRun.map { "\(card.providerID)@\($0.rawValue)" }
            ?? card.providerID
        let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: card.magicTreatments(for: variant)
        )
        return PriceRecord.key(
            game: card.game,
            printingID: printingID,
            variantID: variant?.id,
            treatmentIDs: treatmentIDs
        )
    }

    private func fallbackPriceKey(for scan: RecentScan) -> String {
        fallbackPriceKey(
            for: scan.card,
            variant: scan.resolved.variant,
            pokemonPrintRun: scan.pokemonPrintRun
        )
    }

    private func applyFallbackQuote(
        _ quote: PriceLookup,
        priceKey: String,
        scanIDsBySession: [UUID: Set<UUID>]
    ) {
        let scanIDs = scanIDsBySession[scannerSessionID] ?? []
        guard !scanIDs.isEmpty else { return }

        // Diagnostic only: this loop scans every card added this session, and
        // fires once per JustTCG fallback price response — not a rare event.
        // The metadata carries `sessionScans`' size so an Instruments trace can
        // show whether this operation's cost grows with session length.
        let applyFallbackQuoteState = PerformanceSignpost.beginInterval(
            "applyFallbackQuoteScan",
            id: PerformanceSignpost.makeID(),
            "sessionScans=\(sessionScans.count)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "applyFallbackQuoteScan",
                applyFallbackQuoteState,
                "sessionScans=\(sessionScans.count)"
            )
        }

        var updatedScanIDs = Set<UUID>()
        for index in sessionScans.indices {
            let scan = sessionScans[index]
            guard scanIDs.contains(scan.id),
                  fallbackPriceKey(for: scan) == priceKey else { continue }

            let replacement = scan.updating(price: quote)
            sessionScans[index] = replacement
            if let recentIndex = recent.firstIndex(where: { $0.id == scan.id }) {
                recent[recentIndex] = replacement
            }
            if lastAdd?.id == scan.id {
                lastAdd = replacement
            }
            updatedScanIDs.insert(scan.id)
        }

        // A fallback answer is a projection correction, not a new scanner add.
        // Keep the existing receipt identity and timer, and never recreate a
        // scan that was undone while the request was in flight.
        if let currentReceipt = receipt,
           updatedScanIDs.contains(currentReceipt.scanID) {
            receipt = currentReceipt.updating(price: quote)
        }
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
        guard let priceCheckCoordinator, isCurrent(resolvedScan.request) else {
            endOneCardScan(
                encounterID: resolvedScan.request.encounterID,
                outcome: "cancelled"
            )
            return
        }
        cancelPriceCheckRefresh()
        pendingChoice = nil
        pendingPrintRunChoice = nil
        pendingIdentityChoice = nil
        recognitionEligibility.isBlockedByPresentation = true
        scanner.pauseRecognition()
        let result = priceCheckCoordinator.present(resolvedScan)
        presentedPriceCheckSubject = resolvedScan.request.subject
        priceCheckResult = result
        PerformanceSignpost.emitEvent("successUIPublication", "price-check \(resolvedScan.request.encounterID.uuidString)")
        endOneCardScan(encounterID: resolvedScan.request.encounterID, outcome: "price-check")
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
                // A published exact miss is card evidence. Configuration,
                // allowance, rate-limit, and transport outcomes are not, so
                // they must not write a ReferenceQuote failure timestamp.
                if issue == .noExactPrice {
                    priceCheckCoordinator.recordRefreshFailure(for: latest)
                }
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
        case .notMatched: return .notMatched
        case .unsupportedFinish: return .unsupportedFinish
        case .unsupportedTreatment: return .unsupportedTreatment
        case .gradedGradeNotPriced: return .gradedGradeNotPriced
        case .gradedProductNotMatched: return .gradedProductNotMatched
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
        guard recognitionEligibility.allowsRecognition,
              priceCheckResult == nil else { return }
        guard pendingChoice == nil,
              pendingPrintRunChoice == nil,
              pendingIdentityChoice == nil,
              pendingDuplicateConfirmation == nil else { return }
        scanner.resumeRecognition()
    }

    private func isCurrent(_ request: ScanRequest) -> Bool {
        request.generation == scanGeneration
    }

    private func observeCatalogMissVerification(_ subject: ScanSubject) {
        guard var verification = catalogMissVerification,
              verification.suppressionKey == subject.suppressionKey else { return }

        guard !verification.window.observe(subject) else {
            catalogMissVerification = nil
            unresolvedScans = UnresolvedScan.merging(unresolvedScans, with: subject)
            show(
                ScanNote(
                    text: "Still can't confirm \(subject.displayIdentifier) — set it aside",
                    tone: .problem
                )
            )
            return
        }
        catalogMissVerification = verification
    }

    private func handleLookupFailure(_ request: ScanRequest, _ error: Error) {
        let subject = request.subject
        if request.purpose == .collection {
            failAcknowledgement(
                for: request.encounterID,
                message: "This card was recognized but was not added. Try again."
            )
        } else {
            endOneCardScan(encounterID: request.encounterID, outcome: "price-check-failure")
        }
        feedback.problem()

        switch CardCatalog.classify(error) {
        case .transient:
            // Nothing is known to be wrong with the card, so let the very next
            // reading through instead of making the user re-present it.
            scanner.allowImmediateRetry()
            show(ScanNote(text: "Lookup failed — keep the card in the box", tone: .problem))

        case .providerUnavailable:
            // A held card must remain latched while the provider circuit cools.
            // Releasing it here would turn one outage into an unbounded stream
            // of requests and haptics from the same physical card.
            show(ScanNote(text: "Magic lookup is temporarily unavailable — try again later", tone: .problem))

        case .notInCatalog:
            // The first deterministic miss is not enough to file a card: a
            // transient OCR/catalog boundary can still have produced the same
            // resolved identifier. The latch remains engaged while a fresh
            // three-of-five suppression-key window verifies the physical card.
            if catalogMissVerification?.suppressionKey != subject.suppressionKey {
                catalogMissVerification = CatalogMissVerification(
                    suppressionKey: subject.suppressionKey
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

    private func clearAcknowledgement(for encounterID: UUID) {
        guard scanAcknowledgement?.encounterID == encounterID else { return }
        scanAcknowledgement = nil
    }

    private func endOneCardScan(encounterID: UUID, outcome: String) {
        guard let state = oneCardScanIntervals.removeValue(forKey: encounterID) else { return }
        // `sessionScans.count` here is this card's position in the current
        // session. Plotting this interval's duration against that count across
        // one long session is the decisive test for whether per-card scan cost
        // grows with how long the session has run.
        PerformanceSignpost.endInterval(
            "oneCardScan",
            state,
            "encounter=\(encounterID.uuidString) outcome=\(outcome) sessionScans=\(sessionScans.count)"
        )
    }

    @discardableResult
    private func failAcknowledgement(for encounterID: UUID, message: String) -> Bool {
        endOneCardScan(encounterID: encounterID, outcome: "failure")
        guard let acknowledgement = scanAcknowledgement,
              acknowledgement.encounterID == encounterID else { return false }
        scanAcknowledgement = ScanAcknowledgement(
            encounterID: encounterID,
            subject: acknowledgement.subject,
            phase: .failed,
            message: message
        )
        diagnostic("recognitionAcknowledgementFailed")
        return true
    }

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

#if DEBUG
    /// Seeds the deterministic `WholeCardScanner` route with a receipt so the
    /// bottom card can be captured without a camera. The values are the layout's
    /// hard case on purpose: a long name, a full identifier line, and a priced
    /// printing all competing for one row.
    func seedReceiptFixtureForScreenshot() {
        let isTrustReceipt = ProcessInfo.processInfo.arguments.contains("TrustScanReceipt")
        let resolution = isTrustReceipt ? PortfolioDebugFixtures.debugResolution() : nil
        let variantLabel: String
        switch resolution {
        case .catalogSilent?:
            variantLabel = "Unknown finish"
        case .finishLock?:
            variantLabel = "Reverse Holo"
        case .userConfirmed?:
            variantLabel = "Holofoil"
        case .uniqueInCatalog?, .deterministicSetRule?, .printedLabel?:
            variantLabel = "Holofoil"
        case .imported?:
            variantLabel = "Normal"
        case nil:
            variantLabel = "Foil Etched"
        }
        receipt = ScanReceipt(
            scanID: UUID(),
            name: "Ragavan, Nimble Pilferer",
            identifier: "MH2 · 138",
            variantLabel: variantLabel,
            treatmentDiagnostics: [],
            thumbnailURL: nil,
            price: .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 62.47,
                    currencyCode: "USD",
                    source: .tcgplayer,
                    sourceVariantID: "foil-etched",
                    sourceUpdatedAt: .now,
                    fetchedAt: .now
                )
            ),
            resolution: resolution
        )
    }

    /// Replays the reported path for the deterministic UI harness: a card was
    /// recognized, a finish choice appeared, and the person cancelled it. The
    /// screenshot settles after `dismissChoice()` so the harness proves that a
    /// cancelled scan does not leave the collection-saving acknowledgement up.
    func seedVariantChoiceCancellationFixtureForScreenshot() {
        let encounterID = UUID()
        let identifier = ScanIdentifier.pokemon(
            setCode: "TST",
            cardNumber: "078",
            printedTotal: 109,
            setDefinition: PokemonSetDefinition(
                printedCode: "TST",
                tcgdexSetID: "debug-set",
                officialCount: 109,
                releaseIndex: 0
            )
        )
        let subject = ScanSubject(identifier: identifier)
        let card = IdentifiedCard.pokemon(
            TCGdexCard(
                id: "debug-set-078",
                localId: "078",
                name: "Debug Variant Card",
                image: nil,
                rarity: "Rare",
                set: TCGdexSetBrief(
                    id: "debug-set",
                    name: "Debug Set",
                    cardCount: TCGdexCardCount(total: 109, official: 109)
                ),
                variants: TCGdexVariants(
                    firstEdition: false,
                    holo: true,
                    normal: true,
                    reverse: false,
                    wPromo: nil
                ),
                pricing: nil,
                variantsDetailed: nil
            ),
            setCode: "TST"
        )
        let request = ScanRequest(
            subject: subject,
            purpose: .collection,
            generation: scanGeneration,
            encounterID: encounterID
        )
        pendingChoice = PendingVariantChoice(
            request: request,
            card: card,
            options: [.normal, .holo],
            pokemonPrintRun: nil,
            catalogRetrievedAt: .now,
            lockDidNotApply: nil
        )
        scanAcknowledgement = ScanAcknowledgement(
            encounterID: encounterID,
            subject: subject,
            phase: .recognized,
            message: "Saving to your collection…"
        )
        scanner.pauseRecognition()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.dismissChoice()
        }
    }
#endif

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
            self.installMagicDefinitions(definitions)
        }
    }
}
