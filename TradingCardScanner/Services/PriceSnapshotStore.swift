import Combine
import Foundation
import SwiftData

/// One committed price value crossing the refresh boundary. The key is the
/// persisted instrument key, not a collection-row id, so every copy and every
/// consumer converges on the same value.
struct PriceDelta: Equatable, Sendable {
    let key: String
    let display: PriceDisplay
}

/// The value snapshot built away from the main actor. `revision` is assigned by
/// the app-scoped store when a new value is published.
struct PriceSnapshot: Equatable, Sendable {
    var prices: [String: PriceDisplay]
    var diagnosticsByCollectionKey: [String: PriceSnapshotDiagnostics]
    /// The same instrument-resolution decision used by the collection grid.
    /// Keeping this index in the value snapshot lets a price delta repair the
    /// small diagnostic payload without re-reading the card table on the main
    /// actor.
    var priceStorageKeyByCollectionKey: [String: String]
}

struct PriceSnapshotDiagnostics: Equatable, Sendable {
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
}

/// Main-actor presentation store for prices and their small diagnostic payload.
/// SwiftData remains the durable source; this is the explicit UI value channel.
@MainActor
final class PriceSnapshotStore: ObservableObject {
    static let shared = PriceSnapshotStore()

    private static let maxRebuildAttempts = 3
    private static let rebuildRetryDelay: Duration = .milliseconds(50)

    @Published private(set) var prices: [String: PriceDisplay] = [:]
    @Published private(set) var diagnosticsByCollectionKey: [String: PriceSnapshotDiagnostics] = [:]
    @Published private(set) var priceStorageKeyByCollectionKey: [String: String] = [:]
    @Published private(set) var revision: UInt = 0

    private var bootstrapTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var rebuildRequested = false
    private var collectionKeysByPriceKey: [String: [String]] = [:]

    func display(for key: String?) -> PriceDisplay? {
        guard let key else { return nil }
        return prices[key]
    }

    /// Applies only values that changed. A refresh may send repeated keys across
    /// checkpoint boundaries; those do not cause another publication.
    func apply(_ deltas: [PriceDelta]) {
        var changed = false
        for delta in deltas {
            if prices[delta.key] != delta.display {
                prices[delta.key] = delta.display
                changed = true
            }

            // A projection can correctly retain its shape while the answer for
            // its existing instrument changes from "unpriced" to priced. Clear
            // only the stale price diagnosis here; artwork and the exact
            // failure reason remain projection facts until the authoritative
            // rebuild at pass completion.
            guard delta.display.amount != nil else { continue }
            for collectionKey in collectionKeysByPriceKey[delta.key] ?? [] {
                guard var diagnostics = diagnosticsByCollectionKey[collectionKey],
                      diagnostics.unpricedReason != nil else { continue }
                diagnostics = PriceSnapshotDiagnostics(
                    unpricedReason: nil,
                    artworkReason: diagnostics.artworkReason
                )
                diagnosticsByCollectionKey[collectionKey] = diagnostics
                changed = true
            }
        }
        if changed {
            revision &+= 1
            if rebuildTask != nil { rebuildRequested = true }
        }
    }

    /// Replaces the authoritative snapshot in one main-actor publication.
    func replace(with snapshot: PriceSnapshot) {
        guard prices != snapshot.prices
            || diagnosticsByCollectionKey != snapshot.diagnosticsByCollectionKey
            || priceStorageKeyByCollectionKey != snapshot.priceStorageKeyByCollectionKey else {
            return
        }
        prices = snapshot.prices
        diagnosticsByCollectionKey = snapshot.diagnosticsByCollectionKey
        priceStorageKeyByCollectionKey = snapshot.priceStorageKeyByCollectionKey
        collectionKeysByPriceKey = Dictionary(
            grouping: snapshot.priceStorageKeyByCollectionKey,
            by: { $0.value }
        ).mapValues { $0.map(\.key) }
        revision &+= 1
    }

