import Foundation

/// How a physical token's identity was established.
///
/// A third provenance fact beside `identityResolution` (how the face was read)
/// and `variantResolution` (how the finish was chosen). Stored so that a
/// coverage claim later found to be wrong can be traced to every row that
/// leaned on it, without disturbing the rows a person decided.
enum MagicTokenPairingBasis: String, Codable, Hashable, Sendable {
    /// A coverage-complete catalog lists exactly one card with this face.
    case uniqueFace
    /// Both faces were read and exactly one catalogued card carries both.
    case bothFacesCatalogued
    /// The person picked the card from the catalog's candidates.
    case userChoseCandidate
    /// The person said the back carries no token.
    case userDeclaredSingleFaced
    /// Both faces were read, no catalogued card carries both, and the person
    /// confirmed they are one card.
    case userConfirmedObservedPair
}

/// One physical token card to record. Finish resolution follows, unchanged.
struct MagicTokenAcquisition: Equatable, Sendable {
    let key: MagicPhysicalTokenKey
    /// The catalogued card, when there is one. Nil means the cardboard is known
    /// only from what was read and what the person confirmed, so there is no
    /// listing to price it from.
    let product: MagicPhysicalToken?
    let basis: MagicTokenPairingBasis
}

/// "Flip it." One face was read and it does not decide the card.
struct MagicTokenReverseQuestion: Equatable, Sendable {
    let face: MagicTokenFaceID
    /// Catalogued cards carrying the face, in key order. Shown as tap targets,
    /// so the person sees what the scanner already knows.
    let candidates: [MagicPhysicalToken]
    /// Whether the candidates are every possibility.
    let catalogIsExhaustive: Bool

    /// The backs the catalog knows about, one per double-sided candidate.
    var knownBacks: [MagicTokenFace] {
        candidates.compactMap { $0.reverse(of: face) }
    }

    /// The single-sided printing of this face, when the catalog lists one.
    var singleFacedCandidate: MagicPhysicalToken? {
        candidates.first { !$0.isDoubleFaced }
    }

    /// Whether "no token on the back" is a possible answer. Never offered when
    /// a complete catalog says every printing of this face is double-sided:
    /// that would invite recording something that does not exist.
    var allowsSingleFaced: Bool {
        !catalogIsExhaustive || singleFacedCandidate != nil
    }
}

/// "Same card?" Two faces were read back to back and nothing catalogued
/// carries both. Only a person can say whether they were one card.
struct MagicTokenPairConfirmation: Equatable, Sendable {
    let face: MagicTokenFaceID
    let reverse: MagicTokenFaceID
}

/// A face that was read but not added. It belongs in Needs Attention with
/// everything that was learned, so retrying never starts from nothing.
struct MagicTokenParkedFace: Equatable, Sendable {
    let face: MagicTokenFaceID
    let candidates: [MagicPhysicalToken]
    /// A second face read while the question was open but never confirmed as
    /// the back. Kept on the same entry so one card never becomes two rows.
    let unconfirmedReverse: MagicTokenFaceID?
}

/// Turns confirmed token-face readings into physical token cards.
///
/// It sits after the card latch and the catalog face lookup, and before the
/// add. It exists because the latch's unit is a printed identifier while a
/// double-sided token is one object with two of them:
///
/// - Flipping a recorded token over to look at it must never add it again.
/// - Flipping an undecided token over is the answer to "which card is this?",
///   not a new card — even though the band empties while it turns.
/// - A different card arriving while that question is open means the person
///   moved on. The question is parked with what it learned, and nothing is
///   added on its behalf.
///
/// The scanner never pauses for the flip. The answer is the other side of the
/// card, so recognition has to keep running to read it.
struct MagicTokenPairingSession: Sendable {
    enum Event: Equatable, Sendable {
        /// The latch confirmed a token face and the catalog resolved its face.
        case faceConfirmed(MagicTokenFaceID)
        /// Something that is not a token face confirmed: an ordinary card,
        /// another game. The latch has released whatever came before it.
        case otherCardConfirmed
        /// The band has been empty long enough for the latch to release.
        case bandCleared
        /// Taps on the open question.
        case choseCandidate(MagicPhysicalTokenKey)
        case declaredSingleFaced
        case confirmedPair
        case rejectedPair
        case skipped
    }

