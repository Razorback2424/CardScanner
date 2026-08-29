import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var collectionActivities: [CollectionActivity]
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
    @StateObject private var history = PortfolioHistoryStore()
    /// One catalog actor is shared by every Collection/Browse route in this
    /// app session. Its protected checklist and in-memory caches therefore do
    /// not reset when the user pushes into a set and returns.
    @State private var browseCatalog: BrowseCatalog
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var collectionSort: CollectionSort = .priceHighToLow
    @State private var hasCheckedForStalePrices = false
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
        case "Browse", "SealedArtwork", "CardMovement": initialTab = .collection
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
                opensBrowseOnLaunch: isBrowseDebugRoute,
                opensMovementDetailsOnLaunch: isMovementDebugRoute,
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
            case "CardMovement":
                PortfolioDebugFixtures.seedMovementIfNeeded(in: modelContext)
                history.mode = .performance
                history.range = .oneMonth
            case "PortfolioToday", "PortfolioPhase3", "PortfolioContributors":
                PortfolioDebugFixtures.seedTodayIfNeeded(in: modelContext)
            case "PortfolioHistory":
                PortfolioDebugFixtures.seedHistoryIfNeeded(in: modelContext)
            default:
                break
            }
            try? CollectionStore(context: modelContext).backfillExistingCollectionIfNeeded()
            portfolio.start(context: modelContext)
            hasStartedPortfolio = true
        }
#else
        .task {
            try? CollectionStore(context: modelContext).backfillExistingCollectionIfNeeded()
            portfolio.start(context: modelContext)
            hasStartedPortfolio = true
        }
#endif
        // Portfolio truth is app-scoped: scanning or importing must recompute it
        // even if Collection has never been selected in this app session. The
        // ledger is synced separately from collection rows, so both tables are
        // part of the trigger; CloudKit can deliver either one first.
        .task(id: portfolioInputTaskID) {
            guard hasStartedPortfolio else { return }
            portfolio.recompute(context: modelContext)
            await refreshStalePricesIfNeeded()
        }
        .task(id: portfolioHistoryTaskID) {
            guard hasStartedPortfolio else { return }
            history.recompute(
                context: modelContext,
                summary: portfolio.summary,
                factors: portfolio.performanceFactors,
                contributions: portfolio.contributionIndex
            )
        }
        .task { await recomputeAtDayRollover() }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await browseCatalog.prepareCatalog()
            } else {
                await browseCatalog.suspendCatalogRefresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, portfolio.needsRecomputeForNewDay() else { return }
            portfolio.recompute(context: modelContext)
        }
        .onDisappear { refreshStatusTask?.cancel() }
    }

    private var portfolioInputTaskID: Int {
        var hasher = Hasher()
        hasher.combine(hasStartedPortfolio)

        for card in cards {
            hasher.combine(card.collectionKey)
            hasher.combine(card.quantity)
            hasher.combine(card.priceKey)
        }

        // Inventory events are synced independently from CollectedCard rows.
        // Include payload fields, not just the count, so a late-arriving event
        // or a repaired conflicting row causes a fresh reconciliation pass.
        for event in inventoryEvents {
            hasher.combine(event.eventID)
            hasher.combine(event.idempotencyKey)
            hasher.combine(event.kindRaw)
            hasher.combine(event.sourceRaw)
            hasher.combine(event.collectionKey)
            hasher.combine(event.priceStorageKey)
            hasher.combine(event.deltaQuantity)
            hasher.combine(event.occurredAt)
            hasher.combine(event.unitPriceUSDTenThousandths)
            hasher.combine(event.reversesEventID)
        }

        for activity in collectionActivities {
            hasher.combine(activity.id)
            hasher.combine(activity.kindRaw)
            hasher.combine(activity.collectionKey)
            hasher.combine(activity.deltaQuantity)
            hasher.combine(activity.quantity)
            hasher.combine(activity.resolvedQuantity)
            hasher.combine(activity.ledgerOperationIDs)
        }

        // Price records can arrive independently through CloudKit. Include
        // their value and freshness fields so the portfolio is recomputed when
        // another device changes the evidence it is valued from.
        for record in priceRecords {
            hasher.combine(record.key)
            hasher.combine(record.effectiveUnitMarketPriceUSD)
            hasher.combine(record.currencyCode)
            hasher.combine(record.sourceRaw)
            hasher.combine(record.sourceUpdatedAt)
            hasher.combine(record.fetchedAt)
            hasher.combine(record.lastSuccessfulCheckAt)
            hasher.combine(record.invalidatedAt)
        }

        hasher.combine(cards.count)
        hasher.combine(inventoryEvents.count)
        hasher.combine(collectionActivities.count)
        hasher.combine(priceRecords.count)
        return hasher.finalize()
    }

    private var portfolioHistoryTaskID: String {
        "\(portfolio.inputRevision)-\(history.mode.rawValue)-\(history.range.rawValue)"
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
                        amount: record?.effectiveUnitMarketPriceUSD,
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
