import Combine
import SwiftData
import SwiftUI

/// One off-main read of the durable inputs that can drive a derived snapshot.
/// The hashes are session-local change tokens, not persisted identifiers.
struct StoreRevisionFingerprint: Equatable, Sendable {
    let cards: Int
    let inventoryEvents: Int
    let collectionActivities: Int
    let priceValues: Int
    let priceShape: Int
    let artwork: Int
    let magicCards: Int
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
            hasher.combine(record.invalidatedAt)
            hasher.combine(record.lastFailureAt)
            hasher.combine(record.lastFailureReasonRaw)
        }
        return hasher.finalize()
    }
}

/// A reference that lets the monitor's body advance an O(1) observation token.
/// It deliberately publishes nothing: the token only restarts the debounced
/// actor read after SwiftData has invalidated this view.
@MainActor
private final class StoreRevisionTicker: ObservableObject {
    private var value: UInt = 0

    func next() -> UInt {
        value &+= 1
        return value
    }
}

/// The only app view that observes whole-table SwiftData queries. Its body does
/// not hash or project those rows; it advances a counter and lets the model
/// actor decide which table revisions actually changed.
struct StoreRevisionMonitor: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var collectionActivities: [CollectionActivity]
    @Query private var priceRecords: [PriceRecord]
    @Query private var artworkOverrides: [LocalArtworkOverride]

    let portfolio: PortfolioEngine
    let projectionStore: CollectionProjectionStore
    let priceSnapshot: PriceSnapshotStore
    let revisionStore: StoreRevisionStore
    let refresh: PriceRefreshController
    let hasStartedPortfolio: Bool

    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @StateObject private var ticker = StoreRevisionTicker()
    @State private var previousFingerprint: StoreRevisionFingerprint?
    @State private var hasCheckedForStalePrices = false
    @State private var hasEstablishedMagicTreatmentBaseline = false

    var body: some View {
        PerformanceSignpost.signposter.emitEvent("StoreRevisionMonitor.body")
        let observation = ticker.next()
        // Touch each @Query without walking it. SwiftData invalidation causes
        // this body to run for field changes as well as insert/delete changes.
        let _ = cards.count
        let _ = inventoryEvents.count
        let _ = collectionActivities.count
        let _ = priceRecords.count
        let _ = artworkOverrides.count

        return Color.clear
            .task(id: observation) {
                guard hasStartedPortfolio else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                let actor = StoreRevisionModelActor(modelContainer: modelContext.container)
                let fingerprint = await actor.fingerprint()
                guard !Task.isCancelled else { return }
                revisionStore.publish(fingerprint)
                await apply(fingerprint)
            }
    }

    @MainActor
    private func apply(_ fingerprint: StoreRevisionFingerprint) async {
        guard let previousFingerprint else {
            self.previousFingerprint = fingerprint
            return
        }
        // This monitor is driven by the unstructured MainActor task above. The
        // fingerprint read and every await below are non-throwing, and there is
        // no cancellation exit inside `apply`, so this assignment is safe as
        // the coalescing token. If this becomes a throwing/structured child,
        // move it to the terminal path after the derived work completes.
        self.previousFingerprint = fingerprint

        let cardsChanged = fingerprint.cards != previousFingerprint.cards
        let inventoryChanged = fingerprint.inventoryEvents != previousFingerprint.inventoryEvents
        let activitiesChanged = fingerprint.collectionActivities != previousFingerprint.collectionActivities
        let pricesChanged = fingerprint.priceValues != previousFingerprint.priceValues
        let priceShapeChanged = fingerprint.priceShape != previousFingerprint.priceShape
        let artworkChanged = fingerprint.artwork != previousFingerprint.artwork
        let magicChanged = fingerprint.magicCards != previousFingerprint.magicCards
        let controllerOwnedPriceChange = pricesChanged
            && revisionStore.consumeExpectedPriceValues(fingerprint.priceValues)

        if pricesChanged || cardsChanged || artworkChanged {
            // During a refresh, deltas already update this store in O(changed).
            // The terminal controller rebuild remains authoritative, so avoid
            // turning each durable checkpoint into a second whole-table read.
            if !isRefreshInFlight && !controllerOwnedPriceChange {
                await priceSnapshot.rebuild(container: modelContext.container)
            }
        }

        if cardsChanged || priceShapeChanged || artworkChanged {
            await projectionStore.rebuild(container: modelContext.container)
        }

        if cardsChanged || inventoryChanged || activitiesChanged {
            CollectionStore(context: modelContext).invalidateIdentityAliasCache()
            // Establish the baseline before the stale-price pass can begin.
            // Once a pass is already in flight, its terminal gate owns the one
            // trailing replay instead.
            if !isRefreshInFlight {
                await portfolio.recomputeAndWait(context: modelContext)
            }
            await refreshStalePricesIfNeeded()
        } else if pricesChanged && !isRefreshInFlight && !controllerOwnedPriceChange {
            CollectionStore(context: modelContext).invalidateIdentityAliasCache()
            await portfolio.recomputeAndWait(context: modelContext)
            await refreshStalePricesIfNeeded()
        }

        if magicChanged {
            guard hasEstablishedMagicTreatmentBaseline else {
                hasEstablishedMagicTreatmentBaseline = true
                return
            }
            MagicTreatmentMigrationCoordinator.shared.invalidateCompletedReports()
            _ = await MagicTreatmentMigrationCoordinator.shared.runNetwork(in: modelContext)
            guard !Task.isCancelled else { return }
            if isRefreshInFlight {
                portfolio.recompute(context: modelContext)
            } else {
                await portfolio.recomputeAndWait(context: modelContext)
            }
        }
    }

    private var isRefreshInFlight: Bool {
        refresh.isPassInFlight
    }

    @MainActor
    private func refreshStalePricesIfNeeded() async {
        guard !hasCheckedForStalePrices, !cards.isEmpty else { return }
        hasCheckedForStalePrices = true
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
        if result.targetBuildFailed {
            hasCheckedForStalePrices = false
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
        "\(hasStartedPortfolio)-\(portfolio.inputRevision)-\(history.mode.rawValue)-\(history.range.rawValue)"
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
    func fingerprint() -> StoreRevisionFingerprint {
        let cards = ((try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? [])
            .sorted { $0.collectionKey < $1.collectionKey }
        let inventoryEvents = ((try? modelContext.fetch(FetchDescriptor<InventoryEvent>())) ?? [])
            .sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        let collectionActivities = ((try? modelContext.fetch(FetchDescriptor<CollectionActivity>())) ?? [])
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let priceRecords = ((try? modelContext.fetch(FetchDescriptor<PriceRecord>())) ?? [])
            .sorted { $0.key < $1.key }
        let artworkOverrides = ((try? modelContext.fetch(FetchDescriptor<LocalArtworkOverride>())) ?? [])
            .sorted {
                if $0.collectionKey != $1.collectionKey {
                    return $0.collectionKey < $1.collectionKey
                }
                return $0.filename < $1.filename
            }

        var cardHasher = Hasher()
        var magicHasher = Hasher()
        for card in cards {
            cardHasher.combine(card.collectionKey)
            cardHasher.combine(card.quantity)
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
            inventoryEvents: inventoryHasher.finalize(),
            collectionActivities: activityHasher.finalize(),
            priceValues: StoreRevisionFingerprinting.priceValues(priceRecords),
            priceShape: priceShapeHasher.finalize(),
            artwork: artworkHasher.finalize(),
            magicCards: magicHasher.finalize()
        )
    }
}
