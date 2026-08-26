import SwiftData
import SwiftUI

/// The scanner reduces friction according to certainty. The collection reduces
/// it according to intent: search plus one filter control answer the common
/// questions without turning the collection header into a toolbar of chips.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]

    @Query private var priceRecords: [PriceRecord]
    @Query private var productIdentities: [ProductIdentity]

    @ObservedObject var refresh: PriceRefreshController
    @ObservedObject var portfolio: PortfolioEngine
    let opensBrowseOnLaunch: Bool
    let onOpenScanner: @MainActor () -> Void
    let onRefresh: @MainActor () async -> Void

    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false

    @State private var searchText = ""
    /// What the grid is actually filtered by. Trails `searchText` by one short
    /// debounce so a large grid is not rebuilt on every keystroke.
    @State private var searchQuery = ""
    @State private var filters = CollectionFilters.none
    @State private var sort: CollectionSort = .priceHighToLow
    @State private var activeSheet: ActiveSheet?
    @State private var isShowingSettings = false
    @State private var isShowingPortfolioDetails = false
    @State private var isShowingSearch = false
    @State private var hasCheckedForStalePrices = false
    @State private var pendingRemoval: RemovedCardSnapshot?
    @State private var removalUndoTask: Task<Void, Never>?
    @State private var showsManualRefreshStatus = false
    @State private var refreshStatusTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @State private var navigationPath: [Destination] = []

    private enum ActiveSheet: String, Identifiable {
        case filters
        var id: String { rawValue }
    }

    private enum Destination: Hashable {
        case browse
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    var body: some View {
        // Built once per render and threaded through. Filtering and sorting are
        // pure local work, but recomputing them separately for the header, the
        // grid and the refresh targets would do it four times for nothing.
        let snapshot = makeSnapshot()

        return NavigationStack(path: $navigationPath) {
            Group {
                if cards.isEmpty {
                    emptyCollection
                } else {
                    content(snapshot)
                }
            }
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") {
                        isShowingSearch = true
                        isSearchFocused = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Search collection")

                    Button("Filters", systemImage: filters.isActive
                           ? "line.3.horizontal.decrease.circle.fill"
                           : "line.3.horizontal.decrease.circle") {
                        activeSheet = .filters
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(filters.isActive ? "Filters, \(activeFilterCount) active" : "Filters")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFocused = false
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .browse:
                    BrowseView()
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .filters:
                CollectionFilterSheet(
                    filters: $filters,
                    sort: $sort,
                    setOptions: setOptions(snapshot),
                    finishOptions: finishOptions(snapshot),
                    gradingCompanyOptions: gradingCompanyOptions(snapshot),
                    gradeOptions: gradeOptions(snapshot)
                )
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .task { await catalogNormalizer.normalizeImportedCards(in: modelContext) }
        .task(id: fallbackAvailabilityTaskID(snapshot)) {
            await refresh.updateFallbackAvailability(pending: fallbackPendingCount(snapshot))
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            searchQuery = searchText
        }
        .onDisappear {
            refreshStatusTask?.cancel()
        }
        .task {
            guard opensBrowseOnLaunch, navigationPath.isEmpty else { return }
            navigationPath.append(.browse)
        }
        .safeAreaInset(edge: .bottom) {
            if let pendingRemoval {
                removalUndoBanner(pendingRemoval)
            }
        }
    }

    private func content(_ snapshot: Snapshot) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                browseCatalogEntry
                if isShowingSearch {
                    searchField
                }
                filterBar(snapshot)

                if snapshot.entries.isEmpty {
                    noMatches
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(snapshot.entries) { entry in
                            NavigationLink {
                                CollectionCardDetailView(
                                    card: entry.card,
                                    price: entry.row.price,
                                    unpricedReason: entry.unpricedReason,
                                    artworkReason: entry.artworkReason,
                                    onRemoved: presentUndo(for:)
                                )
                            } label: {
                                CollectionCardTile(
                                    card: entry.card,
                                    price: entry.row.price,
                                    unpricedReason: entry.unpricedReason,
                                    artworkReason: entry.artworkReason
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await onRefresh() }
        .animation(.easeOut(duration: 0.2), value: filters)
        .animation(.easeOut(duration: 0.2), value: sort)
        .animation(.easeOut(duration: 0.2), value: searchQuery)
    }

    private var emptyCollection: some View {
        ContentUnavailableView {
            Label("No cards yet", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Scan your first card or find one to add.")
        } actions: {
            VStack(spacing: 12) {
                Button("Scan a Card", systemImage: "viewfinder") {
                    onOpenScanner()
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(value: Destination.browse) {
                    Label("Find Items to Add", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var browseCatalogEntry: some View {
        NavigationLink(value: Destination.browse) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find Items to Add")
                        .font(.headline)
                    Text("Cards, sets, and sealed products")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Find items to add")
        .accessibilityHint("Browse cards, sets, and sealed products to add to your collection")
    }

    // MARK: - Removal undo

    private func presentUndo(for removed: RemovedCardSnapshot) {
        removalUndoTask?.cancel()
        pendingRemoval = removed

        removalUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, pendingRemoval?.id == removed.id else { return }
            pendingRemoval = nil
        }
    }

    private func undoRemoval(_ removed: RemovedCardSnapshot) {
        removalUndoTask?.cancel()
        if (try? CollectionStore(context: modelContext).restore(removed)) != nil {
            pendingRemoval = nil
        }
    }

    private func removalUndoBanner(_ removed: RemovedCardSnapshot) -> some View {
        HStack(spacing: 12) {
            Text("Removed \(removed.name)")
                .font(.subheadline)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Undo") {
                undoRemoval(removed)
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityLabel("Undo removal of \(removed.name)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private func header(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // A row rather than an overlay: two 44pt controls stacked on the
            // trailing edge collide with the number itself once the value gets
            // long. Balanced on either side, the hero centres between them and
            // scales down instead of colliding.
            HStack(spacing: 0) {
                detailsButton

                // Whole-collection, and deliberately no longer following the
                // filter chips. A close that changed when you tapped "Holo"
                // would be meaningless — the filtered figure moves to its own
                // line below, where it is clearly a subtotal.
                Text(heroValue, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(portfolioGreen)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Collection value")

                Button("Refresh Prices", systemImage: "arrow.clockwise") {
                    Task { await refreshAllPrices() }
                }
                .labelStyle(.iconOnly)
                .font(.headline.weight(.semibold))
                .foregroundStyle(portfolioGreen)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh prices")
            }

            // Only what the screen is *for*: what the collection is worth and
            // what moved it. Coverage, provenance, exclusions and diagnostics
            // are real and stay reachable, but they belong behind the details
            // button rather than stacked seven deep under the number.
            todayCard

            if isNarrowed {
                Text(
                    "Filtered: \(snapshot.pricedValue, format: .currency(code: "USD").precision(.fractionLength(2))) of \(heroValue, format: .currency(code: "USD").precision(.fractionLength(2)))"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

                Text("\(snapshot.visibleQuantity) of \(snapshot.totalQuantity)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opens the details sheet, badged only when something is actually wrong.
    ///
    /// Deliberately *not* badged for ordinary facts like carried-forward prices
    /// or unpriced copies: most collections have some of those most of the
    /// time, and a badge that is always lit is a badge nobody reads.
    private var detailsButton: some View {
        Button {
            isShowingPortfolioDetails = true
        } label: {
            Image(systemName: "info.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(needsAttention ? Color.orange : portfolioGreen)
                .overlay(alignment: .topTrailing) {
                    if needsAttention {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(needsAttention ? "Collection details, needs attention" : "Collection details")
        .accessibilityHint("Price coverage, excluded copies and diagnostics.")
    }

    /// Something the person would want to act on, as opposed to something they
    /// might want to look up.
    private var needsAttention: Bool {
        if portfolio.summary?.isAuthoritative == false { return true }
        if case let .finished(result) = refresh.status {
            return result.providerUnreachable || result.failed > 0
        }
        return false
    }

    private var portfolioGreen: Color { Color(red: 0.18, green: 0.55, blue: 0.34) }

    /// The whole collection's current value. Falls back to the filtered
    /// snapshot only before the engine's first pass has landed.
    private var heroValue: Double {
        portfolio.summary?.currentValue.doubleValue ?? makeSnapshot().pricedValue
    }

    /// Yesterday's close, what has happened since, and whether any of it is
    /// unaccounted for.
    @ViewBuilder
    private var todayCard: some View {
        if let summary = portfolio.summary {
            VStack(alignment: .leading, spacing: 6) {
                if !summary.isAuthoritative {
                    // Still stated on the screen itself, because it changes
                    // what the numbers below mean. The explanation of *why*
                    // lives in Details, where there is room for it.
                    Label("Performance paused · needs reconciliation", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if summary.isMigrationDay {
                    // Contract 8. There is genuinely no yesterday, so nothing
                    // is invented — no reconciliation block, no fabricated
                    // close, and no explanatory caption either. The history
                    // card already says history is being recorded, and Details
                    // says when the first close forms.
                    EmptyView()
                } else if let attribution = summary.attribution {
                    reconciliation(attribution, closeDate: summary.closeDate)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func reconciliation(
        _ attribution: PortfolioClose.Attribution,
        closeDate: Date?
    ) -> some View {
        VStack(spacing: 3) {
            changeRow("Market movement", attribution.market)
            if !attribution.added.isZero {
                changeRow("Added to collection", attribution.added)
            }
            if !attribution.removed.isZero {
                changeRow("Removed", -attribution.removed)
            }
            if !attribution.corrections.isZero {
                changeRow("Corrections", attribution.corrections)
            }
            // Its own line, always. Folding a pricing arrival into "Corrections"
            // would be exactly the sort of thing this feature exists to stop.
            if !attribution.pricingAdjustment.isZero {
                changeRow("Pricing adjustment", attribution.pricingAdjustment)
            }

            Divider()

            changeRow("Total change", attribution.totalChange, emphasised: true)

            HStack {
                Text(closeDate.map { "\($0.formatted(date: .abbreviated, time: .omitted)) close" } ?? "Yesterday close")
                Spacer()
                Text(attribution.closeValue.doubleValue, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("Current")
                Spacer()
                Text(attribution.currentValue.doubleValue, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !attribution.unexplained.isZero {
                // Only ever shown because it is not zero, and never absorbed
                // into another line. A residual the app hides is a residual
                // nobody ever fixes.
                changeRow("Unexplained", attribution.unexplained, isDefect: true)
            }
        }
    }

    /// One sentence naming the cause, not one line per derived symptom. A
    /// conflicting ledger group necessarily also breaks the ledger/collection
    /// assertion, and saying both would describe a single failure twice.
    private func reconciliationCause(_ defects: [LedgerIntegrityDefect]) -> String {
        let reasons = Set(defects.map(\.reason))
        let cause: String
        if reasons.contains(.conflictingPayloadForIdempotencyKey) {
            cause = "Conflicting synced ownership records were found."
        } else if reasons.contains(.duplicatePositionPricingConflict) {
            cause = "Stored rows for the same card disagree about how it is priced."
        } else {
            cause = "The ownership ledger no longer matches the collection."
        }
        return cause + " Current collection value is still available; performance and history are paused."
    }

    private func changeRow(
        _ label: String,
        _ amount: Money,
        emphasised: Bool = false,
        isDefect: Bool = false
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(signedCurrency(amount))
                .monospacedDigit()
        }
        .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(isDefect ? Color.orange : (emphasised ? .primary : .secondary))
    }

    private func signedCurrency(_ amount: Money) -> String {
        let magnitude = amount.magnitude.doubleValue
            .formatted(.currency(code: "USD").precision(.fractionLength(2)))
        if amount.isZero { return magnitude }
        return (amount < .zero ? "−" : "+") + magnitude
    }

    /// Everything that used to stack under the hero.
    ///
    /// None of it was noise — coverage, exclusions and diagnostics are exactly
    /// what makes the number defensible — but seven stacked caption lines is
    /// how a collection screen turns into a status console. One tap away, with
    /// room to say things properly.
    @ViewBuilder
    private func portfolioDetailsSheet(_ snapshot: Snapshot) -> some View {
        NavigationStack {
            List {
                if let summary = portfolio.summary, !summary.defects.isEmpty {
                    Section {
                        Text(reconciliationCause(summary.defects))
                            .font(.subheadline)
                        ForEach(summary.defects) { defect in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(defect.reason.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(defect.reason.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(defect.collectionKey)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Needs attention")
                    }
                }

                Section("Prices") {
                    if let coverage = portfolio.summary?.coverage {
                        coverageDetailRow(coverage)
                    }
                    if let asOf = snapshot.pricesAsOf {
                        LabeledContent(
                            snapshot.isSourceStamped ? "Market data through" : "Last checked",
                            value: asOf.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if snapshot.unpricedCount > 0 {
                        LabeledContent(
                            "Unpriced",
                            value: "\(snapshot.unpricedCount) cop\(snapshot.unpricedCount == 1 ? "y" : "ies")"
                        )
                    }
                    if snapshot.otherCurrencyCount > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(
                                "Priced in another currency",
                                value: "\(snapshot.otherCurrencyCount) cop\(snapshot.otherCurrencyCount == 1 ? "y" : "ies")"
                            )
                            Text("Not included in the total — there is no live exchange rate to convert at.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if case .finished = refresh.status {
                        freshnessLabel
                    } else if case .refreshing = refresh.status {
                        freshnessLabel
                    }
                    fallbackStatusLabel(snapshot)
                }

                Section("Portfolio") {
                    if portfolio.summary?.isMigrationDay == true {
                        Text("Portfolio tracking started today. The first daily close forms at midnight.")
                            .font(.subheadline)
                    } else if let started = PortfolioEpoch.startedAt() {
                        LabeledContent(
                            "Tracking since",
                            value: started.formatted(date: .abbreviated, time: .omitted)
                        )
                    }
                    LabeledContent(
                        "Day boundary",
                        value: (PortfolioCalendar.pinnedTimeZone() ?? .current)
                            .identifier.replacingOccurrences(of: "_", with: " ")
                    )
                    if let note = portfolio.summary?.revisionNote,
                       let closeDate = portfolio.summary?.closeDate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(closeDate.formatted(date: .abbreviated, time: .omitted)) close revised")
                                .font(.subheadline)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Catalog") {
                    catalogNormalizationLabel
                    LabeledContent("Items", value: "\(snapshot.totalQuantity)")
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingPortfolioDetails = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Coverage, said in full rather than compressed into a caption.
    @ViewBuilder
    private func coverageDetailRow(_ coverage: PortfolioCoverage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch coverage.state {
            case .unknown:
                Text("Coverage unknown for this day")
            case .complete:
                LabeledContent("Checked today", value: "\(coverage.refreshed) of \(coverage.total)")
            case .partial:
                LabeledContent("Checked today", value: "\(coverage.refreshed) of \(coverage.total)")
                Text("\(coverage.carriedForward) still showing an earlier price. Refreshing updates them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var catalogNormalizationLabel: some View {
        switch catalogNormalizer.status {
        case let .normalizing(total):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding artwork for \(total) cards…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case let .finished(matched, unmatched):
            Text(
                unmatched > 0
                    ? "Found artwork for \(matched) cards · \(unmatched) unmatched"
                    : "Card artwork updated"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .failed:
            Text("Artwork lookup will retry later")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fallbackStatusLabel(_ snapshot: Snapshot) -> some View {
        let pending = fallbackPendingCount(snapshot)
        if pending > 0 {
            Button {
                isShowingSettings = true
            } label: {
                Label(fallbackStatusText(pending: pending), systemImage: fallbackStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(fallbackStatusColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens app settings")
        }
    }

    private func fallbackStatusText(pending: Int) -> String {
        guard PriceVendorCredentials.hasKey else {
            return "Price fallback needs an API key · \(pending) card types waiting"
        }
        guard usesPriceFallback else {
            return "Price fallback is off · \(pending) card types waiting"
        }

        switch refresh.fallbackStatus {
        case let .available(remainingToday):
            return "\(pending) card types waiting · \(remainingToday) requests left today"
        case let .running(completed, total, remainingToday):
            return "Price fallback \(completed)/\(total) · \(remainingToday) requests left today"
        case let .finished(_, _, remainingToday):
            return "\(pending) card types still waiting · \(remainingToday) requests left today"
        case let .budgetReached(_, resetAt):
            return "Daily fallback budget reached · resumes after \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        case let .rateLimited(_, retryAt):
            return "Price fallback paused by provider · retry after \(retryAt.formatted(date: .abbreviated, time: .shortened))"
        case .idle, .disabled, .unconfigured:
            return "\(pending) card types waiting for price fallback"
        }
    }

    private var fallbackStatusSymbol: String {
        switch refresh.fallbackStatus {
        case .budgetReached: return "calendar.badge.clock"
        case .rateLimited: return "pause.circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .idle, .disabled, .unconfigured, .available, .finished:
            return usesPriceFallback && PriceVendorCredentials.hasKey
                ? "dollarsign.circle"
                : "exclamationmark.circle"
        }
    }

    private var fallbackStatusColor: Color {
        switch refresh.fallbackStatus {
        case .budgetReached, .rateLimited: return .orange
        case .idle, .disabled, .unconfigured, .available, .running, .finished: return .secondary
        }
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        switch refresh.status {
        case let .refreshing(completed, total):
            Text("Checking prices… \(completed)/\(total) card types")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

        case let .finished(result):
            VStack(alignment: .leading, spacing: 1) {
                Label(
                    refreshOutcomeText(result),
                    systemImage: result.providerUnreachable
                        ? "wifi.exclamationmark"
                        : (result.failed > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                )
                .font(.caption)
                .foregroundStyle(
                    result.providerUnreachable || result.failed > 0
                        ? Color.orange
                        : Color.secondary
                )

                if !result.checkedUnstampedProvider, let asOf = result.latestSourceUpdate {
                    Text("Market data current through \(asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .recentlyChecked:
            Label("Prices were checked recently", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .idle:
            EmptyView()
        }
    }

    /// What a finished refresh actually says.
    ///
    /// An outage and a set of unpriceable cards are different problems with
    /// different remedies, so they get different sentences. "400 card types
    /// couldn't be reached" reads as four hundred broken cards; the truth was
    /// that one server was down.
    private func refreshOutcomeText(_ result: PriceRefreshController.Summary) -> String {
        if result.providerUnreachable {
            return "Card catalogue unreachable · check your connection and try again"
        }
        if result.failed > 0 {
            return "Checked just now · \(result.failed) card types couldn't be reached"
        }
        return refreshSuccessText(result)
    }

    private func refreshSuccessText(_ result: PriceRefreshController.Summary) -> String {
        if result.changedPrices { return "Prices updated" }
        if result.checkedUnstampedProvider { return "Prices checked" }
        return result.foundNothingNewer
            ? "Checked just now · no newer market prices"
            : "Prices updated"
    }

    // MARK: - Search

    /// The fifth filter, and the simplest one. It composes with the chips rather
    /// than replacing them: typing a name narrows whatever view is already set up.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search cards", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($isSearchFocused)
                .onSubmit {
                    isSearchFocused = false
                }

            if !searchText.isEmpty {
                Button {
                    // Clears only the name search. The chips are a separate
                    // question and stay exactly as they were.
                    searchText = ""
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var isNarrowed: Bool {
        filters.isActive || !searchQuery.isEmpty
    }

    @ViewBuilder
    private var noMatches: some View {
        if !searchQuery.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
                .padding(.top, 24)
        } else {
            ContentUnavailableView(
                "Nothing matches these filters",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try clearing one of them.")
            )
            .padding(.top, 24)
        }
    }

    // MARK: - Filters

    private func filterBar(_ snapshot: Snapshot) -> some View {
        HStack {
            Spacer()

            Menu {
                ForEach(CollectionSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Text(sort.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .accessibilityLabel("Sort collection: \(sort.label)")
        }
    }

    private var activeFilterCount: Int {
        (filters.game == nil ? 0 : 1)
            + (filters.itemKinds.isEmpty ? 0 : 1)
            + (filters.setCodes.isEmpty ? 0 : 1)
            + (filters.price == nil ? 0 : 1)
            + (filters.variantIDs.isEmpty ? 0 : 1)
            + (filters.gradingCompanies.isEmpty ? 0 : 1)
            + (filters.gradeValues.isEmpty ? 0 : 1)
    }

    // MARK: - Data

    /// Everything one render of this screen needs, derived once.
    struct Snapshot {
        struct Entry: Identifiable {
            let row: CollectionRow
            let card: CollectedCard
            let unpricedReason: PricingDiagnosticReason?
            let artworkReason: ArtworkDiagnosticReason?

            var id: String { row.id }
        }

        let all: [CollectionRow]
        let visible: [CollectionRow]
        let entries: [Entry]
        let totalQuantity: Int
        let visibleQuantity: Int
        /// Only what is actually priced. A total that quietly folds in unknowns
        /// is worse than an honest gap.
        let pricedValue: Double
        /// Copies whose price is real but quoted in another currency, so they
        /// are deliberately absent from `pricedValue` rather than converted at
        /// a rate this app has no live source for. Reported instead of hidden.
        let otherCurrencyCount: Int
        let unpricedCount: Int
        let pricesAsOf: Date?
        /// Whether `pricesAsOf` is a provider's own "current through" stamp or
        /// merely when this app last looked. The two get different wording.
        let isSourceStamped: Bool
        let cardsByKey: [String: CollectedCard]
        let recordsByKey: [String: PriceRecord]
    }

    @MainActor
    private func makeSnapshot() -> Snapshot {
        let recordsByKey = Dictionary(priceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        // One collection key can legitimately have more than one row, so what
        // is owned comes from the shared projection rather than from whichever
        // row this fetch happened to return first. See `LogicalCollection`.
        let projection = LogicalCollection.project(
            cards: cards,
            ledger: InventoryLedger(context: modelContext)
        )
        let cardsByKey = projection.byKey.mapValues(\.representative)

        let all = projection.positions.map { position in
            let card = position.representative
            return CollectionRow(
                id: card.collectionKey,
                game: card.cardGame,
                name: card.name,
                setCode: card.setCode,
                setName: card.setName,
                setReleaseOrder: card.setReleaseOrder,
                cardNumber: card.cardNumber,
                variantID: card.variantID,
                variantLabel: card.variantLabel,
                quantity: position.quantity,
                dateAdded: position.dateAdded,
                price: PriceStore.record(for: card, in: recordsByKey)?.display ?? .unknown,
                itemKind: card.itemKind,
                itemKindLabel: card.itemKindLabel,
                gradingCompany: card.gradingCompany,
                gradeValue: card.gradeRaw
            )
        }

        let visible = CollectionQuery.apply(
            nameQuery: searchQuery,
            filters: filters,
            sort: sort,
            to: all
        )

        var pricedValue: Double = 0
        var unpriced = 0
        var otherCurrency = 0
        var visibleQuantity = 0
        for row in visible {
            visibleQuantity += row.quantity
            guard let price = row.unitPrice else {
                unpriced += row.quantity
                continue
            }
            // Summing euros into a dollar total would overstate the collection
            // by whatever the exchange rate happens to be. Without a live rate
            // the only honest options are to convert or to exclude, and this
            // app has no rate source — so it excludes, and says so.
            guard row.price.currencyCode == "USD" else {
                otherCurrency += row.quantity
                continue
            }
            pricedValue += price * Double(row.quantity)
        }

        // Freshness belongs to the collection currently being summarized, not to
        // unrelated hidden records. A mixed provider view cannot make a universal
        // provider-side freshness claim because Scryfall publishes no such stamp;
        // in that case report the oldest successful check instead.
        let relevantRecords = visible.compactMap { row -> PriceRecord? in
            guard let card = cardsByKey[row.id] else { return nil }
            return PriceStore.record(for: card, in: recordsByKey)
        }
        let allSourceStamped = !relevantRecords.isEmpty && relevantRecords.allSatisfy {
            $0.source?.publishesSourceTimestamp == true && $0.sourceUpdatedAt != nil
        }
        let asOf: Date?
        if allSourceStamped {
            asOf = relevantRecords.compactMap(\.sourceUpdatedAt).min()
        } else {
            asOf = relevantRecords.compactMap { $0.lastCheckedAt ?? $0.fetchedAt }.min()
        }

        return Snapshot(
            all: all,
            visible: visible,
            entries: visible.compactMap { row -> Snapshot.Entry? in
                guard let card = cardsByKey[row.id] else { return nil }
                let record = PriceStore.record(for: card, in: recordsByKey)
                return Snapshot.Entry(
                    row: row,
                    card: card,
                    unpricedReason: row.unitPrice == nil
                        ? PricingDiagnostics.unpricedReason(for: card, record: record)
                        : nil,
                    artworkReason: ArtworkDiagnostics.reason(for: card)
                )
            },
            totalQuantity: all.reduce(0) { $0 + $1.quantity },
            visibleQuantity: visibleQuantity,
            pricedValue: pricedValue,
            otherCurrencyCount: otherCurrency,
            unpricedCount: unpriced,
            pricesAsOf: asOf,
            isSourceStamped: allSourceStamped,
            cardsByKey: cardsByKey,
            recordsByKey: recordsByKey
        )
    }

    /// Options come from the collection, narrowed by the game chip so a Pokémon
    /// session never has to scroll past Magic finishes.
    private func rowsForOptions(_ snapshot: Snapshot) -> [CollectionRow] {
        let searched = CollectionQuery.filter(snapshot.all, nameQuery: searchQuery, with: .none)
        guard let game = filters.game else { return searched }
        return searched.filter { $0.game == game }
    }

    /// Accumulator for building a filter option. A named type rather than a
    /// tuple: the tuple version of this made the type checker give up.
    private struct OptionTally {
        var label: String
        var group: String
        var groupOrder: String
        var count: Int
        var sortValue: Int
    }

    private func setOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rowsForOptions(snapshot) {
            if var existing = tallies[row.setFilterID] {
                existing.count += row.quantity
                tallies[row.setFilterID] = existing
            } else {
                tallies[row.setFilterID] = OptionTally(
                    label: row.setName,
                    group: row.game.label,
                    groupOrder: row.game.rawValue,
                    count: row.quantity,
                    // Newest set first.
                    sortValue: -row.setReleaseOrder
                )
            }
        }

        return orderedOptions(from: tallies)
    }

    private func finishOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rowsForOptions(snapshot) {
            guard let variant = row.variant else { continue }
            if var existing = tallies[variant.id] {
                existing.count += row.quantity
                tallies[variant.id] = existing
            } else {
                tallies[variant.id] = OptionTally(
                    label: variant.label,
                    group: row.game.label,
                    groupOrder: row.game.rawValue,
                    count: row.quantity,
                    sortValue: variant.choicePriority
                )
            }
        }

        return orderedOptions(from: tallies)
    }

    private func gradingCompanyOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var counts: [GradingCompany: Int] = [:]
        for row in rowsForOptions(snapshot) where row.itemKind == .gradedCard {
            guard let company = row.gradingCompany else { continue }
            counts[company, default: 0] += row.quantity
        }
        return GradingCompany.allCases.compactMap { company in
            guard let count = counts[company] else { return nil }
            return FilterOption(id: company.rawValue, label: company.label, group: nil, count: count)
        }
    }

    private func gradeOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var counts: [String: Int] = [:]
        for row in rowsForOptions(snapshot) where row.itemKind == .gradedCard {
            guard let grade = row.gradeValue, !grade.isEmpty else { continue }
            counts[grade, default: 0] += row.quantity
        }
        return counts
            .map { FilterOption(id: $0.key, label: $0.key, group: nil, count: $0.value) }
            .sorted { left, right in
                let leftNumber = Double(left.label)
                let rightNumber = Double(right.label)
                if let leftNumber, let rightNumber, leftNumber != rightNumber {
                    return leftNumber > rightNumber
                }
                if leftNumber != nil, rightNumber == nil { return true }
                if leftNumber == nil, rightNumber != nil { return false }
                return left.label.localizedStandardCompare(right.label) == .orderedAscending
            }
    }

    private func orderedOptions(from tallies: [String: OptionTally]) -> [FilterOption] {
        let sorted = tallies.sorted { left, right in
            let a = left.value
            let b = right.value
            if a.groupOrder != b.groupOrder { return a.groupOrder < b.groupOrder }
            if a.sortValue != b.sortValue { return a.sortValue < b.sortValue }
            return a.label < b.label
        }

        return sorted.map { key, tally in
            FilterOption(id: key, label: tally.label, group: tally.group, count: tally.count)
        }
    }

    // MARK: - Pricing

    private var isRefreshing: Bool {
        if case .refreshing = refresh.status { return true }
        return false
    }

    /// One entry per unique printing-and-variant, in display order so whatever
    /// the user is looking at becomes fresh first. Eight owned copies of one
    /// printing are one target, not eight.
    @MainActor
    private func priceTargets(_ snapshot: Snapshot, includeImported: Bool) -> [PriceTarget] {
        var seen = Set<String>()
        var result: [PriceTarget] = []

        for row in snapshot.visible + snapshot.all {
            guard let card = snapshot.cardsByKey[row.id] else { continue }
            if card.providerID.hasPrefix("csv:"), !includeImported { continue }
            guard seen.insert(card.priceKey).inserted else { continue }
            let record = PriceStore.record(for: card, in: snapshot.recordsByKey)
            // When fallback is enabled, a fresh euro observation is still
            // unfinished: it cannot contribute to the USD collection total and
            // must reach the fallback immediately rather than waiting eight
            // hours for the ordinary catalog refresh interval.
            let hasFinishedPrice = PriceRefreshController.hasFinishedPrice(
                amount: record?.unitMarketPriceUSD,
                currencyCode: record?.currencyCode,
                usesFallback: usesPriceFallback
            )
            result.append(
                PriceTarget(
                    game: card.cardGame,
                    printingID: card.priceStorageID,
                    catalogPrintingID: card.catalogProviderID ?? card.providerID,
                    setCode: card.setCode,
                    variantID: card.variantID,
                    pokemonPrintRun: card.pokemonPrintRun,
                    importedIdentity: card.providerID.hasPrefix("csv:") && card.catalogProviderID == nil
                        ? ImportedPriceIdentity(
                            name: card.name,
                            setName: card.setName,
                            cardNumber: card.cardNumber
                        )
                        : nil,
                    catalogMetadataCheckedAt: card.catalogMetadataCheckedAt,
                    lastFailureAt: record?.lastFailureAt,
                    hasPrice: hasFinishedPrice,
                    lastCheckedAt: record?.lastCheckedAt,
                    itemKind: card.itemKind,
                    marketVariantID: card.justTCGVariantID,
                    // Only sealed rows: their artwork comes from the vendor's
                    // marketplace id, which arrives with the price. A card's
                    // picture comes from the catalog and is already there.
                    needsArtwork: ArtworkDiagnostics.shouldRetrySealedArtwork(for: card),
                    gradedIdentity: card.itemKind == .gradedCard
                        ? GradedCardIdentity(
                            name: card.name,
                            setName: card.setName,
                            collectorNumber: card.cardNumber
                        )
                        : nil,
                    gradingCompany: card.gradingCompany,
                    grade: card.gradeRaw
                )
            )
        }
        return result
    }

    /// Unique printing-and-finish rows that still lack a USD value. Counts card
    /// types rather than copies so the header matches refresh progress and quota
    /// cost instead of making a stack of duplicates look like extra work.
    private func fallbackPendingCount(_ snapshot: Snapshot) -> Int {
        var seen: Set<String> = []
        let currentMisses = Set(productIdentities.compactMap { identity in
            identity.vendorCardID == nil && identity.isCurrent() ? identity.key : nil
        })
        return snapshot.cardsByKey.values.reduce(into: 0) { count, card in
            guard seen.insert(card.priceKey).inserted else { return }
            guard !currentMisses.contains(card.priceKey) else { return }
            let record = PriceStore.record(for: card, in: snapshot.recordsByKey)
            if record?.unitMarketPriceUSD == nil || record?.currencyCode != "USD" {
                count += 1
            }
        }
    }

    private func fallbackAvailabilityTaskID(_ snapshot: Snapshot) -> String {
        "\(fallbackPendingCount(snapshot)):\(usesPriceFallback):\(PriceVendorCredentials.hasKey)"
    }

    /// Changes when quantity or identity changes, including 1 → 2 on an
    /// existing row (which `cards.count` cannot observe).
    ///
    /// An order-independent hash rather than a sorted, joined string: this is
    /// re-evaluated on every body pass, and building an O(n log n) string per
    /// render in the same file that warns the snapshot is already O(n) per
    /// render was self-defeating. Nothing outside this process compares the
    /// value, so a `Hasher` is enough.
    private var collectionMutationTaskID: Int {
        // Commutative on purpose: CloudKit can return the same logical
        // collection in a different fetch order, and a signature that changed
        // with row order would restart portfolio work for no reason.
        //
        // XOR alone is not enough. Two rows identical in key, quantity and
        // instrument cancel each other out — which is precisely the duplicate
        // row case `LogicalCollection` exists to absorb. Count, wrapping sum
        // and XOR together survive both reordering and cancellation.
        var count = 0
        var sum = 0
        var xor = 0
        for card in cards {
            var element = Hasher()
            element.combine(card.collectionKey)
            element.combine(card.quantity)
            element.combine(card.priceKey)
            let value = element.finalize()
            count += 1
            sum &+= value
            xor ^= value
        }
        var hasher = Hasher()
        hasher.combine(count)
        hasher.combine(sum)
        hasher.combine(xor)
        return hasher.finalize()
    }

    @MainActor
    private func recomputeAtDayRollover() async {
        while !Task.isCancelled {
            let timeZone = PortfolioCalendar.timeZone()
            let today = PortfolioCalendar.day(containing: .now, in: timeZone)
            let next = PortfolioCalendar.boundary(afterDay: today, in: timeZone)
            let delay = max(1, next.timeIntervalSinceNow + 0.5)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            portfolio.recompute(context: modelContext)
        }
    }

    @MainActor
    private func refreshAllPrices() async {
        refreshStatusTask?.cancel()
        showsManualRefreshStatus = true
        let targets = PriceRefreshController.staleTargets(
            from: priceTargets(makeSnapshot(), includeImported: true)
        )
        guard !targets.isEmpty else {
            refresh.markRecentlyChecked()
            scheduleRefreshStatusDismissal()
            return
        }
        await runRefresh(targets, showsStatus: true)
    }

    /// Quiet background top-up. Existing prices stay visible the whole time —
    /// there is no blank grid and no blocking spinner.
    @MainActor
    private func refreshStalePricesIfNeeded() async {
        guard !hasCheckedForStalePrices, !cards.isEmpty else { return }
        hasCheckedForStalePrices = true

        let stale = PriceRefreshController.staleTargets(
            from: priceTargets(makeSnapshot(), includeImported: false)
        )
        guard !stale.isEmpty else { return }
        await runRefresh(stale, showsStatus: false)
    }

    @MainActor
    private func runRefresh(_ targets: [PriceTarget], showsStatus: Bool) async {
        await refresh.refresh(targets, store: PriceStore(context: modelContext))
        portfolio.recompute(context: modelContext)
        guard showsStatus else {
            refresh.dismissSummary()
            return
        }

        scheduleRefreshStatusDismissal()
    }

    private func scheduleRefreshStatusDismissal() {
        refreshStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            showsManualRefreshStatus = false
            refresh.dismissSummary()
        }
    }

}

/// Menu labels cannot use `FilterChip` directly because a `Menu` supplies its own
/// button behaviour, so the visual half is shared instead.
struct FilterChipLabel: View {
    let title: String
    let isActive: Bool
    var symbol: String = "chevron.down"

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .background(
            isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
            in: Capsule()
        )
    }
}

private struct CollectionCardTile: View {
    let card: CollectedCard
    let price: PriceDisplay
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.secondary.opacity(0.08)

                CollectionCardArtwork(
                    userArtworkFilename: card.userArtworkFilename,
                    thumbnailURL: card.lowImageURL,
                    fullSizeURL: card.highImageURL,
                    placeholderText: artworkReason?.title
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if card.quantity > 1 {
                    Text("×\(card.quantity)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.78), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PriceLabel(price: price, style: .compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Text(card.setName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    switch card.itemKind {
                    case .rawCard:
                        if let variant = card.variant {
                            CollectionFinishBadge(variant: variant)
                        }
                    case .gradedCard, .sealedProduct:
                        // A slab or a box has no raw finish, so the badge shows
                        // what it actually is: `PSA 10`, `Sealed`.
                        CollectionItemKindBadge(
                            title: card.itemKindLabel,
                            kind: card.itemKind
                        )
                    }
                }

                if let unpricedReason {
                    Label(unpricedReason.title, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(card.name), \(card.setName), \(accessiblePrice), \(card.itemKindLabel), quantity \(card.quantity)\(diagnosticAccessibilityText)"
        )
    }

    private var diagnosticAccessibilityText: String {
        [unpricedReason?.title, artworkReason?.title]
            .compactMap { $0 }
            .map { ", \($0)" }
            .joined()
    }

    private var accessiblePrice: String {
        if let amount = price.amount {
            return amount.formatted(.currency(code: price.currencyCode))
        }
        return price.state() == .unavailable ? "price unavailable" : "price not checked"
    }
}

/// The badge for a row that is not a raw single.
///
/// Deliberately the same shape and weight as the finish badge beside it: a
/// graded slab and a reverse holo are both "what kind of copy this is", and
/// making one look like a different class of information would be misleading.
private struct CollectionItemKindBadge: View {
    let title: String
    let kind: CollectionItemKind

    var body: some View {
        Label(title, systemImage: kind.symbolName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private var tint: Color {
        switch kind {
        case .gradedCard: return .indigo
        case .sealedProduct: return .brown
        case .rawCard: return .secondary
        }
    }
}

private struct CollectionFinishBadge: View {
    let variant: PhysicalVariant

    var body: some View {
        Label(variant.label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private var tint: Color {
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return .teal
        case PhysicalVariant.foil.id, PhysicalVariant.holo.id, PhysicalVariant.etched.id:
            return .purple
        case PhysicalVariant.pokeBall.id, PhysicalVariant.masterBall.id, PhysicalVariant.firstEdition.id:
            return .orange
        case PhysicalVariant.normal.id, PhysicalVariant.nonfoil.id:
            return .secondary
        default:
            return .blue
        }
    }

    private var symbol: String {
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return "arrow.triangle.2.circlepath"
        case PhysicalVariant.foil.id, PhysicalVariant.holo.id, PhysicalVariant.etched.id:
            return "sparkles"
        case PhysicalVariant.pokeBall.id, PhysicalVariant.masterBall.id:
            return "circle.circle"
        case PhysicalVariant.firstEdition.id:
            return "1.circle"
        default:
            return "circle.fill"
        }
    }
}

/// Use the same URL that powers the detail screen. Some newly returned catalog
/// records have a working full-size image while their thumbnail endpoint remains
/// unavailable, which otherwise leaves the grid stuck on a placeholder.
private struct CollectionCardArtwork: View {
    let userArtworkFilename: String?
    let thumbnailURL: URL?
    let fullSizeURL: URL?
    let placeholderText: String?

    private var primaryURL: URL? { fullSizeURL ?? thumbnailURL }

    private var fallbackURL: URL? {
        guard let thumbnailURL, thumbnailURL != primaryURL else { return nil }
        return thumbnailURL
    }

    var body: some View {
        if let image = CollectionArtworkStore.image(filename: userArtworkFilename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            AsyncImage(url: primaryURL) { phase in
                switch phase {
                case let .success(image):
                    cardImage(image)
                case .failure:
                    fallback
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let fallbackURL {
            AsyncImage(url: fallbackURL) { phase in
                switch phase {
                case let .success(image):
                    cardImage(image)
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private func cardImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(0.727, contentMode: .fit)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                    if let placeholderText {
                        Text(placeholderText)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .foregroundStyle(.secondary)
            }
    }
}

/// One place decides how a price is allowed to be described.
struct PriceLabel: View {
    enum Style { case compact, detailed }

    let price: PriceDisplay
    var style: Style = .compact

    var body: some View {
        switch price.state() {
        case .current:
            amount(.primary)

        case .stale:
            VStack(spacing: 1) {
                amount(.secondary)
                if style == .detailed, let asOf = price.effectiveAsOf {
                    Text("Last updated \(asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .unavailable:
            Text(style == .compact ? "—" : "Price unavailable")
                .font(style == .compact ? .headline : .subheadline)
                .foregroundStyle(.secondary)

        case .unknown:
            Text(style == .compact ? "—" : "Not checked yet")
                .font(style == .compact ? .headline : .subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private func amount(_ shade: HierarchicalShapeStyle) -> some View {
        Text(price.amount ?? 0, format: .currency(code: price.currencyCode))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(shade)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
