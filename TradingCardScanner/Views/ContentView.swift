import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var scanSummaryStore: ScanSessionSummaryStore

    private enum Tab: Hashable {
        case portfolio
        case collection
        case scan
        case centering
    }

    @State private var selectedTab: Tab
    @StateObject private var portfolio = PortfolioEngine()
    @StateObject private var priceSnapshot = PriceSnapshotStore.shared
    @StateObject private var projectionStore = CollectionProjectionStore()
    @StateObject private var revisionStore = StoreRevisionStore()
    /// The root passes this app-scoped service to the small views that observe
    /// the fields they render. It must remain a plain reference here: refresh
    /// progress publishes on a one-second cadence, and observing it at the root would
    /// rebuild the whole tab tree and re-run CollectionView's projection token.
    private let refresh = PriceRefreshController.shared
    @StateObject private var history = PortfolioHistoryStore()
    /// One catalog actor is shared by every Collection/Browse route in this
    /// app session. Its protected checklist and in-memory caches therefore do
    /// not reset when the user pushes into a set and returns.
    @State private var browseCatalog: BrowseCatalog
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var collectionSort: CollectionSort = .priceHighToLow
    /// The mutation observer can start before the separate launch task. Keep it
    /// behind portfolio initialization so it cannot replay a populated
    /// collection before `PortfolioEpoch` has written its baseline.
    @State private var hasStartedPortfolio = false
    @State private var refreshStatusTask: Task<Void, Never>?
#if DEBUG
    private let debugRoute: String?
