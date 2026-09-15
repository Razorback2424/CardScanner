import Combine
import ImageIO
import OSLog
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class BrowseViewModel: ObservableObject {
    struct Lane {
        var cards: [CatalogCardSummary] = []
        var cursor: String?
        var isLoading = false
        var error: String?
    }

    @Published var searchText = "" { didSet { scheduleSearch() } }
    @Published var selectedGame: CardGame? { didSet { scheduleSearch() } }
    @Published var selectedSets: Set<CatalogSetID> = [] { didSet { scheduleSearch() } }
    @Published private(set) var sets: [CardGame: [CatalogSet]] = [:]
    @Published private(set) var setErrors: [CardGame: String] = [:]
    @Published private(set) var lanes: [CardGame: Lane] = [:]
    @Published private(set) var searchResults: [CatalogSearchResult] = []

    let catalog: any BrowseCatalogProviding
    let sealedModel: SealedBrowseModel
    private var searchTask: Task<Void, Never>?
    private var searchResultsRefreshTask: Task<Void, Never>?
    private var generation = UUID()
    private var sealedModelCancellable: AnyCancellable? = nil

    init(
        catalog: any BrowseCatalogProviding = BrowseCatalog(),
        sealedModel: SealedBrowseModel? = nil
    ) {
        self.catalog = catalog
        let sealedModel = sealedModel ?? SealedBrowseModel(transport: JustTCGTransport.shared)
        self.sealedModel = sealedModel
        self.sealedModelCancellable = sealedModel.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            self.scheduleSearchResultsRefresh()
        }
        recomputeSearchResults()
    }

    var normalizedQuery: String { CardNameSearch.normalize(searchText) }
    var isSearching: Bool { !normalizedQuery.isEmpty }

    var searchGames: [CardGame] {
        selectedGame.map { [$0] } ?? CardGame.allCases
    }

    /// A single deterministic stream assembled from the independently paged
    /// card and sealed lanes. It is refreshed when either lane family changes,
    /// so a render does not sort the same provider pages more than once.
    private func recomputeSearchResults() {
        let cardResults = searchGames.flatMap { game in
            (lanes[game]?.cards ?? []).map(CatalogSearchResult.card)
        }
        let sealedResults = searchGames.flatMap { game in
            (sealedModel.searchLanes[game]?.products ?? []).map {
                CatalogSearchResult.sealed(game: game, product: $0)
            }
        }
        let updated = CatalogSearchResultRanking.sorted(
            cardResults + sealedResults,
            query: normalizedQuery
        )
        if searchResults != updated {
            searchResults = updated
        }
    }

    private func scheduleSearchResultsRefresh() {
        searchResultsRefreshTask?.cancel()
        searchResultsRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.recomputeSearchResults()
        }
    }

    var searchState: CatalogSearchState {
        guard normalizedQuery.count >= 2 else { return .idle }
        let games = searchGames
        var statuses: [CatalogSearchLaneStatus] = games.map { game in
            guard let lane = lanes[game] else {
                return CatalogSearchLaneStatus(isLoading: true)
            }
            return CatalogSearchLaneStatus(
                isLoading: lane.isLoading,
                error: lane.error
            )
        }

        let sealedWasSkipped = !sealedModel.isConfigured
            && games.contains { !sealedLaneIsRequested(for: $0) }
        for game in games where sealedLaneIsRequested(for: game) {
            if let lane = sealedModel.searchLanes[game] {
                statuses.append(
                    CatalogSearchLaneStatus(
                        isLoading: lane.isLoading,
                        error: lane.error
                    )
                )
            } else {
                statuses.append(CatalogSearchLaneStatus(isLoading: true))
            }
        }

        return CatalogSearchState.reduce(
            resultCount: searchResults.count,
            lanes: statuses,
            sealedWasSkippedForMissingCredentials: sealedWasSkipped
        )
    }

    var hasSearchPagination: Bool {
        guard normalizedQuery.count >= 2 else { return false }
        return searchGames.contains { game in
            if let lane = lanes[game], lane.cursor != nil, lane.error == nil {
                return true
            }
            if sealedLaneIsRequested(for: game),
               let lane = sealedModel.searchLanes[game],
               lane.nextOffset != nil,
               lane.error == nil {
                return true
            }
            return false
        }
    }

    var searchPaginationKey: String {
        searchGames.map { game in
            let card = lanes[game]?.cursor ?? "-"
            let sealed = sealedModel.searchLanes[game]?.nextOffset.map(String.init) ?? "-"
            return [game.rawValue, card, sealed].joined(separator: ":")
        }.joined(separator: "|")
    }

    func loadSets() async {
        for game in CardGame.allCases where sets[game] == nil {
            do {
                sets[game] = try await catalog.sets(for: game)
                setErrors[game] = nil
            } catch {
                setErrors[game] = error.localizedDescription
            }
        }
    }

    func retrySets(_ game: CardGame) async {
        setErrors[game] = nil
        do { sets[game] = try await catalog.sets(for: game) }
        catch { setErrors[game] = error.localizedDescription }
    }

    func loadMore(_ game: CardGame) async {
        let requestedQuery = normalizedQuery
        let requestedGeneration = generation
        let requestedSetIDs = effectiveSetIDs(for: game)
        guard requestedQuery.count >= 2,
              selectedGame == nil || selectedGame == game,
              var lane = lanes[game],
              let cursor = lane.cursor,
              !lane.isLoading else { return }
        lane.isLoading = true
        lanes[game] = lane
        defer {
            if generation == requestedGeneration,
               var currentLane = lanes[game] {
                currentLane.isLoading = false
                lanes[game] = currentLane
            }
        }
        do {
            let page = try await catalog.searchCards(
                named: requestedQuery,
                game: game,
                setIDs: requestedSetIDs,
                cursor: cursor
            )
            guard generation == requestedGeneration,
                  CardNameSearch.normalize(searchText) == requestedQuery,
                  var currentLane = lanes[game],
                  currentLane.cursor == cursor else { return }
            currentLane.cards = deduplicated(currentLane.cards + page.items)
            currentLane.cursor = page.nextCursor
            currentLane.error = nil
            lanes[game] = currentLane
            recomputeSearchResults()
        } catch {
            guard generation == requestedGeneration,
                  CardNameSearch.normalize(searchText) == requestedQuery,
                  var currentLane = lanes[game],
                  currentLane.cursor == cursor else { return }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            currentLane.error = error.localizedDescription
            lanes[game] = currentLane
            return
        }
    }

    /// Loads the next page for every eligible card and sealed lane. Each lane
    /// remains independent, so a card and sealed page for the same game can be
    /// in flight together.
    func loadMoreSearchResults() async {
        let query = normalizedQuery
        guard query.count >= 2 else { return }
        let games = searchGames

        await withTaskGroup(of: Void.self) { group in
            for game in games {
                if let lane = lanes[game],
                   lane.cursor != nil,
                   !lane.isLoading,
                   lane.error == nil {
                    group.addTask { [weak self] in
                        await self?.loadMore(game)
                    }
                }

                if sealedLaneIsRequested(for: game),
                   let lane = sealedModel.searchLanes[game],
                   lane.nextOffset != nil,
                   !lane.isLoading,
                   lane.error == nil {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.sealedModel.loadMoreSearch(game: game, query: query)
                    }
                }
            }
            await group.waitForAll()
        }
        recomputeSearchResults()
    }

    func retrySearch() {
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        generation = UUID()
        let token = generation
        let query = normalizedQuery
        guard !query.isEmpty else {
            lanes = [:]
            sealedModel.clearSearch()
            recomputeSearchResults()
            return
        }
        guard query.count >= 2 else {
            lanes = [:]
            sealedModel.clearSearch()
            recomputeSearchResults()
            return
        }
        // A new query, game, or card-set filter invalidates both result
        // families immediately. The debounce then repopulates only the lanes
        // for the current selection.
        lanes = [:]
        sealedModel.clearSearch()
        recomputeSearchResults()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            await self.runSearch(query: query, token: token)
        }
    }

    private func runSearch(query: String, token: UUID) async {
        let games = searchGames
        for game in games { lanes[game] = Lane(isLoading: true) }
        for game in CardGame.allCases where !games.contains(game) { lanes[game] = nil }
        recomputeSearchResults()

        async let cardSearch: Void = searchCardLanes(games: games, query: query, token: token)
        async let sealedSearch: Void = sealedModel.search(query: query, games: games)
        _ = await (cardSearch, sealedSearch)
    }

    private func sealedLaneIsRequested(for game: CardGame) -> Bool {
        sealedModel.isConfigured || !(sealedModel.searchLanes[game]?.products.isEmpty ?? true)
    }

    private func searchCardLanes(games: [CardGame], query: String, token: UUID) async {
        await withTaskGroup(of: (CardGame, Result<CatalogPage<CatalogCardSummary>, Error>).self) { group in
            for game in games {
                let catalog = catalog
                let setIDs = effectiveSetIDs(for: game)
                group.addTask {
                    do {
                        return (
                            game,
                            .success(
                                try await catalog.searchCards(
                                    named: query,
                                    game: game,
                                    setIDs: setIDs,
                                    cursor: nil
                                )
                            )
                        )
                    } catch {
                        return (game, .failure(error))
                    }
                }
            }
            for await (game, result) in group {
                guard generation == token else { continue }
                switch result {
                case let .success(page):
                    lanes[game] = Lane(cards: deduplicated(page.items), cursor: page.nextCursor)
                case let .failure(error):
                    lanes[game] = Lane(error: error.localizedDescription)
                }
                recomputeSearchResults()
            }
        }
    }

    private func effectiveSetIDs(for game: CardGame) -> Set<CatalogSetID> {
        Set(selectedSets.filter { $0.game == game })
    }

    private func deduplicated(_ cards: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return cards.filter { seen.insert($0.id).inserted }
    }
}

