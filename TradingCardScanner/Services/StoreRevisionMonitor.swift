import Combine
import OSLog
import SwiftData
import SwiftUI

/// One off-main read of the durable inputs that can drive a derived snapshot.
/// The hashes are session-local change tokens, not persisted identifiers.
struct StoreRevisionFingerprint: Equatable, Sendable {
    let cards: Int
    let cardCount: Int
    let inventoryEvents: Int
    let collectionActivities: Int
    let priceValues: Int
    let priceShape: Int
    let artwork: Int
    let magicCards: Int
    let stalePriceCollectionFingerprint: Int
    let stalePriceTargetFingerprint: Int
}

@MainActor
final class StoreRevisionStore: ObservableObject {
    @Published private(set) var revision: UInt = 0
    private var fingerprint: StoreRevisionFingerprint?
    private var expectedPriceValuesFingerprint: Int?

    func publish(_ fingerprint: StoreRevisionFingerprint) {
        guard self.fingerprint != fingerprint else { return }
        self.fingerprint = fingerprint
        revision &+= 1
    }

    /// The refresh controller has already applied deltas and settled the one
    /// terminal portfolio replay. The next store fingerprint with this exact
    /// price value hash is therefore durable confirmation of work already
    /// handled, not a second input event.
    func expectPriceValuesFingerprint(_ value: Int) {
        expectedPriceValuesFingerprint = value
    }

    func consumeExpectedPriceValues(_ value: Int) -> Bool {
        guard let expected = expectedPriceValuesFingerprint else { return false }
        expectedPriceValuesFingerprint = nil
        return expected == value
    }
}

enum StoreRevisionFingerprinting {
    static func priceValues(_ records: [PriceRecord]) -> Int {
        var hasher = Hasher()
        for record in records.sorted(by: { $0.key < $1.key }) {
            hasher.combine(record.key)
            hasher.combine(record.effectiveUnitMarketPriceUSD)
            hasher.combine(record.currencyCode)
            hasher.combine(record.sourceRaw)
            hasher.combine(record.sourceUpdatedAt)
            hasher.combine(record.fetchedAt)
            hasher.combine(record.lastCheckedAt)
            hasher.combine(record.lastSuccessfulCheckAt)
            hasher.combine(record.invalidatedAt)
            hasher.combine(record.lastFailureAt)
            hasher.combine(record.lastFailureReasonRaw)
        }
        return hasher.finalize()
    }
}

/// Coordinates one logical durable-write operation. Scanner sessions and CSV
/// imports can perform many saves, but derived consumers only need the final
/// store state. The generation changes once when the outermost operation ends,
/// which gives the monitor one trailing observation to reconcile everything.
@MainActor
final class DerivedStateWriteCoordinator: ObservableObject {
    @Published private(set) var generation: UInt = 0
    private var depth = 0
    private var bulkIntervalState: OSSignpostIntervalState?

    var isBulkWriteInFlight: Bool { depth > 0 }

    func beginBulkWrite() {
        if depth == 0 {
            bulkIntervalState = PerformanceSignpost.beginInterval(
                "derivedStateBulkWrite",
                id: PerformanceSignpost.makeID(),
                "generation=\(generation)"
            )
        }
        depth += 1
    }

    func endBulkWrite() {
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0 else { return }
        let completedGeneration = generation
        generation &+= 1
        if let bulkIntervalState {
            PerformanceSignpost.endInterval(
                "derivedStateBulkWrite",
                bulkIntervalState,
                "generation=\(completedGeneration)"
            )
        }
        bulkIntervalState = nil
    }
}

