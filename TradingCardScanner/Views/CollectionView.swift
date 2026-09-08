import OSLog
import SwiftData
import SwiftUI

/// Collection is for finding, filtering, and managing owned items. Portfolio
/// accounting and price refresh ownership remain app-scoped in `ContentView`.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @EnvironmentObject private var priceSnapshot: PriceSnapshotStore
    let catalog: any BrowseCatalogProviding
    let history: PortfolioHistoryStore
    /// Deliberately unobserved, like Portfolio's. Only `PriceRefreshActivityRow`
    /// reads it, and rebuilding the grid on every progress publication is
    /// exactly the cost this screen's projection cache exists to avoid.
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
        return ScrollView {
            LazyVStack(spacing: 12) {
                collectionSummary(snapshot)
                filterBar(snapshot)

                if snapshot.entries.isEmpty {
                    noMatches
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
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
                            .buttonStyle(.plain)
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
    }

    private func collectionSummary(_ snapshot: Snapshot) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shown value")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(snapshot.shownValue.formatted())
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("Shown collection value, \(snapshot.shownValue.formatted())")
                }
                Spacer(minLength: 12)
                Text("\(snapshot.entries.count) \(snapshot.entries.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            return Snapshot(all: [], entries: [], shownValue: .zero)
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
        let shownValue = entries.reduce(Money.zero) { total, entry in
            guard entry.row.price.currencyCode == "USD",
                  let unitPrice = entry.row.price.amount,
                  let money = Money(rounding: unitPrice) else {
                return total
            }
            return total + money * entry.row.quantity
        }

        return Snapshot(
            all: pricedRows,
            entries: entries,
            shownValue: shownValue
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

private struct CollectionCardTile: View {
    let row: CollectionRow
    /// The projected quantity for the position, not a physical row's quantity. The row
    /// is one physical row, and CloudKit can legitimately split a position
    /// across several of them; the badge and the detail view must agree about
    /// how many are owned.
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                CollectionCardArtwork(
                    userArtworkFilename: row.userArtworkFilename,
                    thumbnailURL: row.lowImageURL,
                    fullSizeURL: row.highImageURL,
                    placeholderText: artworkReason?.title
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)

                Text(identityLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        PriceLabel(price: row.price, style: .compact)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 4)
                        inlineBadgeRow
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        PriceLabel(price: row.price, style: .compact)
                        badgeContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(row.name), \(row.setName), \(accessiblePrice), \(row.displayKindLabel), quantity \(row.quantity)\(diagnosticAccessibilityText)"
        )
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
        return row.price.state() == .unavailable ? "price unavailable" : "price not checked"
    }

    private var identityLine: String {
        [row.setCode, row.cardNumber, row.setName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var inlineBadgeRow: some View {
        badgeContent
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var badgeContent: some View {
        CollectionBadgeWrapLayout(itemSpacing: 6, rowSpacing: 4) {
            switch row.itemKind {
            case .rawCard:
                if let variant = row.variant,
                   !row.displayedMagicTreatmentEvidence.impliesFinish(variant) {
                    AppCardBadge(
                        text: variant.label,
                        systemImage: finishSymbol(for: variant),
                        tint: finishTint(for: variant)
                    )
                }
            case .gradedCard, .sealedProduct:
                // A slab or a box has no raw finish, so the badge shows what it
                // actually is: `PSA 10`, `Sealed`.
                AppCardBadge(
                    text: row.displayKindLabel,
                    systemImage: row.itemKind.symbolName,
                    tint: itemKindTint(for: row.itemKind)
                )
            }

            ForEach(
                Array(row.displayedMagicTreatmentEvidence.displayLabels.enumerated()),
                id: \.offset
            ) { item in
                AppCardBadge(
                    text: item.element,
                    systemImage: "wand.and.stars",
                    tint: .pink
                )
            }

            if row.quantity > 1 {
                AppCardBadge(text: "×\(row.quantity)", tint: .teal)
            }

            if let unpricedReason {
                AppCardBadge(
                    text: unpricedReason.title,
                    systemImage: "exclamationmark.circle",
                    tint: .orange
                )
            }
        }
    }

    private func finishTint(for variant: PhysicalVariant) -> Color {
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

    private func finishSymbol(for variant: PhysicalVariant) -> String {
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

    private func itemKindTint(for kind: CollectionItemKind) -> Color {
        switch kind {
        case .gradedCard: return .indigo
        case .sealedProduct: return .brown
        case .rawCard: return .secondary
        }
    }
}

/// Keeps the compact badge vocabulary visible without introducing a nested
/// horizontal scroll view inside the collection's vertical grid scroll view.
/// The layout is intentionally small and local: badges keep their intrinsic
/// width and move to a new line when the footer or Dynamic Type leaves less
/// room for them.
private struct CollectionBadgeWrapLayout: Layout {
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? intrinsicWidth(of: subviews)
        guard !subviews.isEmpty else { return .zero }

        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maximumRowWidth: CGFloat = 0

        for subview in subviews {
            let size = badgeSize(for: subview, availableWidth: availableWidth)
            let proposedRowWidth = rowWidth == 0 ? size.width : rowWidth + itemSpacing + size.width

            if rowWidth > 0, proposedRowWidth > availableWidth {
                totalHeight += rowHeight
                totalHeight += rowSpacing
                maximumRowWidth = max(maximumRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = proposedRowWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalHeight += rowHeight
        maximumRowWidth = max(maximumRowWidth, rowWidth)
        return CGSize(
            width: proposal.width ?? maximumRowWidth,
            height: totalHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let availableWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = badgeSize(for: subview, availableWidth: availableWidth)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func intrinsicWidth(of subviews: Subviews) -> CGFloat {
        subviews.reduce(0) { width, subview in
            width + (width == 0 ? 0 : itemSpacing) + badgeSize(for: subview, availableWidth: nil).width
        }
    }

    private func badgeSize(for subview: LayoutSubviews.Element, availableWidth: CGFloat?) -> CGSize {
        subview.sizeThatFits(
            ProposedViewSize(width: availableWidth, height: nil)
        )
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
                .font(style == .compact ? .title3.weight(.semibold).monospacedDigit() : .subheadline)
                .foregroundStyle(.secondary)

        case .unknown:
            Text(style == .compact ? "—" : "Not checked yet")
                .font(style == .compact ? .title3.weight(.semibold).monospacedDigit() : .subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private func amount(_ shade: HierarchicalShapeStyle) -> some View {
        Text(price.amount ?? 0, format: .currency(code: price.currencyCode))
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(shade)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
