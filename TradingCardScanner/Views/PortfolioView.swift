import SwiftUI
import SwiftData
import UIKit

/// One meaning per colour.
///
/// Green stopped meaning "gain" the moment it also meant "this is the
/// portfolio": a red loss beside a green current value reads as two facts of
/// the same kind, and the eye has to be told which green is which. So value is
/// neutral, direction is green/red, and orange is reserved for things a person
/// can actually act on.
enum PortfolioPalette {
    /// Positive market or performance movement, and nothing else.
    static let gain = Color(red: 0.118, green: 0.557, blue: 0.243)
    /// Negative movement, and nothing else.
    static let loss = Color(red: 0.788, green: 0.231, blue: 0.192)
    /// An actionable integrity or provider problem. Never decoration.
    static let attention = Color(uiColor: .systemOrange)
    /// The valuation itself. Deliberately not a signal colour — it is the
    /// subject of the screen, not a judgement about it.
    static let value = Color.primary
    /// The money/refresh accent shared by collection and portfolio controls,
    /// distinct from the neutral value text and from gain/loss direction.
    static let money = Color(red: 0.18, green: 0.55, blue: 0.34)

    static func direction(_ amount: Money) -> Color {
        if amount.isZero { return .secondary }
        return amount < .zero ? loss : gain
    }

    static func directionFill(_ amount: Money) -> Color {
        if amount.isZero { return Color(uiColor: .systemGray).opacity(0.12) }
        return amount < .zero
            ? Color(uiColor: .systemRed).opacity(0.12)
            : Color(uiColor: .systemGreen).opacity(0.14)
    }
}

private let portfolioMoversExplanation = "Movers reflect market price changes while you owned these holdings. Added, removed, corrected, newly priced, and re-sourced values are excluded."

struct PortfolioInfoButton<Content: View>: View {
    let label: String
    private let content: () -> Content
    @State private var isPresented = false

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .imageScale(.small)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popover(isPresented: $isPresented) {
            content()
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct PortfolioDetailsDestination: Identifiable, Hashable {
    let id = UUID()
    let summary: PortfolioSummary
    let historyResult: PortfolioHistoryResult?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// The collection's home screen. It presents the value and accounting already
/// produced by `PortfolioEngine`; it never recomputes or replays history itself.
struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var portfolio: PortfolioEngine
    /// Deliberately unobserved. A running refresh publishes progress on a
    /// one-second cadence, and observing it here re-evaluated the hero, the chart, the
    /// movers and every holding row on each publication. The two places that
    /// actually read it are child views below — the same isolation the
    /// app-scoped `StoreRevisionMonitor` applies in `ContentView`.
    let refresh: PriceRefreshController
    @ObservedObject var history: PortfolioHistoryStore
    let onRefresh: @MainActor () async -> Void
    let onOpenCollectionSortedByPrice: @MainActor () -> Void
    @State private var isShowingSettings = false
    @State private var contributorContext: PortfolioContributorContext?
    @State private var detailsDestination: PortfolioDetailsDestination?
    @State private var pendingRemoval: RemovedCardSnapshot?
    @State private var removalErrorMessage: String?
    @State private var isShowingQuantityRepairConfirmation = false
    @State private var quantityRepairError: String?
    @State private var isRebuildingPortfolioEvidence = false

    private var historyRange: PortfolioHistoryRange {
        get { history.range }
        nonmutating set { history.range = newValue }
    }

    /// The history result that actually belongs to the current selection.
    ///
    /// `historyResult` arrives asynchronously, so between changing the range and
    /// the replacement landing it still holds the *previous* period's
    /// accounting. Rendering that under the new label would state a 1M total
    /// beside a 3M heading — a mismatch a person has no way to detect. Anything
    /// that describes the selected period reads this and shows nothing until a
    /// matching result exists.
    private var activeHistoryResult: PortfolioHistoryResult? {
        history.activeResult
    }

    private var startsAtPhase3DebugSection: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_route"),
              arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "PortfolioPhase3"
#else
        return false
#endif
    }

    private var opensContributorsDebugScreen: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_route"),
              arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "PortfolioContributors"
#else
        return false
#endif
    }

    private var startsAtMostValuableCardsDebugSection: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_route"),
              arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "PortfolioMostValuable"
#else
        return false
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        portfolioHero
                            .padding(.horizontal, 16)

