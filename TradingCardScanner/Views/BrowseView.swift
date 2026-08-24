import SwiftData
import SwiftUI

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

    let catalog: any BrowseCatalogProviding
    private var searchTask: Task<Void, Never>?
    private var generation = UUID()

    init(catalog: any BrowseCatalogProviding = BrowseCatalog()) {
        self.catalog = catalog
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
        guard requestedQuery.count >= 2,
              selectedGame == nil || selectedGame == game,
              var lane = lanes[game],
              let cursor = lane.cursor,
              !lane.isLoading else { return }
        lane.isLoading = true
        lanes[game] = lane
        do {
            let page = try await catalog.searchCards(
                named: requestedQuery,
                game: game,
                setIDs: effectiveSetIDs(for: game),
                cursor: cursor
            )
            guard CardNameSearch.normalize(searchText) == requestedQuery else { return }
            lane.cards = deduplicated(lane.cards + page.items)
            lane.cursor = page.nextCursor
            lane.error = nil
        } catch {
            lane.error = error.localizedDescription
        }
        lane.isLoading = false
        lanes[game] = lane
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        generation = UUID()
        let token = generation
        let query = normalizedQuery
        guard !query.isEmpty else {
            lanes = [:]
            return
        }
        guard query.count >= 2 else {
            lanes = [:]
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
        for game in games { lanes[game] = Lane(isLoading: true) }
        for game in CardGame.allCases where !games.contains(game) { lanes[game] = nil }

        await withTaskGroup(of: (CardGame, Result<CatalogPage<CatalogCardSummary>, Error>).self) { group in
            for game in games {
                let catalog = catalog
                let setIDs = effectiveSetIDs(for: game)
                group.addTask {
                    do { return (game, .success(try await catalog.searchCards(named: query, game: game, setIDs: setIDs, cursor: nil))) }
                    catch { return (game, .failure(error)) }
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
    @StateObject private var model = BrowseViewModel()
    @State private var showsSetFilter = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    searchField
                    if model.isSearching { searchBody } else { gameChooser }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                }
            }
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
        guard let sets = model.sets[.pokemon], !sets.isEmpty else { return }
        var changed = false
        for card in ownedCards where card.cardGame == .pokemon {
            let providerID = card.catalogProviderID ?? card.providerID
            guard let set = sets
                .filter({ providerID.hasPrefix($0.providerID + "-") })
                .max(by: { $0.providerID.count < $1.providerID.count }),
                  card.setReleaseOrder != set.sortRank else { continue }
            card.setReleaseOrder = set.sortRank
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    private var searchField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search every card printing", text: $model.searchText)
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
                    CatalogSetListView(game: game, sets: sets, catalog: model.catalog, ownedCards: ownedCards)
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
            ForEach(model.selectedGame.map { [$0] } ?? CardGame.allCases, id: \.self) { game in
                searchSection(game)
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
                CatalogCardGrid(cards: lane.cards, catalog: model.catalog, ownedCards: ownedCards)
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
}

private struct CatalogSetListView: View {
    let game: CardGame
    let sets: [CatalogSet]
    let catalog: any BrowseCatalogProviding
    let ownedCards: [CollectedCard]
    @State private var search = ""

    private var visible: [CatalogSet] {
        let query = CardNameSearch.normalize(search)
        guard !query.isEmpty else { return sets }
        return sets.filter {
            CardNameSearch.normalize($0.name).contains(query)
                || CardNameSearch.normalize($0.code).contains(query)
        }
    }

    var body: some View {
        List(visible) { set in
            let completion = SetCompletionCalculator.progress(for: set, cards: ownedCards)
            NavigationLink {
                CatalogSetCardsView(set: set, catalog: catalog, ownedCards: ownedCards)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: set.symbolURL ?? set.logoURL) { phase in
                        if case let .success(image) = phase { image.resizable().scaledToFit() }
                        else { Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary) }
                    }
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
                    "\(set.name), \(completion.owned) of \(completion.total.map { String($0) } ?? "unknown") cards collected, set code \(set.code)"
                )
            }
        }
        .navigationTitle("\(game.label) Sets")
        .searchable(text: $search, prompt: "Search sets")
    }
}

private struct CatalogSetCardsView: View {
    let set: CatalogSet
    let catalog: any BrowseCatalogProviding
    let ownedCards: [CollectedCard]
    @State private var cards: [CatalogCardSummary] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var search = ""

    private var visible: [CatalogCardSummary] {
        let query = CardNameSearch.normalize(search)
        guard !query.isEmpty else { return cards }
        return cards.filter {
            CardNameSearch.normalize($0.name).contains(query)
                || CardNameSearch.normalize($0.collectorNumber).contains(query)
        }
    }

    var body: some View {
        ScrollView {
            if cards.isEmpty && isLoading { ProgressView().padding(.top, 80) }
            else if cards.isEmpty, let error {
                ContentUnavailableView("Couldn't load this set", systemImage: "wifi.exclamationmark", description: Text(error))
                Button("Retry") { Task { await load(reset: true) } }.buttonStyle(.borderedProminent)
            } else {
                if visible.isEmpty {
                    ContentUnavailableView(
                        "No matching cards",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or collector number.")
                    )
                    .padding(.top, 60)
                } else {
                    CatalogCardGrid(cards: visible, catalog: catalog, ownedCards: ownedCards)
                        .padding(12)
                }
                if cursor != nil {
                    ProgressView().padding().task { await load(reset: false) }
                }
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Name or number")
        .task { if cards.isEmpty { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset { error = nil; cursor = nil }
        do {
            let page = try await catalog.cards(in: set, cursor: reset ? nil : cursor)
            cards = reset ? page.items : deduplicated(cards + page.items)
            cursor = page.nextCursor
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func deduplicated(_ values: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

private struct CatalogCardGrid: View {
    let cards: [CatalogCardSummary]
    let catalog: any BrowseCatalogProviding
    let ownedCards: [CollectedCard]
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(cards) { card in
                NavigationLink {
                    CatalogCardDetailView(summary: card, catalog: catalog)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        CatalogArtworkView(thumbnailURL: card.thumbnailURL, imageURL: card.imageURL)
                        Text(card.name).font(.headline).lineLimit(2)
                        HStack {
                            Text("\(card.setCode) \(card.collectorNumber)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            let count = ownedQuantity(card)
                            if count > 0 { Text("Owned \(count)").font(.caption.bold()).foregroundStyle(.green) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(card))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ownedQuantity(_ card: CatalogCardSummary) -> Int {
        ownedCards.filter { $0.providerID == card.providerID || $0.catalogProviderID == card.providerID }.reduce(0) { $0 + $1.quantity }
    }

    private func accessibilityLabel(_ card: CatalogCardSummary) -> String {
        let owned = ownedQuantity(card)
        return "\(card.name), \(card.setName), card \(card.collectorNumber)\(owned > 0 ? ", owned quantity \(owned)" : "")"
    }
}

struct CatalogArtworkView: View {
    let thumbnailURL: URL?
    let imageURL: URL?

    var body: some View {
        AsyncImage(url: imageURL ?? thumbnailURL) { phase in
            switch phase {
            case let .success(image): image.resizable().scaledToFit()
            case .failure: fallback
            default: placeholder.overlay { ProgressView() }
            }
        }
        .aspectRatio(0.727, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var fallback: some View {
        if let thumbnailURL, thumbnailURL != imageURL {
            AsyncImage(url: thumbnailURL) { phase in
                if case let .success(image) = phase { image.resizable().scaledToFit() }
                else { placeholder }
            }
        } else { placeholder }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10).fill(.quaternary).overlay { Image(systemName: "photo") }
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