    enum Effect: Equatable, Sendable {
        /// Record this physical card.
        case add(MagicTokenAcquisition)
        /// Show the flip prompt.
        case askForReverse(MagicTokenReverseQuestion)
        /// Ask whether two faces read back to back are one card.
        case confirmPair(MagicTokenPairConfirmation)
        /// This reading is the card just recorded, seen from its other side.
        /// Nothing is added; the scanner may say so quietly.
        case sameCard(MagicPhysicalTokenKey)
        /// Keep this face in Needs Attention. Nothing is added.
        case park(MagicTokenParkedFace)
        /// Clear whatever prompt is showing.
        case dismissPrompt
    }

    private enum State: Equatable, Sendable {
        case idle
        /// A card was just recorded. `lastSeen` is the face most recently read
        /// from it; `inBand` is false once the latch has seen the band empty.
        case holding(MagicPhysicalTokenKey, lastSeen: MagicTokenFaceID, inBand: Bool)
        case awaitingReverse(MagicTokenReverseQuestion)
        case confirmingPair(MagicTokenReverseQuestion, reverse: MagicTokenFaceID)
    }

    let catalog: MagicTokenProductCatalog
    private var state: State = .idle

    init(catalog: MagicTokenProductCatalog) {
        self.catalog = catalog
    }

    /// The open flip question, if any.
    var pendingQuestion: MagicTokenReverseQuestion? {
        switch state {
        case let .awaitingReverse(question), let .confirmingPair(question, _): return question
        case .idle, .holding: return nil
        }
    }

