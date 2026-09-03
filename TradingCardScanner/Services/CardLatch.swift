import Foundation

/// The safety mechanism that makes automatic collection entry defensible.
///
/// The scanner reads several times a second. Without this, one Charizard resting
/// in the scan band for three seconds becomes quantity five. The latch turns the
/// stream of OCR readings back into physical events by remembering which physical
/// presentation has already been consumed:
///
///     confirmed -> engage -> every further reading of that printing does nothing
///
/// It releases only on evidence that the physical card changed — the identifier
/// stops being read for several consecutive passes, or a *different* card
/// confirms. A single stray reading is never enough, because one garbage frame
/// releasing the latch would let the card that is still sitting there be added a
/// second time.
///
/// Two identical copies back to back are deliberately not inferred optically.
/// The first copy has to leave before the second is automatically accepted; a
/// held-card offer is the separate, explicit fallback when a person chooses to
/// authorize one more copy. That trade is intentional: a missed card costs one
/// more pass, a phantom duplicate quietly corrupts a five thousand card collection.
///
/// Time is passed in rather than read so the whole thing is testable.
struct CardLatch: Equatable {
    enum Decision: Equatable {
        /// Hand this observation to the confirmation window.
        case forward(ScanIdentifier?)
        /// Hand this matching observation to the confirmation window under a
        /// user-authorized, one-shot permit. This is deliberately distinct
        /// from ordinary forwarding so admission cannot fall through to
        /// `admits` after the permit is consumed.
        case forwardAuthorized(ScanIdentifier)
        /// Same physical presentation as the one already consumed. Ignore it.
        case holdingLatch
    }

    /// Consecutive unreadable observations before the latched card is presumed
    /// gone. A different valid-looking identifier is not absence evidence: OCR
    /// can turn a slightly blurred version of the card into another plausible
    /// identifier for a few frames.
    let releaseAfterAbsences: Int
    /// How long a consumed printing must go unread before an identical reading is
    /// believed to be a second physical copy rather than the same card.
    let minimumAbsenceBeforeRelatch: TimeInterval
    /// A backstop, so nothing can be suppressed forever.
    ///
    /// Absence evidence needs an empty band, and a band is not empty while any
    /// other card is being read — so without this, a printing scanned early in a
    /// long run could never become admissible again and a genuine second copy
    /// would be refused indefinitely. Well beyond the length of a hand movement,
    /// which is what the ordinary rule is there to survive.
    let presumedGoneAfter: TimeInterval

    /// How many recently consumed printings are remembered.
    ///
    /// More than one, because a single slot is the whole duplicate bug: anything
    /// that confirms in between — a blurred frame reading a neighbouring number,
    /// or the same card whose title read differently for a moment — replaces the
    /// memory of the card that was actually added, and the card still sitting in
    /// the band walks straight back in. Nothing that briefly appears to be there
    /// can now erase what is known about the cards that were.
    ///
    /// Small on purpose: absence evidence advances every remembered printing at
    /// once, so a real gap between cards clears all of them together and this
    /// only has to span one hand movement.
    static let recentlyConsumedLimit = 6

    private(set) var latched: ScanIdentifier?
    /// Consecutive readings of the latched printing since it was consumed. Lets
    /// the UI explain the one confusing case — a second identical copy dropped in
    /// too quickly — instead of silently ignoring it.
    private(set) var heldMatchCount = 0

    private var consecutiveAbsences = 0
    private var consumed: [ConsumedPrinting] = []
    /// A user-authorized repeat is deliberately separate from `hasLeft`. It
    /// permits one expected confirmation without teaching the latch that the
    /// physical presentation exited.
    private var heldRepeatAuthorizationKey: ScanSuppressionKey?

    /// One printing that has already been counted, and what is known about
    /// whether it is still in front of the camera.
    private struct ConsumedPrinting: Equatable {
        let key: ScanSuppressionKey
        /// When this printing was last actually read. The absence is measured
        /// from here rather than from the first unreadable frame, because that is
        /// the moment the card was last known to be present — starting the clock
        /// one frame later silently demands a longer gap than configured.
        var lastSeenAt: CFAbsoluteTime
        var consecutiveAbsences = 0
        /// Sticky once set. A printing that has genuinely been away has left,
        /// whatever is read afterwards — including a second copy of itself.
        var hasLeft = false
        /// A Price Check dismissal may explicitly make this one printing
        /// checkable again. The entry remains until a matching observation
        /// arrives after this time, so an idle camera cannot accidentally
        /// release a card while its result sheet is still closing.
        var recheckEligibleAt: CFAbsoluteTime?
    }

