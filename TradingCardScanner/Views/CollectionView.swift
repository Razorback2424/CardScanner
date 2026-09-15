import OSLog
import SwiftData
import SwiftUI
import UIKit

private enum CollectionArtworkLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TradingCardScanner",
        category: "CollectionArtwork"
    )
}

/// The root owns the refresh operation, while Collection owns the way a
/// deliberate Collection refresh is reported. Keeping the terminal snapshot
/// as a value prevents the root's transient-status cleanup from erasing the
/// result before Collection can present it.
struct CollectionRefreshOutcome: Equatable {
    let status: PriceRefreshController.Status
    let fallbackStatus: PriceRefreshController.FallbackStatus

    static let idle = CollectionRefreshOutcome(
        status: .idle,
        fallbackStatus: .idle
    )
}

struct CollectionRefreshStatusPresentation: Equatable {
    let message: String
    let isWarning: Bool
    let isTransient: Bool
}

enum CollectionRefreshStatusResolver {
    static let updating = CollectionRefreshStatusPresentation(
        message: "Updating prices…",
        isWarning: false,
        isTransient: false
    )

    static func presentation(
        for outcome: CollectionRefreshOutcome
    ) -> CollectionRefreshStatusPresentation? {
        let fallbackWarning = hasUnresolvedFallbackWork(outcome.fallbackStatus)
            ? warning("Some prices couldn’t be refreshed")
            : nil

        switch outcome.status {
        case .idle, .refreshing:
            break
        case .recentlyChecked:
            return fallbackWarning ?? transient("Prices already current")
        case let .finished(summary):
            if summary.targetBuildFailed {
                return warning("Couldn’t refresh prices")
            }
            if summary.providerUnreachable {
                return warning("Pricing provider unavailable")
            }
            if summary.persistenceFailed {
                return warning("Some updates couldn’t be saved")
            }
            if let fallbackWarning {
                return fallbackWarning
            }
            if summary.failed > 0
                || summary.gradedLookupMisses > 0
                || summary.gradedTransportFailures > 0
                || summary.reconciledDuplicateRecords > 0 {
                return warning("Prices updated with some issues")
            }
            if summary.changedPrices {
                return transient("Prices updated")
            }
            return transient("Prices checked — already current")
        }

        return fallbackWarning
    }

    private static func transient(_ message: String) -> CollectionRefreshStatusPresentation {
        CollectionRefreshStatusPresentation(
            message: message,
            isWarning: false,
            isTransient: true
        )
    }

    private static func warning(_ message: String) -> CollectionRefreshStatusPresentation {
        CollectionRefreshStatusPresentation(
            message: message,
            isWarning: true,
            isTransient: false
        )
    }

    private static func hasUnresolvedFallbackWork(
        _ status: PriceRefreshController.FallbackStatus
    ) -> Bool {
        switch status {
        case let .disabled(pending), let .unconfigured(pending):
            return pending > 0
        case let .budgetReached(pending, _), let .rateLimited(pending, _):
            return pending > 0
        case .idle, .available, .running, .finished:
            return false
        }
    }
}

