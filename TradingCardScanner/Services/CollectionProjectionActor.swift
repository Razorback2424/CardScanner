import Foundation
import SwiftData

struct CollectionRowDiagnostics: Equatable, Sendable {
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
}

/// The collection projection is a value snapshot. Model objects are used only
/// while the actor reads the store; no live row crosses into the grid.
struct CollectionProjectionSnapshot: Equatable, Sendable {
    let rows: [CollectionRow]
    let rowsByCollectionKey: [String: CollectionRow]
    let diagnosticsByCollectionKey: [String: CollectionRowDiagnostics]
    let physicalRowCountsByKey: [String: Int]
    let ownership: CatalogOwnershipIndex

    /// `rowsByCollectionKey` is constructed deterministically from `rows` by
    /// the actor. It is a lookup index for consumers, not independent state;
    /// comparing it again makes every main-actor rebuild walk the same data a
    /// second time.
    static func == (
        lhs: CollectionProjectionSnapshot,
        rhs: CollectionProjectionSnapshot
    ) -> Bool {
        lhs.rows == rhs.rows
            && lhs.diagnosticsByCollectionKey == rhs.diagnosticsByCollectionKey
            && lhs.physicalRowCountsByKey == rhs.physicalRowCountsByKey
            && lhs.ownership == rhs.ownership
    }
}

@MainActor
final class CollectionProjectionStore: ObservableObject {
    @Published private(set) var snapshot: CollectionProjectionSnapshot?
    @Published private(set) var revision: UInt = 0
    @Published private(set) var cardOwnershipRevision: UInt = 0
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false

    private var rebuildTask: Task<Void, Never>?
    private var rebuildRequested = false
    private var requestedContainer: ModelContainer?
    private var requestedToken: StorageGenerationToken?
    private let workerSlot = BackgroundModelActorSlot<CollectionProjectionActor>()
    private static let maximumReadAttempts = 3
    private static let readRetryDelay: Duration = .milliseconds(80)

    func rebuild(container: ModelContainer) async {
        let storage = CollectionStorageGeneration.shared
        let token = storage.activeSession()?.container === container ? storage.currentToken() : nil
        if let requestedContainer, requestedContainer !== container || requestedToken != token {
            if snapshot != nil {
                snapshot = nil
                revision &+= 1
                cardOwnershipRevision &+= 1
            }
            isLoaded = false
        }
        requestedContainer = container
        requestedToken = token
        rebuildRequested = true
        guard rebuildTask == nil else {
            await rebuildTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.rebuildTask = nil }

            while self.rebuildRequested, let currentContainer = self.requestedContainer {
                self.rebuildRequested = false
                self.loadFailed = false
                let currentToken = self.requestedToken
                let actor = await self.workerSlot.worker(for: currentContainer, token: currentToken)
                var snapshot: CollectionProjectionSnapshot?
                for attempt in 0..<Self.maximumReadAttempts {
                    guard !Task.isCancelled,
                          currentToken.map(storage.isCurrent) ?? true else { break }
                    snapshot = await actor.readSnapshot()
                    if snapshot != nil || self.rebuildRequested { break }
                    guard attempt + 1 < Self.maximumReadAttempts else { break }
                    try? await Task.sleep(for: Self.readRetryDelay)
                }
                guard !Task.isCancelled else { return }
                // A save or store transition can request a newer read while
                // this one is in flight, including after a failed attempt.
                guard !self.rebuildRequested else { continue }
                guard currentToken.map(storage.isCurrent) ?? true else { return }
                guard let snapshot else {
                    // Keep the failure visible. A later SwiftData save or the
                    // explicit retry affordance can make progress without
                    // leaving the tab on an infinite loading spinner.
                    self.loadFailed = true
                    return
                }
                if self.snapshot != snapshot {
                    let ownershipChanged = self.snapshot?.ownership.hasSameCardOwnership(as: snapshot.ownership) != true
                    self.snapshot = snapshot
                    self.revision &+= 1
                    if ownershipChanged { self.cardOwnershipRevision &+= 1 }
                }
                self.isLoaded = true
                self.loadFailed = false
            }
        }
        rebuildTask = task
        await task.value
    }
}