struct BrowseView: View {
    private static let pokemonReleaseOrderBackfillVersionKey =
        "browse.pokemonReleaseOrderBackfillVersion"
    private static let pokemonReleaseOrderBackfillVersion = 1

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    let catalog: any BrowseCatalogProviding
    @StateObject private var model: BrowseViewModel
    @State private var showsSetFilter = false
    @State private var isShowingSettings = false
    @FocusState private var searchFocused: Bool

    init(catalog: any BrowseCatalogProviding = BrowseCatalog()) {
        self.catalog = catalog
        _model = StateObject(wrappedValue: BrowseViewModel(catalog: catalog))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                searchField
                if model.isSearching {
                    searchBody
                } else {
                    recentlyReleasedRail
                    gameChooser
                }
            }
            .padding(16)
            .contentWidthLimit(.standard)
            .safeAreaPadding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Settings")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .task {
            await model.loadSets()
            backfillPokemonReleaseOrder()
        }
        .sheet(isPresented: $showsSetFilter) {
            CatalogSetFilterSheet(
                sets: CardGame.allCases.flatMap { model.sets[$0] ?? [] },
                selectedGame: model.selectedGame,
                selection: $model.selectedSets
            )
        }
    }

    private func backfillPokemonReleaseOrder() {
        guard UserDefaults.standard.integer(
            forKey: Self.pokemonReleaseOrderBackfillVersionKey
        ) < Self.pokemonReleaseOrderBackfillVersion else { return }
        guard let sets = model.sets[.pokemon], !sets.isEmpty else { return }

        // Resolve the longest set prefix without scanning every catalog set for
        // each owned row. Provider card ids are set-id/card-id, so walking the
        // candidate prefixes from longest to shortest preserves the old
        // longest-prefix rule while keeping the lookup bounded by the id's
        // number of components.
        let setByProviderID = sets.reduce(into: [String: CatalogSet]()) { result, set in
            result[set.providerID] = result[set.providerID] ?? set
        }

        func set(for providerID: String) -> CatalogSet? {
            let components = providerID.split(separator: "-")
            guard components.count > 1 else { return nil }
            for end in stride(from: components.count - 1, through: 1, by: -1) {
                let prefix = components[..<end].joined(separator: "-")
                if let set = setByProviderID[prefix] { return set }
            }
            return nil
        }

        do {
            let pokemonRawValue = CardGame.pokemon.rawValue
            let ownedCards = try modelContext.fetch(
                FetchDescriptor<CollectedCard>(
                    predicate: #Predicate { $0.game == pokemonRawValue }
                )
            )
            var changed = false
            for card in ownedCards {
                let providerID = card.catalogProviderID ?? card.providerID
                guard let set = set(for: providerID) else { continue }

                // Repair rows tagged with a print run their set never had. The
                // e-card sets were split into 1st Edition and Unlimited runs that
                // were never printed, and a row still carrying one would stop
                // counting toward its set and keep pricing under a storage id that
                // names an edition the vendor has no listing for.
                if card.pokemonPrintRunRaw != nil,
                   !PokemonMasterSetDefinition.hasSeparatePrintRuns(
                        setProviderID: set.providerID
                   ) {
                    card.pokemonPrintRunRaw = nil
                    changed = true
                }

                if card.setReleaseOrder != set.sortRank {
                    card.setReleaseOrder = set.sortRank
                    changed = true
                }
            }
            if changed { try modelContext.save() }
            UserDefaults.standard.set(
                Self.pokemonReleaseOrderBackfillVersion,
                forKey: Self.pokemonReleaseOrderBackfillVersionKey
            )
        } catch {
            // Leave the watermark untouched so a transient store failure can
            // retry on the next Browse appearance.
        }
    }

    private var searchField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search the catalog", text: $model.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                if !model.searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { model.searchText = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))

            if model.isSearching {
                HStack {
                    Menu {
                        Button("All Games") { model.selectedGame = nil }
                        ForEach(CardGame.allCases) { game in
                            Button(game.label) { model.selectedGame = game }
                        }
                    } label: {
                        Label(model.selectedGame?.label ?? "All Games", systemImage: "gamecontroller")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showsSetFilter = true
                    } label: {
                        Label(
                            activeSetCount == 0 ? "All Sets" : "\(activeSetCount) Sets",
                            systemImage: "square.stack.3d.up"
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Filters card results only")
                    Spacer()
                }
                .font(.subheadline)
            }
        }
    }

    private var activeSetCount: Int {
        guard let game = model.selectedGame else { return model.selectedSets.count }
        return model.selectedSets.filter { $0.game == game }.count
    }

    private var isCatalogLoadedForRail: Bool {
        CardGame.allCases.allSatisfy { model.sets[$0] != nil }
    }

    private var releaseRail: CatalogReleaseRail {
        CatalogSetOrdering.releaseRail(from: model.sets)
    }

    private var ownership: CatalogOwnershipIndex {
        projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
    }

    @ViewBuilder
    private var recentlyReleasedRail: some View {
        if isCatalogLoadedForRail, !releaseRail.sets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(releaseRail.title)
                    .font(.title2.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(releaseRail.sets) { set in
                            NavigationLink {
                                CatalogSetCardsView(set: set, catalog: model.catalog)
                            } label: {
                                CatalogSetTile(
                                    set: set,
                                    completion: ownership.progress(for: set),
                                    layout: .rail,
                                    showsNewBadge: releaseRail.showsNewBadges
                                )
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                min(max(width * 0.72, 220), 300)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder private var gameChooser: some View {
        let rows = projectionStore.snapshot?.rows ?? []
        Text("Browse by game")
            .font(.headline)
        ForEach(CardGame.allCases) { game in
            if let sets = model.sets[game] {
                let summary = CatalogGameSummary(game: game, sets: sets, rows: rows)
                NavigationLink {
                    CatalogGameBrowseView(
                        game: game,
                        sets: sets,
                        catalog: model.catalog,
                        sealedModel: model.sealedModel,
                        onOpenSettings: { isShowingSettings = true }
                    )
                } label: {
                    CatalogGameRow(summary: summary)
                }
                .buttonStyle(.plain)
            } else if let error = model.setErrors[game] {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load \(game.label) sets").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.retrySets(game) } }
                }
                .padding(16)
            } else {
                HStack { ProgressView(); Text("Loading \(game.label) sets…") }
                    .frame(minHeight: 76)
            }
        }
    }

    private struct CatalogGameArtwork: Identifiable {
        let slot: Int
        let url: URL?
        let fallbacks: [URL]
        let localAssetName: String?
        let localFallbackAssetNames: [String]
        let placeholderText: String

        var id: Int { slot }
    }

    private struct CatalogGameRow: View {
        let summary: CatalogGameSummary

        var body: some View {
            HStack(spacing: 14) {
                CatalogGameFan(
                    game: summary.game,
                    ownedRows: summary.recentArtworkRows,
                    fallbackSets: summary.recentSetArtwork
                )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.game.label)
                        .font(.headline)
                    Text(summary.subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 86)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private struct CatalogGameFan: View {
        let game: CardGame
        let ownedRows: [CollectionRow]
        let fallbackSets: [CatalogSet]
        private static let horizontalOffsets: [CGFloat] = [2, 24, 44]

        private var artworks: [CatalogGameArtwork] {
            var result = ownedRows.prefix(3).enumerated().map { index, row in
                let artwork = CatalogCardArtworkSource(
                    game: row.game,
                    setCode: row.setCode,
                    collectorNumber: row.cardNumber,
                    thumbnailURL: row.lowImageURL,
                    imageURL: row.highImageURL,
                    prefersFullSize: false
                )
                return CatalogGameArtwork(
                    slot: index,
                    url: artwork.primaryURL,
                    fallbacks: artwork.fallbacks,
                    localAssetName: nil,
                    localFallbackAssetNames: [],
                    placeholderText: row.name
                )
            }

            for set in fallbackSets where result.count < 3 {
                let artwork = PokemonArtworkFallbacks.setSource(for: set, kind: .logo)
                result.append(
                    CatalogGameArtwork(
                        slot: result.count,
                        url: artwork.primaryURL,
                        fallbacks: artwork.fallbacks,
                        localAssetName: artwork.localAssetName,
                        localFallbackAssetNames: artwork.localFallbackAssetNames,
                        placeholderText: set.code
                    )
                )
            }

            while result.count < 3 {
                result.append(
                    CatalogGameArtwork(
                        slot: result.count,
                        url: nil,
                        fallbacks: [],
                        localAssetName: nil,
                        localFallbackAssetNames: [],
                        placeholderText: game.label
                    )
                )
            }
            return result
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                ForEach(artworks) { artwork in
                    let index = artwork.slot
                    CatalogCachedImage(
                        url: artwork.url,
                        fallbacks: artwork.fallbacks,
                        targetPixelSize: 160,
                        placeholderSymbol: "rectangle.portrait",
                        placeholderText: artwork.placeholderText,
                        localAssetName: artwork.localAssetName,
                        localFallbackAssetNames: artwork.localFallbackAssetNames
                    )
                    .frame(width: 38, height: 52)
                    .rotationEffect(.degrees(Double(index - 1) * 7))
                    .offset(
                        x: Self.horizontalOffsets[index],
                        y: index == 1 ? 3 : 6
                    )
                }
            }
            .frame(width: 96, height: 62)
        }
    }

    @ViewBuilder private var searchBody: some View {
        if model.normalizedQuery.count < 2 {
            ContentUnavailableView(
                "Keep typing",
                systemImage: "text.cursor",
                description: Text("Enter at least two characters.")
            )
        } else {
            switch model.searchState {
            case let .results(hasFailures):
                if hasFailures {
                    searchPartialFailureBanner
                }
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.searchResults) { result in
                        NavigationLink {
                            searchDestination(for: result)
                        } label: {
                            CatalogSearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.hasSearchPagination {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .task(id: model.searchPaginationKey) {
                                await model.loadMoreSearchResults()
                            }
                    }
                }
            case .loading:
                HStack {
                    ProgressView()
                    Text("Searching…")
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .idle:
                EmptyView()
            case .failed:
                ContentUnavailableView(
                    "Search failed",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Some catalog providers could not be reached.")
                )
                Button("Retry") { model.retrySearch() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            case let .empty(needsSealedSetup):
                ContentUnavailableView(
                    "No catalog results",
                    systemImage: "magnifyingglass",
                    description: Text("Try another card or product name.")
                )
                if needsSealedSetup {
                    Button("Set up sealed browsing", systemImage: "key") {
                        isShowingSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var searchPartialFailureBanner: some View {
        HStack(spacing: 10) {
            Label("Some results could not load", systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            Spacer(minLength: 8)
            Button("Retry") { model.retrySearch() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func searchDestination(for result: CatalogSearchResult) -> some View {
        switch result {
        case let .card(summary):
            CatalogCardDetailView(summary: summary, catalog: model.catalog)
        case let .sealed(game, product):
            SealedProductDetailView(game: game, product: product)
        }
    }
}

private struct CatalogSearchResultRow: View {
    let result: CatalogSearchResult

    private var cardArtwork: CatalogCardArtworkSource? {
        switch result {
        case let .card(summary):
            return CatalogCardArtworkSource(
                game: summary.game,
                setCode: summary.setCode,
                collectorNumber: summary.collectorNumber,
                thumbnailURL: summary.thumbnailURL,
                imageURL: summary.imageURL,
                prefersFullSize: false
            )
        case .sealed:
            return nil
        }
    }

    private var imageURL: URL? {
        switch result {
        case .card:
            return cardArtwork?.primaryURL
        case let .sealed(_, product):
            return product.imageURL
        }
    }

    private var imageFallbacks: [URL] { cardArtwork?.fallbacks ?? [] }

    private var secondaryText: String {
        switch result {
        case let .card(summary):
            return "\(summary.setName) · \(summary.setCode) \(summary.collectorNumber)"
        case let .sealed(_, product):
            return product.setName ?? "Vendor catalog"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CatalogCachedImage(
                url: imageURL,
                fallbacks: imageFallbacks,
                targetPixelSize: 256,
                placeholderSymbol: result.kind == .card
                    ? "rectangle.portrait"
                    : "shippingbox.fill"
            )
            .frame(width: 62, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CatalogSearchBadge(text: result.kind == .card ? "Card" : "Sealed")
                    CatalogSearchBadge(text: result.game.label)
                }

                Text(result.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(result.name), \(result.kind == .card ? "Card" : "Sealed"), \(result.game.label), \(secondaryText)"
        )
    }
}

private struct CatalogSearchBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
    }
}

enum CatalogSetOrdering {
    static let newReleaseWindow: TimeInterval = 45 * 86_400
    static let minimumRailCardCount = 10
    static let releaseRailLimit = 3
    static let railPerGameFallbackLimit = 2

    static func newestFirst(_ sets: [CatalogSet]) -> [CatalogSet] {
        sets.sorted {
            if $0.releaseOrder != $1.releaseOrder {
                return $0.releaseOrder > $1.releaseOrder
            }
            return $0.id < $1.id
        }
    }

    static func oldestFirst(_ sets: [CatalogSet]) -> [CatalogSet] {
        sets.sorted {
            if $0.releaseOrder != $1.releaseOrder {
                return $0.releaseOrder < $1.releaseOrder
            }
            return $0.id < $1.id
        }
    }

    static func ordered(
        _ sets: [CatalogSet],
        by sort: CatalogSetListSort,
        ownership: CatalogOwnershipIndex
    ) -> [CatalogSet] {
        switch sort {
        case .newestFirst:
            return newestFirst(sets)
        case .oldestFirst:
            return oldestFirst(sets)
        case .nameAToZ:
            return sets.sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.id < $1.id
            }
        case .mostComplete:
            return sets
                .map { (set: $0, fraction: ownership.progress(for: $0).fraction ?? -1) }
                .sorted {
                    if $0.fraction != $1.fraction { return $0.fraction > $1.fraction }
                    return isNewer($0.set, than: $1.set)
                }
                .map(\.set)
        }
    }

    private static func isNewer(_ lhs: CatalogSet, than rhs: CatalogSet) -> Bool {
        if lhs.releaseOrder != rhs.releaseOrder {
            return lhs.releaseOrder > rhs.releaseOrder
        }
        return lhs.id < rhs.id
    }

    static func releaseRail(
        from setsByGame: [CardGame: [CatalogSet]],
        now: Date = .now
    ) -> CatalogReleaseRail {
        let eligibleByGame = Dictionary(uniqueKeysWithValues: CardGame.allCases.map { game in
            (
                game,
                (setsByGame[game] ?? []).filter { set in
                    guard let cardCount = set.cardCount else { return true }
                    return cardCount >= minimumRailCardCount
                }
            )
        })
        let eligible = eligibleByGame.values.flatMap { $0 }
        let datedRecent = eligible
            .filter { isNew($0, now: now, window: newReleaseWindow) }
            .sorted {
                guard let left = $0.releaseDate, let right = $1.releaseDate else {
                    return $0.id < $1.id
                }
                if left != right { return left > right }
                return $0.id < $1.id
            }

        if !datedRecent.isEmpty {
            return CatalogReleaseRail(
                title: "Just released",
                sets: Array(datedRecent.prefix(releaseRailLimit)),
                showsNewBadges: true
            )
        }

        let fallback = CardGame.allCases.flatMap { game in
            newestFirst(eligibleByGame[game] ?? []).prefix(railPerGameFallbackLimit)
        }
        return CatalogReleaseRail(
            title: "Recent sets",
            sets: Array(newestFirst(fallback).prefix(releaseRailLimit)),
            showsNewBadges: false
        )
    }

    static func isNew(
        _ set: CatalogSet,
        now: Date = .now,
        window: TimeInterval = newReleaseWindow
    ) -> Bool {
        guard let releaseDate = set.releaseDate,
              releaseDate <= now else { return false }
        return now.timeIntervalSince(releaseDate) <= window
    }
}

private enum CatalogGameContentKind: String, CaseIterable, Identifiable {
    case cards = "Cards"
    case sealed = "Sealed"

    var id: String { rawValue }
}

enum CatalogGameCardSearchPolicy {
    /// `normalizedQuery` is expected to have already been normalized by the
    /// owning view, so this remains a cheap gate on the task's hot path.
    static func shouldRequest(isActive: Bool, normalizedQuery: String) -> Bool {
        isActive && normalizedQuery.count >= 2
    }
}

private struct CatalogGameBrowseView: View {
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    @ObservedObject var sealedModel: SealedBrowseModel
    let onOpenSettings: () -> Void

    @State private var contentKind: CatalogGameContentKind = .cards
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Catalog content", selection: $contentKind) {
                ForEach(CatalogGameContentKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ZStack {
                // Keep this subtree alive while Sealed is visible. Its loaded
                // pages and pagination cursor are local state and must survive
                // the segment switch.
                CatalogGameCardsView(
                    game: game,
                    sets: sets,
                    catalog: catalog,
                    isActive: contentKind == .cards,
                    search: $search
                )
                .opacity(contentKind == .cards ? 1 : 0)
                .allowsHitTesting(contentKind == .cards)
                .accessibilityHidden(contentKind != .cards)

                if contentKind == .sealed {
                    SealedSetDirectoryContent(
                        game: game,
                        model: sealedModel,
                        searchText: search,
                        onOpenSettings: onOpenSettings
                    )
                }
            }
        }
        .navigationTitle(game.label)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $search,
            prompt: "Search \(game.label) \(contentKind == .cards ? "cards" : "sets")"
        )
        .toolbar {
            if contentKind == .cards {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CatalogSetListView(game: game, sets: sets, catalog: catalog)
                    } label: {
                        Label("Sets", systemImage: "square.stack.3d.up")
                    }
                    .accessibilityLabel("Browse \(game.label) sets")
                }
            }
        }
        .onChange(of: contentKind) { _, _ in
            // Card queries are not vendor set filters. A segment change starts
            // with a clean, shared search field in either direction.
            search = ""
        }
    }
}

private struct CatalogGameCardsView: View {
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    let isActive: Bool
    @Binding var search: String

    @State private var cards: [CatalogCardSummary] = []
    @State private var nextSetIndex = 0
    @State private var activeSetIndex: Int?
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchCards: [CatalogCardSummary] = []
    @State private var searchCursor: String?
    @State private var searchIsLoading = false
    @State private var searchError: String?
    @State private var searchRevision = 0
    @State private var searchRequestKey: String?
    @State private var cardGroups: [CatalogCardDisplayGroup] = []
    @State private var searchCardGroups: [CatalogCardDisplayGroup] = []

    private var orderedSets: [CatalogSet] {
        CatalogSetOrdering.newestFirst(sets)
    }

    private var normalizedSearch: String {
        CardNameSearch.normalize(search)
    }

    private var hasSearchText: Bool { !normalizedSearch.isEmpty }
    private var isSearchQuery: Bool { normalizedSearch.count >= 2 }
    private var hasMoreSets: Bool {
        activeSetIndex != nil || nextSetIndex < orderedSets.count
    }

    var body: some View {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        return ScrollView {
            if hasSearchText {
                searchContent(owned: owned)
            } else {
                defaultContent(owned: owned)
            }
        }
        .task {
            await loadDefaultMore()
        }
        .task(id: "\(isActive)-\(normalizedSearch)-\(searchRevision)") {
            guard CatalogGameCardSearchPolicy.shouldRequest(
                isActive: isActive,
                normalizedQuery: normalizedSearch
            ) else {
                searchCards = []
                searchCursor = nil
                searchError = nil
                searchIsLoading = false
                searchRequestKey = nil
                return
            }
            let requestKey = "\(normalizedSearch)-\(searchRevision)"
            searchRequestKey = requestKey
            searchCards = []
            searchCursor = nil
            searchError = nil
            searchIsLoading = true
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await loadSearch(query: normalizedSearch, requestKey: requestKey)
        }
        .onChange(of: cards) { _, newCards in
            cardGroups = CatalogCardDisplayGrouping.groups(for: newCards)
        }
        .onChange(of: searchCards) { _, newSearchCards in
            searchCardGroups = CatalogCardDisplayGrouping.groups(for: newSearchCards)
        }
        .safeAreaPadding(.bottom, 24)
    }

    @ViewBuilder
    private func defaultContent(owned: CatalogOwnershipIndex) -> some View {
        if cards.isEmpty && isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(game.label) cards…")
                    .font(.headline)
            }
            .padding(.horizontal, 32)
            .padding(.top, 80)
        } else if cards.isEmpty, let error {
            ContentUnavailableView(
                "Couldn't load \(game.label) cards",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
            Button("Retry") { Task { await loadDefaultMore() } }
                .buttonStyle(.borderedProminent)
        } else {
            if let error, !cards.isEmpty {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if cards.isEmpty {
                ContentUnavailableView(
                    "No cards found",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("This game has no cards in the catalogue.")
                )
            } else {
                CatalogCardGrid(
                    groups: cardGroups,
                    catalog: catalog,
                    owned: owned
                )
                    .padding(12)
                    .contentWidthLimit(.wide)
            }
            if hasMoreSets {
                ProgressView()
                    .padding()
                    .task { await loadDefaultMore() }
            }
        }
    }

    @ViewBuilder
    private func searchContent(owned: CatalogOwnershipIndex) -> some View {
        if !isSearchQuery {
            ContentUnavailableView(
                "Keep typing",
                systemImage: "text.cursor",
                description: Text("Enter at least two characters.")
            )
        } else if searchCards.isEmpty && searchIsLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching…")
                    .font(.headline)
            }
            .padding(.top, 80)
        } else if searchCards.isEmpty, let searchError {
            ContentUnavailableView(
                "Search failed",
                systemImage: "wifi.exclamationmark",
                description: Text(searchError)
            )
            Button("Retry") { searchRevision += 1 }
                .buttonStyle(.borderedProminent)
        } else if searchCards.isEmpty {
            ContentUnavailableView(
                "No matching cards",
                systemImage: "magnifyingglass",
                description: Text("Try another card name.")
            )
        } else {
            CatalogCardGrid(
                groups: searchCardGroups,
                catalog: catalog,
                owned: owned
            )
                .padding(12)
                .contentWidthLimit(.wide)
            if searchCursor != nil {
                ProgressView()
                    .padding()
                    .task { await loadMoreSearch(query: normalizedSearch) }
            }
        }
    }

    private func loadDefaultMore() async {
        guard !isLoading, !hasSearchText else { return }
        guard activeSetIndex != nil || nextSetIndex < orderedSets.count else { return }
        isLoading = true
        error = nil
        var startedNewSet = false
        do {
            let set: CatalogSet
            let page: CatalogPage<CatalogCardSummary>
            if let activeSetIndex, let cursor {
                set = orderedSets[activeSetIndex]
                page = try await catalog.cards(in: set, cursor: cursor)
            } else {
                let index = nextSetIndex
                nextSetIndex += 1
                activeSetIndex = index
                cursor = nil
                startedNewSet = true
                set = orderedSets[index]
                page = try await catalog.cards(in: set, cursor: nil)
            }
            cards = deduplicated(cards + page.items)
            cursor = page.nextCursor
            if page.nextCursor == nil {
                activeSetIndex = nil
            }
        } catch {
            if startedNewSet {
                nextSetIndex = max(0, nextSetIndex - 1)
                activeSetIndex = nil
                cursor = nil
            }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSearch(query: String, requestKey: String) async {
        guard isActive else { return }
        defer {
            if searchRequestKey == requestKey {
                searchIsLoading = false
            }
        }
        do {
            let page = try await catalog.searchCards(
                named: query,
                game: game,
                setIDs: [],
                cursor: nil
            )
            guard !Task.isCancelled,
                  normalizedSearch == query,
                  searchRequestKey == requestKey else { return }
            searchCards = deduplicated(page.items)
            searchCursor = page.nextCursor
        } catch {
            guard !Task.isCancelled,
                  normalizedSearch == query,
                  searchRequestKey == requestKey else { return }
            searchError = error.localizedDescription
        }
    }

    private func loadMoreSearch(query: String) async {
        guard isActive,
              !searchIsLoading,
              isSearchQuery,
              normalizedSearch == query,
              let cursor = searchCursor else { return }
        guard let requestKey = searchRequestKey else { return }
        searchIsLoading = true
        defer {
            if searchRequestKey == requestKey {
                searchIsLoading = false
            }
        }
        do {
            let page = try await catalog.searchCards(
                named: query,
                game: game,
                setIDs: [],
                cursor: cursor
            )
            guard !Task.isCancelled,
                  normalizedSearch == query,
                  searchRequestKey == requestKey else { return }
            searchCards = deduplicated(searchCards + page.items)
            searchCursor = page.nextCursor
        } catch {
            guard !Task.isCancelled,
                  normalizedSearch == query,
                  searchRequestKey == requestKey else { return }
            searchError = error.localizedDescription
        }
    }

    private func deduplicated(_ values: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

private struct CatalogSetListView: View {
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    @State private var search = ""
    @State private var showsMasterSetRules = false
    @State private var sort: CatalogSetListSort = .newestFirst
    @State private var filter: CatalogSetListFilter = .all

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 16, alignment: .top)]
        }
        return [
            GridItem(.flexible(), spacing: 16, alignment: .top),
            GridItem(.flexible(), spacing: 16, alignment: .top)
        ]
    }

    private var isChronological: Bool {
        sort == .newestFirst || sort == .oldestFirst
    }

    private func makeVisibleSets(owned: CatalogOwnershipIndex) -> [CatalogSet] {
        let query = CardNameSearch.normalize(search)
        let filtered = sets.filter {
            let matchesSearch = query.isEmpty
                || CardNameSearch.normalize($0.name).contains(query)
                || CardNameSearch.normalize($0.code).contains(query)
            let matchesFilter = filter.includes($0, ownership: owned)
            return matchesSearch && matchesFilter
        }
        return CatalogSetOrdering.ordered(filtered, by: sort, ownership: owned)
    }

    var body: some View {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        let visibleSets = makeVisibleSets(owned: owned)
        let groups = CatalogSetListGrouping.groups(for: visibleSets, sort: sort)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if game == .pokemon {
                    masterSetRules
                }

                setListFilters

                if visibleSets.isEmpty {
                    ContentUnavailableView(
                        filter == .started ? "No started sets" : "No matching sets",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(
                            filter == .started
                                ? "Add a card from this game to see its progress here."
                                : "Try another set name or code."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if isChronological {
                    ForEach(groups) { group in
                        CatalogSetGroupSection(
                            group: group,
                            columns: columns,
                            catalog: catalog,
                            owned: owned
                        )
                    }
                } else {
                    CatalogSetGrid(
                        sets: visibleSets,
                        columns: columns,
                        catalog: catalog,
                        owned: owned
                    )
                }
            }
            .padding(16)
            .contentWidthLimit(.standard)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaPadding(.bottom, 24)
        .navigationTitle("\(game.label) Sets")
        .searchable(text: $search, prompt: "Search sets")
    }

    private var masterSetRules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    showsMasterSetRules.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Master set rules")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Image(systemName: showsMasterSetRules ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsMasterSetRules ? "Expanded" : "Collapsed")

            if showsMasterSetRules {
                Text("Standard includes every English, pack-pulled numbered card, holo, reverse holo, and secret rare. Promos and non-pack products stay out. Expanded adds catalog-confirmed special parallel patterns.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var setListFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CatalogSetListFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(filter == option ? Color.white : Color.primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                filter == option ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }

                Menu {
                    Picker("Sort sets", selection: $sort) {
                        ForEach(CatalogSetListSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sort.label)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .accessibilityLabel("Sort sets, \(sort.label)")
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }
}

extension CatalogSetListFilter {
    func includes(_ set: CatalogSet, ownership: CatalogOwnershipIndex) -> Bool {
        switch self {
        case .all:
            return true
        case .started:
            return ownership.progress(for: set).owned > 0
        }
    }
}

struct CatalogSetYearGroup: Identifiable {
    let title: String?
    let sets: [CatalogSet]

    var id: String { title ?? "all" }
}

enum CatalogSetListGrouping {
    static func groups(
        for orderedSets: [CatalogSet],
        sort: CatalogSetListSort
    ) -> [CatalogSetYearGroup] {
        guard !orderedSets.isEmpty else { return [] }

        guard sort == .newestFirst || sort == .oldestFirst else {
            return [CatalogSetYearGroup(title: nil, sets: orderedSets)]
        }

        var setsByYear: [Int: [CatalogSet]] = [:]
        var earlier: [CatalogSet] = []
        let calendar = Calendar.current

        for set in orderedSets {
            guard let releaseDate = set.releaseDate else {
                earlier.append(set)
                continue
            }
            let year = calendar.component(.year, from: releaseDate)
            setsByYear[year, default: []].append(set)
        }

        let years = setsByYear.keys.sorted {
            if sort == .oldestFirst { return $0 < $1 }
            return $0 > $1
        }
        var groups = years.compactMap { year -> CatalogSetYearGroup? in
            guard let sets = setsByYear[year], !sets.isEmpty else { return nil }
            return CatalogSetYearGroup(title: String(year), sets: sets)
        }
        if !earlier.isEmpty {
            let earlierGroup = CatalogSetYearGroup(title: "Earlier", sets: earlier)
            if sort == .oldestFirst {
                groups.insert(earlierGroup, at: 0)
            } else {
                groups.append(earlierGroup)
            }
        }
        return groups
    }
}

private struct CatalogSetGroupSection: View {
    let group: CatalogSetYearGroup
    let columns: [GridItem]
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = group.title {
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.top, 2)
            }

            CatalogSetGrid(
                sets: group.sets,
                columns: columns,
                catalog: catalog,
                owned: owned
            )
        }
    }
}

private struct CatalogSetGrid: View {
    let sets: [CatalogSet]
    let columns: [GridItem]
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(sets) { set in
                NavigationLink {
                    CatalogSetCardsView(set: set, catalog: catalog)
                } label: {
                    CatalogSetTile(
                        set: set,
                        completion: owned.progress(for: set)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CatalogSetCardsView: View {
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    let set: CatalogSet
    let catalog: any BrowseCatalogProviding
    @State private var cards: [CatalogCardSummary] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var search = ""
    @State private var sort: CatalogSetSort = .numberLowToHigh
    @State private var ownership: CatalogOwnershipFilter = .all
    /// The tier is a statement about what the user counts as a master set, not
    /// a per-set preference, so it should not reset every time a set is opened.
    @AppStorage("pokemonMasterSetTier") private var masterSetTier: PokemonMasterSetTier = .standard
    @State private var prices: [String: Double] = [:]
    @State private var isLoadingPrices = false
    @State private var hasLoadedPrices = false
    @State private var contentGeneration = UUID()
    @State private var visibleGroups: [CatalogCardDisplayGroup] = []
    /// Identifies the price request that owns `isLoadingPrices`. Content can
    /// change while a catalog price lookup is suspended, so the content token
    /// alone is not enough to safely clean up the loading state.
    @State private var priceRequestID: UUID?

    private func visibleCards(owned: CatalogOwnershipIndex) -> [CatalogCardSummary] {
        CatalogSetQuery.apply(
            masterSetSlots,
            search: search,
            sort: sort.needsPrices && !hasLoadedPrices ? .numberLowToHigh : sort,
            ownership: ownership,
            owned: owned,
            prices: prices
        )
    }

    private func refreshVisibleGroups() {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        visibleGroups = CatalogCardDisplayGrouping.groups(for: visibleCards(owned: owned))
    }

    private var masterSetSlots: [CatalogCardSummary] {
        guard set.game == .pokemon, masterSetTier == .standard else { return cards }
        return cards.filter { !$0.isExpandedMasterSetVariant }
    }

    private var completion: SetCompletion {
        self.set.game == .pokemon
            ? (projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])).progress(for: masterSetSlots)
            : (projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])).progress(for: set)
    }

    var body: some View {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        let visible = visibleCards(owned: owned)
        return ScrollView {
            if cards.isEmpty && isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading cards…")
                        .font(.headline)
                }
                .padding(.horizontal, 32)
                .padding(.top, 80)
                .accessibilityElement(children: .combine)
            }
            else if cards.isEmpty, let error {
                ContentUnavailableView("Couldn't load this set", systemImage: "wifi.exclamationmark", description: Text(error))
                Button("Retry") { Task { await load(reset: true) } }.buttonStyle(.borderedProminent)
            } else {
                completionHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .contentWidthLimit(.standard)
                if isLoadingPrices {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading prices for this set…")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                }
                if visible.isEmpty {
                    ContentUnavailableView(
                        "No matching cards",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search or ownership filter.")
                    )
                    .padding(.top, 60)
                } else {
                    CatalogCardGrid(
                        groups: visibleGroups,
                        catalog: catalog,
                        owned: owned,
                        prices: prices
                    )
                        .padding(12)
                        .contentWidthLimit(.wide)
                }
                if cursor != nil {
                    ProgressView().padding().task { await load(reset: false) }
                }
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 24)
        .searchable(text: $search, prompt: "Name or number")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CatalogSetSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort cards, \(sort.label)")

                Menu {
                    Picker("Ownership", selection: $ownership) {
                        ForEach(CatalogOwnershipFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: ownership == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter cards, \(ownership.label)")
            }
        }
        .task { if cards.isEmpty { await load(reset: true) } }
        .onAppear { refreshVisibleGroups() }
        .onChange(of: cards) { _, _ in refreshVisibleGroups() }
        .onChange(of: search) { _, _ in refreshVisibleGroups() }
        .onChange(of: ownership) { _, _ in refreshVisibleGroups() }
        .onChange(of: masterSetTier) { _, _ in refreshVisibleGroups() }
        .onChange(of: prices) { _, _ in refreshVisibleGroups() }
        .onChange(of: hasLoadedPrices) { _, _ in refreshVisibleGroups() }
        .onChange(of: projectionStore.revision) { _, _ in refreshVisibleGroups() }
        .onChange(of: sort) { _, newSort in
            refreshVisibleGroups()
            if newSort.needsPrices { Task { await loadPrices() } }
        }
    }

    /// Magic sets showed completion in the set list and then nothing at all on
    /// the set screen. Same header, without the Pokémon-only tier control.
    private var completionHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(set.game == .pokemon ? "Master Set Progress" : "Set Progress")
                        .font(.headline)
                    Text(completion.label)
                        .font(.title2.bold())
                        .foregroundStyle(completion.owned > 0 ? Color.green : Color.primary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if let fraction = completion.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: completion.fraction ?? 0)
                .tint(.green)
                .accessibilityLabel(set.game == .pokemon ? "Master set progress" : "Set progress")
                .accessibilityValue(completion.label)

            if set.game == .pokemon {
                Picker("Master set definition", selection: $masterSetTier) {
                    ForEach(PokemonMasterSetTier.allCases) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                .pickerStyle(.segmented)

                Text(masterSetTier.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        let requestID = UUID()
        contentGeneration = requestID
        // A page load changes the card set even before its response arrives.
        // Invalidate any sort request for the previous set so its result cannot
        // strand the new page in a loading state or mark it fully priced.
        priceRequestID = nil
        isLoadingPrices = false
        hasLoadedPrices = false
        isLoading = true
        defer {
            if contentGeneration == requestID { isLoading = false }
        }
        if reset { error = nil; cursor = nil }
        do {
            let page = try await catalog.cards(in: set, cursor: reset ? nil : cursor)
            guard contentGeneration == requestID, !Task.isCancelled else { return }
            cards = reset ? page.items : deduplicated(cards + page.items)
            cursor = page.nextCursor
            if sort.needsPrices { await loadPrices(for: requestID, whileLoadingCards: true) }
        } catch {
            guard contentGeneration == requestID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadPrices(
        for expectedContentGeneration: UUID? = nil,
        whileLoadingCards: Bool = false
    ) async {
        // Pagination owns the card-content transition. A sort-change task must
        // not snapshot the old card set while that transition is in flight;
        // the page load will start the price request after its page is applied.
        guard !cards.isEmpty,
              whileLoadingCards || !isLoading else { return }
        let contentRequestID = expectedContentGeneration ?? contentGeneration
        guard contentRequestID == contentGeneration else { return }
        guard priceRequestID == nil else { return }

        let priceRequestID = UUID()
        self.priceRequestID = priceRequestID
        let requestedCardIDs = Set(cards.map(\.id))
        isLoadingPrices = true
        hasLoadedPrices = false
        defer {
            if self.priceRequestID == priceRequestID {
                self.priceRequestID = nil
                self.isLoadingPrices = false
            }
        }
        let loadedPrices = await catalog.sortPrices(for: cards)
        guard contentRequestID == contentGeneration,
              self.priceRequestID == priceRequestID,
              !Task.isCancelled else { return }
        prices.merge(loadedPrices) { _, newest in newest }
        hasLoadedPrices = requestedCardIDs == Set(cards.map(\.id))
    }

    private func deduplicated(_ values: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

private struct CatalogCardGrid: View {
    let groups: [CatalogCardDisplayGroup]
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex
    let prices: [String: Double]
    /// Adaptive so the catalog gains columns with the window instead of stretching
    /// two of them across a thirteen-inch iPad. The minimum matches the tile width
    /// the two-column phone layout already produces.
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    init(
        groups: [CatalogCardDisplayGroup],
        catalog: any BrowseCatalogProviding,
        owned: CatalogOwnershipIndex,
        prices: [String: Double] = [:]
    ) {
        self.groups = groups
        self.catalog = catalog
        self.owned = owned
        self.prices = prices
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(groups) { group in
                CatalogCardDisplayGroupTile(
                    group: group,
                    catalog: catalog,
                    owned: owned,
                    prices: prices
                )
            }
        }
    }
}

private struct CatalogCardDisplayGroupTile: View {
    let group: CatalogCardDisplayGroup
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex
    let prices: [String: Double]

    private var preferred: CatalogCardSummary { group.preferredSummary }
    private var showsVariantChips: Bool {
        group.summaries.count > 1 || preferred.masterSetVariantLabel != nil
    }

    private var sharedPrice: Double? {
        let values = group.summaries.compactMap { prices[$0.id] }
        guard values.count == group.summaries.count,
              let first = values.first,
              values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private var showsIndividualPrices: Bool { sharedPrice == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                CatalogCardDetailView(summary: preferred, catalog: catalog)
            } label: {
                cardMainContent
            }
            .buttonStyle(.plain)

            if showsVariantChips {
                CatalogVariantChipWrap(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(group.summaries) { summary in
                        NavigationLink {
                            CatalogCardDetailView(summary: summary, catalog: catalog)
                        } label: {
                            variantChip(summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var cardMainContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            CatalogArtworkView(
                thumbnailURL: preferred.thumbnailURL,
                imageURL: preferred.imageURL,
                game: preferred.game,
                setCode: preferred.setCode,
                collectorNumber: preferred.collectorNumber
            )
                .overlay(alignment: .topTrailing) {
                    if owned.owns(preferred) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }

            Text(preferred.name)
                .font(.headline)
                .lineLimit(2)

            if let treatment = preferred.magicTreatmentDisplayLabel {
                CatalogTreatmentBadge(label: treatment)
            }

            if let sharedPrice {
                Text(sharedPrice, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }

            HStack {
                Text("\(preferred.setCode) \(preferred.collectorNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !showsVariantChips {
                    let count = ownedQuantity(preferred)
                    if count > 0 {
                        Text("Owned \(count)")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(preferred))
    }

    private func variantChip(_ summary: CatalogCardSummary) -> some View {
        let count = ownedQuantity(summary)
        let label = summary.masterSetVariantLabel ?? "Standard"
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if count > 0 {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                Text("Owned")
                    .font(.caption2.weight(.semibold))
            }
            if showsIndividualPrices, let price = prices[summary.id] {
                Text(price, format: .currency(code: "USD"))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(count > 0 ? Color.green : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            (count > 0 ? Color.green : Color.accentColor).opacity(0.12),
            in: Capsule()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(label)\(count > 0 ? ", Owned quantity \(count)" : ", Not owned")\(prices[summary.id].map { ", price \($0.formatted(.currency(code: "USD")))" } ?? "")"
        )
    }

    private func ownedQuantity(_ summary: CatalogCardSummary) -> Int {
        owned.quantity(of: summary)
    }

    private func accessibilityLabel(_ summary: CatalogCardSummary) -> String {
        let ownedQuantity = ownedQuantity(summary)
        let price = prices[summary.id].map { ", price \($0.formatted(.currency(code: "USD")))" } ?? ""
        let variant = summary.masterSetVariantLabel.map { ", \($0) variation" } ?? ""
        let treatment = summary.magicTreatmentDisplayLabel.map { ", \($0) treatment" } ?? ""
        return "\(summary.name), \(summary.setName), card \(summary.collectorNumber)\(variant)\(treatment)\(price)\(ownedQuantity > 0 ? ", owned quantity \(ownedQuantity)" : ", missing")"
    }
}

private struct CatalogVariantChipWrap: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layoutFrames(width: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layoutFrames(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func layoutFrames(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let availableWidth = max(width, 1)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: availableWidth, height: nil)
            )
            if x > 0, x + size.width > availableWidth {
                contentWidth = max(contentWidth, x - horizontalSpacing)
                y += lineHeight + verticalSpacing
                x = 0
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            contentWidth = max(contentWidth, x - horizontalSpacing)
        }

        return (
            frames,
            CGSize(width: min(contentWidth, availableWidth), height: y + lineHeight)
        )
    }
}

private struct CatalogTreatmentBadge: View {
    let label: String

    var body: some View {
        Label(label, systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

struct CatalogArtworkView: View {
    let thumbnailURL: URL?
    let imageURL: URL?
    var prefersFullSize = false
    var game: CardGame? = nil
    var setCode: String? = nil
    var collectorNumber: String? = nil

    private var artworkSource: CatalogCardArtworkSource {
        CatalogCardArtworkSource(
            game: game,
            setCode: setCode,
            collectorNumber: collectorNumber,
            thumbnailURL: thumbnailURL,
            imageURL: imageURL,
            prefersFullSize: prefersFullSize
        )
    }

    var body: some View {
        CatalogCachedImage(
            url: artworkSource.primaryURL,
            fallbacks: artworkSource.fallbacks
        )
        .aspectRatio(0.727, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Small, app-owned remote artwork view. The corresponding disk cache lives in
/// Caches (not Application Support), so iOS may reclaim it under pressure and
/// it never becomes synced collection data.
struct CatalogCachedImage: View {
    let url: URL?
    var fallbacks: [URL] = []
    /// An explicit maximum decoded dimension is useful for callers that know
    /// their drawing size. Most callers leave this nil and the view measures
    /// its laid-out bounds so the cache can keep separate derivatives for a
    /// grid tile, a portfolio thumbnail, and a detail hero.
    var targetPixelSize: Int? = nil
    var reloadToken: Int = 0
    var placeholderSymbol = "photo"
    var placeholderText: String? = nil
    var localAssetName: String? = nil
    var localFallbackAssetNames: [String] = []
    var onPhaseChange: ((CatalogImageLoadPhase) -> Void)? = nil
    private var recursionTier: Int = 0
    @StateObject private var loader = CatalogImageLoader()
    @Environment(\.displayScale) private var displayScale
    @State private var measuredTargetPixelSize: Int?

    private struct LoadID: Equatable {
        let url: URL?
        let targetPixelSize: Int?
        let reloadToken: Int
    }

    init(
        url: URL?,
        fallbacks: [URL] = [],
        targetPixelSize: Int? = nil,
        reloadToken: Int = 0,
        placeholderSymbol: String = "photo",
        placeholderText: String? = nil,
        localAssetName: String? = nil,
        localFallbackAssetNames: [String] = [],
        onPhaseChange: ((CatalogImageLoadPhase) -> Void)? = nil
    ) {
        self.url = url
        self.fallbacks = fallbacks
        self.targetPixelSize = targetPixelSize
        self.reloadToken = reloadToken
        self.placeholderSymbol = placeholderSymbol
        self.placeholderText = placeholderText
        self.localAssetName = localAssetName
        self.localFallbackAssetNames = localFallbackAssetNames
        self.onPhaseChange = onPhaseChange
    }

    private init(
        url: URL?,
        fallbacks: [URL],
        targetPixelSize: Int?,
        reloadToken: Int,
        placeholderSymbol: String,
        placeholderText: String?,
        localAssetName: String?,
        localFallbackAssetNames: [String],
        onPhaseChange: ((CatalogImageLoadPhase) -> Void)?,
        recursionTier: Int
    ) {
        self.init(
            url: url,
            fallbacks: fallbacks,
            targetPixelSize: targetPixelSize,
            reloadToken: reloadToken,
            placeholderSymbol: placeholderSymbol,
            placeholderText: placeholderText,
            localAssetName: localAssetName,
            localFallbackAssetNames: localFallbackAssetNames,
            onPhaseChange: onPhaseChange
        )
        self.recursionTier = recursionTier
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.failed, let nextFallback {
                CatalogCachedImage(
                    url: nextFallback.url,
                    fallbacks: nextFallback.remaining,
                    targetPixelSize: targetPixelSize,
                    reloadToken: reloadToken,
                    placeholderSymbol: placeholderSymbol,
                    placeholderText: placeholderText,
                    localAssetName: localAssetName,
                    localFallbackAssetNames: localFallbackAssetNames,
                    onPhaseChange: onPhaseChange,
                    recursionTier: recursionTier + 1
                )
            } else if (remoteURL == nil || loader.failed), let localAssetImage {
                Image(uiImage: localAssetImage)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateMeasuredTarget(for: proxy.size) }
                    .onChange(of: proxy.size) { _, size in
                        updateMeasuredTarget(for: size)
                    }
            }
        }
        .task(id: LoadID(
            url: remoteURL,
            targetPixelSize: resolvedTargetPixelSize,
            reloadToken: reloadToken
        )) {
            guard let resolvedTargetPixelSize else { return }
            loader.load(remoteURL, targetPixelSize: resolvedTargetPixelSize)
        }
        .onChange(of: loader.phase) { _, phase in
            if phase == .loaded || phase == .failed {
                CatalogArtworkLog.log(
                    phase: phase,
                    tier: recursionTier,
                    url: remoteURL
                )
            }
            // A URL may fail while a fallback or local asset is still
            // available. The caller only sees the terminal state from the
            // innermost loader.
            guard !(phase == .failed && (nextFallback != nil || localAssetImage != nil)) else {
                return
            }
            onPhaseChange?(phase)
        }
    }

    private var remoteURL: URL? { url ?? fallbacks.first }

    private var nextFallback: (url: URL, remaining: [URL])? {
        guard let remoteURL else { return nil }
        guard let index = fallbacks.firstIndex(where: { $0 != remoteURL }) else {
            return nil
        }
        return (
            url: fallbacks[index],
            remaining: Array(fallbacks.dropFirst(index + 1))
        )
    }

    private var localAssetImage: UIImage? {
        ([localAssetName].compactMap { $0 } + localFallbackAssetNames)
            .compactMap { UIImage(named: $0) }
            .first
    }

    private var resolvedTargetPixelSize: Int? {
        targetPixelSize.map(Self.quantizedPixelSize)
            ?? measuredTargetPixelSize.map(Self.quantizedPixelSize)
    }

    private static func quantizedPixelSize(_ size: Int) -> Int {
        let clamped = min(max(size, 128), 4_096)
        return min(((clamped + 127) / 128) * 128, 4_096)
    }

    private func updateMeasuredTarget(for size: CGSize) {
        guard targetPixelSize == nil else { return }
        let maximumPointDimension = max(size.width, size.height)
        guard maximumPointDimension.isFinite, maximumPointDimension > 1 else { return }
        let measured = Int(ceil(maximumPointDimension * displayScale))
        let bucket = Self.quantizedPixelSize(measured)
        guard bucket != measuredTargetPixelSize else { return }
        measuredTargetPixelSize = bucket
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .overlay {
                if loader.isLoading {
                    ProgressView()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: placeholderSymbol)
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
}

enum CatalogImageLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

private enum CatalogArtworkLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TradingCardScanner",
        category: "CatalogArtwork"
    )

    static func log(phase: CatalogImageLoadPhase, tier: Int, url: URL?) {
        let phaseName: String
        switch phase {
        case .idle: phaseName = "idle"
        case .loading: phaseName = "loading"
        case .loaded: phaseName = "loaded"
        case .failed: phaseName = "failed"
        }
        logger.debug(
            "phase=\(phaseName, privacy: .public) tier=\(tier, privacy: .public) source=\((url?.absoluteString ?? "none"), privacy: .public)"
        )
    }
}

@MainActor
private final class CatalogImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var failed = false
    @Published var phase: CatalogImageLoadPhase = .idle
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    func load(_ url: URL?, targetPixelSize: Int?) {
        task?.cancel()
        image = nil
        failed = false
        phase = .idle
        guard let url else {
            isLoading = false
            return
        }
        isLoading = true
        phase = .loading
        task = Task { [weak self] in
            do {
                let image = try await CatalogImageCache.shared.image(
                    for: url,
                    targetPixelSize: targetPixelSize
                )
                guard !Task.isCancelled else { return }
                self?.image = image
                self?.phase = .loaded
            } catch {
                if !Task.isCancelled {
                    self?.failed = true
                    self?.phase = .failed
                }
            }
            if !Task.isCancelled { self?.isLoading = false }
        }
    }
}

/// A 60 MiB LRU disk cache for provider artwork. It deliberately persists only
/// source-URL keyed image bytes, never collection photos or provider responses.
actor CatalogImageCache {
    static let shared = CatalogImageCache()
    private static let maximumBytes = 60 * 1_024 * 1_024
    private static let maximumAssetBytes = 5 * 1_024 * 1_024
    private static let trimThresholdBytes = 10 * 1_024 * 1_024
    private static let touchInterval: TimeInterval = 60
    private static let maximumTouchEntries = 512
    /// A short-lived fallback for non-view consumers such as accent sampling.
    /// `CatalogCachedImage` normally replaces this with its measured bounds.
    private static let defaultTargetPixelSize = 1_024
    private static let maximumTargetPixelSize = 4_096

    private let directory: URL
    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private struct InFlight {
        let id: UUID
        let task: Task<Data, Error>
    }
    private var inFlight: [URL: InFlight] = [:]
    private var lastTouchAt: [URL: Date] = [:]
    private var bytesSinceTrim = 0
    private var didTrimAtStartup = false

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BrowseArtworkCache", isDirectory: true)
    }

    func image(for url: URL, targetPixelSize: Int? = nil) async throws -> UIImage {
        let targetPixelSize = Self.normalizedTargetPixelSize(targetPixelSize)
        let cacheKey = Self.memoryKey(for: url, targetPixelSize: targetPixelSize)
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let data = try await data(for: url)
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsampledImage(from: data, targetPixelSize: targetPixelSize)
        }.value
        guard let image else {
            throw BrowseCatalogError.badResponse
        }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? max(Int(image.size.width * image.scale * image.size.height * image.scale * 4), 1)
        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private static func normalizedTargetPixelSize(_ targetPixelSize: Int?) -> Int {
        min(
            max(targetPixelSize ?? defaultTargetPixelSize, 1),
            maximumTargetPixelSize
        )
    }

    private static func memoryKey(for url: URL, targetPixelSize: Int) -> NSString {
        "\(url.absoluteString)#pixel=\(targetPixelSize)" as NSString
    }

    private static func downsampledImage(
        from data: Data,
        targetPixelSize: Int
    ) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions as CFDictionary
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func data(for url: URL) async throws -> Data {
        await trimAtStartupIfNeeded()
        let file = directory.appendingPathComponent(filename(for: url))
        if let cached = try? await Self.readData(from: file) {
            await touchIfNeeded(file, for: url)
            return cached
        }

        if let existing = inFlight[url] {
            // A cancelled image owner must not cancel a request another cell is
            // already waiting for. The shared task is intentionally unstructured
            // and is cleaned up by whichever waiter resumes first.
            return try await existing.task.value
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let requestID = UUID()
        let task = Task<Data, Error> {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw BrowseCatalogError.badResponse
            }
            return data
        }

        inFlight[url] = InFlight(id: requestID, task: task)
        do {
            let data = try await task.value
            // Only one waiter writes the completed response. This also avoids
            // duplicate LRU timestamps when several visible cells share a URL.
            if inFlight[url]?.id == requestID {
                if data.count <= Self.maximumAssetBytes {
                    await Self.writeData(data, to: file, directory: directory)
                    bytesSinceTrim += data.count
                    if bytesSinceTrim >= Self.trimThresholdBytes {
                        bytesSinceTrim = 0
                        await trimOffActor()
                    }
                }
                inFlight[url] = nil
            }
            return data
        } catch {
            if inFlight[url]?.id == requestID {
                inFlight[url] = nil
            }
            throw error
        }
    }

    private func touchIfNeeded(_ file: URL, for sourceURL: URL) async {
        let now = Date.now
        guard now.timeIntervalSince(lastTouchAt[sourceURL] ?? .distantPast) >= Self.touchInterval else {
            return
        }
        if lastTouchAt[sourceURL] == nil,
           lastTouchAt.count >= Self.maximumTouchEntries,
           let oldest = lastTouchAt.min(by: { $0.value < $1.value })?.key {
            lastTouchAt.removeValue(forKey: oldest)
        }
        lastTouchAt[sourceURL] = now
        await Self.touch(file: file, at: now)
    }

    private func trimAtStartupIfNeeded() async {
        guard !didTrimAtStartup else { return }
        didTrimAtStartup = true
        // A previous process may have left the disk cache at its ceiling. One
        // lazy startup trim restores the limit without enumerating the entire
        // directory on every image download.
        await trimOffActor()
    }

    private func trimOffActor() async {
        let directory = self.directory
        await Task.detached(priority: .utility) {
            Self.trim(directory: directory)
        }.value
    }

    private static func readData(from file: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: file)
        }.value
    }

    private static func writeData(_ data: Data, to file: URL, directory: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? data.write(to: file, options: .atomic)
        }.value
    }

    private static func touch(file: URL, at date: Date) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: file.path
            )
        }.value
    }

    private static func trim(directory: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let files = urls.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        for (url, size, _) in files where total > Self.maximumBytes {
            guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            total -= size
        }
    }

    private func filename(for url: URL) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16) + ".image"
    }
}

private struct CatalogSetFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sets: [CatalogSet]
    let selectedGame: CardGame?
    @Binding var selection: Set<CatalogSetID>
    @State private var search = ""

    private var visible: [CatalogSet] {
        let query = CardNameSearch.normalize(search)
        let filtered = sets.filter { set in
            (selectedGame == nil || set.game == selectedGame)
                && (
                    query.isEmpty
                        || CardNameSearch.normalize(set.name + " " + set.code).contains(query)
                )
        }
        return CatalogSetOrdering.newestFirst(filtered)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(CardGame.allCases) { game in
                    let gameSets = visible.filter { $0.game == game }
                    if !gameSets.isEmpty {
                        Section(game.label) {
                            ForEach(gameSets) { set in
                                Button {
                                    if selection.contains(set.catalogID) { selection.remove(set.catalogID) }
                                    else { selection.insert(set.catalogID) }
                                } label: {
                                    HStack {
                                        Text(set.name)
                                        Spacer()
                                        Text(set.code).foregroundStyle(.secondary)
                                        if selection.contains(set.catalogID) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Sets")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search sets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { selection.removeAll() }.disabled(selection.isEmpty) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
