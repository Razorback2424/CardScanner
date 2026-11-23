import Combine
import ImageIO
import OSLog
import SwiftData
import SwiftUI
import UIKit

private struct CatalogSetNavigationKey: EnvironmentKey {
    static let defaultValue: (CatalogSet) -> Void = { _ in }
}

private extension EnvironmentValues {
    var openCatalogSet: (CatalogSet) -> Void {
        get { self[CatalogSetNavigationKey.self] }
        set { self[CatalogSetNavigationKey.self] = newValue }
    }
}

@MainActor
final class BrowseViewModel: ObservableObject {
    struct Lane {
        var cards: [CatalogCardSummary] = []
        var cursor: String?
        var isLoading = false
        var error: String?
        var paginationRevision: UInt = 0
        var visitedCursors: Set<String> = []

        var paginationKey: String { "\(paginationRevision)|\(cursor ?? "")" }
    }

    @Published var searchText = "" { didSet { scheduleSearch() } }
    @Published var selectedGame: CardGame? { didSet { scheduleSearch() } }
    @Published var selectedSets: Set<CatalogSetID> = [] { didSet { scheduleSearch() } }
    @Published var selectedResultKind: CatalogResultKind? { didSet { scheduleSearch() } }
    @Published private(set) var sets: [CardGame: [CatalogSet]] = [:]
    @Published private(set) var catalogRevision = 0
    @Published private(set) var setErrors: [CardGame: String] = [:]
    @Published private(set) var lanes: [CardGame: Lane] = [:]
    @Published private(set) var searchResults: [CatalogSearchResult] = []
    @Published private(set) var isLoadingSearchFirstPages = false

    let catalog: any BrowseCatalogProviding
    var gameRegistry: CardGameRegistry { catalog.gameRegistry }
    let sealedModel: SealedBrowseModel
    private let includesSealedProducts: Bool
    private var searchTask: Task<Void, Never>?
    private var searchResultsRefreshTask: Task<Void, Never>?
    private var searchIsSuspended = false
    private var needsSearchOnResume = false
    private var cardGamesToResume: [CardGame]?
    private var generation = UUID()
    private var setLoadIDs: [CardGame: UUID] = [:]
    private var catalogUpdateSequence: UInt64?
    private var sealedModelCancellable: AnyCancellable? = nil
    private let releaseRailCache: CatalogReleaseRailCache?
    /// The rail last shown with complete directories, read once so the next
    /// visit can present it before the directories finish rebuilding.
    private(set) var cachedReleaseRailSets: [CatalogSet]

