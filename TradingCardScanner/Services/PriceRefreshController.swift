import Foundation
import SwiftData

/// Applies the vendor identity and quote to a persisted graded row. Scanner
/// acquisition and background refresh share this path so both migrate the
/// unbound price lineage and write the exact same vendor quote key.
struct GradedVariantBindingReceipt: Sendable {
    let quote: PriceLookup
    let priceKey: String
    let wasAccepted: Bool
}

enum GradedVariantBinding {
    static func apply(
        _ variant: GradedVariant,
        to row: CollectedCard,
        store: PriceStore,
        context: ModelContext,
        variantID: String?,
        treatmentIDs: [String],
        at fetchedAt: Date
    ) throws -> GradedVariantBindingReceipt {
        if let currentID = row.justTCGVariantID, currentID != variant.id {
            throw CollectionStoreError.ledgerConflict(
                "graded row is already bound to a different market variant"
            )
        }
        if row.justTCGVariantID == nil {
            try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
                for: row,
                toMarketVariantID: variant.id,
                apiVersion: JustTCGV2GradedClient.apiVersion,
                in: context,
                index: store.index
            )
        }
        row.justTCGVariantID = variant.id
        row.justTCGCardID = variant.cardID ?? row.justTCGCardID
        row.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue

        return storeVariantQuote(
            variant,
            game: row.cardGame,
            printingID: row.priceStorageID,
            variantID: variantID,
            treatmentIDs: treatmentIDs,
            store: store,
            at: fetchedAt
        )
    }

    /// Preserves the provider-key quote path for refresh targets whose row has
    /// disappeared or cannot be resolved during the pass.
    static func storeUnboundVariantQuote(
        _ variant: GradedVariant,
        game: CardGame,
        variantID: String?,
        treatmentIDs: [String],
        store: PriceStore,
        at fetchedAt: Date
    ) -> GradedVariantBindingReceipt {
        storeVariantQuote(
            variant,
            game: game,
            printingID: "justtcg:v2:\(variant.id)",
            variantID: variantID,
            treatmentIDs: treatmentIDs,
            store: store,
            at: fetchedAt
        )
    }

    private static func storeVariantQuote(
        _ variant: GradedVariant,
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String],
        store: PriceStore,
        at fetchedAt: Date
    ) -> GradedVariantBindingReceipt {
        let quote: PriceLookup = if let amount = variant.marketPriceUSD {
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: amount,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: variant.id,
                    sourceUpdatedAt: variant.updatedAt,
                    fetchedAt: fetchedAt
                )
            )
        } else {
            .unavailable(.justTCG)
        }
        let priceKey = PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
        let wasAccepted = store.store(
            quote,
            game: game,
            printingID: printingID,
            variantID: variantID,
            marketVariantID: variant.id,
            treatmentIDs: treatmentIDs
        )
        if let record = store.record(forKey: priceKey) {
            if wasAccepted, variant.marketPriceUSD != nil {
                record.justTCGFetchedAt = fetchedAt
            }
            record.marketVariantID = variant.id
            record.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        }
        return GradedVariantBindingReceipt(
            quote: quote,
            priceKey: priceKey,
            wasAccepted: wasAccepted
        )
    }
}

/// The result of one catalog fetch during a refresh.
///
/// The outcome distinguishes an ordinary provider failure from cancellation so
/// leaving the collection cannot turn an abandoned request into a recorded check.
/// File scope rather than nested, so it cannot inherit the controller's
/// main-actor isolation.
fileprivate struct PriceFetchOutcome: Sendable {
    let printing: PriceTarget.Printing
    let result: Result

    enum Result: Sendable {
        case card(IdentifiedCard)
        case failed
        /// The provider itself could not be reached.
        case unreachable
        case cancelled
    }

    /// Errors that mean "the network or the host is the problem", as opposed to
    /// a provider that answered and had nothing.
    static func isUnreachable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .notConnectedToInternet, .networkConnectionLost,
             .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}

typealias PriceRefreshPokemonFetchOverride = @Sendable (
    PriceTarget.Printing
) async throws -> IdentifiedCard

/// A value-only description of a collection row observed before provider work.
/// Refresh passes retain these snapshots across awaits, then verify them again
/// in a fresh serialized context before applying any collection changes.
private struct RefreshRowIdentity: Sendable {
    let collectionKey: String
    let priceKey: String
    let providerID: String
    let variantID: String?
    let marketVariantID: String?
    let itemKind: CollectionItemKind
    let imageURLIsMissing: Bool
}

/// The pending-finish fields are treated as one compare-and-set value so a
/// stale refresh cannot clear or replace evidence recorded by a newer pass.
struct PendingCatalogFinishState: Equatable, Sendable {
    let id: String?
    let firstSeenAt: Date?
    let refreshID: UUID?

    static func read(from row: CollectedCard) -> Self {
        Self(
            id: row.pendingCatalogFinishID,
            firstSeenAt: row.pendingCatalogFinishFirstSeenAt,
            refreshID: row.pendingCatalogFinishRefreshID
        )
    }
}

/// A guarded, value-only collection-row update produced by asynchronous price
/// refresh work. These patches are applied only after the price-side checkpoint
/// has saved, using a fresh context under CollectionWriteSerializer.
struct RefreshRowPatch: Sendable {
    enum Change: Sendable {
        case catalogMetadata(ImportedCatalogMetadata, checkedAt: Date)
        case sealedArtwork(url: String?, checkedAt: Date)
        case vendorBinding(productID: String?, sku: String?)
        case gradedBinding(
            marketVariantID: String,
            marketCardID: String?,
            apiVersion: String
        )
        case pendingCatalogFinish(
            expected: PendingCatalogFinishState,
            replacement: PendingCatalogFinishState
        )
    }

    let collectionKey: String
    let expectedPriceKey: String
    let expectedVariantID: String?
    let expectedMarketVariantID: String?
    let change: Change

    fileprivate static func catalogMetadata(
        from card: IdentifiedCard,
        row: RefreshRowIdentity,
        checkedAt: Date
    ) -> Self {
        let imageURL: String?
        let thumbnailURL: String?
        let tcgplayerURL: String?
        switch card {
        case let .pokemon(pokemon, _):
            imageURL = pokemon.image
            thumbnailURL = pokemon.image.map { $0 + "/low.png" }
            tcgplayerURL = nil
        case let .magic(magic):
            imageURL = card.displayImageURL?.absoluteString
            thumbnailURL = card.thumbnailImageURL?.absoluteString
            tcgplayerURL = magic.purchaseURIs?.tcgplayer?.absoluteString
        }
        let metadata = ImportedCatalogMetadata(
            providerID: card.providerID,
            setCode: card.setCode,
            rarity: card.rarity,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            tcgplayerURL: tcgplayerURL,
            setReleaseOrder: card.setReleaseOrder
        )
        return Self(
            collectionKey: row.collectionKey,
            expectedPriceKey: row.priceKey,
            expectedVariantID: row.variantID,
            expectedMarketVariantID: row.marketVariantID,
            change: .catalogMetadata(metadata, checkedAt: checkedAt)
        )
    }
}