/// The app-scoped invalidation bridge for durable SwiftData changes. Its body
/// does not materialize or hash any table; it advances a counter and lets the
/// model actor decide which table revisions actually changed.
struct StoreRevisionMonitor: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var writeCoordinator: DerivedStateWriteCoordinator

    let portfolio: PortfolioEngine
    let projectionStore: CollectionProjectionStore
    let priceSnapshot: PriceSnapshotStore
    let revisionStore: StoreRevisionStore
    let refresh: PriceRefreshController
    let hasStartedPortfolio: Bool

    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var saveGeneration: UInt = 0
    @State private var previousFingerprint: StoreRevisionFingerprint?
    /// Multiple debounced observations can overlap while a derived store is
    /// suspended. Only the newest apply may commit its fingerprint; otherwise
    /// an older continuation can move the token backwards after a newer one
    /// has already finished.
    @State private var applyGeneration: UInt = 0
    /// One automatic pass per target set, rather than one pass per view
    /// lifetime. A card arriving from CloudKit or an import must be eligible
    /// immediately even when the monitor already ran earlier in the session.
    @State private var lastStalePriceTargetFingerprint: Int?
    /// Metadata and vendor bindings are written by the refresh itself. While
    /// that pass is active, those fields must not enqueue a second pass for the
    /// same collection. A changed collection identity still queues a trailing
    /// request so a card arriving from sync/import is not lost.
    @State private var activeStalePriceCollectionFingerprint: Int?
    @State private var hasEstablishedMagicTreatmentBaseline = false

    var body: some View {
        PerformanceSignpost.signposter.emitEvent("StoreRevisionMonitor.body")
        let observation = "\(hasStartedPortfolio)-\(saveGeneration)-\(writeCoordinator.generation)"

        return Color.clear
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                saveGeneration &+= 1
            }
            .task(id: observation) {
                guard hasStartedPortfolio, !writeCoordinator.isBulkWriteInFlight else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, !writeCoordinator.isBulkWriteInFlight else { return }

                let actor = StoreRevisionModelActor(modelContainer: modelContext.container)
                let fingerprint = await actor.fingerprint()
                guard await actor.readSucceeded() else { return }
                guard !Task.isCancelled, !writeCoordinator.isBulkWriteInFlight else { return }
                revisionStore.publish(fingerprint)
                await apply(fingerprint)
            }
    }

    @MainActor
    private func apply(_ fingerprint: StoreRevisionFingerprint) async {
        let generation = applyGeneration &+ 1
        applyGeneration = generation

        guard let previousFingerprint else {
            self.previousFingerprint = fingerprint
            return
        }
        guard !writeCoordinator.isBulkWriteInFlight else { return }

        let cardsChanged = fingerprint.cards != previousFingerprint.cards
        let inventoryChanged = fingerprint.inventoryEvents != previousFingerprint.inventoryEvents
        let activitiesChanged = fingerprint.collectionActivities != previousFingerprint.collectionActivities
        let pricesChanged = fingerprint.priceValues != previousFingerprint.priceValues
        let priceShapeChanged = fingerprint.priceShape != previousFingerprint.priceShape
        let artworkChanged = fingerprint.artwork != previousFingerprint.artwork
        let magicChanged = fingerprint.magicCards != previousFingerprint.magicCards
        let controllerOwnedPriceChange = pricesChanged
            && revisionStore.consumeExpectedPriceValues(fingerprint.priceValues)

        PerformanceSignpost.emitEvent(
            "storeRevisionApply",
            "cards=\(cardsChanged ? 1 : 0),inventory=\(inventoryChanged ? 1 : 0),activities=\(activitiesChanged ? 1 : 0),prices=\(pricesChanged ? 1 : 0),shape=\(priceShapeChanged ? 1 : 0),artwork=\(artworkChanged ? 1 : 0),magic=\(magicChanged ? 1 : 0)"
        )

        if pricesChanged || cardsChanged || artworkChanged {
            // During a refresh, deltas already update this store in O(changed).
            // The terminal controller rebuild remains authoritative, so avoid
            // turning each durable checkpoint into a second whole-table read.
            if !isRefreshInFlight && !controllerOwnedPriceChange {
                let state = PerformanceSignpost.beginInterval(
                    "storeRevision.priceSnapshotRebuild",
                    id: PerformanceSignpost.makeID(),
                    "generation=\(generation)"
                )
                await priceSnapshot.rebuild(container: modelContext.container)
                PerformanceSignpost.endInterval(
                    "storeRevision.priceSnapshotRebuild",
                    state,
                    "generation=\(generation)"
                )
            }
        }

        if cardsChanged || priceShapeChanged || artworkChanged {
            let state = PerformanceSignpost.beginInterval(
                "storeRevision.projectionRebuild",
                id: PerformanceSignpost.makeID(),
                "generation=\(generation)"
            )
            await projectionStore.rebuild(container: modelContext.container)
            PerformanceSignpost.endInterval(
                "storeRevision.projectionRebuild",
                state,
                "generation=\(generation)"
            )
        }

        if cardsChanged || inventoryChanged || activitiesChanged {
            CollectionStore(context: modelContext).invalidateIdentityAliasCache()
            // Establish the baseline before the stale-price pass can begin.
            // Once a pass is already in flight, its terminal gate owns the one
            // trailing replay instead.
            if !isRefreshInFlight {
                let portfolioState = PerformanceSignpost.beginInterval(
                    "storeRevision.portfolioRecompute",
                    id: PerformanceSignpost.makeID(),
                    "generation=\(generation)"
                )
                await portfolio.recomputeAndWait(context: modelContext)
                PerformanceSignpost.endInterval(
                    "storeRevision.portfolioRecompute",
                    portfolioState,
                    "generation=\(generation)"
                )
            }
            let refreshState = PerformanceSignpost.beginInterval(
                "storeRevision.refreshStalePrices",
                id: PerformanceSignpost.makeID(),
                "generation=\(generation)"
            )
            await refreshStalePricesIfNeeded(using: fingerprint)
            PerformanceSignpost.endInterval(
                "storeRevision.refreshStalePrices",
                refreshState,
                "generation=\(generation)"
            )
        } else if pricesChanged && !isRefreshInFlight && !controllerOwnedPriceChange {
            CollectionStore(context: modelContext).invalidateIdentityAliasCache()
            let portfolioState = PerformanceSignpost.beginInterval(
                "storeRevision.portfolioRecompute",
                id: PerformanceSignpost.makeID(),
                "generation=\(generation)"
            )
            await portfolio.recomputeAndWait(context: modelContext)
            PerformanceSignpost.endInterval(
                "storeRevision.portfolioRecompute",
                portfolioState,
                "generation=\(generation)"
            )
            let refreshState = PerformanceSignpost.beginInterval(
                "storeRevision.refreshStalePrices",
                id: PerformanceSignpost.makeID(),
                "generation=\(generation)"
            )
            await refreshStalePricesIfNeeded(using: fingerprint)
            PerformanceSignpost.endInterval(
                "storeRevision.refreshStalePrices",
                refreshState,
                "generation=\(generation)"
            )
        }

        if magicChanged {
            guard hasEstablishedMagicTreatmentBaseline else {
                hasEstablishedMagicTreatmentBaseline = true
                guard generation == applyGeneration else { return }
                self.previousFingerprint = fingerprint
                return
            }
            MagicTreatmentMigrationCoordinator.shared.invalidateCompletedReports()
            let migrationState = PerformanceSignpost.beginInterval(
                "storeRevision.magicMigration",
                id: PerformanceSignpost.makeID(),
                "generation=\(generation)"
            )
            _ = await MagicTreatmentMigrationCoordinator.shared.runNetwork(in: modelContext)
            PerformanceSignpost.endInterval(
                "storeRevision.magicMigration",
                migrationState,
                "generation=\(generation)"
            )
            guard !Task.isCancelled else { return }
            if isRefreshInFlight {
                let portfolioState = PerformanceSignpost.beginInterval(
                    "storeRevision.portfolioRecompute",
                    id: PerformanceSignpost.makeID(),
                    "generation=\(generation),mode=queued"
                )
                portfolio.recompute(context: modelContext)
                PerformanceSignpost.endInterval(
                    "storeRevision.portfolioRecompute",
                    portfolioState,
                    "generation=\(generation),mode=queued"
                )
            } else {
                let portfolioState = PerformanceSignpost.beginInterval(
                    "storeRevision.portfolioRecompute",
                    id: PerformanceSignpost.makeID(),
                    "generation=\(generation),mode=wait"
                )
                await portfolio.recomputeAndWait(context: modelContext)
                PerformanceSignpost.endInterval(
                    "storeRevision.portfolioRecompute",
                    portfolioState,
                    "generation=\(generation),mode=wait"
                )
            }
        }

        // Commit only after every derived consumer has settled. The generation
        // guard prevents an older apply, resumed after a newer one, from
        // overwriting the newer coalescing token.
        guard generation == applyGeneration else { return }
        self.previousFingerprint = fingerprint
    }

    private var isRefreshInFlight: Bool {
        refresh.isPassInFlight
    }

    @MainActor
    private func refreshStalePricesIfNeeded(
        using fingerprint: StoreRevisionFingerprint
    ) async {
        guard fingerprint.cardCount > 0 else { return }
        let targetFingerprint = fingerprint.stalePriceTargetFingerprint
        if isRefreshInFlight,
           let activeCollectionFingerprint = activeStalePriceCollectionFingerprint,
           activeCollectionFingerprint == fingerprint.stalePriceCollectionFingerprint {
            // The active pass owns its catalog metadata, vendor binding, and
            // price writes. Do not turn those writes into a metered retry.
            return
        }
        guard lastStalePriceTargetFingerprint != targetFingerprint else { return }
        lastStalePriceTargetFingerprint = targetFingerprint
        activeStalePriceCollectionFingerprint = fingerprint.stalePriceCollectionFingerprint
        let result = await MagicTreatmentMigrationCoordinator.shared.withPriceRefresh(
            in: modelContext
        ) {
            let request = PriceRefreshRequest(
                usesPriceFallback: usesPriceFallback,
                includeImported: true,
                forceUnsupportedRetry: false,
                sortOldestFirst: false,
                maximumTargetCount: nil,
                markRecentlyCheckedIfEmpty: false
            )
            return await refresh.refresh(request, container: modelContext.container)
        }
        activeStalePriceCollectionFingerprint = nil
        if result.targetBuildFailed {
            lastStalePriceTargetFingerprint = nil
        } else {
            // The pass may have changed a vendor binding or catalog metadata.
            // Keep the pre-pass token; the next didSave fingerprint will decide
            // whether that target-set change needs a trailing pass.
            lastStalePriceTargetFingerprint = targetFingerprint
        }
        guard result.didRun else { return }
        refresh.dismissTransientSuccessSummary()
    }
}

