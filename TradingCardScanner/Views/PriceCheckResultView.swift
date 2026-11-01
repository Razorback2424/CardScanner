import SwiftUI

/// A single resolved Price Check transaction. This intentionally shares only
/// card presentation primitives with collection review; its actions and pricing
/// semantics are separate.
struct PriceCheckResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: ScannerViewModel

    let initialResult: PriceCheckResult
    @State private var isShowingSettings = false
    @State private var isSharing = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(sharePrice == nil)
                    .accessibilityLabel("Share price check")
                    .accessibilityHint("Shares an image of this card with its market price and recent trend.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isSharing) {
                if let sharePrice {
                    BuyCheckShareSheet(
                        identity: CardShareIdentity(priceCheck: result),
                        price: sharePrice,
                        artworkURLs: [result.card.displayImageURL].compactMap { $0 },
                        historyRequest: shareHistoryRequest
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: model.settingsDismissed) {
            SettingsView()
                .environmentObject(model)
        }
    }

    private var sharePrice: CardSharePrice? {
        CardSharePrice(priceCheck: result)
    }

    /// Market history is keyed to the raw printing. A graded check has no
    /// matching raw history to stand behind, so its image goes out without a
    /// chart rather than borrowing one.
    private var shareHistoryRequest: CardMarketHistoryRequest? {
        guard result.resolvedScan.request.subject.slab == nil else { return nil }
        return CardMarketHistoryRequest(
            card: result.card,
            variant: result.resolved.variant,
            printRun: result.pokemonPrintRun
        )
    }

    private var artwork: some View {
        let source = CatalogCardArtworkSource(identifiedCard: result.card, thumbnailURL: result.card.thumbnailImageURL,
                                              imageURL: result.card.displayImageURL, prefersFullSize: true)
        return Group {
            if source.primaryURL != nil {
                CatalogCachedImage(url: source.primaryURL, fallbacks: source.fallbacks)
                    .aspectRatio(0.727, contentMode: .fit)
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo")
                    .frame(height: 380)
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
            if let slab = result.resolvedScan.request.subject.slab {
                Text(slab.grade.display(company: slab.company))
                    .font(.subheadline.weight(.semibold))
                if let certificationNumber = slab.certificationNumber {
                    Text("Cert \(certificationNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let printRun = result.pokemonPrintRun {
                Text(printRun.label)
                    .font(.subheadline.weight(.semibold))
            }
            if result.resolvedScan.request.subject.slab == nil {
                Text(result.resolved.label)
                    .font(.subheadline.weight(.semibold))
            }
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
                if !result.isRefreshing, result.successfulQuoteState == .stale {
                    Label("Latest available quote is more than a day old", systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if !result.isRefreshing {
                    if let successfulCheck = result.lastSuccessfulCheckAt
                        ?? (result.refreshFeedback == .failed || result.checkTimeIsRetrievalEvidence ? nil : result.checkedAt) {
                        Text("Last checked \(successfulCheck.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if result.checkTimeIsRetrievalEvidence, let retrieved = display.fetchedAt {
                        Text("Quote received \(retrieved.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if result.refreshFeedback == .failed {
                        Text("Last attempt failed \(result.checkedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if result.refreshFeedback == .noNewerData {
                        Text("Checked; no newer price data available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if result.refreshFeedback == .updated {
                        Text("Price updated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                noQuoteState
            }

            if result.resolvedScan.request.subject.slab != nil {
                Text("Beta graded pricing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// Each state says what happened in a few words. A line beneath appears only
    /// when there is something to do; the provider-level reason waits behind
    /// Why? for anyone who wants it.
    @ViewBuilder
    private var noQuoteState: some View {
        switch result.quoteState {
        case .mappingUnavailable:
            NoPriceState(
                "No price yet",
                systemImage: "tag",
                why: "This exact printing and finish isn’t linked to a marketplace listing yet, so no price was checked."
            )
        case .checking where result.isRefreshing || result.shouldAutoRefresh:
            VStack(spacing: 10) {
                ProgressView()
                Text("Checking price…")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checking current price")
        case .checking:
            NoPriceState("Price check paused", systemImage: "pause.circle")
        case .noExactPrice:
            exactPriceUnavailableState
        case .notMatched:
            NoPriceState(
                "No price found",
                systemImage: "questionmark.folder",
                why: "The price provider doesn’t have a product matched to this card yet."
            )
        case .unsupportedFinish:
            NoPriceState(
                "No price for this finish",
                systemImage: "tag.slash",
                why: "The backup price source can’t tell this finish apart from others, so it wasn’t asked."
            )
        case .unsupportedGame:
            NoPriceState("No prices for this game", systemImage: "tag.slash")
        case .unsupportedTreatment:
            NoPriceState(
                "No price for this treatment",
                systemImage: "tag.slash",
                why: "The backup price source can’t identify this treatment exactly. A guess could show another printing’s price."
            )
        case .gradedGradeNotPriced:
            NoPriceState(
                "No price for this grade",
                systemImage: "seal",
                why: "The card was found, but no price is published for this grader and grade."
            )
        case .gradedProductNotMatched:
            NoPriceState(
                "No graded price found",
                systemImage: "questionmark.folder",
                why: "The graded price source couldn’t match this card."
            )
        case .gradedCardNotTracked:
            NoPriceState(
                "No graded price found",
                systemImage: "questionmark.folder",
                why: "JustTCG has no graded card with this name, set and number."
            )
        case .gradedCardHasNoPrices:
            NoPriceState(
                "No graded sales yet",
                systemImage: "seal",
                why: "JustTCG knows this card but has no graded listings for it yet."
            )
        case .gradedGradeNotTracked:
            NoPriceState(
                "No price for this grade",
                systemImage: "seal",
                detail: gradedMarketContext,
                why: gradedMarketContext == nil
                    ? "JustTCG lists other grades for this card, but not this one."
                    : nil
            )
        case .providerUnavailable:
            NoPriceState("Couldn’t reach prices", systemImage: "wifi.exclamationmark", detail: "Try again shortly.")
        case .fallbackDisabled:
            NoPriceState("Backup prices are off", systemImage: "gearshape") { openSettingsButton }
        case .fallbackUnconfigured:
            NoPriceState("Backup prices need a key", systemImage: "key.horizontal") { openSettingsButton }
        case let .rateLimited(retryAt):
            NoPriceState(
                "Too many price checks",
                systemImage: "hourglass",
                detail: "Try again \(retryAt.formatted(date: .abbreviated, time: .shortened))."
            )
        case let .budgetLimited(resetAt):
            NoPriceState(
                "Backup price checks used up",
                systemImage: "calendar.badge.clock",
                detail: "Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))."
            )
        case .current, .stale, .lastKnown(_):
            exactPriceUnavailableState
        }
    }

    private var exactPriceUnavailableState: some View {
        NoPriceState(
            hasTreatment ? "No price for this treatment" : "No price for this finish",
            systemImage: "dollarsign.circle",
            why: hasTreatment
                ? "No listing matches this treatment exactly, and a price is never borrowed from another printing."
                : "The price provider found this card but has no listing for its exact finish."
        )
    }

    private var openSettingsButton: some View {
        Button("Open Settings", systemImage: "gearshape") {
            isShowingSettings = true
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Opens Pricing Settings.")
    }

    private func lastKnownMessage(for issue: PriceCheckRefreshIssue) -> String {
        switch issue {
        case .providerUnavailable:
            return "Couldn’t update — showing last known"
        case .fallbackDisabled:
            return "Backup prices are off — showing last known"
        case .fallbackUnconfigured:
            return "Backup prices need a key — showing last known"
        case .rateLimited:
            return "Too many checks — showing last known"
        case .budgetLimited:
            return "Backup checks used up — showing last known"
        case .mappingUnavailable, .noExactPrice, .notMatched, .unsupportedFinish,
             .unsupportedGame, .unsupportedTreatment, .gradedGradeNotPriced,
             .gradedProductNotMatched, .gradedCardNotTracked, .gradedCardHasNoPrices,
             .gradedGradeNotTracked:
            return "No current price — showing last known"
        }
    }

    private var gradedMarketContext: String? {
        guard let coverage = result.resolvedScan.gradedOutcome?.marketCoverage,
              coverage.status == .gradeNotListed,
              !coverage.listedGrades.isEmpty else { return nil }
        let entries = coverage.listedGrades.prefix(6).map { listed in
            guard let amount = listed.marketPriceUSD else { return listed.displayName }
            return "\(listed.displayName) \(amount.formatted(.currency(code: "USD")))"
        }
        return "Other grades: \(entries.joined(separator: ", "))"
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
            return "\(prefix)\(source) · Price data as of \(asOf.formatted(date: .abbreviated, time: .shortened))"
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

/// A missing price, said briefly. `detail` is for something the person can act
/// on; `why` holds the provider-level reason behind a Why? popover.
private struct NoPriceState<Actions: View>: View {
    let title: String
    let systemImage: String
    var detail: String?
    var why: String?
    @ViewBuilder var actions: () -> Actions
    @State private var isShowingWhy = false

    init(
        _ title: String,
        systemImage: String,
        detail: String? = nil,
        why: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.why = why
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let why {
                Button("Why?") { isShowingWhy = true }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
                    .accessibilityHint(why)
                    .popover(isPresented: $isShowingWhy) {
                        Text(why)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .frame(idealWidth: 300)
                            .presentationCompactAdaptation(.popover)
                    }
            }
            actions()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 8)
    }
}
