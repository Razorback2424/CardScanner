import Foundation
import SwiftData

enum QuoteEvidenceOrdering {
    static func isNewer(_ candidate: NormalizedPrice, than previous: NormalizedPrice, game: CardGame,
                        now: Date = .now) -> Bool {
        guard game == .pokemon else { return candidate.fetchedAt > previous.fetchedAt }
        switch (candidate.source, previous.source) {
        case (.tcgplayer, .tcgCSV), (.tcgCSV, .tcgplayer):
            let embed = candidate.source == .tcgplayer ? candidate : previous
            let mirror = candidate.source == .tcgCSV ? candidate : previous
            return PokemonPriceSelection.preferred(embed: embed, tcgCSV: mirror, now: now) == candidate
        default: break
        }
        guard candidate.fetchedAt >= previous.fetchedAt else { return false }
        if previous.sourceUpdatedAt != nil, candidate.sourceUpdatedAt == nil { return false }
        if candidate.sourceUpdatedAt != nil, previous.sourceUpdatedAt == nil {
            return candidate.effectiveAsOf > previous.effectiveAsOf
        }
        if candidate.effectiveAsOf != previous.effectiveAsOf {
            return candidate.effectiveAsOf > previous.effectiveAsOf
        }
        return candidate.fetchedAt > previous.fetchedAt
    }

    static func isNewer(_ candidate: NormalizedPrice, thanHintCheckedAt checkedAt: Date, game: CardGame) -> Bool {
        (game == .pokemon ? candidate.effectiveAsOf : candidate.fetchedAt) > checkedAt
    }
}

/// An exact provider answer that a printing and finish has no USD quote.
struct ConfirmedQuoteMiss: Equatable, Sendable {
    let source: PriceSource
    let checkedAt: Date
}

/// Persistence boundary for non-collection price knowledge.
///
/// There is deliberately no path from this service to `PriceObservationLog`,
/// `PriceCheckDay`, or `PriceRecord`.
struct QuoteCache {
    let context: ModelContext