/// Performs one refresh queue on a context owned by this actor. The facade
/// below deliberately receives only value progress and result messages: a
/// SwiftData model object never has to cross back to the main actor while a
/// provider request is suspended.
@ModelActor
actor PriceRefreshModelActor {
    private let tcgdex = TCGdexService()
    private let scryfall = ScryfallService()
    private let importedResolver = ImportedCardResolver()
    private let fallbackService = ProductPriceService.shared
    private let sharedTransport = JustTCGTransport.shared

    private var refreshStore: PriceStore?
    private var identityStore: ProductIdentityStore?
    private var identityIndex: ProductIdentityIndex?
    private var artworkRowIdentitiesByPriceKey: [String: [RefreshRowIdentity]] = [:]
    private var identityRowIdentitiesByPriceKey: [String: [RefreshRowIdentity]] = [:]
    private var pendingRowPatches: [RefreshRowPatch] = []
    private var skippedRowPatchCount = 0
    private var activeFallbackLastCommitAt = Date.distantPast
    private var activeFallbackStagedWrites = 0
    private var priceKeysWritten: Set<String> = []
    private var storageContinuation: StorageGenerationContinuation?
    private var pokemonFetchOverride: PriceRefreshPokemonFetchOverride?

    func setPokemonFetchOverrideForTesting(_ override: PriceRefreshPokemonFetchOverride?) {
        pokemonFetchOverride = `override`
    }

    func run(
        _ request: PriceRefreshRequest,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void,
        shouldContinue: StorageGenerationContinuation?
    ) async -> PriceRefreshWorkOutcome {
        storageContinuation = shouldContinue
        guard shouldContinue?() ?? true else {
            return .cancelled(repairedFinishes: 0, backfilledFinishes: 0)
        }
        let runState = PerformanceSignpost.beginInterval(
            "priceRefresh.run",
            id: PerformanceSignpost.makeID(),
            "targets=unknown"
        )
        var runOutcome = "target-build-failed"
        var targetCount = "unknown"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.run",
                runState,
                "targets=\(targetCount),outcome=\(runOutcome)"
            )
        }
        let store = makeStore()
        let targets: [PriceTarget]
        do {
            let allTargets = try PriceRefreshTargets.make(
                context: modelContext,
                usesPriceFallback: request.usesPriceFallback,
                includeImported: request.includeImported
            )
            var staleTargets = PriceRefreshController.staleTargets(
                from: allTargets,
                usesPriceFallback: request.usesPriceFallback,
                forceUnsupportedRetry: request.forceUnsupportedRetry
            )
            if request.gradedOnly {
                staleTargets = staleTargets.filter { $0.itemKind == .gradedCard }
            }
            if request.sortOldestFirst {
                staleTargets.sort {
                    ($0.lastCheckedAt ?? .distantPast) < ($1.lastCheckedAt ?? .distantPast)
                }
            }
            if let maximumTargetCount = request.maximumTargetCount {
                targets = Array(staleTargets.prefix(maximumTargetCount))
            } else {
                targets = staleTargets
            }
        } catch {
            return .targetBuildFailed
        }
        guard shouldContinue?() ?? true else {
            return .cancelled(repairedFinishes: 0, backfilledFinishes: 0)
        }

        targetCount = String(targets.count)
        guard !targets.isEmpty else {
            runOutcome = "no-targets"
            return .noTargets
        }
        let result = await performRefresh(
            targets,
            request: request,
            store: store,
            progress: progress
        )
        runOutcome = switch result {
        case .noTargets: "no-targets"
        case .targetBuildFailed: "target-build-failed"
        case .cancelled(_, _): "cancelled"
        case .completed(_): "completed"
        }
        return result
    }

    private func makeStore() -> PriceStore {
        if let refreshStore { return refreshStore }
        // Both whole-table indexes are deliberately born on this executor. The
        // signposts exist to prove that the old main-actor materialisation has
        // actually moved, not merely that the network awaits moved.
        let store = PriceStore(
            context: modelContext,
            index: PriceRefreshDataIndex(context: modelContext)
        )
        refreshStore = store
        return store
    }

    fileprivate func priceValuesFingerprint() -> Int? {
        guard let records = try? modelContext.fetch(FetchDescriptor<PriceRecord>()) else {
            return nil
        }
        return StoreRevisionFingerprinting.priceValues(records)
    }

    private func rememberPriceKey(_ key: String) {
        priceKeysWritten.insert(key)
    }

    private func takePriceDeltas(from store: PriceStore) -> [PriceDelta] {
        let keys = priceKeysWritten.sorted()
        priceKeysWritten.removeAll()
        return keys.compactMap { key in
            store.record(forKey: key).map { PriceDelta(key: key, display: $0.display) }
        }
    }

    private func performRefresh(
        _ targets: [PriceTarget],
        request: PriceRefreshRequest,
        store: PriceStore,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void
    ) async -> PriceRefreshWorkOutcome {
        let refreshState = PerformanceSignpost.beginInterval(
            "priceRefresh.performRefresh",
            id: PerformanceSignpost.makeID(),
            "targets=\(targets.count)"
        )
        var refreshOutcome = "cancelled"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.performRefresh",
                refreshState,
                "targets=\(targets.count),outcome=\(refreshOutcome)"
            )
        }
        var priced = 0
        var failed = 0
        var latestSourceUpdate: Date?
        var checkedUnstampedProvider = false
        var changedPrices = false
        var persistenceFailed = false
        var gradedLookupMisses = 0
        var gradedTransportFailures = 0
        var reconciledDuplicateRecords = 0
        var repairedFinishes = 0
        var backfilledFinishes = 0
        var stagedPriced = 0
        var stagedChangedPrices = false
        var stagedDuplicateRepairs = store.reconcileDuplicateRecords()
        var stagedWriteCount = 0
        var lastCommitAt = Date.now
        priceKeysWritten.removeAll()
        pendingRowPatches.removeAll()
        skippedRowPatchCount = 0

        func stage(
            _ accepted: Bool,
            key: String? = nil,
            priced: Bool = false,
            changed: Bool = false
        ) {
            let stageState = PerformanceSignpost.beginInterval(
                "priceRefresh.stage",
                id: PerformanceSignpost.makeID(),
                "accepted=\(accepted ? 1 : 0),priced=\(priced ? 1 : 0),changed=\(changed ? 1 : 0)"
            )
            defer {
                PerformanceSignpost.endInterval(
                    "priceRefresh.stage",
                    stageState,
                    "accepted=\(accepted ? 1 : 0)"
                )
            }
            guard accepted else {
                persistenceFailed = true
                return
            }
            if let key { rememberPriceKey(key) }
            if priced { stagedPriced += 1 }
            stagedChangedPrices = stagedChangedPrices || changed
            stagedWriteCount += 1
        }

        @discardableResult
        func commitStaged(force: Bool = false) async -> Bool {
            guard storageContinuation?() ?? true,
                  force || !Task.isCancelled else { return false }
            let writeCount = stagedWriteCount
            let commitState = PerformanceSignpost.beginInterval(
                "priceRefresh.commitStaged",
                id: PerformanceSignpost.makeID(),
                "writes=\(writeCount)"
            )
            let saved = store.save()
            var appliedRows = 0
            var skippedRows = 0
            var rowPatchSaveFailed = false
            if saved {
                let patchResult = applyPendingRowPatches()
                appliedRows = patchResult.applied
                skippedRows = patchResult.skipped
                rowPatchSaveFailed = !patchResult.saved
                persistenceFailed = persistenceFailed || rowPatchSaveFailed
                priced += stagedPriced
                changedPrices = changedPrices || stagedChangedPrices
                reconciledDuplicateRecords += stagedDuplicateRepairs
                let deltas = takePriceDeltas(from: store)
                if !deltas.isEmpty { await progress(.prices(deltas)) }
            } else {
                persistenceFailed = true
                pendingRowPatches.removeAll()
                identityIndex?.reload()
            }
            stagedPriced = 0
            stagedChangedPrices = false
            stagedDuplicateRepairs = 0
            stagedWriteCount = 0
            lastCommitAt = .now
            PerformanceSignpost.endInterval(
                "priceRefresh.commitStaged",
                commitState,
                "writes=\(writeCount),saved=\(saved ? 1 : 0),rowPatches=\(appliedRows),rowSkipped=\(skippedRows),rowSaveFailed=\(rowPatchSaveFailed ? 1 : 0)"
            )
            return saved
        }

        func checkpointIsDue() -> Bool {
            stagedWriteCount >= PriceRefreshController.stagedWriteCeiling
                || Date.now.timeIntervalSince(lastCommitAt)
                    >= PriceRefreshController.checkpointBudget
        }

        // Only rows that cannot even form a graded request receive the
        // capability stamp here. A scanned slab with a persisted underlying
        // identity, grader and grade is requestable even when it has not yet
        // acquired the vendor's variant UUID; refreshGraded owns that lookup.
        let unsupported = targets.filter {
            $0.itemKind == .gradedCard
                && $0.marketVariantID == nil
                && !$0.canResolveGradedVariant
        }
        for target in unsupported {
            stage(store.recordUnsupportedProvider(
                game: target.game,
                printingID: target.printingID,
                variantID: target.variantID,
                treatmentIDs: target.magicTreatmentIDsRaw
            ), key: target.id)
        }
        let unsupportedIDs = Set(unsupported.map(\.id))
        let supportedTargets = targets.filter { !unsupportedIDs.contains($0.id) }
        let vendorNative = supportedTargets.filter(\.isVendorNative)
        // An unbound graded row is neither a catalog-card request nor a raw
        // fallback candidate. It is handled by the v2 graded pass below.
        let catalogTargets = supportedTargets.filter {
            $0.itemKind != .gradedCard
        }

        var order: [PriceTarget.Printing] = []
        var byPrinting: [PriceTarget.Printing: [PriceTarget]] = [:]
        for target in catalogTargets where !target.isVendorNative {
            if byPrinting[target.printing] == nil { order.append(target.printing) }
            byPrinting[target.printing, default: []].append(target)
        }

        let previousLatest = latestKnownSourceUpdate(in: store)
        let rowIdentitiesByPriceKey = PriceRefreshController.rowIdentitiesByPriceKey(
            in: modelContext
        )
        let importedRowIdentitiesByProviderID = Dictionary(
            grouping: rowIdentitiesByPriceKey.values.flatMap { $0 }
                .filter { $0.providerID.hasPrefix("csv:") },
            by: \.providerID
        )
        var completed = 0
        var wasCancelled = false
        let refreshID = UUID()
        var fallbackSubjects: [PriceRefreshController.FallbackCandidate] = vendorNative.map {
            PriceRefreshController.FallbackCandidate(target: $0, card: nil)
        }
        var deferredCatalogRepairs: [(repair: PokemonFinishReconciliation.Repair, card: IdentifiedCard)] = []
        var deferredPriceTargets: [String: (target: PriceTarget, card: IdentifiedCard)] = [:]
        var pricedTargetIDs = Set<String>()
        var consecutiveUnreachable = 0
        var providerUnreachable = false
        var lastCatalogProgressAt: Date?
        var lastCatalogProgressPercent: Int?

        func publishCatalogProgress(force: Bool = false) async {
            let now = Date.now
            let percent: Int = {
                guard !order.isEmpty else { return completed == 0 ? 0 : 100 }
                return min(
                    100,
                    max(0, Int((Double(completed) / Double(order.count) * 100).rounded(.down)))
                )
            }()
            let intervalElapsed = lastCatalogProgressAt.map {
                now.timeIntervalSince($0) >= PriceRefreshController.progressPublishInterval
            } ?? true
            guard force || (intervalElapsed && lastCatalogProgressPercent != percent) else {
                return
            }
            lastCatalogProgressAt = now
            lastCatalogProgressPercent = percent
            await progress(.catalog(completed: completed, total: order.count))
        }

        func priceTarget(_ target: PriceTarget, card: IdentifiedCard, at now: Date) {
            guard pricedTargetIDs.insert(target.id).inserted else { return }
            let variant = target.variantID.map(PhysicalVariant.resolving)
            let lookup = CardPricing.price(
                for: card,
                variant: variant,
                magicTreatments: card.magicTreatments(for: variant),
                pokemonPrintRun: target.pokemonPrintRun,
                at: now
            )
            if PriceRefreshController.needsFallback(
                lookup,
                identifiedCatalogCard: true
            ) {
                fallbackSubjects.append(
                    PriceRefreshController.FallbackCandidate(target: target, card: card)
                )
            }
            if case let .price(price) = lookup {
                if let updated = price.sourceUpdatedAt,
                   updated > (latestSourceUpdate ?? .distantPast) {
                    latestSourceUpdate = updated
                } else if price.sourceUpdatedAt == nil {
                    checkedUnstampedProvider = true
                }
            }

            let key = PriceRecord.key(
                game: target.game,
                printingID: target.printingID,
                variantID: target.variantID,
                treatmentIDs: target.magicTreatmentIDsRaw
            )
            let previousAmount = store.record(forKey: key)?.effectiveUnitMarketPriceUSD
            let newAmount: Double?
            switch lookup {
            case let .price(price): newAmount = price.unitMarketPriceUSD
            case .unavailable: newAmount = previousAmount
            }
            let accepted = store.store(
                lookup,
                game: target.game,
                printingID: target.printingID,
                variantID: target.variantID,
                at: now,
                treatmentIDs: target.magicTreatmentIDsRaw
            )
            stage(
                accepted,
                key: key,
                priced: {
                    if case .price = lookup { return true }
                    return false
                }(),
                changed: previousAmount != newAmount
            )
        }

        await publishCatalogProgress(force: true)

        var requestBatches: [[PriceTarget.Printing]] = []
        var magicBatch: [PriceTarget.Printing] = []
        for printing in order {
            if printing.game == .magic, printing.importedIdentity == nil {
                magicBatch.append(printing)
                if magicBatch.count == 75 {
                    requestBatches.append(magicBatch)
                    magicBatch.removeAll(keepingCapacity: true)
                }
            } else {
                if !magicBatch.isEmpty {
                    requestBatches.append(magicBatch)
                    magicBatch.removeAll(keepingCapacity: true)
                }
                requestBatches.append([printing])
            }
        }
        if !magicBatch.isEmpty { requestBatches.append(magicBatch) }

        var cursor = 0
        await withTaskGroup(of: [PriceFetchOutcome].self) { group in
            let initial = min(PriceRefreshController.maxConcurrentRequests, requestBatches.count)
            for _ in 0..<initial {
                let batch = requestBatches[cursor]
                cursor += 1
                let batchID = UUID()
                group.addTask { [tcgdex, scryfall, importedResolver, pokemonFetchOverride] in
                    await PriceRefreshController.fetchBatch(
                        batch,
                        batchID: batchID,
                        tcgdex: tcgdex,
                        scryfall: scryfall,
                        importedResolver: importedResolver,
                        pokemonFetchOverride: pokemonFetchOverride
                    )
                }
            }

            while let outcomes = await group.next() {
                for outcome in outcomes {
                    guard storageContinuation?() ?? true, !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }
                    let printing = outcome.printing
                    let now = Date.now
                    switch outcome.result {
                    case let .card(card):
                        if printing.importedIdentity != nil {
                            for importedRow in importedRowIdentitiesByProviderID[printing.printingID] ?? [] {
                                pendingRowPatches.append(
                                    RefreshRowPatch.catalogMetadata(
                                        from: card,
                                        row: importedRow,
                                        checkedAt: now
                                    )
                                )
                                stage(true, key: importedRow.priceKey)
                            }
                        }
                        if card.game == .magic {
                            checkedUnstampedProvider = true
                        }
                        let targetsForPrinting = byPrinting[printing] ?? []
                        for target in targetsForPrinting {
                            var assessment = PokemonFinishReconciliation.Assessment(
                                repairs: [],
                                changedPendingRows: 0
                            )
                            if card.game == .pokemon,
                               target.game == .pokemon,
                               target.itemKind == .rawCard,
                               target.importedIdentity == nil {
                                let rows = (try? PriceRefreshController.liveRows(
                                    collectionKeys: (rowIdentitiesByPriceKey[target.id] ?? [])
                                        .map(\.collectionKey),
                                    in: modelContext
                                )) ?? []
                                assessment = PokemonFinishReconciliation.assess(
                                    targets: [target],
                                    card: card,
                                    rows: rows,
                                    refreshID: refreshID,
                                    at: now
                                )
                            }
                            if assessment.changedPendingRows > 0 {
                                pendingRowPatches.append(contentsOf: assessment.pendingPatches)
                                for patch in assessment.pendingPatches {
                                    stage(true, key: patch.expectedPriceKey)
                                }
                            }

                            if assessment.repairs.isEmpty {
                                priceTarget(target, card: card, at: now)
                            } else {
                                deferredPriceTargets[target.id] = (target, card)
                                deferredCatalogRepairs.append(contentsOf: assessment.repairs.map {
                                    ($0, card)
                                })
                            }
                        }

                    case .failed:
                        failed += 1
                        for target in byPrinting[printing] ?? [] {
                            stage(store.recordFailure(
                                game: target.game,
                                printingID: target.printingID,
                                variantID: target.variantID,
                                at: now,
                                treatmentIDs: target.magicTreatmentIDsRaw
                            ), key: target.id)
                            fallbackSubjects.append(
                                PriceRefreshController.FallbackCandidate(target: target, card: nil)
                            )
                        }

                    case .unreachable:
                        fallbackSubjects.append(contentsOf: (byPrinting[printing] ?? []).map {
                            PriceRefreshController.FallbackCandidate(target: $0, card: nil)
                        })
                        consecutiveUnreachable += 1
                        if !providerUnreachable,
                           consecutiveUnreachable >= PriceRefreshController.unreachableThreshold {
                            providerUnreachable = true
                            for pending in requestBatches.dropFirst(cursor).flatMap({ $0 }) {
                                fallbackSubjects.append(contentsOf: (byPrinting[pending] ?? []).map {
                                    PriceRefreshController.FallbackCandidate(target: $0, card: nil)
                                })
                            }
                        }

                    case .cancelled:
                        wasCancelled = true
                    }

                    switch outcome.result {
                    case .card, .failed:
                        consecutiveUnreachable = 0
                    case .unreachable, .cancelled:
                        break
                    }
                    completed += 1
                    await publishCatalogProgress()

                    if checkpointIsDue() {
                        guard storageContinuation?() ?? true, !Task.isCancelled else {
                            wasCancelled = true
                            break
                        }
                        _ = await commitStaged()
                    }
                }

                if cursor < requestBatches.count,
                   !providerUnreachable,
                   !wasCancelled,
                   !Task.isCancelled {
                    let batch = requestBatches[cursor]
                    cursor += 1
                    let batchID = UUID()
                    group.addTask { [tcgdex, scryfall, importedResolver, pokemonFetchOverride] in
                        await PriceRefreshController.fetchBatch(
                            batch,
                            batchID: batchID,
                            tcgdex: tcgdex,
                            scryfall: scryfall,
                            importedResolver: importedResolver,
                            pokemonFetchOverride: pokemonFetchOverride
                        )
                    }
                }
            }
        }

        await publishCatalogProgress(force: true)
        // A card's successful response is complete evidence on its own. Keep
        // those staged sightings even if the enclosing refresh was cancelled;
        // a storage-generation change still blocks writes to the stale store.
        _ = await commitStaged(force: true)
        if wasCancelled || Task.isCancelled || !(storageContinuation?() ?? true) {
            refreshOutcome = "cancelled"
            return .cancelled(
                repairedFinishes: repairedFinishes,
                backfilledFinishes: backfilledFinishes
            )
        }

        if !deferredCatalogRepairs.isEmpty {
            await progress(.reconciling(completed: 0, total: deferredCatalogRepairs.count))
        }
        var completedRepairs = 0
        var repairedDestinationCards: [String: IdentifiedCard] = [:]
        for deferred in deferredCatalogRepairs {
            guard storageContinuation?() ?? true, !Task.isCancelled else {
                refreshOutcome = "cancelled"
                return .cancelled(
                    repairedFinishes: repairedFinishes,
                    backfilledFinishes: backfilledFinishes
                )
            }
            if PokemonFinishReconciliation.apply(
                deferred.repair,
                card: deferred.card,
                in: modelContext.container
            ) {
                var destination = deferred.repair.target
                destination.variantID = deferred.repair.resolved.variant?.id
                repairedDestinationCards[destination.id] = deferred.card
                switch deferred.repair.kind {
                case .catalogCorrection:
                    repairedFinishes += 1
                case .quietBackfill:
                    backfilledFinishes += 1
                }
            }
            completedRepairs += 1
            await progress(.reconciling(
                completed: completedRepairs,
                total: deferredCatalogRepairs.count
            ))
        }

        // Corrections commit in sibling contexts. Rebuild from the live rows so
        // pricing picks up destination metadata and cannot carry an outgoing
        // finish's marketplace handle or failure state onto the new price key.
        let reconciliationContext = ModelContext(modelContext.container)
        let currentTargets: [PriceTarget]
        do {
            currentTargets = try PriceRefreshTargets.make(
                context: reconciliationContext,
                usesPriceFallback: request.usesPriceFallback,
                includeImported: true
            )
        } catch {
            persistenceFailed = true
            currentTargets = []
        }
        let currentTargetsByID = Dictionary(
            currentTargets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (sourceID, deferred) in deferredPriceTargets {
            if let liveTarget = currentTargetsByID[sourceID] {
                priceTarget(liveTarget, card: deferred.card, at: .now)
            }
        }
        for (destinationID, card) in repairedDestinationCards {
            if let liveTarget = currentTargetsByID[destinationID] {
                priceTarget(liveTarget, card: card, at: .now)
            }
        }
        _ = await commitStaged()
        if wasCancelled || Task.isCancelled || !(storageContinuation?() ?? true) {
            refreshOutcome = "cancelled"
            return .cancelled(
                repairedFinishes: repairedFinishes,
                backfilledFinishes: backfilledFinishes
            )
        }

        guard storageContinuation?() ?? true else {
            refreshOutcome = "cancelled"
            return .cancelled(
                repairedFinishes: repairedFinishes,
                backfilledFinishes: backfilledFinishes
            )
        }
        let fallbackResult = await runFallback(
            fallbackSubjects,
            usesPriceFallback: request.usesPriceFallback,
            progress: progress,
            store: store
        )
        if fallbackResult.priced > 0 {
            priced += fallbackResult.priced
        }
        changedPrices = changedPrices || fallbackResult.changedPrices
        persistenceFailed = persistenceFailed || fallbackResult.persistenceFailed

        guard storageContinuation?() ?? true, !Task.isCancelled else {
            refreshOutcome = "cancelled"
            return .cancelled(
                repairedFinishes: repairedFinishes,
                backfilledFinishes: backfilledFinishes
            )
        }
        let gradedResult = await refreshGraded(
            targets,
            store: store,
            progress: progress
        )
        if gradedResult.priced > 0 {
            priced += gradedResult.priced
            changedPrices = true
        }
        persistenceFailed = persistenceFailed || gradedResult.persistenceFailed
        gradedLookupMisses += gradedResult.lookupMisses
        gradedTransportFailures += gradedResult.transportFailures

        if Task.isCancelled || !(storageContinuation?() ?? true) {
            refreshOutcome = "cancelled"
            return .cancelled(
                repairedFinishes: repairedFinishes,
                backfilledFinishes: backfilledFinishes
            )
        }
        let latest = latestSourceUpdate ?? previousLatest
        let finalPriceDeltas = takePriceDeltas(from: store)
        refreshOutcome = "completed"
        return .completed(
            PriceRefreshWorkResult(
                checkedAt: .now,
                priced: priced,
                failed: failed,
                latestSourceUpdate: latest,
                checkedUnstampedProvider: checkedUnstampedProvider,
                changedPrices: changedPrices,
                foundNothingNewer: !isNewer(latestSourceUpdate, than: previousLatest),
                providerUnreachable: providerUnreachable,
                persistenceFailed: persistenceFailed,
                gradedLookupMisses: gradedLookupMisses,
                gradedTransportFailures: gradedTransportFailures,
                reconciledDuplicateRecords: reconciledDuplicateRecords,
                repairedFinishes: repairedFinishes,
                backfilledFinishes: backfilledFinishes,
                priceDeltas: finalPriceDeltas
            )
        )
    }

    private func latestKnownSourceUpdate(in store: PriceStore) -> Date? {
        store.allRecords().compactMap(\.sourceUpdatedAt).max()
    }

    private func isNewer(_ candidate: Date?, than previous: Date?) -> Bool {
        guard let candidate else { return false }
        guard let previous else { return true }
        return candidate > previous
    }

    private func makeIdentityState() -> (ProductIdentityStore, ProductIdentityIndex) {
        if let identityIndex {
            return (
                identityStore ?? ProductIdentityStore(context: modelContext),
                identityIndex
            )
        }
        let identities = ProductIdentityStore(context: modelContext)
        let index = ProductIdentityIndex(context: modelContext)
        identityStore = identities
        identityIndex = index
        return (identities, index)
    }

    private func applyPendingRowPatches(
        retryAfterFailure: Bool = true
    ) -> (saved: Bool, applied: Int, skipped: Int) {
        guard !pendingRowPatches.isEmpty else { return (true, 0, 0) }
        let patches = pendingRowPatches
        do {
            let result = try CollectionWriteSerializer.perform(
                container: modelContainer,
                timeout: .wait
            ) { context -> (applied: Int, skipped: Int) in
                var applied = 0
                var skipped = 0
                for patch in patches {
                    let key = patch.collectionKey
                    let descriptor = FetchDescriptor<CollectedCard>(
                        predicate: #Predicate { $0.collectionKey == key }
                    )
                    let rows = try context.fetch(descriptor)
                    guard !rows.isEmpty else {
                        skipped += 1
                        continue
                    }
                    for row in rows {
                        guard row.priceKey == patch.expectedPriceKey,
                              row.variantID == patch.expectedVariantID,
                              row.justTCGVariantID == patch.expectedMarketVariantID else {
                            skipped += 1
                            continue
                        }
                        switch patch.change {
                        case let .catalogMetadata(metadata, checkedAt):
                            row.applyCatalogMetadata(metadata)
                            CollectionCatalogNormalizer.recordCatalogMetadataCheck(
                                on: row,
                                at: checkedAt
                            )
                        case let .sealedArtwork(url, checkedAt):
                            guard row.itemKind == .sealedProduct, row.imageURL == nil else {
                                skipped += 1
                                continue
                            }
                            CollectionCatalogNormalizer.recordSealedArtworkCheck(
                                on: row,
                                at: checkedAt
                            )
                            if let url { row.imageURL = url }
                        case let .vendorBinding(productID, sku):
                            if row.tcgplayerProductID == nil, let productID {
                                row.tcgplayerProductID = productID
                            }
                            if row.tcgplayerSKUID == nil, let sku {
                                row.tcgplayerSKUID = sku
                            }
                        case let .gradedBinding(
                            marketVariantID,
                            marketCardID,
                            apiVersion
                        ):
                            guard row.itemKind == .gradedCard,
                                  row.justTCGVariantID == nil
                                    || row.justTCGVariantID == marketVariantID else {
                                skipped += 1
                                continue
                            }
                            let oldPriceKey = row.priceKey
                            let marketPrintingID = "justtcg:\(apiVersion):\(marketVariantID)"
                            let newPriceKey = PriceRecord.key(
                                game: row.cardGame,
                                printingID: marketPrintingID,
                                variantID: row.variantID,
                                treatmentIDs: row.priceTreatmentIDs
                            )
                            if oldPriceKey != newPriceKey {
                                let events = try context.fetch(
                                    FetchDescriptor<InventoryEvent>(
                                        predicate: #Predicate {
                                            $0.priceStorageKey == oldPriceKey
                                        }
                                    )
                                )
                                for event in events {
                                    event.priceStorageKey = newPriceKey
                                }
                            }
                            row.justTCGVariantID = marketVariantID
                            row.justTCGCardID = marketCardID ?? row.justTCGCardID
                            row.justTCGAPIVersion = apiVersion
                            row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
                        case let .pendingCatalogFinish(expected, replacement):
                            guard PendingCatalogFinishState.read(from: row) == expected else {
                                skipped += 1
                                continue
                            }
                            row.pendingCatalogFinishID = replacement.id
                            row.pendingCatalogFinishFirstSeenAt = replacement.firstSeenAt
                            row.pendingCatalogFinishRefreshID = replacement.refreshID
                        }
                        applied += 1
                    }
                }
                if context.hasChanges { try context.save() }
                return (applied, skipped)
            }
            pendingRowPatches.removeAll()
            skippedRowPatchCount += result.skipped
            // A graded binding may have moved price records and lineage in the
            // patch context. Refresh the actor's value indexes before its next
            // lookup can consult them.
            refreshStore?.index?.reload()
            identityIndex?.reload()
            return (true, result.applied, result.skipped)
        } catch {
            pendingRowPatches = patches
            refreshStore?.index?.reload()
            identityIndex?.reload()
            if retryAfterFailure {
                // The price-side checkpoint is already durable. Retry the
                // guarded ownership patch once in a fresh context so a
                // transient row-store save failure does not strand the row on
                // its pre-promotion price key.
                return applyPendingRowPatches(retryAfterFailure: false)
            }
            return (false, 0, patches.count)
        }
    }

    private func applyActiveBatch(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget]
    ) -> MarketRefreshApplyResult {
        guard storageContinuation?() ?? true else { return .rejected }
        guard let store = refreshStore,
              let identities = identityStore,
              let identityIndex else { return .rejected }
        let applied = PriceRefreshController.applyVendorBatchHitResult(
            card: card,
            variant: variant,
            owners: owners,
            store: store,
            identities: identities,
            artworkRowsByPriceKey: [:],
            identityRowsByPriceKey: [:],
            identityIndex: identityIndex
        )
        if applied.accepted {
            activeFallbackStagedWrites += owners.count
            let artworkURL = JustTCGV1Client.productImageURL(tcgplayerID: card.tcgplayerId)?.absoluteString
            for owner in owners {
                rememberPriceKey(owner.priceKey)
                for row in identityRowIdentitiesByPriceKey[owner.priceKey] ?? [] {
                    pendingRowPatches.append(
                        RefreshRowPatch(
                            collectionKey: row.collectionKey,
                            expectedPriceKey: row.priceKey,
                            expectedVariantID: row.variantID,
                            expectedMarketVariantID: row.marketVariantID,
                            change: .vendorBinding(
                                productID: card.tcgplayerId,
                                sku: variant.tcgplayerSkuId
                            )
                        )
                    )
                }
                if owner.itemKind == .sealedProduct {
                    for row in artworkRowIdentitiesByPriceKey[owner.priceKey] ?? []
                    where row.itemKind == .sealedProduct && row.imageURLIsMissing {
                        pendingRowPatches.append(
                            RefreshRowPatch(
                                collectionKey: row.collectionKey,
                                expectedPriceKey: row.priceKey,
                                expectedVariantID: row.variantID,
                                expectedMarketVariantID: row.marketVariantID,
                                change: .sealedArtwork(url: artworkURL, checkedAt: .now)
                            )
                        )
                    }
                }
            }
        }
        return applied
    }

    private func recordActiveArtworkMiss(for owners: [MarketPriceTarget]) {
        guard storageContinuation?() ?? true else { return }
        for owner in owners where owner.itemKind == .sealedProduct {
            for row in artworkRowIdentitiesByPriceKey[owner.priceKey] ?? []
            where row.itemKind == .sealedProduct && row.imageURLIsMissing {
                pendingRowPatches.append(
                    RefreshRowPatch(
                        collectionKey: row.collectionKey,
                        expectedPriceKey: row.priceKey,
                        expectedVariantID: row.variantID,
                        expectedMarketVariantID: row.marketVariantID,
                        change: .sealedArtwork(url: nil, checkedAt: .now)
                    )
                )
            }
        }
        activeFallbackStagedWrites += owners.count
    }

    @discardableResult
    private func saveActiveContext() -> Bool {
        guard storageContinuation?() ?? true, !Task.isCancelled else { return false }
        guard let identities = identityStore, let store = refreshStore else { return false }
        // Both wrappers point at this actor's one context. Keep the existing
        // identity-then-price checkpoint order; changing it would widen the
        // already-known non-atomic window between synced and local stores.
        guard identities.save(index: identityIndex) else {
            refreshStore?.index?.reload()
            identityIndex?.reload()
            pendingRowPatches.removeAll()
            return false
        }
        guard store.save() else {
            identityIndex?.reload()
            pendingRowPatches.removeAll()
            return false
        }
        return applyPendingRowPatches().saved
    }

    /// The coordinator calls its checkpoint callback after a successful vendor
    /// batch. That callback is a durability opportunity, not a requirement to
    /// save every batch: keep the same wall-clock budget as the other lanes.
    private func checkpointActiveContextIfDue(force: Bool = false) -> Bool {
        let checkpointState = PerformanceSignpost.beginInterval(
            "priceRefresh.checkpointActiveContext",
            id: PerformanceSignpost.makeID(),
            "staged=\(activeFallbackStagedWrites)"
        )
        var checkpointOutcome = "not-due"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.checkpointActiveContext",
                checkpointState,
                "staged=\(activeFallbackStagedWrites),outcome=\(checkpointOutcome)"
            )
        }
        guard storageContinuation?() ?? true, !Task.isCancelled else {
            checkpointOutcome = "cancelled"
            return false
        }
        let due = force
            || activeFallbackStagedWrites >= PriceRefreshController.stagedWriteCeiling
            || Date.now.timeIntervalSince(activeFallbackLastCommitAt)
                >= PriceRefreshController.checkpointBudget
        guard due else { return true }
        let saved = saveActiveContext()
        if saved {
            activeFallbackStagedWrites = 0
            activeFallbackLastCommitAt = .now
            checkpointOutcome = "saved"
        } else {
            checkpointOutcome = "failed"
        }
        return saved
    }

    private func runFallback(
        _ candidates: [PriceRefreshController.FallbackCandidate],
        usesPriceFallback: Bool,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void,
        store: PriceStore
    ) async -> (priced: Int, persistenceFailed: Bool, changedPrices: Bool) {
        let fallbackState = PerformanceSignpost.beginInterval(
            "priceRefresh.runFallback",
            id: PerformanceSignpost.makeID(),
            "candidates=\(candidates.count)"
        )
        var fallbackOutcome = "skipped"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.runFallback",
                fallbackState,
                "candidates=\(candidates.count),outcome=\(fallbackOutcome)"
            )
        }
        guard storageContinuation?() ?? true, !Task.isCancelled else {
            fallbackOutcome = "cancelled"
            return (0, false, false)
        }
        guard !candidates.isEmpty else {
            await progress(.fallbackIdle)
            return (0, false, false)
        }

        let deduplicatedCandidates = PriceRefreshController.collapsingDuplicates(candidates)
        let eligibleCandidates = deduplicatedCandidates.filter {
            PriceRefreshController.permitsVendorWork(
                for: $0.target,
                usesFallback: usesPriceFallback
            )
        }
        guard !eligibleCandidates.isEmpty else {
            await progress(.fallbackDisabled(pending: deduplicatedCandidates.count))
            return (0, false, false)
        }
        guard PriceVendorCredentials.hasKey else {
            await progress(.fallbackUnconfigured(pending: eligibleCandidates.count))
            return (0, false, false)
        }
        fallbackOutcome = "running"

        let (identities, identityIndex) = makeIdentityState()
        let rowIdentities = PriceRefreshController.rowIdentitiesByPriceKey(in: modelContext)
        artworkRowIdentitiesByPriceKey = rowIdentities.mapValues {
            $0.filter(\.imageURLIsMissing)
        }
        identityRowIdentitiesByPriceKey = rowIdentities
        activeFallbackLastCommitAt = .now
        activeFallbackStagedWrites = 0
        defer {
            artworkRowIdentitiesByPriceKey = [:]
            identityRowIdentitiesByPriceKey = [:]
            activeFallbackLastCommitAt = .distantPast
            activeFallbackStagedWrites = 0
        }

        var priced = 0
        var changedPrices = false
        var stagedPriced = 0
        var persistenceFailed = false
        var completed = 0
        var stoppedByAllowance = false
        var budget = await fallbackService.budgetSnapshot()
        var lastFallbackProgressAt: Date?
        var lastFallbackProgressPercent: Int?

        func publishFallbackProgress(force: Bool = false) async {
            let now = Date.now
            let percent: Int = {
                guard !eligibleCandidates.isEmpty else { return completed == 0 ? 0 : 100 }
                return min(
                    100,
                    max(
                        0,
                        Int((Double(completed) / Double(eligibleCandidates.count) * 100).rounded(.down))
                    )
                )
            }()
            let intervalElapsed = lastFallbackProgressAt.map {
                now.timeIntervalSince($0) >= PriceRefreshController.progressPublishInterval
            } ?? true
            guard force || (intervalElapsed && lastFallbackProgressPercent != percent) else {
                return
            }
            lastFallbackProgressAt = now
            lastFallbackProgressPercent = percent
            await progress(.fallback(
                completed: completed,
                total: eligibleCandidates.count,
                remainingToday: budget.remainingToday
            ))
        }

        await publishFallbackProgress(force: true)

        @discardableResult
        func checkpoint(force: Bool = false) async -> Bool {
            let checkpointState = PerformanceSignpost.beginInterval(
                "priceRefresh.fallbackCheckpoint",
                id: PerformanceSignpost.makeID(),
                "force=\(force ? 1 : 0),staged=\(activeFallbackStagedWrites)"
            )
            var checkpointOutcome = "not-due"
            defer {
                PerformanceSignpost.endInterval(
                    "priceRefresh.fallbackCheckpoint",
                    checkpointState,
                    "force=\(force ? 1 : 0),outcome=\(checkpointOutcome)"
                )
            }
            guard storageContinuation?() ?? true, !Task.isCancelled else {
                checkpointOutcome = "cancelled"
                return false
            }
            let due = force
                || activeFallbackStagedWrites >= PriceRefreshController.stagedWriteCeiling
                || Date.now.timeIntervalSince(activeFallbackLastCommitAt)
                    >= PriceRefreshController.checkpointBudget
            guard due else { return true }
            let saved = saveActiveContext()
            if saved {
                priced += stagedPriced
                activeFallbackStagedWrites = 0
                activeFallbackLastCommitAt = .now
                let deltas = takePriceDeltas(from: store)
                if !deltas.isEmpty { await progress(.prices(deltas)) }
                checkpointOutcome = "saved"
            } else {
                persistenceFailed = true
                checkpointOutcome = "failed"
            }
            stagedPriced = 0
            return saved
        }

        var batchable: [CardGame: [MarketPriceTarget]] = [:]
        var needsIdentity: [PriceRefreshController.FallbackCandidate] = []
        for candidate in eligibleCandidates {
            let key = ProductIdentity.key(
                game: candidate.target.game,
                printingID: candidate.target.printingID,
                variantID: candidate.target.variantID,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw
            )
            guard identities.fallbackCheckIsDue(
                forKey: key,
                minimumInterval: PriceRefreshController.fallbackRefreshInterval,
                using: identityIndex
            ) else {
                completed += 1
                await publishFallbackProgress()
                continue
            }
            let cachedVariant = candidate.target.marketVariantID
                ?? identities.cachedVariantID(forKey: key, using: identityIndex)
            let cachedCard = identities.cachedCardID(forKey: key, using: identityIndex)
            if cachedVariant == nil, cachedCard == nil,
               !identities.needsResolution(forKey: key, using: identityIndex) {
                completed += 1
                await publishFallbackProgress()
                continue
            }

            let external = candidate.externalLookups
            guard cachedVariant != nil || !external.isEmpty else {
                needsIdentity.append(candidate)
                continue
            }
            guard candidate.target.itemKind != .gradedCard else {
                completed += 1
                await publishFallbackProgress()
                continue
            }

            batchable[candidate.target.game, default: []].append(
                MarketPriceTarget(
                    priceKey: key,
                    game: candidate.target.game,
                    printingID: candidate.target.printingID,
                    variantID: candidate.target.variantID,
                    itemKind: candidate.target.itemKind,
                    marketVariantID: cachedVariant,
                    lookupCandidates: external,
                    currentAmount: nil,
                    lastCheckedAt: candidate.target.lastCheckedAt,
                    justTCGFetchedAt: candidate.target.justTCGFetchedAt,
                    magicTreatmentIDsRaw: candidate.target.magicTreatmentIDsRaw,
                    requiresFullResponse: !candidate.target.hasPrice
                        || candidate.target.needsArtwork
                )
            )
        }

        let coordinator = JustTCGRefreshCoordinator(
            client: JustTCGV1Client(transport: sharedTransport)
        )
        for (game, targets) in batchable {
            if Task.isCancelled || !(storageContinuation?() ?? true) { break }
            let useDelta = JustTCGSyncLedger()
                .checkpoint(game: game, apiVersion: JustTCGV1Client.apiVersion)
                .supportsDeltaSync
            let report = await coordinator.refresh(
                targets,
                game: game,
                lane: .background,
                useDelta: useDelta,
                applyDetailed: { [self] card, variant, owners in
                    await self.applyActiveBatch(card: card, variant: variant, owners: owners)
                },
                unmatched: { [self] owners in
                    await self.recordActiveArtworkMiss(for: owners)
                },
                checked: { [self] owners, checkedAt in
                    await self.recordActiveFallbackChecks(owners, at: checkedAt)
                },
                checkpoint: { [self] in
                    await self.checkpointActiveContextIfDue()
                },
                finalCheckpoint: { [self] in
                    await self.checkpointActiveContextIfDue(force: true)
                }
            )
            PriceRefreshController.accumulateMarketRefreshReport(
                report,
                priced: &priced,
                changedPrices: &changedPrices
            )
            persistenceFailed = persistenceFailed || report.persistenceFailed
            completed += report.variantsRequested
            await publishFallbackProgress()

            switch report.stoppedReason {
            case let .dailyBudget(resetAt), let .monthlyBudget(resetAt):
                stoppedByAllowance = true
                await progress(.fallbackBudgetReached(
                    pending: max(eligibleCandidates.count - completed, 0),
                    resetAt: resetAt
                ))
            case let .rateLimited(retryAt):
                stoppedByAllowance = true
                await progress(.fallbackRateLimited(
                    pending: max(eligibleCandidates.count - completed, 0),
                    retryAt: retryAt
                ))
            case .cancelled, .transportFailure, .none:
                break
            }
            if stoppedByAllowance { break }
        }

        for candidate in (stoppedByAllowance ? [] : needsIdentity) {
            if Task.isCancelled || !(storageContinuation?() ?? true) { break }
            let key = ProductIdentity.key(
                game: candidate.target.game,
                printingID: candidate.target.printingID,
                variantID: candidate.target.variantID,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw
            )
            let cached = identities.cachedCardID(forKey: key, using: identityIndex)
            if cached == nil, !identities.needsResolution(forKey: key, using: identityIndex) {
                completed += 1
                await publishFallbackProgress()
                continue
            }
            guard let subject = candidate.subject(vendorCardID: cached) else {
                completed += 1
                await publishFallbackProgress()
                continue
            }
            let outcome = await fallbackService.quote(
                for: subject,
                variant: candidate.target.variantID.map(PhysicalVariant.resolving),
                lane: .background
            )
            let identityStored = identities.record(
                outcome,
                forKey: key,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw,
                using: identityIndex
            )
            guard identityStored else {
                persistenceFailed = true
                completed += 1
                await publishFallbackProgress()
                continue
            }

            switch outcome {
            case let .price(price, _, _):
                if store.store(
                    .price(price),
                    game: candidate.target.game,
                    printingID: candidate.target.printingID,
                    variantID: candidate.target.variantID,
                    treatmentIDs: candidate.target.magicTreatmentIDsRaw
                ) {
                    stagedPriced += 1
                    changedPrices = true
                    activeFallbackStagedWrites += 1
                    rememberPriceKey(candidate.target.id)
                } else {
                    persistenceFailed = true
                }
            case let .budgetReached(resetAt):
                stoppedByAllowance = true
                await progress(.fallbackBudgetReached(
                    pending: max(eligibleCandidates.count - completed, 0),
                    resetAt: resetAt
                ))
            case let .rateLimited(retryAt):
                stoppedByAllowance = true
                await progress(.fallbackRateLimited(
                    pending: max(eligibleCandidates.count - completed, 0),
                    retryAt: retryAt
                ))
            case .noListingForVariant, .noProductMatch, .unsupportedFinish,
                 .unsupportedTreatment, .requestFailed:
                break
            }
            completed += 1
            if stoppedByAllowance { break }

            budget = await fallbackService.budgetSnapshot()
            _ = await checkpoint()
            await publishFallbackProgress()
        }

        _ = await checkpoint(force: true)
        await publishFallbackProgress(force: true)
        if !stoppedByAllowance, !Task.isCancelled {
            budget = await fallbackService.budgetSnapshot()
            await progress(.fallbackFinished(
                checked: completed,
                priced: priced,
                remainingToday: budget.remainingToday
            ))
        }
        fallbackOutcome = stoppedByAllowance ? "stopped" : (Task.isCancelled ? "cancelled" : "completed")
        return (priced, persistenceFailed, changedPrices)
    }

    private func recordActiveFallbackChecks(
        _ targets: [MarketPriceTarget],
        at date: Date
    ) -> Bool {
        guard storageContinuation?() ?? true else { return false }
        let (identities, index) = makeIdentityState()
        var allRecorded = true
        for target in targets {
            let recorded = identities.recordFallbackCheck(
                forKey: target.priceKey,
                treatmentIDs: target.magicTreatmentIDsRaw,
                at: date,
                using: index
            )
            allRecorded = allRecorded && recorded
        }
        return allRecorded
    }

    private func refreshGraded(
        _ targets: [PriceTarget],
        store: PriceStore,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void
    ) async -> (
        priced: Int,
        persistenceFailed: Bool,
        lookupMisses: Int,
        transportFailures: Int
    ) {
        let gradedState = PerformanceSignpost.beginInterval(
            "priceRefresh.refreshGraded",
            id: PerformanceSignpost.makeID(),
            "targets=\(targets.count)"
        )
        var gradedOutcome = "skipped"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.refreshGraded",
                gradedState,
                "targets=\(targets.count),outcome=\(gradedOutcome)"
            )
        }
        let slabs = targets.filter {
            guard $0.itemKind == .gradedCard else { return false }
            if $0.marketVariantID != nil { return true }
            return $0.canResolveGradedVariant
        }
        guard !slabs.isEmpty, PriceVendorCredentials.hasKey else {
            return (0, false, 0, 0)
        }
        gradedOutcome = "running"

        var byCard: [String: [PriceTarget]] = [:]
        for slab in slabs {
            guard let identity = slab.gradedIdentity else { continue }
            byCard[identity.groupingKey(game: slab.game), default: []].append(slab)
        }

        let client = JustTCGV2GradedClient(transport: sharedTransport)
        var priced = 0
        var persistenceFailed = false
        var lookupMisses = 0
        var transportFailures = 0
        var stagedPriced = 0
        var stagedWriteCount = 0
        var lastCommitAt = Date.now

        // Collection state is represented by keys and identity values only.
        // A vendor response can arrive after any one of these rows was removed
        // or rekeyed, so the checkpoint will re-fetch and validate it.
        let gradedRowsByPriceKey = PriceRefreshController.rowIdentitiesByPriceKey(
            in: modelContext
        ).mapValues { $0.filter { $0.itemKind == .gradedCard } }
        let gradedRowsByMarketVariant = Dictionary(
            grouping: gradedRowsByPriceKey.values.flatMap { $0 }
                .filter { $0.marketVariantID != nil },
            by: { $0.marketVariantID! }
        )

        func selectGradedVariant(
            from variants: [GradedVariant],
            target: PriceTarget
        ) -> GradedVariant? {
            guard let company = target.gradingCompany else { return nil }
            let value = JustTCGV2GradedClient.normalizedVendorGrade(target.grade)
            let label = target.gradeLabel ?? (value == nil ? target.grade : nil)
            guard value != nil || label != nil || target.gradingQualifier != nil else {
                return nil
            }
            return ScannedGradedResolver.matchingVariant(
                in: variants,
                for: GradedSlabEvidence(
                    company: company,
                    grade: CardGrade(
                        value: value,
                        label: label,
                        qualifier: target.gradingQualifier
                    ),
                    certificationNumber: nil,
                    labelCardText: []
                )
            )
        }

        func rowIdentity(for target: PriceTarget) -> RefreshRowIdentity? {
            if let handle = target.marketVariantID,
               let existing = gradedRowsByMarketVariant[handle]?.first {
                return existing
            }
            return gradedRowsByPriceKey[target.id]?.first
        }

        func checkpoint(force: Bool = false) async {
            let checkpointState = PerformanceSignpost.beginInterval(
                "priceRefresh.gradedCheckpoint",
                id: PerformanceSignpost.makeID(),
                "force=\(force ? 1 : 0),writes=\(stagedWriteCount)"
            )
            var checkpointOutcome = "not-due"
            defer {
                PerformanceSignpost.endInterval(
                    "priceRefresh.gradedCheckpoint",
                    checkpointState,
                    "force=\(force ? 1 : 0),outcome=\(checkpointOutcome)"
                )
            }
            guard storageContinuation?() ?? true, !Task.isCancelled else {
                checkpointOutcome = "cancelled"
                return
            }
            let due = force
                || stagedWriteCount >= PriceRefreshController.stagedWriteCeiling
                || Date.now.timeIntervalSince(lastCommitAt)
                    >= PriceRefreshController.checkpointBudget
            guard due, stagedWriteCount > 0 else { return }
            if (storageContinuation?() ?? true), !Task.isCancelled, store.save() {
                let patchResult = applyPendingRowPatches()
                persistenceFailed = persistenceFailed || !patchResult.saved
                priced += stagedPriced
                stagedPriced = 0
                stagedWriteCount = 0
                lastCommitAt = .now
                let deltas = takePriceDeltas(from: store)
                if !deltas.isEmpty { await progress(.prices(deltas)) }
                checkpointOutcome = "saved"
            } else {
                persistenceFailed = true
                pendingRowPatches.removeAll()
                identityIndex?.reload()
                checkpointOutcome = "failed"
            }
        }

        func stampCoverage(
            _ target: PriceTarget,
            status: GradedMarketCoverageStatus,
            variants: [GradedVariant] = []
        ) {
            let coverage = GradedMarketCoverage(
                status: status,
                variants: variants,
                targetCompany: target.gradingCompany,
                targetGrade: CardGrade(
                    value: JustTCGV2GradedClient.normalizedVendorGrade(target.grade),
                    label: target.gradeLabel,
                    qualifier: target.gradingQualifier
                )
            )
            let accepted = store.recordGradedMarketCoverage(
                coverage,
                game: target.game,
                printingID: target.printingID,
                variantID: target.variantID,
                treatmentIDs: target.magicTreatmentIDsRaw
            )
            if accepted {
                stagedWriteCount += 1
                rememberPriceKey(target.id)
            } else {
                persistenceFailed = true
            }
        }

        groupLoop: for (_, group) in byCard.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled || !(storageContinuation?() ?? true) { break }
            guard let identity = group.first?.gradedIdentity,
                  let game = group.first?.game else { continue }
            let variants: [GradedVariant]
            do {
                let lookup = try await client.lookup(
                    identity: identity,
                    game: game,
                    lane: .background
                )
                switch lookup {
                case let .matched(values):
                    variants = values
                case .cardFoundWithoutGradedVariants:
                    lookupMisses += group.count
                    for target in group where target.marketVariantID == nil {
                        stampCoverage(target, status: .noGradedListings)
                    }
                    await checkpoint()
                    continue
                case .noProductMatch:
                    lookupMisses += group.count
                    for target in group where target.marketVariantID == nil {
                        stampCoverage(target, status: .cardNotTracked)
                    }
                    await checkpoint()
                    continue
                }
            } catch {
                // A single graded product lookup is independent of the other
                // groups. Do not abandon every later slab because one request
                // failed; leave this group untouched so its prior price and
                // retry state remain honest, then continue the bounded pass.
                if Task.isCancelled { break }
                transportFailures += group.count
                continue
            }

            let byVariantID = Dictionary(
                variants.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for target in group {
                guard storageContinuation?() ?? true, !Task.isCancelled else { break }
                let variant: GradedVariant?
                if let handle = target.marketVariantID {
                    variant = byVariantID[handle]
                } else {
                    variant = selectGradedVariant(from: variants, target: target)
                }
                guard let variant else {
                    lookupMisses += 1
                    if target.marketVariantID == nil {
                        stampCoverage(
                            target,
                            status: .gradeNotListed,
                            variants: variants
                        )
                    }
                    continue
                }

                let owner = rowIdentity(for: target)
                if owner != nil, target.marketVariantID == nil {
                    // Move price-side lineage in the refresh actor's own
                    // context before staging the vendor quote. The collection
                    // row remains a guarded patch applied after this save.
                    let apiVersion = JustTCGV2GradedClient.apiVersion
                    let printingID = "justtcg:\(apiVersion):\(variant.id)"
                    do {
                        try PriceIdentityLineageMigration.migratePriceSide(
                            from: target.id,
                            to: PriceRecord.key(
                                game: target.game,
                                printingID: printingID,
                                variantID: target.variantID,
                                treatmentIDs: target.magicTreatmentIDsRaw
                            ),
                            game: target.game,
                            printingID: printingID,
                            variantID: target.variantID,
                            treatmentIDs: target.magicTreatmentIDsRaw,
                            in: modelContext,
                            index: store.index
                        )
                    } catch {
                        modelContext.rollback()
                        store.index?.reload()
                        identityIndex?.reload()
                        pendingRowPatches.removeAll()
                        stagedWriteCount = 0
                        stagedPriced = 0
                        persistenceFailed = true
                        break groupLoop
                    }
                }
                let binding = GradedVariantBinding.storeUnboundVariantQuote(
                    variant,
                    game: target.game,
                    variantID: target.variantID,
                    treatmentIDs: target.magicTreatmentIDsRaw,
                    store: store,
                    at: .now
                )
                if let owner {
                    pendingRowPatches.append(
                        RefreshRowPatch(
                            collectionKey: owner.collectionKey,
                            expectedPriceKey: owner.priceKey,
                            expectedVariantID: owner.variantID,
                            expectedMarketVariantID: owner.marketVariantID,
                            change: .gradedBinding(
                                marketVariantID: variant.id,
                                marketCardID: variant.cardID,
                                apiVersion: JustTCGV2GradedClient.apiVersion
                            )
                        )
                    )
                }
                if binding.wasAccepted {
                    if variant.marketPriceUSD != nil { stagedPriced += 1 }
                    stagedWriteCount += 1
                    rememberPriceKey(binding.priceKey)
                }
                else { persistenceFailed = true }
            }
            await checkpoint()
        }
        await checkpoint(force: true)
        gradedOutcome = Task.isCancelled ? "cancelled" : "completed"
        return (priced, persistenceFailed, lookupMisses, transportFailures)
    }
}