    /// Starts the off-main initial read once per app lifetime. A failed read is
    /// retried by the next explicit rebuild rather than poisoning the store with
    /// a fabricated empty snapshot.
    func bootstrap(container: ModelContainer) async {
        guard bootstrapTask == nil else {
            await bootstrapTask?.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rebuild(container: container)
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    func rebuild(container: ModelContainer) async {
        rebuildRequested = true
        guard rebuildTask == nil else {
            await rebuildTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.rebuildTask = nil }
            var completedAttempts = 0
            while self.rebuildRequested,
                  completedAttempts < Self.maxRebuildAttempts {
                completedAttempts += 1
                self.rebuildRequested = false
                let startingRevision = self.revision
                let actor = PriceSnapshotModelActor(modelContainer: container)
                let snapshot = await actor.snapshot()
                guard await actor.readSucceeded() else { return }
                guard !Task.isCancelled else { return }

                // A delta or another requested rebuild landed while the actor
                // was reading. Do not overwrite it with an older whole-store
                // read; loop and take a fresh authoritative snapshot instead.
                guard self.revision == startingRevision, !self.rebuildRequested else {
                    self.rebuildRequested = true
                    continue
                }
                self.replace(with: snapshot)
            }

            guard self.rebuildRequested else { return }

            // A provider can still be delivering deltas while the actor is
            // reading. Yield to the caller, then retry as a new bounded task;
            // never let a continuously changing store create an unbounded
            // actor-read loop or lose the final snapshot.
            let container = container
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.rebuildRetryDelay)
                guard !Task.isCancelled else { return }
                await self?.rebuild(container: container)
            }
        }
        rebuildTask = task
        await task.value
    }
}

/// Reads the durable store once on its own model-actor executor. The UI never
/// needs to hash or refetch a whole price table after an individual delta.
@ModelActor
actor PriceSnapshotModelActor {
    private var lastGoodSnapshot: PriceSnapshot?
    private var lastReadSucceeded = false

    func readSucceeded() -> Bool { lastReadSucceeded }

    func snapshot() -> PriceSnapshot {
        let records: [PriceRecord]
        let cards: [CollectedCard]
        let artworkOverrides: [LocalArtworkOverride]
        do {
            records = try modelContext.fetch(FetchDescriptor<PriceRecord>())
            cards = try modelContext.fetch(FetchDescriptor<CollectedCard>())
            artworkOverrides = try modelContext.fetch(FetchDescriptor<LocalArtworkOverride>())
        } catch {
            lastReadSucceeded = false
            return lastGoodSnapshot ?? PriceSnapshot(
                prices: [:],
                diagnosticsByCollectionKey: [:],
                priceStorageKeyByCollectionKey: [:]
            )
        }

        let recordsByKey = Dictionary(grouping: records, by: \.key)
            .compactMapValues(PriceStore.authoritativeRecord(in:))
        let keySelection = PriceRecordKeySelection(records: Array(recordsByKey.values))
        let prices = recordsByKey.mapValues(\.display)
        let localArtworkKeys = Set(artworkOverrides.map(\.collectionKey))
        var diagnostics: [String: PriceSnapshotDiagnostics] = [:]
        var priceStorageKeys: [String: String] = [:]
        for card in cards {
            let priceStorageKey = keySelection.priceStorageKey(for: card)
            let record = recordsByKey[priceStorageKey]
            priceStorageKeys[card.collectionKey] = priceStorageKey
            diagnostics[card.collectionKey] = PriceSnapshotDiagnostics(
                unpricedReason: record?.effectiveUnitMarketPriceUSD == nil
                    ? PricingDiagnostics.unpricedReason(for: card, record: record)
                    : nil,
                artworkReason: ArtworkDiagnostics.reason(
                    for: card,
                    hasLocalOverride: localArtworkKeys.contains(card.collectionKey)
                )
            )
        }
        let snapshot = PriceSnapshot(
            prices: prices,
            diagnosticsByCollectionKey: diagnostics,
            priceStorageKeyByCollectionKey: priceStorageKeys
        )
        lastGoodSnapshot = snapshot
        lastReadSucceeded = true
        return snapshot
    }
}
