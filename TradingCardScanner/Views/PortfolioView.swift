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
    static let gain = Color(uiColor: .systemGreen)
    /// Negative movement, and nothing else.
    static let loss = Color(uiColor: .systemRed)
    /// An actionable integrity or provider problem. Never decoration.
    static let attention = Color(uiColor: .systemOrange)
    /// The valuation itself. Deliberately not a signal colour — it is the
    /// subject of the screen, not a judgement about it.
    static let value = Color.primary

    static func direction(_ amount: Money) -> Color {
        if amount.isZero { return .secondary }
        return amount < .zero ? loss : gain
    }
}

/// The collection's home screen. It presents the value and accounting already
/// produced by `PortfolioEngine`; it never recomputes or replays history itself.
struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var portfolio: PortfolioEngine
    @ObservedObject var refresh: PriceRefreshController
    @ObservedObject var history: PortfolioHistoryStore
    let onRefresh: @MainActor () async -> Void
    let onOpenCollectionSortedByPrice: @MainActor () -> Void
    @State private var isShowingSettings = false
    @State private var contributorContext: PortfolioContributorContext?
    @State private var pendingRemoval: RemovedCardSnapshot?
    @State private var removalErrorMessage: String?
    @State private var isShowingQuantityRepairConfirmation = false
    @State private var quantityRepairError: String?

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

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                    // Order is the argument: what it is worth, then over what
                    // period, then everything scoped to that period. The range
                    // control precedes every range-scoped number so no figure
                    // is ever read before its scope.
                    portfolioHero

                    if let summary = portfolio.summary {
                        if !summary.isAuthoritative {
                            integrityWarning(summary.defects)
                        }

                        if summary.isAuthoritative {
                            periodControl
                            periodSummary

                            PortfolioHistoryView(
                                history: history
                            )

                            biggestMovers()
                                .id("phase3-movers")
                            largestHoldings
                        }

                    } else if !portfolio.integrityDefects.isEmpty {
                        integrityWarning(portfolio.integrityDefects)
                    } else {
                        ProgressView("Calculating portfolio…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    }
                    }
                    .padding(16)
                    .contentWidthLimit(.wide)
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
                        NavigationLink {
                            PortfolioDetailsView(
                                summary: summary,
                                refresh: refresh,
                                historyResult: activeHistoryResult
                            )
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel(
                            needsPortfolioAttention
                                ? "Pricing and data details, needs attention"
                                : "Pricing and data details"
                        )
                        .overlay(alignment: .topTrailing) {
                            if needsPortfolioAttention {
                                Circle()
                                    .fill(PortfolioPalette.attention)
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                            }
                        }
                    }

                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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

    private var isRefreshing: Bool {
        if case .refreshing = refresh.status { return true }
        return false
    }

    private var needsPortfolioAttention: Bool {
        guard let summary = portfolio.summary else {
            return !portfolio.integrityDefects.isEmpty
        }
        if !summary.isAuthoritative || !summary.defects.isEmpty { return true }
        if !(activeHistoryResult?.accounting?.unexplained ?? .zero).isZero { return true }
        if case let .finished(result) = refresh.status {
            return result.providerUnreachable || result.failed > 0
        }
        return false
    }

    private var canRepairQuantityDefects: Bool {
        let defects = portfolio.summary?.defects ?? portfolio.integrityDefects
        guard !defects.isEmpty else { return false }
        return defects.allSatisfy {
            $0.reason == .quantityMismatch && $0.canRepairQuantity
        }
    }

    private var periodControl: some View {
        Picker("Portfolio period", selection: Binding(get: { historyRange }, set: { historyRange = $0 })) {
            ForEach(PortfolioHistoryRange.allCases, id: \.self) { item in
                Text(item.rawValue)
                    .accessibilityLabel(item.accessibilityName)
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose the period used for the portfolio summary, chart, and movers.")
    }

    /// The valuation, and nothing that depends on a period.
    ///
    /// The decorative sparkline is gone: there is one authoritative trend
    /// display, and it is the chart a person can actually scrub.
    private var portfolioHero: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Current value")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(portfolio.summary?.currentValue.formatted() ?? "Value unavailable")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(PortfolioPalette.value)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: portfolio.summary?.currentValue)
                    .accessibilityLabel(
                        portfolio.summary.map { "Collection value, \($0.currentValue.formatted())" }
                            ?? "Collection value unavailable"
                    )

                Button("Refresh Prices", systemImage: "arrow.clockwise") {
                    Task { await onRefresh() }
                }
                .labelStyle(.iconOnly)
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh prices")
            }

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

    /// The one period metric shown on the primary Portfolio screen.
    ///
    /// It is deliberately the same additive market movement used by the
    /// chart and contributor rows. Full portfolio-value accounting remains one
    /// explicit tap away in the details view.
    @ViewBuilder
    private var periodSummary: some View {
        if let summary = portfolio.summary,
           let result = activeHistoryResult,
           let accounting = result.accounting {
            let amount = accounting.market
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Market movement · \(historyRange.rawValue)")
                            .font(.headline)
                        Text(PortfolioHistoryDisplay.signedCurrency(amount))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(PortfolioPalette.direction(amount))
                    }
                    Spacer(minLength: 8)
                    NavigationLink {
                        PortfolioDetailsView(
                            summary: summary,
                            refresh: refresh,
                            historyResult: result
                        )
                    } label: {
                        Text("Details")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityHint("Shows the full portfolio value change and its accounting")
                }
                Text("Price changes only · cards added or removed are excluded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func integrityWarning(_ defects: [LedgerIntegrityDefect]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                defects.isEmpty
                    ? "History is paused while portfolio data reconciles."
                    : "History is paused until the collection records reconcile.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PortfolioPalette.attention)

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

    @ViewBuilder
    private func biggestMovers() -> some View {
        let active = activeHistoryResult
        let contributions = active?.contributions ?? [:]
        let hasEligibleMovement = active?.hasEligibleMarketMovement ?? false
        let total = active?.accounting?.market ?? .zero
        if active == nil {
            // Recomputing for a newly chosen period. Say nothing rather than
            // claim the market was flat.
            EmptyView()
        } else if !hasEligibleMovement {
            Label("No market movement in \(historyRange.rawValue)", systemImage: "minus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Market movement by holding · \(historyRange.rawValue)")
                        .font(.headline)
                    Spacer()
                    Button("See all") {
                        if let active {
                            contributorContext = historicalContext(from: active)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }

                PortfolioContributorPreview(
                    contributions: contributions,
                    total: total,
                    holdings: portfolio.holdings,
                    history: history,
                    onRemoved: presentUndo(for:)
                )
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var largestHoldings: some View {
        let ranked = portfolio.holdings
            .filter { $0.currentValue != nil }
            .sorted { lhs, rhs in
                if lhs.currentValue != rhs.currentValue { return (lhs.currentValue ?? .zero) > (rhs.currentValue ?? .zero) }
                return lhs.collectionKey < rhs.collectionKey
            }

        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Largest holdings")
                        .font(.headline)
                    Spacer()
                    if ranked.count > 5 {
                        Button("See all") {
                            onOpenCollectionSortedByPrice()
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHint("Opens Collection sorted by price, highest first")
                    }
                }
                ForEach(Array(ranked.prefix(5))) { holding in
                    NavigationLink {
                        PortfolioOwnedCardDestination(
                            collectionKey: holding.collectionKey,
                            history: history,
                            onRemoved: presentUndo(for:)
                        )
                    } label: {
                        PortfolioHoldingRow(holding: holding)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        let today = PortfolioCalendar.day(containing: .now, in: PortfolioCalendar.timeZone())
        return PortfolioContributorContext(
            id: "today-\(today.timeIntervalSinceReferenceDate)",
            title: "Today’s market movement",
            total: attribution.market,
            contributions: portfolio.contributionIndex.byDay[today, default: [:]],
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

private struct PortfolioContributorContext: Identifiable, Hashable {
    let id: String
    let title: String
    let total: Money
    let contributions: [String: Money]
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
            let quantity = holding.quantity > 1 ? "×\(holding.quantity)" : nil
            return [holding.detail, quantity].compactMap { $0 }.joined(separator: " · ")
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
        holdings: [PortfolioHoldingSnapshot]
    ) -> [PortfolioContributionRowModel] {
        let byKey = Dictionary(holdings.map { ($0.collectionKey, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [PortfolioContributionRowModel] = []
        var unknown = Money.zero
        for (key, amount) in contributions where !amount.isZero {
            if let holding = byKey[key] {
                result.append(PortfolioContributionRowModel(kind: .holding(holding), amount: amount))
            } else {
                unknown += amount
            }
        }
        if !unknown.isZero {
            result.append(PortfolioContributionRowModel(kind: .previouslyOwned, amount: unknown))
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
    }

    static func signed(_ amount: Money) -> String {
        let sign = amount.tenThousandths < 0 ? "−" : "+"
        return sign + amount.magnitude.formatted()
    }

    static func color(_ amount: Money) -> Color { PortfolioPalette.direction(amount) }

    static func magnitudeFraction(_ amount: Money, maximum: Money) -> CGFloat {
        guard maximum.tenThousandths > 0 else { return 0 }
        return min(1, CGFloat(amount.magnitude.doubleValue / maximum.doubleValue))
    }

    static func shareOfCurrentHolding(_ row: PortfolioContributionRowModel) -> Double? {
        guard let value = row.holding?.currentValue, !value.isZero else { return nil }
        return row.amount.magnitude.doubleValue / value.doubleValue
    }
}

private struct PortfolioContributorPreview: View {
    let contributions: [String: Money]
    let total: Money
    let holdings: [PortfolioHoldingSnapshot]
    let history: PortfolioHistoryStore
    let onRemoved: (RemovedCardSnapshot) -> Void

    var body: some View {
        let all = PortfolioContributionPresentation.sorted(
            PortfolioContributionPresentation.rows(contributions: contributions, holdings: holdings),
            order: .impact
        )
        let displayed = Array(all.prefix(3))
        let residual = total - displayed.map(\.amount).sum()
        let maximum = all.map(\.amount.magnitude).max() ?? .zero
        VStack(spacing: 8) {
            ForEach(displayed) { row in
                previewRow(row, maximum: maximum)
            }
            if all.count > displayed.count, !residual.isZero {
                previewRow(
                    PortfolioContributionRowModel(kind: .otherHoldings, amount: residual),
                    maximum: maximum
                )
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ row: PortfolioContributionRowModel, maximum: Money) -> some View {
        if let key = row.collectionKey {
            NavigationLink {
                PortfolioOwnedCardDestination(collectionKey: key, history: history, onRemoved: onRemoved)
            } label: {
                PortfolioContributionRow(
                    row: row,
                    magnitudeFraction: PortfolioContributionPresentation.magnitudeFraction(row.amount, maximum: maximum),
                    showsHoldingShare: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this holding")
        } else {
            PortfolioContributionRow(
                row: row,
                magnitudeFraction: PortfolioContributionPresentation.magnitudeFraction(row.amount, maximum: maximum),
                showsHoldingShare: false
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
            PortfolioContributionPresentation.rows(contributions: context.contributions, holdings: holdings),
            order: order
        )
        let maximum = rows.map(\.amount.magnitude).max() ?? .zero
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(PortfolioContributionPresentation.signed(context.total))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(PortfolioContributionPresentation.color(context.total))
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
                                PortfolioOwnedCardDestination(collectionKey: key, history: history, onRemoved: onRemoved)
                            } label: {
                                PortfolioContributionRow(
                                    row: row,
                                    magnitudeFraction: PortfolioContributionPresentation.magnitudeFraction(row.amount, maximum: maximum),
                                    showsHoldingShare: false
                                )
                            }
                        } else {
                            PortfolioContributionRow(
                                row: row,
                                magnitudeFraction: PortfolioContributionPresentation.magnitudeFraction(row.amount, maximum: maximum),
                                showsHoldingShare: false
                            )
                        }
                    }
                }
            }

            Section {
                Label(
                    "Movers reflect market price changes while you owned these holdings. Added, removed, corrected, newly priced, and re-sourced values are excluded.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if let coverage = context.coverageDescription {
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
    let row: PortfolioContributionRowModel
    let magnitudeFraction: CGFloat
    let showsHoldingShare: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                if let holding = row.holding {
                    PortfolioArtwork(url: holding.artworkURL)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .foregroundStyle(.primary)
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PortfolioContributionPresentation.signed(row.amount))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PortfolioContributionPresentation.color(row.amount))
                    if showsHoldingShare,
                       let share = PortfolioContributionPresentation.shareOfCurrentHolding(row) {
                        Text("\(share.formatted(.percent.precision(.fractionLength(1)))) of current value")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            PortfolioMagnitudeBar(
                fraction: magnitudeFraction,
                color: PortfolioContributionPresentation.color(row.amount)
            )
            .padding(.leading, 44)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct PortfolioHoldingRow: View {
    let holding: PortfolioHoldingSnapshot

    var body: some View {
        HStack(spacing: 10) {
            PortfolioArtwork(url: holding.artworkURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name).foregroundStyle(.primary)
                Text([holding.detail, holding.quantity > 1 ? "×\(holding.quantity)" : nil]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(holding.currentValue.map { $0.formatted() } ?? "Value unavailable")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(holdingAccessibilityLabel)
    }

    private var holdingAccessibilityLabel: String {
        let quantity = holding.quantity > 1 ? ", quantity \(holding.quantity)" : ""
        let value = holding.currentValue.map { $0.formatted() } ?? "Value unavailable"
        return "\(holding.name), \(holding.detail)\(quantity), \(value)"
    }

}

private struct PortfolioMagnitudeBar: View {
    let fraction: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.65))
                        .frame(width: geometry.size.width * fraction)
                }
        }
        .frame(height: 4)
    }
}

private struct PortfolioArtwork: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.quaternary)
                            .overlay(Image(systemName: "rectangle.stack").foregroundStyle(.secondary))
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "rectangle.stack").foregroundStyle(.secondary))
            }
        }
        .frame(width: 34, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct PortfolioOwnedCardDestination: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectedCard.dateAdded, order: .forward) private var cards: [CollectedCard]
    @Query private var priceRecords: [PriceRecord]
    let collectionKey: String
    @ObservedObject var history: PortfolioHistoryStore
    let onRemoved: (RemovedCardSnapshot) -> Void

    var body: some View {
        let projection = LogicalCollection.project(
            cards: cards,
            ledger: InventoryLedger(context: modelContext)
        )
        if let position = projection.byKey[collectionKey] {
            let card = position.representative
            let record = PriceStore.record(
                for: card,
                in: Dictionary(priceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            )
            CollectionCardDetailView(
                card: card,
                price: record?.display ?? .unknown,
                history: history,
                unpricedReason: record?.effectiveUnitMarketPriceUSD == nil
                    ? PricingDiagnostics.unpricedReason(for: card, record: record)
                    : nil,
                artworkReason: ArtworkDiagnostics.reason(for: card),
                logicalQuantity: position.quantity,
                isLogicalConflict: position.physicalRowCount > 1,
                onRemoved: onRemoved
            )
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
                LabeledContent("Market movement", value: signed(accounting.market))
                if !accounting.netInventoryActivity.isZero {
                    LabeledContent("Cards added or removed", value: signed(accounting.netInventoryActivity))
                }
                if !accounting.newlyAddedValue.isZero {
                    LabeledContent("Newly priced additions", value: signed(accounting.newlyAddedValue))
                }
                if !accounting.corrections.isZero {
                    LabeledContent("Corrections", value: signed(accounting.corrections))
                }
                if !accounting.pricingAdjustments.isZero {
                    LabeledContent("Pricing adjustments", value: signed(accounting.pricingAdjustments))
                }
                if !accounting.unexplained.isZero {
                    LabeledContent("Unexplained", value: signed(accounting.unexplained))
                        .foregroundStyle(PortfolioPalette.attention)
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
                .foregroundStyle(PortfolioPalette.attention)
        } else if coverage.completeDays > 0 {
            LabeledContent("Completed-day coverage", value: "\(coverage.completeDays) complete")
        }
        if let live = coverage.live, live.carriedForward > 0 {
            Text("Today: \(live.refreshed) checked · \(live.carriedForward) carried forward")
                .foregroundStyle(PortfolioPalette.attention)
        }
    }

    private func signed(_ amount: Money) -> String {
        let prefix = amount.tenThousandths > 0 ? "+" : amount.tenThousandths < 0 ? "−" : ""
        return prefix + amount.magnitude.formatted()
    }

    @ViewBuilder
    private var refreshStatus: some View {
        switch refresh.status {
        case let .refreshing(completed, total):
            LabeledContent("Checking prices", value: "\(completed) of \(total)")
        case let .finished(result):
            Text(result.providerUnreachable
                 ? "The card catalog is unreachable. Check your connection and try again."
                 : "Prices checked \(result.checkedAt.formatted(date: .omitted, time: .shortened)).")
                .font(.subheadline)
                .foregroundStyle(result.providerUnreachable || result.failed > 0 ? PortfolioPalette.attention : .secondary)
        case .recentlyChecked:
            Text("Prices were checked recently.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }
}
