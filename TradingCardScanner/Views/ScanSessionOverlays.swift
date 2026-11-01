import SwiftUI

/// One visual language for everything floating on the camera: event color is
/// reserved for meaning (cyan read, green added, orange needs you), so a glance
/// at a tint says what happened before any text is read.
enum ScannerTone {
    case recognized
    case added
    case attention
    case neutral

    var color: Color {
        switch self {
        case .recognized: return .cyan
        case .added: return .green
        case .attention: return .orange
        case .neutral: return .white
        }
    }
}

/// A small tinted disc that anchors a scanner row. Every banner leads with one
/// at the same size, so receipt, recognition, and problems line up and the
/// eye finds the state in the same place each time.
struct ScannerStatusBadge<Content: View>: View {
    let tone: ScannerTone
    var size: CGFloat = 32
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .fill(tone.color.opacity(tone == .neutral ? 0.14 : 0.22))
            Circle()
                .strokeBorder(tone.color.opacity(tone == .neutral ? 0.18 : 0.4), lineWidth: 1)
            content()
                .foregroundStyle(tone.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension ScannerStatusBadge where Content == AnyView {
    init(tone: ScannerTone, systemName: String, size: CGFloat = 32) {
        self.tone = tone
        self.size = size
        self.content = {
            AnyView(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .bold))
            )
        }
    }
}

/// A quiet, round close control with a full 44 pt target. Dismissing is always
/// available on a camera question, but never louder than the answers.
struct ScannerDismissButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The printed identifier as a small token, so the number the person can see on
/// the card reads as the same kind of thing everywhere on the scanner.
struct ScannerIdentifierChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.white.opacity(0.12), in: Capsule())
    }
}

/// The small instruction above a camera question: what you are being asked,
/// before what about.
struct ScannerQuestionEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ScanAssistanceView: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "viewfinder")
                .foregroundStyle(.white.opacity(0.75))
        }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .appPillGlass()
            .accessibilityLabel("Scanner guidance: \(message)")
    }
}