    func quote(
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String] = []
    ) -> ReferenceQuote? {
        let key = ReferenceQuote.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
        var descriptor = FetchDescriptor<ReferenceQuote>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func store(
        _ lookup: PriceLookup,
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now,
        treatmentIDs: [String] = [],
        isReplay: Bool = false,
        successfulCheckAt: Date? = nil,
        saveImmediately: Bool = true
    ) -> ReferenceQuote {
        let record = quote(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) ?? {
            let created = ReferenceQuote(
                key: ReferenceQuote.key(
                    game: game,
                    printingID: printingID,
                    variantID: variantID,
                    treatmentIDs: treatmentIDs
                ),
                game: game,
                printingID: printingID,
                variantID: variantID,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            return created
        }()
        if record.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
            record.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        }
        record.apply(lookup, at: date, isReplay: isReplay)
        // Check completion is independent of which quote won the evidence comparison.
        // Never infer success from lastCheckedAt: that field includes failures.
        if let successfulCheckAt, case let .price(price) = lookup, price.isUsableUSD,
           record.lastSuccessfulCheckAt.map({ successfulCheckAt >= $0 }) ?? true {
            record.lastSuccessfulCheckAt = successfulCheckAt
        }
        if saveImmediately { save() }
        return record
    }

    @discardableResult
    func storeIfNewer(_ price: NormalizedPrice, key: CatalogQuoteKey, successfulCheckAt: Date,
                      saveImmediately: Bool = true) -> NormalizedPrice? {
        let previous = quote(game: key.game, printingID: key.printingID,
            variantID: key.variantID, treatmentIDs: key.treatmentIDs)?.normalizedPrice
        guard price.isUsableUSD, !price.sourceVariantID.isEmpty else { return previous }
        if let previous, !QuoteEvidenceOrdering.isNewer(price, than: previous, game: key.game) {
            return previous
        }
        return store(.price(price), game: key.game, printingID: key.printingID, variantID: key.variantID,
            at: successfulCheckAt, treatmentIDs: key.treatmentIDs, successfulCheckAt: successfulCheckAt,
            saveImmediately: saveImmediately).normalizedPrice
    }

    /// Marks an existing quote as disproved by a later exact check from the
    /// same source. Never creates a row and never clears the dated amount.
    func recordConfirmedMiss(_ miss: ConfirmedQuoteMiss, key: CatalogQuoteKey) {
        guard let record = quote(game: key.game, printingID: key.printingID,
                                 variantID: key.variantID, treatmentIDs: key.treatmentIDs),
              record.source == miss.source,
              miss.checkedAt > (record.retrievedAt ?? .distantPast),
              record.lastConfirmedMissAt.map({ miss.checkedAt > $0 }) ?? true else { return }
        record.lastConfirmedMissAt = miss.checkedAt
    }

    @discardableResult
    func recordFailure(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now,
        treatmentIDs: [String] = [],
        saveImmediately: Bool = true
    ) -> ReferenceQuote {
        let record = quote(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) ?? {
            let created = ReferenceQuote(
                key: ReferenceQuote.key(
                    game: game,
                    printingID: printingID,
                    variantID: variantID,
                    treatmentIDs: treatmentIDs
                ),
                game: game,
                printingID: printingID,
                variantID: variantID,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            return created
        }()
        if record.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
            record.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        }
        record.recordFailure(at: date)
        if saveImmediately { save() }
        return record
    }

    /// Quote persistence is intentionally best effort, but a failed save must
    /// not leave this context dirty for the next Price Check or collection
    /// mutation. Production Price Check contexts are separate from collection
    /// ownership state as well.
    @discardableResult
    fileprivate func save() -> Bool {
        guard context.hasChanges else { return true }
        let signpost = PerformanceSignpost.beginInterval("PriceCheck.quoteSave", id: PerformanceSignpost.makeID(), "")
        do {
            try context.save()
            PerformanceSignpost.endInterval("PriceCheck.quoteSave", signpost, "ok")
            return true
        } catch {
            context.rollback()
            PerformanceSignpost.endInterval("PriceCheck.quoteSave", signpost, "rollback")
            return false
        }
    }
}