/// One priced thing: a printing plus the physical variant the user owns.
struct PriceTarget: Hashable, Identifiable, Sendable {
    let game: CardGame
    let printingID: String
    let catalogPrintingID: String?
    let setCode: String
    var variantID: String?
    var pokemonPrintRun: PokemonPrintRun? = nil
    let importedIdentity: ImportedPriceIdentity?
    /// Persisted card identity used only when the catalog provider is down.
    /// Kept separate from `importedIdentity` so normal catalog-backed rows still
    /// use their provider id during the primary pass.
    var fallbackIdentity: ImportedPriceIdentity? = nil
    let catalogMetadataCheckedAt: Date?
    let lastFailureAt: Date?
    var lastFailureReasonRaw: String? = nil
    let hasPrice: Bool
    /// When this app last asked about it, successfully or not.
    let lastCheckedAt: Date?
    /// When a live JustTCG refresh last supplied a price for this row.
    var justTCGFetchedAt: Date? = nil
    /// Raw card, graded slab or sealed product.
    var itemKind: CollectionItemKind = .rawCard
    /// The vendor's variant handle already stored on the row, from the sealed or
    /// graded catalogue it was added out of.
    var marketVariantID: String? = nil
    /// The vendor's card handle already stored on the row. This is useful when a
    /// corrected raw-card finish must be resolved again but the card itself is
    /// already known.
    var justTCGCardID: String? = nil
    /// A provider-published TCGplayer product id is a safe card-level lookup
    /// when the catalog provider is unavailable. It avoids a name/set search;
    /// the requested finish is still selected and validated from the response.
    var tcgplayerProductID: String? = nil
    /// This row has no picture and the vendor's response carries one.
    ///
    /// Artwork rides along with the price, but a row can need one without
    /// needing the other: a sealed product priced yesterday is not stale, so it
    /// never entered a refresh, so the backfill never saw it and the placeholder
    /// box stayed forever. Missing artwork is its own reason to ask.
    var needsArtwork: Bool = false
    /// Enough of the underlying card to find it again in the graded catalogue.
    var gradedIdentity: GradedCardIdentity? = nil
    /// The slab's grader and grade, so a graded request asks only about what is
    /// owned rather than every permutation the vendor publishes.
    var gradingCompany: GradingCompany? = nil
    var grade: String? = nil
    /// The vendor's grade label and qualifier are part of identity. A BGS 10,
    /// BGS 10 Black Label and BGS 10 OC are not interchangeable holdings.
    var gradeLabel: String? = nil
    var gradingQualifier: String? = nil
    /// Treatment ids are part of the price identity. A direct provider product
    /// handle belongs to the exact printing, so a response may safely write a
    /// treated record under its own key; only handle-less searches are refused.
    var magicTreatmentIDsRaw: [String] = []

