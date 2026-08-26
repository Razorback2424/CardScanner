import SwiftUI

/// A single resolved Price Check transaction. This intentionally shares only
/// card presentation primitives with collection review; its actions and pricing
/// semantics are separate.
struct PriceCheckResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: ScannerViewModel

    let initialResult: PriceCheckResult

    private var result: PriceCheckResult {
        guard let live = model.priceCheckResult, live.id == initialResult.id else {
            return initialResult
        }
        return live
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    artwork
                    identity
                    quote
                }
                .padding(20)
            }
            .navigationTitle("Price Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(result.isRefreshing)
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: result.card.displayImageURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFit()
            case .failure:
                ContentUnavailableView("Image unavailable", systemImage: "photo")
                    .frame(height: 380)
            default:
                ProgressView().frame(height: 380)
            }
        }
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Text(result.card.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(result.card.setName)
                .foregroundStyle(.secondary)
            Text(result.card.identifier)
                .font(.headline.monospacedDigit())
            if let printRun = result.pokemonPrintRun {
                Text(printRun.label)
                    .font(.subheadline.weight(.semibold))
            }
            Text(result.resolved.label)
                .font(.subheadline.weight(.semibold))
            if let rarity = result.card.rarity {
                Text(rarity)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var quote: some View {
        let display = result.display
        return VStack(spacing: 10) {
            Text("Estimated market value")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let amount = display.amount {
                Text(amount, format: .currency(code: display.currencyCode))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(provenance(for: display))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if result.refreshFailed {
                    Label("Current price unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            } else {
                ContentUnavailableView(
                    "Market price unavailable",
                    systemImage: "dollarsign.circle",
                    description: Text("No price is available for this exact variant.")
                )
                if result.refreshFailed {
                    Label("Current price unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Button {
                model.refreshPriceCheckQuote()
            } label: {
                if result.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh Price", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(result.isRefreshing)
            .accessibilityHint("Requests a newer quote for this exact card and variant.")
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }

    private func provenance(for display: PriceDisplay) -> String {
        let source = display.source?.label ?? "Source unavailable"
        if let asOf = display.sourceUpdatedAt {
            return "\(result.refreshFailed ? "Last known " : "")\(source) · Updated \(asOf.formatted(date: .abbreviated, time: .shortened))"
        }
        if let retrieved = display.fetchedAt {
            return "\(result.refreshFailed ? "Last known " : "")\(source) · Retrieved \(retrieved.formatted(date: .abbreviated, time: .shortened))"
        }
        return source
    }
}
