import SwiftData
import SwiftUI

/// The scanner reduces friction according to certainty. The collection reduces
/// it according to intent: four chips and one sort menu answer nearly every
/// question a collector actually asks, and none of them touch the network.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]

    @Query private var priceRecords: [PriceRecord]

    @StateObject private var refresh = PriceRefreshController()

    @State private var searchText = ""
    /// What the grid is actually filtered by. Trails `searchText` by one short
    /// debounce so a large grid is not rebuilt on every keystroke.
    @State private var searchQuery = ""
    @State private var filters = CollectionFilters.none
    @State private var sort: CollectionSort = .setAndCardNumber
    @State private var activeSheet: ActiveSheet?
    @State private var hasCheckedForStalePrices = false
    @State private var pendingRemoval: RemovedCardSnapshot?
    @State private var removalUndoTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private enum ActiveSheet: String, Identifiable {
        case set, price, finish
        var id: String { rawValue }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        // Built once per render and threaded through. Filtering and sorting are
        // pure local work, but recomputing them separately for the header, the
        // grid and the refresh targets would do it four times for nothing.
        let snapshot = makeSnapshot()

        return NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Scan a card and it lands here.")
                    )
                } else {
                    content(snapshot)
                }
            }
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFocused = false
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .set:
                MultiSelectFilterSheet(title: "Sets", options: setOptions(snapshot), selection: $filters.setCodes)
            case .finish:
                MultiSelectFilterSheet(title: "Finish", options: finishOptions(snapshot), selection: $filters.variantIDs)
            case .price:
                PriceFilterSheet(selection: $filters.price)
            }
        }
        .task(id: cards.count) { await refreshStalePricesIfNeeded() }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            searchQuery = searchText
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
                header(snapshot)
                searchField
                filterBar(snapshot)

                if snapshot.entries.isEmpty {
                    noMatches
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(snapshot.entries) { entry in
                            NavigationLink {
                                CollectionCardDetailView(
                                    card: entry.card,
                                    price: entry.row.price,
                                    onRemoved: presentUndo(for:)
                                )
                            } label: {
                                CollectionCardTile(card: entry.card, price: entry.row.price)
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
        .refreshable { await refreshAllPrices() }
        .animation(.easeOut(duration: 0.2), value: filters)
        .animation(.easeOut(duration: 0.2), value: sort)
        .animation(.easeOut(duration: 0.2), value: searchQuery)
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
        removed.restore(in: modelContext)
        pendingRemoval = nil
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
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.pricedValue, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.title2.bold())
                Text("priced value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if isNarrowed {
                    Text("\(snapshot.visibleQuantity) of \(snapshot.totalQuantity)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if snapshot.unpricedCount > 0 {
                Text("\(snapshot.unpricedCount) card\(snapshot.unpricedCount == 1 ? "" : "s") unpriced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                freshnessLabel(snapshot)
                Spacer()
                refreshButton
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func freshnessLabel(_ snapshot: Snapshot) -> some View {
        switch refresh.status {
        case let .refreshing(completed, total):
            Text("Updating prices… \(completed)/\(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

        case let .finished(result):
            VStack(alignment: .leading, spacing: 1) {
                Label(
                    result.failed > 0
                        ? "Checked just now · \(result.failed) couldn't be reached"
                        : refreshSuccessText(result),
                    systemImage: result.failed > 0 ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(result.failed > 0 ? Color.orange : Color.secondary)

                if !result.checkedUnstampedProvider, let asOf = result.latestSourceUpdate {
                    Text("Market data current through \(asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .idle:
            Text(idleFreshnessText(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshSuccessText(_ result: PriceRefreshController.Summary) -> String {
        if result.changedPrices { return "Prices updated" }
        if result.checkedUnstampedProvider { return "Prices checked" }
        return result.foundNothingNewer
            ? "Checked just now · no newer market prices"
            : "Prices updated"
    }

    /// "Current as of" is a claim about the market data. "Checked" is a claim
    /// about this app. Providers that publish no timestamp only ever earn the
    /// second one.
    private func idleFreshnessText(_ snapshot: Snapshot) -> String {
        guard let asOf = snapshot.pricesAsOf else { return "No prices yet" }
        let formatted = Calendar.current.isDateInToday(asOf)
            ? asOf.formatted(date: .omitted, time: .shortened)
            : asOf.formatted(date: .abbreviated, time: .shortened)
        return snapshot.isSourceStamped
            ? "Prices current as of \(formatted)"
            : "Prices checked \(formatted)"
    }

    private var refreshButton: some View {
        Button {
            Task { await refreshAllPrices() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(isRefreshing)
        .accessibilityLabel("Refresh prices")
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All") { selectGame(nil) }
                    ForEach(CardGame.allCases) { game in
                        Button(game.label) { selectGame(game) }
                    }
                } label: {
                    FilterChipLabel(title: filters.game?.label ?? "Game", isActive: filters.game != nil)
                }

                FilterChip(
                    title: setChipTitle(snapshot),
                    isActive: !filters.setCodes.isEmpty
                ) { activeSheet = .set }

                FilterChip(
                    title: filters.price?.label ?? "Price",
                    isActive: filters.price != nil
                ) { activeSheet = .price }

                FilterChip(
                    title: finishChipTitle,
                    isActive: !filters.variantIDs.isEmpty
                ) { activeSheet = .finish }

                Divider().frame(height: 20)

                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CollectionSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    FilterChipLabel(title: "Sort", isActive: false, symbol: "arrow.up.arrow.down")
                }

                if filters.isActive {
                    Button("Clear") { filters = .none }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func setChipTitle(_ snapshot: Snapshot) -> String {
        switch filters.setCodes.count {
        case 0: return "Set"
        case 1:
            guard let selected = filters.setCodes.first else { return "Set" }
            return snapshot.all.first(where: { $0.setFilterID == selected })?.setCode ?? "Set"
        default: return "\(filters.setCodes.count) sets"
        }
    }

    /// Set and finish selections are scoped by game. Carrying them across a game
    /// change can leave an apparently active filter with no selectable option in
    /// the new game, producing an unexplained empty collection.
    private func selectGame(_ game: CardGame?) {
        guard filters.game != game else { return }
        filters.game = game
        filters.setCodes.removeAll()
        filters.variantIDs.removeAll()
    }

    private var finishChipTitle: String {
        switch filters.variantIDs.count {
        case 0: return "Finish"
        case 1:
            let id = filters.variantIDs.first ?? ""
            return PhysicalVariant.resolving(id).label
        default: return "\(filters.variantIDs.count) finishes"
        }
    }

    // MARK: - Data

    /// Everything one render of this screen needs, derived once.
    struct Snapshot {
        struct Entry: Identifiable {
            let row: CollectionRow
            let card: CollectedCard

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
        let cardsByKey = Dictionary(cards.map { ($0.collectionKey, $0) }, uniquingKeysWith: { first, _ in first })

        let all = cards.map { card in
            CollectionRow(
                id: card.collectionKey,
                game: card.cardGame,
                name: card.name,
                setCode: card.setCode,
                setName: card.setName,
                setReleaseOrder: card.setReleaseOrder,
                cardNumber: card.cardNumber,
                variantID: card.variantID,
                variantLabel: card.variantLabel,
                quantity: card.quantity,
                dateAdded: card.dateAdded,
                price: recordsByKey[card.priceKey]?.display ?? .unknown
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
        var visibleQuantity = 0
        for row in visible {
            visibleQuantity += row.quantity
            if let price = row.unitPrice {
                pricedValue += price * Double(row.quantity)
            } else {
                unpriced += row.quantity
            }
        }

        // Freshness belongs to the collection currently being summarized, not to
        // unrelated hidden records. A mixed provider view cannot make a universal
        // provider-side freshness claim because Scryfall publishes no such stamp;
        // in that case report the oldest successful check instead.
        let relevantRecords = visible.compactMap { row -> PriceRecord? in
            guard let card = cardsByKey[row.id] else { return nil }
            return recordsByKey[card.priceKey]
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
                return Snapshot.Entry(row: row, card: card)
            },
            totalQuantity: all.reduce(0) { $0 + $1.quantity },
            visibleQuantity: visibleQuantity,
            pricedValue: pricedValue,
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
    private func priceTargets(_ snapshot: Snapshot) -> [PriceTarget] {
        var seen = Set<String>()
        var result: [PriceTarget] = []

        for row in snapshot.visible + snapshot.all {
            guard let card = snapshot.cardsByKey[row.id] else { continue }
            guard seen.insert(card.priceKey).inserted else { continue }
            result.append(
                PriceTarget(
                    game: card.cardGame,
                    printingID: card.providerID,
                    setCode: card.setCode,
                    variantID: card.variantID,
                    lastCheckedAt: snapshot.recordsByKey[card.priceKey]?.lastCheckedAt
                )
            )
        }
        return result
    }

    @MainActor
    private func refreshAllPrices() async {
        await runRefresh(priceTargets(makeSnapshot()))
    }

    /// Quiet background top-up. Existing prices stay visible the whole time —
    /// there is no blank grid and no blocking spinner.
    @MainActor
    private func refreshStalePricesIfNeeded() async {
        guard !hasCheckedForStalePrices, !cards.isEmpty else { return }
        hasCheckedForStalePrices = true

        let stale = PriceRefreshController.staleTargets(from: priceTargets(makeSnapshot()))
        guard !stale.isEmpty else { return }
        await runRefresh(stale)
    }

    @MainActor
    private func runRefresh(_ targets: [PriceTarget]) async {
        await refresh.refresh(targets, store: PriceStore(context: modelContext))
        // Let the outcome stand long enough to be read, then collapse back to the
        // compact freshness line.
        try? await Task.sleep(for: .seconds(4))
        refresh.dismissSummary()
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

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                CollectionCardArtwork(
                    thumbnailURL: card.lowImageURL,
                    fullSizeURL: card.highImageURL
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if card.quantity > 1 {
                    Text("×\(card.quantity)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.78), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }

                // A reverse and a normal copy of one printing are different rows,
                // so the tile has to say which one it is or the grid looks
                // duplicated.
                if let variant = card.variant {
                    Text(variant.label)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.72), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }

            PriceLabel(price: price, style: .compact)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.name), \(card.variant?.label ?? "unknown finish"), quantity \(card.quantity)")
    }
}

/// Prefer the smaller portfolio image, but never turn a thumbnail-provider
/// failure into a permanently blank card. The detail screen already proves the
/// full-size URL is usable, so it is the natural fallback for this surface.
private struct CollectionCardArtwork: View {
    let thumbnailURL: URL?
    let fullSizeURL: URL?

    private var primaryURL: URL? { thumbnailURL ?? fullSizeURL }

    private var fallbackURL: URL? {
        guard let fullSizeURL, fullSizeURL != primaryURL else { return nil }
        return fullSizeURL
    }

    var body: some View {
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
            .overlay { Image(systemName: "photo") }
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
                .font(style == .compact ? .caption.weight(.medium) : .subheadline)
                .foregroundStyle(.secondary)

        case .unknown:
            Text(style == .compact ? "—" : "Not checked yet")
                .font(style == .compact ? .caption.weight(.medium) : .subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private func amount(_ shade: HierarchicalShapeStyle) -> some View {
        Text(price.amount ?? 0, format: .currency(code: "USD"))
            .font(style == .compact ? .caption.weight(.semibold) : .headline)
            .monospacedDigit()
            .foregroundStyle(shade)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
