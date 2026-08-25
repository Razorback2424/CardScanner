import SwiftUI

/// Shared chrome style. Everything floating over the camera is the same dark,
/// slightly translucent material so the card underneath stays the brightest,
/// most legible object on screen.
private struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
    }
}

extension View {
    func scannerGlass(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

struct ScanAssistanceView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "viewfinder")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .scannerGlass(cornerRadius: 14)
            .accessibilityLabel("Scanner guidance: \(message)")
    }
}

/// The one-tap fork.
///
/// This appears only when two or more variants are genuinely possible and the
/// card carries nothing that separates them — the moment the person holding it
/// knows something the scanner cannot. The tap is the whole transaction: it
/// means this variant *and* save it. There is no follow-up confirmation,
/// because the tap already said everything.
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
        .scannerGlass()
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
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("\(option.label), add \(choice.card.name)")
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
                            .background(
                                .white.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(.white.opacity(0.22), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(option.label), add \(choice.card.name)")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .scannerGlass()
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
                        .background(
                            .white.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("\(candidate.setName), add \(candidate.name)")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .scannerGlass()
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
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    CardThumbnail(url: receipt.thumbnailURL, width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(receipt.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Text("\(receipt.identifier) · \(receipt.variantLabel)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(10)
        .scannerGlass(cornerRadius: 16)
    }
}

/// Inspectable history. It asks for nothing; it is simply there to glance at,
/// and it is the way back into any single record without leaving the session.
struct RecentScanRail: View {
    let scans: [RecentScan]
    let onSelect: (RecentScan) -> Void

    var body: some View {
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
                .accessibilityLabel("\(scan.card.name), \(scan.resolved.label). Open to correct.")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(8)
        .scannerGlass(cornerRadius: 14)
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