    init(
        releaseAfterAbsences: Int = 4,
        minimumAbsenceBeforeRelatch: TimeInterval = 2.0,
        presumedGoneAfter: TimeInterval = 6.0
    ) {
        self.releaseAfterAbsences = max(1, releaseAfterAbsences)
        self.minimumAbsenceBeforeRelatch = minimumAbsenceBeforeRelatch
        self.presumedGoneAfter = presumedGoneAfter
    }

    /// - Parameter cardPresent: whether anything was legible in the scan band at
    ///   all, independent of whether it parsed into an identifier. This is the
    ///   difference between "the band is empty" and "a card is there and I cannot
    ///   read it", and the latch is wrong about duplicates without it: a card
    ///   being moved spends most of the movement in the second state, and
    ///   counting that as the card leaving is what lets the very same card be
    ///   added again the moment it comes back into focus.
    mutating func observe(
        _ observation: ScanIdentifier?,
        cardPresent: Bool = false,
        at now: CFAbsoluteTime
    ) -> Decision {
        if observation == nil, !cardPresent {
            consecutiveAbsences += 1
        } else {
            consecutiveAbsences = 0
        }

        updateConsumedPresence(with: observation, cardPresent: cardPresent, at: now)

        guard latched != nil else { return .forward(observation) }

        if let authorizedKey = heldRepeatAuthorizationKey,
           authorizedKey == latched?.suppressionKey,
           let observation,
           observation.suppressionKey == authorizedKey {
            // Keep forwarding the matching confirmation frames while the
            // permit is armed. The scanner consumes the permit only once the
            // normal two-match confirmation window succeeds.
            return .forwardAuthorized(observation)
        }

        if observation?.suppressionKey == latched?.suppressionKey {
            heldMatchCount += 1
            return .holdingLatch
        }

        // A differing reading is evidence, not proof. Forward it so the ordinary
        // confirmation window decides whether a different card is really there.
        if consecutiveAbsences >= releaseAfterAbsences {
            release()
        }
        return .forward(observation)
    }

    /// Ages every remembered printing against this observation.
    ///
    /// Only an empty band is evidence that anything left. A frame with legible
    /// text in it says a card is present — and says nothing about *which*, since
    /// a blurred card produces text that parses as nothing, or briefly as
    /// something else. Either way the band is occupied, so no remembered printing
    /// can be concluded to have gone anywhere.
    ///
    /// A reading only ever speaks for the one printing it matches.
    private mutating func updateConsumedPresence(
        with observation: ScanIdentifier?,
        cardPresent: Bool,
        at now: CFAbsoluteTime
    ) {
        let observedKey = observation?.suppressionKey

        var index = consumed.startIndex
        while index < consumed.endIndex {
            if let observedKey, consumed[index].key == observedKey {
                // This must precede the matching-read `continue`: a card held
                // still beneath a resumed Price Check sheet otherwise refreshes
                // `lastSeenAt` forever and never gets another confirmation.
                if let recheckEligibleAt = consumed[index].recheckEligibleAt,
                   now >= recheckEligibleAt {
                    let releasedKey = consumed[index].key
                    consumed.remove(at: index)
                    if latched?.suppressionKey == releasedKey {
                        release()
                    }
                    continue
                }
                consumed[index].lastSeenAt = now
                consumed[index].consecutiveAbsences = 0
                index = consumed.index(after: index)
                continue
            }

            // A frame that parsed into anything at all is a card in the band,
            // whatever the caller reported: the identifier came off a card.
            if cardPresent || observation != nil {
                consumed[index].consecutiveAbsences = 0
            } else {
                consumed[index].consecutiveAbsences += 1
            }

            let unreadFor = now - consumed[index].lastSeenAt
            let bandWentEmpty = consumed[index].consecutiveAbsences >= releaseAfterAbsences
                && unreadFor >= minimumAbsenceBeforeRelatch
            if bandWentEmpty || unreadFor >= presumedGoneAfter {
                consumed[index].hasLeft = true
            }
            index = consumed.index(after: index)
        }
    }

