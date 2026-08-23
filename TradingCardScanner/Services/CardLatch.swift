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

    /// Consecutive non-matching observations before the latched card is presumed
    /// gone. At roughly four passes a second this is about a second of the
    /// identifier not being readable.
    let releaseAfterAbsences: Int
    /// How long a consumed printing must go unread before an identical reading is
    /// believed to be a second physical copy rather than the same card.
    let minimumAbsenceBeforeRelatch: TimeInterval

    private(set) var latched: ScanIdentifier?
    /// Consecutive readings of the latched printing since it was consumed. Lets
    /// the UI explain the one confusing case — a second identical copy dropped in
    /// too quickly — instead of silently ignoring it.
    private(set) var heldMatchCount = 0

    private var consecutiveNonMatches = 0
    private var consumed: ScanIdentifier?
    private var consumedLastSeenAt: CFAbsoluteTime = 0
    private var consumedHasLeft = false

    init(releaseAfterAbsences: Int = 4, minimumAbsenceBeforeRelatch: TimeInterval = 1.2) {
        self.releaseAfterAbsences = max(1, releaseAfterAbsences)
        self.minimumAbsenceBeforeRelatch = minimumAbsenceBeforeRelatch
    }

    mutating func observe(_ observation: ScanIdentifier?, at now: CFAbsoluteTime) -> Decision {
        // Absence is measured against the consumed printing, not the latch, so the
        // gap keeps accumulating after the latch itself has released.
        if let observation, observation == consumed {
            if now - consumedLastSeenAt >= minimumAbsenceBeforeRelatch {
                consumedHasLeft = true
            }
            consumedLastSeenAt = now
        }

        guard let latched else { return .forward(observation) }

        if observation == latched {
            heldMatchCount += 1
            consecutiveNonMatches = 0
            return .holdingLatch
        }

        // A differing reading is evidence, not proof. Forward it so the ordinary
        // confirmation window decides whether a different card is really there.
        consecutiveNonMatches += 1
        if consecutiveNonMatches >= releaseAfterAbsences {
            release()
        }
        return .forward(observation)
    }

    /// Whether a confirmed identifier may mutate the collection right now.
    ///
    /// Time does not appear here: `observe` is what decides that a consumed
    /// printing has genuinely been away, so this stays a simple fact lookup.
    func admits(_ confirmed: ScanIdentifier) -> Bool {
        guard confirmed == consumed else { return true }
        return consumedHasLeft
    }

    mutating func engage(on identifier: ScanIdentifier, at now: CFAbsoluteTime) {
        latched = identifier
        heldMatchCount = 0
        consecutiveNonMatches = 0
        consumed = identifier
        consumedLastSeenAt = now
        consumedHasLeft = false
    }

    /// Stop suppressing, but keep remembering what was consumed. Used when the
    /// user undoes or dismisses — the card is probably still sitting in the band,
    /// and re-adding it instantly would be the opposite of an undo.
    mutating func release() {
        latched = nil
        heldMatchCount = 0
        consecutiveNonMatches = 0
    }

    /// Release *and* forget the consumed printing, so the very next confirmation
    /// is accepted. Only for failures where nothing was written: a dropped
    /// network request should cost the user a re-read, not a card.
    mutating func releaseAndForget() {
        release()
        consumed = nil
        consumedLastSeenAt = 0
        consumedHasLeft = false
    }
}
