import PhotosUI
import SwiftData
import SwiftUI

#if DEBUG && LOCAL_ONLY_SIGNING
/// Opt-in UI acceptance uses public fixture identities and isolated local storage.
private actor SealedAcceptanceProvider: SealedBrowseProviding {
    let failsFirstDirectory: Bool
    private var directoryRequests = 0
    init(failsFirstDirectory: Bool) { self.failsFirstDirectory = failsFirstDirectory }
    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] {
        directoryRequests += 1
        if failsFirstDirectory, directoryRequests == 1 { throw URLError(.notConnectedToInternet) }
        return [.init(id: "recorded-one-piece-set", name: "One Piece — Recorded Booster Set", sealedCount: 2,
                      game: game, releaseDate: nil)]
    }
    func searchSealedProducts(game: CardGame, setID: String?, query: String?, offset: Int) async throws -> MarketCatalogPage<SealedProductSummary> {
        let product = SealedProductSummary(id: "recorded-one-piece-box-\(offset)", name: offset == 0 ? "One Piece Booster Box" : "One Piece Double Pack",
            setName: "Recorded Booster Set", variantID: "recorded-sealed-\(offset)", marketPriceUSD: offset == 0 ? 99.25 : 12.50,
            updatedAt: nil, imageURL: nil)
        return .init(items: [product], total: 2, offset: offset, limit: 1, hasMore: offset == 0)
    }
}