    /// Whether this row exists only in the market vendor's catalogue.
    ///
    /// A booster box has no TCGdex or Scryfall identity by construction, so
    /// asking those providers about one spends a request to learn nothing and
    /// then stamps a price failure that reads as though something went wrong.
    /// These go straight to the vendor, keyed by the handle the row carries.
    ///
    /// Sealed products have no external catalog identity. Graded slabs are
    /// vendor-native only after their stored variant handle is available;
    /// requestable handle-less slabs are handled by the separate v2 graded
    /// lookup, while incomplete rows are stamped unsupported before the catalog
    /// pass. Raw cards are intentionally not vendor-native: a catalog response
    /// may still provide a free price or the identity needed for a later
    /// fallback.
    var isVendorNative: Bool {
        itemKind == .sealedProduct
            || (itemKind == .gradedCard && marketVariantID != nil)
    }

    /// An unbound graded row can be asked about by the v2 catalogue when its
    /// underlying card, grader and numeric grade are all persisted. The vendor
    /// variant UUID is deliberately not required here: acquiring that UUID is
    /// the job of the background graded refresh.
    var canResolveGradedVariant: Bool {
        itemKind == .gradedCard
            && gradedIdentity != nil
            && gradingCompany != nil
            && grade != nil
    }

    var id: String {
        PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: magicTreatmentIDsRaw
        )
    }

    var isTreatmentQualified: Bool {
        game == .magic && !magicTreatmentIDsRaw.isEmpty
    }

    /// One catalog response answers every variant of the same printing, so a
    /// collection holding a normal and a reverse copy costs one request.
    var printing: Printing {
        Printing(
            game: game,
            printingID: catalogPrintingID ?? printingID,
            setCode: setCode,
            importedIdentity: importedIdentity
        )
    }

    struct Printing: Hashable, Sendable {
        let game: CardGame
        let printingID: String
        let setCode: String
        let importedIdentity: ImportedPriceIdentity?
    }
}

struct ImportedPriceIdentity: Hashable, Sendable {
    let name: String
    let setName: String
    let cardNumber: String
}

extension PokemonFinishReconciliation {
    enum RepairKind: Equatable, Sendable {
        case catalogCorrection
        case quietBackfill
    }

    struct Repair: Sendable {
        let collectionKey: String
        let storedVariantID: String?
        let storedResolutionRaw: String?
        let target: PriceTarget
        let resolved: ResolvedVariant
        let kind: RepairKind
        let requiresConfirmation: Bool
        let pendingFinishID: String?
        let pendingFirstSeenAt: Date?
        let pendingRefreshID: UUID?
    }

    struct Assessment {
        let repairs: [Repair]
        let changedPendingRows: Int
        let pendingPatches: [RefreshRowPatch]

        init(
            repairs: [Repair],
            changedPendingRows: Int,
            pendingPatches: [RefreshRowPatch] = []
        ) {
            self.repairs = repairs
            self.changedPendingRows = changedPendingRows
            self.pendingPatches = pendingPatches
        }
    }

    /// Identifies only raw Pokémon rows represented by this exact price target
    /// and printing. Callers pass the already-materialized rows for the target's
    /// price key, so catalog refresh does not refetch collection rows per card.
    static func candidates(
        targets: [PriceTarget],
        card: IdentifiedCard,
        rows: [CollectedCard]
    ) -> [Repair] {
        guard card.game == .pokemon else { return [] }

        var repairs: [Repair] = []
        for target in targets {
            guard target.game == .pokemon,
                  target.itemKind == .rawCard,
                  target.importedIdentity == nil,
                  target.printing.printingID == card.providerID else {
                continue
            }
            for row in rows {
                guard row.priceKey == target.id,
                      row.providerID == card.providerID,
                      row.cardGame == .pokemon,
                      row.itemKind == .rawCard,
                      row.identityResolution != .imported,
                      row.variantID == target.variantID,
                      let resolved = repair(
                        storedVariantID: row.variantID,
                        storedResolution: row.variantResolution,
                        itemKind: row.itemKind,
                        printRun: row.pokemonPrintRun,
                        card: card
                      ) else {
                    continue
                }
                repairs.append(
                    Repair(
                        collectionKey: row.collectionKey,
                        storedVariantID: row.variantID,
                        storedResolutionRaw: row.variantResolutionRaw,
                        target: target,
                        resolved: resolved,
                        kind: .catalogCorrection,
                        requiresConfirmation: false,
                        pendingFinishID: row.pendingCatalogFinishID,
                        pendingFirstSeenAt: row.pendingCatalogFinishFirstSeenAt,
                        pendingRefreshID: row.pendingCatalogFinishRefreshID
                    )
                )
            }
        }
        return repairs
    }

    /// Applies the evidence policy to the live row snapshot. A missing finish
    /// can be backfilled immediately; a change to an existing automatic finish
    /// needs a second fresh result from a different refresh at least a day later.
    /// Pending evidence is returned as a guarded value patch. The caller saves
    /// it with the normal price-refresh checkpoint in a fresh serialized context.
    static func assess(
        targets: [PriceTarget],
        card: IdentifiedCard,
        rows: [CollectedCard],
        refreshID: UUID,
        at now: Date,
        confirmationInterval: TimeInterval = 24 * 60 * 60
    ) -> Assessment {
        guard card.game == .pokemon else {
            return Assessment(repairs: [], changedPendingRows: 0)
        }

        var repairs: [Repair] = []
        var pendingPatches: [RefreshRowPatch] = []

        func stagePendingFinish(
            for row: CollectedCard,
            replacement: PendingCatalogFinishState
        ) {
            let expected = PendingCatalogFinishState.read(from: row)
            guard expected != replacement else { return }
            pendingPatches.append(
                RefreshRowPatch(
                    collectionKey: row.collectionKey,
                    expectedPriceKey: row.priceKey,
                    expectedVariantID: row.variantID,
                    expectedMarketVariantID: row.justTCGVariantID,
                    change: .pendingCatalogFinish(
                        expected: expected,
                        replacement: replacement
                    )
                )
            )
        }

        for target in targets where target.game == .pokemon
            && target.itemKind == .rawCard
            && target.importedIdentity == nil
            && target.printing.printingID == card.providerID {
            for row in rows where row.priceKey == target.id
                && row.providerID == card.providerID
                && row.cardGame == .pokemon
                && row.itemKind == .rawCard
                && row.identityResolution != .imported
                && row.variantID == target.variantID {
                let storedResolution = row.variantResolution
                guard row.pokemonPrintRun == nil || row.pokemonPrintRun == .unlimited else {
                    stagePendingFinish(
                        for: row,
                        replacement: PendingCatalogFinishState(
                            id: nil,
                            firstSeenAt: nil,
                            refreshID: nil
                        )
                    )
                    continue
                }
                let canBackfill = row.variantID == nil
                    && (storedResolution == nil || storedResolution?.isAutomatic == true)
                let canCorrect = row.variantID != nil && storedResolution?.isAutomatic == true
                guard canBackfill || canCorrect else {
                    stagePendingFinish(
                        for: row,
                        replacement: PendingCatalogFinishState(
                            id: nil,
                            firstSeenAt: nil,
                            refreshID: nil
                        )
                    )
                    continue
                }

                let evidence = row.pokemonPrintRun == nil
                    ? card.variantEvidence
                    : card.variantEvidence.excludingFirstEditionPseudoFinish()
                let outcome = VariantResolver.resolve(evidence)
                guard case let .resolved(resolved) = outcome,
                      let variant = resolved.variant else {
                    stagePendingFinish(
                        for: row,
                        replacement: PendingCatalogFinishState(
                            id: nil,
                            firstSeenAt: nil,
                            refreshID: nil
                        )
                    )
                    continue
                }
                if variant.id == row.variantID {
                    stagePendingFinish(
                        for: row,
                        replacement: PendingCatalogFinishState(
                            id: nil,
                            firstSeenAt: nil,
                            refreshID: nil
                        )
                    )
                    continue
                }

                if canBackfill {
                    repairs.append(
                        Repair(
                            collectionKey: row.collectionKey,
                            storedVariantID: row.variantID,
                            storedResolutionRaw: row.variantResolutionRaw,
                            target: target,
                            resolved: resolved,
                            kind: .quietBackfill,
                            requiresConfirmation: false,
                            pendingFinishID: row.pendingCatalogFinishID,
                            pendingFirstSeenAt: row.pendingCatalogFinishFirstSeenAt,
                            pendingRefreshID: row.pendingCatalogFinishRefreshID
                        )
                    )
                    continue
                }

                let pendingMatches = row.pendingCatalogFinishID == variant.id
                guard pendingMatches,
                      let firstSeenAt = row.pendingCatalogFinishFirstSeenAt,
                      let firstRefreshID = row.pendingCatalogFinishRefreshID,
                      firstRefreshID != refreshID,
                      now.timeIntervalSince(firstSeenAt) >= confirmationInterval else {
                    if !pendingMatches
                        || row.pendingCatalogFinishFirstSeenAt == nil
                        || row.pendingCatalogFinishRefreshID == nil {
                        stagePendingFinish(
                            for: row,
                            replacement: PendingCatalogFinishState(
                                id: variant.id,
                                firstSeenAt: now,
                                refreshID: refreshID
                            )
                        )
                    }
                    continue
                }

                repairs.append(
                    Repair(
                        collectionKey: row.collectionKey,
                        storedVariantID: row.variantID,
                        storedResolutionRaw: row.variantResolutionRaw,
                        target: target,
                        resolved: resolved,
                        kind: .catalogCorrection,
                        requiresConfirmation: true,
                        pendingFinishID: row.pendingCatalogFinishID,
                        pendingFirstSeenAt: row.pendingCatalogFinishFirstSeenAt,
                        pendingRefreshID: row.pendingCatalogFinishRefreshID
                    )
                )
            }
        }
        return Assessment(
            repairs: repairs,
            changedPendingRows: pendingPatches.count,
            pendingPatches: pendingPatches
        )
    }