    init(
        catalog: any BrowseCatalogProviding = BrowseCatalog(),
        sealedModel: SealedBrowseModel? = nil,
        initialGame: CardGame? = nil,
        includesSealedProducts: Bool = true,
        releaseRailCache: CatalogReleaseRailCache? = nil
    ) {
        self.catalog = catalog
        self.includesSealedProducts = includesSealedProducts
        self.releaseRailCache = releaseRailCache
        cachedReleaseRailSets = releaseRailCache?.load() ?? []
        let sealedModel = sealedModel ?? SealedBrowseModel(transport: JustTCGTransport.shared, gameRegistry: catalog.gameRegistry)
        self.sealedModel = sealedModel
        self.selectedGame = initialGame
        self.sealedModelCancellable = sealedModel.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            self.scheduleSearchResultsRefresh()
        }
        recomputeSearchResults()
    }

    var normalizedQuery: String { CardNameSearch.normalize(searchText) }
    private var providerQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !normalizedQuery.isEmpty }
    var canSearch: Bool { normalizedQuery.count >= 2 || !queryCardGames.isEmpty }

    var searchGames: [CardGame] {
        selectedGame.map { [$0] } ?? gameRegistry.games(supporting: .browse)
    }

    var cardSearchGames: [CardGame] {
        guard selectedResultKind != .sealed else { return [] }
        guard selectedGame == nil, !selectedSets.isEmpty else { return searchGames }
        return searchGames.filter { game in selectedSets.contains { $0.game == game } }
    }

    private var queryCardGames: [CardGame] {
        let query = normalizedQuery
        return cardSearchGames.filter { CatalogCardSearchQuery.isEligible(query, for: $0) }
    }

    /// A single deterministic stream assembled from the independently paged
    /// card and sealed lanes. It is refreshed when either lane family changes,
    /// so a render does not sort the same provider pages more than once.
    private func recomputeSearchResults() {
        let cardResults = cardSearchGames.flatMap { game in
            (lanes[game]?.cards ?? []).map(CatalogSearchResult.card)
        }
        let sealedResults = searchGames.filter { sealedLaneIsRequested(for: $0) }.flatMap { game in
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
        guard !searchIsSuspended else { return }
        searchResultsRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.recomputeSearchResults()
        }
    }

    var searchState: CatalogSearchState {
        guard canSearch else { return .idle }
        let games = searchGames
        var statuses: [CatalogSearchLaneStatus] = queryCardGames.map { game in
            guard let lane = lanes[game] else {
                return CatalogSearchLaneStatus(isLoading: true)
            }
            return CatalogSearchLaneStatus(
                isLoading: lane.isLoading,
                error: lane.error
            )
        }

        let sealedWasSkipped = selectedResultKind != .card && normalizedQuery.count >= 2
            && includesSealedProducts && games.contains {
            gameRegistry.supports($0, .sealed) && !sealedModel.isConfigured(for: $0)
                && !sealedLaneIsRequested(for: $0)
        }
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
            sealedWasSkippedForMissingCredentials: sealedWasSkipped,
            hasContinuation: hasSearchPagination
        )
    }

    var hasSearchPagination: Bool {
        guard canSearch else { return false }
        return searchGames.contains { game in
            if cardSearchGames.contains(game), let lane = lanes[game], lane.cursor != nil, lane.error == nil {
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

    /// Preserve completed results across a detail push or tab change, while
    /// preventing hidden searches from retaining the screen and spending quota.
    func suspendSearch() {
        guard !searchIsSuspended else { return }
        searchIsSuspended = true
        needsSearchOnResume = searchTask != nil && canSearch
        cardGamesToResume = needsSearchOnResume
            ? queryCardGames.filter { lanes[$0]?.isLoading != false }
            : nil
        searchTask?.cancel()
        searchTask = nil
        isLoadingSearchFirstPages = false
        searchResultsRefreshTask?.cancel()
        generation = UUID()
        for (game, var lane) in lanes where lane.isLoading {
            lane.isLoading = false
            lanes[game] = lane
        }
        sealedModel.cancelSearchRequests()
        recomputeSearchResults()
    }

    func resumeSearch() {
        searchIsSuspended = false
        guard needsSearchOnResume else { return }
        needsSearchOnResume = false
        guard canSearch else { return }
        let query = providerQuery
        let token = generation
        let cardGames = (cardGamesToResume ?? queryCardGames).filter { queryCardGames.contains($0) }
        cardGamesToResume = nil
        for game in cardGames { lanes[game] = Lane(isLoading: true) }
        isLoadingSearchFirstPages = true
        searchTask = Task { [weak self] in
            guard !Task.isCancelled, let self, self.generation == token else { return }
            await self.runSearch(query: query, token: token, cardGames: cardGames)
            self.finishFirstPages(token)
        }
    }

    /// Records the live rail only when it differs from what was cached, so an
    /// unchanged catalog costs no write. The returned task completes after
    /// the background cache write.
    @discardableResult
    func rememberReleaseRail(_ rail: [CatalogSet]) -> Task<Void, Never>? {
        guard let releaseRailCache, rail != cachedReleaseRailSets else { return nil }
        cachedReleaseRailSets = rail
        return Task.detached(priority: .utility) { releaseRailCache.store(rail) }
    }

    var availableCompletionSets: [CatalogSet] {
        gameRegistry.games(supporting: .browse).flatMap { sets[$0] ?? [] }
    }

    func loadSets() async {
        await loadSetDirectories(gameRegistry.games(supporting: .browse).filter { sets[$0] == nil })
    }

    private func loadSetDirectories(_ games: [CardGame]) async {
        let requests = games.map { game in
            let id = UUID()
            setLoadIDs[game] = id
            setErrors[game] = nil
            return (game, id)
        }
        await withTaskGroup(of: (CardGame, UUID, [CatalogSet]?, String?).self) { group in
            for (game, id) in requests {
                group.addTask { [catalog] in
                    let interval = PerformanceSignpost.beginInterval("Browse.directory", id: PerformanceSignpost.makeID(), game.rawValue)
                    defer { PerformanceSignpost.endInterval("Browse.directory", interval, game.rawValue) }
                    do { return (game, id, try await catalog.sets(for: game), nil) }
                    catch is CancellationError { return (game, id, nil, nil) }
                    catch { return (game, id, nil, error.localizedDescription) }
                }
            }
            for await (game, id, directory, error) in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                guard setLoadIDs[game] == id else { continue }
                if let directory { sets[game] = directory }
                setErrors[game] = error
            }
        }
    }

    func observeCatalogUpdates() async {
        let (updates, baseline) = await catalog.catalogUpdates(after: catalogUpdateSequence)
        guard !Task.isCancelled else { return }
        if catalogUpdateSequence == nil { catalogUpdateSequence = baseline }
        for await update in updates {
            guard !Task.isCancelled else { return }
            let affectedGames = gameRegistry.games(supporting: .browse).filter { update.affects(game: $0) }
            guard !affectedGames.isEmpty else {
                catalogUpdateSequence = update.sequence ?? catalogUpdateSequence
                continue
            }
            let previousDirectories = sets
            await loadSetDirectories(affectedGames)
            guard !Task.isCancelled else { return }
            catalogRevision += 1
            let available = Set(sets.values.flatMap { $0.map(\.catalogID) })
            let retainedSelection = selectedSets.intersection(available)
            if retainedSelection != selectedSets {
                selectedSets = retainedSelection
            } else if queryCardGames.contains(where: { game in
                affectedGames.contains(game) && shouldRestartSearch(for: update, game: game,
                    previousDirectory: previousDirectories[game] ?? [])
            }) {
                // Invalidate previous-generation rows/cursors even when the query
                // and selected sets did not change. Existing debounce coalesces
                // successive checklist/catalog publications.
                scheduleSearch()
            } else {
                recomputeSearchResults()
            }
            catalogUpdateSequence = update.sequence ?? catalogUpdateSequence
        }
    }

    private func shouldRestartSearch(
        for update: BrowseCatalogUpdate, game: CardGame, previousDirectory: [CatalogSet]
    ) -> Bool {
        guard update.providerSetID != nil else { return true }
        let selected = effectiveSetIDs(for: game)
        if !selected.isEmpty {
            return selected.contains { update.affects(game: game, providerSetID: $0.providerID) }
        }
        let previousIDs = Set(previousDirectory.map(\.catalogID))
        let currentIDs = Set((sets[game] ?? []).map(\.catalogID))
        // A checklist can gain a match without changing the directory. Its
        // new matches can also move the boundary of an existing offset page.
        let changedPokemonChecklist = game == .pokemon && (previousIDs.union(currentIDs)).contains {
            update.affects(game: game, providerSetID: $0.providerID)
        }
        return previousIDs != currentIDs || changedPokemonChecklist || lanes[game]?.isLoading == true
            || lanes[game]?.cards.contains { update.affects(game: game, providerSetID: $0.setID.providerID) } == true
    }

    func retrySets(_ game: CardGame) async {
        await loadSetDirectories([game])
    }

    func loadMore(_ game: CardGame) async {
        let requestedQuery = providerQuery
        let requestedGeneration = generation
        let requestedSetIDs = effectiveSetIDs(for: game)
        guard !Task.isCancelled, !searchIsSuspended, queryCardGames.contains(game),
              var lane = lanes[game],
              let cursor = lane.cursor,
              !lane.isLoading, lane.error == nil else { return }
        lane.isLoading = true
        lanes[game] = lane
        defer {
            if generation == requestedGeneration,
               var currentLane = lanes[game] {
                currentLane.isLoading = false
                // Wake a replacement footer that appeared while cancellation
                // was still settling; the cancelled page keeps its cursor.
                if Task.isCancelled { currentLane.paginationRevision &+= 1 }
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
            guard !Task.isCancelled, generation == requestedGeneration,
                  providerQuery == requestedQuery,
                  var currentLane = lanes[game],
                  currentLane.cursor == cursor else { return }
            currentLane.visitedCursors.insert(cursor)
            if let next = page.nextCursor, currentLane.visitedCursors.contains(next) {
                throw BrowseCatalogError.badResponse
            }
            currentLane.cards = deduplicated(currentLane.cards + page.items)
            currentLane.cursor = page.nextCursor
            currentLane.error = nil
            lanes[game] = currentLane
            recomputeSearchResults()
        } catch {
            guard generation == requestedGeneration,
                  providerQuery == requestedQuery,
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

    func loadMoreSealed(_ game: CardGame) async {
        guard !Task.isCancelled, !searchIsSuspended,
              searchGames.contains(game), sealedLaneIsRequested(for: game),
              sealedModel.searchLanes[game]?.error == nil else { return }
        await sealedModel.loadMoreSearch(game: game, query: normalizedQuery)
    }

    func retrySearch() {
        scheduleSearch()
    }

    func continueSearch() async {
        let token = generation
        for game in searchGames {
            guard !Task.isCancelled, generation == token else { return }
            await loadMore(game)
            guard !Task.isCancelled, generation == token else { return }
            await loadMoreSealed(game)
        }
    }

    /// The automatic footer may be unwinding a cancelled fetch when the user
    /// switches to an explicit full sort. Let it release the lane first.
    func waitForSearchPagination() async throws {
        let token = generation
        while generation == token, !searchIsSuspended, searchGames.contains(where: { game in
            (lanes[game]?.cursor != nil && lanes[game]?.isLoading == true)
                || (sealedLaneIsRequested(for: game) && sealedModel.searchLanes[game]?.nextOffset != nil
                    && sealedModel.searchLanes[game]?.isLoading == true)
        }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard generation == token, !searchIsSuspended else { throw CancellationError() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = nil
        cardGamesToResume = nil
        needsSearchOnResume = false
        generation = UUID()
        let token = generation
        let query = providerQuery
        isLoadingSearchFirstPages = canSearch && !searchIsSuspended
        guard canSearch else {
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
        needsSearchOnResume = searchIsSuspended
        guard !searchIsSuspended else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            await self.runSearch(query: query, token: token)
            self.finishFirstPages(token)
        }
    }

    private func finishFirstPages(_ token: UUID) {
        guard generation == token else { return }
        searchTask = nil
        isLoadingSearchFirstPages = false
    }

    private func runSearch(query: String, token: UUID, cardGames: [CardGame]? = nil) async {
        let selectedGames = searchGames
        let eligible = queryCardGames
        let games = (cardGames ?? eligible).filter { eligible.contains($0) }
        for game in games { lanes[game] = Lane(isLoading: true) }
        for game in gameRegistry.games(supporting: .browse) where !cardSearchGames.contains(game) { lanes[game] = nil }
        recomputeSearchResults()

        // Own and join the workers explicitly. Device Browse crashes reached
        // AsyncTask.completeFuture while the nested search groups completed;
        // keep their lifetimes independent of an async-let stack frame.
        let cardSearch = Task { await searchCardLanes(games: games, query: query, token: token) }
        await withTaskCancellationHandler {
            if selectedResultKind != .card && includesSealedProducts && normalizedQuery.count >= 2 {
                await sealedModel.search(query: CardNameSearch.normalize(query),
                                         games: selectedGames.filter { gameRegistry.supports($0, .sealed) })
            }
            await cardSearch.value
        } onCancel: {
            cardSearch.cancel()
        }
    }

    private func sealedLaneIsRequested(for game: CardGame) -> Bool {
        selectedResultKind != .card && normalizedQuery.count >= 2 && includesSealedProducts && gameRegistry.supports(game, .sealed)
            && (sealedModel.isConfigured(for: game) || !(sealedModel.searchLanes[game]?.products.isEmpty ?? true))
    }

    private func searchCardLanes(games: [CardGame], query: String, token: UUID) async {
        let tasks = games.map { game in
            let catalog = catalog
            let setIDs = effectiveSetIDs(for: game)
            return Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                let result: Result<CatalogPage<CatalogCardSummary>, Error>
                do {
                    result = .success(try await catalog.searchCards(
                        named: query, game: game, setIDs: setIDs, cursor: nil
                    ))
                } catch {
                    result = .failure(error)
                }
                guard !Task.isCancelled, let self, self.generation == token else { return }
                switch result {
                case let .success(page):
                    self.lanes[game] = Lane(cards: self.deduplicated(page.items), cursor: page.nextCursor)
                case let .failure(error):
                    self.lanes[game] = Lane(error: error.localizedDescription)
                }
                self.recomputeSearchResults()
            }
        }
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: {
            for task in tasks { task.cancel() }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @EnvironmentObject private var setCompletionStore: CatalogSetCompletionStore
    let catalog: any BrowseCatalogProviding
    private let recoveryGame: CardGame?
    @StateObject private var model: BrowseViewModel
    @State private var showsSetFilter = false
    @State private var isShowingSettings = false
    @State private var rootSort = CatalogBrowseSort.recommended
    @State private var rootQuotes: [String: CatalogBrowseQuote] = [:]
    @State private var rootPriceSlots: [String: [CatalogCardSummary]] = [:]
    @State private var rootAttemptedPrices: Set<String> = []
    @State private var rootPriceScope = UUID()
    @State private var rootRetryingPrices = false
    @State private var rootSortRequest: UUID?
    @State private var gameQueries: [CardGame: CatalogGameBrowseQuery] = [:]
    @FocusState private var searchFocused: Bool
    @AppStorage("pokemonMasterSetTier") private var masterSetTier: PokemonMasterSetTier = .standard

    init(
        catalog: any BrowseCatalogProviding = BrowseCatalog(),
        recoveryGame: CardGame? = nil,
        releaseRailCache: CatalogReleaseRailCache? = nil
    ) {
        var selectedCatalog = catalog
        var selectedRailCache = releaseRailCache
#if DEBUG
        if Self.isMissingArtworkReview {
            selectedCatalog = BrowseMissingArtworkCatalog()
            selectedRailCache = nil
        }
#endif
        self.catalog = selectedCatalog
        self.recoveryGame = recoveryGame
        _model = StateObject(wrappedValue: BrowseViewModel(catalog: selectedCatalog,
                                                         initialGame: recoveryGame,
                                                         includesSealedProducts: recoveryGame == nil,
                                                         releaseRailCache: selectedRailCache))
    }

#if DEBUG
    private static var isMissingArtworkReview: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(index + 1)
        else { return false }
        return arguments[index + 1] == "ArtworkUnavailable"
    }
#endif

    var body: some View {
        let priceRequest = RootPriceRequest(scope: rootPriceScope, cards: rootPriceCards)
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
        .onAppear { model.resumeSearch() }
        .onDisappear { model.suspendSearch() }
        .onChange(of: model.searchText) { _, _ in resetRootSortWork() }
        .onChange(of: model.selectedGame) { _, _ in resetRootSortWork() }
        .onChange(of: model.selectedSets) { _, _ in resetRootSortWork() }
        .onChange(of: model.selectedResultKind) { _, _ in
            rootSort = .recommended
            resetRootSortWork()
        }
        .onChange(of: model.catalogRevision) { _, _ in resetRootSortWork() }
        .onChange(of: rootSort) { _, _ in rootSortRequest = nil }
        .task(id: priceRequest) {
            await loadRootPriceQuotes(priceRequest.cards, scope: priceRequest.scope)
        }
        .task(id: rootSortRequest) {
            if let rootSortRequest { await finishRootSort(rootSortRequest) }
        }
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
            await backfillPokemonReleaseOrder()
            requestSetCompletionRebuild()
        }
        .navigationDestination(for: CatalogSet.self) { set in
            CatalogSetCardsView(set: set, catalog: model.catalog)
        }
        .task {
            await model.observeCatalogUpdates()
        }
        .onChange(of: projectionStore.revision) { _, _ in
            requestSetCompletionRebuild()
        }
        .onChange(of: model.sets) { _, _ in
            requestSetCompletionRebuild()
            if isCatalogLoadedForRail { model.rememberReleaseRail(releaseRail.sets) }
        }
        .onChange(of: model.catalogRevision) { _, _ in
            requestSetCompletionRebuild(invalidateCatalog: true)
        }
        .onChange(of: masterSetTier) { _, _ in
            requestSetCompletionRebuild()
        }
        .sheet(isPresented: $showsSetFilter) {
            CatalogSetFilterSheet(
                sets: model.gameRegistry.games(supporting: .browse).flatMap { model.sets[$0] ?? [] },
                selectedGame: model.selectedGame,
                selection: $model.selectedSets
            )
        }
    }

    @MainActor
    private func backfillPokemonReleaseOrder() async {
        guard UserDefaults.standard.integer(
            forKey: Self.pokemonReleaseOrderBackfillVersionKey
        ) < Self.pokemonReleaseOrderBackfillVersion else { return }
        guard let sets = model.sets[.pokemon], !sets.isEmpty else { return }

        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        do {
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
            try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
                try await writer.backfillPokemonReleaseOrder(sets, shouldContinue: shouldContinue)
            }
            guard !Task.isCancelled, generation.isCurrent(token) else { return }
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
                let filtersLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                filtersLayout {
                    if recoveryGame == nil {
                        Menu {
                            Button("All Games") { model.selectedGame = nil }
                            ForEach(model.gameRegistry.games(supporting: .browse)) { game in
                                Button(game.label) { model.selectedGame = game }
                            }
                        } label: {
                            Label(model.selectedGame?.label ?? "All Games", systemImage: "gamecontroller")
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.selectedResultKind != .sealed {
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
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                if recoveryGame == nil {
                    ViewThatFits(in: .horizontal) {
                        HStack { rootContentPicker; rootSortControl }
                        VStack(alignment: .leading) { rootContentPicker; rootSortControl }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var rootContentPicker: some View {
        Picker("Result type", selection: $model.selectedResultKind) {
            Text("All").tag(nil as CatalogResultKind?)
            Text("Cards").tag(CatalogResultKind.card as CatalogResultKind?)
            Text("Sealed").tag(CatalogResultKind.sealed as CatalogResultKind?)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var rootSortControl: some View {
        if model.selectedResultKind != nil { CatalogBrowseSortMenu(sort: $rootSort) }
    }

    private var rootPriceCards: [CatalogCardSummary] {
        guard model.selectedResultKind == .card, rootSort.needsPrices else { return [] }
        return model.searchResults.compactMap { result in
            if case let .card(card) = result { return card }
            return nil
        }
    }

    private struct RootPriceRequest: Equatable {
        let scope: UUID
        let cards: [CatalogCardSummary]
    }

    private struct RootSearchRow: Identifiable {
        let result: CatalogSearchResult
        let price: Double?
        let priceLabel: String?
        let pricedFinishID: String?
        let date: Date?
        var id: String { result.id }
    }

    private func resetRootSortWork() {
        rootSortRequest = nil
        rootPriceScope = UUID()
        rootQuotes = [:]
        rootPriceSlots = [:]
        rootAttemptedPrices = []
        rootRetryingPrices = false
    }

    private func loadRootPriceQuotes(_ cards: [CatalogCardSummary], scope: UUID) async {
        guard !Task.isCancelled, scope == rootPriceScope else { return }
        let newCards = cards.filter { !rootAttemptedPrices.contains($0.id) }
        let pokemonSets = Dictionary((model.sets[.pokemon] ?? []).map { ($0.catalogID, $0) },
                                     uniquingKeysWith: { first, _ in first })
        var expansion = CatalogSearchFinishExpansion()
        for start in stride(from: 0, to: newCards.count, by: 12) {
            let batch = newCards[start..<min(start + 12, newCards.count)]
            var slots: [String: [CatalogCardSummary]] = [:]
            for card in batch {
                let expanded = try? await expansion.expand([card], setsByID: pokemonSets) { set in
                    try await catalog.completeLocalCards(in: set) ?? []
                }
                guard !Task.isCancelled, scope == rootPriceScope else { return }
                slots[card.id] = (expanded ?? [card]).flatMap { printing -> [CatalogCardSummary] in
                    let finishes = CatalogBrowseFilters.explicitFinishes(of: printing)
                    return finishes.isEmpty ? [printing] : finishes
                }
            }
            rootPriceSlots.merge(slots) { _, latest in latest }
            let candidates = batch.flatMap { slots[$0.id] ?? [] }
            for await update in catalog.sortPriceUpdates(for: candidates) {
                guard !Task.isCancelled, scope == rootPriceScope else { return }
                for card in candidates {
                    rootQuotes[card.id] = CatalogBrowseQuote.merging(update, id: card.id, previous: rootQuotes[card.id])
                }
            }
            guard !Task.isCancelled, scope == rootPriceScope else { return }
            for card in candidates where rootQuotes[card.id] == nil {
                rootQuotes[card.id] = .failed
            }
            rootAttemptedPrices.formUnion(batch.map(\.id))
        }
    }

    private func retryRootPrices() async {
        let scope = rootPriceScope
        rootRetryingPrices = true
        let ids = Set(rootQuotes.filter { $0.value.canRetry }.keys)
        await catalog.resetPriceResolution(for: Array(ids))
        guard scope == rootPriceScope else { return }
        let affected = rootPriceSlots.filter { $0.value.contains(where: { ids.contains($0.id) }) }
        rootAttemptedPrices.subtract(affected.keys)
        rootRetryingPrices = false
        rootPriceScope = UUID()
    }

    private func rootResultQuote(_ result: CatalogSearchResult) -> (Double?, String?, String?) {
        switch result {
        case let .sealed(_, product): return (product.marketPriceUSD, nil, nil)
        case let .card(summary):
            guard rootSort.needsPrices else { return (nil, nil, nil) }
            let ownership = projectionStore.snapshot?.ownership
            let candidates = rootPriceSlots[summary.id] ?? [summary]
            let ranked = candidates.compactMap { card -> (Double, String?, String?)? in
                let quote = CatalogBrowsePresentation.effectiveQuote(card, quoted: rootQuotes[card.id], ownership: ownership)
                guard let amount = quote.amount else { return nil }
                let label = [card.masterSetVariant?.label, quote.status.label].compactMap { $0 }.joined(separator: " · ")
                return (amount, label.isEmpty ? nil : label, card.masterSetVariant?.id)
            }.max { $0.0 < $1.0 }
            return ranked ?? (nil, nil, nil)
        }
    }

    private func rootResultDate(_ result: CatalogSearchResult) -> Date? {
        switch result {
        case let .sealed(_, product): return product.releaseDate
        case let .card(card):
            return card.printingReleaseDate ?? model.sets[card.game]?.first { $0.catalogID == card.setID }?.releaseDate
        }
    }

    private var rootPaginationSignature: [String] {
        model.searchGames.flatMap { game in
            [model.lanes[game]?.cursor ?? "", model.sealedModel.searchLanes[game]?.nextOffset.map(String.init) ?? ""]
        }
    }

    private func finishRootSort(_ request: UUID) async {
        defer { if rootSortRequest == request { rootSortRequest = nil } }
        guard !model.isLoadingSearchFirstPages else { return }
        while rootSortRequest == request, !Task.isCancelled, model.hasSearchPagination {
            do { try await model.waitForSearchPagination() } catch { return }
            guard rootSortRequest == request, !Task.isCancelled else { return }
            let previous = rootPaginationSignature
            await model.continueSearch()
            if previous == rootPaginationSignature { return }
            await Task.yield()
        }
    }

    private var activeSetCount: Int {
        guard let game = model.selectedGame else { return model.selectedSets.count }
        return model.selectedSets.filter { $0.game == game }.count
    }

    private var isCatalogLoadedForRail: Bool {
        model.gameRegistry.games(supporting: .browse).allSatisfy { model.sets[$0] != nil }
    }

    /// While any directory is still in flight the rail's final contents are
    /// unknown, but its slot is almost always filled. Reserve it so the game
    /// rows below do not jump down under the user's finger when it arrives.
    private var isRailPending: Bool {
        model.gameRegistry.games(supporting: .browse).contains {
            model.sets[$0] == nil && model.setErrors[$0] == nil
        }
    }

    private var releaseRail: CatalogReleaseRail {
        CatalogSetOrdering.releaseRail(from: model.sets.filter { recoveryGame == nil || $0.key == recoveryGame })
    }

    private var ownership: CatalogOwnershipIndex {
        projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
    }

    private func requestSetCompletionRebuild(invalidateCatalog: Bool = false) {
        // Each returned directory is complete for that game. Prepare it now;
        // an unrelated provider can remain unavailable or pending indefinitely.
        setCompletionStore.requestRebuild(sets: model.availableCompletionSets, ownership: ownership,
            tier: masterSetTier, invalidateCatalog: invalidateCatalog,
            ownershipRevision: projectionStore.revision)
    }

    /// The live rail once every directory has loaded; until then, the rail
    /// from the previous visit. Both are keyed by set id, so when the live
    /// rail matches the cached one the swap changes nothing on screen.
    private var displayedReleaseRail: CatalogReleaseRail? {
        if isCatalogLoadedForRail { return releaseRail }
        guard isRailPending else { return nil }
        let games = Set(recoveryGame.map { [$0] } ?? model.gameRegistry.games(supporting: .browse))
        let cached = model.cachedReleaseRailSets.filter { games.contains($0.game) }
        guard !cached.isEmpty else { return nil }
        return CatalogSetOrdering.releaseRail(from: Dictionary(grouping: cached, by: \.game))
    }

    @ViewBuilder
    private var recentlyReleasedRail: some View {
        if let releaseRail = displayedReleaseRail, !releaseRail.sets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(releaseRail.title)
                    .font(.title2.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(releaseRail.sets) { set in
                            NavigationLink(value: set) {
                                CatalogSetTile(
                                    set: set,
                                    completion: setCompletionStore.currentIndex(ownershipRevision: projectionStore.revision)?.completion(
                                        for: set,
                                        tier: masterSetTier
                                    ) ?? ownership.directoryProgress(for: set),
                                    layout: .rail,
                                    showsNewBadge: releaseRail.showsNewBadges,
                                    catalog: model.catalog
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
        } else if isRailPending {
            releaseRailPlaceholder
        }
    }

    /// Mirrors `CatalogSetTile`'s rail layout (title, 112pt artwork, name,
    /// metadata, reserved notice line) so the swap to real tiles is in place.
    private var releaseRailPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Just released")
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<CatalogSetOrdering.releaseRailLimit, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.quaternary.opacity(0.65))
                                .frame(height: CatalogSetTileLayout.rail.artworkHeight)
                            Text("Placeholder set name")
                                .font(.subheadline.weight(.semibold))
                            Text("SET · 100 cards")
                                .font(.caption)
                            Text("Some cards are browse only")
                                .font(.caption.weight(.medium))
                                .hidden()
                        }
                        .containerRelativeFrame(.horizontal) { width, _ in
                            min(max(width * 0.72, 220), 300)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollDisabled(true)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recent sets")
    }

    @ViewBuilder private var gameChooser: some View {
#if DEBUG
        let rows = Self.isMissingArtworkReview ? [] : projectionStore.snapshot?.rows ?? []
#else
        let rows = projectionStore.snapshot?.rows ?? []
#endif
        Text("Browse by game")
            .font(.headline)
        ForEach(recoveryGame.map { [$0] } ?? model.gameRegistry.games(supporting: .browse)) { game in
            if let sets = model.sets[game] {
                let summary = CatalogGameSummary(game: game, sets: sets, rows: rows)
                NavigationLink {
                    CatalogGameBrowseView(
                        game: game,
                        sets: sets,
                        catalog: model.catalog,
                        sealedModel: model.sealedModel,
                        onOpenSettings: { isShowingSettings = true },
                        query: Binding(
                            get: { gameQueries[game] ?? .init() },
                            set: { gameQueries[game] = $0 }
                        )
                    )
                } label: {
                    CatalogGameRow(summary: summary, catalog: model.catalog)
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
                    .frame(minHeight: 92) // Matches CatalogGameRow so loaded rows do not shift.
            }
        }
    }

    private struct CatalogGameArtwork: Identifiable {
        let slot: Int
        let candidates: [PokemonArtworkFallbacks.Candidate]
        let placeholderText: String

        var id: Int { slot }
    }

    private struct CatalogGameRow: View {
        let summary: CatalogGameSummary
        let catalog: any BrowseCatalogProviding
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var hasArtworkSources: Bool {
            summary.recentArtworkRows.contains { $0.lowImageURL != nil || $0.highImageURL != nil }
                || summary.recentSetArtwork.contains { !($0.artworkFallbackURLs ?? []).isEmpty }
        }

        var body: some View {
            HStack(spacing: 18) {
                if !dynamicTypeSize.isAccessibilitySize && (summary.game != .onePiece || hasArtworkSources) {
                    CatalogGameFan(
                        game: summary.game,
                        ownedRows: summary.recentArtworkRows,
                        fallbackSets: summary.recentSetArtwork,
                        catalog: catalog
                    )
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.game.label)
                        .font(.headline)
                    Text(summary.subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 92)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private struct CatalogGameFan: View {
        let game: CardGame
        let ownedRows: [CollectionRow]
        let fallbackSets: [CatalogSet]
        let catalog: any BrowseCatalogProviding
        @State private var magicArtwork: [CatalogSetID: [URL]] = [:]
        @State private var loadedSources: [Int: [PokemonArtworkFallbacks.Candidate]] = [:]
        private static let horizontalOffsets: [CGFloat] = [4, 28, 52]

        private var hasLoadedArtwork: Bool {
            artworks.contains { !$0.candidates.isEmpty && loadedSources[$0.slot] == $0.candidates }
        }

        private var artworks: [CatalogGameArtwork] {
            var result = ownedRows.prefix(3).enumerated().map { index, row in
                let artwork = CatalogCardArtworkSource(
                    collectionRow: row,
                    prefersFullSize: false
                )
                return CatalogGameArtwork(
                    slot: index,
                    candidates: artwork.remoteCandidates,
                    placeholderText: row.name
                )
            }

            for set in fallbackSets where result.count < 3 {
                let candidates: [PokemonArtworkFallbacks.Candidate] = game == .magic
                    ? (magicArtwork[set.catalogID] ?? []).map { .remote($0) }
                    : (set.artworkFallbackURLs?.isEmpty == false
                        ? (set.artworkFallbackURLs ?? []).map { .remote($0) }
                        : PokemonArtworkFallbacks.setSource(for: set, kind: .logo).candidates)
                result.append(
                    CatalogGameArtwork(
                        slot: result.count,
                        candidates: candidates,
                        placeholderText: set.code
                    )
                )
            }

            while result.count < 3 {
                result.append(
                    CatalogGameArtwork(
                        slot: result.count,
                        candidates: [],
                        placeholderText: game.label
                    )
                )
            }
            return result
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                if game != .onePiece {
                    CatalogGameEmblem(game: game)
                        .frame(width: 100, height: 68)
                        .opacity(hasLoadedArtwork ? 0 : 1)
                }
                ForEach(artworks) { artwork in
                    let index = artwork.slot
                    CatalogCachedImage(
                        candidates: artwork.candidates,
                        targetPixelSize: 160,
                        showsPlaceholder: false,
                        onPhaseChange: { phase in
                            if phase == .loaded { loadedSources[index] = artwork.candidates }
                            if phase == .failed, loadedSources[index] == artwork.candidates {
                                loadedSources[index] = nil
                            }
                        }
                    )
                    .frame(width: 40, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .rotationEffect(.degrees(Double(index - 1) * 7))
                    .offset(
                        x: Self.horizontalOffsets[index],
                        y: index == 1 ? 4 : 8
                    )
                    .opacity(!artwork.candidates.isEmpty && loadedSources[index] == artwork.candidates ? 1 : 0)
                }
            }
            .frame(width: 100, height: 68, alignment: .topLeading)
            .task(id: fallbackSets.map(\.id) + ownedRows.map(\.id)) {
                guard game == .magic, ownedRows.count < 3 else { return }
                for set in fallbackSets.prefix(3 - ownedRows.count) {
                    let urls = (try? await catalog.artwork(for: set))?.cardURLs ?? []
                    guard !Task.isCancelled else { return }
                    magicArtwork[set.catalogID] = urls
                }
            }
        }
    }

    @ViewBuilder private var searchBody: some View {
        if !model.canSearch {
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
                let rows = model.searchResults.map { result in
                    let (price, label, finishID) = rootResultQuote(result)
                    return RootSearchRow(result: result, price: price, priceLabel: label, pricedFinishID: finishID,
                                         date: rootSort.usesReleaseDate ? rootResultDate(result) : nil)
                }
                let results = rootSort.ordered(rows, price: { $0.price }, date: { $0.date },
                    name: { $0.result.name }, tie: { $0.result.id < $1.result.id })
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.selectedResultKind == .card, rootSort.needsPrices {
                        if rootRetryingPrices || rootAttemptedPrices.count < rows.count {
                            Label("Checking market prices…", systemImage: "clock")
                                .font(.footnote)
                        } else if rootQuotes.values.contains(where: \.canRetry) {
                            Button("Retry Prices") { Task { await retryRootPrices() } }
                                .font(.footnote)
                        }
                    }
                    if rootSort != .recommended, model.hasSearchPagination || hasFailures || model.isLoadingSearchFirstPages {
                        HStack {
                            Text("Sorting \(results.count) loaded matches")
                            if rootSortRequest != nil {
                                Button("Cancel") { rootSortRequest = nil }
                            } else if model.hasSearchPagination {
                                Button("Sort All Results") { rootSortRequest = UUID() }
                                    .disabled(model.isLoadingSearchFirstPages)
                            }
                        }
                        .font(.footnote)
                    }
                    ForEach(results) { row in
                        NavigationLink {
                            searchDestination(for: row.result, openingFinishID: row.pricedFinishID)
                        } label: {
                            CatalogSearchResultRow(result: row.result, marketPrice: row.price,
                                priceLabel: row.priceLabel, releaseDate: row.date)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.hasSearchPagination, rootSortRequest == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                // One visible footer, with independent task identities:
                                // a newly ready lane can start without cancelling peers.
                                ForEach(model.cardSearchGames, id: \.self) { game in
                                    Color.clear.frame(width: 0, height: 0)
                                        .task(id: model.lanes[game]?.paginationKey) {
                                            await model.loadMore(game)
                                        }
                                }
                                ForEach(model.searchGames, id: \.self) { game in
                                    Color.clear.frame(width: 0, height: 0)
                                        .task(id: model.sealedModel.searchLanes[game]?.paginationKey) {
                                            await model.loadMoreSealed(game)
                                        }
                                }
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
            case let .canContinue(hasFailures):
                if hasFailures { searchPartialFailureBanner }
                Button("Continue search") { Task { await model.continueSearch() } }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
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
    private func searchDestination(for result: CatalogSearchResult, openingFinishID: String?) -> some View {
        switch result {
        case let .card(summary):
            CatalogCardDetailView(summary: summary, catalog: model.catalog, openingFinishID: openingFinishID)
        case let .sealed(game, product):
            SealedProductDetailView(game: game, product: product)
        }
    }
}

private struct CatalogSearchResultRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let result: CatalogSearchResult
    var marketPrice: Double? = nil
    var priceLabel: String? = nil
    var releaseDate: Date? = nil

    private var cardArtwork: CatalogCardArtworkSource? {
        switch result {
        case let .card(summary):
            return CatalogCardArtworkSource(
                game: summary.game,
                setCode: summary.setCode,
                collectorNumber: summary.collectorNumber,
                thumbnailURL: summary.thumbnailURL,
                imageURL: summary.imageURL,
                prefersFullSize: false,
                limitlessArtworkAuthorized: summary.limitlessArtworkAuthorized,
                providerID: summary.providerID,
                providerSetID: summary.setID.providerID
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

    private var availabilityNotice: String? {
        guard case let .card(summary) = result else { return nil }
        return summary.collectionAvailabilityNotice
    }

    private var secondaryText: String {
        switch result {
        case let .card(summary):
            return "\(summary.setName) · \(summary.setAndCollectorLabel)"
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
                let badgesLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 6))
                badgesLayout {
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

                if let marketPrice {
                    Text([marketPrice.formatted(.currency(code: "USD")), priceLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                }
                if let releaseDate {
                    Text(CatalogBrowseSort.releaseDateLabel(releaseDate))
                        .font(.caption)
                }

                if let notice = availabilityNotice {
                    Text(notice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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
                + (marketPrice.map { ", \($0.formatted(.currency(code: "USD")))" } ?? "")
                + (priceLabel.map { ", \($0)" } ?? "")
                + (releaseDate.map { ", \(CatalogBrowseSort.releaseDateLabel($0))" } ?? "")
                + (availabilityNotice.map { ", \($0)" } ?? "")
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
            let leftDate = $0.releaseDate ?? .distantPast
            let rightDate = $1.releaseDate ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            if $0.releaseOrder != $1.releaseOrder {
                return $0.releaseOrder > $1.releaseOrder
            }
            return $0.id < $1.id
        }
    }

    static func oldestFirst(_ sets: [CatalogSet]) -> [CatalogSet] {
        sets.sorted {
            switch ($0.releaseDate, $1.releaseDate) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if $0.releaseOrder != $1.releaseOrder {
                return $0.releaseOrder < $1.releaseOrder
            }
            return $0.id < $1.id
        }
    }

    static func ordered(
        _ sets: [CatalogSet],
        by sort: CatalogSetListSort,
        ownership: CatalogOwnershipIndex,
        completions: CatalogSetCompletionIndex? = nil,
        tier: PokemonMasterSetTier = .standard
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
                .map {
                    let completion = completions?.completion(for: $0, tier: tier)
                        ?? ownership.directoryProgress(for: $0)
                    return (set: $0, fraction: completion.fraction ?? -1)
                }
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
        let eligibleByGame = Dictionary(uniqueKeysWithValues: setsByGame.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { game in
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

        let fallback = setsByGame.keys.sorted(by: { $0.rawValue < $1.rawValue }).flatMap { game in
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

private struct CatalogGameBrowseQuery {
    var search = ""
    var sealedSearch = ""
    var filters = CatalogBrowseFilters.none
    var sort = CatalogBrowseSort.recommended
}

struct CatalogBrowseSortMenu: View {
    @Binding var sort: CatalogBrowseSort

    var body: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(CatalogBrowseSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Label(sort == .recommended ? "Sort" : sort.label, systemImage: "arrow.up.arrow.down")
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Sort")
        .accessibilityValue(sort.label)
        .accessibilityIdentifier("catalog-browse-sort")
    }
}

enum CatalogGameCardSearchPolicy {
    /// `normalizedQuery` is expected to have already been normalized by the
    /// owning view, so this remains a cheap gate on the task's hot path.
    static func shouldRequest(isActive: Bool, normalizedQuery: String, game: CardGame = .magic) -> Bool {
        isActive && CatalogCardSearchQuery.isEligible(normalizedQuery, for: game)
    }
}

/// A price stream may outlive the page that requested it. Keep the two pieces
/// of identity together so every incremental emission is rejected when either
/// the card content or the owning request has changed.
struct CatalogPriceRequestIdentity: Equatable, Sendable {
    let contentGeneration: UUID
    let requestID: UUID

    func matches(
        contentGeneration: UUID,
        requestID: UUID?,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && self.contentGeneration == contentGeneration
            && self.requestID == requestID
    }
}

/// State owned by one set-screen price request. Keeping the lifecycle in a
/// value type makes the content-invalidation rule explicit: a late completion
/// from an old page cannot turn a new page back into a loaded state.
struct CatalogPriceLoadState: Equatable, Sendable {
    private(set) var requestID: UUID?
    private(set) var isLoading = false
    private(set) var hasLoadedPrices = false

    mutating func begin(requestID: UUID) {
        self.requestID = requestID
        isLoading = true
        hasLoadedPrices = false
    }

    mutating func invalidate() {
        requestID = nil
        isLoading = false
        hasLoadedPrices = false
    }

    mutating func finish(requestID: UUID, loaded: Bool) {
        guard self.requestID == requestID else { return }
        self.requestID = nil
        isLoading = false
        hasLoadedPrices = loaded
    }
}

/// Keep catalog search in the screen's layout. Navigation-bar search controllers
/// survive pushes in this shared stack and can leave stale scroll insets or a
/// search presentation intercepting touches after a pop.
private struct CatalogSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }
                .accessibilityLabel(prompt)
            // Reserve the clear target while empty so the first/last character
            // doesn't resize the native text input during keyboard layout.
            Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty)
                .accessibilityHidden(text.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemBackground))
        .onChange(of: isFocused) { _, focused in
            PerformanceSignpost.emitEvent("Browse.searchFocus", "focused=\(focused)")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // End the input session before UIKit prepares the background scene
            // snapshot. Keep the query, but don't carry a live search keyboard
            // through the snapshot's trait/layout overrides.
            if isFocused { isFocused = false }
        }
        .onDisappear { isFocused = false }
    }
}

private struct CatalogGameBrowseView: View {
    @Environment(\.catalogCardSelection) private var catalogCardSelection
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    @ObservedObject var sealedModel: SealedBrowseModel
    let onOpenSettings: () -> Void
    @Binding var query: CatalogGameBrowseQuery

    @State private var contentKind: CatalogGameContentKind = .cards
    @State private var isShowingFilters = false
    @State private var facets = CatalogBrowseFacets()
    @State private var checklistFinishes: [PhysicalVariant] = []

    private var orderedSets: [CatalogSet] { CatalogSetOrdering.newestFirst(sets) }
    private var finishOptions: [PhysicalVariant] {
        facets.finishOptions(base: PhysicalVariant.selectable(for: game, registry: catalog.gameRegistry),
                             catalog: checklistFinishes, for: game)
    }

    var body: some View {
        VStack(spacing: 0) {
            if catalogCardSelection == nil, catalog.gameRegistry.supports(game, .sealed) {
                Picker("Catalog content", selection: $contentKind) {
                    ForEach(CatalogGameContentKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            ZStack {
                // Keep this subtree alive while Sealed is visible. Its loaded
                // pages and pagination cursor are local state and must survive
                // the segment switch.
                CatalogGameCardsView(
                    game: game,
                    sets: sets,
                    catalog: catalog,
                    isActive: contentKind == .cards,
                    search: $query.search,
                    filters: query.filters,
                    sort: query.sort,
                    onClearFilters: { query.filters = .none },
                    onCardsLoaded: { facets.record($0) }
                )
                .opacity(contentKind == .cards ? 1 : 0)
                .allowsHitTesting(contentKind == .cards)
                .accessibilityHidden(contentKind != .cards)

                if contentKind == .sealed {
                    SealedSetDirectoryContent(
                        game: game,
                        model: sealedModel,
                        searchText: query.sealedSearch,
                        onOpenSettings: onOpenSettings
                    )
                }
            }
        }
        .navigationTitle(game.label)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CatalogSearchField(
                    text: contentKind == .cards ? $query.search : $query.sealedSearch,
                    prompt: "Search \(game.label) \(contentKind == .cards ? "cards" : "sets")"
                )
                if contentKind == .cards, query.filters.isActive {
                    CatalogBrowseFilterChips(filters: $query.filters, sets: orderedSets, finishOptions: finishOptions)
                }
                if contentKind == .cards {
                    HStack {
                        Spacer()
                        CatalogBrowseSortMenu(sort: $query.sort)
                    }
                    .padding(.horizontal, 16)
                    .background(Color(uiColor: .systemBackground))
                }
            }
        }
        .modifier(CollectionFilterPresentation(
            isPresented: $isShowingFilters,
            filters: CatalogBrowseFilterSheet(
                isPresented: $isShowingFilters,
                filters: $query.filters,
                game: game,
                sets: orderedSets,
                finishOptions: finishOptions,
                treatmentOptions: facets.treatmentOptions(for: game)
            )
        ))
        .toolbar {
            if contentKind == .cards {
                ToolbarItem(placement: .topBarTrailing) {
                    CatalogBrowseFilterButton(activeCount: query.filters.activeCount) { isShowingFilters = true }
                }
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
        .task {
            guard game == .pokemon else { return }
            let options = await PokemonBrowseFinishCatalog.bundled.value
            guard !Task.isCancelled else { return }
            checklistFinishes = options
        }
    }
}

/// A new cursor waits for layout before requesting its page.
/// Lazy-container prefetch alone doesn't establish that the footer is visible.
private struct CatalogPaginationFooter: View {
    let requestID: String
    let viewport: CGRect
    let load: () async -> Void
    @State private var isVisible = false

    var body: some View {
        indicator
            .id("catalog-pagination-footer")
            .task(id: "\(requestID)-\(isVisible)") {
                // Allow the newly appended grid to move the footer out of the
                // viewport before starting another request.
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled, isVisible else { return }
                await load()
            }
    }

    @ViewBuilder
    private var indicator: some View {
        let viewport = viewport
        if #available(iOS 18.0, *) {
            ProgressView().padding()
                .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        } else {
            ProgressView().padding()
                .onGeometryChange(for: Bool.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    return !viewport.isEmpty && !frame.isEmpty && viewport.intersects(frame)
                } action: { isVisible = $0 }
        }
    }
}

/// The rectangle is needed only by the iOS 17 pagination fallback. On newer
/// systems scroll visibility drives pagination directly; observing geometry
/// there would invalidate the entire card screen for every keyboard frame.
private struct CatalogPaginationViewport: ViewModifier {
    @Binding var viewport: CGRect

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
        } else {
            content.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { viewport = $0 }
        }
    }
}

struct CatalogGameCardsView: View {
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    let isActive: Bool
    @Binding var search: String
    var filters: CatalogBrowseFilters = .none
    var sort: CatalogBrowseSort = .recommended
    var onClearFilters: () -> Void = {}
    /// Every page the grid receives, so the owner can learn which finishes exist.
    var onCardsLoaded: ([CatalogCardSummary]) -> Void = { _ in }

    @State private var cards: [CatalogCardSummary] = []
    /// The filtered walk runs over `filteredSets`, not `orderedSets`, so it
    /// keeps its own position. `nil` means every chosen set has been read.
    @State private var filteredPosition: CatalogSetWalkPosition? = .start
    @State private var filteredStoppedAtLimit = false
    @State private var filteredScannedCount = 0
    @State private var visitedSetPositions: Set<CatalogSetWalkPosition> = []
    @State private var searchStoppedAtLimit = false
    @State private var nextSetIndex = 0
    @State private var activeSet: CatalogSet?
    @State private var refreshedSets: [CatalogSet]?
    @State private var directoryNeedsReload = false
    @State private var contentRevision = 0
    @State private var viewport = CGRect.zero
    @State private var cursor: String?
    @State private var visitedDefaultCursors: Set<String> = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchCards: [CatalogCardSummary] = []
    @State private var searchCursor: String?
    @State private var searchIsLoading = false
    @State private var searchError: String?
    @State private var searchRevision = 0
    @State private var searchRequestKey: UUID?
    @State private var visitedSearchPositions: Set<CatalogSearchPosition> = []
    @State private var isVisible = false
    @State private var ownershipRevision: UInt?
    @State private var resultRows: [CatalogBrowsePresentation.Row] = []
    @State private var visibleCardID: String?
    @State private var priceCandidates: [CatalogCardSummary] = []
    @State private var visiblePriceSlots: [String: CatalogCardSummary] = [:]
    /// First-appearance order, so the most recently shown tiles price first.
    @State private var visiblePriceOrder: [String] = []
    @State private var quotes: [String: CatalogBrowseQuote] = [:]
    @State private var attemptedPrices: Set<String> = []
    @State private var priceScope = UUID()
    @State private var priceRevision = 0
    @State private var priceRetry = 0
    @State private var isLoadingPrices = false
    @State private var activePriceLoad: UUID?
    @State private var completeSortRequest: UUID?
    @State private var localSortRequest: UUID?
    @State private var skippedSets = false
    @State private var activeSearchQuery: String?
    @State private var catalogUpdateSequence: UInt64?

    private struct PresentationRequest: Equatable {
        let cards: [CatalogCardSummary]
        let sets: [CatalogSet]
        let filters: CatalogBrowseFilters
        let sort: CatalogBrowseSort
        let ownershipRevision: UInt?
        let priceScope: UUID
        let priceRevision: Int
        let isActive: Bool
    }

    /// Deliberately excludes the card list: a newly visible tile or page must
    /// join the running loader rather than cancel its in-flight provider batch.
    private struct PriceRequest: Equatable {
        let scope: UUID
        let retry: Int
        let isActive: Bool
        let pricesAllCandidates: Bool
        let hasPending: Bool
    }

    private var pricesAllCandidates: Bool { sort.needsPrices || filters.needsPrices }

    /// Unattempted slots in request order: every candidate for a price sort or
    /// filter, otherwise the visible tiles, most recently shown first.
    private var pendingPriceSlots: [CatalogCardSummary] {
        if pricesAllCandidates { return priceCandidates.filter { !attemptedPrices.contains($0.id) } }
        return visiblePriceOrder.reversed().compactMap { id in
            attemptedPrices.contains(id) ? nil : visiblePriceSlots[id]
        }
    }

    private var hasUnattemptedPriceCandidates: Bool {
        priceCandidates.contains { !attemptedPrices.contains($0.id) }
    }

    private var orderedSets: [CatalogSet] {
        CatalogSetOrdering.newestFirst(refreshedSets ?? sets)
    }

    private var filteredSets: [CatalogSet] { filters.restrictedSets(orderedSets) }

    private var ownershipIndex: CatalogOwnershipIndex {
        projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
    }

    private var normalizedSearch: String {
        CardNameSearch.normalize(search)
    }

    private var providerSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchText: Bool { !normalizedSearch.isEmpty }
    private var isSearchQuery: Bool { CatalogCardSearchQuery.isEligible(normalizedSearch, for: game) }
    private var hasMoreSets: Bool {
        activeSet != nil || nextSetIndex < orderedSets.count
    }

    private var indexAfterFailedSet: Int? {
        guard !directoryNeedsReload, error != nil else { return nil }
        let index = nextSetIndex + (activeSet == nil ? 1 : 0)
        return index < orderedSets.count ? index : nil
    }

    private var defaultPaginationKey: String {
        let nextSetID = activeSet?.id ?? orderedSets.dropFirst(nextSetIndex).first?.id ?? ""
        return "\(contentRevision)-\(nextSetID)-\(cursor ?? "")"
    }

    var body: some View {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        let request = PresentationRequest(cards: hasSearchText ? searchCards : cards, sets: orderedSets,
            filters: filters, sort: sort, ownershipRevision: projectionStore.revision, priceScope: priceScope,
            priceRevision: priceRevision, isActive: isActive)
        let priceRequest = PriceRequest(scope: priceScope, retry: priceRetry, isActive: isActive,
                                        pricesAllCandidates: pricesAllCandidates,
                                        hasPending: !pendingPriceSlots.isEmpty)
        return ScrollView {
            LazyVStack {
                resultStatus
                if hasSearchText {
                    searchContent(owned: owned)
                } else {
                    defaultContent(owned: owned)
                }
            }
        }
        .modifier(CatalogPaginationViewport(viewport: $viewport))
        .scrollPosition(id: $visibleCardID, anchor: .top)
        .task(id: request) { await preparePresentation(request, ownership: owned) }
        .task(id: priceRequest) { await loadResultPrices(request: priceRequest) }
        .task(id: completeSortRequest) {
            if let completeSortRequest { await completeSort(completeSortRequest) }
        }
        .task(id: "\(contentRevision)-\(isActive)-\(hasSearchText)") {
            if isActive, cards.isEmpty { await retryDefault() }
        }
        .onChange(of: providerSearch) { _, _ in
            resetResultPrices()
            invalidateDefaultRequest()
        }
        .onChange(of: sort) { _, _ in completeSortRequest = nil }
        .onChange(of: isActive) { _, active in
            invalidateDefaultRequest()
            if active { refreshOwnershipFilter() }
            else { completeSortRequest = nil }
        }
        .onAppear {
            isVisible = true
            refreshOwnershipFilter()
        }
        .onDisappear {
            isVisible = false
            invalidateDefaultRequest()
            completeSortRequest = nil
            searchRequestKey = nil
            searchIsLoading = false
        }
        .onChange(of: projectionStore.cardOwnershipRevision) { _, _ in refreshOwnershipFilter() }
        .onChange(of: sets) { oldSets, newSets in
            guard newSets != refreshedSets else { return }
            let previous = refreshedSets ?? oldSets
            refreshedSets = nil
            if directoryNeedsReload {
                directoryNeedsReload = false
                resetContent()
            } else {
                updateVisibleContent(from: previous, to: newSets, publication: nil)
            }
        }
        .task { await observeCatalogUpdates() }
        .task(id: "\(isActive)-\(providerSearch)-\(searchRevision)") {
            guard isActive else { return }
            guard CatalogGameCardSearchPolicy.shouldRequest(
                isActive: isActive,
                normalizedQuery: normalizedSearch,
                game: game
            ) else {
                clearSearchResults()
                return
            }
            let query = providerSearch
            if activeSearchQuery == query, !searchCards.isEmpty {
                if searchRequestKey == nil { searchRequestKey = UUID() }
                return
            }
            clearSearchResults()
            activeSearchQuery = query
            let requestKey = UUID()
            searchRequestKey = requestKey
            searchIsLoading = true
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await loadSearchPage(query: query, requestKey: requestKey, cursor: nil)
        }
        .onChange(of: filters) { _, _ in
            // A filter change is a new question: start both walks over.
            ownershipRevision = projectionStore.cardOwnershipRevision
            resetContent()
        }
        .safeAreaPadding(.bottom, 24)
    }

    private func preparePresentation(_ request: PresentationRequest, ownership: CatalogOwnershipIndex) async {
        guard request.isActive else { return }
        let quoteSnapshot = quotes
        let projection = Task.detached(priority: .userInitiated) {
            let candidates = CatalogBrowsePresentation.candidates(request.cards, filters: request.filters, ownership: ownership)
            guard !Task.isCancelled else { return (candidates, [CatalogBrowsePresentation.Row]()) }
            let rows = CatalogBrowsePresentation.rows(candidates, filters: request.filters, sort: request.sort,
                sets: request.sets, quotes: quoteSnapshot, ownership: ownership)
            return (candidates, rows)
        }
        let result = await withTaskCancellationHandler { await projection.value } onCancel: { projection.cancel() }
        guard !Task.isCancelled, request.priceScope == priceScope else { return }
        if priceCandidates != result.0 { priceCandidates = result.0 }
        resultRows = result.1
    }

    private func resetResultPrices() {
        completeSortRequest = nil
        priceScope = UUID()
        priceCandidates = []
        visiblePriceSlots = [:]
        visiblePriceOrder = []
        resultRows = []
        visibleCardID = nil
        quotes = [:]
        attemptedPrices = []
        isLoadingPrices = false
        activePriceLoad = nil
    }

    private func loadResultPrices(request: PriceRequest) async {
        guard request.isActive, request.scope == priceScope, !pendingPriceSlots.isEmpty else { return }
        let load = UUID()
        activePriceLoad = load
        isLoadingPrices = true
        defer {
            if activePriceLoad == load {
                activePriceLoad = nil
                isLoadingPrices = false
            }
        }
        // Re-read the queue per batch so tiles or pages that arrived meanwhile
        // are picked up without restarting this task.
        while !Task.isCancelled, request.scope == priceScope {
            let batch = Array(pendingPriceSlots.prefix(24))
            guard !batch.isEmpty else { return }
            for await update in catalog.sortPriceUpdates(for: batch) {
                guard !Task.isCancelled, request.scope == priceScope else { return }
                for card in batch {
                    quotes[card.id] = CatalogBrowseQuote.merging(update, id: card.id, previous: quotes[card.id])
                }
                priceRevision += 1
            }
            guard !Task.isCancelled, request.scope == priceScope else { return }
            for card in batch where quotes[card.id] == nil || quotes[card.id]?.status == .pending {
                quotes[card.id] = .failed
            }
            attemptedPrices.formUnion(batch.map(\.id))
            priceRevision += 1
            await Task.yield()
        }
    }

    private var hasMoreForSort: Bool {
        hasSearchText ? searchCursor != nil : (filters.isActive ? filteredPosition != nil : hasMoreSets)
    }

    private var hasResultCandidates: Bool { !(hasSearchText ? searchCards : cards).isEmpty }
    private var isPartialSort: Bool {
        hasMoreForSort || (hasSearchText ? searchError != nil : skippedSets || error != nil)
    }

    private var isCheckingFilterPrices: Bool {
        filters.needsPrices && (isLoadingPrices || hasUnattemptedPriceCandidates)
    }

    private var hasFailedFilterPrices: Bool {
        filters.needsPrices && quotes.values.contains { $0.status == .failed }
    }

    @ViewBuilder private var resultStatus: some View {
        if hasResultCandidates || (sort != .recommended && hasMoreForSort) {
            if sort != .recommended, isPartialSort {
                HStack {
                    if completeSortRequest != nil {
                        ProgressView()
                        Text("Loading more matches…")
                        Button("Cancel") { completeSortRequest = nil }
                    } else {
                        Text("Sorting \(resultRows.count) loaded matches")
                        if hasMoreForSort {
                            Button("Sort All Results") { completeSortRequest = UUID() }
                                .disabled(isLoading || searchIsLoading)
                        }
                    }
                }
                .font(.footnote)
                .padding(.horizontal, 16)
            }
            if pricesAllCandidates, isLoadingPrices || hasUnattemptedPriceCandidates {
                Label("Checking market prices…", systemImage: "clock")
                    .font(.footnote)
            } else if quotes.values.contains(where: \.canRetry) {
                Button("Retry Prices") {
                    Task {
                        let scope = priceScope
                        let ids = quotes.filter { $0.value.canRetry }.map(\.key)
                        await catalog.resetPriceResolution(for: ids)
                        guard scope == priceScope else { return }
                        attemptedPrices.subtract(ids)
                        priceRetry += 1
                    }
                }
                .font(.footnote)
            }
        }
    }

    private func completeSort(_ request: UUID) async {
        defer { if completeSortRequest == request { completeSortRequest = nil } }
        if !hasSearchText, !skippedSets, error == nil,
           await loadCompleteLocalScope(request: request) { return }
        while !Task.isCancelled, completeSortRequest == request, hasMoreForSort,
              !searchIsLoading, !isLoading {
            if hasSearchText {
                let previous = searchCursor
                await loadMoreSearch(query: providerSearch)
                if searchError != nil || searchCursor == previous { return }
            } else {
                let previousPosition = filteredPosition
                let previousKey = defaultPaginationKey
                await loadDefaultMore()
                let advanced = filters.isActive ? filteredPosition != previousPosition : defaultPaginationKey != previousKey
                if error != nil || !advanced { return }
            }
            await Task.yield()
        }
    }

    private func loadCompleteLocalScope(request: UUID) async -> Bool {
        guard !isLoading else { return false }
        let revision = contentRevision
        let scope = filters.isActive ? filteredSets : orderedSets
        let owned = ownershipIndex
        let ownershipRevision = projectionStore.cardOwnershipRevision
        isLoading = true
        localSortRequest = request
        defer {
            if localSortRequest == request { localSortRequest = nil }
            if revision == contentRevision { isLoading = false }
        }
        var allCards: [CatalogCardSummary] = []
        for set in scope {
            guard !Task.isCancelled, completeSortRequest == request, revision == contentRevision else { return false }
            guard let local = try? await catalog.completeLocalCards(in: set) else { return false }
            allCards += local
        }
        guard !Task.isCancelled, completeSortRequest == request, revision == contentRevision,
              filters.ownership == .all || ownershipRevision == projectionStore.cardOwnershipRevision else { return false }
        let candidates = allCards.filter {
            !filters.matchingPrintings(for: $0, isOwned: owned.owns, expandFinishes: true).isEmpty
        }
        cards = deduplicated(candidates)
        onCardsLoaded(cards)
        nextSetIndex = orderedSets.count
        activeSet = nil
        cursor = nil
        filteredPosition = nil
        filteredStoppedAtLimit = false
        filteredScannedCount = allCards.count
        return true
    }

    private func refreshOwnershipFilter() {
        guard isVisible, isActive else { return }
        let previous = ownershipRevision
        ownershipRevision = projectionStore.cardOwnershipRevision
        if filters.ownership != .all, let previous, previous != ownershipRevision {
            resetContent()
        }
    }

    @ViewBuilder
    private func defaultContent(owned: CatalogOwnershipIndex) -> some View {
        if cards.isEmpty && isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(filters.isActive ? "Finding matching cards…" : "Loading \(game.label) cards…")
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
            Button("Retry") { Task { await retryDefault() } }
                .buttonStyle(.borderedProminent)
            skipFailedSetButton
        } else {
            if let error, !cards.isEmpty {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if resultRows.isEmpty, filters.isActive, !isLoadingPrices,
               (cards.isEmpty || !priceCandidates.isEmpty && !hasUnattemptedPriceCandidates) {
                ContentUnavailableView(
                    hasFailedFilterPrices ? "Some prices couldn’t be checked"
                        : filteredPosition == nil ? "No cards match these filters" : "No matches yet",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(hasFailedFilterPrices ? "Retry prices to check more cards against this filter."
                        : filteredPosition == nil ? "Try removing a filter."
                            : "Checked \(filteredScannedCount) cards so far.")
                )
                Button("Clear Filters", action: onClearFilters)
                    .buttonStyle(.bordered)
            } else if cards.isEmpty {
                ContentUnavailableView(
                    "No cards found",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("This game has no cards in the catalogue.")
                )
            } else if !resultRows.isEmpty {
                CatalogCardGrid(
                    groups: resultRows.map(\.group),
                    catalog: catalog,
                    owned: owned,
                    browseRows: resultRows,
                    showsReleaseDate: sort.usesReleaseDate,
                    onTileVisible: requestPricesForTile
                )
                    .padding(12)
                    .contentWidthLimit(.wide)
            }
            if error != nil, !cards.isEmpty {
                Button("Retry") { Task { await loadDefaultMore() } }
                    .buttonStyle(.bordered)
                skipFailedSetButton
            } else if completeSortRequest == nil, filters.isActive {
                filteredFooter
            } else if completeSortRequest == nil, hasMoreSets, nextSetIndex > 0 || !cards.isEmpty {
                CatalogPaginationFooter(requestID: defaultPaginationKey, viewport: viewport) { await loadDefaultMore() }
            }
        }
    }

    /// A selective filter pauses after a bounded batch rather than reading the
    /// whole catalog behind the user's back.
    @ViewBuilder
    private var filteredFooter: some View {
        if filteredPosition != nil {
            if filters.needsPrices, resultRows.isEmpty, isCheckingFilterPrices {
                EmptyView()
            } else if filteredStoppedAtLimit || (filters.needsPrices && resultRows.isEmpty) {
                Button("Keep Searching More Sets") { Task { await loadDefaultMore() } }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 8)
            } else if !cards.isEmpty {
                CatalogPaginationFooter(
                    requestID: "\(contentRevision)-filtered-\(String(describing: filteredPosition))", viewport: viewport
                ) { await loadDefaultMore() }
            }
        }
    }

    @ViewBuilder
    private var skipFailedSetButton: some View {
        if filters.isActive {
            if error != nil, let next = filteredPosition?.skippingSet(setCount: filteredSets.count) {
                Button("Skip this set") {
                    Task {
                        filteredPosition = next
                        skippedSets = true
                        error = nil
                        await loadDefaultMore()
                    }
                }
                .buttonStyle(.bordered)
            }
        } else if indexAfterFailedSet != nil {
            Button("Skip this set") {
                Task {
                    guard let index = indexAfterFailedSet else { return }
                    nextSetIndex = index
                    skippedSets = true
                    activeSet = nil
                    cursor = nil
                    visitedDefaultCursors = []
                    await loadDefaultMore()
                }
            }
            .buttonStyle(.bordered)
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
            Button("Retry") {
                if searchCursor != nil {
                    Task { await loadMoreSearch(query: providerSearch) }
                } else {
                    searchRevision += 1
                }
            }
                .buttonStyle(.borderedProminent)
        } else if searchCards.isEmpty, searchCursor != nil, completeSortRequest == nil {
            Button("Continue search") { Task { await loadMoreSearch(query: providerSearch) } }
                .buttonStyle(.borderedProminent)
        } else if resultRows.isEmpty, filters.isActive, searchCursor == nil, searchError == nil,
                  !isLoadingPrices, (searchCards.isEmpty || !priceCandidates.isEmpty && !hasUnattemptedPriceCandidates) {
            ContentUnavailableView(
                hasFailedFilterPrices ? "Some prices couldn’t be checked" : "No matching cards",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(hasFailedFilterPrices ? "Retry prices to check more cards against this filter."
                    : "Nothing matches this search with your filters.")
            )
            Button("Clear Filters", action: onClearFilters)
                .buttonStyle(.bordered)
        } else if searchCards.isEmpty {
            ContentUnavailableView(
                "No matching cards",
                systemImage: "magnifyingglass",
                description: Text(game == .pokemon ? "Try a card name or collector number." : "Try another card name.")
            )
        } else {
            if !resultRows.isEmpty {
                CatalogCardGrid(
                    groups: resultRows.map(\.group), catalog: catalog, owned: owned,
                    browseRows: resultRows, showsReleaseDate: sort.usesReleaseDate,
                    onTileVisible: requestPricesForTile
                )
                .padding(12)
                .contentWidthLimit(.wide)
            }
            if let searchError {
                Text(searchError).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { Task { await loadMoreSearch(query: providerSearch) } }
                    .buttonStyle(.bordered)
            } else if completeSortRequest == nil, searchCursor != nil,
                      filters.needsPrices && resultRows.isEmpty && isCheckingFilterPrices {
                EmptyView()
            } else if completeSortRequest == nil, searchCursor != nil,
                      searchStoppedAtLimit || (filters.needsPrices && resultRows.isEmpty) {
                Button("Keep Searching") { Task { await loadMoreSearch(query: providerSearch) } }
                    .buttonStyle(.bordered)
            } else if completeSortRequest == nil, searchCursor != nil {
                CatalogPaginationFooter(
                    requestID: "\(searchRequestKey?.uuidString ?? "")-\(searchCursor ?? "")", viewport: viewport
                ) { await loadMoreSearch(query: providerSearch) }
            }
        }
    }

    private func loadDefaultMore() async {
        if filters.isActive {
            await loadFilteredMore()
            return
        }
        guard isActive, !isLoading, !hasSearchText, hasMoreSets else { return }
        let revision = contentRevision
        let set = activeSet ?? orderedSets[nextSetIndex]
        let startedNewSet = activeSet == nil
        isLoading = true
        error = nil
        defer { if revision == contentRevision { isLoading = false } }
        do {
            let page = try await catalog.cards(in: set, cursor: cursor)
            // The revision is the staleness guard. A footer task cancelled only
            // because the grid re-laid out must keep its page, or the unchanged
            // cursor refetches it.
            guard revision == contentRevision else { return }
            if let next = page.nextCursor, next == cursor || visitedDefaultCursors.contains(next) {
                throw BrowseCatalogError.badResponse
            }
            if let cursor { visitedDefaultCursors.insert(cursor) }
            if startedNewSet { nextSetIndex += 1 }
            cards = deduplicated(cards + page.items)
            onCardsLoaded(page.items)
            cursor = page.nextCursor
            activeSet = page.nextCursor == nil ? nil : set
            if activeSet == nil { visitedDefaultCursors = [] }
        } catch {
            guard !Task.isCancelled, revision == contentRevision else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadFilteredMore() async {
        guard isActive, !isLoading, !hasSearchText, let start = filteredPosition else { return }
        let sets = filteredSets
        guard start.setIndex < sets.count else {
            filteredPosition = nil
            return
        }
        let revision = contentRevision
        let catalog = catalog
        let owned = ownershipIndex
        let capturedOwnershipRevision = projectionStore.cardOwnershipRevision
        isLoading = true
        error = nil
        defer { if revision == contentRevision { isLoading = false } }
        var discoveryFilters = filters
        discoveryFilters.price = nil
        let fill = await CatalogFilteredPager.fill(
            from: start,
            filters: discoveryFilters,
            expandFinishes: true,
            visitedPositions: visitedSetPositions,
            existingIDs: Set(cards.map(\.id)),
            loadPage: CatalogFilteredPager.setWalkLoader(sets: sets) { set, cursor in
                try await catalog.cards(in: set, cursor: cursor)
            },
            isOwned: { owned.owns($0) },
            resolvePrices: { _ in [:] },
            isCurrent: {
                revision == contentRevision && (filters.ownership == .all || projectionStore.cardOwnershipRevision == capturedOwnershipRevision)
            }
        )
        guard let fill, !Task.isCancelled, revision == contentRevision else { return }
        cards += fill.matches
        onCardsLoaded(fill.matches)
        filteredPosition = fill.position
        visitedSetPositions = fill.visitedPositions
        filteredStoppedAtLimit = fill.stoppedAtPageLimit
        filteredScannedCount += fill.scannedCount
        if let failure = fill.error { error = failure.localizedDescription }
    }

    private func searchStep(query: String, cursor: String?, isCurrent: () -> Bool) async
        -> CatalogFilteredPager.Fill<CatalogSearchPosition>? {
        let catalog = catalog
        let game = game
        let filters = filters
        let expands = game == .pokemon
        let requiresFinishEvidence = CatalogSearchFinishExpansion.needsExpansion(game: game, filters: filters)
            || filters.needsPrices
        let eligibleSets = expands || !filters.pokemonPrintRuns.isEmpty ? filteredSets : []
        let setsByID = Dictionary(eligibleSets.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        let searchSetIDs = filters.pokemonPrintRuns.isEmpty ? filters.setIDs : Set(setsByID.keys)
        if !filters.pokemonPrintRuns.isEmpty, searchSetIDs.isEmpty {
            return .init()
        }
        let owned = ownershipIndex
        let capturedOwnershipRevision = projectionStore.cardOwnershipRevision
        var expansion = CatalogSearchFinishExpansion()
        var discoveryFilters = filters
        discoveryFilters.price = nil
        return await CatalogFilteredPager.fill(
            from: CatalogSearchPosition(cursor: cursor),
            filters: discoveryFilters,
            limits: filters.isActive ? .init() : .init(targetMatchCount: 1, maxPagesPerFill: 1),
            expandFinishes: true,
            visitedPositions: visitedSearchPositions,
            existingIDs: Set(searchCards.map(\.id)),
            loadPage: CatalogFilteredPager.searchLoader { cursor in
                let page = try await catalog.searchCards(
                    named: query, game: game, setIDs: searchSetIDs, cursor: cursor
                )
                guard expands else { return page }
                let items = try await expansion.expand(page.items, setsByID: setsByID) { set in
                    if let slots = try? await catalog.completeLocalCards(in: set) { return slots }
                    guard requiresFinishEvidence else { return [] }
                    return try await Self.allCards(in: set, catalog: catalog)
                }
                return CatalogPage(items: items, nextCursor: page.nextCursor)
            },
            isOwned: { owned.owns($0) },
            resolvePrices: { _ in [:] },
            isCurrent: {
                isCurrent() && (filters.ownership == .all || projectionStore.cardOwnershipRevision == capturedOwnershipRevision)
            }
        )
    }

    /// A Pokémon set page is local and normally one page; follow any cursor anyway.
    private static func allCards(in set: CatalogSet, catalog: any BrowseCatalogProviding) async throws -> [CatalogCardSummary] {
        let result = await CatalogSetPageLoader.collect(from: nil, limit: nil) { cursor in
            try await catalog.cards(in: set, cursor: cursor)
        }
        if let error = result.error { throw error }
        return result.items
    }

    private func resetContent() {
        resetDefaultContent()
        resetSearchContent()
    }

    private func resetDefaultContent() {
        invalidateDefaultRequest()
        if !hasSearchText { resetResultPrices() }
        cards = []
        skippedSets = false
        nextSetIndex = 0
        activeSet = nil
        cursor = nil
        visitedDefaultCursors = []
        error = nil
        filteredPosition = .start
        visitedSetPositions = []
        filteredStoppedAtLimit = false
        filteredScannedCount = 0
    }

    private func resetSearchContent() {
        clearSearchResults()
        searchRevision += 1
    }

    private func clearSearchResults() {
        searchRequestKey = nil
        activeSearchQuery = nil
        if hasSearchText { resetResultPrices() }
        searchCards = []
        searchCursor = nil
        visitedSearchPositions = []
        searchError = nil
        searchIsLoading = false
        searchStoppedAtLimit = false
    }

    private func updateVisibleContent(
        from oldDirectory: [CatalogSet], to newDirectory: [CatalogSet], publication: BrowseCatalogUpdate?
    ) {
        let oldOrder = CatalogSetOrdering.newestFirst(oldDirectory)
        let newOrder = CatalogSetOrdering.newestFirst(newDirectory)
        let oldScope = filters.isActive ? filters.restrictedSets(oldOrder) : oldOrder
        let newScope = filters.isActive ? filters.restrictedSets(newOrder) : newOrder
        let prefixCount: Int
        if localSortRequest != nil {
            // A full local snapshot can already contain any set in scope.
            prefixCount = max(oldScope.count, newScope.count)
        } else if filters.isActive {
            // An in-flight fill can read several consecutive sets before it
            // publishes its position. Protect that entire window.
            let pending = isLoading ? CatalogFilteredPager.Limits().maxPagesPerFill : 1
            prefixCount = filteredPosition.map { $0.setIndex + pending } ?? max(oldScope.count, newScope.count)
        } else {
            let pending = activeSet == nil && (isLoading || error != nil) ? 1 : 0
            prefixCount = nextSetIndex + pending
        }
        let prefix = oldScope.prefix(prefixCount)
        if !prefix.elementsEqual(newScope.prefix(prefixCount))
            || (oldScope.isEmpty && !newScope.isEmpty)
            || prefix.contains(where: { publication?.affects(game: game, providerSetID: $0.providerID) == true }) {
            resetDefaultContent()
        }

        let oldIDs = Set(oldScope.map(\.catalogID))
        let newIDs = Set(newScope.map(\.catalogID))
        let affectsSearchScope = newIDs.contains { id in
            publication?.affects(game: game, providerSetID: id.providerID) == true
        }
        let canGainMatches = isSearchQuery && (game == .pokemon || filters.isActive || searchCards.isEmpty)
            && affectsSearchScope
        if oldIDs != newIDs || (affectsSearchScope && searchIsLoading)
            || canGainMatches
            || searchCards.contains(where: { publication?.affects(game: game, providerSetID: $0.setID.providerID) == true }) {
            resetSearchContent()
        }
    }

    private func invalidateDefaultRequest() {
        contentRevision += 1
        localSortRequest = nil
        isLoading = false
    }

    private func observeCatalogUpdates() async {
        let (updates, baseline) = await catalog.catalogUpdates(after: catalogUpdateSequence)
        guard !Task.isCancelled else { return }
        if catalogUpdateSequence == nil { catalogUpdateSequence = baseline }
        for await update in updates {
            guard !Task.isCancelled else { return }
            if update.affects(game: game) {
                if update.providerSetID != nil, !directoryNeedsReload {
                    let directory = try? await catalog.sets(for: game)
                    guard !Task.isCancelled else { return }
                    let previous = orderedSets
                    if let directory { refreshedSets = directory }
                    updateVisibleContent(from: previous, to: directory ?? previous, publication: update)
                } else {
                    // Clear old-generation rows before awaiting the new directory.
                    refreshedSets = []
                    directoryNeedsReload = true
                    resetContent()
                }
            }
            catalogUpdateSequence = update.sequence ?? catalogUpdateSequence
        }
    }

    private func retryDefault() async {
        guard directoryNeedsReload else {
            await loadDefaultMore()
            return
        }
        let revision = contentRevision
        isLoading = true
        defer { if revision == contentRevision { isLoading = false } }
        do {
            let directory = try await catalog.sets(for: game)
            guard !Task.isCancelled, revision == contentRevision else { return }
            refreshedSets = directory
            directoryNeedsReload = false
            resetContent()
        } catch {
            guard !Task.isCancelled, revision == contentRevision else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadMoreSearch(query: String) async {
        guard !searchIsLoading, let cursor = searchCursor, let requestKey = searchRequestKey else { return }
        await loadSearchPage(query: query, requestKey: requestKey, cursor: cursor)
    }

    private func loadSearchPage(query: String, requestKey: UUID, cursor: String?) async {
        let isCurrent = { isActive && providerSearch == query && searchRequestKey == requestKey }
        guard isCurrent() else { return }
        searchIsLoading = true
        searchError = nil
        defer {
            if searchRequestKey == requestKey {
                searchIsLoading = false
            }
        }
        guard let fill = await searchStep(query: query, cursor: cursor, isCurrent: isCurrent),
              !Task.isCancelled, isCurrent() else { return }
        searchCards += fill.matches
        onCardsLoaded(fill.matches)
        searchCursor = fill.position?.cursor
        visitedSearchPositions = fill.visitedPositions
        searchStoppedAtLimit = fill.stoppedAtPageLimit && filters.isActive
        searchError = fill.error?.localizedDescription
    }

    private func deduplicated(_ values: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private func requestPricesForTile(_ group: CatalogCardDisplayGroup) {
        for card in group.summaries where visiblePriceSlots[card.id] != card {
            if visiblePriceSlots[card.id] == nil { visiblePriceOrder.append(card.id) }
            visiblePriceSlots[card.id] = card
        }
    }
}

private struct CatalogSetListView: View {
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @EnvironmentObject private var setCompletionStore: CatalogSetCompletionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    @State private var search = ""
    @State private var selectedSet: CatalogSet?
    @State private var sort: CatalogSetListSort = .newestFirst
    @State private var filter: CatalogSetListFilter = .all
    @AppStorage("pokemonMasterSetTier") private var masterSetTier: PokemonMasterSetTier = .standard

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
            let matchesFilter = filter.includes(
                $0, ownership: owned, completions: setCompletionStore.currentIndex(ownershipRevision: projectionStore.revision), tier: masterSetTier
            )
            return matchesSearch && matchesFilter
        }
        return CatalogSetOrdering.ordered(
            filtered,
            by: sort,
            ownership: owned,
            completions: setCompletionStore.currentIndex(ownershipRevision: projectionStore.revision),
            tier: masterSetTier
        )
    }

    var body: some View {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        let visibleSets = makeVisibleSets(owned: owned)
        let groups = CatalogSetListGrouping.groups(for: visibleSets, sort: sort)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
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
                            owned: owned,
                            completions: setCompletionStore.currentIndex(ownershipRevision: projectionStore.revision),
                            tier: masterSetTier
                        )
                    }
                } else {
                    CatalogSetGrid(
                        sets: visibleSets,
                        columns: columns,
                        catalog: catalog,
                        owned: owned,
                        completions: setCompletionStore.currentIndex(ownershipRevision: projectionStore.revision),
                        tier: masterSetTier
                    )
                }
            }
            .padding(16)
            .contentWidthLimit(.standard)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaPadding(.bottom, 24)
        .navigationTitle("\(game.label) Sets")
        .safeAreaInset(edge: .top, spacing: 0) {
            CatalogSearchField(text: $search, prompt: "Search sets")
        }
        .navigationDestination(item: $selectedSet) { set in
            CatalogSetCardsView(set: set, catalog: catalog)
        }
        .environment(\.openCatalogSet) { selectedSet = $0 }
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
    func includes(
        _ set: CatalogSet,
        ownership: CatalogOwnershipIndex,
        completions: CatalogSetCompletionIndex? = nil,
        tier: PokemonMasterSetTier = .standard
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .started:
            return (completions?.completion(for: set, tier: tier)
                ?? ownership.directoryProgress(for: set)).owned > 0
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
        var undated: [CatalogSet] = []
        let calendar = Calendar.current

        for set in orderedSets {
            guard let releaseDate = set.releaseDate else {
                undated.append(set)
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
        if !undated.isEmpty {
            groups.append(CatalogSetYearGroup(title: "Release Date Unknown", sets: undated))
        }
        return groups
    }
}

private struct CatalogSetGroupSection: View {
    let group: CatalogSetYearGroup
    let columns: [GridItem]
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex
    let completions: CatalogSetCompletionIndex?
    let tier: PokemonMasterSetTier

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
                owned: owned,
                completions: completions,
                tier: tier
            )
        }
    }
}

private struct CatalogSetGrid: View {
    @Environment(\.openCatalogSet) private var openCatalogSet
    let sets: [CatalogSet]
    let columns: [GridItem]
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex
    let completions: CatalogSetCompletionIndex?
    let tier: PokemonMasterSetTier

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(sets) { set in
                Button {
                    openCatalogSet(set)
                } label: {
                    CatalogSetTile(
                        set: set,
                        completion: completions?.completion(for: set, tier: tier)
                            ?? owned.directoryProgress(for: set),
                        catalog: catalog
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CatalogSetCardsView: View {
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @EnvironmentObject private var setCompletionStore: CatalogSetCompletionStore
    private let initialSet: CatalogSet
    @State private var refreshedSet: CatalogSet?
    private var set: CatalogSet { refreshedSet ?? initialSet }
    let catalog: any BrowseCatalogProviding
    @State private var cards: [CatalogCardSummary] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var search = ""
    @State private var sort: CatalogSetSort = .numberLowToHigh
    @State private var setFilters = CatalogBrowseFilters.none
    @State private var showsFilters = false
    @State private var browseQuotes: [String: CatalogBrowseQuote] = [:]
    /// The tier is a statement about what the user counts as a master set, not
    /// a per-set preference, so it should not reset every time a set is opened.
    @AppStorage("pokemonMasterSetTier") private var masterSetTier: PokemonMasterSetTier = .standard
    @State private var priceLoadState = CatalogPriceLoadState()
    @State private var explicitPriceScope: [CatalogCardSummary]?
    @State private var completedPriceChecks: [String: Date] = [:]
    @State private var contentGeneration = UUID()
    @StateObject private var presentation = CatalogSetPresentationStore()
    @State private var entryInterval: OSSignpostIntervalState?
    private var visibleGroups: [CatalogCardDisplayGroup] { presentation.groups }
    private var needsPrices: Bool { sort.needsPrices || setFilters.needsPrices }
    private var usesBrowsePresentation: Bool { sort.browseSort != .recommended || setFilters.isActive }
    private var finishOptions: [PhysicalVariant] {
        Array(Set(cards.flatMap(CatalogBrowseFilters.finishes))).sorted { $0.label < $1.label }
    }
    @State private var setProgress = SetCompletion(owned: 0, total: nil)
    @State private var priceLoadTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var viewport = CGRect.zero
    @State private var reloadAfterCurrentLoad = false
    @State private var isReloadingCatalog = false
    @State private var catalogUpdateSequence: UInt64?
    @State private var loadedPageCount = 0
    @State private var visitedPageCursors: Set<String> = []
    @State private var retryEntireSort = false
    @State private var paginationRevision = 0
    @State private var completeSortRequested = false
    @State private var isLoadingAllCards = false
    @State private var priceReloadAfterCurrentLoad = false
    @State private var queuedPricePriority: TaskPriority = .utility

    private struct PriceScopeInputs: Equatable {
        let search: String
        let tier: PokemonMasterSetTier
        let filters: CatalogBrowseFilters
        let ownershipRevision: UInt?
    }

    private var priceScopeInputs: PriceScopeInputs? {
        guard needsPrices else { return nil }
        return .init(search: search, tier: masterSetTier, filters: setFilters,
            ownershipRevision: setFilters.ownership == .all ? nil : projectionStore.cardOwnershipRevision)
    }

    init(set: CatalogSet, catalog: any BrowseCatalogProviding) {
        self.initialSet = set
        self.catalog = catalog
    }

    private func refreshVisibleGroups() {
        guard isVisible else { return }
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        presentation.update(.init(setID: set.catalogID, contentGeneration: contentGeneration,
            cards: cards, search: search, sort: sort, ownership: .all,
            ownershipRevision: projectionStore.revision, tier: masterSetTier, prices: displayPrices,
            officialCollectorCount: set.officialCollectorCount,
            browseFilters: usesBrowsePresentation ? setFilters : nil,
            browseQuotes: usesBrowsePresentation ? browseQuotes : [:], browseSet: set), owned: owned)
    }

    private var displayPrices: [String: Double] {
        OwnedCatalogPrice.displayPrices(for: cards, catalogPrices: browseQuotes.compactMapValues(\.amount),
            ownership: projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: []))
    }

    private var masterSetSlots: [CatalogCardSummary] {
        guard set.game == .pokemon, masterSetTier == .standard else { return cards }
        return cards.filter { !$0.isExpandedMasterSetVariant }
    }

    private var completionInputs: CatalogSetCompletionInputs {
        let isFullyLoaded = cursor == nil && !cards.isEmpty
        return CatalogSetCompletionInputs(
            set: set, slots: masterSetSlots, isFullyLoaded: isFullyLoaded,
            ownershipRevision: projectionStore.revision,
            completions: set.game == .pokemon && isFullyLoaded ? nil
                : setCompletionStore.currentIndex(ownershipRevision: projectionStore.revision),
            tier: masterSetTier
        )
    }

    var body: some View {
        let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        let browseRows = usesBrowsePresentation
            ? visibleGroups.map { CatalogBrowsePresentation.row($0, setDate: set.releaseDate, quotes: browseQuotes, ownership: owned) }
            : []
        return ScrollView {
            // Only the card grid needs lazy layout. Keep the header's identity
            // and origin stable when a short loading state becomes a long grid.
            VStack {
                if (cards.isEmpty && isLoading) || (visibleGroups.isEmpty && presentation.isProjecting) {
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
                    if set.physicalPrintingIDs?.isEmpty != true {
                        completionHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .contentWidthLimit(.standard)
                    }
                    sortScopeBanner
                    priceStatusBanner
                    if visibleGroups.isEmpty {
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
                            prices: displayPrices, browseRows: browseRows, showsReleaseDate: sort.browseSort.usesReleaseDate
                        )
                            .padding(12)
                            .contentWidthLimit(.wide)
                    }
                    if let error, !retryEntireSort {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry") { Task { await load(reset: false) } }
                            .buttonStyle(.bordered)
                    } else if error == nil, cursor != nil, !isLoadingAllCards {
                        CatalogPaginationFooter(
                            requestID: "\(paginationRevision)-\(cursor ?? "")", viewport: viewport
                        ) { await load(reset: false) }
                    }
                }
            }
        }
        .modifier(CatalogPaginationViewport(viewport: $viewport))
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaPadding(.bottom, 24)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CatalogSearchField(text: $search, prompt: "Name or number")
                if setFilters.isActive {
                    CatalogBrowseFilterChips(filters: $setFilters, sets: [set], finishOptions: finishOptions)
                }
            }
        }
        .modifier(CollectionFilterPresentation(isPresented: $showsFilters,
            filters: CatalogBrowseFilterSheet(isPresented: $showsFilters, filters: $setFilters, game: set.game,
                sets: [set], finishOptions: finishOptions,
                treatmentOptions: CatalogBrowseFacets().treatmentOptions(for: set.game), allowsSetSelection: false)))
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

                CatalogBrowseFilterButton(activeCount: setFilters.activeCount) { showsFilters = true }
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            if reloadAfterCurrentLoad {
                await requestReload()
            } else if cards.isEmpty {
                await load(reset: true)
            } else if needsPrices || (!priceLoadState.hasLoadedPrices && shouldPrefetchPrices) {
                startPriceLoading(
                    for: contentGeneration,
                    whileLoadingCards: false,
                    priority: needsPrices ? .userInitiated : .utility,
                    queueIfBusy: false
                )
            }
        }
        .onAppear {
            isVisible = true
            entryInterval = PerformanceSignpost.beginInterval("Browse.firstUsable",
                id: PerformanceSignpost.makeID(), "state=pending")
            if !visibleGroups.isEmpty { endEntryInterval(displayed: true) }
            refreshVisibleGroups()
            if !cards.isEmpty, needsPrices || (!priceLoadState.hasLoadedPrices && shouldPrefetchPrices) {
                startPriceLoading(
                    for: contentGeneration,
                    whileLoadingCards: false,
                    priority: needsPrices ? .userInitiated : .utility,
                    queueIfBusy: false
                )
            }
        }
        .onDisappear {
            isVisible = false
            presentation.cancel()
            endEntryInterval()
            if isLoading {
                if isReloadingCatalog { reloadAfterCurrentLoad = true }
                isReloadingCatalog = false
                contentGeneration = UUID()
                isLoading = false
            }
            isLoadingAllCards = false
            completeSortRequested = false
            priceLoadTask?.cancel()
            priceLoadTask = nil
            if priceLoadState.isLoading { priceLoadState.invalidate() }
            priceReloadAfterCurrentLoad = false
        }
        .onChange(of: cards) { _, _ in refreshVisibleGroups() }
        .onChange(of: visibleGroups) { _, groups in
            if !groups.isEmpty { endEntryInterval(displayed: true) }
        }
        .onChange(of: completionInputs, initial: true) { _, inputs in
            let owned = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
            setProgress = inputs.progress(ownership: owned)
        }
        .onChange(of: search) { _, _ in
            PerformanceSignpost.emitEvent("Browse.typing", "queryLength=\(search.count)")
            refreshVisibleGroups()
        }
        .onChange(of: setFilters) { _, _ in
            refreshVisibleGroups()
        }
        .onChange(of: priceScopeInputs) { _, scope in
            startPriceLoading(for: contentGeneration, whileLoadingCards: false,
                priority: scope == nil ? .utility : .userInitiated)
        }
        .onChange(of: browseQuotes) { _, _ in if usesBrowsePresentation { refreshVisibleGroups() } }
        .onChange(of: masterSetTier) { _, _ in refreshVisibleGroups() }
        .onChange(of: projectionStore.revision) { _, _ in refreshVisibleGroups() }
        .onChange(of: sort) { _, _ in
            refreshVisibleGroups()
            if !isLoadingAllCards, cursor != nil || isLoading {
                requestCompleteSort()
            }
        }
        .onChange(of: isLoading) { _, loading in
            if !loading, completeSortRequested { requestCompleteSort() }
        }
        .task(id: set.id) {
            let (updates, baseline) = await catalog.catalogUpdates(after: catalogUpdateSequence)
            guard !Task.isCancelled else { return }
            if catalogUpdateSequence == nil { catalogUpdateSequence = baseline }
            for await update in updates {
                guard !Task.isCancelled else { return }
                if update.affects(game: set.game, providerSetID: set.providerID) {
                    await requestReload()
                    guard !Task.isCancelled else { return }
                }
                catalogUpdateSequence = update.sequence ?? catalogUpdateSequence
            }
        }
    }

    private func endEntryInterval(displayed: Bool = false) {
        guard let entryInterval else { return }
        PerformanceSignpost.endInterval("Browse.firstUsable", entryInterval,
            displayed ? "state=displayed" : "state=cancelled")
        self.entryInterval = nil
    }

    @ViewBuilder
    private var sortScopeBanner: some View {
        if cursor != nil {
            VStack(alignment: .leading, spacing: 6) {
                if isLoadingAllCards {
                    Label("Loading remaining cards for sorting…", systemImage: "arrow.down.circle")
                } else {
                    Text("Sorting \(cards.count) loaded cards. More cards are available in this set.")
                    if retryEntireSort, let error { Text(error) }
                    Button(retryEntireSort ? "Retry Full Sort" : "Sort Entire Set", action: requestCompleteSort)
                        .disabled(isLoading)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentWidthLimit(.standard)
        }
    }

    private func requestCompleteSort() {
        completeSortRequested = true
        Task {
            guard isVisible, completeSortRequested, !isLoading else { return }
            completeSortRequested = false
            if cursor != nil { await load(reset: false, allRemainingPages: true) }
        }
    }

    @ViewBuilder
    private var priceStatusBanner: some View {
        if needsPrices {
            let ownership = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
            let slots = explicitPriceScope ?? []
            let effectiveQuotes = slots.map {
                CatalogBrowsePresentation.effectiveQuote($0, quoted: browseQuotes[$0.id], ownership: ownership)
            }
            let retryCount = slots.filter {
                browseQuotes[$0.id]?.canRetry == true && ownership.matchingRows(for: $0).isEmpty
            }.count
            let noQuoteCount = effectiveQuotes.filter { $0.status == .noQuote }.count
            let missingMappingCount = effectiveQuotes.filter { $0.status == .mappingPending }.count
            if priceLoadState.isLoading, !priceLoadState.hasLoadedPrices {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(effectiveQuotes.filter { $0.amount != nil }.count) of \(slots.count) matching finishes priced")
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else if !priceLoadState.isLoading,
                      retryCount > 0 || noQuoteCount > 0 || missingMappingCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    if missingMappingCount > 0 {
                        Label("Price mappings pending for \(missingMappingCount) finishes", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if retryCount > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Label(
                                "Couldn't refresh prices for \(retryCount) finishes",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("Retry") { retryPrices() }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if noQuoteCount > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Label(
                                "No USD quote for \(noQuoteCount) finishes",
                                systemImage: "info.circle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .contain)
            }
        }
    }

    /// Magic sets showed completion in the set list and then nothing at all on
    /// the set screen. Same header, without the Pokémon-only tier control.
    private var completionHeader: some View {
        let title = set.game == .pokemon ? "\(masterSetTier.label) Set Progress" : "Set Progress"
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(setProgress.label)
                        .font(.title2.bold())
                        .foregroundStyle(setProgress.owned > 0 ? Color.green : Color.primary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if let fraction = setProgress.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: setProgress.fraction ?? 0)
                .tint(.green)
                .accessibilityLabel(title)
                .accessibilityValue(setProgress.label)

            // Grand Master is only a choice when it adds slots to this set's checklist.
            // Use the full loaded checklist so search and ownership filters cannot hide the choice.
            if set.game == .pokemon, cards.contains(where: \.isExpandedMasterSetVariant) {
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

    private func load(reset: Bool, preservingLoadedPages: Bool = false, allRemainingPages: Bool = false) async {
        guard !isLoading else { return }
        guard !allRemainingPages || cursor != nil else { return }
        let pagesToLoad = reset && preservingLoadedPages ? max(1, loadedPageCount) : 1
        let requestID = UUID()
        contentGeneration = requestID
        presentation.cancel()
        // A page load changes the card set even before its response arrives.
        // Invalidate any sort request for the previous set so its result cannot
        // strand the new page in a loading state or mark it fully priced.
        priceLoadTask?.cancel()
        priceLoadTask = nil
        priceLoadState.invalidate()
        priceReloadAfterCurrentLoad = false
        if reset {
            browseQuotes.removeAll()
            explicitPriceScope = nil
            completedPriceChecks.removeAll()
        }
        isLoading = true
        isReloadingCatalog = reset && preservingLoadedPages
        isLoadingAllCards = allRemainingPages
        defer {
            if contentGeneration == requestID {
                isLoading = false
                isReloadingCatalog = false
                isLoadingAllCards = false
                if reloadAfterCurrentLoad {
                    Task { await requestReload() }
                } else if priceReloadAfterCurrentLoad,
                          priceLoadState.requestID == nil,
                          needsPrices,
                          !cards.isEmpty {
                    let priority = queuedPricePriority
                    priceReloadAfterCurrentLoad = false
                    startPriceLoading(
                        for: requestID,
                        whileLoadingCards: false,
                        priority: priority
                    )
                }
            }
        }
        error = nil
        retryEntireSort = false
        do {
            if reset {
                let current = try await catalog.currentSet(for: set)
                guard contentGeneration == requestID, !Task.isCancelled else { return }
                refreshedSet = current
            }
            let result: CatalogSetPageLoader.Result
            if reset, let localCards = try await catalog.completeLocalCards(in: set) {
                result = .init(items: localCards, count: 1)
            } else {
                let requestedSet = set
                result = await CatalogSetPageLoader.collect(
                    from: reset ? nil : cursor, limit: allRemainingPages ? nil : pagesToLoad,
                    visitedCursors: reset ? [] : visitedPageCursors
                ) { cursor in
                    guard contentGeneration == requestID else { throw CancellationError() }
                    return try await catalog.cards(in: requestedSet, cursor: cursor)
                }
            }
            guard contentGeneration == requestID, !Task.isCancelled else { return }
            if let failure = result.error {
                if reset || result.count == 0 { throw failure }
                if let catalogError = failure as? BrowseCatalogError, case .unknownSet = catalogError { throw failure }
                error = failure.localizedDescription
                retryEntireSort = allRemainingPages
            }
            cards = deduplicated(reset ? result.items : cards + result.items)
            loadedPageCount = reset ? result.count : loadedPageCount + result.count
            if reset { paginationRevision += 1 }
            cursor = result.nextCursor
            visitedPageCursors = result.visitedCursors
            PerformanceSignpost.emitEvent("Browse.cardsPublished", "cards=\(cards.count) complete=\(cursor == nil)")
            refreshVisibleGroups()
            if completeSortRequested, cursor != nil { return }
            if needsPrices {
                startPriceLoading(
                    for: requestID,
                    whileLoadingCards: true,
                    priority: .userInitiated
                )
            } else if shouldPrefetchPrices {
                startPriceLoading(
                    for: requestID,
                    whileLoadingCards: true,
                    priority: .utility
                )
            }
        } catch {
            guard contentGeneration == requestID, !Task.isCancelled else { return }
            if let catalogError = error as? BrowseCatalogError, case .unknownSet = catalogError {
                // A withdrawn set must not retain selectable old-generation rows.
                cards = []
                cursor = nil
                loadedPageCount = 0
                visitedPageCursors = []
                refreshVisibleGroups()
            }
            self.error = error.localizedDescription
            retryEntireSort = allRemainingPages && cursor != nil
            if needsPrices, !cards.isEmpty {
                startPriceLoading(for: requestID, whileLoadingCards: true, priority: .userInitiated)
            }
        }
    }

    private func requestReload() async {
        guard isVisible, !isLoading else {
            reloadAfterCurrentLoad = true
            return
        }
        reloadAfterCurrentLoad = false
        await load(reset: true, preservingLoadedPages: true)
    }

    private var shouldPrefetchPrices: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func startPriceLoading(
        for expectedContentGeneration: UUID,
        whileLoadingCards: Bool,
        priority: TaskPriority,
        queueIfBusy: Bool = true
    ) {
        // Pagination owns the card-content transition. A sort-change task must
        // not snapshot the old card set while that transition is in flight;
        // the page load will start the price request after its page is applied.
        guard isVisible, !cards.isEmpty,
              expectedContentGeneration == contentGeneration else { return }

        guard needsPrices || shouldPrefetchPrices else {
            priceLoadTask?.cancel()
            priceLoadTask = nil
            priceLoadState.invalidate()
            explicitPriceScope = nil
            return
        }

        if !whileLoadingCards && isLoading {
            guard queueIfBusy else { return }
            priceReloadAfterCurrentLoad = true
            queuedPricePriority = priority
            return
        }

        let scope = needsPrices ? CatalogBrowsePresentation.setPriceCandidates(cards, in: set, search: search,
            tier: masterSetTier, filters: setFilters,
            ownership: projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])) : nil
        if priceLoadState.requestID != nil {
            guard explicitPriceScope != scope else { return }
            priceLoadTask?.cancel()
            priceLoadTask = nil
            priceLoadState.invalidate()
        }
        explicitPriceScope = scope
        let candidates = scope ?? deduplicated(cards + cards.flatMap(CatalogBrowseFilters.explicitFinishes))
        let now = Date.now
        let requestedCards = candidates.filter { card in
            guard let checkedAt = completedPriceChecks[card.id] else { return true }
            let age = now.timeIntervalSince(checkedAt)
            // Let the catalog revalidate old prices and negative answers.
            let maxAge: TimeInterval = browseQuotes[card.id]?.amount == nil ? 6 * 3600 : 24 * 3600
            return age < 0 || age >= maxAge
        }
        priceReloadAfterCurrentLoad = false
        guard !requestedCards.isEmpty else { return }
        let requestID = UUID()
        priceLoadState.begin(requestID: requestID)
        priceLoadTask = Task(priority: priority) {
            await loadPrices(
                for: expectedContentGeneration,
                requestID: requestID,
                cards: requestedCards,
                whileLoadingCards: whileLoadingCards
            )
        }
    }

    private func loadPrices(
        for expectedContentGeneration: UUID,
        requestID: UUID,
        cards requestedCards: [CatalogCardSummary],
        whileLoadingCards: Bool
    ) async {
        var didComplete = false
        defer {
            if priceLoadState.requestID == requestID {
                self.priceLoadState.finish(
                    requestID: requestID,
                    loaded: didComplete
                )
                self.priceLoadTask = nil
                if didComplete,
                   priceReloadAfterCurrentLoad,
                   !isLoading,
                   needsPrices {
                    let priority = queuedPricePriority
                    priceReloadAfterCurrentLoad = false
                    startPriceLoading(
                        for: expectedContentGeneration,
                        whileLoadingCards: false,
                        priority: priority
                    )
                }
            }
        }
        guard !requestedCards.isEmpty,
              whileLoadingCards || !isLoading else { return }
        let requestIdentity = CatalogPriceRequestIdentity(
            contentGeneration: expectedContentGeneration,
            requestID: requestID
        )
        guard requestIdentity.matches(
            contentGeneration: contentGeneration,
            requestID: priceLoadState.requestID,
            isCancelled: Task.isCancelled
        ) else { return }
        for await update in catalog.sortPriceUpdates(for: requestedCards) {
            guard requestIdentity.matches(
                contentGeneration: contentGeneration,
                requestID: priceLoadState.requestID,
                isCancelled: Task.isCancelled
            ) else { return }
            for card in requestedCards {
                browseQuotes[card.id] = CatalogBrowseQuote.merging(update, id: card.id, previous: browseQuotes[card.id])
            }
        }
        guard requestIdentity.matches(
            contentGeneration: contentGeneration,
            requestID: priceLoadState.requestID,
            isCancelled: Task.isCancelled
        ) else { return }
        for card in requestedCards where browseQuotes[card.id] == nil {
            browseQuotes[card.id] = .failed
        }
        let checkedAt = Date.now
        for card in requestedCards { completedPriceChecks[card.id] = checkedAt }
        // Completion means the ordering stream drained. A slot can resolve to
        // no USD price (or be a virtual print-run slot), so price-map coverage
        // is not a valid definition of whether loading finished.
        didComplete = true
    }

    private func retryPrices() {
        guard needsPrices, !cards.isEmpty else { return }
        let ownership = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        let retryIDs = (explicitPriceScope ?? []).filter {
            browseQuotes[$0.id]?.canRetry == true && ownership.matchingRows(for: $0).isEmpty
        }.map(\.id)
        guard !retryIDs.isEmpty else { return }
        let generation = contentGeneration
        priceLoadTask?.cancel()
        priceLoadTask = nil
        priceReloadAfterCurrentLoad = false
        priceLoadState.invalidate()
        Task { @MainActor in
            await catalog.resetPriceResolution(for: retryIDs)
            guard !Task.isCancelled, generation == contentGeneration else { return }
            for id in retryIDs { completedPriceChecks[id] = nil }
            startPriceLoading(
                for: generation,
                whileLoadingCards: false,
                priority: .userInitiated
            )
        }
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
    let browseRows: [String: CatalogBrowsePresentation.Row]
    let showsReleaseDate: Bool
    let onTileVisible: (CatalogCardDisplayGroup) -> Void
    /// Adaptive so the catalog gains columns with the window instead of stretching
    /// two of them across a thirteen-inch iPad. The minimum matches the tile width
    /// the two-column phone layout already produces.
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    init(
        groups: [CatalogCardDisplayGroup],
        catalog: any BrowseCatalogProviding,
        owned: CatalogOwnershipIndex,
        prices: [String: Double] = [:],
        browseRows: [CatalogBrowsePresentation.Row] = [],
        showsReleaseDate: Bool = false,
        onTileVisible: @escaping (CatalogCardDisplayGroup) -> Void = { _ in }
    ) {
        self.groups = groups
        self.catalog = catalog
        self.owned = owned
        self.prices = prices
        self.browseRows = Dictionary(uniqueKeysWithValues: browseRows.map { ($0.id, $0) })
        self.showsReleaseDate = showsReleaseDate
        self.onTileVisible = onTileVisible
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(groups) { group in
                CatalogCardDisplayGroupTile(
                    group: group,
                    catalog: catalog,
                    owned: owned,
                    prices: prices,
                    browseRow: browseRows[group.id],
                    showsReleaseDate: showsReleaseDate
                )
                .onAppear { onTileVisible(group) }
            }
        }
        .scrollTargetLayout()
    }
}

private struct CatalogCardDisplayGroupTile: View {
    let group: CatalogCardDisplayGroup
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex
    let prices: [String: Double]
    let browseRow: CatalogBrowsePresentation.Row?
    let showsReleaseDate: Bool

    private var preferred: CatalogCardSummary { group.preferredSummary }

    private var openingFinish: PhysicalVariant? {
        browseRow?.representative?.masterSetVariant ?? preferred.masterSetVariant
    }

    private var treatmentLabel: String? {
        guard let openingFinish else { return preferred.magicTreatmentDisplayLabel }
        return MagicTreatmentEvidence(
            treatments: preferred.magicTreatmentEvidence.applicableTreatments(for: openingFinish),
            qualifiers: preferred.magicTreatmentQualifiers
        ).displayLabel
    }
    private var showsVariantChips: Bool {
        if browseRow != nil { return group.summaries.count > 1 }
        return group.summaries.count > 1 || preferred.masterSetVariantLabel != nil
    }

    private var representativeQuote: CatalogBrowseQuote? {
        guard let browseRow else { return nil }
        return browseRow.quotes[(browseRow.representative ?? preferred).id]
    }

    private var browsePriceLabel: String? {
        guard let quote = representativeQuote else { return nil }
        guard let amount = quote.amount else { return quote.status.label }
        let price = amount.formatted(.currency(code: "USD"))
        let finish = browseRow?.representative?.masterSetVariant?.label
        let freshness = quote.status.label
        return [price, finish, freshness].compactMap { $0 }.joined(separator: " · ")
    }

    private var releaseLabel: String? {
        guard showsReleaseDate, let browseRow else { return nil }
        guard let date = browseRow.releaseDate else { return "Release date unknown" }
        return "\(browseRow.usesSetDate ? "Set release" : "Released") \(CatalogBrowseSort.releaseDateLabel(date))"
    }

    private var sharedPrice: Double? {
        let values = group.summaries.compactMap { prices[$0.id] }
        guard values.count == group.summaries.count,
              let first = values.first,
              values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                CatalogCardDetailView(summary: preferred, catalog: catalog, openingFinishID: openingFinish?.id)
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
                collectorNumber: preferred.collectorNumber,
                limitlessArtworkAuthorized: preferred.limitlessArtworkAuthorized,
                providerID: preferred.providerID,
                providerSetID: preferred.setID.providerID
            )
                .overlay(alignment: .topTrailing) {
                    if group.summaries.contains(where: owned.owns) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }

            Text(preferred.displayName)
                .font(.headline)
                .lineLimit(2)

            if let notice = preferred.collectionAvailabilityNotice {
                Text(notice)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let treatment = treatmentLabel {
                CatalogTreatmentBadge(label: treatment)
            }

            if let browsePriceLabel {
                Text(browsePriceLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(representativeQuote?.amount == nil ? Color.secondary : Color.green)
            } else if !showsVariantChips, let sharedPrice {
                Text(sharedPrice, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            if let releaseLabel {
                Text(releaseLabel).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text(preferred.setAndCollectorLabel)
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
            if let price = browseRow?.quotes[summary.id]?.amount ?? prices[summary.id] {
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
            "\(label)\(count > 0 ? ", Owned quantity \(count)" : ", Not owned")\((browseRow?.quotes[summary.id]?.amount ?? prices[summary.id]).map { ", price \($0.formatted(.currency(code: "USD")))" } ?? "")"
        )
    }

    private func ownedQuantity(_ summary: CatalogCardSummary) -> Int {
        owned.quantity(of: summary)
    }

    private func accessibilityLabel(_ summary: CatalogCardSummary) -> String {
        let ownedQuantity = ownedQuantity(summary)
        let price = browsePriceLabel.map { ", \($0)" }
            ?? prices[summary.id].map { ", price \($0.formatted(.currency(code: "USD")))" } ?? ""
        let variant = summary.masterSetVariantLabel.map { ", \($0) variation" } ?? ""
        let treatment = treatmentLabel.map { ", \($0) treatment" } ?? ""
        let availability = summary.collectionAvailabilityNotice.map { ", \($0)" } ?? ""
        let number = summary.printedCollectorNumber.map { "card \($0)" } ?? "unnumbered card"
        let release = releaseLabel.map { ", \($0)" } ?? ""
        let source = representativeQuote?.source.map { ", \($0.label)" } ?? ""
        return "\(summary.displayName), \(summary.setName), \(number)\(variant)\(treatment)\(price)\(source)\(release)\(ownedQuantity > 0 ? ", owned quantity \(ownedQuantity)" : ", missing")\(availability)"
    }
}

struct CatalogVariantChipWrap: Layout {
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
    var limitlessArtworkAuthorized: Bool? = nil
    var providerID: String? = nil
    var providerSetID: String? = nil

    private var artworkSource: CatalogCardArtworkSource {
        CatalogCardArtworkSource(
            game: game,
            setCode: setCode,
            collectorNumber: collectorNumber,
            thumbnailURL: thumbnailURL,
            imageURL: imageURL,
            prefersFullSize: prefersFullSize,
            limitlessArtworkAuthorized: limitlessArtworkAuthorized,
            providerID: providerID,
            providerSetID: providerSetID
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

#if DEBUG
/// Repeatable visual QA for missing provider artwork, without touching collection data.
private struct BrowseMissingArtworkCatalog: BrowseCatalogProviding {
    let gameRegistry = CardGameRegistry(descriptors: [
        .init(game: .pokemon, displayName: "Pokémon", sortOrder: 0, capabilities: [.browse]),
        .init(game: .magic, displayName: "Magic", sortOrder: 1, capabilities: [.browse]),
        .init(game: .onePiece, displayName: "One Piece", sortOrder: 2, capabilities: [.browse])
    ])

    func sets(for game: CardGame) async throws -> [CatalogSet] {
        [.init(catalogID: .init(game: game, providerID: "artwork-qa"),
               name: game == .magic ? "Reality Fracture" : game == .pokemon ? "Prismatic Evolutions" : "Emperors in the New World",
               code: game == .magic ? "FRA" : game == .pokemon ? "PRE" : "OP09",
               logoURL: nil, symbolURL: nil, cardCount: 103, releaseDate: .now, sortRank: 1)]
    }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        .init(items: [], nextCursor: nil)
    }
    func searchCards(named query: String, game: CardGame, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        .init(items: [], nextCursor: nil)
    }
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        throw BrowseCatalogError.unknownSet
    }
    func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        AsyncStream { $0.finish() }
    }
}
#endif

/// Small, app-owned remote artwork view. The corresponding disk cache lives in
/// Caches (not Application Support), so iOS may reclaim it under pressure and
/// it never becomes synced collection data.
struct CatalogCachedImage: View {
    let candidates: [PokemonArtworkFallbacks.Candidate]
    /// An explicit maximum decoded dimension is useful for callers that know
    /// their drawing size. Most callers leave this nil and the view measures
    /// its laid-out bounds so the cache can keep separate derivatives for a
    /// grid tile, a portfolio thumbnail, and a detail hero.
    var targetPixelSize: Int? = nil
    var reloadToken: Int = 0
    var placeholderSymbol = "photo"
    var placeholderText: String? = nil
    var showsPlaceholder = true
    var contentMode: ContentMode = .fit
    var onPhaseChange: ((CatalogImageLoadPhase) -> Void)? = nil
    private var recursionTier: Int = 0
    @StateObject private var loader = CatalogImageLoader()
    @Environment(\.displayScale) private var displayScale
    @State private var measuredTargetPixelSize: Int?
    @State private var didReportBundledLoaded = false

    private struct LoadID: Equatable {
        let candidate: PokemonArtworkFallbacks.Candidate?
        let targetPixelSize: Int?
        let reloadToken: Int
    }

    init(
        candidates: [PokemonArtworkFallbacks.Candidate],
        targetPixelSize: Int? = nil,
        reloadToken: Int = 0,
        placeholderSymbol: String = "photo",
        placeholderText: String? = nil,
        showsPlaceholder: Bool = true,
        contentMode: ContentMode = .fit,
        onPhaseChange: ((CatalogImageLoadPhase) -> Void)? = nil,
        imageLoader: CatalogImageLoader? = nil
    ) {
        self.candidates = candidates
        self.targetPixelSize = targetPixelSize
        self.reloadToken = reloadToken
        self.placeholderSymbol = placeholderSymbol
        self.placeholderText = placeholderText
        self.showsPlaceholder = showsPlaceholder
        self.contentMode = contentMode
        self.onPhaseChange = onPhaseChange
        self._loader = StateObject(wrappedValue: imageLoader ?? CatalogImageLoader())
    }

    /// Compatibility initializer for card artwork and older callers. Set
    /// artwork uses the typed candidate initializer above; the legacy order is
    /// preserved here so card artwork keeps its existing provider preference.
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
        self.init(
            candidates: Self.legacyCandidates(
                url: url,
                fallbacks: fallbacks,
                localAssetName: localAssetName,
                localFallbackAssetNames: localFallbackAssetNames
            ),
            targetPixelSize: targetPixelSize,
            reloadToken: reloadToken,
            placeholderSymbol: placeholderSymbol,
            placeholderText: placeholderText,
            onPhaseChange: onPhaseChange
        )
    }

    private init(
        candidates: [PokemonArtworkFallbacks.Candidate],
        targetPixelSize: Int?,
        reloadToken: Int,
        placeholderSymbol: String,
        placeholderText: String?,
        showsPlaceholder: Bool,
        contentMode: ContentMode,
        onPhaseChange: ((CatalogImageLoadPhase) -> Void)?,
        recursionTier: Int
    ) {
        self.init(
            candidates: candidates,
            targetPixelSize: targetPixelSize,
            reloadToken: reloadToken,
            placeholderSymbol: placeholderSymbol,
            placeholderText: placeholderText,
            showsPlaceholder: showsPlaceholder,
            contentMode: contentMode,
            onPhaseChange: onPhaseChange
        )
        self.recursionTier = recursionTier
    }

    var body: some View {
        Group {
            if loader.matchesSource(remoteURL, reloadToken: reloadToken), let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loader.matchesSource(remoteURL, reloadToken: reloadToken), loader.failed, hasRemainingCandidate {
                CatalogCachedImage(
                    candidates: Array(resolvedCandidates.dropFirst()),
                    targetPixelSize: targetPixelSize,
                    reloadToken: reloadToken,
                    placeholderSymbol: placeholderSymbol,
                    placeholderText: placeholderText,
                    showsPlaceholder: showsPlaceholder,
                    contentMode: contentMode,
                    onPhaseChange: onPhaseChange,
                    recursionTier: recursionTier + 1
                )
            } else if let localAssetImage {
                Image(uiImage: localAssetImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let bundledLoadingImage {
                Image(uiImage: bundledLoadingImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                if showsPlaceholder { placeholder } else { Color.clear }
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
            candidate: activeCandidate,
            targetPixelSize: resolvedTargetPixelSize,
            reloadToken: reloadToken
        )) {
            guard !Task.isCancelled, let resolvedTargetPixelSize else { return }
            guard let remoteURL else {
                loader.cancel()
                return
            }
            loader.load(remoteURL, targetPixelSize: resolvedTargetPixelSize, reloadToken: reloadToken)
        }
        .onAppear {
            guard localAssetImage != nil || bundledLoadingImage != nil, !didReportBundledLoaded else { return }
            didReportBundledLoaded = true
            onPhaseChange?(.loaded)
        }
        .onChange(of: loader.phase) { _, phase in
            guard loader.matchesSource(remoteURL, reloadToken: reloadToken) else { return }
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
            guard !(phase == .failed && (hasRemainingCandidate || localAssetImage != nil)) else {
                return
            }
            onPhaseChange?(phase)
        }
        .onDisappear { loader.cancel() }
    }

    private var resolvedCandidates: [PokemonArtworkFallbacks.Candidate] {
        Self.candidatesSkippingMissingBundledAssets(candidates)
    }

    static func candidatesSkippingMissingBundledAssets(
        _ candidates: [PokemonArtworkFallbacks.Candidate]
    ) -> [PokemonArtworkFallbacks.Candidate] {
        // Every missing bundled candidate is dropped, not only a leading run:
        // `hasRemainingCandidate` decides whether a terminal `.failed` phase is
        // suppressed, so a trailing unloadable asset would otherwise swallow the
        // missing-art signal the tile depends on.
        candidates.filter { candidate in
            guard case let .bundled(name) = candidate else { return true }
            return UIImage(named: name) != nil
        }
    }

    private var activeCandidate: PokemonArtworkFallbacks.Candidate? {
        resolvedCandidates.first
    }

    private var hasRemainingCandidate: Bool {
        resolvedCandidates.count > 1
    }

    private var remoteURL: URL? {
        guard case let .remote(url) = activeCandidate else { return nil }
        return url
    }

    private var localAssetImage: UIImage? {
        guard case let .bundled(name) = activeCandidate else { return nil }
        return UIImage(named: name)
    }

    private var bundledLoadingImage: UIImage? {
        guard remoteURL != nil, !loader.failed else { return nil }
        for candidate in resolvedCandidates {
            if case let .bundled(name) = candidate,
               let image = UIImage(named: name) { return image }
        }
        return nil
    }

    private static func legacyCandidates(
        url: URL?,
        fallbacks: [URL],
        localAssetName: String?,
        localFallbackAssetNames: [String]
    ) -> [PokemonArtworkFallbacks.Candidate] {
        let remote = ([url] + fallbacks.map(Optional.some))
            .compactMap { $0 }
            .map(PokemonArtworkFallbacks.Candidate.remote)
        let bundled = ([localAssetName].compactMap { $0 } + localFallbackAssetNames)
            .map(PokemonArtworkFallbacks.Candidate.bundled)
        var result: [PokemonArtworkFallbacks.Candidate] = []
        for candidate in remote + bundled where !result.contains(candidate) {
            result.append(candidate)
        }
        return result
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
final class CatalogImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var failed = false
    @Published var phase: CatalogImageLoadPhase = .idle
    private var task: Task<Void, Never>?
    private struct Request: Equatable {
        let url: URL?
        let reloadToken: Int
        let targetPixelSize: Int?
    }
    private var request: Request?
    /// Completed artwork belongs to its source even after pending work is
    /// cancelled when the view disappears.
    private var displayedRequest: Request?
    private var generation = 0
    private let fetch: @Sendable (URL, Int?) async throws -> UIImage

    init(fetch: @escaping @Sendable (URL, Int?) async throws -> UIImage = { url, size in
        try await CatalogImageCache.shared.image(for: url, targetPixelSize: size)
    }) {
        self.fetch = fetch
    }

    deinit { task?.cancel() }

    func matchesSource(_ url: URL?, reloadToken: Int) -> Bool {
        let source = image == nil ? request : displayedRequest
        return source?.url == url && source?.reloadToken == reloadToken
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        request = nil
        isLoading = false
    }

    func load(_ url: URL?, targetPixelSize: Int?, reloadToken: Int = 0) {
        let next = Request(url: url, reloadToken: reloadToken, targetPixelSize: targetPixelSize)
        guard next != request else { return }
        let retainsArtwork = displayedRequest?.url == url && displayedRequest?.reloadToken == reloadToken
        request = next
        generation &+= 1
        let expectedGeneration = generation
        task?.cancel()
        task = nil
        if !retainsArtwork {
            image = nil
            displayedRequest = nil
        }
        failed = false
        phase = .idle
        if displayedRequest == next, image != nil {
            isLoading = false
            phase = .loaded
            return
        }
        guard let url else {
            isLoading = false
            return
        }
        isLoading = true
        phase = image == nil ? .loading : .loaded
        let fetch = fetch
        task = Task { [weak self] in
            do {
                let image = try await fetch(url, targetPixelSize)
                guard !Task.isCancelled, self?.generation == expectedGeneration else { return }
                self?.displayedRequest = next
                self?.image = image
                self?.phase = .loaded
            } catch {
                if !Task.isCancelled, self?.generation == expectedGeneration {
                    // A failed size derivative is not a failed source when
                    // its previous derivative is still usable.
                    let hasArtwork = self?.image != nil
                    self?.failed = !hasArtwork
                    self?.phase = hasArtwork ? .loaded : .failed
                }
            }
            if !Task.isCancelled, self?.generation == expectedGeneration { self?.isLoading = false }
        }
    }
}

/// A 60 MiB LRU disk cache for provider artwork. It deliberately persists only
/// source-URL keyed image bytes, never collection photos or provider responses.
actor CatalogImageCache {
    static let shared = CatalogImageCache()
    typealias HTTPResponseLoader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
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
    private let responseDataLoader: @Sendable (URLRequest) async throws -> Data
    /// Bounded by decoded bytes, not entry count: small accent-sampling copies
    /// must not evict the full-size tiles a grid scrolls back to.
    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private struct InFlight {
        let id: UUID
        let task: Task<Data, Error>
    }
    private struct CachedDataResponse {
        enum Source {
            case disk
            case network(UUID)
        }

        let data: Data
        let source: Source
    }
    private var inFlight: [URL: InFlight] = [:]
    private var persistenceInProgress: [URL: UUID] = [:]
    private var lastTouchAt: [URL: Date] = [:]
    private var bytesSinceTrim = 0
    private var didTrimAtStartup = false

    init(
        directory: URL? = nil,
        responseDataLoader: @escaping @Sendable (URLRequest) async throws -> Data = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw BrowseCatalogError.badResponse
            }
            guard let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  contentType.hasPrefix("image/") else {
                throw BrowseCatalogError.badResponse
            }
            return data
        }
    ) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BrowseArtworkCache", isDirectory: true)
        self.responseDataLoader = responseDataLoader
    }

    /// Test and transport seam that retains HTTP metadata long enough to reject
    /// HTML guidance responses before they reach ImageIO. The production
    /// initializer above uses the same status/MIME policy with URLSession.
    init(
        directory: URL? = nil,
        responseLoader: @escaping HTTPResponseLoader
    ) {
        self.init(directory: directory, responseDataLoader: { request in
            let (data, response) = try await responseLoader(request)
            guard (200..<300).contains(response.statusCode),
                  let contentType = response.value(forHTTPHeaderField: "Content-Type")?
                    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
                  contentType.hasPrefix("image/") else {
                throw BrowseCatalogError.badResponse
            }
            return data
        })
    }

    func image(for url: URL, targetPixelSize: Int? = nil) async throws -> UIImage {
        let targetPixelSize = Self.normalizedTargetPixelSize(targetPixelSize)
        let cacheKey = Self.memoryKey(for: url, targetPixelSize: targetPixelSize)
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        var response = try await data(for: url)
        var image = await Self.downsampledImageAsync(
            from: response.data,
            targetPixelSize: targetPixelSize
        )

        if image == nil, case .disk = response.source {
            // Older app versions persisted every successful HTTP body before
            // attempting image decoding. Evict those undecodable entries and
            // make one network attempt so a prior HTML response cannot poison
            // this URL's disk-cache slot forever.
            let file = directory.appendingPathComponent(Self.cacheFilename(for: url))
            await removeCachedData(at: file, for: url)
            response = try await data(for: url)
            image = await Self.downsampledImageAsync(
                from: response.data,
                targetPixelSize: targetPixelSize
            )
        }

        guard let image else {
            if case let .network(requestID) = response.source {
                finishRejectedResponse(for: url, requestID: requestID)
            }
            throw BrowseCatalogError.badResponse
        }

        switch response.source {
        case .disk:
            let file = directory.appendingPathComponent(Self.cacheFilename(for: url))
            await touchIfNeeded(file, for: url)
        case let .network(requestID):
            await persistDecodedResponse(response.data, for: url, requestID: requestID)
        }

        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? max(Int(image.size.width * image.scale * image.size.height * image.scale * 4), 1)
        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private static func downsampledImageAsync(
        from data: Data,
        targetPixelSize: Int
    ) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            Self.downsampledImage(from: data, targetPixelSize: targetPixelSize)
        }.value
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

    private func data(for url: URL) async throws -> CachedDataResponse {
        await trimAtStartupIfNeeded()
        let file = directory.appendingPathComponent(Self.cacheFilename(for: url))
        if let cached = try? await Self.readData(from: file) {
            return CachedDataResponse(data: cached, source: .disk)
        }

        if let existing = inFlight[url] {
            // A cancelled image owner must not cancel a request another cell is
            // already waiting for. The shared task is intentionally unstructured
            // and is persisted only after a waiter confirms successful decoding.
            do {
                let data = try await existing.task.value
                return CachedDataResponse(data: data, source: .network(existing.id))
            } catch {
                if inFlight[url]?.id == existing.id {
                    inFlight[url] = nil
                }
                throw error
            }
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let requestID = UUID()
        let responseDataLoader = self.responseDataLoader
        let task = Task<Data, Error> {
            try await responseDataLoader(request)
        }

        inFlight[url] = InFlight(id: requestID, task: task)
        do {
            let data = try await task.value
            return CachedDataResponse(data: data, source: .network(requestID))
        } catch {
            if inFlight[url]?.id == requestID {
                inFlight[url] = nil
            }
            throw error
        }
    }

    private func persistDecodedResponse(
        _ data: Data,
        for url: URL,
        requestID: UUID
    ) async {
        guard inFlight[url]?.id == requestID else { return }
        guard data.count <= Self.maximumAssetBytes else {
            inFlight[url] = nil
            return
        }
        // Keep the completed fetch coalesced across the disk-write await. The
        // actor is re-entrant there, so track the writer separately to prevent
        // another waiter from writing the same response a second time.
        guard persistenceInProgress[url] != requestID else { return }
        persistenceInProgress[url] = requestID

        let file = directory.appendingPathComponent(Self.cacheFilename(for: url))
        await Self.writeData(data, to: file, directory: directory)
        guard persistenceInProgress[url] == requestID else { return }
        persistenceInProgress[url] = nil
        if inFlight[url]?.id == requestID {
            inFlight[url] = nil
        }
        bytesSinceTrim += data.count
        if bytesSinceTrim >= Self.trimThresholdBytes {
            bytesSinceTrim = 0
            await trimOffActor()
        }
    }

    private func finishRejectedResponse(for url: URL, requestID: UUID) {
        guard inFlight[url]?.id == requestID,
              persistenceInProgress[url] != requestID else { return }
        inFlight[url] = nil
    }

    private func removeCachedData(at file: URL, for sourceURL: URL) async {
        lastTouchAt.removeValue(forKey: sourceURL)
        await Self.removeData(from: file)
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

    private static func removeData(from file: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: file)
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

    static func cacheFilename(for url: URL) -> String {
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
                ForEach(Set(sets.map(\.game)).sorted(by: { $0.rawValue < $1.rawValue })) { game in
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