struct SealedBrowseAcceptanceView: View {
    let runtimes: CardGameRuntimeContainer?
    private let state: String
    @StateObject private var model: SealedBrowseModel
    init(runtimes: CardGameRuntimeContainer?) {
        self.runtimes = runtimes
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "-ui_debug_state")
        let state = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "ready"
        self.state = state
        _model = StateObject(wrappedValue: SealedBrowseModel(client: SealedAcceptanceProvider(failsFirstDirectory: state == "offline"),
            gameRegistry: runtimes?.registry ?? .standard,
            cache: CatalogCacheStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("SealedAcceptance-\(UUID())")),
            isConfigured: { true }))
    }
    var body: some View {
        NavigationStack {
            SealedSetDirectoryContent(game: .onePiece, model: model, searchText: "")
                .navigationTitle("One Piece Sealed")
        }
        .environment(\.cardGameRuntimes, state == "blocked" ? nil : runtimes)
    }
}
#endif

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
        var paginationRevision: UInt = 0

        var paginationKey: String { "\(paginationRevision)|\(nextOffset.map(String.init) ?? "")" }
    }

    @Published private(set) var sets: [SealedSetSummary] = []
    @Published private(set) var products: [SealedProductSummary] = []
    @Published private(set) var searchLanes: [CardGame: Lane] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var failurePresentation: CatalogFailurePresentation?
    @Published private(set) var hasMore = false

    private let client: any SealedBrowseProviding
    private let cache: CatalogCacheStore
    private let credentialsAvailable: @Sendable () -> Bool
    private let gameRegistry: CardGameRegistry
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
        gameRegistry: CardGameRegistry = .standard,
        cache: CatalogCacheStore = .shared,
        isConfigured: @escaping @Sendable () -> Bool = { PriceVendorCredentials.hasKey }
    ) {
        self.client = JustTCGV1Client(transport: transport)
        self.gameRegistry = gameRegistry
        self.cache = cache
        self.credentialsAvailable = isConfigured
    }

    init(
        client: any SealedBrowseProviding,
        gameRegistry: CardGameRegistry = .standard,
        cache: CatalogCacheStore = .shared,
        isConfigured: @escaping @Sendable () -> Bool = { PriceVendorCredentials.hasKey }
    ) {
        self.client = client
        self.gameRegistry = gameRegistry
        self.cache = cache
        self.credentialsAvailable = isConfigured
    }

    var isConfigured: Bool {
        credentialsAvailable() || gameRegistry.supports(.lorcana, .sealed)
    }
    func isConfigured(for game: CardGame) -> Bool {
        credentialsAvailable() || (game == .lorcana && gameRegistry.supports(game, .sealed))
    }

    func clearSearch() {
        searchGeneration = UUID()
        searchQuery = nil
        searchLanes = [:]
    }

    /// Invalidate pending responses without discarding already visible products
    /// or their next-page cursor when Browse moves off screen.
    func cancelSearchRequests() {
        searchGeneration = UUID()
        for (game, var lane) in searchLanes where lane.isLoading {
            lane.isLoading = false
            searchLanes[game] = lane
        }
    }

    /// Loads the requested sealed search lanes from the query that the browse
    /// model has already debounced. Cached pages are usable without
    /// credentials; only a stale or missing page with a configured account
    /// proceeds to the network. A scope change supplies a narrower game list,
    /// so invisible lanes never spend the shared vendor allowance.
    func search(query: String, games requestedGames: [CardGame]? = nil) async {
        let games = requestedGames ?? gameRegistry.games(supporting: .sealed)
        guard games.allSatisfy({ gameRegistry.supports($0, .sealed) }) else {
            clearSearch()
            errorMessage = CatalogFailurePresentation.unavailable.message
            failurePresentation = .unavailable
            return
        }
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

        for game in games {
            let isConfigured = isConfigured(for: game)
            let key = CatalogCacheStore.sealedPageKey(
                game: game,
                setID: nil,
                query: normalizedQuery,
                offset: 0
            )
            var lane = Lane(isLoading: isConfigured)
            if let saved = await cache.sealedProductPage(for: key) {
                lane.products = deduplicated(Self.dated(saved.value.items, at: saved.storedAt))
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
        // Each worker publishes on the main actor as soon as it finishes.
        // Explicit handles avoid nested task-group completion lifetimes in
        // Browse's cancellable search, and are all cancelled and joined below.
        let tasks = gamesToFetch.map { game in
            Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                let result: Result<CatalogPage<SealedProductSummary>, Error>
                do {
                    let response = try await client.searchSealedProducts(
                        game: game,
                        setID: nil,
                        query: normalizedQuery,
                        offset: 0
                    )
                    let page = CatalogPage(
                        items: response.items,
                        nextCursor: response.nextOffset.map(String.init)
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
                    result = .success(page)
                } catch {
                    result = .failure(error)
                }
                guard !Task.isCancelled, let self, token == self.searchGeneration,
                      var lane = self.searchLanes[game] else { return }
                lane.isLoading = false
                switch result {
                case let .success(page):
                    lane.products = deduplicated(page.items)
                    lane.nextOffset = Int(page.nextCursor ?? "")
                    lane.error = nil
                case let .failure(error):
                    lane.error = Self.message(for: error)
                }
                self.searchLanes[game] = lane
            }
        }
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: {
            for task in tasks { task.cancel() }
        }
    }

    func loadMoreSearch(game: CardGame, query: String) async {
        let isConfigured = isConfigured(for: game)
        guard gameRegistry.supports(game, .sealed) else { return }
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
                // A cancelled page must wake an already-visible replacement footer.
                if Task.isCancelled { currentLane.paginationRevision &+= 1 }
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
            lane.products = deduplicated(lane.products + Self.dated(saved.value.items, at: saved.storedAt))
            lane.nextOffset = Int(saved.value.nextCursor ?? "")
            lane.error = nil
            searchLanes[game] = lane
            return
        }

        guard token == searchGeneration, !Task.isCancelled else { return }
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
                nextCursor: page.nextOffset.map(String.init)
            )
            await cache.storeSealedProductPage(cachePage, for: cacheKey)
            guard token == searchGeneration, !Task.isCancelled,
                  var lane = searchLanes[game] else { return }
            lane.products = deduplicated(lane.products + cachePage.items)
            lane.nextOffset = Int(cachePage.nextCursor ?? "")
            lane.error = nil
            searchLanes[game] = lane
        } catch {
            guard token == searchGeneration, !Task.isCancelled,
                  var lane = searchLanes[game] else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            lane.error = Self.message(for: error)
            searchLanes[game] = lane
        }
    }

    /// One request, and only when the directory is not already loaded for this
    /// game. Sealed browse is interactive, but it is still the user's quota.
    func loadSetsIfNeeded(game: CardGame, forceRefresh: Bool = false) async {
        let isConfigured = isConfigured(for: game)
        guard gameRegistry.supports(game, .sealed) else {
            setsRequestID = UUID()
            activeSetsGame = nil
            isLoadingSets = false
            updateLoadingState()
            sets = []
            errorMessage = CatalogFailurePresentation.unavailable.message
            failurePresentation = .unavailable
            return
        }
        guard (forceRefresh || loadedGame != game || sets.isEmpty), activeSetsGame != game else { return }
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
            failurePresentation = nil
        }
        if let saved = await cache.sealedSets(for: game) {
            guard requestID == setsRequestID, !Task.isCancelled else { return }
            sets = SealedSetOrdering.newestFirst(saved.value)
            loadedGame = game
            if saved.isFresh, !forceRefresh {
                errorMessage = nil
                return
            }
        }
        guard requestID == setsRequestID, !Task.isCancelled else { return }
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
            failurePresentation = nil
        } catch {
            guard requestID == setsRequestID, !Task.isCancelled else { return }
            failurePresentation = CatalogFailurePresentation(error: error)
            errorMessage = sets.isEmpty
                ? Self.message(for: error)
                : "Showing saved sealed sets · \(Self.message(for: error))"
        }
    }

    func loadProducts(game: CardGame, setID: String?, query: String? = nil) async {
        let isConfigured = isConfigured(for: game)
        guard gameRegistry.supports(game, .sealed) else {
            productsRequestID = UUID()
            activeProductRoute = nil
            isLoadingProducts = false
            updateLoadingState()
            products = []
            hasMore = false
            errorMessage = CatalogFailurePresentation.unavailable.message
            failurePresentation = .unavailable
            return
        }
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
            apply(CatalogPage(items: Self.dated(saved.value.items, at: saved.storedAt), nextCursor: saved.value.nextCursor), replacing: true)
            if saved.isFresh || !isConfigured {
                errorMessage = nil
                return
            }
        }
        guard requestID == productsRequestID, !Task.isCancelled else { return }
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
        let isConfigured = isConfigured(for: game)
        guard gameRegistry.supports(game, .sealed) else { return }
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
                apply(CatalogPage(items: Self.dated(saved.value.items, at: saved.storedAt), nextCursor: saved.value.nextCursor), replacing: false)
                errorMessage = nil
                return
            }
        }
        guard requestID == productsRequestID, !Task.isCancelled else { return }
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

    private static func dated(_ products: [SealedProductSummary], at date: Date) -> [SealedProductSummary] {
        products.map { product in
            var product = product
            if product.retrievedAt == nil { product.retrievedAt = date }
            return product
        }
    }

    private func deduplicated(_ products: [SealedProductSummary]) -> [SealedProductSummary] {
        var seen: Set<String> = []
        return products.filter { product in
            let key = product.id + "|" + (product.variantID ?? "")
            return seen.insert(key).inserted
        }
    }

    private func cachePage(from page: MarketCatalogPage<SealedProductSummary>) -> CatalogPage<SealedProductSummary> {
        CatalogPage(
            items: page.items,
            nextCursor: page.nextOffset.map(String.init)
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
            return CatalogFailurePresentation(error: error).message
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
        case .badResponse(status: 401), .badResponse(status: 403):
            return CatalogFailurePresentation.accessUnavailable.message
        case .invalidURL, .badResponse:
            return "The pricing catalog couldn’t be loaded. Try again in a moment."
        }
    }

    func retrySets(game: CardGame) async {
        await loadSetsIfNeeded(game: game, forceRefresh: true)
    }
}

