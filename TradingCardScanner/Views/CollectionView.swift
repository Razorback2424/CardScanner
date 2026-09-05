import SwiftData
import SwiftUI

/// Inputs that can change the cached collection projection. Search text and
/// filter state intentionally do not participate: they only transform the
/// already-projected rows. Keeping this fingerprint separate makes the cache's
/// invalidation contract testable without rendering a full SwiftUI hierarchy.
enum CollectionProjectionToken {
    @MainActor
    static func make(
        cards: [CollectedCard],
        priceRecords: [PriceRecord],
        artworkOverrides: [LocalArtworkOverride]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(cards.count)
        for card in cards {
            // Only fields that change the logical projection or the value row
            // belong here. Artwork and diagnostic-only metadata remain on the
            // live model passed to each tile, so changing them must not rebuild
            // every CollectionRow.
            hasher.combine(card.collectionKey)
            hasher.combine(card.dateAdded)
            hasher.combine(card.providerID)
            hasher.combine(card.catalogProviderID)
            hasher.combine(card.name)
            hasher.combine(card.quantity)
            hasher.combine(card.game)
            hasher.combine(card.setName)
            hasher.combine(card.setCode)
            hasher.combine(card.cardNumber)
            hasher.combine(card.variantID)
            hasher.combine(card.variantLabel)
            hasher.combine(card.magicTreatmentIDsRaw)
            hasher.combine(card.magicTreatmentQualifiersJSON)
            hasher.combine(card.magicContentKindRaw)
            hasher.combine(card.pokemonPrintRunRaw)
            hasher.combine(card.setReleaseOrder)
            hasher.combine(card.itemKindRaw)
            hasher.combine(card.justTCGVariantID)
            hasher.combine(card.justTCGAPIVersion)
            hasher.combine(card.gradingCompanyRaw)
            hasher.combine(card.gradeRaw)
            hasher.combine(card.gradeLabel)
            hasher.combine(card.gradingQualifier)
        }

        hasher.combine(priceRecords.count)
        for record in priceRecords {
            hasher.combine(record.key)
            hasher.combine(record.game)
            hasher.combine(record.magicTreatmentIDsRaw)
            hasher.combine(record.unitMarketPriceUSD)
            hasher.combine(record.currencyCode)
            hasher.combine(record.sourceRaw)
            hasher.combine(record.sourceVariantID)
            hasher.combine(record.sourceUpdatedAt)
            hasher.combine(record.fetchedAt)
            hasher.combine(record.lastCheckedAt)
            hasher.combine(record.lastFailureAt)
            hasher.combine(record.lastFailureReasonRaw)
            hasher.combine(record.invalidatedAt)
        }

        hasher.combine(artworkOverrides.count)
        for override in artworkOverrides {
            hasher.combine(override.collectionKey)
        }
        return hasher.finalize()
    }
}