    /// Applies all of a row's activity-backed changes in one sibling-context
    /// transaction. A row is untouched unless its outstanding acquisition
    /// activities account for its complete current quantity.
    static func apply(
        _ repair: Repair,
        card: IdentifiedCard,
        in container: ModelContainer
    ) -> Bool {
        do {
            return try CollectionWriteSerializer.perform(
                container: container,
                timeout: .wait
            ) { context in
        guard let row = CollectionStore(context: context).card(forKey: repair.collectionKey),
              row.collectionKey == repair.collectionKey,
              row.variantID == repair.storedVariantID,
              row.variantResolutionRaw == repair.storedResolutionRaw,
              !repair.requiresConfirmation
                || (row.pendingCatalogFinishID == repair.pendingFinishID
                    && row.pendingCatalogFinishFirstSeenAt == repair.pendingFirstSeenAt
                    && row.pendingCatalogFinishRefreshID == repair.pendingRefreshID),
              row.priceKey == repair.target.id,
              self.repair(
                storedVariantID: row.variantID,
                storedResolution: row.variantResolution,
                itemKind: row.itemKind,
                printRun: row.pokemonPrintRun,
                card: card
              ) == repair.resolved else {
            return false
        }

        do {
            let key = row.collectionKey
            let descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.collectionKey == key }
            )
            let activities = try context.fetch(descriptor)
                .filter { $0.kind.hasQuantityClaim && $0.signedQuantity > 0 && $0.remainingQuantity > 0 }
                .sorted {
                    if $0.occurredAt != $1.occurredAt {
                        return $0.occurredAt < $1.occurredAt
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }

            var coveredQuantity = 0
            for activity in activities {
                let (sum, overflow) = coveredQuantity.addingReportingOverflow(
                    activity.remainingQuantity
                )
                guard !overflow else { return false }
                coveredQuantity = sum
            }
            guard coveredQuantity == row.quantity, !activities.isEmpty else {
                PerformanceSignpost.emitEvent(
                    "pokemonFinishReconciliationSkipped",
                    "reason=activityCoverage"
                )
                return false
            }

            guard let currentRow = CollectionStore(context: context).card(forKey: repair.collectionKey) else {
                return false
            }
            let claims = activities.map {
                CollectionVariantCorrectionClaim(
                    activityID: $0.id,
                    quantity: $0.remainingQuantity
                )
            }
            let mode: CollectionVariantCorrectionMode = repair.kind == .quietBackfill
                ? .quietBackfill
                : .visibleCorrection
            let source: CollectionActivitySource = repair.kind == .quietBackfill
                ? .catalogBackfill
                : .catalogUpdate
            return try CollectionStore(context: context).recordVariantCorrection(
                for: currentRow,
                to: repair.resolved,
                claims: claims,
                source: source,
                mode: mode
            ) != nil
        } catch {
            PerformanceSignpost.emitEvent(
                "pokemonFinishReconciliationSkipped",
                "reason=collectionCorrection"
            )
            return false
        }
            }
        } catch {
            PerformanceSignpost.emitEvent(
                "pokemonFinishReconciliationSkipped",
                "reason=collectionCorrection"
            )
            return false
        }
    }
}

/// The value-only request handed from the UI facade to the refresh model actor.
/// The actor builds its target snapshot after the migration gate is held, so a
/// row rekeyed while a caller waited cannot be written under an obsolete key.
struct PriceRefreshRequest: Sendable {
    let usesPriceFallback: Bool
    let includeImported: Bool
    let forceUnsupportedRetry: Bool
    let sortOldestFirst: Bool
    let maximumTargetCount: Int?
    let markRecentlyCheckedIfEmpty: Bool
    let gradedOnly: Bool

    init(
        usesPriceFallback: Bool,
        includeImported: Bool,
        forceUnsupportedRetry: Bool,
        sortOldestFirst: Bool,
        maximumTargetCount: Int?,
        markRecentlyCheckedIfEmpty: Bool,
        gradedOnly: Bool = false
    ) {
        self.usesPriceFallback = usesPriceFallback
        self.includeImported = includeImported
        self.forceUnsupportedRetry = forceUnsupportedRetry
        self.sortOldestFirst = sortOldestFirst
        self.maximumTargetCount = maximumTargetCount
        self.markRecentlyCheckedIfEmpty = markRecentlyCheckedIfEmpty
        self.gradedOnly = gradedOnly
    }
}

struct PriceRefreshResult: Sendable, Equatable {
    let didRun: Bool
    let targetBuildFailed: Bool
    var wasPreempted: Bool = false
    var wasQueuedDuringSuspension: Bool = false
}

enum PriceRefreshProgress: Sendable {
    case catalog(completed: Int, total: Int)
    case reconciling(completed: Int, total: Int)
    case prices([PriceDelta])
    case fallback(completed: Int, total: Int, remainingToday: Int)
    case fallbackIdle
    case fallbackDisabled(pending: Int)
    case fallbackUnconfigured(pending: Int)
    case fallbackBudgetReached(pending: Int, resetAt: Date)
    case fallbackRateLimited(pending: Int, retryAt: Date)
    case fallbackFinished(checked: Int, priced: Int, remainingToday: Int)
}

/// Progress is produced by the model actor at answer/checkpoint cadence. Keep
/// the actor from waking the main actor once per printing: the latest
/// presentation value is enough, while price deltas are merged losslessly and
/// a final flush preserves terminal progress.
private actor PriceRefreshProgressRelay {
    private let consumer: @MainActor @Sendable (PriceRefreshProgress) -> Void
    private var pendingProgress: PriceRefreshProgress?
    private var pendingPriceDeltas: [String: PriceDelta] = [:]
    private var flushTask: Task<Void, Never>?

    init(consumer: @escaping @MainActor @Sendable (PriceRefreshProgress) -> Void) {
        self.consumer = consumer
    }

    func offer(_ value: PriceRefreshProgress) {
        switch value {
        case let .prices(deltas):
            // Price messages carry state, not presentation-only progress. Keep
            // every key's newest value even when a catalog/fallback progress
            // message arrives before the scheduled flush.
            for delta in deltas {
                pendingPriceDeltas[delta.key] = delta
            }
        default:
            pendingProgress = value
        }
        scheduleFlushIfNeeded()
    }

    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        await flush()
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        // The scheduled task owns the current slot. Clearing it here allows
        // the next provider answer to schedule another coalesced hop.
        flushTask = nil
        let deltas = pendingPriceDeltas.values.sorted { $0.key < $1.key }
        pendingPriceDeltas.removeAll()
        let progress = pendingProgress
        pendingProgress = nil
        guard !deltas.isEmpty || progress != nil else { return }

        await MainActor.run {
            if !deltas.isEmpty { consumer(.prices(deltas)) }
            if let progress { consumer(progress) }
        }
    }
}

struct PriceRefreshWorkResult: Sendable {
    let checkedAt: Date
    let priced: Int
    let failed: Int
    let latestSourceUpdate: Date?
    let checkedUnstampedProvider: Bool
    let changedPrices: Bool
    let foundNothingNewer: Bool
    let providerUnreachable: Bool
    let persistenceFailed: Bool
    /// Owned graded targets for which the vendor returned no matching graded
    /// product or variant. This is distinct from a priced target and remains
    /// visible instead of being reported as though no slab needed attention.
    let gradedLookupMisses: Int
    /// Graded product requests that failed at the transport layer. These are
    /// distinct from a provider response with no matching listing.
    let gradedTransportFailures: Int
    let reconciledDuplicateRecords: Int
    let repairedFinishes: Int
    let backfilledFinishes: Int
    let priceDeltas: [PriceDelta]
}

enum PriceRefreshWorkOutcome: Sendable {
    case noTargets
    case targetBuildFailed
    case cancelled(repairedFinishes: Int, backfilledFinishes: Int)
    case completed(PriceRefreshWorkResult)
}

/// Keeps prices current without ever claiming more than it knows.
///
/// Three separate promises, all of which the UI depends on:
///
/// - a refresh that fails leaves the previous price in place, labelled with its
///   real age, because yesterday's price beats no price;
/// - "checked" and "current as of" are different facts and are reported
///   separately, so a check that found no newer market data says exactly that;
/// - refreshing is per unique printing-and-variant, not per owned copy.
@MainActor
final class PriceRefreshController: ObservableObject {
    static let shared = PriceRefreshController()

    enum Owner: Equatable, Sendable {
        case foreground
        case background
    }

    struct SuspensionToken: Hashable, Sendable {
        fileprivate let id: UUID
    }

    enum FallbackStatus: Equatable {
        case idle
        case disabled(pending: Int)
        case unconfigured(pending: Int)
        case available(remainingToday: Int)
        case running(completed: Int, total: Int, remainingToday: Int)
        case finished(checked: Int, priced: Int, remainingToday: Int)
        case budgetReached(pending: Int, resetAt: Date)
        case rateLimited(pending: Int, retryAt: Date)
    }

    struct Summary: Equatable {
        let checkedAt: Date
        let priced: Int
        let failed: Int
        /// The newest "market data current through" any provider reported.
        let latestSourceUpdate: Date?
        /// At least one successful provider response had no provider-side market
        /// timestamp. Such a response can be described as checked, but never as
        /// having no newer timestamp.
        let checkedUnstampedProvider: Bool
        /// Whether any stored unit price actually changed during this refresh.
        let changedPrices: Bool
        /// True when nothing the providers returned was newer than what was
        /// already stored. Saying so is more useful than implying an update.
        let foundNothingNewer: Bool
        /// The catalog provider could not be reached and the pass stopped early.
        /// Reported separately from `failed` because it is one fact about the
        /// network, not a count of cards with something wrong with them.
        var providerUnreachable = false
        /// At least one provider response or identity update could not be
        /// durably persisted. Network success is not presented as a complete
        /// refresh in this state.
        var persistenceFailed = false
        /// Number of redundant synced rows repaired and durably removed.
        var reconciledDuplicateRecords = 0
        /// Collection rows whose finish identity was corrected from fresh
        /// authoritative Pokémon catalog evidence.
        var repairedFinishes = 0
        /// Collection rows whose previously unknown finish was filled quietly.
        var backfilledFinishes = 0
        /// The refresh stopped after durably applying some finish work.
        var wasCancelled = false
        /// Owned graded targets with no matching vendor graded result.
        var gradedLookupMisses = 0
        /// Owned graded targets whose product lookup could not complete.
        var gradedTransportFailures = 0
        /// The target snapshot could not be read, so no refresh claim is safe.
        var targetBuildFailed = false
    }

    enum Status: Equatable {
        case idle
        case recentlyChecked
        case refreshing(completed: Int, total: Int)
        case reconciling(completed: Int, total: Int)
        case finished(Summary)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var fallbackStatus: FallbackStatus = .idle

    // The budget service is also used to restore fallback availability while no
    // refresh is running. The actor owns its own provider and persistence
    // services for the refresh itself.
    private let fallbackService = ProductPriceService.shared

    /// Opt-in, and off until a key is present. The catalog prices most of the
    /// collection for free; this is only for what it cannot reach.
    ///
    /// Read from `UserDefaults` rather than declared with `@AppStorage`: that
    /// wrapper is a SwiftUI `DynamicProperty` and only updates inside a `View`.
    /// The settings screen writes the same key.
    private var usesPriceFallback: Bool {
        UserDefaults.standard.bool(forKey: "usesPriceFallback")
    }

    /// Below this age an automatic refresh is skipped. TCGplayer itself only
    /// republishes every few hours at best, so asking more often buys nothing and
    /// costs the user's battery and the provider's bandwidth.
    nonisolated static let automaticRefreshInterval: TimeInterval = 8 * 60 * 60

    /// The fallback vendor has a monthly request ceiling. Rechecking a stable
    /// listing on every ordinary catalog refresh spends that allowance without
    /// improving the quote, so fallback requests run weekly per price identity.
    /// New items and explicit Price Check actions remain available immediately.
    nonisolated static let fallbackRefreshInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Enough parallelism to make a few hundred cards quick, few enough to stay a
    /// polite client.
    nonisolated fileprivate static let maxConcurrentRequests = 4

    /// A short run of in-flight requests failing to reach the provider is taken
    /// as the provider being down. Small on purpose: the cost of being wrong is
    /// one retry, and the cost of being slow is minutes of timeouts.
    nonisolated fileprivate static let unreachableThreshold = maxConcurrentRequests

    /// The pass currently running, if any.
    ///
    /// Unstructured on purpose. A refresh is owned by this controller, not by
    /// whichever view happened to start it: the automatic pass is kicked off
    /// from a `task(id:)` whose identity is derived from the collection and its
    /// price records, which is exactly what the refresh writes. Running the work
    /// as a child of that task made every saved batch cancel the pass that
    /// produced it, silently, partway through. Cancellation is still available
    /// — `cancelRefresh()` — but it now means "the user left", which is the only
    /// thing it was ever supposed to mean.
    private var activeRefresh: Task<PriceRefreshResult, Never>?
    private(set) var activeRefreshOwner: Owner?
    private var activeRefreshQueueID: UUID?
    private var preemptedRefreshQueueIDs: Set<UUID> = []
    private var activeRefreshContainer: ModelContainer?
    private var activeRefreshContinuation: StorageGenerationContinuation?
    private var activeQueueRequest: PriceRefreshRequest?
    private var suspensionTokens: Set<UUID> = []
    private var writeSuspensionRevision: UInt64 = 0
    private(set) var isSuspendedForWrite = false
    private var retainedQueueIDForSuspension: UUID?
    private var suspensionNeedsReplay = false
    private var statusBeforeWriteSuspension: Status?
    private var suspendedContainer: ModelContainer?
    private var suspendedContinuation: StorageGenerationContinuation?
    private var lastProgressPublicationAt: Date?
    private var lastPublishedProgressPercent: Int?
    private weak var registeredPortfolio: PortfolioEngine?
    private weak var registeredPriceSnapshotStore: PriceSnapshotStore?
    private weak var registeredRevisionStore: StoreRevisionStore?
    private weak var registeredCompletionSignal: PriceRefreshCompletionSignal?
    private var pokemonFetchOverrideForTesting: PriceRefreshPokemonFetchOverride?
    /// A caller that arrives during a pass must not lose its newer targets.
    /// Keep a trailing request; the actor rebuilds its targets from the live
    /// context when it reaches that request rather than retaining model rows.
    private var pendingRefreshRequests: [PendingRefreshRequest] = []
    private var queueDrainWaiters: [CheckedContinuation<PriceRefreshResult, Never>] = []
    private var hasQueuedRefreshOutcomeToReport = false
    private var completedQueuedRefreshResult: PriceRefreshResult?

    private struct PendingRefreshRequest {
        var request: PriceRefreshRequest
        var owner: Owner
    }

    private var isRefreshing: Bool {
        if case .refreshing = status { return true }
        if case .reconciling = status { return true }
        return false
    }

    /// True for the whole controller-owned queue, including the brief setup
    /// and terminal windows where presentation status has not yet changed.
    var isPassInFlight: Bool {
        activeRefresh != nil || isRefreshing
    }

    /// Publishes progress at a human-visible cadence while keeping terminal
    /// states immediate. Fallback progress is carried in the same publication
    /// so the two observers do not each update once per candidate.
    private func publishRefreshingProgress(
        completed: Int,
        total: Int,
        fallbackRemainingToday: Int? = nil,
        force: Bool = false
    ) {
        let now = Date.now
        let intervalElapsed = lastProgressPublicationAt.map {
            now.timeIntervalSince($0) >= Self.progressPublishInterval
        } ?? true
        let percent: Int = {
            guard total > 0 else { return completed == 0 ? 0 : 100 }
            return min(100, max(0, Int((Double(completed) / Double(total) * 100).rounded(.down))))
        }()
        let percentChanged = lastPublishedProgressPercent != percent
        guard force || (intervalElapsed && percentChanged) else { return }

        status = .refreshing(completed: completed, total: total)
        if let fallbackRemainingToday {
            fallbackStatus = .running(
                completed: completed,
                total: total,
                remainingToday: fallbackRemainingToday
            )
        }
        lastProgressPublicationAt = now
        lastPublishedProgressPercent = percent
    }

