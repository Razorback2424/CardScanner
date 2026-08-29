import SwiftData
import SwiftUI

/// Loads sealed directories and product pages one game at a time, while the
/// top-level search keeps an independent lane for each game.
///
/// Kept apart from the card catalogue because the two use different directories.
/// The vendor groups sets its own way, and mapping those groupings onto TCGdex
/// or Scryfall set identities is unreliable — a wrong mapping would show the
/// wrong products under a familiar set name, which is worse than showing the
/// vendor's own grouping honestly.
@MainActor
final class SealedBrowseModel: ObservableObject {
    struct Lane {
        var products: [SealedProductSummary] = []
        var nextOffset: Int?
        var isLoading = false
        var error: String?
    }

    @Published private(set) var sets: [SealedSetSummary] = []
    @Published private(set) var products: [SealedProductSummary] = []
    @Published private(set) var searchLanes: [CardGame: Lane] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasMore = false

    private let client: any SealedBrowseProviding
    private let cache: CatalogCacheStore
    private let credentialsAvailable: @Sendable () -> Bool
    private var offset = 0
    private var loadedGame: CardGame?
    private var loadedProductKey: String?
    private var searchQuery: String?
    private var searchGeneration = UUID()
    private struct ProductRoute: Equatable {
        let game: CardGame
        let setID: String?
        let query: String?
    }
    private var setsRequestID = UUID()
    private var activeSetsGame: CardGame?
    private var productsRequestID = UUID()
    private var activeProductRoute: ProductRoute?
    private var isLoadingSets = false
    private var isLoadingProducts = false

    init(
        transport: JustTCGTransport,
        cache: CatalogCacheStore = .shared,
        isConfigured: @escaping @Sendable () -> Bool = { PriceVendorCredentials.hasKey }
    ) {
        self.client = JustTCGV1Client(transport: transport)
        self.cache = cache
        self.credentialsAvailable = isConfigured
    }

    init(
        client: any SealedBrowseProviding,
        cache: CatalogCacheStore = .shared,
        isConfigured: @escaping @Sendable () -> Bool = { PriceVendorCredentials.hasKey }
    ) {
        self.client = client
        self.cache = cache
        self.credentialsAvailable = isConfigured
    }

    var isConfigured: Bool { credentialsAvailable() }

    func clearSearch() {
        searchGeneration = UUID()
        searchQuery = nil
        searchLanes = [:]
    }

    /// Loads both sealed search lanes from the query that the browse model has
    /// already debounced. Cached pages are usable without credentials; only a
    /// stale or missing page with a configured account proceeds to the network.
    func search(query: String) async {
        let normalizedQuery = CardNameSearch.normalize(query)
        guard normalizedQuery.count >= 2 else {
            clearSearch()
            return
        }

        let token = UUID()
        searchGeneration = token
        searchQuery = normalizedQuery
        var lanes: [CardGame: Lane] = [:]
        var gamesToFetch: [CardGame] = []

        for game in CardGame.allCases {
            let key = CatalogCacheStore.sealedPageKey(
                game: game,
                setID: nil,
                query: normalizedQuery,
                offset: 0
            )
            var lane = Lane(isLoading: isConfigured)
            if let saved = await cache.sealedProductPage(for: key) {
                lane.products = saved.value.items
                lane.nextOffset = Int(saved.value.nextCursor ?? "")
                if saved.isFresh || !isConfigured {
                    lane.isLoading = false
                } else {
                    gamesToFetch.append(game)
                }
            } else if isConfigured {
                gamesToFetch.append(game)
            }
            lanes[game] = lane
        }

        guard token == searchGeneration, !Task.isCancelled else { return }
        searchLanes = lanes
        guard isConfigured, !gamesToFetch.isEmpty else { return }

        let client = client
        let cache = cache
        await withTaskGroup(of: (CardGame, Result<CatalogPage<SealedProductSummary>, Error>).self) { group in
            for game in gamesToFetch {
                group.addTask {
                    do {
                        let response = try await client.searchSealedProducts(
                            game: game,
                            setID: nil,
                            query: normalizedQuery,
                            offset: 0
                        )
                        let page = CatalogPage(
                            items: response.items,
                            nextCursor: response.hasMore
                                ? String(response.offset + response.items.count)
                                : nil
                        )
                        await cache.storeSealedProductPage(
                            page,
                            for: CatalogCacheStore.sealedPageKey(
                                game: game,
                                setID: nil,
                                query: normalizedQuery,
                                offset: 0
                            )
                        )
                        return (game, .success(page))
                    } catch {
                        return (game, .failure(error))
                    }
                }
            }

            for await (game, result) in group {
                guard token == searchGeneration, !Task.isCancelled,
                      var lane = searchLanes[game] else { continue }
                lane.isLoading = false
                switch result {
                case let .success(page):
                    lane.products = page.items
                    lane.nextOffset = Int(page.nextCursor ?? "")
                    lane.error = nil
                case let .failure(error):
                    lane.error = Self.message(for: error)
                }
                searchLanes[game] = lane
            }
        }
    }

