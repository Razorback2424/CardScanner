import SwiftUI

/// A single resolved Price Check transaction. This intentionally shares only
/// card presentation primitives with collection review; its actions and pricing
/// semantics are separate.
struct PriceCheckResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: ScannerViewModel

    let initialResult: PriceCheckResult
    @State private var isShowingSettings = false

    private var result: PriceCheckResult {
        guard let live = model.priceCheckResult, live.id == initialResult.id else {
            return initialResult
        }
        return live
    }

    private var hasTreatment: Bool {
        !result.card.magicTreatments(for: result.resolved.variant).isEmpty
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
                .contentWidthLimit(.standard)
            }
            .navigationTitle("Price Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: model.settingsDismissed) {
            SettingsView()
                .environmentObject(model)
        }
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

                if result.isRefreshing {
                    Label("Updating current price…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if case let .lastKnown(issue) = result.quoteState {
                    Label(lastKnownMessage(for: issue), systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    if issue.isFallbackSettingsIssue {
                        openSettingsButton
                    }
                }
            } else {
                noQuoteState
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

    @ViewBuilder
    private var noQuoteState: some View {
        switch result.quoteState {
        case .checking where result.isRefreshing || result.shouldAutoRefresh:
            VStack(spacing: 10) {
                ProgressView()
                Text("Checking current price…")
                    .font(.headline)
                Text("We’re checking the exact card and variant.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checking current price")
        case .checking:
            ContentUnavailableView(
                "Price check paused",
                systemImage: "pause.circle",
                description: Text("Tap Refresh Price to check this exact variant.")
            )
        case .noExactPrice:
            exactPriceUnavailableState
        case .notMatched:
            ContentUnavailableView(
                "Card not matched to a vendor product",
                systemImage: "questionmark.folder",
                description: Text("We couldn’t match this card to a product at the price provider. Try again later after the catalog match is updated.")
            )
        case .unsupportedFinish:
            ContentUnavailableView(
                "Finish not supported",
                systemImage: "tag.slash",
                description: Text("The optional fallback provider does not have a safe mapping for this finish, so it was not asked for a price.")
            )
        case .unsupportedTreatment:
            ContentUnavailableView(
                "Treatment price unavailable",
                systemImage: "tag.slash",
                description: Text("The optional fallback provider has no direct product identity for this treatment, so a name/set search is not used to avoid borrowing another printing's price.")
            )
        case .providerUnavailable:
            ContentUnavailableView(
                "Price provider unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text("The price service could not be reached. Try again shortly.")
            )
        case .fallbackDisabled:
            fallbackSettingsState(
                "Price fallback is off",
                systemImage: "gearshape",
                description: "Enable the optional fallback provider in Settings to continue."
            )
        case .fallbackUnconfigured:
            fallbackSettingsState(
                "Price fallback needs setup",
                systemImage: "key.horizontal",
                description: "Add the optional fallback provider credential in Settings."
            )
        case let .rateLimited(retryAt):
            ContentUnavailableView(
                "Price check is rate limited",
                systemImage: "hourglass",
                description: Text("Try again \(retryAt.formatted(date: .abbreviated, time: .shortened)).")
            )
        case let .budgetLimited(resetAt):
            ContentUnavailableView(
                "Price fallback limit reached",
                systemImage: "calendar.badge.clock",
                description: Text("The optional fallback allowance resets \(resetAt.formatted(date: .abbreviated, time: .shortened)).")
            )
        case .current, .lastKnown(_):
            exactPriceUnavailableState
        }
    }

    private var exactPriceUnavailableState: some View {
        ContentUnavailableView(
            hasTreatment ? "No exact treatment price" : "No listing for this finish",
            systemImage: "dollarsign.circle",
            description: Text(
                hasTreatment
                    ? "No exact provider listing was available for this treatment. A direct product identity is required; name/set search is not used."
                    : "The price provider found this card but has no listing for its exact finish."
            )
        )
    }

    private func fallbackSettingsState(
        _ title: String,
        systemImage: String,
        description: String
    ) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            openSettingsButton
        }
    }

    private var openSettingsButton: some View {
        Button("Open Settings", systemImage: "gearshape") {
            isShowingSettings = true
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Opens Pricing Settings so you can enable and configure the fallback provider.")
    }

    private func lastKnownMessage(for issue: PriceCheckRefreshIssue) -> String {
        switch issue {
        case .noExactPrice:
            return hasTreatment
                ? "No exact treatment price — showing last known"
                : "No listing for this finish — showing last known"
        case .notMatched:
            return "Card not matched to a vendor product — showing last known"
        case .unsupportedFinish:
            return "Finish not supported by the fallback provider — showing last known"
        case .unsupportedTreatment:
            return "Treatment not supported by the fallback provider — showing last known"
        case .providerUnavailable:
            return "Couldn’t update — showing last known"
        case .fallbackDisabled:
            return "Fallback is off — showing last known"
        case .fallbackUnconfigured:
            return "Fallback needs setup — showing last known"
        case .rateLimited:
            return "Rate limited — showing last known"
        case .budgetLimited:
            return "Fallback limit reached — showing last known"
        }
    }

    private func provenance(for display: PriceDisplay) -> String {
        let source = display.source?.label ?? "Source unavailable"
        let prefix: String
        if case .lastKnown(_) = result.quoteState {
            prefix = "Last known "
        } else {
            prefix = ""
        }
        if let asOf = display.sourceUpdatedAt {
            return "\(prefix)\(source) · Updated \(asOf.formatted(date: .abbreviated, time: .shortened))"
        }
        if let retrieved = display.fetchedAt {
            return "\(prefix)\(source) · Retrieved \(retrieved.formatted(date: .abbreviated, time: .shortened))"
        }
        return "\(prefix)\(source)"
    }
}

private extension PriceCheckRefreshIssue {
    var isFallbackSettingsIssue: Bool {
        switch self {
        case .fallbackDisabled, .fallbackUnconfigured:
            true
        default:
            false
        }
    }
}