    private func consume(_ progress: PriceRefreshProgress) {
        switch progress {
        case let .catalog(completed, total):
            publishRefreshingProgress(
                completed: completed,
                total: total,
                force: completed == 0
            )
        case let .reconciling(completed, total):
            status = .reconciling(completed: completed, total: total)
        case let .prices(deltas):
            registeredPriceSnapshotStore?.apply(deltas)
            registeredPortfolio?.applyPriceDeltas(deltas)
        case let .fallback(completed, total, remainingToday):
            publishRefreshingProgress(
                completed: completed,
                total: total,
                fallbackRemainingToday: remainingToday,
                force: completed == 0
            )
        case .fallbackIdle:
            fallbackStatus = .idle
        case let .fallbackDisabled(pending):
            fallbackStatus = .disabled(pending: pending)
        case let .fallbackUnconfigured(pending):
            fallbackStatus = .unconfigured(pending: pending)
        case let .fallbackBudgetReached(pending, resetAt):
            fallbackStatus = .budgetReached(pending: pending, resetAt: resetAt)
        case let .fallbackRateLimited(pending, retryAt):
            fallbackStatus = .rateLimited(pending: pending, retryAt: retryAt)
        case let .fallbackFinished(checked, priced, remainingToday):
            fallbackStatus = .finished(
                checked: checked,
                priced: priced,
                remainingToday: remainingToday
            )
        }
    }

    private func apply(_ result: PriceRefreshWorkResult) {
        status = .finished(
            Summary(
                checkedAt: result.checkedAt,
                priced: result.priced,
                failed: result.failed,
                latestSourceUpdate: result.latestSourceUpdate,
                checkedUnstampedProvider: result.checkedUnstampedProvider,
                changedPrices: result.changedPrices,
                foundNothingNewer: result.foundNothingNewer,
                providerUnreachable: result.providerUnreachable,
                persistenceFailed: result.persistenceFailed,
                reconciledDuplicateRecords: result.reconciledDuplicateRecords,
                repairedFinishes: result.repairedFinishes,
                backfilledFinishes: result.backfilledFinishes,
                gradedLookupMisses: result.gradedLookupMisses,
                gradedTransportFailures: result.gradedTransportFailures
            )
        )
    }

    private func cancelledFinishSummary(from result: PriceRefreshWorkResult) -> Summary? {
        guard result.repairedFinishes > 0 || result.backfilledFinishes > 0 else { return nil }
        return Summary(
            checkedAt: result.checkedAt,
            priced: result.priced,
            failed: result.failed,
            latestSourceUpdate: result.latestSourceUpdate,
            checkedUnstampedProvider: result.checkedUnstampedProvider,
            changedPrices: result.changedPrices,
            foundNothingNewer: result.foundNothingNewer,
            providerUnreachable: result.providerUnreachable,
            persistenceFailed: result.persistenceFailed,
            reconciledDuplicateRecords: result.reconciledDuplicateRecords,
            repairedFinishes: result.repairedFinishes,
            backfilledFinishes: result.backfilledFinishes,
            wasCancelled: true,
            gradedLookupMisses: result.gradedLookupMisses,
            gradedTransportFailures: result.gradedTransportFailures
        )
    }

    /// Targets that a refresh should bother with.
    nonisolated static func staleTargets(
        from targets: [PriceTarget],
        now: Date = .now,
        usesPriceFallback: Bool = true,
        forceUnsupportedRetry: Bool = false
    ) -> [PriceTarget] {
        targets.filter { target in
            if target.itemKind == .gradedCard,
               target.lastFailureReasonRaw
                .flatMap(PricingDiagnosticReason.init(rawValue:))?.isGradedCoverageResult == true {
                guard target.canResolveGradedVariant else { return false }
                if forceUnsupportedRetry { return true }
                return target.lastCheckedAt.map {
                    now.timeIntervalSince($0) >= gradedCoverageRetryInterval
                } ?? true
            }
            if target.lastFailureReasonRaw == PricingDiagnosticReason.noSupportedProvider.rawValue {
                // Raw capability results use the long interval. Unbound slabs
                // use their own weekly graded-catalog retry policy regardless
                // of the raw-price fallback preference.
                if forceUnsupportedRetry { return true }
                if target.itemKind == .gradedCard {
                    guard target.canResolveGradedVariant else { return false }
                    return target.lastCheckedAt.map {
                        now.timeIntervalSince($0) >= gradedCoverageRetryInterval
                    } ?? true
                }
                guard usesPriceFallback else { return false }
                return target.lastCheckedAt.map {
                    now.timeIntervalSince($0) >= noSupportedProviderRetryInterval
                } ?? true
            }
            // A never-checked row needs an immediate first attempt. Later
            // automatic passes respect the ordinary interval even if the
            // catalog has no quote or no artwork for this printing.
            if !target.hasPrice || target.needsArtwork {
                if forceUnsupportedRetry { return true }
                return target.lastCheckedAt.map {
                    now.timeIntervalSince($0) >= automaticRefreshInterval
                } ?? true
            }

            let identityResolvedAfterFailure = target.catalogPrintingID != nil
                && target.lastFailureAt != nil
                && target.catalogMetadataCheckedAt.map {
                    $0 > (target.lastCheckedAt ?? .distantPast)
                } == true
            if identityResolvedAfterFailure { return true }

            let priceNeedsRefresh = target.lastCheckedAt.map {
                now.timeIntervalSince($0) >= automaticRefreshInterval
            } ?? true
            guard target.importedIdentity != nil else { return priceNeedsRefresh }
            let metadataNeedsRefresh = target.catalogMetadataCheckedAt.map {
                now.timeIntervalSince($0) >= automaticRefreshInterval
            } ?? true
            return priceNeedsRefresh || metadataNeedsRefresh
        }
    }

    /// A capability gap is stable for much longer than a transport failure.
    /// Keeping this interval separate prevents an unpriceable identity from
    /// turning every launch into another request.
    nonisolated static let noSupportedProviderRetryInterval: TimeInterval = 30 * 24 * 60 * 60

    /// Graded catalog coverage changes as sales add new rows, so a successful
    /// miss is revisited weekly instead of treated as a stable capability gap.
    nonisolated static let gradedCoverageRetryInterval: TimeInterval = 7 * 24 * 60 * 60

    /// The historical non-Pokémon rule: a provider's native-currency amount
    /// counts when fallback is off, and requires USD when fallback is enabled.
    nonisolated static func hasFinishedPrice(
        amount: Double?,
        currencyCode: String?,
        usesFallback: Bool
    ) -> Bool {
        guard amount != nil else { return false }
        return !usesFallback
            || currencyCode?.caseInsensitiveCompare("USD") == .orderedSame
    }

    /// Pokémon collection valuation is always denominated in USD. Provider
    /// fallback configuration controls lookup order, never whether EUR is a
    /// completed canonical price.
    nonisolated static func hasFinishedPokemonPrice(
        amount: Double?,
        currencyCode: String?
    ) -> Bool {
        amount != nil
            && currencyCode?.caseInsensitiveCompare("USD") == .orderedSame
    }

    /// Sealed artwork is part of the owned product, not an optional price
    /// enhancement. An exact sealed variant may therefore use the configured
    /// vendor connection for one missing-artwork backfill even when general
    /// catalog fallback pricing is disabled.
    nonisolated static func permitsVendorWork(
        for target: PriceTarget,
        usesFallback: Bool
    ) -> Bool {
        usesFallback || (target.itemKind == .sealedProduct && target.needsArtwork)
    }

    /// The actor rebuilds its target snapshot from the context after the
    /// migration gate is held, so the request never carries model objects or a
    /// stale display-order snapshot across the boundary.
    ///
    /// A second caller arriving while a pass is already running waits for that
    /// pass and queues any targets it added. Returning the second caller's
    /// targets was a silent no-op: pulling to refresh during the automatic
    /// startup check looked like a button that did nothing.
    func refresh(
        _ request: PriceRefreshRequest,
        container: ModelContainer,
        shouldContinue: StorageGenerationContinuation? = nil,
        owner: Owner = .foreground,
        identityRewritePermit: PriceIdentityRewritePermit? = nil
    ) async -> PriceRefreshResult {
        let controllerState = PerformanceSignpost.beginInterval(
            "priceRefresh.controller",
            id: PerformanceSignpost.makeID(),
            "maxTargets=\(request.maximumTargetCount.map(String.init) ?? "all")"
        )
        var controllerOutcome = "joined"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.controller",
                controllerState,
                "outcome=\(controllerOutcome)"
            )
        }
        guard shouldContinue?() ?? true else {
            controllerOutcome = "cancelled"
            return PriceRefreshResult(didRun: false, targetBuildFailed: false)
        }
        if isSuspendedForWrite {
            suspendedContainer = container
            suspendedContinuation = shouldContinue
            enqueuePending(request, owner: owner)
            hasQueuedRefreshOutcomeToReport = true
            completedQueuedRefreshResult = nil
            // Do not wait here: an enclosing migration operation may own the
            // migration gate that the exclusive writer is waiting to acquire.
            // Returning releases that gate; the queued request runs after the
            // writer resumes the controller.
            controllerOutcome = "queued-during-suspension"
            return PriceRefreshResult(
                didRun: false,
                targetBuildFailed: false,
                wasQueuedDuringSuspension: true
            )
        }
        if let activeRefresh {
            if owner == .foreground { activeRefreshOwner = .foreground }
            let suspensionRevision = writeSuspensionRevision
            enqueuePending(request, owner: owner)
            var result = await activeRefresh.value
            if writeSuspensionRevision != suspensionRevision {
                result.wasQueuedDuringSuspension = true
            }
            return result
        }

