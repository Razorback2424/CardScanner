import SwiftUI
import SwiftData

/// The collection's home screen. It presents the value and accounting already
/// produced by `PortfolioEngine`; it never recomputes or replays history itself.
struct PortfolioView: View {
    @ObservedObject var portfolio: PortfolioEngine
    @ObservedObject var refresh: PriceRefreshController
    let onRefresh: @MainActor () async -> Void
    @State private var isShowingSettings = false
    @State private var contributorContext: PortfolioContributorContext?

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
                    portfolioHero

                    if let summary = portfolio.summary {
                        if !summary.isAuthoritative {
                            integrityWarning(summary)
                        } else if !summary.isMigrationDay,
                                  let attribution = summary.attribution {
                            todayBreakdown(attribution, closeDate: summary.closeDate)
                        }

                        if summary.isAuthoritative {
                            PortfolioHistoryView(
                                summary: summary,
                                factors: portfolio.performanceFactors,
                                contributions: portfolio.contributionIndex,
                                refreshRevision: portfolio.inputRevision,
                                onShowContributors: { result in
                                    contributorContext = historicalContext(from: result)
                                }
                            )

                            biggestMovers(summary)
                                .id("phase3-movers")
                            largestHoldings
                        }

                        coverage(summary.coverage)

                    } else {
                        ProgressView("Calculating portfolio…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    }
                    }
                    .padding(16)
                }
                .task {
                    guard startsAtPhase3DebugSection else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    proxy.scrollTo("phase3-movers", anchor: .top)
                }
            }
            .navigationTitle("Portfolio")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let summary = portfolio.summary {
                        NavigationLink {
                            PortfolioDetailsView(summary: summary, refresh: refresh)
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel("Pricing and data details")
                    }

                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(item: $contributorContext) { context in
                PortfolioContributorsView(context: context, holdings: portfolio.holdings)
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
    }

    private var isRefreshing: Bool {
        if case .refreshing = refresh.status { return true }
        return false
    }

    private var portfolioHero: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Current value")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text((portfolio.summary?.currentValue ?? .zero).formatted())
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.34))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel("Collection value, \((portfolio.summary?.currentValue ?? .zero).formatted())")

                Button("Refresh Prices", systemImage: "arrow.clockwise") {
                    Task { await onRefresh() }
                }
                .labelStyle(.iconOnly)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.34))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh prices")
            }

            if let attribution = portfolio.summary?.attribution,
               portfolio.summary?.isAuthoritative == true,
               portfolio.summary?.isMigrationDay == false {
                Text("\(signedCurrency(attribution.totalChange)) today")
                    .font(.headline)
                    .foregroundStyle(changeColor(attribution.totalChange))
                    .monospacedDigit()
            } else if portfolio.summary?.isMigrationDay == true {
                Text("Tracking started today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func integrityWarning(_ summary: PortfolioSummary) -> some View {
        Label(
            summary.defects.isEmpty
                ? "Performance is paused while portfolio data reconciles."
                : "Performance is paused until the collection records reconcile.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func todayBreakdown(
        _ attribution: PortfolioClose.Attribution,
        closeDate: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)

            Button {
                contributorContext = todayContext(attribution)
            } label: {
                changeRow("Market movement", attribution.market)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows today's market contributors")
            if !attribution.added.isZero { changeRow("Added", attribution.added) }
            if !attribution.removed.isZero { changeRow("Removed", -attribution.removed) }
            if !attribution.corrections.isZero { changeRow("Corrections", attribution.corrections) }
            if !attribution.pricingAdjustment.isZero {
                changeRow("Pricing adjustment", attribution.pricingAdjustment)
            }

            Divider()
            changeRow("Total change", attribution.totalChange, emphasized: true)

            if let closeDate {
                LabeledContent(
                    closeDate.formatted(date: .abbreviated, time: .omitted) + " close",
                    value: attribution.closeValue.formatted()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func biggestMovers(_ summary: PortfolioSummary) -> some View {
        let today = PortfolioCalendar.day(containing: .now, in: PortfolioCalendar.timeZone())
        let contributions = portfolio.contributionIndex.byDay[today, default: [:]]
        let hasEligibleMovement = portfolio.contributionIndex.daysWithEligibleMarketMovement.contains(today)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Biggest movers today")
                    .font(.headline)
                Spacer()
                if hasEligibleMovement {
                    Button("See all") {
                        if let attribution = summary.attribution {
                            contributorContext = todayContext(attribution)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if summary.coverage.total > 0, summary.coverage.refreshed == 0 {
                Text("Prices haven’t been checked today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !hasEligibleMovement {
                Text("No market movement today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                PortfolioContributorPreview(
                    contributions: contributions,
                    total: summary.attribution?.market ?? .zero,
                    holdings: portfolio.holdings
                )
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        NavigationLink("See all") {
                            PortfolioHoldingsView(holdings: ranked)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                ForEach(Array(ranked.prefix(5))) { holding in
                    NavigationLink {
                        PortfolioOwnedCardDestination(collectionKey: holding.collectionKey)
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

    private func changeRow(_ title: String, _ amount: Money, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(signedCurrency(amount))
                .monospacedDigit()
        }
        .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(emphasized ? .primary : .secondary)
    }

    private func signedCurrency(_ amount: Money) -> String {
        let sign = amount.tenThousandths < 0 ? "−" : "+"
        return sign + amount.magnitude.formatted()
    }

    private func changeColor(_ amount: Money) -> Color {
        if amount.isZero { return .secondary }
        return amount.tenThousandths < 0 ? .red : Color(red: 0.18, green: 0.55, blue: 0.34)
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
        case .previouslyOwned: return "Previously owned holdings"
        case .otherHoldings: return "Other holdings"
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

    static func color(_ amount: Money) -> Color {
        if amount.isZero { return .secondary }
        return amount.tenThousandths < 0 ? .red : Color(red: 0.18, green: 0.55, blue: 0.34)
    }
}

private struct PortfolioContributorPreview: View {
    let contributions: [String: Money]
    let total: Money
    let holdings: [PortfolioHoldingSnapshot]

    var body: some View {
        let all = PortfolioContributionPresentation.sorted(
            PortfolioContributionPresentation.rows(contributions: contributions, holdings: holdings),
            order: .impact
        )
        let displayed = Array(all.prefix(3))
        let residual = total - displayed.map(\.amount).sum()
        VStack(spacing: 8) {
            ForEach(displayed) { row in
                PortfolioContributionRow(row: row)
            }
            if all.count > displayed.count, !residual.isZero {
                PortfolioContributionRow(
                    row: PortfolioContributionRowModel(kind: .otherHoldings, amount: residual)
                )
            }
        }
    }
}

private struct PortfolioContributorsView: View {
    let context: PortfolioContributorContext
    let holdings: [PortfolioHoldingSnapshot]
    @State private var order: PortfolioContributionOrder = .impact

    var body: some View {
        let rows = PortfolioContributionPresentation.sorted(
            PortfolioContributionPresentation.rows(contributions: context.contributions, holdings: holdings),
            order: order
        )
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
                                PortfolioOwnedCardDestination(collectionKey: key)
                            } label: {
                                PortfolioContributionRow(row: row)
                            }
                        } else {
                            PortfolioContributionRow(row: row)
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

    var body: some View {
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
            Text(PortfolioContributionPresentation.signed(row.amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(PortfolioContributionPresentation.color(row.amount))
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct PortfolioHoldingsView: View {
    let holdings: [PortfolioHoldingSnapshot]

    var body: some View {
        List(holdings) { holding in
            NavigationLink {
                PortfolioOwnedCardDestination(collectionKey: holding.collectionKey)
            } label: {
                PortfolioHoldingRow(holding: holding)
            }
        }
        .navigationTitle("Largest holdings")
        .navigationBarTitleDisplayMode(.inline)
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
            Text((holding.currentValue ?? .zero).formatted())
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
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
    @Query(sort: \CollectedCard.dateAdded, order: .forward) private var cards: [CollectedCard]
    @Query private var priceRecords: [PriceRecord]
    let collectionKey: String

    var body: some View {
        if let card = cards.first(where: { $0.collectionKey == collectionKey }) {
            let record = PriceStore.record(
                for: card,
                in: Dictionary(priceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            )
            CollectionCardDetailView(
                card: card,
                price: record?.display ?? .unknown,
                unpricedReason: record?.unitMarketPriceUSD == nil
                    ? PricingDiagnostics.unpricedReason(for: card, record: record)
                    : nil,
                artworkReason: ArtworkDiagnostics.reason(for: card),
                onRemoved: { _ in }
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
                    Text("Performance and history resume after reconciliation.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Pricing & Data")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(result.providerUnreachable || result.failed > 0 ? .orange : .secondary)
        case .recentlyChecked:
            Text("Prices were checked recently.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }
}
