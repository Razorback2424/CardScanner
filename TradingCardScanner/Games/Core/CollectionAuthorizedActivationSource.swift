import Foundation
import SwiftData

/// An adapter's exact market mappings, indexed by the existing persisted price key.
/// Absence withdraws managed-provider quotes, never user-entered prices.
struct GameCatalogPriceAuthority: Sendable {
    let game: CardGame
    let managedSources: Set<PriceSource>
    let identityByPriceKey: [String: String]

    func install(in container: ModelContainer, at date: Date = .now) throws {
        try install(in: container, at: date, beforeSave: nil)
    }

    #if DEBUG
    func install(in container: ModelContainer, at date: Date = .now,
                 beforeSaveForTesting: ((ModelContext) throws -> Void)?) throws {
        try install(in: container, at: date, beforeSave: beforeSaveForTesting)
    }
    #endif

    private func install(in container: ModelContainer, at date: Date,
                         beforeSave: ((ModelContext) throws -> Void)?) throws {
        try CollectionWriteSerializer.perform(container: container,
            timeout: Thread.isMainThread ? .mainThread : .wait) { context in
            try install(in: context, at: date, beforeSave: beforeSave)
        }
    }

    /// The caller owns the serializer through price withdrawal and catalog
    /// publication. Never release it between these two authority changes.
    fileprivate func install(in context: ModelContext, at date: Date = .now,
                             beforeSave: ((ModelContext) throws -> Void)? = nil) throws {
            precondition(CollectionWriteSerializer.isHeldByCurrentThread)
            let gameID = game.rawValue
            let records = try context.fetch(FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.game == gameID }))
            let quotes = try context.fetch(FetchDescriptor<ReferenceQuote>(predicate: #Predicate { $0.game == gameID }))
            let log = PriceObservationLog(context: context)
            for record in records {
                guard let source = record.source, managedSources.contains(source), !record.isInvalidated,
                      identityByPriceKey[record.key] == nil || record.catalogPriceIdentity != identityByPriceKey[record.key] else { continue }
                let watermark = max(date, record.fetchedAt ?? .distantPast)
                _ = log.recordInvalidation(instrumentKey: record.key, source: source, at: watermark)
                // Also withdraw a checked-but-null record with no prior value/log row.
                _ = record.invalidate(at: watermark)
            }
            for quote in quotes {
                guard let source = quote.source, managedSources.contains(source), quote.invalidatedAt == nil,
                      identityByPriceKey[quote.key] == nil || quote.catalogPriceIdentity != identityByPriceKey[quote.key] else { continue }
                quote.invalidatedAt = max(date, quote.retrievedAt ?? .distantPast)
            }
            if context.hasChanges {
                try beforeSave?(context)
                try context.save()
            }
    }
}

/// Every consumer shares one container-bound publication boundary. SwiftData
/// withdrawal and collection validation authority are installed before yield.
@MainActor
final class CollectionAuthorizedActivationSource: GameCatalogActivationSource {
    nonisolated let game: CardGame
    private let source: any GameCatalogActivationSource
    private let container: ModelContainer
    private let isCurrent: @MainActor @Sendable () -> Bool
    private let capabilities: GameCatalogCapabilityState?
    private var accepted: GameCatalogSnapshot?
    #if DEBUG
    private var beforeSaveForTesting: ((ModelContext) throws -> Void)?

    func setBeforeSaveForTesting(_ hook: ((ModelContext) throws -> Void)?) {
        beforeSaveForTesting = hook
    }
    #endif

    init(source: any GameCatalogActivationSource, container: ModelContainer,
         isCurrent: @escaping @MainActor @Sendable () -> Bool = { true },
         capabilities: GameCatalogCapabilityState? = nil) {
        self.source = source; self.container = container; game = source.game
        self.isCurrent = isCurrent
        self.capabilities = capabilities
    }

    private func accept(_ snapshot: GameCatalogSnapshot) -> GameCatalogSnapshot? {
        guard isCurrent(), snapshot.catalog.game == game, snapshot.revision >= 0,
              snapshot.priceAuthority == nil || snapshot.priceAuthority?.game == game else { return nil }
        if let accepted {
            if snapshot.revision < accepted.revision { return accepted }
            if snapshot.revision == accepted.revision {
                return snapshot.catalog.generation == accepted.catalog.generation ? accepted : nil
            }
        }
        do {
            let installed = try CollectionWriteSerializer.perform(container: container, timeout: .mainThread) { context in
                guard CollectionStore.canInstallCatalogAdapter(snapshot.catalog, revision: snapshot.revision, for: container) else { return false }
                #if DEBUG
                try snapshot.priceAuthority?.install(in: context, beforeSave: beforeSaveForTesting)
                #else
                try snapshot.priceAuthority?.install(in: context)
                #endif
                guard CollectionStore.installCatalogAdapter(snapshot.catalog, revision: snapshot.revision, for: container) else { return false }
                if let next = snapshot.capabilities { capabilities?.install(next, for: game) }
                return true
            }
            guard installed else { return nil }
        }
        catch { return nil } // No new authority or UI generation on a failed save.
        accepted = snapshot
        return snapshot
    }

    func currentSnapshot() async -> GameCatalogSnapshot? {
        guard isCurrent() else { return nil }
        guard let snapshot = await source.currentSnapshot() else { return accepted }
        return accept(snapshot)
    }

    func activationSnapshots() async -> AsyncStream<GameCatalogSnapshot> {
        let events = await source.activationSnapshots()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor [weak self] in
                for await snapshot in events {
                    guard !Task.isCancelled, let self else { break }
                    if let installed = self.accept(snapshot) { continuation.yield(installed) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func refreshAtLaunch() async { await source.refreshAtLaunch() }
}
