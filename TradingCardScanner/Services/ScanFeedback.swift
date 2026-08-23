import UIKit

/// The peripheral channel.
///
/// During a good session the user is looking at cards, not at the screen, so the
/// haptic *is* the interface. Each one describes a change in their workflow
/// state and nothing else — there is deliberately no feedback for "OCR ran", for
/// "a candidate looks plausible", or for anything else the app is busy with
/// internally. Constant buzzing would destroy the rhythm the whole design exists
/// to produce.
///
/// The generators are held and re-armed rather than created per event: a cold
/// `UIFeedbackGenerator` costs enough latency to break the card-to-tick coupling
/// that makes the app feel like it is keeping up.
@MainActor
final class ScanFeedback {
    private let addedGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let attentionGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let noticeGenerator = UINotificationFeedbackGenerator()

    func prepare() {
        addedGenerator.prepare()
        attentionGenerator.prepare()
    }

    /// A card went into the collection. The crisp one.
    func added() {
        addedGenerator.impactOccurred()
        addedGenerator.prepare()
    }

    /// The app knows the card but needs one fact only the person holding it has.
    func needsChoice() {
        attentionGenerator.impactOccurred(intensity: 0.7)
        attentionGenerator.prepare()
    }

    func choiceMade() {
        selectionGenerator.selectionChanged()
    }

    /// Identity was established and the lookup still failed, or the card was
    /// undone. Distinct from success so it never reads as one.
    func problem() {
        noticeGenerator.notificationOccurred(.warning)
    }

    func undone() {
        selectionGenerator.selectionChanged()
    }
}