#endif

    init() {
        _browseCatalog = State(initialValue: BrowseCatalog())
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        debugRoute = route
        let initialTab: Tab
        switch route {
        case "Browse", "SealedArtwork", "CardMovement", "CardDetail", "MagicTreatmentSlice4": initialTab = .collection
        case "PortfolioToday", "PortfolioPhase3", "PortfolioContributors", "PortfolioHistory": initialTab = .portfolio
        case "WholeCardScanner", "PriceCheck", "GradedLabelCapture": initialTab = .scan
        case "Centering", "CenteringExpanded": initialTab = .centering
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
                history: history,
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
                catalog: browseCatalog,
                history: history,
                refresh: refresh,
                opensBrowseOnLaunch: isBrowseDebugRoute,
                opensMovementDetailsOnLaunch: isMovementDebugRoute,
                opensCardDetailOnLaunch: isCardDetailDebugRoute,
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
        .environmentObject(priceSnapshot)
        .environmentObject(projectionStore)
        .environmentObject(revisionStore)
        .overlay(alignment: .top) {
            ScanSessionSummaryBanner()
                .environmentObject(scanSummaryStore)
        }
#if DEBUG
        .overlay {
            if debugRoute == "MagicTreatmentSlice4" {
                MagicTreatmentSlice4DebugView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .ignoresSafeArea()
            }
        }
#endif
#if DEBUG
        .task {
            switch debugRoute {
            case "SealedArtwork":
                seedSealedArtworkQA()
            case "CardMovement":
                PortfolioDebugFixtures.seedMovementIfNeeded(in: modelContext)
                history.mode = .marketMovement
                history.range = .oneMonth
            case "CardDetail":
                PortfolioDebugFixtures.seedTodayIfNeeded(in: modelContext)
                history.mode = .marketMovement
                history.range = .oneMonth
            case "PortfolioToday", "PortfolioPhase3", "PortfolioContributors":
                PortfolioDebugFixtures.seedTodayIfNeeded(in: modelContext)
                history.mode = .marketMovement
                history.range = .oneWeek
            case "PortfolioHistory":
                PortfolioDebugFixtures.seedHistoryIfNeeded(in: modelContext)
                history.mode = .marketMovement
                history.range = .all
            default:
                break
            }
            try? CollectionStore(context: modelContext).backfillExistingCollectionIfNeeded()
            _ = await MagicTreatmentMigrationCoordinator.shared.runLocal(in: modelContext)
            portfolio.start(context: modelContext)
            hasStartedPortfolio = true
        }
#else
        .task {
            try? CollectionStore(context: modelContext).backfillExistingCollectionIfNeeded()
            _ = await MagicTreatmentMigrationCoordinator.shared.runLocal(in: modelContext)
            portfolio.start(context: modelContext)
            hasStartedPortfolio = true
        }
#endif
        .task {
            refresh.registerPortfolio(portfolio)
            refresh.registerPriceSnapshotStore(priceSnapshot)
            refresh.registerRevisionStore(revisionStore)
            await priceSnapshot.bootstrap(container: modelContext.container)
        }
        .task(id: hasStartedPortfolio) {
            guard hasStartedPortfolio else { return }
            await projectionStore.rebuild(container: modelContext.container)
            _ = await MagicTreatmentMigrationCoordinator.shared.runNetwork(in: modelContext)
            guard !Task.isCancelled else { return }
            // Network enrichment can add treatments or rekey rows after the
            // initial portfolio snapshot. Recompute only after the migration
            // has finished so the user never sees a half-applied result.
            portfolio.recompute(context: modelContext)
        }
        // Portfolio truth is app-scoped: scanning or importing must recompute it
        // even if Collection has never been selected in this app session. This
        // lives in its own view rather than here because deciding whether the
        // inputs changed means walking every row of four tables, and this view
        // re-renders for reasons that have nothing to do with them — most of
        // all a running refresh, which publishes progress while it runs. Down
        // there it observes only what it actually reacts to.
        .background(
            StoreRevisionMonitor(
                portfolio: portfolio,
                projectionStore: projectionStore,
                priceSnapshot: priceSnapshot,
                revisionStore: revisionStore,
                refresh: refresh,
                hasStartedPortfolio: hasStartedPortfolio
            )
        )
        .background(
            StoreRevisionHistoryMonitor(
                portfolio: portfolio,
                history: history,
                hasStartedPortfolio: hasStartedPortfolio
            )
        )
        .task { await recomputeAtDayRollover() }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await browseCatalog.prepareCatalog()
            } else {
                await browseCatalog.suspendCatalogRefresh()
            }
        }
        .task(id: fallbackAvailabilityTaskID) {
            guard scenePhase == .active, hasStartedPortfolio else { return }
            // This value only controls settings/status affordances. Let the
            // scene settle before projecting the collection for its count, and
            // cancel the work when a rapid phase or preference change supersedes
            // it.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, scenePhase == .active, hasStartedPortfolio else { return }
            await updateFallbackAvailability()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundPriceRefresh.schedule()
                return
            }
            guard phase == .active, portfolio.needsRecomputeForNewDay() else { return }
            portfolio.recompute(context: modelContext)
        }
        .onDisappear {
            refreshStatusTask?.cancel()
            // Real abandonment, which is the only thing that should stop a
            // pass. The `task(id:)` above deliberately does not: its identity
            // is derived from the price records the refresh itself writes.
            refresh.cancelRefresh()
        }
    }

    @MainActor
    private func updateFallbackAvailability() async {
        let targets = (try? PriceRefreshTargets.make(
            context: modelContext,
            usesPriceFallback: usesPriceFallback,
            includeImported: true
        )) ?? []
        let pending = PriceRefreshController.staleTargets(
            from: targets,
            usesPriceFallback: usesPriceFallback
        ).count
        await refresh.updateFallbackAvailability(pending: pending)
    }

    private var fallbackAvailabilityTaskID: String {
        "\(scenePhase)-\(hasStartedPortfolio)-\(usesPriceFallback)"
    }

    private var isBrowseDebugRoute: Bool {
#if DEBUG
        return debugRoute == "Browse"
#else
        return false
#endif
    }

    private var isMovementDebugRoute: Bool {
#if DEBUG
        return debugRoute == "CardMovement"
#else
        return false
#endif
    }

    private var isCardDetailDebugRoute: Bool {
#if DEBUG
        return debugRoute == "CardDetail"
#else
        return false
#endif
    }

    @MainActor
    private func refreshAllPrices() async {
        refreshStatusTask?.cancel()
        let didRefresh = await MagicTreatmentMigrationCoordinator.shared.withPriceRefresh(
            in: modelContext
        ) {
            let request = PriceRefreshRequest(
                usesPriceFallback: usesPriceFallback,
                includeImported: true,
                forceUnsupportedRetry: true,
                sortOldestFirst: false,
                maximumTargetCount: nil,
                markRecentlyCheckedIfEmpty: true
            )
            return (await refresh.refresh(request, container: modelContext.container)).didRun
        }
        _ = didRefresh
        dismissRefreshStatusLater()
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
            let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
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
            CollectionCatalogNormalizer.recordCatalogMetadataCheck(on: row, at: .now)
        }
        try? modelContext.save()
    }
#endif
}

/// Legacy input-observer implementation removed in favour of the single
/// store-driven `StoreRevisionMonitor` in `Services/StoreRevisionMonitor.swift`.