    func loadMoreSearch(game: CardGame, query: String) async {
        let normalizedQuery = CardNameSearch.normalize(query)
        guard normalizedQuery.count >= 2,
              searchQuery == normalizedQuery,
              var lane = searchLanes[game],
              let requestedOffset = lane.nextOffset,
              !lane.isLoading else { return }

        let token = searchGeneration
        lane.isLoading = true
        searchLanes[game] = lane
        defer {
            if token == searchGeneration,
               var currentLane = searchLanes[game] {
                currentLane.isLoading = false
                searchLanes[game] = currentLane
            }
        }
        let cacheKey = CatalogCacheStore.sealedPageKey(
            game: game,
            setID: nil,
            query: normalizedQuery,
            offset: requestedOffset
        )
        if let saved = await cache.sealedProductPage(for: cacheKey),
           saved.isFresh || !isConfigured {
            guard token == searchGeneration, !Task.isCancelled,
                  var lane = searchLanes[game] else { return }
            lane.products += saved.value.items
            lane.nextOffset = Int(saved.value.nextCursor ?? "")
            lane.error = nil
            searchLanes[game] = lane
            return
        }

        guard isConfigured else {
            lane.isLoading = false
            lane.nextOffset = nil
            searchLanes[game] = lane
            return
        }

        do {
            let page = try await client.searchSealedProducts(
                game: game,
                setID: nil,
                query: normalizedQuery,
                offset: requestedOffset
            )
            let cachePage = CatalogPage(
                items: page.items,
                nextCursor: page.hasMore
                    ? String(page.offset + page.items.count)
                    : nil
            )
            await cache.storeSealedProductPage(cachePage, for: cacheKey)
            guard token == searchGeneration, !Task.isCancelled,
                  var lane = searchLanes[game] else { return }
            lane.products += cachePage.items
            lane.nextOffset = Int(cachePage.nextCursor ?? "")
            lane.error = nil
            searchLanes[game] = lane
        } catch {
            guard token == searchGeneration, !Task.isCancelled,
                  var lane = searchLanes[game] else { return }
            lane.error = Self.message(for: error)
            searchLanes[game] = lane
        }
    }

    /// One request, and only when the directory is not already loaded for this
    /// game. Sealed browse is interactive, but it is still the user's quota.
    func loadSetsIfNeeded(game: CardGame) async {
        guard (loadedGame != game || sets.isEmpty), activeSetsGame != game else { return }
        let requestID = UUID()
        setsRequestID = requestID
        activeSetsGame = game
        isLoadingSets = true
        updateLoadingState()
        defer {
            if setsRequestID == requestID {
                activeSetsGame = nil
                isLoadingSets = false
                updateLoadingState()
            }
        }
        if loadedGame != game {
            sets = []
            errorMessage = nil
        }
        if let saved = await cache.sealedSets(for: game) {
            guard requestID == setsRequestID, !Task.isCancelled else { return }
            sets = SealedSetOrdering.newestFirst(saved.value)
            loadedGame = game
            if saved.isFresh {
                errorMessage = nil
                return
            }
        }
        guard isConfigured else {
            loadedGame = game
            return
        }
        do {
            let loadedSets = try await client.sealedSets(game: game)
            guard requestID == setsRequestID, !Task.isCancelled else { return }
            sets = SealedSetOrdering.newestFirst(loadedSets)
            loadedGame = game
            await cache.storeSealedSets(sets, for: game)
            guard requestID == setsRequestID, !Task.isCancelled else { return }
            errorMessage = nil
        } catch {
            guard requestID == setsRequestID, !Task.isCancelled else { return }
            errorMessage = sets.isEmpty
                ? Self.message(for: error)
                : "Showing saved sealed sets · \(Self.message(for: error))"
        }
    }

