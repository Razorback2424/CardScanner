import SwiftUI

struct ScanAssistanceView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "viewfinder")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appGlass(cornerRadius: 14)
            .accessibilityLabel("Scanner guidance: \(message)")
    }
}

/// A nonblocking fallback for an identical card that never produces reliable
/// spatial exit evidence. Its button is secondary because ignoring it remains
/// the safe default and a different card may continue through the scanner.
struct HeldDuplicateOfferView: View {
    let offer: HeldDuplicateOffer
    let onAddAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already added")
                .font(.subheadline.weight(.bold))
                .accessibilitySortPriority(3)

            Text(offer.cardName + " — " + offer.printedIdentifier)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(2)

            Button(action: onAddAnother) {
                Text("Add another copy")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .accessibilityLabel("Add another copy")
            .accessibilityHint("Authorizes one additional copy of this card.")
            .accessibilitySortPriority(1)
        }
        .foregroundStyle(.white)
        .padding(12)
        .appGlass(cornerRadius: 14)
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
            Text("Another copy?")
                .font(.title3.bold())
                .accessibilitySortPriority(3)

            Text("\(confirmation.candidate.card.name) — \(confirmation.candidate.identifier.scannerDisplayIdentifier(for: confirmation.candidate.card)) was just scanned.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
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
                .tint(.white)
                .accessibilityLabel("Add another copy")
                .accessibilityHint("Adds one copy to your collection.")
                .accessibilitySortPriority(0)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .appGlass()
        .accessibilityElement(children: .contain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.card.name)
                        .font(.title3.bold())
                        .lineLimit(2)

                    Text(variantChoiceIdentifier)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(choice.card.setName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this card")
            }

            if let missed = choice.lockDidNotApply {
                Label("No \(missed.label) printing exists — pick one that does", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            options
        }
        .foregroundStyle(.white)
        .padding(14)
        .appGlass()
    }

    private var variantChoiceIdentifier: String {
        if case .pokemonHistorical = choice.identifier {
            return choice.identifier.displayIdentifier
        }
        return "Card \(choice.card.displayCardNumber)"
    }

    @ViewBuilder
    private var options: some View {
        // Three or fewer stay on one row, which keeps every button under the
        // thumb. Beyond that a second row beats shrinking the targets.
        if choice.options.count <= 3 {
            HStack(spacing: 10) {
                ForEach(choice.options) { option in
                    button(for: option)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(choice.options) { option in
                    button(for: option)
                }
            }
        }
    }

    private func button(for option: PhysicalVariant) -> some View {
        Button {
            onChoose(option)
        } label: {
            Text(option.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .appGlassOptionButton()
        .foregroundStyle(.white)
        .accessibilityLabel("Select \(option.label) for \(choice.card.name)")
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.card.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(choice.identifier.scannerDisplayIdentifier(for: choice.card))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(choice.card.setName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this card")
            }

            Text("Which print run is this card?")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

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
        .padding(14)
        .appGlass()
    }
}

/// The resolver proved that more than one catalog printing carries the same
/// visible title and number. This tap supplies the one fact the card evidence
/// could not; ordering is never used as identity.
struct IdentityChoiceBar: View {
    let choice: PendingIdentityChoice
    let onChoose: (PokemonCatalogCardIdentity) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.candidates.first?.name ?? "Pokémon card")
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(choice.identifier.displayIdentifier)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this card")
            }

            Text("The printed details exist in more than one set. Which symbol is on the card?")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            ForEach(choice.candidates, id: \.providerID) { candidate in
                Button {
                    onChoose(candidate)
                } label: {
                    Text(candidate.setName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .appGlassOptionButton()
                .foregroundStyle(.white)
                .accessibilityLabel("Select \(candidate.setName) for \(candidate.name)")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .appGlass()
    }
}

/// The unit price captured during identification. It is deliberately a small
/// value view shared by the receipt and review sheet so both surfaces make the
/// same promise: this amount belongs to the printing and finish just scanned.
struct ScanPriceValue: View {
    enum Style: Equatable {
        case receipt
        case review

        var font: Font {
            switch self {
            case .receipt: return .headline.weight(.bold)
            case .review: return .title2.weight(.bold)
            }
        }
    }

    let lookup: PriceLookup
    var style: Style = .receipt

    var body: some View {
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

/// What just happened, shown rather than asked about.
///
/// It does not block the next card: recognition never stopped, so card two can
/// already be resolving while this is still on screen. Undo is insurance, not a
/// step in the workflow.
struct ScanReceiptCard: View {
    let receipt: ScanReceipt
    let onUndo: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        // No thumbnail. At 40 pt over a live preview it was too
                        // small to identify a card by, and it cost the name the
                        // width that actually confirms the right card was added
                        // while scanning fast. The rail below still carries the
                        // artwork for anyone who wants to look back.
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                // A long Magic name loses a little size before it
                                // loses its last words.
                                .minimumScaleFactor(0.85)
                            Text("\(receipt.identifier) · \(receipt.variantLabel)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // An amount is never allowed to wrap. Without this the
                        // trailing column compresses to a few points under the
                        // name and the button, and the currency typesets one
                        // character per line.
                        ScanPriceValue(lookup: receipt.price)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Insurance, not a step in the workflow: it keeps a full 44 pt
                // target and its complete VoiceOver label, but stops being the
                // loudest and widest thing on a card about the card just added.
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Undo scan and remove \(receipt.name) from your collection")
                .accessibilityHint("Removes the card that was just added and lets you correct its scan details.")
            }

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
        .foregroundStyle(.white)
        .padding(10)
        .appGlass(cornerRadius: 16)
    }
}

/// Inspectable history. It asks for nothing; it is simply there to glance at,
/// and it is the way back into any single record without leaving the session.
struct RecentScanRail: View {
    let scans: [RecentScan]
    let onSelect: (RecentScan) -> Void
    let onDelete: (RecentScan) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scans) { scan in
                    Button {
                        onSelect(scan)
                    } label: {
                        CardThumbnail(url: scan.thumbnailURL, width: 38)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green, .black)
                                    .padding(2)
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
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .appGlass(cornerRadius: 14)
        .accessibilityLabel("Recently scanned cards")
    }
}

struct CardThumbnail: View {
    let url: URL?
    var width: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(.white.opacity(0.12))
            }
        }
        .frame(width: width, height: width / 0.716)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Local recovery. One awkward card gets a line beside the band and nothing
/// more — no modal, no acknowledgement button, no interruption to the run.
struct ScanNoteView: View {
    let note: ScanNote

    var body: some View {
        Label(note.text, systemImage: note.tone == .problem ? "exclamationmark.triangle.fill" : "info.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                (note.tone == .problem ? Color.orange.opacity(0.9) : Color.black.opacity(0.66)),
                in: Capsule()
            )
    }
}
