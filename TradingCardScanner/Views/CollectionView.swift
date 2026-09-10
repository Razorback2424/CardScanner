import OSLog
import SwiftData
import SwiftUI

private enum CollectionArtworkLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TradingCardScanner",
        category: "CollectionArtwork"
    )
}

/// Collection is for finding, filtering, and managing owned items. Portfolio
/// accounting and price refresh ownership remain app-scoped in `ContentView`.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @EnvironmentObject private var priceSnapshot: PriceSnapshotStore
    let catalog: any BrowseCatalogProviding
    let history: PortfolioHistoryStore
    /// Deliberately unobserved, like Portfolio's. The refresh button and
    /// `PriceRefreshActivityRow` read it in leaf views, and rebuilding the grid
    /// on every progress publication is exactly the cost this screen's
    /// projection cache exists to avoid.
    let refresh: PriceRefreshController
    let opensBrowseOnLaunch: Bool
    let opensMovementDetailsOnLaunch: Bool
    let opensCardDetailOnLaunch: Bool
    let onOpenScanner: @MainActor () -> Void
    let onRefresh: @MainActor () async -> Void
    @Binding var sort: CollectionSort

    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()

    @State private var searchText = ""
    /// What the grid is actually filtered by. Trails `searchText` by one short
    /// debounce so a large grid is not rebuilt on every keystroke.
    @State private var searchQuery = ""
    @State private var filters = CollectionFilters.none
    /// Filters are an inspector rather than a sheet: in a wide window they sit
    /// beside the grid so the result of a change is visible as it is made, and
    /// SwiftUI falls back to a sheet when there is no room for a column.
    @State private var isShowingFilters = false
    @State private var isShowingSettings = false
    @State private var pendingRemoval: RemovedCardSnapshot?
    @State private var removalErrorMessage: String?
    /// View-owned cache for the part of a snapshot that cannot change when the
    /// user edits search, filters, or sort. The cache is deliberately a plain
    /// reference rather than an observed object: changing it must not itself
    /// trigger another body evaluation.
    @State private var projectionCache = ProjectionCache()
    /// The compact phone stack or regular-width detail-column stack. Selection
    /// lives here rather than in a closure destination so it survives the
    /// window shrinking to one column and widening back out — resizing must
    /// never throw away where the user was.
    @State private var navigationPath: [Destination] = []
    /// `.doubleColumn` rather than `.automatic`: automatic hides the grid behind a
    /// toggle in a portrait iPad window, which would land the user on an empty
    /// detail pane in the one orientation an iPad is most often held.
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.cardFinishMotionSource) private var cardFinishMotion

    /// Both of the collection's destinations, so one hierarchy drives a push on a
    /// phone-sized window and a second column on an iPad-sized one. `card` carries
    /// the row id rather than the model object: a removed card's id simply stops
    /// resolving, which is how the detail column falls back to its placeholder.
    private enum Destination: Hashable {
        case browse
        case history
        case card(String)
        case movement(String)
    }

    init(
        catalog: any BrowseCatalogProviding = BrowseCatalog(),
        history: PortfolioHistoryStore,
        refresh: PriceRefreshController,
        opensBrowseOnLaunch: Bool,
        opensMovementDetailsOnLaunch: Bool = false,
        opensCardDetailOnLaunch: Bool = false,
        onOpenScanner: @escaping @MainActor () -> Void,
        onRefresh: @escaping @MainActor () async -> Void,
        sort: Binding<CollectionSort>
    ) {
        self.catalog = catalog
        self.history = history
        self.refresh = refresh
        self.opensBrowseOnLaunch = opensBrowseOnLaunch
        self.opensMovementDetailsOnLaunch = opensMovementDetailsOnLaunch
        self.opensCardDetailOnLaunch = opensCardDetailOnLaunch
        self.onOpenScanner = onOpenScanner
        self.onRefresh = onRefresh
        self._sort = sort
    }

    /// Adaptive rather than a fixed pair of columns: the same minimum tile width
    /// yields two columns at phone width and as many as the window earns on an
    /// iPad, without anything having to ask which device it is running on. 165pt
    /// is what a tile measures today in the two-column phone layout, so the phone
    /// result is unchanged.
    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 165), spacing: 16, alignment: .top)]
    }

    var body: some View {
        PerformanceSignpost.signposter.emitEvent("CollectionView.body")
        // Built once per render and threaded through so filtering, sorting, and
        // filter-option counts always describe the same logical collection.
        let snapshot = makeSnapshot()
        let optionRows = isShowingFilters ? rowsForOptions(snapshot) : []

        return Group {
            if horizontalSizeClass == .compact {
                // On a phone the collection itself is the navigation root. A
                // split view's empty detail column would otherwise become an
                // extra back-stop between a card and the collection grid.
                NavigationStack(path: $navigationPath) {
                    collectionRoot(snapshot)
                        .navigationDestination(for: Destination.self) { destination in
                            destinationView(destination, in: snapshot)
                        }
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    collectionRoot(snapshot)
                        // Wider than a stock sidebar, because this column is a
                        // grid of card art rather than a list of labels — at the
                        // default width it would show one column and waste the
                        // room it was given.
                        .navigationSplitViewColumnWidth(min: 360, ideal: 520)
                } detail: {
                    NavigationStack(path: $navigationPath) {
                        noSelection
                            .navigationDestination(for: Destination.self) { destination in
                                destinationView(destination, in: snapshot)
                            }
                    }
                }
            }
        }
        // The option tallies each walk every entry and sort the result, and a
        // modifier's arguments are evaluated whenever `body` runs — so closed or
        // not, they were paid for on every keystroke in the search field. Behind
        // the presentation flag they are computed only when the inspector is up.
        .inspector(isPresented: $isShowingFilters) {
            if isShowingFilters {
                CollectionFilterSheet(
                    isPresented: $isShowingFilters,
                    filters: $filters,
                    sort: $sort,
                    setOptions: setOptions(optionRows),
                    finishOptions: finishOptions(optionRows),
                    treatmentOptions: treatmentOptions(optionRows),
                    gradingCompanyOptions: gradingCompanyOptions(optionRows),
                    gradeOptions: gradeOptions(optionRows)
                )
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .task { await catalogNormalizer.normalizeImportedCards(in: modelContext.container) }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            searchQuery = searchText
        }
        .task {
            guard opensBrowseOnLaunch, navigationPath.isEmpty else { return }
            select(.browse)
        }
        .task {
            guard opensMovementDetailsOnLaunch, navigationPath.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard let entry = snapshot.entries.first else { return }
            navigationPath = [.card(entry.id), .movement(entry.id)]
        }
        .task(id: opensCardDetailOnLaunch ? snapshot.entries.first?.id : nil) {
            guard opensCardDetailOnLaunch, navigationPath.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard let entry = snapshot.entries.first else { return }
            navigationPath = [.card(entry.id)]
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

    @ViewBuilder
    private func collectionRoot(_ snapshot: Snapshot) -> some View {
        Group {
            if projectionStore.loadFailed {
                projectionLoadFailed
            } else if !projectionStore.isLoaded {
                loadingCollection
            } else if snapshot.all.isEmpty {
                emptyCollection
            } else {
                content(snapshot)
            }
        }
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    select(.browse)
                } label: {
                    Label("Find items to add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Find items to add")

                Button("Filters", systemImage: filters.isActive
                       ? "line.3.horizontal.decrease.circle.fill"
                       : "line.3.horizontal.decrease.circle") {
                    isShowingFilters = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel(filters.isActive ? "Filters, \(activeFilterCount) active" : "Filters")

                Button {
                    select(.history)
                } label: {
                    Label("Collection history", systemImage: "clock.arrow.circlepath")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Collection history")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Settings")
            }
        }
    }

    private var loadingCollection: some View {
        ProgressView("Loading collection…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectionLoadFailed: some View {
        ContentUnavailableView {
            Label("Collection Couldn’t Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The collection store could not be read. Try again.")
        } actions: {
            Button("Retry") {
                Task {
                    await projectionStore.rebuild(container: modelContext.container)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Replaces whatever the detail column is showing. Replacing rather than
    /// appending keeps the column one level deep: picking a second card from the
    /// grid should show that card, not stack it behind the first.
    private func select(_ destination: Destination) {
        navigationPath = [destination]
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination, in snapshot: Snapshot) -> some View {
        switch destination {
        case .browse:
            BrowseView(catalog: catalog)
        case .history:
            CollectionActivityLogView()
        case let .card(id):
            if let entry = snapshot.entries.first(where: { $0.id == id }) {
                CollectionCardDestination(
                    row: entry.row,
                    unpricedReason: entry.unpricedReason,
                    artworkReason: entry.artworkReason,
                    isLogicalConflict: entry.isLogicalConflict,
                    history: history,
                    onRemoved: presentUndo(for:)
                )
            } else {
                // The card was removed, or a filter now excludes it. Either way the
                // id no longer names anything, so say so rather than showing a stale
                // copy of a card that is not in the collection any more.
                ContentUnavailableView(
                    "Card not shown",
                    systemImage: "rectangle.stack",
                    description: Text("It was removed, or the current filters exclude it.")
                )
            }
        case let .movement(id):
            if let entry = snapshot.entries.first(where: { $0.id == id }) {
                CollectionMovementDestination(row: entry.row, history: history)
            } else {
                ContentUnavailableView(
                    "Card not shown",
                    systemImage: "rectangle.stack",
                    description: Text("It was removed, or the current filters exclude it.")
                )
            }
        }
    }

    private var noSelection: some View {
        ContentUnavailableView(
            "No card selected",
            systemImage: "rectangle.stack",
            description: Text("Choose a card to see its details.")
        )
    }

    private func content(_ snapshot: Snapshot) -> some View {
        let hasSpecularFinish = snapshot.entries.contains { $0.row.hasSpecularFinish }

        return ScrollView {
            LazyVStack(spacing: 12) {
                collectionSummary(snapshot)
                filterBar(snapshot)

                if snapshot.entries.isEmpty {
                    noMatches
                } else {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(snapshot.entries) { entry in
                            // A button driving the detail column's path rather than a
                            // `NavigationLink`: links push onto the stack that encloses
                            // them, and the stack that must move is the one in the next
                            // column over.
                            Button {
                                select(.card(entry.id))
                            } label: {
                                CollectionCardTile(
                                    row: entry.row,
                                    unpricedReason: entry.unpricedReason,
                                    artworkReason: entry.artworkReason
                                )
                            }
                            .buttonStyle(CollectionTileButtonStyle())
                            // A plain button only takes hits on its drawn pixels, which
                            // leaves the gaps inside a tile dead to both touch and the
                            // pointer. The tile is one target, so say so.
                            .contentShape(.rect)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .contentWidthLimit(.wide)
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, prompt: "Search collection")
        .refreshable {
            // `refreshable` holds the grid pushed down under its spinner for
            // as long as this closure is suspended, and a pass over a few
            // hundred cards with paced fallback requests runs for minutes.
            // Hand the work to a task that outlives the gesture and let the
            // status row above the grid report it — the same progress
            // Portfolio shows, from the same publisher.
            Task { await onRefresh() }
            try? await Task.sleep(for: .milliseconds(500))
        }
        .animation(.easeOut(duration: 0.2), value: filters)
        .animation(.easeOut(duration: 0.2), value: sort)
        .animation(.easeOut(duration: 0.2), value: searchQuery)
        .onAppear {
            if hasSpecularFinish {
                cardFinishMotion.startGrid()
            }
        }
        .onChange(of: hasSpecularFinish) { _, isActive in
            if isActive {
                cardFinishMotion.startGrid()
            } else {
                cardFinishMotion.stopGrid()
            }
        }
        .onDisappear { cardFinishMotion.stopGrid() }
    }

    private func collectionSummary(_ snapshot: Snapshot) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shown value")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(snapshot.shownValue.formatted())
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PortfolioPalette.money)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: snapshot.shownValue)
                            .accessibilityLabel("Shown collection value, \(snapshot.shownValue.formatted())")

                        Text(snapshot.countSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                CollectionRefreshButton(refresh: refresh, onRefresh: onRefresh)
            }

            // Pull-to-refresh returns immediately, so this is where a running
            // pass is actually reported. Entry point and progress live
            // together rather than in different screens.
            PriceRefreshActivityRow(refresh: refresh)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var emptyCollection: some View {
        ContentUnavailableView {
            Label("No items yet", systemImage: "rectangle.stack.badge.plus")
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
            + (filters.treatmentIDs.isEmpty ? 0 : 1)
            + (filters.minimumQuantity == nil ? 0 : 1)
            + (filters.gradingCompanies.isEmpty ? 0 : 1)
            + (filters.gradeValues.isEmpty ? 0 : 1)
    }

    // MARK: - Data

    /// Everything one render of this screen needs, derived once.
    struct Snapshot {
        struct Entry: Identifiable {
            let row: CollectionRow
            let unpricedReason: PricingDiagnosticReason?
            let artworkReason: ArtworkDiagnosticReason?
            let isLogicalConflict: Bool

            var id: String { row.id }
        }

        let all: [CollectionRow]
        let entries: [Entry]
        let shownValue: Money
        let unpricedCount: Int

        var countSummary: String {
            let itemLabel = entries.count == 1 ? "item" : "items"
            guard unpricedCount > 0 else {
                return "\(entries.count) \(itemLabel)"
            }
            return "\(entries.count) \(itemLabel) · \(unpricedCount) unpriced"
        }
    }

    /// The expensive half of a collection render. Search and filter state are
    /// intentionally absent so typing remains a local operation over `all`.
    private struct CachedProjection {
        let all: [CollectionRow]
        let diagnosticsByCollectionKey: [String: CollectionRowDiagnostics]
        let physicalRowCountsByKey: [String: Int]
    }

    private struct QueryCacheKey: Equatable {
        let projectionRevision: UInt
        let priceRevision: UInt
        let searchQuery: String
        let filters: CollectionFilters
        let sort: CollectionSort
    }

    private struct PricedRowsCacheKey: Equatable {
        let projectionRevision: UInt
        let priceRevision: UInt
    }

    private final class ProjectionCache {
        private var projectionRevision: UInt?
        private var cachedValue: CachedProjection?
        private var pricedRowsKey: PricedRowsCacheKey?
        private var pricedRowsValue: [CollectionRow] = []
        private var visibleKey: QueryCacheKey?
        private var visibleValue: [CollectionRow] = []

        func value(
            for revision: UInt,
            build: () -> CachedProjection
        ) -> CachedProjection {
            if projectionRevision == revision, let cachedValue { return cachedValue }
            let value = build()
            projectionRevision = revision
            self.cachedValue = value
            pricedRowsKey = nil
            pricedRowsValue = []
            visibleKey = nil
            visibleValue = []
            return value
        }

        func pricedRows(
            for key: PricedRowsCacheKey,
            build: () -> [CollectionRow]
        ) -> [CollectionRow] {
            if pricedRowsKey == key { return pricedRowsValue }
            let value = build()
            pricedRowsKey = key
            pricedRowsValue = value
            visibleKey = nil
            visibleValue = []
            return value
        }

        func visible(
            for key: QueryCacheKey,
            build: () -> [CollectionRow]
        ) -> [CollectionRow] {
            if visibleKey == key { return visibleValue }
            let value = build()
            visibleKey = key
            visibleValue = value
            return value
        }
    }

    @MainActor
    private func makeSnapshot() -> Snapshot {
        guard let projected = projectionStore.snapshot else {
            return Snapshot(all: [], entries: [], shownValue: .zero, unpricedCount: 0)
        }

        let cached = projectionCache.value(for: projectionStore.revision) {
            CachedProjection(
                all: projected.rows,
                diagnosticsByCollectionKey: projected.diagnosticsByCollectionKey,
                physicalRowCountsByKey: projected.physicalRowCountsByKey
            )
        }

        let pricedRows = projectionCache.pricedRows(
            for: PricedRowsCacheKey(
                projectionRevision: projectionStore.revision,
                priceRevision: priceSnapshot.revision
            )
        ) {
            cached.all.map { row in
                var row = row
                if let price = priceSnapshot.display(for: row.priceStorageKey) {
                    row.price = price
                }
                return row
            }
        }
        let queryKey = QueryCacheKey(
            projectionRevision: projectionStore.revision,
            priceRevision: priceSnapshot.revision,
            searchQuery: searchQuery,
            filters: filters,
            sort: sort
        )
        let visible = projectionCache.visible(for: queryKey) {
            CollectionQuery.apply(
                nameQuery: searchQuery,
                filters: filters,
                sort: sort,
                to: pricedRows
            )
        }

        let entries = visible.map { row in
            let liveDiagnostics = priceSnapshot.diagnosticsByCollectionKey[row.id]
            let projectedDiagnostics = cached.diagnosticsByCollectionKey[row.id]
            return Snapshot.Entry(
                row: row,
                // A diagnostic is about the current value, not a permanent
                // property of the row. The delta channel clears the live
                // reason immediately; this guard also prevents an older
                // projection from rendering a warning beside a price.
                unpricedReason: row.price.amount == nil
                    ? (liveDiagnostics?.unpricedReason ?? projectedDiagnostics?.unpricedReason)
                    : nil,
                artworkReason: liveDiagnostics?.artworkReason
                    ?? projectedDiagnostics?.artworkReason,
                isLogicalConflict: (cached.physicalRowCountsByKey[row.id] ?? 1) > 1
            )
        }
        let shownValue = CollectionValuation.shownValue(for: entries.map(\.row))

        return Snapshot(
            all: pricedRows,
            entries: entries,
            shownValue: shownValue,
            unpricedCount: entries.filter { $0.row.price.amount == nil }.count
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

    private func setOptions(_ rows: [CollectionRow]) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rows {
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

    private func finishOptions(_ rows: [CollectionRow]) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rows {
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

    private func treatmentOptions(_ rows: [CollectionRow]) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rows {
            for treatment in row.displayedMagicTreatments {
                let id = treatment.id
                if var existing = tallies[id] {
                    existing.count += row.quantity
                    tallies[id] = existing
                } else {
                    tallies[id] = OptionTally(
                        label: treatment.label,
                        group: row.game.label,
                        groupOrder: row.game.rawValue,
                        count: row.quantity,
                        sortValue: id == MagicTreatment.neonInk.id ? 1 : 0
                    )
                }
            }
        }

        return orderedOptions(from: tallies)
    }

    private func gradingCompanyOptions(_ rows: [CollectionRow]) -> [FilterOption] {
        var counts: [GradingCompany: Int] = [:]
        for row in rows where row.itemKind == .gradedCard {
            guard let company = row.gradingCompany else { continue }
            counts[company, default: 0] += row.quantity
        }
        return GradingCompany.allCases.compactMap { company in
            guard let count = counts[company] else { return nil }
            return FilterOption(id: company.rawValue, label: company.label, group: nil, count: count)
        }
    }

    private func gradeOptions(_ rows: [CollectionRow]) -> [FilterOption] {
        var counts: [String: Int] = [:]
        for row in rows where row.itemKind == .gradedCard {
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

}

private struct CollectionCardDestination: View {
    @Query private var cards: [CollectedCard]

    let row: CollectionRow
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
    let isLogicalConflict: Bool
    @ObservedObject var history: PortfolioHistoryStore
    let onRemoved: (RemovedCardSnapshot) -> Void

    init(
        row: CollectionRow,
        unpricedReason: PricingDiagnosticReason?,
        artworkReason: ArtworkDiagnosticReason?,
        isLogicalConflict: Bool,
        history: PortfolioHistoryStore,
        onRemoved: @escaping (RemovedCardSnapshot) -> Void
    ) {
        self.row = row
        self.unpricedReason = unpricedReason
        self.artworkReason = artworkReason
        self.isLogicalConflict = isLogicalConflict
        self.history = history
        self.onRemoved = onRemoved
        let collectionKey = row.id
        self._cards = Query(
            filter: #Predicate<CollectedCard> { $0.collectionKey == collectionKey },
            sort: [SortDescriptor(\.dateAdded, order: .forward)]
        )
    }

    var body: some View {
        if let card = cards.first {
            CollectionCardDetailView(
                card: card,
                price: row.price,
                history: history,
                unpricedReason: unpricedReason,
                artworkReason: artworkReason,
                logicalQuantity: row.quantity,
                isLogicalConflict: isLogicalConflict,
                instrumentKey: row.priceStorageKey,
                onRemoved: onRemoved
            )
        } else {
            ContentUnavailableView(
                "Card not shown",
                systemImage: "rectangle.stack",
                description: Text("It was removed, or the current filters exclude it.")
            )
        }
    }
}

private struct CollectionMovementDestination: View {
    @Query private var cards: [CollectedCard]

    let row: CollectionRow
    @ObservedObject var history: PortfolioHistoryStore

    init(row: CollectionRow, history: PortfolioHistoryStore) {
        self.row = row
        self.history = history
        let collectionKey = row.id
        self._cards = Query(
            filter: #Predicate<CollectedCard> { $0.collectionKey == collectionKey },
            sort: [SortDescriptor(\.dateAdded, order: .forward)]
        )
    }

    var body: some View {
        if let card = cards.first {
            MovementDetailsView(
                card: card,
                price: row.price,
                history: history,
                quantity: row.quantity
            )
        } else {
            ContentUnavailableView(
                "Card not shown",
                systemImage: "rectangle.stack",
                description: Text("It was removed, or the current filters exclude it.")
            )
        }
    }
}

private struct CollectionTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct CollectionRefreshButton: View {
    @ObservedObject var refresh: PriceRefreshController
    let onRefresh: @MainActor () async -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isRefreshing: Bool {
        if case .refreshing = refresh.status { return true }
        return false
    }

    var body: some View {
        Button {
            Task { await onRefresh() }
        } label: {
            if dynamicTypeSize > .xxxLarge {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .imageScale(.medium)
            } else {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                    .imageScale(.medium)
            }
        }
        .foregroundStyle(Color("RefreshAccent"))
        .padding(.horizontal, 14)
        .frame(minWidth: 44)
        .frame(height: 44)
        .background(PortfolioPalette.money.opacity(0.18), in: Capsule())
        .disabled(isRefreshing)
        .accessibilityLabel("Refresh prices")
        .accessibilityValue(isRefreshing ? "In progress" : "")
    }
}

private struct CollectionCardTile: View {
    let row: CollectionRow
    /// The projected quantity for the position, not a physical row's quantity.
    /// CloudKit can legitimately split a position across several rows; the
    /// footer and detail view must agree about how many are owned.
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
    let showDefaultFinish: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.cardFinishMotionSource) private var cardFinishMotion
    @State private var loadedArtworkAccent: ArtworkAccent?

    private struct ArtworkSource: Equatable {
        let localFilename: String?
        let remoteURL: URL?
        let fallbackURL: URL?
    }

    init(
        row: CollectionRow,
        unpricedReason: PricingDiagnosticReason?,
        artworkReason: ArtworkDiagnosticReason?,
        showDefaultFinish: Bool = true
    ) {
        self.row = row
        self.unpricedReason = unpricedReason
        self.artworkReason = artworkReason
        self.showDefaultFinish = showDefaultFinish
    }

    private var artworkSource: ArtworkSource {
        let primaryURL = row.highImageURL ?? row.lowImageURL
        return ArtworkSource(
            localFilename: row.userArtworkFilename,
            remoteURL: primaryURL,
            fallbackURL: row.lowImageURL == primaryURL ? nil : row.lowImageURL
        )
    }

    private var artworkAccent: ArtworkAccent? {
        row.artworkAccent ?? loadedArtworkAccent
    }

    private var nameMinHeight: CGFloat? {
        dynamicTypeSize > .xxxLarge ? nil : 46
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                CollectionArtworkGlow(
                    accent: artworkAccent,
                    colorScheme: colorScheme,
                    reduceTransparency: reduceTransparency
                )

                ZStack {
                    CollectionCardArtwork(
                        userArtworkFilename: row.userArtworkFilename,
                        thumbnailURL: row.lowImageURL,
                        fullSizeURL: row.highImageURL,
                        placeholderText: artworkReason?.title
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if row.hasSpecularFinish {
                        CardFinishOverlay(
                            variant: row.variant,
                            resolution: row.variantResolution,
                            treatments: row.displayedMagicTreatmentEvidence.treatments,
                            cornerRadius: 10,
                            motionSource: cardFinishMotion
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .aspectRatio(5.0 / 7.0, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.18)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: nameMinHeight, alignment: .topLeading)

                    Text(identityLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color("TileIdentity"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                quietLine
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(row.name), \(row.setName), \(accessiblePrice), \(accessibleStatus), quantity \(row.quantity)\(diagnosticAccessibilityText)"
        )
        .task(id: artworkSource) {
            guard row.artworkAccent == nil else {
                loadedArtworkAccent = nil
                return
            }
            let accent = await ArtworkAccentStore.accent(
                localFilename: artworkSource.localFilename,
                remoteURL: artworkSource.remoteURL,
                fallbackRemoteURL: artworkSource.fallbackURL
            )
            guard !Task.isCancelled else { return }
            loadedArtworkAccent = accent
#if DEBUG
            CollectionArtworkLog.logger.notice(
                "Collection tile accent \(accent == nil ? "missing" : "loaded", privacy: .public) source=\(artworkSource.remoteURL?.absoluteString ?? artworkSource.localFilename ?? "none", privacy: .public) fallback=\(artworkSource.fallbackURL?.absoluteString ?? "none", privacy: .public)"
            )
#endif
        }
    }

    private var diagnosticAccessibilityText: String {
        [unpricedReason?.title, artworkReason?.title]
            .compactMap { $0 }
            .map { ", \($0)" }
            .joined()
    }

    private var accessiblePrice: String {
        if let amount = row.price.amount {
            return amount.formatted(.currency(code: row.price.currencyCode))
        }
        return row.price.state() == .unavailable ? "Price unavailable" : "Not checked yet"
    }

    private var accessibleStatus: String {
        CollectionFinishStatus.resolve(row: row, showDefaultFinish: showDefaultFinish)?.label
            ?? row.displayKindLabel
    }

    private var identityLine: String {
        [row.setName, row.cardNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var priceReplacementCaveat: String? {
        guard row.price.amount == nil else { return nil }
        if let unpricedReason { return unpricedReason.title }
        return row.price.state() == .unavailable ? "Price unavailable" : "Not checked yet"
    }

    @ViewBuilder
    private var quietLine: some View {
        HStack(alignment: .center, spacing: 8) {
            if let caveat = priceReplacementCaveat {
                Text(caveat)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                PriceLabel(price: row.price, style: .tile)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if row.quantity > 1 {
                Text("×\(row.quantity)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 4)

            if let status = CollectionFinishStatus.resolve(
                row: row,
                showDefaultFinish: showDefaultFinish
            ) {
                HStack(spacing: 5) {
                    CollectionFinishDot(style: statusDotStyle(for: status))
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint(for: status))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
            }
        }
    }

    private func statusDotStyle(for status: CollectionFinishStatus) -> CollectionFinishDot.Style {
        switch status.kind {
        case .treatment:
            return .treatment
        case .foil:
            return .foil
        case .reverse:
            return .reverse
        case .plain:
            return .plain
        case .flat:
            switch row.itemKind {
            case .gradedCard, .sealedProduct:
                return .flat(itemKindTint(for: row.itemKind))
            case .rawCard:
                return .flat(row.variant.map(finishTint(for:)) ?? .secondary)
            }
        }
    }

    private func statusTint(for status: CollectionFinishStatus) -> Color {
        switch status.kind {
        case .treatment:
            return .finishTreatment
        case .foil, .reverse, .plain:
            return row.variant.map(finishTint(for:)) ?? .secondary
        case .flat:
            switch row.itemKind {
            case .gradedCard, .sealedProduct:
                return itemKindTint(for: row.itemKind)
            case .rawCard:
                return row.variant.map(finishTint(for:)) ?? .secondary
            }
        }
    }

    private func finishTint(for variant: PhysicalVariant) -> Color {
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return .finishReverse
        case PhysicalVariant.foil.id, PhysicalVariant.holo.id, PhysicalVariant.etched.id:
            return .finishFoil
        case PhysicalVariant.pokeBall.id, PhysicalVariant.masterBall.id, PhysicalVariant.firstEdition.id:
            return .orange
        case PhysicalVariant.normal.id, PhysicalVariant.nonfoil.id:
            return .secondary
        default:
            return .blue
        }
    }

    private func itemKindTint(for kind: CollectionItemKind) -> Color {
        switch kind {
        case .gradedCard: return .finishGraded
        case .sealedProduct: return .finishSealed
        case .rawCard: return .secondary
        }
    }
}

private struct CollectionArtworkGlow: View {
    let accent: ArtworkAccent?
    let colorScheme: ColorScheme
    let reduceTransparency: Bool

    var body: some View {
        if let glowColor = accent?.color, !reduceTransparency {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(colorScheme == .dark ? 0.55 : 0.22),
                                .clear
                            ],
                            center: .init(x: 0.5, y: 0.6),
                            startRadius: 0,
                            endRadius: geo.size.width * 0.6
                        )
                    )
                    .blur(radius: 16)
                    .padding(.horizontal, geo.size.width * 0.10)
                    .padding(.top, geo.size.height * 0.18)
                    .padding(.bottom, -geo.size.height * 0.04)
            }
            .allowsHitTesting(false)
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

    /// The grid is now large enough that Scryfall's `small` asset is visibly
    /// blurry. The normal-sized asset is the primary, while the thumbnail
    /// remains a cheap fallback when a provider has not filled the larger URL.
    private var primaryURL: URL? { fullSizeURL ?? thumbnailURL }

    private var fallbackURL: URL? {
        guard let thumbnailURL, thumbnailURL != primaryURL else { return nil }
        return thumbnailURL
    }

    var body: some View {
        if let image = CollectionArtworkStore.image(
            filename: userArtworkFilename,
            maximumPixelDimension: 512
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            CatalogCachedImage(
                url: primaryURL,
                fallbackURL: fallbackURL,
                placeholderText: placeholderText
            )
        }
    }

}

/// One place decides how a price is allowed to be described.
struct PriceLabel: View {
    enum Style { case compact, detailed, tile }

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
                .font(style == .compact ? compactPriceFont : priceFont)
                .foregroundStyle(.secondary)

        case .unknown:
            Text(style == .compact ? "—" : "Not checked yet")
                .font(style == .compact ? compactPriceFont : priceFont)
                .foregroundStyle(.tertiary)
        }
    }

    private var compactPriceFont: Font {
        .system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
    }

    private var tilePriceFont: Font {
        .system(size: 15, weight: .semibold).monospacedDigit()
    }

    private var priceFont: Font {
        style == .tile ? tilePriceFont : .subheadline
    }

    private func amount(_ shade: HierarchicalShapeStyle) -> some View {
        Text(price.amount ?? 0, format: .currency(code: price.currencyCode))
            .font(style == .tile ? tilePriceFont : compactPriceFont)
            .foregroundStyle(shade)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentTransition(.numericText())
            .animation(.snappy, value: price.amount)
    }
}
