import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    private enum Tab: Hashable {
        case portfolio
        case collection
        case scan
        case centering
    }

    @State private var selectedTab: Tab
    @StateObject private var portfolio = PortfolioEngine()
    @StateObject private var refresh: PriceRefreshController
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
        _refresh = StateObject(wrappedValue: PriceRefreshController.shared)
        _browseCatalog = State(initialValue: BrowseCatalog())
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        debugRoute = route
        let initialTab: Tab
        switch route {
        case "Browse", "SealedArtwork", "CardMovement", "MagicTreatmentSlice4": initialTab = .collection
        case "PortfolioToday", "PortfolioPhase3", "PortfolioContributors", "PortfolioHistory": initialTab = .portfolio
        case "WholeCardScanner", "PriceCheck": initialTab = .scan
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
        .task(id: hasStartedPortfolio) {
            guard hasStartedPortfolio else { return }
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
            PortfolioInputObserver(
                portfolio: portfolio,
                history: history,
                refresh: refresh,
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

    @MainActor
    private func refreshAllPrices() async {
        refreshStatusTask?.cancel()
        let didRefresh = await MagicTreatmentMigrationCoordinator.shared.withPriceRefresh(
            in: modelContext
        ) {
            // Build the target snapshot inside the gate. The migration may have
            // changed both the row key and its treatment ids while the caller
            // was waiting, so a pre-gate snapshot is not safe to write with.
            let currentTargets: [PriceTarget]
            do {
                currentTargets = try PriceRefreshTargets.make(
                    context: modelContext,
                    usesPriceFallback: usesPriceFallback,
                    includeImported: true
                )
            } catch {
                return false
            }
            let targets = PriceRefreshController.staleTargets(
                from: currentTargets,
                usesPriceFallback: usesPriceFallback,
                forceUnsupportedRetry: true
            )
            guard !targets.isEmpty else {
                refresh.markRecentlyChecked()
                return false
            }
            await refresh.refresh(targets, container: modelContext.container)
            return true
        }
        if didRefresh {
            portfolio.recompute(context: modelContext)
        }
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

/// Watches the collection's inputs and drives the recomputes that depend on
/// them.
///
/// Its own view precisely so that deciding "did anything change?" is not paid
/// for on every unrelated redraw. Answering that means walking every row of
/// four tables, and the parent can re-render whenever a refresh publishes its
/// progress. The controller is therefore held as a plain reference rather than
/// an `ObservedObject`: this view calls it, but must never re-render because of
/// it.
private struct PortfolioInputObserver: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var collectionActivities: [CollectionActivity]
    @Query private var priceRecords: [PriceRecord]

    @ObservedObject var portfolio: PortfolioEngine
    @ObservedObject var history: PortfolioHistoryStore
    /// Deliberately unobserved. See the type's note.
    let refresh: PriceRefreshController
    let hasStartedPortfolio: Bool

    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var hasCheckedForStalePrices = false
    @State private var hasEstablishedMagicTreatmentBaseline = false

    var body: some View {
        Color.clear
            // The ledger is synced separately from collection rows, so both
            // tables are part of the trigger; CloudKit can deliver either first.
            .task(id: portfolioInputTaskID) {
                guard hasStartedPortfolio else { return }
                // A refresh pass or an arriving CloudKit batch changes these
                // tables many times in quick succession, and each change used to
                // buy its own full recompute. Settling first collapses the burst
                // into one; `task(id:)` cancels the sleep when the next change
                // supersedes it. This paces the recompute only — the identity
                // above is still derived from every payload field, because that
                // is what notices a late event or a repaired row.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
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
            // A collection row can arrive after the one-time launch migration,
            // including through CloudKit. Establish the launch snapshot first;
            // later Magic-row changes invalidate the memo and rerun enrichment.
            .task(id: magicTreatmentInputTaskID) {
                guard hasStartedPortfolio else { return }
                guard hasEstablishedMagicTreatmentBaseline else {
                    hasEstablishedMagicTreatmentBaseline = true
                    return
                }
                MagicTreatmentMigrationCoordinator.shared.invalidateCompletedReports()
                _ = await MagicTreatmentMigrationCoordinator.shared.runNetwork(in: modelContext)
                guard !Task.isCancelled else { return }
                portfolio.recompute(context: modelContext)
            }
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

    private var magicTreatmentInputTaskID: Int {
        var hasher = Hasher()
        hasher.combine(hasStartedPortfolio)
        let magicCards = cards.filter { $0.cardGame == .magic }
        hasher.combine(magicCards.count)
        for card in magicCards {
            hasher.combine(card.collectionKey)
            hasher.combine(card.quantity)
            hasher.combine(card.variantID)
            hasher.combine(card.magicTreatmentMigrationVersion)
            hasher.combine(card.magicTreatmentIDsRaw)
        }
        return hasher.finalize()
    }

    /// The controller owns the pass this starts, so a saved batch invalidating
    /// the id above cancels this caller without tearing the work down partway
    /// through and leaving the collection unrefreshed.
    @MainActor
    private func refreshStalePricesIfNeeded() async {
        guard !hasCheckedForStalePrices, !cards.isEmpty else { return }
        hasCheckedForStalePrices = true
        let didRefresh = await MagicTreatmentMigrationCoordinator.shared.withPriceRefresh(
            in: modelContext
        ) {
            let currentTargets: [PriceTarget]
            do {
                currentTargets = try PriceRefreshTargets.make(
                    context: modelContext,
                    usesPriceFallback: usesPriceFallback,
                    includeImported: true
                )
            } catch {
                hasCheckedForStalePrices = false
                return false
            }
            let targets = PriceRefreshController.staleTargets(
                from: currentTargets,
                usesPriceFallback: usesPriceFallback
            )
            guard !targets.isEmpty else { return false }
            await refresh.refresh(targets, container: modelContext.container)
            return true
        }
        guard didRefresh else { return }
        // The automatic stale check is silent when it works. When it does not,
        // the failure is still the app's to surface.
        refresh.dismissTransientSuccessSummary()
        portfolio.recompute(context: modelContext)
    }
}
