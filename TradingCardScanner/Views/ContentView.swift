import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]
    @Query private var priceRecords: [PriceRecord]

    private enum Tab: Hashable {
        case portfolio
        case collection
        case scan
        case centering
    }

    @State private var selectedTab: Tab
    @StateObject private var portfolio = PortfolioEngine()
    @StateObject private var refresh = PriceRefreshController()
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var collectionSort: CollectionSort = .priceHighToLow
    @State private var hasCheckedForStalePrices = false
    @State private var refreshStatusTask: Task<Void, Never>?
#if DEBUG
    private let debugRoute: String?
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        debugRoute = route
        let initialTab: Tab
        switch route {
        case "Browse", "SealedArtwork": initialTab = .collection
        case "PortfolioToday", "PortfolioPhase3", "PortfolioContributors", "PortfolioHistory": initialTab = .portfolio
        case "WholeCardScanner", "PriceCheck": initialTab = .scan
        default: initialTab = .portfolio
        }
        _selectedTab = State(initialValue: initialTab)
#else
        _selectedTab = State(initialValue: .portfolio)
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PortfolioView(
                portfolio: portfolio,
                refresh: refresh,
                onRefresh: refreshAllPrices,
                onOpenCollectionSortedByPrice: {
                    collectionSort = .priceHighToLow
                    selectedTab = .collection
                }
            )
                .tabItem {
                    Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(Tab.portfolio)

            CollectionView(
                opensBrowseOnLaunch: isBrowseDebugRoute,
                onOpenScanner: { selectedTab = .scan },
                onRefresh: refreshAllPrices,
                sort: $collectionSort
            )
                .tabItem {
                    Label("Collection", systemImage: "rectangle.stack")
                }
                .tag(Tab.collection)

            ScannerView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }
                .tag(Tab.scan)

            CardCenteringView()
                .tabItem {
                    Label("Centering", systemImage: "square.dashed.inset.filled")
                }
                .tag(Tab.centering)
        }
#if DEBUG
        .task {
            switch debugRoute {
            case "SealedArtwork":
                seedSealedArtworkQA()
            case "PortfolioToday", "PortfolioPhase3", "PortfolioContributors":
                PortfolioDebugFixtures.seedTodayIfNeeded(in: modelContext)
            case "PortfolioHistory":
                PortfolioDebugFixtures.seedHistoryIfNeeded(in: modelContext)
            default:
                break
            }
            portfolio.start(context: modelContext)
        }
#else
        .task { portfolio.start(context: modelContext) }
