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
}

@MainActor
final class CollectionProjectionStore: ObservableObject {
    @Published private(set) var snapshot: CollectionProjectionSnapshot?
    @Published private(set) var revision: UInt = 0
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false

    private var rebuildTask: Task<Void, Never>?
    private var rebuildRequested = false
    private static let maximumReadAttempts = 3
    private static let readRetryDelay: Duration = .milliseconds(80)

    func rebuild(container: ModelContainer) async {
        rebuildRequested = true
        guard rebuildTask == nil else {
            await rebuildTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.rebuildTask = nil }

            while self.rebuildRequested {
                self.rebuildRequested = false
                self.loadFailed = false
                var snapshot: CollectionProjectionSnapshot?
                var readSucceeded = false
                for attempt in 0..<Self.maximumReadAttempts {
                    let actor = CollectionProjectionActor(modelContainer: container)
                    let candidate = await actor.snapshot()
                    if await actor.readSucceeded() {
                        snapshot = candidate
                        readSucceeded = true
                        break
                    }
                    guard attempt + 1 < Self.maximumReadAttempts else { break }
                    try? await Task.sleep(for: Self.readRetryDelay)
                    guard !Task.isCancelled else { return }
                }
                guard readSucceeded, let snapshot else {
                    // A request can arrive while the actor is suspended for
                    // its final read. Preserve that request instead of turning
                    // a transient failure into another dropped rebuild.
                    if self.rebuildRequested {
                        continue
                    }
                    // Keep the failure visible. A later SwiftData save or the
                    // explicit retry affordance can make progress without
                    // leaving the tab on an infinite loading spinner.
                    self.loadFailed = true
                    return
                }
                guard !Task.isCancelled else { return }

                // Serialize overlapping requests and let the newest read win.
                // A refresh or CloudKit merge can invalidate the view while the
                // actor is fetching; returning here would leave that change
                // without a projection retry.
                guard !self.rebuildRequested else {
                    self.rebuildRequested = true
                    continue
                }
                if self.snapshot != snapshot {
                    self.snapshot = snapshot
                    self.revision &+= 1
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
actor CollectionProjectionActor {
    private var lastReadSucceeded = false

    func readSucceeded() -> Bool { lastReadSucceeded }

    func snapshot() -> CollectionProjectionSnapshot {
        let signpostState = PerformanceSignpost.signposter
            .beginInterval("makeCachedProjection")
        defer {
            PerformanceSignpost.signposter
                .endInterval("makeCachedProjection", signpostState)
        }

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
            lastReadSucceeded = false
            return CollectionProjectionSnapshot(
                rows: [],
                rowsByCollectionKey: [:],
                diagnosticsByCollectionKey: [:],
                physicalRowCountsByKey: [:],
                ownership: CatalogOwnershipIndex(rows: [])
            )
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
                    price: record?.display ?? .unknown,
                    priceStorageKey: position.priceStorageKey,
                    magicTreatmentIDsRaw: card.magicTreatmentIDsRaw,
                    magicTreatmentQualifiers: card.magicTreatmentQualifiers,
                    itemKind: card.itemKind,
                    itemKindLabel: card.itemKindLabel,
                    gradingCompany: card.gradingCompany,
                    gradeValue: card.gradeRaw,
                    lowImageURL: card.lowImageURL,
                    highImageURL: card.highImageURL,
                    userArtworkFilename: artworkByKey[card.collectionKey]?.filename
                        ?? card.userArtworkFilename,
                    normalizedName: CardNameSearch.normalize(card.name),
                    collectorNumberSortKey: CollectorNumber.key(for: card.cardNumber)
                )
            )
            diagnostics[card.collectionKey] = CollectionRowDiagnostics(
                unpricedReason: record?.effectiveUnitMarketPriceUSD == nil
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
            ownership: CatalogOwnershipIndex(rows: cards.map(CatalogOwnershipCardSnapshot.init))
        )
        lastReadSucceeded = true
        return snapshot
    }
}