        // The active task represents the whole queue, not just the first pass.
        // A caller that joins after the first pass has completed must remain
        // suspended until its trailing targets have been processed too.
        let queueID = UUID()
        activeRefreshOwner = owner
        activeRefreshQueueID = queueID
        activeQueueRequest = request
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return PriceRefreshResult(didRun: false, targetBuildFailed: false)
            }
            let runQueue = {
                await self.runRefreshQueue(
                    queueID: queueID,
                    startingWith: request,
                    container: container,
                    shouldContinue: shouldContinue
                )
            }
            if let identityRewritePermit {
                return await PriceIdentityRewriteAuthorization.withAuthorizedTask(
                    identityRewritePermit,
                    operation: runQueue
                )
            }
            return await runQueue()
        }
        activeRefresh = task
        activeRefreshContainer = container
        activeRefreshContinuation = shouldContinue
        let result = await task.value
        resumeQueueDrainWaitersIfReady(with: result)
        if let pending = pendingFallbackWork {
            await updateFallbackAvailability(pending: pending)
        }
        controllerOutcome = result.targetBuildFailed ? "target-build-failed" : (result.didRun ? "completed" : "empty-or-cancelled")
        return result
    }

    /// Pauses refresh queues for an identity rewrite. A normal suspension
    /// cancels and retains the active request; a scanner binding can instead
    /// let the active request reach its checkpoint and pause before trailing
    /// work, avoiding a full pass restart.
    func suspendPasses(cancelActivePass: Bool = true) async -> SuspensionToken {
        let token = UUID()
        suspensionTokens.insert(token)
        guard suspensionTokens.count == 1 else {
            // A scanner binding may already be waiting for the current pass
            // without cancelling it. If a real structural writer arrives
            // during that wait, upgrade the shared suspension and cancel the
            // active request instead of making that writer wait for the whole
            // provider pass as well.
            if cancelActivePass {
                retainActiveRequestForSuspension()
                activeRefresh?.cancel()
            }
            return SuspensionToken(id: token)
        }
        let passWasInFlight = activeRefresh != nil || isRefreshing
        writeSuspensionRevision &+= 1
        statusBeforeWriteSuspension = status
        isSuspendedForWrite = true
        retainedQueueIDForSuspension = nil
        suspensionNeedsReplay = false
        suspendedContainer = activeRefreshContainer
        suspendedContinuation = activeRefreshContinuation
        if cancelActivePass { retainActiveRequestForSuspension() }
        if !pendingRefreshRequests.isEmpty {
            hasQueuedRefreshOutcomeToReport = true
            completedQueuedRefreshResult = nil
        }
        if let activeRefresh {
            if cancelActivePass { activeRefresh.cancel() }
            _ = await activeRefresh.value
        }
        if passWasInFlight, suspensionNeedsReplay {
            status = .refreshing(completed: 0, total: 0)
        } else {
            // A non-cancelling scanner bind lets this request finish. Preserve
            // its terminal summary instead of replacing it with a fake 0/0
            // refresh state after the pass has already completed.
            statusBeforeWriteSuspension = status
        }
        return SuspensionToken(id: token)
    }

    private func retainActiveRequestForSuspension() {
        guard let queueID = activeRefreshQueueID,
              retainedQueueIDForSuspension != queueID else { return }
        if let activeQueueRequest {
            enqueuePending(
                activeQueueRequest,
                owner: activeRefreshOwner ?? .foreground
            )
            suspensionNeedsReplay = true
        }
        retainedQueueIDForSuspension = queueID
    }

    func resume(_ token: SuspensionToken) {
        guard suspensionTokens.remove(token.id) != nil else {
            assertionFailure("Unknown price-refresh suspension token")
            return
        }
        guard suspensionTokens.isEmpty else { return }
        isSuspendedForWrite = false
        retainedQueueIDForSuspension = nil
        suspensionNeedsReplay = false

        guard let container = suspendedContainer else {
            // Storage transitions explicitly abandon queued work when its
            // container is no longer available.
            pendingRefreshRequests.removeAll()
            suspendedContainer = nil
            suspendedContinuation = nil
            activeRefresh = nil
            activeRefreshOwner = nil
            activeRefreshQueueID = nil
            activeRefreshContainer = nil
            activeRefreshContinuation = nil
            activeQueueRequest = nil
            if case .refreshing(completed: 0, total: 0) = status {
                switch statusBeforeWriteSuspension {
                case .some(.finished), .some(.recentlyChecked), .some(.idle):
                    status = statusBeforeWriteSuspension ?? .idle
                case .some(.refreshing), .some(.reconciling), .none:
                    status = .idle
                }
            }
            statusBeforeWriteSuspension = nil
            resumeQueueDrainWaitersIfReady(
                with: PriceRefreshResult(didRun: false, targetBuildFailed: false)
            )
            return
        }
        guard let pending = takePendingRefresh() else {
            suspendedContainer = nil
            suspendedContinuation = nil
            activeRefresh = nil
            activeRefreshOwner = nil
            activeRefreshQueueID = nil
            activeRefreshContainer = nil
            activeRefreshContinuation = nil
            activeQueueRequest = nil
            if case .refreshing(completed: 0, total: 0) = status {
                switch statusBeforeWriteSuspension {
                case .some(.finished), .some(.recentlyChecked), .some(.idle):
                    status = statusBeforeWriteSuspension ?? .idle
                case .some(.refreshing), .some(.reconciling), .none:
                    status = .idle
                }
            }
            statusBeforeWriteSuspension = nil
            resumeQueueDrainWaitersIfReady(
                with: PriceRefreshResult(didRun: false, targetBuildFailed: false)
            )
            return
        }
        statusBeforeWriteSuspension = nil
        let continuation = suspendedContinuation
        let queueID = UUID()
        activeRefreshOwner = pending.owner
        activeRefreshQueueID = queueID
        activeQueueRequest = pending.request
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return PriceRefreshResult(didRun: false, targetBuildFailed: false)
            }
            let result = await MagicTreatmentMigrationCoordinator.shared.withPriceRefresh(
                in: ModelContext(container),
                runsNetworkMigration: false,
                shouldContinue: continuation,
                operation: { _ in
                    await self.runRefreshQueue(
                        queueID: queueID,
                        startingWith: pending.request,
                        container: container,
                        shouldContinue: continuation
                    )
                }
            )
            guard let result else {
                self.clearUnstartedResumedQueue(queueID)
                let abandoned = PriceRefreshResult(didRun: false, targetBuildFailed: false)
                self.resumeQueueDrainWaitersIfReady(with: abandoned)
                return abandoned
            }
            self.resumeQueueDrainWaitersIfReady(with: result)
            return result
        }
        activeRefresh = task
        activeRefreshContainer = container
        activeRefreshContinuation = continuation
        Task { @MainActor [weak self] in
            _ = await task.value
            if let pending = self?.pendingFallbackWork {
                await self?.updateFallbackAvailability(pending: pending)
            }
        }
    }

    /// Waits for work queued while an exclusive writer held the migration gate.
    /// Callers must invoke this after releasing that gate, otherwise the queued
    /// pass could never reacquire it.
    func waitForQueuedRefreshesToFinish() async -> PriceRefreshResult? {
        if let completedQueuedRefreshResult {
            return completedQueuedRefreshResult
        }
        guard activeRefresh != nil || !pendingRefreshRequests.isEmpty || isSuspendedForWrite else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            queueDrainWaiters.append(continuation)
        }
    }

    private func resumeQueueDrainWaitersIfReady(with result: PriceRefreshResult) {
        guard activeRefresh == nil,
              pendingRefreshRequests.isEmpty,
              !isSuspendedForWrite else { return }
        if hasQueuedRefreshOutcomeToReport {
            completedQueuedRefreshResult = result
            hasQueuedRefreshOutcomeToReport = false
        }
        guard !queueDrainWaiters.isEmpty else { return }
        let waiters = queueDrainWaiters
        queueDrainWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }

    /// Stops the pass in progress. The only legitimate reason is that the work
    /// has genuinely been abandoned — never that its own writes changed the
    /// data some view is keyed on.
    func cancelRefresh() {
        activeRefresh?.cancel()
        pendingRefreshRequests.removeAll()
        if isSuspendedForWrite {
            statusBeforeWriteSuspension = nil
            suspendedContainer = nil
            suspendedContinuation = nil
            status = .idle
        }
        resumeQueueDrainWaitersIfReady(
            with: PriceRefreshResult(didRun: false, targetBuildFailed: false)
        )
    }

    /// Cancels the active queue only when it is still owned by the requested
    /// lifecycle. A foreground join promotes a background queue, so background
    /// task expiration can no longer cancel work the app now owns.
    @discardableResult
    func cancelRefresh(onlyIfOwnedBy owner: Owner) -> Bool {
        guard activeRefreshOwner == owner,
              let activeRefresh else { return false }
        if owner == .background, let activeRefreshQueueID {
            preemptedRefreshQueueIDs.insert(activeRefreshQueueID)
            pendingRefreshRequests.removeAll()
        }
        activeRefresh.cancel()
        return true
    }

    /// Foreground startup waits only for a background-owned pass to unwind.
    @discardableResult
    func preemptBackgroundPass() async -> Bool {
        guard activeRefreshOwner == .background,
              let activeRefresh,
              let activeRefreshQueueID else { return false }
        preemptedRefreshQueueIDs.insert(activeRefreshQueueID)
        pendingRefreshRequests.removeAll()
        activeRefresh.cancel()
        _ = await activeRefresh.value
        return true
    }

    private func clearUnstartedResumedQueue(_ queueID: UUID) {
        guard activeRefreshQueueID == queueID else { return }
        activeRefresh = nil
        activeRefreshOwner = nil
        activeRefreshQueueID = nil
        activeRefreshContainer = nil
        activeRefreshContinuation = nil
        activeQueueRequest = nil
        // A newer exclusive writer owns the suspended snapshot and pending
        // request now. This resumed task only owns the active markers it set;
        // clearing the shared suspension here drops the request permanently.
        if isSuspendedForWrite { return }
        if !(suspendedContinuation?() ?? true) {
            pendingRefreshRequests.removeAll()
        }
        suspendedContainer = nil
        suspendedContinuation = nil
        if case .refreshing(completed: 0, total: 0) = status { status = .idle }
        registeredCompletionSignal?.advance()
    }

    private func runRefreshQueue(
        queueID: UUID,
        startingWith initialRequest: PriceRefreshRequest,
        container: ModelContainer,
        shouldContinue: StorageGenerationContinuation?
    ) async -> PriceRefreshResult {
        func makeResult(didRun: Bool, targetBuildFailed: Bool) -> PriceRefreshResult {
            PriceRefreshResult(
                didRun: didRun,
                targetBuildFailed: targetBuildFailed,
                wasPreempted: preemptedRefreshQueueIDs.contains(queueID)
            )
        }
        var didBeginPortfolioRefresh = false
        defer {
            if didBeginPortfolioRefresh {
                // The replay gate is settled for every terminal outcome,
                // including cancellation and target-build failure. It is tied
                // to the controller's queue, not the happy path.
                if shouldContinue?() ?? true {
                    registeredPortfolio?.endPriceRefresh(context: container.mainContext)
                } else {
                    pendingRefreshRequests.removeAll()
                    registeredPortfolio?.cancelPriceRefresh()
                }
            }
            activeRefresh = nil
            activeRefreshOwner = nil
            activeRefreshQueueID = nil
            activeRefreshContainer = nil
            activeRefreshContinuation = nil
            activeQueueRequest = nil
            registeredCompletionSignal?.advance()
            preemptedRefreshQueueIDs.remove(queueID)
            if !isSuspendedForWrite,
               case .refreshing(completed: 0, total: 0) = status {
                status = .idle
            }
        }
        // The active marker is cleared in the same actor turn as the final
        // empty-queue check. A late caller can therefore either join a live
        // queue or start a new one; it cannot enqueue work after this queue has
        // already decided there is nothing left to process.
        guard shouldContinue?() ?? true else {
            pendingRefreshRequests.removeAll()
            return makeResult(didRun: false, targetBuildFailed: false)
        }
        registeredPortfolio?.beginPriceRefresh()
        didBeginPortfolioRefresh = true
        activeQueueRequest = initialRequest
        lastProgressPublicationAt = nil
        lastPublishedProgressPercent = nil
        let worker = PriceRefreshModelActor(modelContainer: container)
        if let pokemonFetchOverrideForTesting {
            await worker.setPokemonFetchOverrideForTesting(pokemonFetchOverrideForTesting)
        }
        let relay = PriceRefreshProgressRelay { [weak self] value in
            self?.consume(value)
        }
        let progress: @Sendable (PriceRefreshProgress) async -> Void = { value in
            await relay.offer(value)
        }
        var request = initialRequest
        var didRun = false
        var targetBuildFailed = false
        var lastCompletedResult: PriceRefreshWorkResult?
        while true {
            let outcome = await worker.run(
                request,
                progress: progress,
                shouldContinue: shouldContinue
            )
            await relay.flushNow()
            switch outcome {
            case .noTargets:
                if request.markRecentlyCheckedIfEmpty {
                    markRecentlyChecked()
                }
            case .targetBuildFailed:
                targetBuildFailed = true
                status = .finished(
                    Summary(
                        checkedAt: .now,
                        priced: 0,
                        failed: 0,
                        latestSourceUpdate: nil,
                        checkedUnstampedProvider: false,
                        changedPrices: false,
                        foundNothingNewer: false,
                        targetBuildFailed: true
                    )
                )
            case let .cancelled(repairedFinishes, backfilledFinishes):
                if shouldContinue?() ?? true {
                    if let fingerprint = await worker.priceValuesFingerprint() {
                        registeredRevisionStore?.expectPriceValuesFingerprint(fingerprint)
                    }
                }
                // Cancellation can happen after one or more durable
                // checkpoints. The live delta channel may have been partial;
                // finish with the same authoritative read used by success so
                // the snapshot cannot remain stale until an unrelated edit.
                if shouldContinue?() ?? true {
                    await registeredPriceSnapshotStore?.rebuild(container: container)
                }
                if repairedFinishes > 0 || backfilledFinishes > 0 {
                    status = .finished(
                        Summary(
                            checkedAt: .now,
                            priced: 0,
                            failed: 0,
                            latestSourceUpdate: nil,
                            checkedUnstampedProvider: false,
                            changedPrices: false,
                            foundNothingNewer: false,
                            repairedFinishes: repairedFinishes,
                            backfilledFinishes: backfilledFinishes,
                            wasCancelled: true
                        )
                    )
                } else {
                    if !isSuspendedForWrite { status = .idle }
                }
                return makeResult(didRun: didRun, targetBuildFailed: targetBuildFailed)
            case let .completed(result):
                didRun = true
                lastCompletedResult = result
                guard shouldContinue?() ?? true else {
                    status = cancelledFinishSummary(from: result).map(Status.finished) ?? .idle
                    return makeResult(didRun: didRun, targetBuildFailed: targetBuildFailed)
                }
                if let fingerprint = await worker.priceValuesFingerprint() {
                    registeredRevisionStore?.expectPriceValuesFingerprint(fingerprint)
                }
                if !result.priceDeltas.isEmpty {
                    consume(.prices(result.priceDeltas))
                }
                await registeredPriceSnapshotStore?.rebuild(container: container)
                apply(result)
            }

            guard !Task.isCancelled else {
                if shouldContinue?() ?? true {
                    if let fingerprint = await worker.priceValuesFingerprint() {
                        registeredRevisionStore?.expectPriceValuesFingerprint(fingerprint)
                    }
                    await registeredPriceSnapshotStore?.rebuild(container: container)
                }
                if let result = lastCompletedResult,
                   result.repairedFinishes == 0,
                   result.backfilledFinishes == 0 {
                    if !isSuspendedForWrite { status = .idle }
                }
                return makeResult(didRun: didRun, targetBuildFailed: targetBuildFailed)
            }
            guard shouldContinue?() ?? true else {
                if let result = lastCompletedResult,
                   let summary = cancelledFinishSummary(from: result) {
                    status = .finished(summary)
                } else {
                    if !isSuspendedForWrite { status = .idle }
                }
                return makeResult(didRun: didRun, targetBuildFailed: targetBuildFailed)
            }
            // A non-cancelling suspension lets the current request reach its
            // checkpoint, then leaves queued requests for resume under the
            // migration gate. It does not replay completed work.
            if isSuspendedForWrite { break }
            guard let pending = takePendingRefresh() else { break }
            request = pending.request
            if activeRefreshOwner != .foreground {
                activeRefreshOwner = pending.owner
            }
            activeQueueRequest = request
        }
        return makeResult(didRun: didRun, targetBuildFailed: targetBuildFailed)
    }

    private func enqueuePending(_ request: PriceRefreshRequest, owner: Owner) {
        if let index = pendingRefreshRequests.indices.last {
            let existing = pendingRefreshRequests[index].request
            pendingRefreshRequests[index].request = PriceRefreshRequest(
                usesPriceFallback: request.usesPriceFallback,
                includeImported: existing.includeImported || request.includeImported,
                forceUnsupportedRetry: existing.forceUnsupportedRetry || request.forceUnsupportedRetry,
                sortOldestFirst: existing.sortOldestFirst || request.sortOldestFirst,
                maximumTargetCount: mergedLimit(
                    existing.maximumTargetCount,
                    request.maximumTargetCount
                ),
                markRecentlyCheckedIfEmpty: existing.markRecentlyCheckedIfEmpty
                    || request.markRecentlyCheckedIfEmpty,
                gradedOnly: existing.gradedOnly && request.gradedOnly
            )
            if owner == .foreground {
                pendingRefreshRequests[index].owner = .foreground
            }
        } else {
            pendingRefreshRequests.append(PendingRefreshRequest(request: request, owner: owner))
        }
    }

    private func mergedLimit(_ left: Int?, _ right: Int?) -> Int? {
        switch (left, right) {
        case (nil, nil): return nil
        case (nil, _), (_, nil): return nil
        case let (left?, right?): return max(left, right)
        }
    }

    private func takePendingRefresh() -> PendingRefreshRequest? {
        guard !pendingRefreshRequests.isEmpty else { return nil }
        return pendingRefreshRequests.removeFirst()
    }

    /// Whether the catalog's answer leaves work for the fallback.
    ///
    /// Two cases, and the second is the one that is easy to miss: a Cardmarket
    /// euro price *is* a price, but not one the collection can total, so it is
    /// treated as unfinished rather than done.
    nonisolated static func needsFallback(
        _ lookup: PriceLookup,
        identifiedCatalogCard: Bool = false
    ) -> Bool {
        PriceFallbackQuoteResolver.needsFallback(
            lookup,
            identifiedCatalogCard: identifiedCatalogCard
        )
    }

    /// One card the catalog could not finish, captured with whatever identity
    /// was available at the moment it fell through.
    fileprivate struct FallbackCandidate {
        let target: PriceTarget
        /// Present when the catalog identified the card but could not price it.
        /// Absent when the catalog could not identify it at all.
        let card: IdentifiedCard?

        /// A stored vendor card handle or provider-published TCGplayer id lets a
        /// card batch immediately, without paying for a name search. Pokémon
        /// fall-throughs normally have neither — they fell through precisely
        /// because TCGdex published no TCGplayer block — so those still need
        /// identity resolved once.
        ///
        /// This used to send the Scryfall id for every Magic card, on the
        /// assumption that Scryfall's id is one of the vendor's supported
        /// lookup keys. It is a documented *parameter*, but the vendor does not
        /// hold the mapping: a batch keyed on it comes back empty. Because an
        /// absent variant is deliberately left alone rather than cleared, that
        /// failed silently — the card was never priced and never had its
        /// identity resolved either, because it had gone down the batch path
        /// instead of the search path.
        ///
        /// For Magic, Scryfall's marketplace id belongs to the exact printing,
        /// including treated foil printings. Art cards and tokens — precisely
        /// the fall-through population — can still come back `null`; those have
        /// no keyed route and must resolve by search once, after which the stored
        /// variant handle makes every later refresh a batch.
        var externalLookups: [JustTCGBatchLookup] {
            if let catalogID = card?.providerID ?? target.catalogPrintingID,
               let variant = target.variantID.map(PhysicalVariant.resolving) {
                let stamped = PriceFallbackQuoteResolver.verifiedLookups(catalogID: catalogID, variant: variant)
                if !stamped.isEmpty { return stamped }
            }
            if let tcgplayerProductID = target.tcgplayerProductID,
               !tcgplayerProductID.isEmpty {
                return [.tcgplayerID(tcgplayerProductID)]
            }
            if let justTCGCardID = target.justTCGCardID,
               !justTCGCardID.isEmpty {
                return [.cardID(justTCGCardID)]
            }
            guard case let .magic(magic)? = card,
                  let tcgplayerID = magic.tcgplayerID else {
                return []
            }
            return [.tcgplayerID(String(tcgplayerID))]
        }

        func subject(vendorCardID: String?) -> ProductPriceSubject? {
            let identity = target.fallbackIdentity ?? target.importedIdentity
            let name = card?.name ?? identity?.name
            let setName = card?.setName ?? identity?.setName
            let number = card?.cardNumber ?? identity?.cardNumber
            guard let name, let setName, let number, !name.isEmpty, !number.isEmpty else {
                return nil
            }
            let catalogID = card?.providerID ?? target.catalogPrintingID
            return ProductPriceSubject(
                game: target.game,
                catalogID: catalogID,
                name: name,
                setName: setName,
                cardNumber: number,
                japaneseSetID: catalogID.flatMap(PriceFallbackQuoteResolver.japaneseSetID(forCatalogCardID:)),
                pokemonPrintRun: target.pokemonPrintRun,
                vendorCardID: vendorCardID,
                magicTreatmentIDsRaw: target.magicTreatmentIDsRaw
            )
        }
    }

    /// Collapses candidates that name the same priced thing, preserving the
    /// order the refresh queued them in so the user still sees what they are
    /// looking at priced first.
    nonisolated fileprivate static func collapsingDuplicates(
        _ candidates: [FallbackCandidate]
    ) -> [FallbackCandidate] {
        var byKey: [String: FallbackCandidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            let key = ProductIdentity.key(
                game: candidate.target.game,
                printingID: candidate.target.printingID,
                variantID: candidate.target.variantID,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw
            )
            guard let existing = byKey[key] else {
                byKey[key] = candidate
                order.append(key)
                continue
            }
            if existing.card == nil, candidate.card != nil {
                byKey[key] = candidate
            }
        }
        return order.compactMap { byKey[$0] }
    }

    /// Ask the vendor about everything the catalog left unfinished.
    ///
    /// Returns how many cards it durably priced. Anything it cannot answer is
    /// left exactly as the catalog left it — including a Cardmarket euro price,
    /// which stays as the last resort rather than being cleared.
    nonisolated fileprivate static func rowIdentities(
        in context: ModelContext
    ) -> [RefreshRowIdentity] {
        let rows = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return rows.map {
            RefreshRowIdentity(
                collectionKey: $0.collectionKey,
                priceKey: $0.priceKey,
                providerID: $0.providerID,
                variantID: $0.variantID,
                marketVariantID: $0.justTCGVariantID,
                itemKind: $0.itemKind,
                imageURLIsMissing: $0.imageURL == nil
            )
        }
    }

    nonisolated fileprivate static func rowIdentitiesByPriceKey(
        in context: ModelContext
    ) -> [String: [RefreshRowIdentity]] {
        rowIdentities(in: context).reduce(into: [:]) { result, row in
            result[row.priceKey, default: []].append(row)
        }
    }

    nonisolated fileprivate static func rowIdentitiesByProviderID(
        in context: ModelContext
    ) -> [String: [RefreshRowIdentity]] {
        rowIdentities(in: context).filter { $0.providerID.hasPrefix("csv:") }
            .reduce(into: [:]) { result, row in
                result[row.providerID, default: []].append(row)
            }
    }

    /// Re-fetches only the live rows named by value keys. Callers use this
    /// immediately before a read-only reconciliation decision; they never
    /// retain the returned SwiftData models across an await.
    nonisolated fileprivate static func liveRows(
        collectionKeys: [String],
        in context: ModelContext
    ) throws -> [CollectedCard] {
        guard !collectionKeys.isEmpty else { return [] }
        let keys = Array(Set(collectionKeys))
        return try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { keys.contains($0.collectionKey) }
            )
        )
    }

    /// Applies product artwork independently of whether the returned variant
    /// has a market price. A completed response without a usable marketplace
    /// image is stamped at the current resolver version so an already-priced
    /// row does not spend one request per refresh learning the same fact.
    nonisolated static func recordSealedArtwork(
        from marketCard: JustTCGCard,
        for owners: [MarketPriceTarget],
        rowsByPriceKey: [String: [CollectedCard]],
        checkedAt: Date = .now
    ) {
        let artwork = JustTCGV1Client.productImageURL(tcgplayerID: marketCard.tcgplayerId)
        for owner in owners where owner.itemKind == .sealedProduct {
            for row in rowsByPriceKey[owner.priceKey] ?? []
            where row.itemKind == .sealedProduct && row.imageURL == nil {
                // Record the catalog-owned retry watermark before applying the
                // image; the helper intentionally requires artwork to be
                // missing so a completed row cannot be stamped accidentally.
                CollectionCatalogNormalizer.recordSealedArtworkCheck(
                    on: row,
                    at: checkedAt
                )
                if let artwork {
                    row.imageURL = artwork.absoluteString
                }
            }
        }
    }

    /// A full response that carried no listing for the exact variant asked
    /// about. The vendor was asked and published nothing, which is the terminal
    /// artwork fact — stamped so the row stops re-entering every refresh.
    ///
    /// Only ever called for a non-delta response, where absence is a real
    /// answer rather than "unchanged since the cutoff". No price is touched: a
    /// missing listing is not evidence that a stored amount is wrong.
    nonisolated static func recordSealedArtworkMiss(
        for owners: [MarketPriceTarget],
        rowsByPriceKey: [String: [CollectedCard]],
        checkedAt: Date = .now
    ) {
        for owner in owners where owner.itemKind == .sealedProduct {
            for row in rowsByPriceKey[owner.priceKey] ?? []
            where row.itemKind == .sealedProduct && row.imageURL == nil {
                CollectionCatalogNormalizer.recordSealedArtworkCheck(
                    on: row,
                    at: checkedAt
                )
            }
        }
    }

    /// One matched vendor response, applied in dependency order. Identity and
    /// artwork deliberately happen before the optional price so a null market
    /// amount cannot discard valid product metadata.
    nonisolated static func accumulateMarketRefreshReport(
        _ report: MarketRefreshReport,
        priced: inout Int,
        changedPrices: inout Bool
    ) {
        priced += report.pricesWritten
        changedPrices = changedPrices || report.pricesWritten > 0
    }

    @discardableResult
    nonisolated static func applyVendorBatchHit(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        artworkRowsByPriceKey: [String: [CollectedCard]],
        identityRowsByPriceKey: [String: [CollectedCard]],
        identityIndex: ProductIdentityIndex? = nil,
        fetchedAt: Date = .now
    ) -> Bool {
        applyVendorBatchHitResult(
            card: card,
            variant: variant,
            owners: owners,
            store: store,
            identities: identities,
            artworkRowsByPriceKey: artworkRowsByPriceKey,
            identityRowsByPriceKey: identityRowsByPriceKey,
            identityIndex: identityIndex,
            fetchedAt: fetchedAt
        ).accepted
    }

    @discardableResult
    nonisolated static func applyVendorBatchHitResult(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        artworkRowsByPriceKey: [String: [CollectedCard]],
        identityRowsByPriceKey: [String: [CollectedCard]],
        identityIndex: ProductIdentityIndex? = nil,
        fetchedAt: Date = .now
    ) -> MarketRefreshApplyResult {
        // This callback is a second line of defence after the coordinator's
        // treatment-aware owner grouping. A response without a direct product
        // handle must never be written to a treatment-qualified Magic key, even
        // if a future caller accidentally supplies a mixed owner array.
        guard owners.allSatisfy({ !$0.isTreatmentQualified || $0.hasDirectVendorHandle }) else {
            return .rejected
        }
        recordSealedArtwork(
            from: card,
            for: owners,
            rowsByPriceKey: artworkRowsByPriceKey,
            checkedAt: fetchedAt
        )
        for owner in owners {
            let identityStored = identities.recordBatchResolution(
                forKey: owner.priceKey,
                cardID: card.uuid ?? card.id,
                variantID: variant.variantId,
                treatmentIDs: owner.magicTreatmentIDsRaw,
                at: fetchedAt,
                using: identityIndex
            )
            guard identityStored else { return .rejected }
            // Marketplace identity is catalog metadata: once the vendor has
            // told us which TCGplayer product this printing is, that stays
            // local, so opening the marketplace never needs a live request.
            for row in identityRowsByPriceKey[owner.priceKey] ?? [] {
                if let productID = card.tcgplayerId, row.tcgplayerProductID == nil {
                    row.tcgplayerProductID = productID
                }
                if let sku = variant.tcgplayerSkuId, row.tcgplayerSKUID == nil {
                    row.tcgplayerSKUID = sku
                }
            }
        }

        guard let amount = variant.marketPriceUSD else {
            return .accepted(metadataApplied: true, priceWritten: false)
        }
        let normalized = NormalizedPrice(
            unitMarketPriceUSD: amount,
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: variant.variantId ?? "batch",
            sourceUpdatedAt: variant.updatedAt,
            fetchedAt: fetchedAt
        )
        var allStored = true
        for owner in owners {
            let stored = store.store(
                .price(normalized),
                game: owner.game,
                printingID: owner.printingID,
                variantID: owner.variantID,
                marketVariantID: variant.variantId,
                treatmentIDs: owner.magicTreatmentIDsRaw
            )
            allStored = allStored && stored
            if let record = store.record(forKey: owner.priceKey) {
                if stored { record.justTCGFetchedAt = fetchedAt }
                record.marketVariantID = variant.variantId
                record.canonicalMarketID = card.uuid ?? card.id
                record.providerGameUpdatedAt = variant.updatedAt
                record.itemKindRaw = owner.itemKind.rawValue
                record.periodLow = variant.minPrice7d
                record.periodHigh = variant.maxPrice7d
                record.coefficientOfVariation = variant.covPrice7d
                record.periodChangeCount = variant.priceChangesCount7d
            }
        }
        return allStored
            ? .accepted(metadataApplied: true, priceWritten: true)
            : .rejected
    }

    /// Compatibility overload for callers that already have one row index.
    /// Identity persistence is now intentionally broader than artwork
    /// backfill, but existing support/test callers should keep compiling while
    /// they migrate to the two-index form.
    @discardableResult
    nonisolated static func applyVendorBatchHit(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        rowsByPriceKey: [String: [CollectedCard]],
        fetchedAt: Date = .now
    ) -> Bool {
        return applyVendorBatchHit(
            card: card,
            variant: variant,
            owners: owners,
            store: store,
            identities: identities,
            artworkRowsByPriceKey: rowsByPriceKey,
            identityRowsByPriceKey: rowsByPriceKey,
            fetchedAt: fetchedAt
        )
    }

    /// Checkpoint cadence is a durability budget, not a printing count.
    nonisolated fileprivate static let checkpointBudget: TimeInterval = 10
    /// Bound staged writes if a busy provider keeps the wall-clock budget open.
    nonisolated fileprivate static let stagedWriteCeiling = 500
    /// Progress is presentation-only. Publishing it more often than a few
    /// times per second makes every observer rebuild while provider work is
    /// still in flight.
    nonisolated fileprivate static let progressPublishInterval: TimeInterval = 1.0

    func registerPortfolio(_ portfolio: PortfolioEngine) {
        registeredPortfolio = portfolio
    }

    func registerPriceSnapshotStore(_ store: PriceSnapshotStore) {
        registeredPriceSnapshotStore = store
    }

    func registerRevisionStore(_ store: StoreRevisionStore) {
        registeredRevisionStore = store
    }

    func registerCompletionSignal(_ signal: PriceRefreshCompletionSignal) {
        registeredCompletionSignal = signal
    }

    func setPokemonFetchOverrideForTesting(_ override: PriceRefreshPokemonFetchOverride?) {
        pokemonFetchOverrideForTesting = `override`
    }

    func dismissSummary() {
        switch status {
        case .finished, .recentlyChecked:
            status = .idle
        case .idle, .refreshing, .reconciling:
            break
        }
    }

    /// Clears the ten-second "here's what that refresh did" feedback, and only
    /// that.
    ///
    /// A refresh that failed or could not reach the provider is not transient
    /// feedback — it is an unresolved condition, and the Portfolio attention
    /// indicator reads it. Letting a timer clear it meant the app noticed a
    /// problem, mentioned it for ten seconds, and then looked healthy again
    /// while nothing had been fixed. Only a later successful refresh resolves
    /// it.
    func dismissTransientSuccessSummary() {
        guard Self.isTransientSuccessStatus(status) else { return }
        status = .idle
    }

    /// Whether a status is merely "here's what that refresh did", as opposed to
    /// an unresolved condition someone still has to act on.
    ///
    /// Pure so the rule can be tested without driving a whole refresh.
    nonisolated static func isTransientSuccessStatus(_ status: Status) -> Bool {
        switch status {
        case let .finished(summary):
            return !summary.wasCancelled
                && !summary.targetBuildFailed
                && !summary.providerUnreachable
                && summary.failed == 0
                && !summary.persistenceFailed
                && summary.gradedLookupMisses == 0
                && summary.gradedTransportFailures == 0
                && summary.reconciledDuplicateRecords == 0
        case .recentlyChecked:
            return true
        case .idle, .refreshing, .reconciling:
            return false
        }
    }

    func markRecentlyChecked() {
        guard !isRefreshing else { return }
        status = .recentlyChecked
    }

    /// Restores persisted budget/backoff state when the app becomes active,
    /// before the user spends a request discovering that today's allowance is
    /// gone.
    func updateFallbackAvailability(pending: Int) async {
        guard !isRefreshing else { return }
        guard pending > 0 else {
            fallbackStatus = .idle
            return
        }
        guard usesPriceFallback else {
            fallbackStatus = .disabled(pending: pending)
            return
        }
        guard PriceVendorCredentials.hasKey else {
            fallbackStatus = .unconfigured(pending: pending)
            return
        }

        let budget = await fallbackService.budgetSnapshot()
        if let retryAt = budget.retryAt {
            fallbackStatus = .rateLimited(pending: pending, retryAt: retryAt)
        } else if budget.remainingToday == 0 {
            fallbackStatus = .budgetReached(pending: pending, resetAt: budget.resetAt)
        } else if case .finished = fallbackStatus {
            // Preserve the useful result of the most recent run.
        } else {
            fallbackStatus = .available(remainingToday: budget.remainingToday)
        }
    }

    private var pendingFallbackWork: Int? {
        switch fallbackStatus {
        case let .budgetReached(pending, _), let .rateLimited(pending, _):
            return pending
        case .idle, .disabled, .unconfigured, .available, .running, .finished:
            return nil
        }
    }

    fileprivate nonisolated static func fetchBatch(
        _ printings: [PriceTarget.Printing],
        batchID: UUID,
        tcgdex: TCGdexService,
        scryfall: ScryfallService,
        importedResolver: ImportedCardResolver,
        pokemonFetchOverride: PriceRefreshPokemonFetchOverride? = nil
    ) async -> [PriceFetchOutcome] {
        let batchState = PerformanceSignpost.beginInterval(
            "priceRefresh.fetchBatch",
            id: PerformanceSignpost.makeID(),
            "batch=\(batchID.uuidString),count=\(printings.count)"
        )
        var batchOutcome = "empty"
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.fetchBatch",
                batchState,
                "batch=\(batchID.uuidString),outcome=\(batchOutcome)"
            )
        }
        guard !printings.isEmpty else { return [] }
        guard printings.count > 1,
              printings.allSatisfy({ $0.game == .magic && $0.importedIdentity == nil }) else {
            batchOutcome = "parallel"
            return await withTaskGroup(of: PriceFetchOutcome.self) { group in
                for printing in printings {
                    group.addTask {
                        await fetch(
                            printing,
                            batchID: batchID,
                            tcgdex: tcgdex,
                            scryfall: scryfall,
                            importedResolver: importedResolver,
                            pokemonFetchOverride: pokemonFetchOverride
                        )
                    }
                }
                var outcomes: [PriceFetchOutcome] = []
                for await outcome in group { outcomes.append(outcome) }
                return outcomes
            }
        }

        do {
            batchOutcome = "magic-batch"
            let cards = try await scryfall.fetchCards(
                identifiers: printings.map { ScryfallCardIdentifier(id: $0.printingID) }
            )
            let cardsByID = Dictionary(
                cards.map { ($0.id.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let classifications = classifyMagicBatchResponse(
                requestedIDs: printings.map(\.printingID),
                returnedIDs: Set(cardsByID.keys)
            )
            return zip(printings, classifications).map { printing, classification in
                // Scryfall omits `not_found` identifiers from `data`. An
                // omitted requested id is a provider data miss, never a
                // network outage: it must be `.failed` so it cannot trip the
                // unreachable diversion threshold.
                guard classification == .matched,
                      let card = cardsByID[printing.printingID.lowercased()],
                      card.id.caseInsensitiveCompare(printing.printingID) == .orderedSame else {
                    return PriceFetchOutcome(printing: printing, result: .failed)
                }
                return PriceFetchOutcome(printing: printing, result: .card(.magic(card)))
            }
        } catch is CancellationError {
            batchOutcome = "cancelled"
            return printings.map { PriceFetchOutcome(printing: $0, result: .cancelled) }
        } catch let error as URLError where error.code == .cancelled {
            batchOutcome = "cancelled"
            return printings.map { PriceFetchOutcome(printing: $0, result: .cancelled) }
        } catch let error as URLError where PriceFetchOutcome.isUnreachable(error) {
            batchOutcome = "unreachable"
            return printings.map { PriceFetchOutcome(printing: $0, result: .unreachable) }
        } catch let error as ScryfallError {
            let result: PriceFetchOutcome.Result
            switch error {
            case .badResponse, .endpointNotFound, .providerUnavailable, .rateLimited:
                result = .unreachable
            default:
                result = .failed
            }
            batchOutcome = switch result {
            case .unreachable: "unreachable"
            default: "failed"
            }
            return printings.map { PriceFetchOutcome(printing: $0, result: result) }
        } catch {
            batchOutcome = "failed"
            return printings.map { PriceFetchOutcome(printing: $0, result: .failed) }
        }
    }

    enum MagicBatchClassification: Equatable, Sendable {
        case matched
        case failed
    }

    nonisolated static func classifyMagicBatchResponse(
        requestedIDs: [String],
        returnedIDs: Set<String>
    ) -> [MagicBatchClassification] {
        let normalizedReturnedIDs = Set(returnedIDs.map { $0.lowercased() })
        return requestedIDs.map { id in
            normalizedReturnedIDs.contains(id.lowercased()) ? .matched : .failed
        }
    }

    fileprivate nonisolated static func fetch(
        _ printing: PriceTarget.Printing,
        batchID: UUID,
        tcgdex: TCGdexService,
        scryfall: ScryfallService,
        importedResolver: ImportedCardResolver,
        pokemonFetchOverride: PriceRefreshPokemonFetchOverride? = nil
    ) async -> PriceFetchOutcome {
        let fetchState = PerformanceSignpost.beginInterval(
            "priceRefresh.fetch",
            id: PerformanceSignpost.makeID(),
            "batch=\(batchID.uuidString),printing=\(printing.printingID)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "priceRefresh.fetch",
                fetchState,
                "batch=\(batchID.uuidString),printing=\(printing.printingID)"
            )
        }
        do {
            if printing.game == .pokemon,
               printing.importedIdentity == nil,
               let pokemonFetchOverride {
                let card = try await pokemonFetchOverride(printing)
                guard card.game == .pokemon,
                      card.providerID.caseInsensitiveCompare(printing.printingID) == .orderedSame else {
                    return PriceFetchOutcome(printing: printing, result: .failed)
                }
                return PriceFetchOutcome(printing: printing, result: .card(card))
            }
            if let identity = printing.importedIdentity {
                let card = try await importedResolver.resolve(
                    game: printing.game,
                    identity: identity,
                    tcgdex: tcgdex,
                    scryfall: scryfall
                )
                return PriceFetchOutcome(printing: printing, result: .card(card))
            }

            switch printing.game {
            case .pokemon:
                let card = try await tcgdex.fetchCard(
                    id: printing.printingID,
                    // Japanese-exclusive printings are 404 on the English
                    // endpoint, and the Japanese one is where both their
                    // identity and their Cardmarket price live. Fetching the
                    // wrong edition turns a priceable card into an unreachable
                    // one.
                    locale: CatalogIdentityNormalization.locale(forCatalogCardID: printing.printingID),
                    ignoringCache: true
                )
                // The direct provider id is the exact printing identity. Keep
                // this guard beside the fetch so a malformed or redirected
                // response cannot be used to value a different collection row.
                guard card.id.caseInsensitiveCompare(printing.printingID) == .orderedSame else {
                    return PriceFetchOutcome(printing: printing, result: .failed)
                }
                return PriceFetchOutcome(printing: printing, result: .card(.pokemon(card, setCode: printing.setCode)))
            case .magic:
                let card = try await scryfall.fetchCard(id: printing.printingID, ignoringCache: true)
                return PriceFetchOutcome(printing: printing, result: .card(.magic(card)))
            }
        } catch is CancellationError {
            return PriceFetchOutcome(printing: printing, result: .cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return PriceFetchOutcome(printing: printing, result: .cancelled)
        } catch let error as URLError where PriceFetchOutcome.isUnreachable(error) {
            // The provider could not be reached at all. Distinct from a card the
            // provider does not have: one is about the network, the other about
            // the data, and treating them alike makes an outage look like four
            // hundred missing cards.
            return PriceFetchOutcome(printing: printing, result: .unreachable)
        } catch let error as TCGdexError {
            // TCGdex wraps HTTP failures in its own error type. Treat its
            // server response as an outage so the stale target reaches JustTCG.
            if case .badResponse = error, printing.game == .pokemon {
                return PriceFetchOutcome(printing: printing, result: .unreachable)
            }
            return PriceFetchOutcome(printing: printing, result: .failed)
        } catch let error as ScryfallError {
            if printing.game == .magic {
                switch error {
                case .badResponse, .endpointNotFound, .providerUnavailable, .rateLimited:
                    return PriceFetchOutcome(printing: printing, result: .unreachable)
                default:
                    break
                }
            }
            return PriceFetchOutcome(printing: printing, result: .failed)
        } catch {
            return PriceFetchOutcome(printing: printing, result: .failed)
        }
    }
}

/// Resolves a CSV identity only when the user explicitly refreshes prices.
/// Directory requests are shared across the whole refresh, while each card is
/// fetched once and supplies both the verified identity and its current price.
private actor ImportedCardResolver {
    private var pokemonDirectoryTask: Task<[CatalogSetReference], Error>?
    private var magicDirectoryTask: Task<[CatalogSetReference], Error>?

    func resolve(
        game: CardGame,
        identity: ImportedPriceIdentity,
        tcgdex: TCGdexService,
        scryfall: ScryfallService
    ) async throws -> IdentifiedCard {
        let number = CatalogIdentityNormalization.localNumber(identity.cardNumber)
        guard !number.isEmpty else { throw TCGdexError.identityMismatch }

        switch game {
        case .pokemon:
            let sets = try await pokemonSets(using: tcgdex)
            let candidates = CatalogIdentityNormalization.matchingSets(
                named: identity.setName,
                cardName: identity.name,
                in: sets,
                game: game
            )
            for set in candidates {
                guard let card = try? await tcgdex.fetchCard(
                    setID: set.id,
                    localID: number,
                    ignoringCache: true
                ),
                      CatalogIdentityNormalization.namesMatch(
                        imported: identity.name,
                        catalog: card.name
                      ) else {
                    continue
                }
                let printedCode = PokemonCatalogRegistry.bundledSeed.printedCode(forProviderSetID: set.id)
                    ?? set.id.uppercased()
                return .pokemon(card, setCode: printedCode)
            }
            throw TCGdexError.identityMismatch

        case .magic:
            let sets = try await magicSets(using: scryfall)
            let candidates = CatalogIdentityNormalization.matchingSets(
                named: identity.setName,
                cardName: identity.name,
                in: sets,
                game: game
            )
            for set in candidates {
                guard let card = try? await scryfall.fetchCard(
                    setCode: set.id,
                    collectorNumber: number,
                    language: "en",
                    ignoringCache: true,
                    requiresScannableCard: false
                ), CatalogIdentityNormalization.namesMatch(
                    imported: identity.name,
                    catalog: card.name
                ) else {
                    continue
                }
                return .magic(card)
            }
            throw ScryfallError.identityMismatch
        }
    }

    private func pokemonSets(using service: TCGdexService) async throws -> [CatalogSetReference] {
        if let pokemonDirectoryTask { return try await pokemonDirectoryTask.value }
        let task = Task { try await service.fetchSetDirectory() }
        pokemonDirectoryTask = task
        do {
            return try await task.value
        } catch {
            pokemonDirectoryTask = nil
            throw error
        }
    }

    private func magicSets(using service: ScryfallService) async throws -> [CatalogSetReference] {
        if let magicDirectoryTask { return try await magicDirectoryTask.value }
        let task = Task { try await service.fetchSetDirectory() }
        magicDirectoryTask = task
        do {
            return try await task.value
        } catch {
            magicDirectoryTask = nil
            throw error
        }
    }

}