#endif
        // Portfolio truth is app-scoped: scanning or importing must recompute it
        // even if Collection has never been selected in this app session.
        .task(id: collectionMutationTaskID) {
            portfolio.recompute(context: modelContext)
            await refreshStalePricesIfNeeded()
        }
        .task { await recomputeAtDayRollover() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, portfolio.needsRecomputeForNewDay() else { return }
            portfolio.recompute(context: modelContext)
        }
        .onDisappear { refreshStatusTask?.cancel() }
    }

    private var collectionMutationTaskID: Int {
        var count = 0
        var sum = 0
        var xor = 0
        for card in cards {
            var element = Hasher()
            element.combine(card.collectionKey)
            element.combine(card.quantity)
            element.combine(card.priceKey)
            let value = element.finalize()
            count += 1
            sum &+= value
            xor ^= value
        }
        var hasher = Hasher()
        hasher.combine(count)
        hasher.combine(sum)
        hasher.combine(xor)
        return hasher.finalize()
    }

    private var isBrowseDebugRoute: Bool {
#if DEBUG
        return debugRoute == "Browse"
#else
        return false
#endif
    }

    @MainActor
    private func priceTargets(includeImported: Bool) -> [PriceTarget] {
        let recordsByKey = Dictionary(priceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let projection = LogicalCollection.project(cards: cards, ledger: InventoryLedger(context: modelContext))
        var seen = Set<String>()
        var result: [PriceTarget] = []

        for position in projection.positions {
            let card = position.representative
            if card.providerID.hasPrefix("csv:"), !includeImported { continue }
            guard seen.insert(card.priceKey).inserted else { continue }
            let record = PriceStore.record(for: card, in: recordsByKey)
            result.append(
                PriceTarget(
                    game: card.cardGame,
                    printingID: card.priceStorageID,
                    catalogPrintingID: card.catalogProviderID ?? card.providerID,
                    setCode: card.setCode,
                    variantID: card.variantID,
                    pokemonPrintRun: card.pokemonPrintRun,
                    importedIdentity: card.providerID.hasPrefix("csv:") && card.catalogProviderID == nil
                        ? ImportedPriceIdentity(name: card.name, setName: card.setName, cardNumber: card.cardNumber)
                        : nil,
                    catalogMetadataCheckedAt: card.catalogMetadataCheckedAt,
                    lastFailureAt: record?.lastFailureAt,
                    hasPrice: PriceRefreshController.hasFinishedPrice(
                        amount: record?.unitMarketPriceUSD,
                        currencyCode: record?.currencyCode,
                        usesFallback: usesPriceFallback
                    ),
                    lastCheckedAt: record?.lastCheckedAt,
                    itemKind: card.itemKind,
                    marketVariantID: card.justTCGVariantID,
                    needsArtwork: ArtworkDiagnostics.shouldRetrySealedArtwork(for: card),
                    gradedIdentity: card.itemKind == .gradedCard
                        ? GradedCardIdentity(name: card.name, setName: card.setName, collectorNumber: card.cardNumber)
                        : nil,
                    gradingCompany: card.gradingCompany,
                    grade: card.gradeRaw
                )
            )
        }
        return result
    }

    @MainActor
    private func refreshAllPrices() async {
        refreshStatusTask?.cancel()
        let targets = PriceRefreshController.staleTargets(from: priceTargets(includeImported: true))
        guard !targets.isEmpty else {
            refresh.markRecentlyChecked()
            dismissRefreshStatusLater()
            return
        }
        await refresh.refresh(targets, store: PriceStore(context: modelContext))
        portfolio.recompute(context: modelContext)
        dismissRefreshStatusLater()
    }

    @MainActor
    private func refreshStalePricesIfNeeded() async {
        guard !hasCheckedForStalePrices, !cards.isEmpty else { return }
        hasCheckedForStalePrices = true
        let targets = PriceRefreshController.staleTargets(from: priceTargets(includeImported: false))
        guard !targets.isEmpty else { return }
        await refresh.refresh(targets, store: PriceStore(context: modelContext))
        // The automatic stale check is silent when it works. When it does not,
        // the failure is still the app's to surface.
        refresh.dismissTransientSuccessSummary()
        portfolio.recompute(context: modelContext)
    }

    /// Success fades; an unresolved failure does not.
    private func dismissRefreshStatusLater() {
        refreshStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            refresh.dismissTransientSuccessSummary()
        }
    }

    @MainActor
    private func recomputeAtDayRollover() async {
        while !Task.isCancelled {
            let timeZone = PortfolioCalendar.timeZone()
            let today = PortfolioCalendar.day(containing: .now, in: timeZone)
            let next = PortfolioCalendar.boundary(afterDay: today, in: timeZone)
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled else { return }
            portfolio.recompute(context: modelContext)
        }
    }

#if DEBUG
    @MainActor
    private func seedSealedArtworkQA() {
        let store = CollectionStore(context: modelContext)
        let artworkURL = URL(
            string: "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        )
        _ = try? store.addSealed(
            SealedProductSummary(
                id: "ui-artwork-product",
                name: "Legendary Treasures Booster Box",
                setName: "Legendary Treasures",
                variantID: "ui-artwork-variant",
                marketPriceUSD: 18_750,
                updatedAt: .now,
                imageURL: artworkURL
            ),
            game: .pokemon
        )

        guard let unavailable = try? store.addSealed(
            SealedProductSummary(
                id: "ui-no-artwork-product",
                name: "Provider Artwork Missing",
                setName: "Artwork Diagnostics",
                variantID: "ui-no-artwork-variant",
                marketPriceUSD: 25,
                updatedAt: .now,
                imageURL: nil
            ),
            game: .pokemon
        ) else { return }
        if let row = store.card(forKey: unavailable.collectionKey) {
            row.catalogMetadataCheckedAt = .now
            row.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion
        }
        try? modelContext.save()
    }
#endif
}