struct SlabLabelReadingOfferView: View {
    let prompt: SlabLabelReadPrompt
    let onSwitchToRaw: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ScannerStatusBadge(tone: .neutral, systemName: "viewfinder", size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.stage.title)
                    .font(.subheadline.weight(.semibold))
                Text(prompt.stage.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if prompt.stage.offersRawSwitch {
                Button("Use Raw", action: onSwitchToRaw)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
                    .accessibilityHint("Changes scanning mode to raw cards.")
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .appGlass(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

struct PendingSlabConversionOfferView: View {
    let offer: PendingSlabConversionOffer
    let onConvert: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ScannerStatusBadge(tone: .recognized, systemName: "rosette", size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Looks like \(offer.gradeDescription) — Save as graded")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(offer.cardName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Convert", action: onConvert)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.cyan)
                .frame(minHeight: 44)
                .accessibilityHint("Replaces the raw scan with the graded slab entry.")
            ScannerDismissButton(accessibilityLabel: "Dismiss graded conversion offer", action: onDismiss)
                .padding(.trailing, -8)
        }
        .foregroundStyle(.white)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .appGlass(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

/// A compact statement of the finish and the evidence behind it. Detail keeps
/// this visible for every card; receipts show it only for resolutions that
/// need a person's attention, since the receipt's subtitle already names the
/// finish and routine scans should stay quiet.
enum VariantProvenancePresentation {
    static func text(
        finish: String?,
        resolution: VariantResolution?
    ) -> String {
        let finish = finish?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolution == .catalogSilent {
            return "Finish unconfirmed"
        }
        if let finish, !finish.isEmpty, let resolution {
            return "\(finish) · \(resolution.label)"
        }
        if let finish, !finish.isEmpty {
            return finish
        }
        if let resolution {
            return resolution.label
        }
        return "Finish unconfirmed"
    }

    /// Whether a receipt should call this out. A finish with no recorded
    /// evidence is not news on a receipt; a missing finish always is.
    static func needsAttention(finish: String?, resolution: VariantResolution?) -> Bool {
        guard let resolution else {
            return finish?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
        return resolution.receiptProminence != .quiet
    }
}

struct VariantProvenanceLabel: View {
    enum Style: Equatable {
        case detail
        case receipt
    }

    let finish: String?
    let resolution: VariantResolution?
    let style: Style

    private var text: String {
        VariantProvenancePresentation.text(finish: finish, resolution: resolution)
    }

    private var needsAttention: Bool {
        VariantProvenancePresentation.needsAttention(finish: finish, resolution: resolution)
    }

    var body: some View {
        if style == .receipt, !needsAttention {
            EmptyView()
        } else {
            label
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if style == .receipt, needsAttention {
                Image(systemName: "questionmark.circle.fill")
                    .imageScale(.small)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(
            style == .detail
                ? .caption.weight(.medium)
                : (needsAttention ? .caption.weight(.semibold) : .caption2)
        )
        .foregroundStyle(
            style == .detail
                ? (resolution?.certainty == .unresolved
                    ? AnyShapeStyle(PortfolioPalette.attention)
                    : AnyShapeStyle(.secondary))
                : (needsAttention
                    ? AnyShapeStyle(.orange)
                    : AnyShapeStyle(.white.opacity(0.72)))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Finish: \(text)")
    }
}

/// Immediate feedback for the card that has just crossed the two-frame OCR
/// boundary. It stays truthful while the writer is busy: only the failed state
/// says that the card was not added, and only the receipt says that the write
/// completed.
struct ScanAcknowledgementCard: View {
    let acknowledgement: ScanAcknowledgement
    let onRetryScan: () -> Void

    private var isFailure: Bool {
        acknowledgement.phase == .failed
    }

    private var showsRetryAction: Bool {
        isFailure && acknowledgement.canRetryScan
    }

    var body: some View {
        // Same geometry as the receipt that replaces it, so "recognized" turns
        // into "added" in place instead of the banner jumping.
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isFailure {
                    ScannerStatusBadge(tone: .attention, systemName: "exclamationmark")
                } else {
                    ScannerStatusBadge(tone: .recognized) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.cyan)
                            .accessibilityLabel("Saving")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isFailure ? "Not added" : "Recognized")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(acknowledgement.subject.displayIdentifier)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if let message = acknowledgement.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsRetryAction {
                    Button(action: onRetryScan) {
                        Label("Retry scan", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(.cyan)
                    .padding(.top, 2)
                    .accessibilityHint("Adjust the card, then hold it steady for a clearer read.")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appGlass(cornerRadius: 20)
        .accessibilityElement(children: showsRetryAction ? .contain : .combine)
        .accessibilityLabel(
            isFailure
                ? "Not added. \(acknowledgement.message ?? "Try again")"
                : "Recognized. \(acknowledgement.message ?? "Saving")"
        )
    }
}

/// A nonblocking fallback for an identical card that never produces reliable
/// spatial exit evidence. Its button is secondary because ignoring it remains
/// the safe default and a different card may continue through the scanner.
struct HeldDuplicateOfferView: View {
    let offer: HeldDuplicateOffer
    let onAddAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ScannerStatusBadge(tone: .added, systemName: "checkmark", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Already added")
                        .font(.subheadline.weight(.semibold))
                        .accessibilitySortPriority(3)

                    Text(offer.cardName + " — " + offer.printedIdentifier)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilitySortPriority(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onAddAnother) {
                Text("Add another copy")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .appGlassOptionButton()
            .foregroundStyle(.white)
            .accessibilityLabel("Add another copy")
            .accessibilityHint("Authorizes one additional copy of this card.")
            .accessibilitySortPriority(1)
        }
        .foregroundStyle(.white)
        .padding(12)
        .appGlass(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

/// A graded card is already committed when label evidence is ambiguous. This
/// compact correction surface deliberately does not own camera pause/resume.
struct GradedVariantCorrectionOfferView: View {
    let correction: PendingGradedVariantCorrection
    let onChoose: (PhysicalVariant) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ScannerStatusBadge(tone: .attention, systemName: "wand.and.stars", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish not confirmed")
                        .font(.subheadline.weight(.semibold))
                    Text(correction.cardName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ScannerDismissButton(accessibilityLabel: "Dismiss finish correction", action: onDismiss)
                    .padding(.trailing, -8)
                    .padding(.vertical, -6)
            }

            HStack(spacing: 8) {
                ForEach(correction.options) { option in
                    let label = correction.card.finishAndTreatmentDisplayLabel(for: option)
                    Button(label) {
                        onChoose(option)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .appGlassOptionButton()
                    .foregroundStyle(.white)
                    .accessibilityLabel("Set \(label) for \(correction.cardName)")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .appGlass(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

/// Confirmation required before a resolved card with the same printing identity
/// can change collection quantity. The safer no-mutation answer is first and
/// remains the visually safer default over Add another.
struct DuplicateConfirmationBar: View {
    let confirmation: PendingDuplicateConfirmation
    let onSameCard: () -> Void
    let onAddAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ScannerQuestionEyebrow(text: "Already added this session")
                    .accessibilityHidden(true)
                Text("Another copy?")
                    .font(.title3.bold())
                    .accessibilitySortPriority(3)
            }

            Text(duplicateDescription)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(2)

            VStack(spacing: 10) {
                Button(action: onSameCard) {
                    Text("Same card")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.orange)
                .accessibilityLabel("Same card")
                .accessibilityHint("Dismisses this question without changing your collection.")
                .accessibilitySortPriority(1)

                Button(action: onAddAnother) {
                    Text("Add another")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.white)
                .accessibilityLabel("Add another copy")
                .accessibilityHint("Adds one copy to your collection.")
                .accessibilitySortPriority(0)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .appGlass(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }

    private var duplicateDescription: String {
        let candidate = confirmation.candidate
        let label = "\(candidate.card.name) — \(candidate.identifier.scannerDisplayIdentifier(for: candidate.card))"
        guard let previousFinish = confirmation.previousFinishLabel else {
            return "\(label) was already added this session. Add this copy?"
        }
        let currentFinish = candidate.duplicateDisplayLabel
        return "\(label) was added this session as \(previousFinish). Add this \(currentFinish) copy?"
    }
}

/// The one-tap fork.
///
/// This appears only when two or more variants are genuinely possible and the
/// card carries nothing that separates them — the moment the person holding it
/// knows something the scanner cannot. The tap is the whole transaction: it
/// means this variant and continue to the captured scan destination. There is
/// no follow-up confirmation, because the tap already said everything.
struct VariantChoiceBar: View {
    let choice: PendingVariantChoice
    let onChoose: (PhysicalVariant) -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    ScannerQuestionEyebrow(text: choice.card.game == .yuGiOh ? "Which edition is this?" : "Which finish is this?")
                        .accessibilityHidden(true)
                    Text(choice.card.name)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ScannerIdentifierChip(text: variantChoiceIdentifier)
                        Text(choice.card.setName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScannerDismissButton(
                    accessibilityLabel: choice.duplicateChoiceContext == nil
                        ? "Skip this card"
                        : "Do not add another copy",
                    action: onDismiss
                )
                .padding(.top, -8)
                .padding(.trailing, -8)
            }

            if let missed = choice.lockDidNotApply {
                Label("No \(missed.label) printing exists — pick one that does", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let duplicate = choice.duplicateChoiceContext {
                let previousFinish = duplicate.previousFinishLabel ?? "an unconfirmed finish"
                Text(choice.card.game == .yuGiOh
                     ? "Added this session as \(previousFinish). Choose this copy’s edition to add another."
                     : "Added this session as \(previousFinish). Choose this copy’s finish to add another.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if choice.card.game == .yuGiOh && !choice.card.variantEvidence.physicalCoverageVerified {
                Text("Supported editions shown. Other editions may not yet be cataloged. No readable stamp does not establish Unlimited.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            options
        }
        .foregroundStyle(.white)
        .padding(16)
        .appGlass(cornerRadius: 24)
    }

    private var variantChoiceIdentifier: String {
        if case .opaque = choice.identifier.legacyIdentity {
            return choice.identifier.displayIdentifier
        }
        if case .pokemonHistorical = choice.identifier.legacyIdentity {
            return choice.identifier.displayIdentifier
        }
        return "Card \(choice.card.displayCardNumber)"
    }

    @ViewBuilder
    private var options: some View {
        // Three or fewer stay on one row, which keeps every button under the
        // thumb. Beyond that a second row beats shrinking the targets.
        if choice.options.count <= 3 && !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 10) {
                ForEach(choice.options) { option in
                    button(for: option)
                }
            }
        } else {
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(choice.options) { option in
                    button(for: option)
                }
            }
        }
    }

    private func button(for option: PhysicalVariant) -> some View {
        let label = choice.card.finishAndTreatmentDisplayLabel(for: option)
        return Button {
            onChoose(option)
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
        }
        .appGlassOptionButton()
        .foregroundStyle(.white)
        .accessibilityLabel(
            choice.duplicateChoiceContext == nil
                ? "Select \(label) for \(choice.card.name)"
                : "Add another \(label) copy of \(choice.card.name)"
        )
    }
}

/// One factual question for early Pokémon sets whose provider identity is
/// shared by physically distinct print runs with materially different prices.
struct PrintRunChoiceBar: View {
    let choice: PendingPrintRunChoice
    let onChoose: (PokemonPrintRun) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    ScannerQuestionEyebrow(text: "Which print run is this card?")
                    Text(choice.card.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        ScannerIdentifierChip(text: choice.identifier.scannerDisplayIdentifier(for: choice.card))
                        Text(choice.card.setName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScannerDismissButton(accessibilityLabel: "Skip this card", action: onDismiss)
                    .padding(.top, -8)
                    .padding(.trailing, -8)
            }

            HStack(spacing: 10) {
                ForEach(choice.options, id: \.self) { option in
                    Button {
                        onChoose(option)
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .appGlassOptionButton()
                    .foregroundStyle(.white)
                    .accessibilityLabel("Select \(option.label) for \(choice.card.name)")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .appGlass(cornerRadius: 24)
    }
}

/// The resolver proved that more than one catalog printing carries the same
/// visible title and number. This tap supplies the one fact the card evidence
/// could not; ordering is never used as identity.
struct PrintingChoiceBar: View {
    let choice: PendingPrintingChoice
    let onChoose: (PhysicalPrintingCandidate) -> Void
    let onDismiss: () -> Void
    var onChooseEnglish: ((PhysicalPrintingCandidate) -> Void)? = nil
    @State private var showingDetails = false
    @State private var englishConfirmed = false
    private var requiresEnglish: Bool { choice.identifier.needsMagicEnglishConfirmation }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sharedRelease: String? {
        let candidates = choice.displayCandidates
        guard let release = candidates.first?.releaseLabel,
              candidates.allSatisfy({ $0.releaseLabel == release }) else { return nil }
        let label = release.components(separatedBy: " · ").filter { $0 != "English" }.joined(separator: " · ")
        return label.isEmpty ? nil : label
    }

    var body: some View {
        let candidates = choice.displayCandidates
        let labels = PhysicalPrintingCandidate.compactChoiceLabels(among: candidates)
        let evidence = PhysicalPrintingCandidate.selectionEvidenceByID(among: candidates)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidates.first?.name ?? "Card")
                        .font(.title3.bold())
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    ScannerIdentifierChip(text: choice.identifier.displayIdentifier)
                    if let sharedRelease {
                        Text(sharedRelease)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ScannerDismissButton(accessibilityLabel: "Skip this card", action: onDismiss)
                    .padding(.top, -8)
                    .padding(.trailing, -8)
            }

            HStack {
                Text(candidates.count > 2 ? "Choose a printing · \(candidates.count) options" : "Choose a printing")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    showingDetails = true
                } label: {
                    Label("Details", systemImage: "rectangle.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare printing details")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65))

            if requiresEnglish {
                Toggle("This card is in English", isOn: $englishConfirmed)
                    .font(.subheadline)
                    .accessibilityIdentifier("magic-english-confirmation")
            }
            if candidates.count <= 2 && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    ForEach(candidates) { compactButton($0, label: labels[$0.id] ?? $0.choiceLabel, evidence: evidence[$0.id] ?? .insufficient) }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(candidates) { compactButton($0, label: labels[$0.id] ?? $0.choiceLabel, evidence: evidence[$0.id] ?? .insufficient) }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 80, maxHeight: 220)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("printing-choice-list")
            }
            if evidence.values.contains(where: { $0 != .labels }) {
                Text("Compare artwork and markings in Details.")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            if candidates.count > 8 {
                Text("Filter by set or collector number in Details.")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .appGlass(cornerRadius: 24)
        .sheet(isPresented: $showingDetails) {
            PrintingChoiceDetails(candidates: candidates, onChoose: { selected in
                showingDetails = false
                onChoose(selected)
            }, requiresEnglishConfirmation: requiresEnglish, onChooseEnglish: { selected in
                showingDetails = false
                onChooseEnglish?(selected)
            }, englishConfirmation: $englishConfirmed)
        }
        // This panel sits on the camera and uses white labels in either app
        // appearance. Keep the material dark without changing the app theme.
        .environment(\.colorScheme, .dark)
    }

    private func compactButton(_ candidate: PhysicalPrintingCandidate, label: String, evidence: PhysicalPrintingCandidate.SelectionEvidence) -> some View {
        Button {
            if requiresEnglish { onChooseEnglish?(candidate) } else { onChoose(candidate) }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                if let reason = candidate.acquisitionUnavailableReason {
                    Text(reason).font(.caption)
                }
            }
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .disabled(candidate.acquisitionUnavailableReason != nil || evidence != .labels || (requiresEnglish && !englishConfirmed))
        .accessibilityLabel("Select \(label) for \(candidate.name)")
        .accessibilityHint(candidate.acquisitionUnavailableReason ?? "Compare this printing with your card.")
        .accessibilityIdentifier("printing-choice-\(candidate.id)")
    }
}

struct PrintingChoiceDetails: View {
    let candidates: [PhysicalPrintingCandidate]
    let onChoose: (PhysicalPrintingCandidate) -> Void
    var requiresEnglishConfirmation = false
    var onChooseEnglish: ((PhysicalPrintingCandidate) -> Void)? = nil
    var englishConfirmation: Binding<Bool>? = nil
    @State private var englishConfirmed = false
    @State private var searchText = ""
    private var englishBinding: Binding<Bool> { englishConfirmation ?? $englishConfirmed }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if candidates.count > 8 {
                    printingList.searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Set or collector number")
                } else {
                    printingList
                }
            }
            .navigationTitle("Printing details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filteredCandidates: [PhysicalPrintingCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { candidate in
            ([candidate.name, candidate.releaseLabel, candidate.printedIdentifier].compactMap { $0 }
                + (candidate.distinctionLabels ?? [])).contains { $0.localizedStandardContains(query) }
        }
    }

    private var printingList: some View {
            let evidence = PhysicalPrintingCandidate.selectionEvidenceByID(among: candidates)
            return List {
                if requiresEnglishConfirmation {
                    Toggle("This card is in English", isOn: englishBinding)
                        .accessibilityIdentifier("magic-english-confirmation")
                }
                if filteredCandidates.isEmpty {
                    Text("No printings match this search.").foregroundStyle(.secondary)
                }
                ForEach(filteredCandidates) { candidate in
                    PrintingCandidateButton(candidate: candidate,
                        evidence: evidence[candidate.id] ?? .insufficient, onChoose: { selected in
                            if requiresEnglishConfirmation { onChooseEnglish?(selected) } else { onChoose(selected) }
                        })
                        .disabled(requiresEnglishConfirmation && !englishBinding.wrappedValue)
                }
            }
            .onAppear {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("PrintingChoice"), args.contains(where: { $0.hasPrefix("many") && $0.contains("filtered-details") }) {
                    searchText = "Block: 10"
                }
                #endif
            }
    }
}

/// Shared live/recovery presentation. The complete footer and distribution
/// evidence stays readable, and image-only distinctions cannot be guessed while
/// artwork is missing or still loading.
struct PrintingCandidateButton: View {
    let candidate: PhysicalPrintingCandidate
    let evidence: PhysicalPrintingCandidate.SelectionEvidence
    var isOnCamera = false
    let onChoose: (PhysicalPrintingCandidate) -> Void
    @State private var imagePhase: CatalogImageLoadPhase = .idle

    init(candidate: PhysicalPrintingCandidate, evidence: PhysicalPrintingCandidate.SelectionEvidence,
         isOnCamera: Bool = false, onChoose: @escaping (PhysicalPrintingCandidate) -> Void) {
        self.candidate = candidate; self.evidence = evidence
        self.isOnCamera = isOnCamera; self.onChoose = onChoose
    }

    private var isSelectable: Bool {
        candidate.acquisitionUnavailableReason == nil && (evidence == .labels || (evidence == .artwork && imagePhase == .loaded))
    }

    private var unavailableExplanation: String? {
        if let reason = candidate.acquisitionUnavailableReason { return reason }
        switch evidence {
        case .labels: return nil
        case .insufficient: return "More catalog detail is needed to distinguish this printing."
        case .artwork:
            if imagePhase == .loaded { return nil }
            return imagePhase == .failed
                ? "Artwork is unavailable. It is needed to distinguish this printing."
                : "Loading artwork needed to distinguish this printing…"
        }
    }

    var body: some View {
        return Button {
            onChoose(candidate)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if candidate.thumbnailURL != nil {
                    CatalogCachedImage(url: candidate.thumbnailURL, targetPixelSize: 240,
                        onPhaseChange: { imagePhase = $0 })
                        .frame(width: 60, height: 84)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.choiceTitle)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(candidate.identificationDetails.enumerated()), id: \.offset) { _, detail in
                        Text(detail).font(.caption)
                    }
                    if let date = candidate.releaseDateLabel {
                        Text(date).font(.caption)
                    }
                    if let unavailableExplanation {
                        Text(unavailableExplanation).font(.caption)
                            .foregroundStyle(isOnCamera ? Color.white.opacity(0.85) : Color.secondary)
                    }
                    if isSelectable {
                        Text("Select this printing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isOnCamera ? Color.white : Color.primary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(isOnCamera ? Color.white : Color.primary)
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(!isSelectable)
        .accessibilityLabel("Select \(candidate.choiceLabel)\(candidate.releaseDateLabel.map { " · " + $0 } ?? "") for \(candidate.name)")
        .accessibilityHint(unavailableExplanation ?? "Compare this printing's details with the card in front of you.")
        .accessibilityIdentifier("printing-choice-\(candidate.id)")
    }
}

typealias IdentityChoiceBar = PrintingChoiceBar

#if DEBUG
/// Deterministic rendering/interaction fixture; it never creates owned cards or
/// registers synthetic data as production catalog authority.
struct PrintingChoiceDebugView: View {
    private let state: String
    private let choice: PendingPrintingChoice
    @State private var selected: String?
    @State private var dismissed = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "-ui_debug_state")
        let state = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "many"
        self.state = state
        if state.hasPrefix("magic-historical"),
           let index = try? MagicHistoricalIndexSnapshot.loadBundled(),
           let profiles = try? MagicRecognitionProfileSnapshot(descriptors: index.artifact.catalog.sets,
                indexGeneration: index.generation, catalogRevision: index.catalogRevision),
           let snapshot = try? MagicHistoricalLocalSnapshot(profiles: profiles, index: index),
           let record = index.artifact.records.first(where: { $0.name == "Allay" }) {
            let evidence = MagicHistoricalScanEvidence(title: record.name, collectorNumber: record.collectorNumber,
                denominator: 143, encounterID: UUID(), profileGeneration: snapshot.generation,
                indexGeneration: index.generation, titleBounds: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.04),
                numberBounds: CGRect(x: 0.1, y: 0.03, width: 0.3, height: 0.03))
            let candidate = PhysicalPrintingCandidate(id: record.printingID, game: .magic,
                canonicalCardID: record.oracleID!, language: "en", catalogGeneration: "magic-provider-v1",
                name: record.name, printedIdentifier: record.collectorNumber, releaseLabel: record.setName,
                distinctionLabels: ["EXO", record.collectorNumber], recognitionGeneration: snapshot.generation)
            choice = PendingPrintingChoice(request: .init(subject: .init(identifier: try! evidence.identifier()),
                purpose: .collection, generation: 0), candidates: [candidate])
            return
        }
        let count = ["few", "accessibility", "footer", "missing-artwork", "long-title"].contains(state) ? 2 : 61
        let printedNumber = state == "long-title" ? "OP17-047" : "P-001"
        let identifier = try! ScanIdentifier(game: .onePiece, namespace: "numbered-card",
            fields: [.init(key: "number", value: printedNumber)], displayIdentifier: printedNumber,
            suppressionIdentity: "number:\(printedNumber)", catalogGeneration: "ui-fixture")
        let candidates = (1...count).map { number in
            PhysicalPrintingCandidate(id: "fixture-\(number)", game: .onePiece,
                canonicalCardID: "one-piece:en:\(printedNumber)", language: "en", catalogGeneration: "ui-fixture",
                name: state == "long-title" ? "Shiki" : "Monkey.D.Luffy", printedIdentifier: printedNumber,
                releaseLabel: state == "long-title" ? "English · The World's Strongest Warriors"
                    : (count == 2 ? "English · Romance Dawn" : "English · Event \(number)"),
                treatmentLabel: state == "footer" || state == "missing-artwork" ? "Standard"
                    : (number.isMultiple(of: 2) ? "Alternate art" : "Original art"),
                distributionLabel: count == 2 ? nil : (number.isMultiple(of: 3) ? "Winner" : "Participation"),
                thumbnailURL: state == "missing-artwork" ? URL(string: "https://fixture.invalid/\(number).png") : nil,
                artworkID: state == "missing-artwork" ? "artwork-\(number)" : nil,
                distinctionLabels: ["Region: North America / Europe", "Block: \(state == "missing-artwork" ? 1 : number)",
                    "Copyright: Printed footer evidence for this physical release"])
        }
        choice = PendingPrintingChoice(request: .init(subject: .init(identifier: identifier),
            purpose: .collection, generation: 0), candidates: candidates)
    }

    var body: some View {
        if state.hasSuffix("-details") {
            PrintingChoiceDetails(candidates: choice.displayCandidates, onChoose: { selected = $0.id })
                .dynamicTypeSize(state.contains("accessibility") ? .accessibility3 : .large)
        } else {
        VStack(spacing: 16) {
            Text("Printing choice fixture").font(.headline)
            Text(selected ?? (dismissed ? "Skipped to Needs attention" : "No printing selected"))
                .accessibilityIdentifier("printing-fixture-result")
            Spacer(minLength: 0)
            if !dismissed {
                PrintingChoiceBar(choice: choice, onChoose: { selected = $0.id }, onDismiss: { dismissed = true },
                    onChooseEnglish: { selected = $0.id })
            }
        }
        .padding(16)
        .contentWidthLimit(.standard)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .dynamicTypeSize(state.contains("accessibility") ? .accessibility3 : .large)
        }
    }
}
#endif

/// The unit price captured during identification. It is deliberately a small
/// value view shared by the receipt and review sheet so both surfaces make the
/// same promise: this amount belongs to the printing and finish just scanned.
struct ScanPriceValue: View {
    enum Style: Equatable {
        case receipt
        case review

        var font: Font {
            switch self {
            case .receipt: return .system(.headline, design: .rounded).weight(.bold)
            case .review: return .title2.weight(.bold)
            }
        }
    }

    let lookup: PriceLookup
    var style: Style = .receipt
    var isGradedPricePending: Bool = false

    var body: some View {
        if isGradedPricePending {
            Text("Checking graded price…")
                .font(style == .review ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(
                    style == .review
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.white.opacity(0.78))
                )
                .accessibilityLabel("Checking graded price")
        } else {
            switch lookup {
            case let .price(price):
                let formatted = price.unitMarketPriceUSD.formatted(.currency(code: price.currencyCode))
                Text(formatted)
                    .font(style.font)
                    .monospacedDigit()
                    .foregroundStyle(style == .receipt ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .accessibilityLabel("Unit price \(formatted)")
            case .unavailable:
                Text("Price unavailable")
                    .font(style == .review ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(
                        style == .review
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.white.opacity(0.78))
                    )
                    .accessibilityLabel("Price unavailable")
            }
        }
    }
}

/// What just happened, shown rather than asked about.
///
/// It does not block the next card: recognition never stopped, so card two can
/// already be resolving while this is still on screen. Undo is insurance, not a
/// step in the workflow.
struct ScanReceiptCard: View {
    let receipt: ScanReceipt
    let onUndo: () -> Void
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            addedBadge
                            Text(receipt.name)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ScanPriceValue(
                            lookup: receipt.price,
                            isGradedPricePending: receipt.isGradedPricePending
                        )
                        Text("\(receipt.identifier) · \(receipt.variantLabel)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                undoButton
            } else {
            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        // No thumbnail. At 40 pt over a live preview it was too
                        // small to identify a card by, and it cost the name the
                        // width that actually confirms the right card was added
                        // while scanning fast. The recent scans tray carries the
                        // artwork for anyone who wants to look back.
                        addedBadge

                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                // A long Magic name loses a little size before it
                                // loses its last words.
                                .minimumScaleFactor(0.85)
                            Text("\(receipt.identifier) · \(receipt.variantLabel)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // An amount is never allowed to wrap. Without this the
                        // trailing column compresses to a few points under the
                        // name and the button, and the currency typesets one
                        // character per line.
                        ScanPriceValue(
                            lookup: receipt.price,
                            isGradedPricePending: receipt.isGradedPricePending
                        )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                            // A graded quote arriving after the add rolls in
                            // rather than popping.
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                undoButton
            }
            }

            // Aligned under the name rather than the badge, so the receipt
            // keeps one clean text edge.
            VStack(alignment: .leading, spacing: 4) {
                VariantProvenanceLabel(
                    finish: receipt.variantLabel,
                    resolution: receipt.resolution,
                    style: .receipt
                )

                // Full width under the row: a treatment warning is about the whole
                // receipt, and inside the title column it stole the name's width.
                ForEach(receipt.treatmentDiagnostics) { diagnostic in
                    Label(diagnostic.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .accessibilityValue(diagnostic.detail)
                }
            }
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 44)
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .appGlass(cornerRadius: 20)
    }

    /// Bounces once per new receipt: the "got it" beat while scanning a stack.
    /// Keyed to the receipt, so a graded price refresh never replays it.
    private var addedBadge: some View {
        ScannerStatusBadge(tone: .added, systemName: "checkmark")
            .symbolEffect(.bounce, value: receipt.id)
    }

    /// Insurance, not a warning: a quiet round control rather than a red one,
    /// so routine receipts stay calm while it remains one tap away.
    private var undoButton: some View {
        Button(action: onUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo scan and remove \(receipt.name) from your collection")
        .accessibilityHint("Removes the card that was just added and lets you correct its scan details.")
    }
}

/// Inspectable history. It asks for nothing; it is simply there to glance at,
/// and it is the way back into any single record without leaving the session.
struct RecentScanRail: View {
    let scans: [RecentScan]
    var gradedPriceUpdatedScanID: RecentScan.ID? = nil
    let onSelect: (RecentScan) -> Void
    let onDelete: (RecentScan) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(scans.prefix(5)) { scan in
                    Button {
                        onSelect(scan)
                    } label: {
                        // Every card here was added; a per-card checkmark only
                        // repeated that. The artwork is the content.
                        CardThumbnail(artwork: scan.artwork(prefersFullSize: false), width: 44)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            .overlay(alignment: .topTrailing) {
                                if scan.id == gradedPriceUpdatedScanID {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white, .cyan)
                                        .symbolEffect(.pulse, options: .repeating)
                                        .offset(x: 4, y: -4)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Collection", role: .destructive) {
                            onDelete(scan)
                        }
                    }
                    .accessibilityLabel("\(scan.card.name), \(scan.card.finishAndTreatmentDisplayLabel(for: scan.resolved.variant)). Open to correct.")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Recently scanned cards")
    }
}

struct CardThumbnail: View {
    let artwork: CatalogCardArtworkSource
    var width: CGFloat

    var body: some View {
        // The shared loader sizes the decode to this frame, reuses the
        // collection's cache and tries the same fallbacks. The tile stays a
        // plain fill until a candidate loads; a spinner does not fit here.
        CatalogCachedImage(candidates: artwork.remoteCandidates, showsPlaceholder: false, contentMode: .fill)
            .frame(width: width, height: width / 0.716)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: width * 0.1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}

/// Local recovery. One awkward card gets a line beside the band and nothing
/// more — no modal, no acknowledgement button, no interruption to the run.
struct ScanNoteView: View {
    let note: ScanNote

    var body: some View {
        // Glass with a tinted icon rather than a solid orange slab: a problem
        // still reads at a glance, without shouting over the card being read.
        Label {
            Text(note.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: note.tone == .problem ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(note.tone == .problem ? Color.orange : Color.white.opacity(0.75))
        }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .appPillGlass(
                tint: note.tone == .problem ? Color.orange.opacity(0.28) : nil,
                fallbackTintOpacity: 1
            )
    }
}

/// App-scoped departure feedback. It observes only the summary store, so a live
/// scanner write never invalidates the destination tab's entire hierarchy.
struct ScanSessionSummaryBanner: View {
    @EnvironmentObject private var summaryStore: ScanSessionSummaryStore

    var body: some View {
        Group {
            if let summary = summaryStore.summary {
                HStack(spacing: 12) {
                    ScannerStatusBadge(tone: .added, systemName: "checkmark", size: 30)
                    Text(summary.message)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    ScannerDismissButton(accessibilityLabel: "Dismiss scan summary") {
                        summaryStore.dismiss()
                    }
                    .padding(.vertical, -6)
                }
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .appGlass(cornerRadius: 20)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Scan complete. \(summary.message)")
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: summaryStore.summary)
    }
}