@ModelActor
actor ReferenceQuoteStore: BackgroundModelActor {
    private var isCurrent: StorageGenerationContinuation = { true }

    init(modelContainer: ModelContainer, modelExecutor: any ModelExecutor) {
        self.modelContainer = modelContainer
        self.modelExecutor = modelExecutor
    }

    @MainActor
    static func forActiveSession(expectedToken: StorageGenerationToken?) async -> ReferenceQuoteStore? {
        let generation = CollectionStorageGeneration.shared
        guard let token = expectedToken, generation.isCurrent(token),
              let container = generation.activeSession()?.container else {
            return nil
        }
        let store = await makeBackground(modelContainer: container)
        guard generation.isCurrent(token) else { return nil }
        await store.setContinuation(generation.continuation(for: token))
        return store
    }

    func setContinuation(_ continuation: @escaping StorageGenerationContinuation) {
        isCurrent = continuation
    }

    /// `excludingConfirmedMisses` is for surfaces that promote a quote to a
    /// current price. Last-known presentation still reads the dated amount.
    func quotes(forKeys keys: [String], now: Date = .now,
                excludingConfirmedMisses: Bool = false) -> [String: NormalizedPrice] {
        guard isCurrent(), !keys.isEmpty, !Task.isCancelled else { return [:] }
        let context = ModelContext(modelContainer)
        var result: [String: NormalizedPrice] = [:]
        for start in stride(from: 0, to: keys.count, by: 256) {
            let chunk = Array(keys[start..<min(start + 256, keys.count)])
            let descriptor = FetchDescriptor<ReferenceQuote>(predicate: #Predicate { chunk.contains($0.key) })
            guard let quotes = try? context.fetch(descriptor) else { continue }
            for quote in quotes {
                if excludingConfirmedMisses, quote.hasConfirmedMiss { continue }
                guard let price = quote.normalizedPrice,
                      CollectionStore.acceptsCatalogPrice(price, game: CardGame(rawValue: quote.game),
                                                          key: quote.key, in: modelContainer),
                      TCGCSVPriceMirror.canServe(source: price.source, capturedAt: price.fetchedAt, now: now) else { continue }
                if let existing = result[quote.key],
                   !QuoteEvidenceOrdering.isNewer(price, than: existing, game: CardGame(rawValue: quote.game), now: now) { continue }
                result[quote.key] = price
            }
        }
        return isCurrent() ? result : [:]
    }

    func store(_ batch: [CatalogQuoteKey: NormalizedPrice], successfulCheckAt: Date) {
        guard !batch.isEmpty, isCurrent(), !Task.isCancelled else { return }
        // Browse can still display and sort the live quote during an ownership write.
        try? CollectionWriteSerializer.perform(container: modelContainer, timeout: .immediate) { context in
            let cache = QuoteCache(context: context)
            for (key, price) in batch where CollectionStore.acceptsCatalogPrice(price, game: key.game,
                key: key.rawValue, in: modelContainer) {
                cache.storeIfNewer(price, key: key, successfulCheckAt: successfulCheckAt, saveImmediately: false)
            }
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            cache.save()
        }
    }

    /// Persists exact checks that found no USD quote, so a relaunched Browse
    /// does not promote the disproved amount. Only the quote's own source can
    /// disprove it; a failed or incomplete check is never passed here.
    func recordConfirmedMisses(_ misses: [CatalogQuoteKey: ConfirmedQuoteMiss]) {
        guard !misses.isEmpty, isCurrent(), !Task.isCancelled else { return }
        try? CollectionWriteSerializer.perform(container: modelContainer, timeout: .immediate) { context in
            let cache = QuoteCache(context: context)
            for (key, miss) in misses {
                cache.recordConfirmedMiss(miss, key: key)
            }
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            cache.save()
        }
    }

    func recordPriceCheck(_ lookup: PriceLookup, key: CatalogQuoteKey, at date: Date,
                          isReplay: Bool, successfulCheckAt: Date?) async {
        await writePriceCheck { cache in
            if let price = lookup.usablePrice,
               !CollectionStore.acceptsCatalogPrice(price, game: key.game, key: key.rawValue, in: modelContainer) { return }
            var selected = lookup
            if let candidate = lookup.usablePrice,
               let previous = cache.quote(game: key.game, printingID: key.printingID,
                   variantID: key.variantID, treatmentIDs: key.treatmentIDs)?.normalizedPrice,
               !QuoteEvidenceOrdering.isNewer(candidate, than: previous, game: key.game) {
                selected = .price(previous)
            }
            cache.store(selected, game: key.game, printingID: key.printingID, variantID: key.variantID,
                at: date, treatmentIDs: key.treatmentIDs, isReplay: isReplay,
                successfulCheckAt: successfulCheckAt, saveImmediately: false)
        }
    }

    func recordPriceCheckFailure(key: CatalogQuoteKey, at date: Date) async {
        await writePriceCheck { cache in
            cache.recordFailure(game: key.game, printingID: key.printingID, variantID: key.variantID,
                at: date, treatmentIDs: key.treatmentIDs, saveImmediately: false)
        }
    }

    private func writePriceCheck(_ write: (QuoteCache) -> Void) async {
        let maximumAttempts = 10
        for attempt in 1...maximumAttempts {
            guard isCurrent(), !Task.isCancelled else { return }
            do {
                try CollectionWriteSerializer.perform(container: modelContainer, timeout: .immediate) { context in
                    guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                    let cache = QuoteCache(context: context)
                    write(cache)
                    guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                    cache.save()
                }
                return
            } catch CollectionStoreError.collectionBusy {
                // Reference quote persistence is best-effort. Keep a busy
                // ownership writer from indefinitely delaying later quotes.
                guard attempt < maximumAttempts else { return }
                do { try await Task.sleep(for: .milliseconds(80)) }
                catch { return }
            } catch { return }
        }
    }
}