// MARK: - Set directory

struct SealedSetDirectoryContent: View {
    let game: CardGame
    @ObservedObject var model: SealedBrowseModel
    let searchText: String
    var onOpenSettings: (() -> Void)? = nil

    private var normalizedSearch: String {
        CardNameSearch.normalize(searchText)
    }

    private var visibleSets: [SealedSetSummary] {
        guard !normalizedSearch.isEmpty else { return model.sets }
        return model.sets.filter {
            CardNameSearch.normalize($0.name).contains(normalizedSearch)
        }
    }

    private var hasUsableCachedDirectory: Bool {
        !model.sets.isEmpty
    }

    var body: some View {
        List {
            if !model.isConfigured(for: game), !hasUsableCachedDirectory {
                unconfigured
            } else if !model.isConfigured(for: game), hasUsableCachedDirectory {
                Text("Showing saved sealed sets. Set up sealed browsing to refresh this directory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: model.failurePresentation?.icon ?? "shippingbox")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = model.failurePresentation?.action {
                    Button(action, systemImage: "arrow.clockwise") {
                        Task { await model.retrySets(game: game) }
                    }
                    .disabled(model.isLoading)
                } else if model.failurePresentation == .accessUnavailable, let onOpenSettings {
                    Button("Open Settings", systemImage: "key", action: onOpenSettings)
                }
            }

            if hasUsableCachedDirectory {
                Section {
                    ForEach(visibleSets) { set in
                        NavigationLink {
                            SealedProductGridView(game: game, set: set, model: model)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.name)
                                    Text(countLabel(
                                        set.sealedCount,
                                        singular: "sealed product",
                                        plural: "sealed products"
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 44)
                            .accessibilityElement(children: .combine)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Vendor catalog")
                            .font(.headline)
                        Text("Sets are grouped by the pricing vendor.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .overlay {
            if model.isLoading, model.sets.isEmpty {
                ProgressView("Loading sealed sets…")
            } else if model.sets.isEmpty, model.errorMessage == nil, model.isConfigured(for: game) {
                ContentUnavailableView(
                    "No Sealed Products",
                    systemImage: "shippingbox",
                    description: Text("This game has no sealed products in the price catalogue.")
                )
            } else if (model.isConfigured(for: game) || hasUsableCachedDirectory),
                      !normalizedSearch.isEmpty,
                      visibleSets.isEmpty {
                ContentUnavailableView(
                    "No Matching Sets",
                    systemImage: "magnifyingglass",
                    description: Text("No " + game.label + " sealed set matches \"" + searchText + "\".")
                )
            }
        }
        .safeAreaPadding(.bottom, 24)
        .task(id: game) {
            await model.loadSetsIfNeeded(game: game)
        }
    }

    @ViewBuilder
    private var unconfigured: some View {
        if let onOpenSettings {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Set up sealed browsing", systemImage: "key")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens Settings to add the pricing vendor key")

                Text("Add a pricing API key in Settings to browse sealed products.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
        } else {
            Label(
                "Add a pricing API key in Settings to browse sealed products.",
                systemImage: "key"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

struct SealedSetDirectoryView: View {
    let game: CardGame
    @ObservedObject var model: SealedBrowseModel
    @State private var searchText = ""

    var body: some View {
        SealedSetDirectoryContent(
            game: game,
            model: model,
            searchText: searchText
        )
        .navigationTitle("Sealed")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search " + game.label + " sets")
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
                        SealedProductDetailView(game: game, product: product, sourceSet: set)
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
            } else if !model.isConfigured(for: game), model.products.isEmpty {
                Label(
                    "Add a pricing API key in Settings to browse sealed products.",
                    systemImage: "key"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
            } else if model.products.isEmpty, let errorMessage = model.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load products", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await model.loadProducts(game: game, setID: set.id) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if model.products.isEmpty {
                ContentUnavailableView(
                    "No Sealed Products",
                    systemImage: "shippingbox",
                    description: Text("This set has no sealed products in the price catalogue.")
                )
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: set.id) { await model.loadProducts(game: game, setID: set.id) }
    }
}

/// Own the destination's product lane so opening a set never overwrites the
/// search results or set grid underneath the product detail.
struct SealedProductSetDestination: View {
    let game: CardGame
    let setName: String
    let sourceSet: SealedSetSummary?
    @StateObject private var model: SealedBrowseModel
    @State private var finishedLoading = false

    init(game: CardGame, setName: String, sourceSet: SealedSetSummary? = nil,
         gameRegistry: CardGameRegistry) {
        self.game = game
        self.setName = setName
        self.sourceSet = sourceSet
        _model = StateObject(wrappedValue: SealedBrowseModel(
            transport: JustTCGTransport.shared, gameRegistry: gameRegistry
        ))
    }

    private var resolvedSet: SealedSetSummary? {
        if let sourceSet, sourceSet.game == game { return sourceSet }
        // Names are all search results carry. Never guess between similarly
        // named sets or cross the card/sealed provider boundary.
        let matches = model.sets.filter {
            $0.game == game && $0.name.caseInsensitiveCompare(setName) == .orderedSame
        }
        return matches.count == 1 ? matches.first : nil
    }

    var body: some View {
        Group {
            if let set = resolvedSet {
                SealedProductGridView(game: game, set: set, model: model)
            } else if !finishedLoading {
                ProgressView("Loading set…")
            } else {
                ContentUnavailableView {
                    Label("Couldn't load this set", systemImage: "shippingbox")
                } description: {
                    Text(model.errorMessage ?? "This set isn't available in the sealed catalog.")
                } actions: {
                    Button("Retry") {
                        Task { await load(forceRefresh: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(setName)
        .navigationBarTitleDisplayMode(.inline)
        .task { if sourceSet == nil { await load() } }
    }

    private func load(forceRefresh: Bool = false) async {
        finishedLoading = false
        await model.loadSetsIfNeeded(game: game, forceRefresh: forceRefresh)
        finishedLoading = true
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

/// Browse and owned sealed products use the same card-detail visual language.
/// The product remains a sealed object: it has no finish, rarity or collector
/// number, and its market price is not inferred from the cards inside.
struct SealedProductDetailView: View {
    @Environment(\.cardGameRuntimes) private var runtimes
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var projectionStore: CollectionProjectionStore

    let game: CardGame
    let product: SealedProductSummary
    var sourceSet: SealedSetSummary? = nil

    @State private var artworkAccent: ArtworkAccent?
    @State private var historyPoints: [JustTCGHistoryPoint] = []
    @State private var confirmedQuantity: Int?
    @State private var quantityReadRevision: UInt = 0
    @State private var pendingMutation: CollectionMutation?
    @State private var undoTask: Task<Void, Never>?
    @State private var addFailure: String?
    @State private var addAlertTitle = "Couldn't update collection"
    @State private var isAdding = false
    @State private var isAdjusting = false
    @State private var isUndoing = false
    @State private var isConfirmingRemoval = false
    @State private var dispositionTarget: CollectionDispositionTarget?
    @State private var isSharing = false
    @State private var isChoosingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoGeneration = 0

    private var collectionKey: String {
        CollectedCard.sealedCollectionKey(
            game: game, productUUID: product.id, variantUUID: product.variantID ?? product.id
        )
    }

    private var ownedQuantity: Int {
        (projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: []))
            .sealedQuantity(productID: product.id, variantID: product.variantID)
    }

    private var displayedQuantity: Int { confirmedQuantity ?? ownedQuantity }

    private var canSave: Bool {
        (runtimes?.registry ?? .standard).supports(game, .collectionWrite)
    }

    private var isWriting: Bool { isAdding || isAdjusting || isUndoing }

    private var setName: String? {
        (sourceSet?.name ?? product.setName).flatMap { $0.isEmpty ? nil : $0 }
    }

    private var displayedPrice: PriceDisplay {
        PriceDisplay(
            amount: product.marketPriceUSD,
            source: .justTCG,
            sourceUpdatedAt: product.updatedAt,
            fetchedAt: product.retrievedAt,
            lastCheckedAt: product.retrievedAt
        )
    }

    private var marketRequest: CardMarketHistoryRequest {
        CardMarketHistoryRequest(sealedProduct: product, game: game)
    }

    private var shareIdentity: CardShareIdentity {
        CardShareIdentity(name: product.name, setCode: nil, setName: setName,
                          number: nil, badge: nil)
    }

    private var marketplaceURL: URL? {
        // The provider's exact product ID is known; the sealed variant UUID
        // is NOT a card finish and must not become a Printing query parameter.
        TCGplayerLinkBuilder.productURL(
            productID: product.tcgplayerProductID, variantID: nil, game: game
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                identity
                CardMarketHistoryPanel(
                    request: marketRequest,
                    currentPrice: displayedPrice.amount == nil ? nil : displayedPrice,
                    headlinePrice: displayedPrice,
                    showsDetails: false,
                    loadedPoints: $historyPoints
                )
                .accessibilityIdentifier("sealed-price-history")
                ownershipSection
                linksSection
            }
            .padding(.bottom, 28)
            .contentWidthLimit(.standard)
        }
        .background {
            AppCardDetailBackdrop(accent: reduceTransparency ? nil : artworkAccent)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .toolbarBackground(artworkAccent == nil || reduceTransparency ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button { isSharing = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityLabel("Share sealed product")
                    CollectionDetailArtworkSource(collectionKey: collectionKey, legacyFilename: nil) { filename in
                        Menu {
                            if displayedQuantity > 0 {
                                NavigationLink {
                                    CollectionCardHistoryView(
                                        collectionKey: collectionKey, cardName: product.name
                                    )
                                } label: {
                                    Label("Collection History", systemImage: "clock.arrow.circlepath")
                                }
                                Button {
                                    isChoosingPhoto = true
                                } label: {
                                    Label(filename == nil ? "Choose Photo" : "Replace Photo",
                                          systemImage: "photo.badge.plus")
                                }
                                if filename != nil {
                                    Button("Use Catalog Artwork", role: .destructive) {
                                        Task { await removePhoto() }
                                    }
                                }
                                Divider()
                                Button("Record Sale or Trade") { presentDisposition() }
                                Button("Remove One", role: .destructive) { isConfirmingRemoval = true }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.title3.weight(.semibold))
                        }
                        .accessibilityLabel("Sealed product actions")
                        .disabled(isWriting || displayedQuantity == 0)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .task(id: product.imageURL) {
            artworkAccent = await ArtworkAccentStore.accent(
                localFilename: nil, remoteURL: product.imageURL
            )
        }
        .task(id: collectionKey) { await refreshQuantity() }
        .onChange(of: ownedQuantity) { _, _ in
            // A CloudKit update also invalidates older in-flight reads.
            quantityReadRevision &+= 1
            confirmedQuantity = nil
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            photoGeneration &+= 1
            let revision = photoGeneration
            Task { await savePhoto(item, revision: revision) }
        }
        .sheet(isPresented: $isSharing) {
            CollectionDetailArtworkSource(collectionKey: collectionKey, legacyFilename: nil) { filename in
                CollectionShareSheet(
                    identity: shareIdentity,
                    price: CardSharePrice(
                        display: displayedPrice,
                        basis: CardSharePrice.basis(itemKind: .sealedProduct, gradeLabel: nil,
                                                     source: displayedPrice.source)
                    ),
                    showsFinishSheen: false,
                    localArtworkFilename: displayedQuantity > 0 ? filename : nil,
                    remoteArtworkURLs: [product.imageURL].compactMap { $0 }
                )
            }
        }
        .sheet(item: $dispositionTarget) { target in
            CollectionDispositionSheet(target: target) { _, _ in
                undoTask?.cancel()
                pendingMutation = nil
                Task { @MainActor in
                    await projectionStore.rebuild(container: modelContext.container)
                    await refreshQuantity()
                }
            }
        }
        .confirmationDialog(
            "Remove one sealed product?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove One", role: .destructive) {
                Task { await decrease() }
            }
            Button("Record Sale or Trade") { presentDisposition() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing a copy changes your collection quantity. Use Record Sale or Trade to keep a transaction record.")
        }
        .safeAreaInset(edge: .top) {
            if pendingMutation != nil { undoBanner.contentWidthLimit(.standard) }
        }
        .alert(
            addAlertTitle,
            isPresented: Binding(
                get: { addFailure != nil },
                set: { if !$0 { addFailure = nil } }
            ),
            presenting: addFailure
        ) { _ in
            Button("OK", role: .cancel) { addFailure = nil }
        } message: { detail in
            Text(detail)
        }
    }

    private var hero: some View {
        CollectionDetailArtworkSource(collectionKey: collectionKey, legacyFilename: nil) { filename in
            Group {
                if displayedQuantity > 0, let filename,
                   let image = CollectionArtworkStore.image(filename: filename) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    SealedProductArtwork(imageURL: product.imageURL)
                }
            }
            .frame(maxWidth: 360)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 14)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .accessibilityLabel("Product artwork for \(product.name)")
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEALED PRODUCT")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            CardDetailIdentityHeader(
                name: product.name, setName: setName ?? "", designation: "",
                rarity: nil, setLinkID: "sealed-set-link", accent: artworkAccent
            ) {
                SealedProductSetDestination(
                    game: game, setName: setName ?? "", sourceSet: sourceSet,
                    gameRegistry: runtimes?.registry ?? .standard
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    private var ownershipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your collection")
                        .font(.title3.weight(.bold))
                    Text("\(displayedQuantity) owned")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if displayedQuantity > 0, let price = displayedPrice.amount {
                        Text((price * Double(displayedQuantity)).formatted(.currency(code: "USD"))
                             + (displayedPrice.state() == .current ? " total value" : " last known value"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isWriting { ProgressView().controlSize(.small) }
                CatalogQuantityStepper(
                    quantity: displayedQuantity,
                    variantLabel: "sealed product",
                    canIncrease: canSave && displayedQuantity < CollectionQuantityLimits.maximum,
                    canDecrease: displayedQuantity > 0,
                    isUpdating: isWriting,
                    onIncrease: { Task { await add() } },
                    onDecrease: {
                        if displayedQuantity == 1 {
                            isConfirmingRemoval = true
                        } else {
                            Task { await decrease() }
                        }
                    }
                )
            }
            .padding(14)
            .background(.quaternary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !canSave {
                Label("Adding new products is unavailable for this game.", systemImage: "lock")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .accessibilityIdentifier("sealed-ownership")
    }

    private var linksSection: some View {
        CardDetailListGroup {
            NavigationLink {
                CardPriceDetailsView(
                    attribution: displayedPrice.detailAttribution,
                    points: historyPoints,
                    currentPrice: displayedPrice.amount == nil ? nil : displayedPrice,
                    mentionsPortfolioImpact: false
                )
            } label: {
                CardDetailListRow(title: "Price details", systemImage: "chart.xyaxis.line")
            }
            .buttonStyle(.plain)
            if let marketplaceURL {
                CardDetailListDivider()
                Link(destination: marketplaceURL) {
                    CardDetailListRow(
                        title: "View on TCGplayer", systemImage: "cart", isExternal: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the exact sealed product on TCGplayer.")
                .accessibilityIdentifier("sealed-tcgplayer-link")
            }
            if displayedQuantity > 0 {
                CardDetailListDivider()
                Button { presentDisposition() } label: {
                    CardDetailListRow(title: "Record sale or trade",
                                      systemImage: "arrow.left.arrow.right", showsDisclosure: false)
                }
                .buttonStyle(.plain)
                .disabled(isWriting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private var undoBanner: some View {
        HStack {
            Text("Added \(product.name)")
                .font(.subheadline).lineLimit(1)
            Spacer()
            if isUndoing { ProgressView().accessibilityLabel("Undoing addition") }
            Button("Undo") {
                guard !isWriting else { return }
                undoTask?.cancel()
                Task { await undo() }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .disabled(isWriting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func presentDisposition() {
        guard displayedQuantity > 0, !isWriting else { return }
        dispositionTarget = CollectionDispositionTarget(
            collectionKey: collectionKey, treatments: [], cardName: product.name,
            quantity: displayedQuantity, kind: .sold
        )
    }

    @MainActor
    private func refreshQuantity() async {
        quantityReadRevision &+= 1
        let revision = quantityReadRevision
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let reader = await CollectionDetailQuantityReader.makeBackground(modelContainer: modelContext.container)
        do {
            let fresh = try await reader.logicalQuantity(
                forAnyKey: collectionKey, magicTreatmentIDsRaw: []
            )
            guard !Task.isCancelled, generation.isCurrent(token),
                  quantityReadRevision == revision else { return }
            confirmedQuantity = fresh ?? 0
        } catch {
            // A failed read never turns a stored position into an apparent zero.
        }
    }

    /// Uses the existing sealed acquisition and receipt; no request to the
    /// pricing API is required to add an item.
    @MainActor
    private func add() async {
        guard canSave, !isWriting, displayedQuantity < CollectionQuantityLimits.maximum else { return }
        isAdding = true
        defer { isAdding = false }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        do {
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: modelContext.container)
            let mutation = try await CollectionExclusiveWrites.retryingIfRequired {
                try await writer.addSealedSelection(
                    product, game: game, shouldContinue: generation.continuation(for: token)
                )
            }
            guard !Task.isCancelled, generation.isCurrent(token) else { return }
            pendingMutation = mutation
            await refreshQuantity()
            await projectionStore.rebuild(container: modelContext.container)
            undoTask?.cancel()
            undoTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled, pendingMutation == mutation { pendingMutation = nil }
            }
        } catch is CancellationError {
        } catch {
            guard generation.isCurrent(token) else { return }
            addAlertTitle = "Couldn't add to collection"
            addFailure = error.localizedDescription
        }
    }

    /// The saved quantity is compared with the fresh serialized read before
    /// writing, so a concurrent CloudKit or other-device edit is not lost.
    @MainActor
    private func decrease() async {
        // The store independently authorizes maintenance of existing holdings,
        // even when the game's catalog cannot admit new products.
        guard !isWriting, displayedQuantity > 0 else { return }
        isAdjusting = true
        defer { isAdjusting = false }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let expected = displayedQuantity
        do {
            let reader = await CollectionDetailQuantityReader.makeBackground(modelContainer: modelContext.container)
            let actual = try await reader.logicalQuantity(
                forAnyKey: collectionKey, magicTreatmentIDsRaw: []
            ) ?? 0
            guard generation.isCurrent(token), !Task.isCancelled else { return }
            guard actual == expected else {
                confirmedQuantity = actual
                addAlertTitle = "Quantity changed"
                addFailure = "Your collection quantity changed. Review the updated count before removing a copy."
                return
            }
            let writer = await CollectionDetailWriter.makeBackground(modelContainer: modelContext.container)
            let saved = try await CollectionExclusiveWrites.retryingIfRequired {
                try await writer.setQuantity(
                    expected - 1, collectionKey: collectionKey, treatments: [],
                    expectedCurrent: expected, shouldContinue: generation.continuation(for: token)
                )
            }
            guard generation.isCurrent(token), !Task.isCancelled else { return }
            quantityReadRevision &+= 1
            confirmedQuantity = saved
            undoTask?.cancel()
            pendingMutation = nil
            await projectionStore.rebuild(container: modelContext.container)
        } catch is CancellationError {
        } catch {
            guard generation.isCurrent(token) else { return }
            await refreshQuantity()
            addAlertTitle = "Couldn't remove sealed product"
            addFailure = error.localizedDescription
        }
    }

    @MainActor
    private func undo() async {
        guard !isWriting, let mutation = pendingMutation else { return }
        isUndoing = true
        defer { isUndoing = false }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        do {
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: modelContext.container)
            try await CollectionExclusiveWrites.retryingIfRequired {
                try await writer.undoCatalog(
                    mutation, shouldContinue: generation.continuation(for: token)
                )
            }
            guard generation.isCurrent(token), pendingMutation == mutation else { return }
            pendingMutation = nil
            await refreshQuantity()
            await projectionStore.rebuild(container: modelContext.container)
        } catch is CancellationError {
        } catch {
            guard generation.isCurrent(token), pendingMutation == mutation else { return }
            addAlertTitle = "Couldn't undo addition"
            addFailure = "The collection change could not be undone. \(error.localizedDescription)"
        }
    }

    @MainActor
    private func savePhoto(_ item: PhotosPickerItem, revision: Int) async {
        guard displayedQuantity > 0, !isWriting else { return }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        isAdjusting = true
        defer {
            isAdjusting = false
            if revision == photoGeneration { selectedPhoto = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  revision == photoGeneration, !Task.isCancelled, generation.isCurrent(token) else { return }
            let writer = await CollectionDetailWriter.makeBackground(modelContainer: modelContext.container)
            let filename = try await writer.saveArtwork(
                data: data, collectionKey: collectionKey,
                shouldContinue: generation.continuation(for: token)
            )
            guard revision == photoGeneration, generation.isCurrent(token) else { return }
            if filename == nil {
                addAlertTitle = "Couldn't save photo"
                addFailure = "The photo couldn't be prepared."
            }
        } catch is CancellationError {
        } catch {
            guard revision == photoGeneration, generation.isCurrent(token) else { return }
            addAlertTitle = "Couldn't save photo"
            addFailure = error.localizedDescription
        }
    }

    @MainActor
    private func removePhoto() async {
        guard displayedQuantity > 0, !isWriting else { return }
        photoGeneration &+= 1
        selectedPhoto = nil
        isAdjusting = true
        defer { isAdjusting = false }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        do {
            let writer = await CollectionDetailWriter.makeBackground(modelContainer: modelContext.container)
            try await writer.removeArtwork(
                collectionKey: collectionKey, shouldContinue: generation.continuation(for: token)
            )
        } catch is CancellationError {
        } catch {
            guard generation.isCurrent(token) else { return }
            addAlertTitle = "Couldn't remove photo"
            addFailure = error.localizedDescription
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