/// Mirrors the portfolio computation boundary: fetch, project, elect the
/// representative and derive diagnostics away from the main actor.
@ModelActor
actor CollectionProjectionActor: BackgroundModelActor {
    init(modelContainer: ModelContainer, modelExecutor: any ModelExecutor) {
        self.modelContainer = modelContainer
        self.modelExecutor = modelExecutor
    }

    func snapshot() -> CollectionProjectionSnapshot {
        readSnapshot() ?? CollectionProjectionSnapshot(
            rows: [],
            rowsByCollectionKey: [:],
            diagnosticsByCollectionKey: [:],
            physicalRowCountsByKey: [:],
            ownership: CatalogOwnershipIndex(rows: [])
        )
    }

    func readSnapshot() -> CollectionProjectionSnapshot? {
        let signpostState = PerformanceSignpost.signposter
            .beginInterval("makeCachedProjection")
        defer {
            PerformanceSignpost.signposter
                .endInterval("makeCachedProjection", signpostState)
        }

        let modelContext = ModelContext(modelContainer)
        defer { withExtendedLifetime(modelContext) {} }
        let cards: [CollectedCard]
        let records: [PriceRecord]
        let artworkOverrides: [LocalArtworkOverride]
        do {
            cards = try modelContext.fetch(
                FetchDescriptor<CollectedCard>(
                    sortBy: [SortDescriptor(\CollectedCard.dateAdded, order: .reverse)]
                )
            )
            records = try modelContext.fetch(FetchDescriptor<PriceRecord>())
            artworkOverrides = try modelContext.fetch(FetchDescriptor<LocalArtworkOverride>())
        } catch {
            return nil
        }
        let recordsByKey = Dictionary(grouping: records, by: \.key)
            .compactMapValues(PriceStore.authoritativeRecord(in:))
        let keySelection = PriceRecordKeySelection(records: Array(recordsByKey.values))
        let artworkByKey = Dictionary(grouping: artworkOverrides, by: \.collectionKey)
            .compactMapValues { rows in
                rows.max {
                    if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                    return $0.filename < $1.filename
                }
            }
        let localArtworkKeys = Set(artworkByKey.keys)
        let projection = LogicalCollection.project(cards: cards) { card in
            keySelection.priceStorageKey(for: card)
        }

        var rows: [CollectionRow] = []
        var diagnostics: [String: CollectionRowDiagnostics] = [:]
        rows.reserveCapacity(projection.positions.count)
        for position in projection.positions {
            let card = position.representative
            let record = recordsByKey[position.priceStorageKey]
            let artworkFilename = artworkByKey[card.collectionKey]?.filename
                ?? card.userArtworkFilename
            rows.append(
                CollectionRow(
                    id: card.collectionKey,
                    game: card.cardGame,
                    name: card.name,
                    setCode: card.setCode,
                    setName: card.setName,
                    setReleaseOrder: card.setReleaseOrder,
                    cardNumber: card.cardNumber,
                    variantID: card.variantID,
                    variantLabel: card.variantLabel,
                    quantity: position.quantity,
                    dateAdded: position.dateAdded,
                    price: PokemonReviewedPhysicalObjects.requiresReview(card) ? .unknown : (record?.display ?? .unknown),
                    priceStorageKey: position.priceStorageKey,
                    magicTreatmentIDsRaw: card.magicTreatmentIDsRaw,
                    magicTreatmentQualifiers: card.magicTreatmentQualifiers,
                    itemKind: card.itemKind,
                    itemKindLabel: card.itemKindLabel,
                    gradingCompany: card.gradingCompany,
                    gradeValue: card.gradeRaw,
                    lowImageURL: card.lowImageURL,
                    highImageURL: card.highImageURL,
                    userArtworkFilename: artworkFilename,
                    catalogProviderID: card.underlyingPrintingID,
                    pokemonPrintRun: card.pokemonPrintRun,
                    normalizedName: CardNameSearch.normalize(card.name),
                    collectorNumberSortKey: CollectorNumber.key(for: card.cardNumber),
                    variantResolution: card.variantResolution,
                    artworkAccent: ArtworkAccentStore.cachedAccent(localFilename: artworkFilename)
                )
            )
            diagnostics[card.collectionKey] = CollectionRowDiagnostics(
                unpricedReason: PokemonReviewedPhysicalObjects.requiresReview(card) || record?.effectiveUnitMarketPriceUSD == nil
                    ? PricingDiagnostics.unpricedReason(for: card, record: record)
                    : nil,
                artworkReason: ArtworkDiagnostics.reason(
                    for: card,
                    hasLocalOverride: localArtworkKeys.contains(card.collectionKey)
                )
            )
        }

        let snapshot = CollectionProjectionSnapshot(
            rows: rows,
            rowsByCollectionKey: Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, $0) }
            ),
            diagnosticsByCollectionKey: diagnostics,
            physicalRowCountsByKey: projection.byKey.mapValues(\.physicalRowCount),
            ownership: CatalogOwnershipIndex(rows: cards.map { card in
                let key = keySelection.priceStorageKey(for: card)
                return CatalogOwnershipCardSnapshot(card, selectedPriceKey: key,
                    selectedPrice: PokemonReviewedPhysicalObjects.requiresReview(card)
                        ? .unknown : (recordsByKey[key]?.display ?? .unknown))
            })
        )
        return snapshot
    }
}