private struct CollectionRefreshFeedback: Equatable {
    let id: UUID
    let presentation: CollectionRefreshStatusPresentation
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
    let opensCardDetailForCollectionKey: String?
    let waitsForCardDetailCollectionKey: Bool
    let onOpenScanner: @MainActor () -> Void
    let onRefresh: @MainActor () async -> CollectionRefreshOutcome
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
    /// A Collection-local guard prevents double taps without disabling a
    /// request that should join an already-running automatic controller pass.
    @State private var collectionRefreshRequestInFlight = false
    @State private var collectionRefreshFeedback: CollectionRefreshFeedback?
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
        opensCardDetailForCollectionKey: String? = nil,
        waitsForCardDetailCollectionKey: Bool = false,
        onOpenScanner: @escaping @MainActor () -> Void,
        onRefresh: @escaping @MainActor () async -> CollectionRefreshOutcome,
        sort: Binding<CollectionSort>
    ) {
        self.catalog = catalog
        self.history = history
        self.refresh = refresh
        self.opensBrowseOnLaunch = opensBrowseOnLaunch
        self.opensMovementDetailsOnLaunch = opensMovementDetailsOnLaunch
        self.opensCardDetailOnLaunch = opensCardDetailOnLaunch
        self.opensCardDetailForCollectionKey = opensCardDetailForCollectionKey
        self.waitsForCardDetailCollectionKey = waitsForCardDetailCollectionKey
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
        .task {
            guard let storageToken = CollectionStorageGeneration.shared.currentToken() else {
                return
            }
            await catalogNormalizer.normalizeImportedCards(
                in: modelContext.container,
                shouldContinue: {
                    CollectionStorageGeneration.shared.isCurrent(storageToken)
                }
            )
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            searchQuery = searchText
        }
        .task(id: collectionRefreshFeedback?.id) {
            guard let feedback = collectionRefreshFeedback,
                  feedback.presentation.isTransient else { return }
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled,
                  collectionRefreshFeedback?.id == feedback.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                collectionRefreshFeedback = nil
            }
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
        .task(id: opensCardDetailOnLaunch ? cardDetailLaunchTaskID : nil) {
            guard opensCardDetailOnLaunch, navigationPath.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(500))
            let targetID: String?
            if waitsForCardDetailCollectionKey {
                targetID = opensCardDetailForCollectionKey
            } else {
                targetID = opensCardDetailForCollectionKey ?? snapshot.entries.first?.id
            }
            guard let targetID,
                  snapshot.entries.contains(where: { $0.id == targetID }) else { return }
            navigationPath = [.card(targetID)]
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

    private var cardDetailLaunchTaskID: String {
        let projectionRevision = projectionStore.revision
        if waitsForCardDetailCollectionKey {
            return "\(opensCardDetailForCollectionKey ?? "waiting-for-card-detail-target")-\(projectionRevision)"
        }
        return "\(opensCardDetailForCollectionKey ?? "card-detail-launch")-\(projectionRevision)"
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
        // iOS 26 centers a normal inline title when only two trailing actions
        // remain, while an explicit leading Text becomes a clipped glass
        // control. This small safe-area row keeps the requested leading title,
        // exact spacing, and separator without changing the destination stacks.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            collectionNavigationHeader
        }
    }

    private var collectionNavigationHeader: some View {
        HStack(spacing: 0) {
            Text("Collection")
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            HStack(spacing: 18) {
                Button {
                    select(.browse)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Find items to add")

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .foregroundStyle(.primary)
            .tint(.primary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
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
            LazyVStack(spacing: 14) {
                collectionHeader(snapshot)

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
                    collectionFooter(snapshot)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentWidthLimit(.wide)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            // `refreshable` holds the grid pushed down under its spinner for
            // as long as this closure is suspended, and a pass over a few
            // hundred cards with paced fallback requests runs for minutes.
            // Hand the work to a task that outlives the gesture and let the
            // status row above the grid report it — the same progress
            // Portfolio shows, from the same publisher.
            requestCollectionRefresh()
            try? await Task.sleep(for: .milliseconds(500))
        }
        .animation(.easeOut(duration: 0.2), value: filters)
        .animation(.easeOut(duration: 0.2), value: sort)
        .animation(.easeOut(duration: 0.2), value: searchQuery)
    }

    private func collectionHeader(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.collectionValue.formatted())
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(-0.76)
                        .foregroundStyle(Color("RefreshAccent"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: snapshot.collectionValue)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "Collection value, \(snapshot.collectionValue.formatted())"
                        )

                    CollectionRefreshStatusLine(
                        refresh: refresh,
                        isCollectionRequestInFlight: collectionRefreshRequestInFlight,
                        feedback: collectionRefreshFeedback
                    )
                    .frame(height: 18, alignment: .leading)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                CollectionRefreshButton(
                    refresh: refresh,
                    isRequestInFlight: collectionRefreshRequestInFlight,
                    onRefresh: requestCollectionRefresh
                )
            }

            collectionControls
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
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

    @MainActor
    private func requestCollectionRefresh() {
        guard !collectionRefreshRequestInFlight else { return }

        collectionRefreshRequestInFlight = true
        collectionRefreshFeedback = nil

        Task { @MainActor in
            defer { collectionRefreshRequestInFlight = false }

            let outcome = await onRefresh()
            guard !Task.isCancelled,
                  let presentation = CollectionRefreshStatusResolver.presentation(for: outcome) else {
                return
            }

            withAnimation(.easeIn(duration: 0.18)) {
                collectionRefreshFeedback = CollectionRefreshFeedback(
                    id: UUID(),
                    presentation: presentation
                )
            }
            UIAccessibility.post(
                notification: .announcement,
                argument: presentation.message
            )
        }
    }

    // MARK: - Filters

    @ViewBuilder
    private var collectionControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            collectionControlsStacked
        } else {
            ViewThatFits(in: .horizontal) {
                collectionControlsRow
                collectionControlsStacked
            }
        }
    }

    private var collectionControlsRow: some View {
        HStack(spacing: 8) {
            collectionSearchField
                .frame(maxWidth: .infinity)
            collectionFilterButton
            collectionSortMenu
        }
    }

    private var collectionControlsStacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            collectionSearchField
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                collectionFilterButton
                collectionSortMenu
                Spacer(minLength: 0)
            }
        }
    }

    private var collectionControlFill: Color {
        Color.primary.opacity(0.08)
    }

    private var collectionSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search collection", text: $searchText)
                .font(.body)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .accessibilityLabel("Search collection")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            collectionControlFill,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .frame(minHeight: 44)
    }

    private var collectionFilterButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(filters.isActive ? Color("RefreshAccent") : .primary)
                .frame(width: 36, height: 36)
                .background(
                    collectionControlFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filters.isActive ? "Filters, \(activeFilterCount) active" : "Filters")
    }

    private var collectionSortMenu: some View {
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
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 18, weight: .medium))
                    .accessibilityHidden(true)
                Text(sortHeaderLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let sortDirectionSymbol {
                    Image(systemName: sortDirectionSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                collectionControlFill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .tint(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sort collection: \(sort.label)")
    }

    private var sortHeaderLabel: String {
        switch sort {
        case .priceHighToLow, .priceLowToHigh:
            return "Price"
        case .cardNumber:
            return "Card #"
        case .setAndCardNumber:
            return "Set + #"
        }
    }

    private var sortDirectionSymbol: String? {
        switch sort {
        case .priceHighToLow:
            return "arrow.down"
        case .priceLowToHigh, .cardNumber:
            return "arrow.up"
        case .setAndCardNumber:
            return nil
        }
    }

    private func collectionFooter(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.footer.itemSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let exclusionSummary = snapshot.footer.exclusionSummary {
                Text(exclusionSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

    /// The first line describes logical tiles currently visible. The second
    /// line explains the full collection total, so its copy count deliberately
    /// remains collection-wide even when search or filters narrow the grid.
    struct CollectionFooterPresentation: Equatable {
        let visibleLogicalItemCount: Int
        let excludedFromValueCopyCount: Int
        let hasNonPriceExclusions: Bool
        let isNarrowed: Bool

        var itemSummary: String {
            let itemLabel = visibleLogicalItemCount == 1 ? "item" : "items"
            return "\(visibleLogicalItemCount) \(itemLabel)\(isNarrowed ? " shown" : "")"
        }

        var exclusionSummary: String? {
            guard excludedFromValueCopyCount > 0 else { return nil }
            let copyLabel = excludedFromValueCopyCount == 1 ? "copy" : "copies"
            if hasNonPriceExclusions {
                let verb = excludedFromValueCopyCount == 1 ? "is" : "are"
                return "\(excludedFromValueCopyCount) \(copyLabel) \(verb) not included in the collection value."
            }
            return "\(excludedFromValueCopyCount) \(copyLabel) unpriced, not included in the total."
        }

        static func make(
            visibleRows: [CollectionRow],
            collectionRows: [CollectionRow],
            isNarrowed: Bool
        ) -> Self {
            let excludedRows = collectionRows.filter { row in
                PortfolioPriceEligibility.eligibleUnitPrice(
                    amount: row.price.amount,
                    currencyCode: row.price.currencyCode
                ) == nil
            }
            return Self(
                visibleLogicalItemCount: visibleRows.count,
                excludedFromValueCopyCount: excludedRows.reduce(0) {
                    $0 + max(0, $1.quantity)
                },
                hasNonPriceExclusions: excludedRows.contains { $0.price.amount != nil },
                isNarrowed: isNarrowed
            )
        }
    }

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
        let collectionValue: Money
        let footer: CollectionFooterPresentation
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
            return Snapshot(
                all: [],
                entries: [],
                collectionValue: .zero,
                footer: .make(visibleRows: [], collectionRows: [], isNarrowed: false)
            )
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
        let collectionValue = CollectionValuation.shownValue(for: pricedRows)
        let footer = CollectionFooterPresentation.make(
            visibleRows: entries.map(\.row),
            collectionRows: pricedRows,
            isNarrowed: !searchQuery.isEmpty || filters.isActive
        )

        return Snapshot(
            all: pricedRows,
            entries: entries,
            collectionValue: collectionValue,
            footer: footer
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
                        sortValue: MagicTreatment.modelled.firstIndex(of: treatment) ?? Int.max
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
    let isRequestInFlight: Bool
    let onRefresh: @MainActor () -> Void

    private var isRefreshActive: Bool {
        isRequestInFlight || refresh.isPassInFlight
    }

    var body: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .foregroundStyle(Color("RefreshAccent"))
        .background(
            PortfolioPalette.money.opacity(0.18),
            in: Circle()
        )
        .contentShape(Circle())
        .disabled(isRequestInFlight)
        .accessibilityLabel("Refresh prices")
        .accessibilityValue(isRefreshActive ? "In progress" : "")
    }
}

private struct CollectionRefreshStatusLine: View {
    @ObservedObject var refresh: PriceRefreshController
    let isCollectionRequestInFlight: Bool
    let feedback: CollectionRefreshFeedback?

    private var presentation: CollectionRefreshStatusPresentation? {
        if isCollectionRequestInFlight || refresh.isPassInFlight {
            return CollectionRefreshStatusResolver.updating
        }
        let currentPresentation = CollectionRefreshStatusResolver.presentation(
            for: CollectionRefreshOutcome(
                status: refresh.status,
                fallbackStatus: refresh.fallbackStatus
            )
        )

        // An automatic pass may leave an unresolved warning behind. It must
        // remain visible even if an older Collection success is still in its
        // two-and-a-half-second presentation window.
        if let currentPresentation, currentPresentation.isWarning {
            return currentPresentation
        }
        if let feedback {
            // A later clean automatic pass resolves a warning left by an older
            // manual request, so do not keep presenting that stale warning.
            if feedback.presentation.isWarning,
               currentPresentation?.isTransient == true {
                return nil
            }
            return feedback.presentation
        }
        // A clean terminal state belongs to the initiating surface. Automatic
        // passes may still leave warnings here, but should not interrupt the
        // user with a transient success message.
        return currentPresentation?.isTransient == true ? nil : currentPresentation
    }

    var body: some View {
        Group {
            if let presentation {
                Text(presentation.message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(
                        presentation.isWarning
                            ? PortfolioPalette.attention
                            : Color("RefreshAccent")
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.message)
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        game: row.game,
                        setCode: row.setCode,
                        collectorNumber: row.cardNumber,
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
    let game: CardGame
    let setCode: String
    let collectorNumber: String
    let thumbnailURL: URL?
    let fullSizeURL: URL?
    let placeholderText: String?

    private var artworkSource: CatalogCardArtworkSource {
        CatalogCardArtworkSource(
            game: game,
            setCode: setCode,
            collectorNumber: collectorNumber,
            thumbnailURL: thumbnailURL,
            imageURL: fullSizeURL,
            // The collection grid is large enough that the normal-sized asset
            // should be primary. The thumbnail and then Limitless full image
            // remain explicit fallbacks.
            prefersFullSize: true
        )
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
                url: artworkSource.primaryURL,
                fallbacks: artworkSource.fallbacks,
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