                        if let summary = portfolio.summary {
                            if !summary.defects.isEmpty {
                                integrityWarning(summary.defects)
                                    .padding(.horizontal, 16)
                            }

                            if summary.isAuthoritative {
                                VStack(alignment: .leading, spacing: 14) {
                                    PortfolioHistoryView(history: history)
                                    periodControl
                                        .padding(.horizontal, 16)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                bestCardsRail
                                    .id("most-valuable-cards-owned")

                                biggestMovers { result in
                                    detailsDestination = PortfolioDetailsDestination(
                                        summary: summary,
                                        historyResult: result
                                    )
                                }
                                .padding(.horizontal, 16)
                                .id("phase3-movers")
                            }

                        } else if !portfolio.integrityDefects.isEmpty {
                            integrityWarning(portfolio.integrityDefects)
                                .padding(.horizontal, 16)
                        } else {
                            ProgressView("Calculating portfolio…")
                                .frame(maxWidth: .infinity, minHeight: 140)
                        }
                    }
                    .padding(.bottom, 8)
                    .contentWidthLimit(.wide)
                }
                .task(id: portfolio.inputRevision) {
                    guard startsAtMostValuableCardsDebugSection else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    proxy.scrollTo("most-valuable-cards-owned", anchor: .top)
                }
                .task {
                    guard startsAtPhase3DebugSection else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    proxy.scrollTo("phase3-movers", anchor: .top)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let summary = portfolio.summary {
                        Button("Pricing and data details", systemImage: "info.circle") {
                            detailsDestination = PortfolioDetailsDestination(
                                summary: summary,
                                historyResult: activeHistoryResult
                            )
                        }
                        .labelStyle(.iconOnly)
                        .modifier(
                            PortfolioAttentionBadge(
                                refresh: refresh,
                                needsAttentionFromPortfolio: needsAttentionFromPortfolio
                            )
                        )
                    }

                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $detailsDestination) { destination in
                PortfolioDetailsView(
                    summary: destination.summary,
                    refresh: refresh,
                    historyResult: destination.historyResult
                )
            }
            .navigationDestination(item: $contributorContext) { context in
                PortfolioContributorsView(
                    context: context,
                    holdings: portfolio.holdings,
                    history: history,
                    onRemoved: presentUndo(for:)
                )
            }
            .task(id: portfolio.inputRevision) {
                guard opensContributorsDebugScreen,
                      let attribution = portfolio.summary?.attribution else { return }
                contributorContext = todayContext(attribution)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .alert(
            "Reconciliation failed",
            isPresented: Binding(
                get: { quantityRepairError != nil },
                set: { if !$0 { quantityRepairError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { quantityRepairError = nil }
        } message: {
            Text(quantityRepairError ?? "Try again.")
        }
        .safeAreaInset(edge: .bottom) {
            if let pendingRemoval {
                removalUndoBanner(pendingRemoval).contentWidthLimit(.standard)
            }
        }
        .alert("Removal Couldn’t Be Restored", isPresented: removalErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalErrorMessage ?? "Please try again.")
        }
    }

    private var portfolioValueAccessibilityLabel: String {
        guard let summary = portfolio.summary else {
            return portfolio.isRecomputing
                ? "Collection value unavailable. Calculating portfolio."
                : "Collection value unavailable"
        }
        let value = "Collection value, \(summary.currentValue.formatted())"
        return portfolio.isRecomputing ? "\(value). Recalculating portfolio value." : value
    }

    /// The half of "needs attention" that does not read the refresh
    /// controller. `PortfolioAttentionBadge` adds the other half, so this view
    /// never has to observe a four-times-a-second publisher to draw a dot.
    private var needsAttentionFromPortfolio: Bool {
        guard let summary = portfolio.summary else {
            return !portfolio.integrityDefects.isEmpty
        }
        if !summary.isAuthoritative || !summary.defects.isEmpty { return true }
        return !(activeHistoryResult?.accounting?.unexplained ?? .zero).isZero
    }

    private var canRepairQuantityDefects: Bool {
        let defects = portfolio.summary?.defects ?? portfolio.integrityDefects
        guard !defects.isEmpty else { return false }
        return defects.allSatisfy {
            $0.reason == .quantityMismatch && $0.canRepairQuantity
        }
    }

    private var hasAttributionDefect: Bool {
        let defects = portfolio.summary?.defects ?? portfolio.integrityDefects
        return defects.contains { $0.reason == .unattributedValueChange }
    }

    private var integrityWarningTitle: String {
        let defects = portfolio.summary?.defects ?? portfolio.integrityDefects
        if defects.isEmpty {
            return "History is paused while portfolio data reconciles."
        }
        if defects.allSatisfy({ $0.reason == .unattributedValueChange }) {
            return "A portfolio change needs pricing reconciliation."
        }
        if defects.allSatisfy({ $0.reason == .quantityMismatch && $0.canRepairQuantity }) {
            return "History is paused until the collection records reconcile."
        }
        return "History is paused until portfolio data reconciles."
    }

    private var periodControl: some View {
        let activeChange = activeHistoryResult?.accounting?.market ?? .zero
        let ranges = PortfolioHistoryRange.allCases
        // Chips hug their own text and the gaps between them absorb the slack —
        // the first sits flush against the leading gutter and the last against
        // the trailing one. Equal-width slots would centre "ALL" inside a wider
        // cell and leave a gap after it.
        return HStack(spacing: 0) {
            ForEach(Array(ranges.enumerated()), id: \.element) { index, range in
                let isSelected = range == historyRange
                Button {
                    historyRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? PortfolioPalette.direction(activeChange)
                                : .secondary
                        )
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? PortfolioPalette.directionFill(activeChange)
                                : .clear,
                            in: Capsule()
                        )
                }
                .accessibilityLabel(range.accessibilityName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if index < ranges.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Choose the period used for the portfolio summary, chart, and movers.")
    }

    /// The valuation, and nothing that depends on a period.
    ///
    /// The decorative sparkline is gone: there is one authoritative trend
    /// display, and it is the chart a person can actually scrub.
    private var portfolioHero: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Current value")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let currentValue = portfolio.summary?.currentValue {
                        let parts = currentValue.heroParts()
                        Text(parts.whole)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PortfolioPalette.value)
                        if !parts.fraction.isEmpty {
                            Text(parts.fraction)
                                // Between .secondary and .tertiary: the cents
                                // recede without dropping out of the number.
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.75))
                        }
                    } else {
                        Text("Value unavailable")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PortfolioPalette.value)
                    }
                }
                .monospacedDigit()
                // −0.02em at 54pt. Tabular figures set loose at display size;
                // the mockup pulls them back together.
                .tracking(-1.08)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
                .animation(.snappy, value: portfolio.summary?.currentValue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(portfolioValueAccessibilityLabel)

                PortfolioRefreshButton(refresh: refresh, onRefresh: onRefresh)
            }

            if portfolio.summary?.isAuthoritative == true,
               let accounting = activeHistoryResult?.accounting {
                let trailingText = PortfolioHistoryDisplay.percentChange(
                    amount: accounting.market,
                    anchor: accounting.anchorValue
                ).map { "· \(abs($0).formatted(.percent.precision(.fractionLength(2))))" }
                HStack(spacing: 8) {
                    PortfolioAmountPill(
                        amount: accounting.market,
                        showsArrow: true,
                        trailingText: trailingText
                    )
                    Text(historyRange.marketMovementPhrase)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            PriceRefreshActivityRow(
                refresh: refresh,
                isRecomputing: portfolio.isRecomputing
            )

            if portfolio.summary?.isMigrationDay == true {
                Text("Tracking started today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func integrityWarning(_ defects: [LedgerIntegrityDefect]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                integrityWarningTitle,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PortfolioPalette.attention)

            ForEach(defects) { defect in
                Text(defect.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if canRepairQuantityDefects {
                Button("Reconcile with Collection") {
                    isShowingQuantityRepairConfirmation = true
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(PortfolioPalette.attention)
                .accessibilityHint("Records append-only quantity corrections without changing collection contents")
                .confirmationDialog(
                    "Reconcile with Collection",
                    isPresented: $isShowingQuantityRepairConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reconcile") {
                        repairQuantityMismatches()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your collection contents will remain unchanged. Append-only quantity correction events will be recorded for the mismatched positions.")
                }
            }

            if hasAttributionDefect {
                Button {
                    rebuildPortfolioEvidence()
                } label: {
                    if isRebuildingPortfolioEvidence {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Rebuild pricing evidence")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(isRebuildingPortfolioEvidence)
                .accessibilityHint("Re-reads stored price records and rebuilds missing local pricing evidence without changing collection contents")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            PortfolioPalette.attention.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func repairQuantityMismatches() {
        let defects = portfolio.summary?.defects ?? portfolio.integrityDefects
        guard !defects.isEmpty else { return }
        do {
            try CollectionStore.repairQuantityMismatches(defects, in: modelContext)
            portfolio.recompute(context: modelContext)
        } catch {
            quantityRepairError = "No changes were saved. The repair can be retried after the records are available."
        }
    }

    private func rebuildPortfolioEvidence() {
        guard !isRebuildingPortfolioEvidence else { return }
        isRebuildingPortfolioEvidence = true
        Task { @MainActor in
            await portfolio.recomputeAndWait(context: modelContext)
            isRebuildingPortfolioEvidence = false
        }
    }

    @ViewBuilder
    private func biggestMovers(
        _ onOpenDetails: @escaping (PortfolioHistoryResult) -> Void
    ) -> some View {
        if let active = activeHistoryResult {
            let total = active.accounting?.market ?? .zero
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text("What moved · \(active.range.rawValue)")
                            .font(.title3.weight(.bold))
                        PortfolioInfoButton(label: "About market movers") {
                            PortfolioMoversInfoPopover(
                                result: active,
                                onOpenDetails: onOpenDetails
                            )
                        }
                        .imageScale(.small)
                    }
                    Spacer(minLength: 8)
                    Button("See all") {
                        contributorContext = historicalContext(from: active)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Text(PortfolioHistoryDisplay.signedCurrency(total))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(PortfolioPalette.direction(total))

                if !active.hasEligibleMarketMovement {
                    Label("No market movement in \(active.range.rawValue)", systemImage: "minus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    PortfolioContributorPreview(
                        contributions: active.contributions,
                        total: total,
                        holdings: portfolio.holdings,
                        movementDetails: active.movementDetails,
                        history: history,
                        onRemoved: presentUndo(for:)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Recomputing for a newly chosen period. Say nothing rather than
            // claim the market was flat.
            EmptyView()
        }
    }

    @ViewBuilder
    private var bestCardsRail: some View {
        // The publisher orders priced holdings before unpriced holdings, so
        // stop at the first missing value instead of allocating a filtered
        // copy of the entire holdings array on every body evaluation.
        let ranked = portfolio.holdings.prefix(while: { $0.holdingValue != nil })

        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your best cards")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Button("See all") {
                        onOpenCollectionSortedByPrice()
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHint("Opens Collection sorted by price, highest first")
                }
                .accessibilityElement(children: .combine)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(ranked.prefix(5)) { holding in
                            NavigationLink {
                                PortfolioOwnedCardDestination(
                                    collectionKey: holding.collectionKey,
                                    holding: holding,
                                    history: history,
                                    onRemoved: presentUndo(for:)
                                )
                            } label: {
                                PortfolioBestCardTile(
                                    holding: holding,
                                    unitMovement: activeHistoryResult?.movement(for: holding.collectionKey)?.cumulativeUnitMovement
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.bottom, 4, for: .scrollContent)
            }
        }
    }

    // MARK: - Removal undo

    private func presentUndo(for removed: RemovedCardSnapshot) {
        pendingRemoval = removed
    }

    private func undoRemoval(_ removed: RemovedCardSnapshot) {
        do {
            try CollectionStore(context: modelContext).restore(removed)
            pendingRemoval = nil
        } catch {
            removalErrorMessage = error.localizedDescription
        }
    }

    private var removalErrorBinding: Binding<Bool> {
        Binding(
            get: { removalErrorMessage != nil },
            set: { if !$0 { removalErrorMessage = nil } }
        )
    }

    private func removalUndoBanner(_ removed: RemovedCardSnapshot) -> some View {
        RemovalUndoBanner(
            name: removed.name,
            onUndo: { undoRemoval(removed) },
            onDismiss: { pendingRemoval = nil }
        )
    }

    private func todayContext(_ attribution: PortfolioClose.Attribution) -> PortfolioContributorContext {
        let today = PortfolioCalendar.day(
            containing: .now,
            in: PortfolioCalendar.pinnedTimeZone() ?? .current
        )
        return PortfolioContributorContext(
            id: "today-\(today.timeIntervalSinceReferenceDate)",
            title: "Today’s market movement",
            total: attribution.market,
            contributions: portfolio.contributionIndex.byDay[today, default: [:]],
            movementDetails: portfolio.contributionIndex.detailsByDay[today, default: [:]],
            hasEligibleMarketMovement: portfolio.contributionIndex.daysWithEligibleMarketMovement.contains(today),
            coverageDescription: todayCoverageDescription(portfolio.summary?.coverage)
        )
    }

    private func historicalContext(from result: PortfolioHistoryResult) -> PortfolioContributorContext {
        PortfolioContributorContext(
            id: "history-\(result.range.rawValue)-\(result.accountingInterval?.anchorDate.timeIntervalSinceReferenceDate ?? 0)",
            title: "Contributors · \(result.range.rawValue)",
            total: result.accounting?.market ?? .zero,
            contributions: result.contributions,
            movementDetails: result.movementDetails,
            hasEligibleMarketMovement: result.hasEligibleMarketMovement,
            coverageDescription: historyCoverageDescription(result.coverage)
        )
    }

    private func todayCoverageDescription(_ coverage: PortfolioCoverage?) -> String? {
        guard let coverage else { return nil }
        return "\(coverage.refreshed) of \(coverage.total) holdings checked today"
    }

    private func historyCoverageDescription(_ coverage: PortfolioHistoryCoverage) -> String {
        var text = "Coverage: \(coverage.completeDays) complete · \(coverage.partialDays) partial · \(coverage.unknownDays) unknown days"
        if let live = coverage.live {
            text += "\nToday: \(live.refreshed) checked · \(live.carriedForward) carried forward"
        }
        return text
    }

    @ViewBuilder
    private func coverage(_ coverage: PortfolioCoverage) -> some View {
        switch coverage.state {
        case .unknown:
            EmptyView()
        case .complete:
            Label("\(coverage.refreshed) of \(coverage.total) checked today", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .partial:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(coverage.refreshed) of \(coverage.total) checked today")
                    .font(.subheadline.weight(.semibold))
                Text("\(coverage.carriedForward) still show an earlier price.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

}

private struct PortfolioMoversInfoPopover: View {
    let result: PortfolioHistoryResult
    let onOpenDetails: (PortfolioHistoryResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(portfolioMoversExplanation)
                .font(.body)
            Button("Full accounting") {
                dismiss()
                onOpenDetails(result)
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: 280, alignment: .leading)
        .padding()
    }
}

private struct PortfolioContributorContext: Identifiable, Hashable {
    let id: String
    let title: String
    let total: Money
    let contributions: [String: Money]
    let movementDetails: [String: PortfolioContributionDetail]
    let hasEligibleMarketMovement: Bool
    let coverageDescription: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct PortfolioContributionRowModel: Identifiable {
    enum Kind {
        case holding(PortfolioHoldingSnapshot)
        case previouslyOwned
        case otherHoldings
    }

    let kind: Kind
    let amount: Money
    let movementDetail: PortfolioContributionDetail?

    var id: String {
        switch kind {
        case let .holding(holding): return holding.collectionKey
        case .previouslyOwned: return "previously-owned"
        case .otherHoldings: return "other-holdings"
        }
    }

    var collectionKey: String? {
        if case let .holding(holding) = kind { return holding.collectionKey }
        return nil
    }

    var title: String {
        switch kind {
        case let .holding(holding): return holding.name
        case .previouslyOwned: return "Former or unmatched holdings"
        case .otherHoldings: return "Remaining contributors"
        }
    }

    var detail: String? {
        switch kind {
        case let .holding(holding):
            return holding.detail
        case .previouslyOwned, .otherHoldings: return nil
        }
    }

    var holding: PortfolioHoldingSnapshot? {
        if case let .holding(holding) = kind { return holding }
        return nil
    }
}

private enum PortfolioContributionOrder: String, CaseIterable, Identifiable {
    case impact = "Impact"
    case gainers = "Gainers"
    case losers = "Losers"

    var id: String { rawValue }
}

private enum PortfolioContributionPresentation {
    static func rows(
        contributions: [String: Money],
        holdings: [PortfolioHoldingSnapshot],
        movementDetails: [String: PortfolioContributionDetail] = [:]
    ) -> [PortfolioContributionRowModel] {
        let byKey = Dictionary(holdings.map { ($0.collectionKey, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [PortfolioContributionRowModel] = []
        var unknown = Money.zero
        for (key, amount) in contributions where !amount.isZero {
            if let holding = byKey[key] {
                result.append(
                    PortfolioContributionRowModel(
                        kind: .holding(holding),
                        amount: amount,
                        movementDetail: movementDetails[key]
                    )
                )
            } else {
                unknown += amount
            }
        }
        if !unknown.isZero {
            result.append(
                PortfolioContributionRowModel(
                    kind: .previouslyOwned,
                    amount: unknown,
                    movementDetail: nil
                )
            )
        }
        return result
    }

    static func sorted(
        _ rows: [PortfolioContributionRowModel],
        order: PortfolioContributionOrder
    ) -> [PortfolioContributionRowModel] {
        let filtered: [PortfolioContributionRowModel]
        switch order {
        case .impact: filtered = rows
        case .gainers: filtered = rows.filter { $0.amount.tenThousandths > 0 }
        case .losers: filtered = rows.filter { $0.amount.tenThousandths < 0 }
        }
        return filtered.sorted { lhs, rhs in
            comesBefore(lhs, rhs, order: order)
        }
    }

    /// Selects the leading rows without sorting the entire contribution list.
    /// The preview only renders three rows, while the full contributor sheet
    /// still uses `sorted` when it needs the complete order.
    static func top(
        _ rows: [PortfolioContributionRowModel],
        order: PortfolioContributionOrder,
        limit: Int
    ) -> [PortfolioContributionRowModel] {
        guard limit > 0 else { return [] }
        let filtered: [PortfolioContributionRowModel]
        switch order {
        case .impact: filtered = rows
        case .gainers: filtered = rows.filter { $0.amount.tenThousandths > 0 }
        case .losers: filtered = rows.filter { $0.amount.tenThousandths < 0 }
        }

        var selected: [PortfolioContributionRowModel] = []
        selected.reserveCapacity(min(limit, filtered.count))
        for row in filtered {
            let insertionIndex = selected.firstIndex {
                comesBefore(row, $0, order: order)
            }
            if let insertionIndex {
                selected.insert(row, at: insertionIndex)
            } else {
                selected.append(row)
            }
            if selected.count > limit { selected.removeLast() }
        }
        return selected
    }

    private static func comesBefore(
        _ lhs: PortfolioContributionRowModel,
        _ rhs: PortfolioContributionRowModel,
        order: PortfolioContributionOrder
    ) -> Bool {
        switch order {
        case .impact:
            if lhs.amount.magnitude != rhs.amount.magnitude { return lhs.amount.magnitude > rhs.amount.magnitude }
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        case .gainers:
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        case .losers:
            if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
        }
        return lhs.id < rhs.id
    }

    static func signed(_ amount: Money) -> String {
        let sign = amount.tenThousandths < 0 ? "−" : "+"
        return sign + amount.magnitude.formatted()
    }

    static func color(_ amount: Money) -> Color { PortfolioPalette.direction(amount) }

    static func movementBreakdownText(for row: PortfolioContributionRowModel) -> String? {
        guard row.holding != nil else { return nil }
        guard let detail = row.movementDetail,
              detail.totalImpact == row.amount,
              detail.hasConsistentQuantity,
              let quantity = detail.affectedQuantities.first,
              quantity > 0,
              !detail.cumulativeUnitMovement.isZero else {
            if row.movementDetail?.affectedQuantities.count ?? 0 > 1 {
                return "Quantity varied · per-card movement unavailable"
            }
            return nil
        }

        if quantity == 1 {
            return "\(signed(detail.cumulativeUnitMovement)) per card"
        }
        let copyLabel = "copies"
        return "\(quantity) \(copyLabel) × \(signed(detail.cumulativeUnitMovement)) per card"
    }

    static func shareOfCurrentHolding(_ row: PortfolioContributionRowModel) -> Double? {
        guard let value = row.holding?.holdingValue,
              value.isValid,
              !value.isZero,
              row.amount.isValid else { return nil }
        let share = row.amount.magnitude.doubleValue / value.doubleValue
        return share.isFinite ? share : nil
    }
}

private struct PortfolioContributorPreview: View {
    let contributions: [String: Money]
    let total: Money
    let holdings: [PortfolioHoldingSnapshot]
    let movementDetails: [String: PortfolioContributionDetail]
    let history: PortfolioHistoryStore
    let onRemoved: (RemovedCardSnapshot) -> Void

    private var previewRows: [PortfolioContributionRowModel] {
        let all = PortfolioContributionPresentation.rows(
            contributions: contributions,
            holdings: holdings,
            movementDetails: movementDetails
        )
        let displayed = PortfolioContributionPresentation.top(
            all,
            order: .impact,
            limit: 3
        )
        let residual = total - displayed.map(\.amount).sum()
        var previewRows = displayed
        if all.count > displayed.count {
            previewRows.append(
                PortfolioContributionRowModel(
                    kind: .otherHoldings,
                    amount: residual,
                    movementDetail: nil
                )
            )
        }
        return previewRows
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(previewRows.enumerated()), id: \.element.id) { index, row in
                previewRow(row)
                    .padding(.vertical, 8)

                if index < previewRows.count - 1 {
                    Color(uiColor: .quaternaryLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func previewRow(_ row: PortfolioContributionRowModel) -> some View {
        if let key = row.collectionKey {
            NavigationLink {
                PortfolioOwnedCardDestination(
                    collectionKey: key,
                    holding: row.holding,
                    history: history,
                    onRemoved: onRemoved
                )
            } label: {
                PortfolioContributionRow(
                    row: row,
                    showsHoldingShare: false,
                    style: .mover
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this holding")
        } else {
            PortfolioContributionRow(
                row: row,
                showsHoldingShare: false,
                style: .mover
            )
        }
    }
}

private struct PortfolioContributorsView: View {
    let context: PortfolioContributorContext
    let holdings: [PortfolioHoldingSnapshot]
    let history: PortfolioHistoryStore
    let onRemoved: (RemovedCardSnapshot) -> Void
    @State private var order: PortfolioContributionOrder = .impact

    var body: some View {
        let rows = PortfolioContributionPresentation.sorted(
            PortfolioContributionPresentation.rows(
                contributions: context.contributions,
                holdings: holdings,
                movementDetails: context.movementDetails
            ),
            order: order
        )
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(PortfolioContributionPresentation.signed(context.total))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(PortfolioContributionPresentation.color(context.total))
                    }
                    Spacer(minLength: 8)
                    PortfolioInfoButton(label: "About market movers") {
                        Text(portfolioMoversExplanation)
                            .font(.body)
                            .frame(maxWidth: 280, alignment: .leading)
                            .padding()
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Contributor order", selection: $order) {
                    ForEach(PortfolioContributionOrder.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if rows.isEmpty {
                Section {
                    Text(context.hasEligibleMarketMovement
                         ? "Market updates offset to no net contributor impact."
                         : "No market movement during this period")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(order.rawValue) {
                    ForEach(rows) { row in
                        if let key = row.collectionKey {
                            NavigationLink {
                                PortfolioOwnedCardDestination(
                                    collectionKey: key,
                                    holding: row.holding,
                                    history: history,
                                    onRemoved: onRemoved
                                )
                            } label: {
                                PortfolioContributionRow(
                                    row: row,
                                    showsHoldingShare: true
                                )
                            }
                        } else {
                            PortfolioContributionRow(
                                row: row,
                                showsHoldingShare: true
                            )
                        }
                    }
                }
            }

            if let coverage = context.coverageDescription {
                Section {
                    Text(coverage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Contributors")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PortfolioContributionRow: View {
    enum Style: Equatable {
        case standard
        case mover

        var artworkWidth: CGFloat { self == .mover ? 38 : 34 }
        var artworkHeight: CGFloat { self == .mover ? 52 : 46 }
        var artworkCornerRadius: CGFloat { 5 }
        var horizontalSpacing: CGFloat { self == .mover ? 12 : 10 }
        var minHeight: CGFloat { self == .mover ? 56 : 44 }
        var titleFont: Font? {
            self == .mover
                ? .system(size: 16, weight: .regular)
                : nil
        }
        /// Monospaced *digits*, not a monospaced face: the subtitle carries
        /// set names and finishes as often as it carries figures.
        var subtitleFont: Font {
            self == .mover
                ? .system(size: 12, weight: .regular).monospacedDigit()
                : .caption
        }
        var placeholderFont: Font? {
            self == .mover
                ? .system(size: 20, weight: .regular)
                : nil
        }
        var titleLineLimit: Int? { self == .mover ? 1 : nil }
    }

    let row: PortfolioContributionRowModel
    let showsHoldingShare: Bool
    let style: Style

    init(
        row: PortfolioContributionRowModel,
        showsHoldingShare: Bool,
        style: Style = .standard
    ) {
        self.row = row
        self.showsHoldingShare = showsHoldingShare
        self.style = style
    }

    var body: some View {
        HStack(spacing: style.horizontalSpacing) {
            if let holding = row.holding {
                PortfolioArtwork(
                    holding: holding,
                    width: style.artworkWidth,
                    height: style.artworkHeight,
                    cornerRadius: style.artworkCornerRadius
                )
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(style.placeholderFont)
                    .foregroundStyle(.secondary)
                    .frame(width: style.artworkWidth, height: style.artworkHeight)
            }
            VStack(alignment: .leading, spacing: style == .mover ? 1 : 2) {
                Text(row.title)
                    .font(style.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(style.titleLineLimit)
                if let subtitle = PortfolioContributionPresentation.movementBreakdownText(for: row) ?? row.detail,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(style.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                PortfolioAmountPill(amount: row.amount)
                if showsHoldingShare,
                   let share = PortfolioContributionPresentation.shareOfCurrentHolding(row) {
                    Text("\(share.formatted(.percent.precision(.fractionLength(1)))) of current value")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: style.minHeight)
        .accessibilityElement(children: .combine)
    }
}

private struct PortfolioBestCardTile: View {
    let holding: PortfolioHoldingSnapshot
    /// Per-copy market movement for the active period, when known. Omitted
    /// (not zero-filled) when there's nothing to say — never fabricate a
    /// number the ledger hasn't actually produced.
    let unitMovement: Money?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PortfolioArtwork(holding: holding, width: 136, height: 190, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let value = holding.holdingValue {
                        Text(value.formatted())
                            .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    if holding.quantity > 1 {
                        Text("×\(holding.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if let unitMovement, !unitMovement.isZero {
                    Text("\(PortfolioContributionPresentation.signed(unitMovement)) per card")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PortfolioPalette.direction(unitMovement))
                }
            }
        }
        .frame(width: 136, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                holding.name,
                holding.holdingValue.map {
                    "\($0.formatted())\(holding.quantity > 1 ? " total" : "")"
                },
                holding.quantity > 1 ? "quantity \(holding.quantity)" : nil,
                unitMovement.flatMap {
                    $0.isZero ? nil : "\(PortfolioContributionPresentation.signed($0)) per card"
                }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }
}

private struct PortfolioAmountPill: View {
    let amount: Money
    var showsArrow: Bool = false
    var trailingText: String? = nil

    private var arrowReplacesSign: Bool {
        showsArrow && !amount.isZero
    }

    private var visibleAmountText: String {
        arrowReplacesSign
            ? amount.magnitude.formatted()
            : PortfolioContributionPresentation.signed(amount)
    }

    private var spokenLabel: String {
        let amountLabel = visibleAmountText
        let trailingLabel = trailingText?
            .replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: "%", with: " percent")
            .trimmingCharacters(in: .whitespaces)

        if arrowReplacesSign {
            let direction = amount < .zero ? "down" : "up"
            if let trailingLabel, !trailingLabel.isEmpty {
                return "\(direction) \(amountLabel), \(trailingLabel)"
            }
            return "\(direction) \(amountLabel)"
        }

        if let trailingLabel, !trailingLabel.isEmpty {
            return "\(amountLabel), \(trailingLabel)"
        }
        return amountLabel
    }

    var body: some View {
        HStack(spacing: 3) {
            if arrowReplacesSign {
                Image(systemName: amount < .zero ? "arrow.down" : "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(visibleAmountText)
            if let trailingText {
                Text(trailingText)
            }
        }
        .font(.system(size: 14, weight: .semibold).monospacedDigit())
        .foregroundStyle(PortfolioPalette.direction(amount))
        // Asymmetric on purpose: the arrow's own side bearing already reads as
        // space, so the leading inset is tighter than the trailing one.
        .padding(.leading, arrowReplacesSign ? 7 : 9)
        .padding(.trailing, arrowReplacesSign ? 10 : 9)
        .padding(.vertical, 4)
        .background(PortfolioPalette.directionFill(amount), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}

private struct PortfolioArtwork: View {
    let holding: PortfolioHoldingSnapshot
    var width: CGFloat = 34
    var height: CGFloat = 46
    var cornerRadius: CGFloat = 5

    var body: some View {
        Group {
            if let image = CollectionArtworkStore.image(
                filename: holding.userArtworkFilename,
                maximumPixelDimension: 512
            ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                CatalogCachedImage(
                    url: holding.artworkURL,
                    fallbackURL: holding.artworkFallbackURL,
                    placeholderSymbol: "rectangle.stack"
                )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct PortfolioOwnedCardDestination: View {
    @EnvironmentObject private var priceSnapshot: PriceSnapshotStore
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @Query private var cards: [CollectedCard]
    let collectionKey: String
    let holding: PortfolioHoldingSnapshot?
    @ObservedObject var history: PortfolioHistoryStore
    let onRemoved: (RemovedCardSnapshot) -> Void

    init(
        collectionKey: String,
        holding: PortfolioHoldingSnapshot? = nil,
        history: PortfolioHistoryStore,
        onRemoved: @escaping (RemovedCardSnapshot) -> Void
    ) {
        self.collectionKey = collectionKey
        self.holding = holding
        self.history = history
        self.onRemoved = onRemoved
        self._cards = Query(
            filter: #Predicate<CollectedCard> { $0.collectionKey == collectionKey },
            sort: [SortDescriptor(\CollectedCard.dateAdded, order: .forward)]
        )
    }

    var body: some View {
        if let card = cards.first {
            // Historical contributor rows do not always carry a live holding.
            // Use the same resolved instrument the collection projection used;
            // falling back directly to `card.priceKey` can disagree when a
            // legacy alias or observation-only invalidation is involved.
            let resolvedInstrumentKey = holding?.priceStorageKey
                ?? projectionStore.snapshot?.rowsByCollectionKey[collectionKey]?.priceStorageKey
            if let instrumentKey = resolvedInstrumentKey {
                let diagnostics = priceSnapshot.diagnosticsByCollectionKey[collectionKey]
                let price = priceSnapshot.display(for: instrumentKey) ?? .unknown
                CollectionCardDetailView(
                    card: card,
                    price: price,
                    history: history,
                    unpricedReason: price.amount == nil ? diagnostics?.unpricedReason : nil,
                    artworkReason: diagnostics?.artworkReason,
                    logicalQuantity: holding?.quantity ?? cards.reduce(0) { $0 + $1.quantity },
                    isLogicalConflict: cards.count > 1,
                    instrumentKey: instrumentKey,
                    onRemoved: onRemoved
                )
            } else {
                ProgressView("Loading price…")
            }
        } else {
            ContentUnavailableView(
                "Holding unavailable",
                systemImage: "rectangle.stack.badge.questionmark",
                description: Text("This holding is no longer in the current collection.")
            )
        }
    }
}

private struct PortfolioDetailsView: View {
    let summary: PortfolioSummary
    @ObservedObject var refresh: PriceRefreshController
    let historyResult: PortfolioHistoryResult?

    var body: some View {
        List {
            Section("Pricing coverage") {
                LabeledContent("Checked today", value: "\(summary.coverage.refreshed) of \(summary.coverage.total)")
                if summary.coverage.carriedForward > 0 {
                    Text("\(summary.coverage.carriedForward) copies still show an earlier price.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                refreshStatus
            }

            Section("Portfolio") {
                if summary.isMigrationDay {
                    Text("Portfolio tracking started today. The first daily close forms at midnight.")
                } else if let started = PortfolioEpoch.startedAt() {
                    LabeledContent("Tracking since", value: started.formatted(date: .abbreviated, time: .omitted))
                }

                if let revisionNote = summary.revisionNote {
                    Text(revisionNote.capitalized)
                        .foregroundStyle(.secondary)
                }

                if !summary.isAuthoritative {
                    Text("History resumes after reconciliation.")
                        .foregroundStyle(PortfolioPalette.attention)
                }
            }

            if let historyResult {
                periodEvidence(historyResult)
            }
        }
        .navigationTitle("Pricing & Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func periodEvidence(_ result: PortfolioHistoryResult) -> some View {
        Section("\(result.range.rawValue) details") {
            if let accounting = result.accounting {
                LabeledContent("Starting portfolio value", value: accounting.anchorValue.formatted())
                LabeledContent("Current portfolio value", value: accounting.endValue.formatted())
                LabeledContent("Portfolio value change", value: signed(accounting.totalChange))
                if PortfolioHistoryDisplay.hasBreakdown(accounting) {
                    LabeledContent(
                        "Cards added",
                        value: signed(accounting.added + accounting.newlyAddedValue)
                    )
                    .padding(.leading, 16)
                    LabeledContent("Cards removed", value: signed(-accounting.removed))
                        .padding(.leading, 16)
                    LabeledContent("Market movement", value: signed(accounting.market))
                        .padding(.leading, 16)
                    if !accounting.corrections.isZero {
                        LabeledContent("Corrections", value: signed(accounting.corrections))
                            .padding(.leading, 16)
                    }
                    if !accounting.pricingAdjustments.isZero {
                        LabeledContent("Pricing adjustments", value: signed(accounting.pricingAdjustments))
                            .padding(.leading, 16)
                    }
                    if !accounting.unexplained.isZero {
                        LabeledContent("Unexplained", value: signed(accounting.unexplained))
                            .foregroundStyle(PortfolioPalette.attention)
                            .padding(.leading, 16)
                    }
                } else {
                    LabeledContent("Market movement", value: signed(accounting.market))
                }
            }

            coverageEvidence(result.coverage)

            if !result.revisions.isEmpty {
                DisclosureGroup("Reconciled days (\(result.revisions.count))") {
                    ForEach(result.revisions, id: \.date) { revision in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(revision.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                            Text("Original \(revision.original.closeValue.formatted()) · Latest \(revision.latest.closeValue.formatted())")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let note = revision.latest.revisionNote {
                                Text(note).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func coverageEvidence(_ coverage: PortfolioHistoryCoverage) -> some View {
        if coverage.partialDays > 0 || coverage.unknownDays > 0 {
            Text([coverage.partialDays > 0 ? "\(coverage.partialDays) partial day\(coverage.partialDays == 1 ? "" : "s")" : nil,
                  coverage.unknownDays > 0 ? "\(coverage.unknownDays) unknown day\(coverage.unknownDays == 1 ? "" : "s")" : nil]
                .compactMap { $0 }
                .joined(separator: " · "))
                .foregroundStyle(.secondary)
        } else if coverage.completeDays > 0 {
            LabeledContent("Completed-day coverage", value: "\(coverage.completeDays) complete")
        }
        if let live = coverage.live, live.carriedForward > 0 {
            Text("Today: \(live.refreshed) checked · \(live.carriedForward) carried forward")
                .foregroundStyle(.secondary)
        }
    }

    private func signed(_ amount: Money) -> String {
        let prefix = amount.tenThousandths > 0 ? "+" : amount.tenThousandths < 0 ? "−" : ""
        return prefix + amount.magnitude.formatted()
    }

    @ViewBuilder
    private var refreshStatus: some View {
        switch refresh.fallbackStatus {
        case let .budgetReached(pending, resetAt):
            Text(
                "Vendor price checks reached their limit. \(pending) \(pending == 1 ? "check remains" : "checks remain"); resumes \(fallbackResumeTime(resetAt))."
            )
            .font(.subheadline)
            .foregroundStyle(PortfolioPalette.attention)
        case let .rateLimited(pending, retryAt):
            Text(
                "Vendor price checks are paused. \(pending) \(pending == 1 ? "check remains" : "checks remain"); retries \(fallbackResumeTime(retryAt))."
            )
            .font(.subheadline)
            .foregroundStyle(PortfolioPalette.attention)
        case .idle, .disabled, .unconfigured, .available, .running, .finished:
            switch refresh.status {
            case let .refreshing(completed, total):
                LabeledContent("Checking prices", value: "\(completed) of \(total)")
            case let .finished(result):
                Text(
                    result.targetBuildFailed
                        ? "Prices could not be read. Try again."
                        : result.providerUnreachable
                        ? "The card catalog is unreachable. Check your connection and try again."
                        : result.persistenceFailed
                            ? "Some price updates could not be saved. Try again."
                            : result.gradedTransportFailures > 0
                                ? "Some graded price checks could not be completed. Try again."
                            : result.gradedLookupMisses > 0
                                ? "Prices checked; no graded listing was found for \(result.gradedLookupMisses) owned \(result.gradedLookupMisses == 1 ? "slab" : "slabs")."
                            : result.reconciledDuplicateRecords > 0
                                ? "Prices checked; repaired \(result.reconciledDuplicateRecords) duplicate price rows."
                            : "Prices checked \(result.checkedAt.formatted(date: .omitted, time: .shortened))."
                )
                    .font(.subheadline)
                    .foregroundStyle(
                        result.targetBuildFailed
                            || result.providerUnreachable
                            || result.failed > 0
                            || result.persistenceFailed
                            || result.gradedTransportFailures > 0
                            || result.gradedLookupMisses > 0
                            || result.reconciledDuplicateRecords > 0
                            ? PortfolioPalette.attention
                            : .secondary
                    )
            case .recentlyChecked:
                Text("Prices were checked recently.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }
        }
    }

    private func fallbackResumeTime(_ date: Date) -> String {
        Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: .now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}


/// The refresh button, isolated so the four-times-a-second progress publisher
/// invalidates a 44-point control rather than the whole Portfolio tree.
private struct PortfolioRefreshButton: View {
    @ObservedObject var refresh: PriceRefreshController
    let onRefresh: @MainActor () async -> Void

    private var isRefreshing: Bool {
        if case .refreshing = refresh.status { return true }
        return false
    }

    var body: some View {
        Button("Refresh Prices", systemImage: "arrow.triangle.2.circlepath") {
            Task { await onRefresh() }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(PortfolioPalette.money)
        // 44×44 stays the tap target; the nudge sits the glyph against the
        // numerals' optical centre rather than the line box's.
        .frame(width: 44, height: 44)
        .offset(y: 6)
        .contentShape(Rectangle())
        .disabled(isRefreshing)
        .accessibilityLabel("Refresh prices")
    }
}

/// The attention dot, isolated for the same reason as the button. The half of
/// the predicate that reads the portfolio arrives already decided, so this view
/// observes the refresh controller and nothing else.
private struct PortfolioAttentionBadge: ViewModifier {
    @ObservedObject var refresh: PriceRefreshController
    let needsAttentionFromPortfolio: Bool

    private var needsAttention: Bool {
        switch refresh.fallbackStatus {
        case .budgetReached, .rateLimited:
            return true
        case .idle, .disabled, .unconfigured, .available, .running, .finished:
            break
        }
        if needsAttentionFromPortfolio { return true }
        if case let .finished(result) = refresh.status {
            return result.targetBuildFailed
                || result.providerUnreachable
                || result.failed > 0
                || result.persistenceFailed
                || result.gradedTransportFailures > 0
                || result.gradedLookupMisses > 0
                || result.reconciledDuplicateRecords > 0
        }
        return false
    }

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(
                needsAttention
                    ? "Pricing and data details, needs attention"
                    : "Pricing and data details"
            )
            .overlay(alignment: .topTrailing) {
                if needsAttention {
                    Circle()
                        .fill(PortfolioPalette.attention)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    Color(uiColor: .systemBackground),
                                    lineWidth: 1.5
                                )
                        )
                        .accessibilityHidden(true)
                }
            }
    }
}

/// One statement of what a running refresh looks like, shared by Portfolio and
/// Collection so the screen a refresh is started from and the screen reporting
/// it cannot describe the same pass differently.
///
/// Internal rather than private: this is the only view outside Portfolio that
/// is allowed to observe the refresh controller.
struct PriceRefreshActivityRow: View {
    @ObservedObject var refresh: PriceRefreshController
    /// Portfolio has a second, longer-running phase to report. Collection has
    /// nothing to say there, so it says nothing.
    var isRecomputing: Bool = false

    var body: some View {
        switch refresh.status {
        case let .refreshing(completed, total):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking \(completed) of \(total)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Checking prices \(completed) of \(total)")
        case .idle, .recentlyChecked, .finished:
            if isRecomputing {
                Label("Recalculating portfolio value", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Recalculating portfolio value")
            } else {
                EmptyView()
            }
        }
    }
}