    func loadProducts(game: CardGame, setID: String?, query: String? = nil) async {
        let route = ProductRoute(game: game, setID: setID, query: query)
        guard activeProductRoute != route else { return }
        let requestID = UUID()
        productsRequestID = requestID
        activeProductRoute = route
        isLoadingProducts = true
        updateLoadingState()
        defer {
            if productsRequestID == requestID {
                activeProductRoute = nil
                isLoadingProducts = false
                updateLoadingState()
            }
        }
        offset = 0
        let cacheKey = CatalogCacheStore.sealedPageKey(game: game, setID: setID, query: query, offset: offset)
        if loadedProductKey != cacheKey {
            products = []
            hasMore = false
            errorMessage = nil
            loadedProductKey = cacheKey
        }
        if let saved = await cache.sealedProductPage(for: cacheKey) {
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            apply(saved.value, replacing: true)
            if saved.isFresh || !isConfigured {
                errorMessage = nil
                return
            }
        }
        guard isConfigured else {
            errorMessage = Self.message(for: JustTCGTransport.TransportError.missingCredentials)
            return
        }
        do {
            let page = try await client.searchSealedProducts(
                game: game, setID: setID, query: query, offset: 0
            )
            let cachePage = cachePage(from: page)
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            apply(cachePage, replacing: true)
            await cache.storeSealedProductPage(cachePage, for: cacheKey)
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            errorMessage = nil
        } catch {
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            errorMessage = products.isEmpty
                ? Self.message(for: error)
                : "Showing saved products · \(Self.message(for: error))"
        }
    }

    func loadMore(game: CardGame, setID: String?, query: String? = nil) async {
        let route = ProductRoute(game: game, setID: setID, query: query)
        guard hasMore, activeProductRoute != route else { return }
        let requestID = UUID()
        productsRequestID = requestID
        activeProductRoute = route
        isLoadingProducts = true
        updateLoadingState()
        defer {
            if productsRequestID == requestID {
                activeProductRoute = nil
                isLoadingProducts = false
                updateLoadingState()
            }
        }
        let requestedOffset = offset
        let cacheKey = CatalogCacheStore.sealedPageKey(
            game: game, setID: setID, query: query, offset: requestedOffset
        )
        if let saved = await cache.sealedProductPage(for: cacheKey) {
            if saved.isFresh || !isConfigured {
                guard requestID == productsRequestID, !Task.isCancelled else { return }
                apply(saved.value, replacing: false)
                errorMessage = nil
                return
            }
        }
        guard isConfigured else {
            hasMore = false
            errorMessage = Self.message(for: JustTCGTransport.TransportError.missingCredentials)
            return
        }
        do {
            let page = try await client.searchSealedProducts(
                game: game, setID: setID, query: query, offset: requestedOffset
            )
            let cachePage = cachePage(from: page)
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            apply(cachePage, replacing: false)
            await cache.storeSealedProductPage(cachePage, for: cacheKey)
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            errorMessage = nil
        } catch {
            guard requestID == productsRequestID, !Task.isCancelled else { return }
            errorMessage = products.isEmpty
                ? Self.message(for: error)
                : "Showing saved products · \(Self.message(for: error))"
        }
    }

    private func updateLoadingState() {
        isLoading = isLoadingSets || isLoadingProducts
    }

    private func cachePage(from page: MarketCatalogPage<SealedProductSummary>) -> CatalogPage<SealedProductSummary> {
        CatalogPage(
            items: page.items,
            nextCursor: page.hasMore ? String(page.offset + page.items.count) : nil
        )
    }

    private func apply(_ page: CatalogPage<SealedProductSummary>, replacing: Bool) {
        products = replacing ? page.items : products + page.items
        hasMore = page.nextCursor != nil
        offset = Int(page.nextCursor ?? "") ?? products.count
    }

    /// Quota and rate-limit stops get their own wording, including when they
    /// lift — "try again later" with no time attached is not actionable.
    static func message(for error: Error) -> String {
        guard let transportError = error as? JustTCGTransport.TransportError else {
            return error.localizedDescription
        }
        switch transportError {
        case let .budgetReached(resetAt):
            return "Daily request budget reached · resumes \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        case let .monthlyBudgetReached(resetAt):
            return "Monthly request budget reached · resumes \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        case let .rateLimited(retryAt):
            return "Paused by the provider · retry after \(retryAt.formatted(date: .abbreviated, time: .shortened))"
        case .missingCredentials:
            return "Add a pricing API key in Settings to browse sealed products."
        case .invalidURL, .badResponse:
            return transportError.errorDescription ?? "Sealed products could not be loaded."
        }
    }
}

// MARK: - Set directory

struct SealedSetDirectoryView: View {
    let game: CardGame
    @ObservedObject var model: SealedBrowseModel
    @State private var searchText = ""

    private var normalizedSearch: String {
        CardNameSearch.normalize(searchText)
    }

    private var visibleSets: [SealedSetSummary] {
        guard !normalizedSearch.isEmpty else { return model.sets }
        return model.sets.filter {
            CardNameSearch.normalize($0.name).contains(normalizedSearch)
        }
    }