    /// The open "same card?" question, if any.
    var pendingPairConfirmation: MagicTokenPairConfirmation? {
        guard case let .confirmingPair(question, reverse) = state else { return nil }
        return MagicTokenPairConfirmation(face: question.face, reverse: reverse)
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case let .faceConfirmed(face): return faceConfirmed(face)
        case .otherCardConfirmed: return otherCardConfirmed()
        case .bandCleared: bandCleared(); return []
        case let .choseCandidate(key): return choseCandidate(key)
        case .declaredSingleFaced: return declaredSingleFaced()
        case .confirmedPair: return confirmedPair()
        case .rejectedPair: return rejectedPair()
        case .skipped: return parkOpenQuestion()
        }
    }

    // MARK: - Readings

    private mutating func faceConfirmed(_ face: MagicTokenFaceID) -> [Effect] {
        switch state {
        case .idle:
            return begin(face)

        case let .holding(key, lastSeen, inBand):
            guard key.contains(face) else { return begin(face) }
            if face != lastSeen {
                // The other side of the card just recorded. Turning a card over
                // empties the band, so this holds whether or not it did — a
                // flip must never be counted as a second copy.
                state = .holding(key, lastSeen: face, inBand: true)
                return [.sameCard(key)]
            }
            // The same side again. While it never left, that is the latch's
            // business. After the band emptied it is the existing rule for any
            // card: the first copy left, so this is another one.
            return inBand ? [] : begin(face)

        case let .awaitingReverse(question):
            guard face != question.face else { return [] }
            switch catalog.resolve(face: question.face, reverse: face) {
            case let .resolved(product):
                return [.dismissPrompt]
                    + record(product.key, product: product, basis: .bothFacesCatalogued, lastSeen: face)
            case .uncataloguedPair:
                state = .confirmingPair(question, reverse: face)
                return [.confirmPair(MagicTokenPairConfirmation(face: question.face, reverse: face))]
            case .differentCards:
                return parkOpenQuestion() + begin(face)
            case .sameFace:
                return []
            }

        case let .confirmingPair(question, reverse):
            // Turning the card back and forth while deciding is not an answer.
            guard face != question.face, face != reverse else { return [] }
            return parkOpenQuestion() + begin(face)
        }
    }

    private mutating func otherCardConfirmed() -> [Effect] {
        switch state {
        case .idle:
            return []
        case .holding:
            state = .idle
            return []
        case .awaitingReverse, .confirmingPair:
            return parkOpenQuestion()
        }
    }

    private mutating func bandCleared() {
        // An open question survives an empty band: that is what a flip looks
        // like from the camera.
        guard case let .holding(key, lastSeen, _) = state else { return }
        state = .holding(key, lastSeen: lastSeen, inBand: false)
    }

    // MARK: - Answers

    private mutating func choseCandidate(_ key: MagicPhysicalTokenKey) -> [Effect] {
        // Offered only on the flip prompt. Once a back has been read, picking a
        // card that does not carry it would overrule what the camera saw.
        guard case let .awaitingReverse(question) = state,
              let product = question.candidates.first(where: { $0.key == key }) else { return [] }
        return [.dismissPrompt]
            + record(product.key, product: product, basis: .userChoseCandidate, lastSeen: question.face)
    }

    private mutating func declaredSingleFaced() -> [Effect] {
        guard case let .awaitingReverse(question) = state, question.allowsSingleFaced else { return [] }
        if let single = question.singleFacedCandidate {
            return [.dismissPrompt]
                + record(single.key, product: single, basis: .userDeclaredSingleFaced, lastSeen: question.face)
        }
        guard let key = MagicPhysicalTokenKey(faces: [question.face]) else { return [] }
        return [.dismissPrompt]
            + record(key, product: nil, basis: .userDeclaredSingleFaced, lastSeen: question.face)
    }

    private mutating func confirmedPair() -> [Effect] {
        guard case let .confirmingPair(question, reverse) = state,
              let key = MagicPhysicalTokenKey(faces: [question.face, reverse]) else { return [] }
        return [.dismissPrompt]
            + record(key, product: catalog.product(for: key), basis: .userConfirmedObservedPair, lastSeen: reverse)
    }

    private mutating func rejectedPair() -> [Effect] {
        guard case let .confirmingPair(question, reverse) = state else { return [] }
        // Two cards. The first question is parked on its own and the second
        // face starts fresh, exactly as if it had arrived after a skip.
        state = .idle
        let parked = MagicTokenParkedFace(
            face: question.face, candidates: question.candidates, unconfirmedReverse: nil
        )
        return [.dismissPrompt, .park(parked)] + begin(reverse)
    }

    // MARK: - Helpers

    private mutating func begin(_ face: MagicTokenFaceID) -> [Effect] {
        switch catalog.resolve(face: face) {
        case let .resolved(product):
            return record(product.key, product: product, basis: .uniqueFace, lastSeen: face)
        case let .needsReverse(candidates, catalogIsExhaustive):
            let question = MagicTokenReverseQuestion(
                face: face, candidates: candidates, catalogIsExhaustive: catalogIsExhaustive
            )
            state = .awaitingReverse(question)
            return [.askForReverse(question)]
        }
    }

    private mutating func record(
        _ key: MagicPhysicalTokenKey,
        product: MagicPhysicalToken?,
        basis: MagicTokenPairingBasis,
        lastSeen: MagicTokenFaceID
    ) -> [Effect] {
        state = .holding(key, lastSeen: lastSeen, inBand: true)
        return [.add(MagicTokenAcquisition(key: key, product: product, basis: basis))]
    }

    private mutating func parkOpenQuestion() -> [Effect] {
        let parked: MagicTokenParkedFace
        switch state {
        case let .awaitingReverse(question):
            parked = MagicTokenParkedFace(
                face: question.face, candidates: question.candidates, unconfirmedReverse: nil
            )
        case let .confirmingPair(question, reverse):
            parked = MagicTokenParkedFace(
                face: question.face, candidates: question.candidates, unconfirmedReverse: reverse
            )
        case .idle, .holding:
            return []
        }
        state = .idle
        return [.dismissPrompt, .park(parked)]
    }
}