/// History is derived from portfolio publications, but it must not make the
/// whole-table revision monitor observe every portfolio or history change. A
/// child view gives that dependency a narrow observation boundary.
struct StoreRevisionHistoryMonitor: View {
    @Environment(\.modelContext) private var modelContext

    @ObservedObject var portfolio: PortfolioEngine
    @ObservedObject var history: PortfolioHistoryStore
    let hasStartedPortfolio: Bool

    private var taskID: String {
        "\(hasStartedPortfolio)-\(portfolio.inputRevision)-\(history.range.rawValue)"
    }

    var body: some View {
        Color.clear.task(id: taskID) {
            guard hasStartedPortfolio else { return }
            history.recompute(
                context: modelContext,
                summary: portfolio.summary,
                factors: portfolio.performanceFactors,
                contributions: portfolio.contributionIndex
            )
        }
    }
}

@ModelActor
actor StoreRevisionModelActor {
    private var lastReadSucceeded = false

    func readSucceeded() -> Bool { lastReadSucceeded }

    func fingerprint() -> StoreRevisionFingerprint {
        do {
            let fingerprint = try makeFingerprint()
            lastReadSucceeded = true
            return fingerprint
        } catch {
            lastReadSucceeded = false
            return StoreRevisionFingerprint(
                cards: 0,
                cardCount: 0,
                inventoryEvents: 0,
                collectionActivities: 0,
                priceValues: 0,
                priceShape: 0,
                artwork: 0,
                magicCards: 0,
                stalePriceCollectionFingerprint: 0,
                stalePriceTargetFingerprint: 0
            )
        }
    }

    private func makeFingerprint() throws -> StoreRevisionFingerprint {
        let cards = try modelContext.fetch(FetchDescriptor<CollectedCard>())
            .sorted { $0.collectionKey < $1.collectionKey }
        let inventoryEvents = try modelContext.fetch(FetchDescriptor<InventoryEvent>())
            .sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        let collectionActivities = try modelContext.fetch(FetchDescriptor<CollectionActivity>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let priceRecords = try modelContext.fetch(FetchDescriptor<PriceRecord>())
            .sorted { $0.key < $1.key }
        let artworkOverrides = try modelContext.fetch(FetchDescriptor<LocalArtworkOverride>())
            .sorted {
                if $0.collectionKey != $1.collectionKey {
                    return $0.collectionKey < $1.collectionKey
                }
                return $0.filename < $1.filename
            }

        var cardHasher = Hasher()
        var magicHasher = Hasher()
        var stalePriceCollectionHasher = Hasher()
        var stalePriceTargetHasher = Hasher()
        for card in cards {
            cardHasher.combine(card.collectionKey)
            cardHasher.combine(card.quantity)
            cardHasher.combine(card.dateAdded)
            cardHasher.combine(card.priceKey)
            cardHasher.combine(card.name)
            cardHasher.combine(card.game)
            cardHasher.combine(card.setName)
            cardHasher.combine(card.setCode)
            cardHasher.combine(card.cardNumber)
            cardHasher.combine(card.variantID)
            cardHasher.combine(card.variantLabel)
            cardHasher.combine(card.magicTreatmentIDsRaw)
            cardHasher.combine(card.magicTreatmentQualifiersJSON)
            cardHasher.combine(card.itemKindRaw)
            cardHasher.combine(card.gradingCompanyRaw)
            cardHasher.combine(card.gradeRaw)
            cardHasher.combine(card.lowImageURL)
            cardHasher.combine(card.highImageURL)
            cardHasher.combine(card.userArtworkFilename)
            cardHasher.combine(card.setReleaseOrder)
            cardHasher.combine(card.catalogMetadataCheckedAt != nil)
            cardHasher.combine(card.catalogMetadataVersion)
            cardHasher.combine(card.catalogProviderID)
            cardHasher.combine(card.gradeLabel)
            cardHasher.combine(card.gradingQualifier)

            stalePriceCollectionHasher.combine(card.collectionKey)
            stalePriceCollectionHasher.combine(card.itemKindRaw)
            stalePriceTargetHasher.combine(card.collectionKey)
            stalePriceTargetHasher.combine(card.priceKey)
            stalePriceTargetHasher.combine(card.itemKindRaw)
            stalePriceTargetHasher.combine(card.catalogProviderID)
            stalePriceTargetHasher.combine(card.justTCGCardID)
            stalePriceTargetHasher.combine(card.justTCGVariantID)
            stalePriceTargetHasher.combine(card.catalogMetadataVersion)

            if card.cardGame == .magic {
                magicHasher.combine(card.collectionKey)
                magicHasher.combine(card.quantity)
                magicHasher.combine(card.variantID)
                magicHasher.combine(card.magicTreatmentMigrationVersion)
                magicHasher.combine(card.magicTreatmentIDsRaw)
            }
        }

        var inventoryHasher = Hasher()
        for event in inventoryEvents {
            inventoryHasher.combine(event.eventID)
            inventoryHasher.combine(event.idempotencyKey)
            inventoryHasher.combine(event.kindRaw)
            inventoryHasher.combine(event.sourceRaw)
            inventoryHasher.combine(event.collectionKey)
            inventoryHasher.combine(event.priceStorageKey)
            inventoryHasher.combine(event.deltaQuantity)
            inventoryHasher.combine(event.occurredAt)
            inventoryHasher.combine(event.unitPriceUSDTenThousandths)
            inventoryHasher.combine(event.reversesEventID)
        }

        var activityHasher = Hasher()
        for activity in collectionActivities {
            activityHasher.combine(activity.id)
            activityHasher.combine(activity.kindRaw)
            activityHasher.combine(activity.collectionKey)
            activityHasher.combine(activity.deltaQuantity)
            activityHasher.combine(activity.quantity)
            activityHasher.combine(activity.resolvedQuantity)
            activityHasher.combine(activity.ledgerOperationIDs)
        }

        var priceShapeHasher = Hasher()
        for record in priceRecords {
            priceShapeHasher.combine(record.key)
            priceShapeHasher.combine(record.game)
            priceShapeHasher.combine(record.magicTreatmentIDsRaw)
        }

        var artworkHasher = Hasher()
        for override in artworkOverrides {
            artworkHasher.combine(override.collectionKey)
            artworkHasher.combine(override.filename)
        }

        return StoreRevisionFingerprint(
            cards: cardHasher.finalize(),
            cardCount: cards.count,
            inventoryEvents: inventoryHasher.finalize(),
            collectionActivities: activityHasher.finalize(),
            priceValues: StoreRevisionFingerprinting.priceValues(priceRecords),
            priceShape: priceShapeHasher.finalize(),
            artwork: artworkHasher.finalize(),
            magicCards: magicHasher.finalize(),
            stalePriceCollectionFingerprint: stalePriceCollectionHasher.finalize(),
            stalePriceTargetFingerprint: stalePriceTargetHasher.finalize()
        )
    }
}