/// Collection is for finding, filtering, and managing owned items. Portfolio
/// accounting and price refresh ownership remain app-scoped in `ContentView`.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]

    @Query private var priceRecords: [PriceRecord]
    @Query private var artworkOverrides: [LocalArtworkOverride]
    let catalog: any BrowseCatalogProviding
    let history: PortfolioHistoryStore
    let opensBrowseOnLaunch: Bool
    let opensMovementDetailsOnLaunch: Bool
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
        opensBrowseOnLaunch: Bool,
        opensMovementDetailsOnLaunch: Bool = false,
        onOpenScanner: @escaping @MainActor () -> Void,
        onRefresh: @escaping @MainActor () async -> Void,
        sort: Binding<CollectionSort>
    ) {
        self.catalog = catalog
        self.history = history
        self.opensBrowseOnLaunch = opensBrowseOnLaunch
        self.opensMovementDetailsOnLaunch = opensMovementDetailsOnLaunch
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
        // Built once per render and threaded through so filtering, sorting, and
        // filter-option counts always describe the same logical collection.
        let snapshot = makeSnapshot()

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
                    setOptions: setOptions(snapshot),
                    finishOptions: finishOptions(snapshot),
                    treatmentOptions: treatmentOptions(snapshot),
                    gradingCompanyOptions: gradingCompanyOptions(snapshot),
                    gradeOptions: gradeOptions(snapshot)
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
                CollectionCardDetailView(
                    card: entry.card,
                    price: entry.row.price,
                    history: history,
                    unpricedReason: entry.unpricedReason,
                    artworkReason: entry.artworkReason,
                    logicalQuantity: entry.row.quantity,
                    isLogicalConflict: entry.isLogicalConflict,
                    instrumentKey: entry.row.priceStorageKey,
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
                MovementDetailsView(
                    card: entry.card,
                    price: entry.row.price,
                    history: history,
                    quantity: entry.row.quantity
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

    private var noSelection: some View {
        ContentUnavailableView(
            "No card selected",
            systemImage: "rectangle.stack",
            description: Text("Choose a card to see its details.")
        )
    }

    private func content(_ snapshot: Snapshot) -> some View {
        let artworkByKey = Dictionary(
            artworkOverrides.map { ($0.collectionKey, $0.filename) },
            uniquingKeysWith: { first, _ in first }
        )
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
                                    card: entry.card,
                                    userArtworkFilename: artworkByKey[entry.card.collectionKey]
                                        ?? entry.card.userArtworkFilename,
                                    quantity: entry.row.quantity,
                                    price: entry.row.price,
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
        .refreshable { await onRefresh() }
        .animation(.easeOut(duration: 0.2), value: filters)
        .animation(.easeOut(duration: 0.2), value: sort)
        .animation(.easeOut(duration: 0.2), value: searchQuery)
    }

    private func collectionSummary(_ snapshot: Snapshot) -> some View {
        let total = snapshot.entries.reduce(Money.zero) { total, entry in
            guard entry.row.price.currencyCode == "USD",
                  let unitPrice = entry.row.price.amount,
                  let money = Money(rounding: unitPrice) else {
                return total
            }
            return total + money * entry.row.quantity
        }

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shown value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(total.formatted())
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Shown collection value, \(total.formatted())")
            }
            Spacer(minLength: 12)
            Text("\(snapshot.entries.count) \(snapshot.entries.count == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            let isLogicalConflict: Bool

            var id: String { row.id }
        }

        let all: [CollectionRow]
        let entries: [Entry]
    }

    /// The expensive half of a collection render. Search and filter state are
    /// intentionally absent so typing remains a local operation over `all`.
    private struct CachedProjection {
        let all: [CollectionRow]
        let cardsByKey: [String: CollectedCard]
        let priceRecordsByCollectionKey: [String: PriceRecord]
        let localArtworkKeys: Set<String>
        let physicalRowCountsByKey: [String: Int]
    }

    private final class ProjectionCache {
        private var token: Int?
        private var cachedValue: CachedProjection?

        func value(
            for token: Int,
            build: () -> CachedProjection
        ) -> CachedProjection {
            if self.token == token, let cachedValue { return cachedValue }
            let value = build()
            self.token = token
            self.cachedValue = value
            return value
        }
    }

    @MainActor
    private func makeSnapshot() -> Snapshot {
        let cached = projectionCache.value(for: makeProjectionToken()) {
            makeCachedProjection()
        }

        let visible = CollectionQuery.apply(
            nameQuery: searchQuery,
            filters: filters,
            sort: sort,
            to: cached.all
        )

        return Snapshot(
            all: cached.all,
            entries: visible.compactMap { row -> Snapshot.Entry? in
                guard let card = cached.cardsByKey[row.id] else { return nil }
                let record = cached.priceRecordsByCollectionKey[row.id]
                return Snapshot.Entry(
                    row: row,
                    card: card,
                    unpricedReason: row.unitPrice == nil
                        ? PricingDiagnostics.unpricedReason(for: card, record: record)
                        : nil,
                    artworkReason: ArtworkDiagnostics.reason(
                        for: card,
                        hasLocalOverride: cached.localArtworkKeys.contains(card.collectionKey)
                    ),
                    isLogicalConflict: (cached.physicalRowCountsByKey[row.id] ?? 1) > 1
                )
            }
        )
    }

    /// Hashes persisted inputs rather than deriving the projection just to ask
    /// whether the projection changed. SwiftData has no cheap query revision;
    /// this fingerprint is still much less work than faulting every property,
    /// allocating lookup keys, grouping rows, and rebuilding every tile row.
    @MainActor
    private func makeProjectionToken() -> Int {
        CollectionProjectionToken.make(
            cards: cards,
            priceRecords: priceRecords,
            artworkOverrides: artworkOverrides
        )
    }

    @MainActor
    private func makeCachedProjection() -> CachedProjection {
        let recordsByKey = Dictionary(priceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let localArtworkKeys = Set(artworkOverrides.map(\.collectionKey))

        // One collection key can legitimately have more than one row, so what
        // is owned comes from the shared projection rather than from whichever
        // row this fetch happened to return first. See `LogicalCollection`.
        //
        // The closure overload, not the `ledger:` one. That form resolves each
        // position's instrument by asking the ledger, and the ledger answers
        // with two predicate fetches per candidate key — so projecting this way
        // cost several thousand fetches per render on a large collection, on
        // the main thread, for a field this view never reads. `body` re-runs on
        // every keystroke in the search field, which is what made it bite.
        //
        // Answered from the price records already in hand instead. This is the
        // same rule `PriceStore.record(for:in:)` uses to pick the record whose
        // price is displayed below, so the instrument a position is attributed
        // to and the number shown for it now come from one decision.
        let projection = LogicalCollection.project(cards: cards) { card in
            PriceStore.priceStorageKey(for: card, in: recordsByKey)
        }
        let cardsByKey = projection.byKey.mapValues(\.representative)
        let priceRecordsByCollectionKey: [String: PriceRecord] = Dictionary(
            uniqueKeysWithValues: projection.positions.compactMap { position in
                PriceStore.record(for: position.representative, in: recordsByKey)
                    .map { (position.collectionKey, $0) }
            }
        )

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
                price: priceRecordsByCollectionKey[position.collectionKey]?.display ?? .unknown,
                priceStorageKey: position.priceStorageKey,
                magicTreatmentIDsRaw: card.magicTreatmentIDsRaw,
                magicTreatmentQualifiers: card.magicTreatmentQualifiers,
                itemKind: card.itemKind,
                itemKindLabel: card.itemKindLabel,
                gradingCompany: card.gradingCompany,
                gradeValue: card.gradeRaw
            )
        }

        return CachedProjection(
            all: all,
            cardsByKey: cardsByKey,
            priceRecordsByCollectionKey: priceRecordsByCollectionKey,
            localArtworkKeys: localArtworkKeys,
            physicalRowCountsByKey: projection.byKey.mapValues(\.physicalRowCount)
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

    private func treatmentOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rowsForOptions(snapshot) {
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

}

private struct CollectionCardTile: View {
    let card: CollectedCard
    let userArtworkFilename: String?
    /// The projected quantity for the position, not `card.quantity`. The card
    /// is one physical row, and CloudKit can legitimately split a position
    /// across several of them; the badge and the detail view must agree about
    /// how many are owned.
    let quantity: Int
    let price: PriceDisplay
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.secondary.opacity(0.08)

                CollectionCardArtwork(
                    userArtworkFilename: userArtworkFilename,
                    thumbnailURL: card.lowImageURL,
                    fullSizeURL: card.highImageURL,
                    placeholderText: artworkReason?.title
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if quantity > 1 {
                    Text("×\(quantity)")
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

                    HStack(spacing: 4) {
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

                        ForEach(
                            Array(card.displayedMagicTreatmentEvidence.displayLabels.enumerated()),
                            id: \.offset
                        ) { item in
                            CollectionTreatmentBadge(label: item.element)
                        }
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

private struct CollectionTreatmentBadge: View {
    let label: String

    var body: some View {
        Label(label, systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.orange)
            .background(Color.orange.opacity(0.16), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
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

    /// The grid draws these at tile size, so the thumbnail is the correct
    /// request: preferring the full-size scan fetched megabytes per tile for no
    /// visible gain. The larger asset stays as the fallback, which is what keeps
    /// the printings described above off a permanent placeholder.
    private var primaryURL: URL? { thumbnailURL ?? fullSizeURL }

    private var fallbackURL: URL? {
        guard let fullSizeURL, fullSizeURL != primaryURL else { return nil }
        return fullSizeURL
    }

    var body: some View {
        if let image = CollectionArtworkStore.image(filename: userArtworkFilename) {
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