    /// Whether a confirmed identifier may mutate the collection right now.
    ///
    /// Time does not appear here: `observe` is what decides that a consumed
    /// printing has genuinely been away, so this stays a simple fact lookup.
    func admits(_ confirmed: ScanIdentifier) -> Bool {
        let key = confirmed.suppressionKey
        guard let printing = consumed.first(where: { $0.key == key }) else { return true }
        return printing.hasLeft
    }

    mutating func engage(on identifier: ScanIdentifier, at now: CFAbsoluteTime) {
        heldRepeatAuthorizationKey = nil
        latched = identifier
        heldMatchCount = 0
        consecutiveAbsences = 0
        remember(identifier, at: now)
    }

    /// Makes one already-consumed printing eligible for a deliberate Price
    /// Check re-read after a short quiet period. Unlike `releaseAndForget()`,
    /// this preserves every other consumed printing and all of their duplicate
    /// protections.
    mutating func armRecheck(
        for identifier: ScanIdentifier,
        at now: CFAbsoluteTime,
        after delay: TimeInterval
    ) {
        let key = identifier.suppressionKey
        guard let index = consumed.firstIndex(where: { $0.key == key }) else { return }
        consumed[index].recheckEligibleAt = now + max(0, delay)
    }

    /// Releases the current latch while retaining consumed-card memory, then
    /// permits one confirmation for this exact suppression key. The scanner
    /// owns the authorization token and lifetime; the latch only owns this
    /// small, one-shot admission fact.
    mutating func authorizeHeldRepeat(for key: ScanSuppressionKey) {
        guard latched?.suppressionKey == key else { return }
        heldRepeatAuthorizationKey = key
        heldMatchCount = 0
        consecutiveAbsences = 0
    }

    mutating func consumeHeldRepeatAuthorization(for key: ScanSuppressionKey) -> Bool {
        guard heldRepeatAuthorizationKey == key else { return false }
        heldRepeatAuthorizationKey = nil
        return true
    }

    mutating func cancelHeldRepeatAuthorization() {
        heldRepeatAuthorizationKey = nil
        heldMatchCount = 0
    }

    /// Moves a printing to the front of the memory, forgetting what was known
    /// about it before: it has just been counted, so it is present by definition.
    private mutating func remember(_ identifier: ScanIdentifier, at now: CFAbsoluteTime) {
        let key = identifier.suppressionKey
        consumed.removeAll { $0.key == key }
        consumed.insert(ConsumedPrinting(key: key, lastSeenAt: now), at: 0)
        if consumed.count > Self.recentlyConsumedLimit {
            consumed.removeLast(consumed.count - Self.recentlyConsumedLimit)
        }
    }

    /// Stop suppressing, but keep remembering what was consumed. Used when the
    /// user undoes or dismisses — the card is probably still sitting in the band,
    /// and re-adding it instantly would be the opposite of an undo.
    mutating func release() {
        latched = nil
        heldRepeatAuthorizationKey = nil
        heldMatchCount = 0
        consecutiveAbsences = 0
    }

    /// Marks a consumed printing as having physically left based on independent
    /// Vision tracking evidence. This is the only non-OCR path that can make an
    /// identical reading admissible; the view model still requires the matching
    /// `SpatialResetProof` before any duplicate mutation.
    /// The latch still owns only suppression state; it does not know why a
    /// collection mutation might happen.
    mutating func confirmSpatialExit(for identifier: ScanIdentifier) {
        let key = identifier.suppressionKey
        guard let index = consumed.firstIndex(where: { $0.key == key }) else { return }
        consumed[index].hasLeft = true
        if latched?.suppressionKey == key {
            release()
        }
    }

    /// Release *and* forget every consumed printing, so the very next
    /// confirmation is accepted. Only for failures where nothing was written: a
    /// dropped network request should cost the user a re-read, not a card.
    mutating func releaseAndForget() {
        release()
        consumed.removeAll()
        heldRepeatAuthorizationKey = nil
    }
}
