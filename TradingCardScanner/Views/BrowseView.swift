import Combine
import SwiftData
import SwiftUI
import UIKit

enum BrowseScope: Hashable {
    case all
    case cards
    case sealed
}

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
    @Published var searchScope: BrowseScope = .cards { didSet { scheduleSearch() } }
    @Published var selectedSets: Set<CatalogSetID> = [] { didSet { scheduleSearch() } }
    @Published private(set) var sets: [CardGame: [CatalogSet]] = [:]
    @Published private(set) var setErrors: [CardGame: String] = [:]
    @Published private(set) var lanes: [CardGame: Lane] = [:]

    let catalog: any BrowseCatalogProviding
    let sealedModel: SealedBrowseModel
    private var searchTask: Task<Void, Never>?
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
            self?.objectWillChange.send()
        }
    }

    var normalizedQuery: String { CardNameSearch.normalize(searchText) }
    var isSearching: Bool { !normalizedQuery.isEmpty }

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
        } catch {
            guard generation == requestedGeneration,
                  CardNameSearch.normalize(searchText) == requestedQuery,
                  var currentLane = lanes[game],
                  currentLane.cursor == cursor else { return }
            currentLane.error = error.localizedDescription
            lanes[game] = currentLane
            return
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        generation = UUID()
        let token = generation
        let query = normalizedQuery
        guard !query.isEmpty else {
            lanes = [:]
            sealedModel.clearSearch()
            return
        }
        guard query.count >= 2 else {
            lanes = [:]
            sealedModel.clearSearch()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            await self.runSearch(query: query, token: token)
        }
    }

    private func runSearch(query: String, token: UUID) async {
        let games = selectedGame.map { [$0] } ?? CardGame.allCases
        let searchesCards = searchScope != .sealed
        let searchesSealed = searchScope != .cards

        if searchesCards {
            for game in games { lanes[game] = Lane(isLoading: true) }
            for game in CardGame.allCases where !games.contains(game) { lanes[game] = nil }
        } else {
            lanes = [:]
        }

        if searchesSealed {
            async let sealedSearch = sealedModel.search(query: query, games: games)
            if searchesCards {
                await searchCardLanes(games: games, query: query, token: token)
            }
            await sealedSearch
        } else {
            sealedModel.clearSearch()
            if searchesCards {
                await searchCardLanes(games: games, query: query, token: token)
            }
        }
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
    @Environment(\.modelContext) private var modelContext
    @Query private var ownedCards: [CollectedCard]
    let catalog: any BrowseCatalogProviding
    @StateObject private var model: BrowseViewModel
    @State private var showsSetFilter = false
    @State private var isShowingSettings = false
    @FocusState private var searchFocused: Bool

    @State private var browseScope: BrowseScope = .cards

    init(catalog: any BrowseCatalogProviding = BrowseCatalog()) {
        self.catalog = catalog
        _model = StateObject(wrappedValue: BrowseViewModel(catalog: catalog))
    }

    /// Sealed browse is per game, using the vendor's own set directory. Each
    /// game's directory costs one request, and only when opened.
    @ViewBuilder private var sealedChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(CardGame.allCases) { game in
                NavigationLink {
                    SealedSetDirectoryView(game: game, model: model.sealedModel)
                } label: {
                    HStack {
                        Label(game.label, systemImage: "shippingbox")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .frame(minHeight: 44)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            if !PriceVendorCredentials.hasKey {
                Text("Add a pricing API key in Settings to browse sealed products.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                searchField
                // Search results stay sectioned by kind and game, so cards and
                // sealed products can be searched together without pretending
                // that they are interchangeable catalogue records.
                Picker("Browse scope", selection: $browseScope) {
                    if model.isSearching {
                        Text("All").tag(BrowseScope.all)
                    }
                    Text("Cards").tag(BrowseScope.cards)
                    Text("Sealed").tag(BrowseScope.sealed)
                }
                .pickerStyle(.segmented)

                switch browseScope {
                case .all:
                    if model.isSearching { searchBody } else { gameChooser }
                case .cards:
                    if model.isSearching { searchBody } else { gameChooser }
                case .sealed:
                    if model.isSearching { searchBody } else { sealedChooser }
                }
            }
            .padding(16)
            .contentWidthLimit(.standard)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Browse")
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
        .onChange(of: model.isSearching) { _, isSearching in
            if isSearching {
                browseScope = .all
            } else if browseScope == .all {
                browseScope = .cards
            }
        }
        .onChange(of: browseScope) { _, scope in
            model.searchScope = scope
        }
    }

    private func backfillPokemonReleaseOrder() {
        guard let sets = model.sets[.pokemon], !sets.isEmpty else { return }
        var changed = false
        for card in ownedCards where card.cardGame == .pokemon {
            let providerID = card.catalogProviderID ?? card.providerID
            guard let set = sets
                .filter({ providerID.hasPrefix($0.providerID + "-") })
                .max(by: { $0.providerID.count < $1.providerID.count }) else { continue }

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
        if changed { try? modelContext.save() }
    }

    private var searchField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search cards and sealed products", text: $model.searchText)
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

    @ViewBuilder private var gameChooser: some View {
        Text("Choose a game")
            .font(.title2.bold())
        ForEach(CardGame.allCases) { game in
            if let sets = model.sets[game] {
                NavigationLink {
                    CatalogGameCardsView(game: game, sets: sets, catalog: model.catalog)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: game == .pokemon ? "bolt.fill" : "wand.and.stars")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .foregroundStyle(game == .pokemon ? Color.yellow : Color.purple)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.label).font(.headline)
                            Text("Browse \(sets.count) sets").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
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

    @ViewBuilder private var searchBody: some View {
        if model.normalizedQuery.count < 2 {
            ContentUnavailableView("Keep typing", systemImage: "text.cursor", description: Text("Enter at least two characters."))
        } else {
            if browseScope != .sealed {
                Text("Cards")
                    .font(.title2.bold())
                ForEach(model.selectedGame.map { [$0] } ?? CardGame.allCases, id: \.self) { game in
                    searchSection(game)
                }
            }
            if browseScope != .cards {
                Text("Sealed")
                    .font(.title2.bold())
                ForEach(model.selectedGame.map { [$0] } ?? CardGame.allCases, id: \.self) { game in
                    sealedSearchSection(game)
                }
            }
        }
    }

    @ViewBuilder private func searchSection(_ game: CardGame) -> some View {
        let lane = model.lanes[game] ?? .init(isLoading: true)
        Section {
            if lane.cards.isEmpty && lane.isLoading {
                HStack { ProgressView(); Text("Searching…") }.frame(minHeight: 80)
            } else if lane.cards.isEmpty, let error = lane.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(game.label) search failed").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { model.searchText = model.searchText }
                }
            } else if lane.cards.isEmpty {
                Text("No \(game.label) printings found").foregroundStyle(.secondary)
            } else {
                CatalogCardGrid(
                    cards: lane.cards,
                    catalog: model.catalog,
                    owned: CatalogOwnershipIndex(ownedCards)
                )
                if lane.cursor != nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding()
                        .task { await model.loadMore(game) }
                }
            }
        } header: {
            Text(game.label).font(.title3.bold())
        }
    }

    @ViewBuilder private func sealedSearchSection(_ game: CardGame) -> some View {
        let lane = model.sealedModel.searchLanes[game] ?? .init(isLoading: true)
        Section {
            if lane.products.isEmpty && lane.isLoading {
                HStack { ProgressView(); Text("Searching sealed products…") }
                    .frame(minHeight: 80)
            } else if lane.products.isEmpty, !model.sealedModel.isConfigured {
                Text("Add a pricing API key in Settings to browse sealed products.")
                    .foregroundStyle(.secondary)
            } else if lane.products.isEmpty, let error = lane.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(game.label) sealed search failed").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { model.searchText = model.searchText }
                }
            } else if lane.products.isEmpty {
                Text("No \(game.label) sealed products found")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(lane.products) { product in
                        NavigationLink {
                            SealedProductDetailView(game: game, product: product)
                        } label: {
                            SealedProductTile(product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if lane.nextOffset != nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding()
                        .task {
                            await model.sealedModel.loadMoreSearch(
                                game: game,
                                query: model.normalizedQuery
                            )
                        }
                }
            }
        } header: {
            Text(game.label).font(.title3.bold())
        }
    }
}

enum CatalogGameCardsOrdering {
    static func newestFirst(_ sets: [CatalogSet]) -> [CatalogSet] {
        sets.sorted {
            if $0.releaseOrder != $1.releaseOrder {
                return $0.releaseOrder > $1.releaseOrder
            }
            return $0.id < $1.id
        }
    }
}

private struct CatalogGameCardsView: View {
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding

    @Query private var ownedCards: [CollectedCard]
    @State private var cards: [CatalogCardSummary] = []
    @State private var nextSetIndex = 0
    @State private var activeSetIndex: Int?
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var search = ""
    @State private var searchCards: [CatalogCardSummary] = []
    @State private var searchCursor: String?
    @State private var searchIsLoading = false
    @State private var searchError: String?
    @State private var searchRevision = 0
    @State private var searchRequestKey: String?

    private var orderedSets: [CatalogSet] {
        CatalogGameCardsOrdering.newestFirst(sets)
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
        let owned = CatalogOwnershipIndex(ownedCards)
        return ScrollView {
            if hasSearchText {
                searchContent(owned: owned)
            } else {
                defaultContent(owned: owned)
            }
        }
        .navigationTitle("\(game.label) Cards")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search \(game.label) cards")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CatalogSetListView(game: game, sets: sets, catalog: catalog)
                } label: {
                    Label("Sets", systemImage: "square.stack.3d.up")
                }
                .accessibilityLabel("Browse \(game.label) sets")
            }
        }
        .task {
            await loadDefaultMore()
        }
        .task(id: "\(normalizedSearch)-\(searchRevision)") {
            guard isSearchQuery else {
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
                CatalogCardGrid(cards: cards, catalog: catalog, owned: owned)
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
            CatalogCardGrid(cards: searchCards, catalog: catalog, owned: owned)
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
        guard !searchIsLoading,
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
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    // Queried here rather than passed down: a pushed screen handed an array
    // keeps the collection as it was when the link was tapped, so adding a card
    // from the detail screen would leave stale progress behind it.
    @Query private var ownedCards: [CollectedCard]
    @State private var search = ""
    @State private var showsMasterSetRules = false

    private var visible: [CatalogSet] {
        let query = CardNameSearch.normalize(search)
        guard !query.isEmpty else { return sets }
        return sets.filter {
            CardNameSearch.normalize($0.name).contains(query)
                || CardNameSearch.normalize($0.code).contains(query)
        }
    }

    var body: some View {
        List {
            if game == .pokemon {
                Section {
                    DisclosureGroup("Master set rules", isExpanded: $showsMasterSetRules) {
                        Text("Standard includes every English, pack-pulled numbered card, holo, reverse holo, and secret rare. Promos and non-pack products stay out. Expanded adds catalog-confirmed special parallel patterns.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }

            ForEach(visible) { set in
                let completion = SetCompletionCalculator.progress(for: set, cards: ownedCards)
                NavigationLink {
                    CatalogSetCardsView(set: set, catalog: catalog)
                } label: {
                    HStack(spacing: 12) {
                        CatalogCachedImage(
                            url: set.symbolURL ?? set.logoURL,
                            placeholderSymbol: "square.stack.3d.up"
                        )
                        .frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(set.name).font(.headline)
                            HStack(spacing: 8) {
                                Text(completion.label)
                                    .foregroundStyle(completion.owned > 0 ? Color.green : Color.secondary)
                                Text(set.code)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)

                            if let fraction = completion.fraction {
                                ProgressView(value: fraction)
                                    .tint(completion.owned > 0 ? Color.green : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(minHeight: 64)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(set.name), \(completion.owned) of \(completion.total.map { String($0) } ?? "unknown") \(completion.unit) collected, set code \(set.code)"
                    )
                }
            }
        }
        .navigationTitle("\(game.label) Sets")
        .searchable(text: $search, prompt: "Search sets")
    }
}

private struct CatalogSetCardsView: View {
    let set: CatalogSet
    let catalog: any BrowseCatalogProviding
    @Query private var ownedCards: [CollectedCard]
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

    private var masterSetSlots: [CatalogCardSummary] {
        guard set.game == .pokemon, masterSetTier == .standard else { return cards }
        return cards.filter { !$0.isExpandedMasterSetVariant }
    }

    private var completion: SetCompletion {
        self.set.game == .pokemon
            ? SetCompletionCalculator.progress(for: masterSetSlots, cards: ownedCards)
            : SetCompletionCalculator.progress(for: set, cards: ownedCards)
    }

    var body: some View {
        let owned = CatalogOwnershipIndex(ownedCards)
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
                    CatalogCardGrid(cards: visible, catalog: catalog, owned: owned, prices: prices)
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
        .onChange(of: sort) { _, newSort in
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
    let cards: [CatalogCardSummary]
    let catalog: any BrowseCatalogProviding
    let owned: CatalogOwnershipIndex
    let prices: [String: Double]
    /// Adaptive so the catalog gains columns with the window instead of stretching
    /// two of them across a thirteen-inch iPad. The minimum matches the tile width
    /// the two-column phone layout already produces.
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    init(
        cards: [CatalogCardSummary],
        catalog: any BrowseCatalogProviding,
        owned: CatalogOwnershipIndex,
        prices: [String: Double] = [:]
    ) {
        self.cards = cards
        self.catalog = catalog
        self.owned = owned
        self.prices = prices
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(cards) { card in
                NavigationLink {
                    CatalogCardDetailView(summary: card, catalog: catalog)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        CatalogArtworkView(thumbnailURL: card.thumbnailURL, imageURL: card.imageURL)
                            .overlay(alignment: .topTrailing) {
                                if owned.owns(card) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .green)
                                        .padding(8)
                                        .accessibilityHidden(true)
                                }
                            }
                        Text(card.name).font(.headline).lineLimit(2)
                        if let variant = card.masterSetVariantLabel {
                            Text(variant)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(card.isExpandedMasterSetVariant ? Color.purple : Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    (card.isExpandedMasterSetVariant ? Color.purple : Color.accentColor).opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        if let treatment = card.magicTreatmentDisplayLabel {
                            CatalogTreatmentBadge(label: treatment)
                        }
                        if let price = prices[card.id] {
                            Text(price, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        HStack {
                            Text("\(card.setCode) \(card.collectorNumber)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            let count = ownedQuantity(card)
                            if count > 0 { Text("Owned \(count)").font(.caption.bold()).foregroundStyle(.green) }
                        }
                    }
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(card))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ownedQuantity(_ card: CatalogCardSummary) -> Int {
        owned.quantity(of: card)
    }

    private func accessibilityLabel(_ card: CatalogCardSummary) -> String {
        let owned = ownedQuantity(card)
        let price = prices[card.id].map { ", price \($0.formatted(.currency(code: "USD")))" } ?? ""
        let variant = card.masterSetVariantLabel.map { ", \($0) variation" } ?? ""
        let treatment = card.magicTreatmentDisplayLabel.map { ", \($0) treatment" } ?? ""
        return "\(card.name), \(card.setName), card \(card.collectorNumber)\(variant)\(treatment)\(price)\(owned > 0 ? ", owned quantity \(owned)" : ", missing")"
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

    private var primaryURL: URL? {
        prefersFullSize ? (imageURL ?? thumbnailURL) : (thumbnailURL ?? imageURL)
    }

    private var fallbackURL: URL? {
        guard primaryURL != thumbnailURL else { return imageURL }
        return thumbnailURL
    }

    var body: some View {
        CatalogCachedImage(url: primaryURL, fallbackURL: fallbackURL)
        .aspectRatio(0.727, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Small, app-owned remote artwork view. The corresponding disk cache lives in
/// Caches (not Application Support), so iOS may reclaim it under pressure and
/// it never becomes synced collection data.
struct CatalogCachedImage: View {
    let url: URL?
    var fallbackURL: URL? = nil
    var placeholderSymbol = "photo"
    var placeholderText: String? = nil
    @StateObject private var loader = CatalogImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.failed, let fallbackURL, fallbackURL != url {
                CatalogCachedImage(
                    url: fallbackURL,
                    placeholderSymbol: placeholderSymbol,
                    placeholderText: placeholderText
                )
            } else {
                placeholder
            }
        }
        .task(id: url) { loader.load(url) }
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

@MainActor
private final class CatalogImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var failed = false
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    func load(_ url: URL?) {
        task?.cancel()
        image = nil
        failed = false
        guard let url else {
            isLoading = false
            return
        }
        isLoading = true
        task = Task { [weak self] in
            do {
                let image = try await CatalogImageCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                self?.image = image
            } catch {
                if !Task.isCancelled { self?.failed = true }
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

    private let directory: URL
    private let memoryCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
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

    func image(for url: URL) async throws -> UIImage {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        let data = try await data(for: url)
        guard let image = UIImage(data: data) else {
            throw BrowseCatalogError.badResponse
        }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? max(Int(image.size.width * image.scale * image.size.height * image.scale * 4), 1)
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
        return image
    }

    private func data(for url: URL) async throws -> Data {
        trimAtStartupIfNeeded()
        let file = directory.appendingPathComponent(filename(for: url))
        if let cached = try? Data(contentsOf: file) {
            touchIfNeeded(file, for: url)
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
                inFlight[url] = nil
                if data.count <= Self.maximumAssetBytes {
                    try? FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    try? data.write(to: file, options: .atomic)
                    bytesSinceTrim += data.count
                    if bytesSinceTrim >= Self.trimThresholdBytes {
                        trim()
                        bytesSinceTrim = 0
                    }
                }
            }
            return data
        } catch {
            if inFlight[url]?.id == requestID {
                inFlight[url] = nil
            }
            throw error
        }
    }

    private func touchIfNeeded(_ file: URL, for sourceURL: URL) {
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
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
    }

    private func trimAtStartupIfNeeded() {
        guard !didTrimAtStartup else { return }
        didTrimAtStartup = true
        // A previous process may have left the disk cache at its ceiling. One
        // lazy startup trim restores the limit without enumerating the entire
        // directory on every image download.
        trim()
    }

    private func trim() {
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
        return sets.filter { set in
            (selectedGame == nil || set.game == selectedGame)
                && (query.isEmpty || CardNameSearch.normalize(set.name + " " + set.code).contains(query))
        }
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