    var body: some View {
        List {
            if !model.isConfigured {
                unconfigured
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(visibleSets) { set in
                NavigationLink {
                    SealedProductGridView(game: game, set: set, model: model)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.name)
                            Text("\(set.sealedCount) sealed product\(set.sealedCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    // 44pt minimum, and both lines read as one label.
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay {
            if model.isLoading, model.sets.isEmpty {
                ProgressView("Loading sealed sets…")
            } else if model.sets.isEmpty, model.errorMessage == nil, model.isConfigured {
                ContentUnavailableView(
                    "No Sealed Products",
                    systemImage: "shippingbox",
                    description: Text("This game has no sealed products in the price catalogue.")
                )
            } else if !normalizedSearch.isEmpty, visibleSets.isEmpty {
                ContentUnavailableView(
                    "No Matching Sets",
                    systemImage: "magnifyingglass",
                    description: Text("No " + game.label + " sealed set matches \"" + searchText + "\".")
                )
            }
        }
        .navigationTitle("Sealed")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search " + game.label + " sets")
        .task(id: game) { await model.loadSetsIfNeeded(game: game) }
    }

    private var unconfigured: some View {
        Label(
            "Add a pricing API key in Settings to browse sealed products.",
            systemImage: "key"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Product grid

struct SealedProductGridView: View {
    let game: CardGame
    let set: SealedSetSummary
    @ObservedObject var model: SealedBrowseModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            if let errorMessage = model.errorMessage, !model.products.isEmpty {
                Label(errorMessage, systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.products) { product in
                    NavigationLink {
                        SealedProductDetailView(game: game, product: product)
                    } label: {
                        SealedProductTile(product: product)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .contentWidthLimit(.wide)

            if model.hasMore {
                Button("Load More") {
                    Task { await model.loadMore(game: game, setID: set.id) }
                }
                .padding(.bottom, 20)
                .disabled(model.isLoading)
            }
        }
        .overlay {
            if model.isLoading, model.products.isEmpty {
                ProgressView("Loading products…")
            } else if !model.isConfigured, model.products.isEmpty {
                Label(
                    "Add a pricing API key in Settings to browse sealed products.",
                    systemImage: "key"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: set.id) { await model.loadProducts(game: game, setID: set.id) }
    }
}

struct SealedProductTile: View {
    let product: SealedProductSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SealedProductArtwork(imageURL: product.imageURL)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(product.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let price = product.marketPriceUSD {
                Text(price, format: .currency(code: "USD"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            } else {
                Text("No market price")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Product detail

struct SealedProductDetailView: View {
    let game: CardGame
    let product: SealedProductSummary

    @Environment(\.modelContext) private var modelContext
    @Query private var owned: [CollectedCard]
    @State private var pendingMutation: CollectionMutation?
    @State private var undoTask: Task<Void, Never>?

    private var ownedQuantity: Int {
        owned
            .filter { $0.itemKind == .sealedProduct && $0.justTCGCardID == product.id }
            .filter { $0.justTCGVariantID == product.variantID }
            .reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        List {
            Section {
                SealedProductArtwork(imageURL: product.imageURL)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                LabeledContent("Product", value: product.name)
                if let setName = product.setName {
                    LabeledContent("Set", value: setName)
                }
                if let price = product.marketPriceUSD {
                    LabeledContent("Market price") {
                        Text(price, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                } else {
                    // A missing price is stated, not hidden behind a dash.
                    LabeledContent("Market price", value: "No reliable market price")
                }
                if let updatedAt = product.updatedAt {
                    LabeledContent(
                        "Price as of",
                        value: updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                LabeledContent("Owned", value: "\(ownedQuantity)")
            }

            Section {
                Button {
                    add()
                } label: {
                    Label("Add to Collection", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Sealed Product")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if pendingMutation != nil {
                undoBanner.contentWidthLimit(.standard)
            }
        }
        .onDisappear { undoTask?.cancel() }
    }

    private var undoBanner: some View {
        HStack {
            Text("Added \(product.name)")
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("Undo") { undo() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Adding never waits on the network. The price already shown came with the
    /// listing, and routine repricing happens later through a batch.
    private func add() {
        let store = CollectionStore(context: modelContext)
        pendingMutation = try? store.addSealed(product, game: game)
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { pendingMutation = nil }
        }
    }

    private func undo() {
        guard let pendingMutation else { return }
        if (try? CollectionStore(context: modelContext).undo(pendingMutation)) != nil {
            self.pendingMutation = nil
            undoTask?.cancel()
        }
    }
}

private struct SealedProductArtwork: View {
    let imageURL: URL?

    var body: some View {
        CatalogCachedImage(url: imageURL, placeholderSymbol: "shippingbox.fill")
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
    }
}
