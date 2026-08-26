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
/// Two identical copies back to back are deliberately not solved optically. The
/// first copy has to leave before the second is accepted, which is exactly what
/// happens when a hand moves through a stack, and which cannot produce a phantom
/// duplicate. That trade is intentional: a missed card costs one more pass, a
/// phantom duplicate quietly corrupts a five thousand card collection.
///
/// Time is passed in rather than read so the whole thing is testable.
struct CardLatch: Equatable {
    enum Decision: Equatable {
        /// Hand this observation to the confirmation window.
        case forward(ScanIdentifier?)
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
    }

    init(releaseAfterAbsences: Int = 4, minimumAbsenceBeforeRelatch: TimeInterval = 2.0) {
        self.releaseAfterAbsences = max(1, releaseAfterAbsences)
        self.minimumAbsenceBeforeRelatch = minimumAbsenceBeforeRelatch
    }

    mutating func observe(_ observation: ScanIdentifier?, at now: CFAbsoluteTime) -> Decision {
        if observation == nil {
            consecutiveAbsences += 1
        } else {
            consecutiveAbsences = 0
        }

        updateConsumedPresence(with: observation, at: now)

        guard latched != nil else { return .forward(observation) }

        if observation == latched {
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
    /// Absence is evidence about all of them at once — an unreadable frame says
    /// nothing is in the band. A reading only ever says something about the one
    /// printing it matches; for the others it is neither presence nor absence,
    /// because a focus wobble can produce another plausible parse while the card
    /// it came from is still sitting there.
    private mutating func updateConsumedPresence(
        with observation: ScanIdentifier?,
        at now: CFAbsoluteTime
    ) {
        let observedKey = observation?.suppressionKey

        for index in consumed.indices {
            if let observedKey, consumed[index].key == observedKey {
                consumed[index].lastSeenAt = now
                consumed[index].consecutiveAbsences = 0
            } else if observation == nil {
                consumed[index].consecutiveAbsences += 1
                if consumed[index].consecutiveAbsences >= releaseAfterAbsences,
                   now - consumed[index].lastSeenAt >= minimumAbsenceBeforeRelatch {
                    consumed[index].hasLeft = true
                }
            } else {
                consumed[index].consecutiveAbsences = 0
            }
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
        latched = identifier
        heldMatchCount = 0
        consecutiveAbsences = 0
        remember(identifier, at: now)
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
        heldMatchCount = 0
        consecutiveAbsences = 0
    }

    /// Release *and* forget every consumed printing, so the very next
    /// confirmation is accepted. Only for failures where nothing was written: a
    /// dropped network request should cost the user a re-read, not a card.
    mutating func releaseAndForget() {
        release()
        consumed.removeAll()
    }
}
