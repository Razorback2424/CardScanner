import Foundation
import SwiftData

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
    private var artworkRowIDsByPriceKey: [String: [PersistentIdentifier]] = [:]
    private var identityRowIDsByPriceKey: [String: [PersistentIdentifier]] = [:]
    /// Materialised once when the fallback lane starts. The network callbacks
    /// may be per variant, but resolving the same persistent identifiers must
    /// not be per variant as well.
    private var artworkRowsByPriceKey: [String: [CollectedCard]] = [:]
    private var identityRowsByPriceKey: [String: [CollectedCard]] = [:]
    private var activeFallbackLastCommitAt = Date.distantPast
    private var activeFallbackStagedWrites = 0
    private var priceKeysWritten: Set<String> = []

    fileprivate func run(
        _ request: PriceRefreshRequest,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void
    ) async -> PriceRefreshWorkOutcome {
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

        guard !targets.isEmpty else { return .noTargets }
        return await performRefresh(
            targets,
            request: request,
            store: store,
            progress: progress
        )
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
        var priced = 0
        var failed = 0
        var latestSourceUpdate: Date?
        var checkedUnstampedProvider = false
        var changedPrices = false
        var persistenceFailed = false
        var gradedLookupMisses = 0
        var gradedTransportFailures = 0
        var reconciledDuplicateRecords = 0
        var stagedPriced = 0
        var stagedChangedPrices = false
        var stagedDuplicateRepairs = store.reconcileDuplicateRecords()
        var stagedWriteCount = 0
        var lastCommitAt = Date.now
        priceKeysWritten.removeAll()

        func stage(
            _ accepted: Bool,
            key: String? = nil,
            priced: Bool = false,
            changed: Bool = false
        ) {
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
        func commitStaged() async -> Bool {
            let saved = store.save()
            if saved {
                priced += stagedPriced
                changedPrices = changedPrices || stagedChangedPrices
                reconciledDuplicateRecords += stagedDuplicateRepairs
                let deltas = takePriceDeltas(from: store)
                if !deltas.isEmpty { await progress(.prices(deltas)) }
            } else {
                persistenceFailed = true
            }
            stagedPriced = 0
            stagedChangedPrices = false
            stagedDuplicateRepairs = 0
            stagedWriteCount = 0
            lastCommitAt = .now
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
        let importedCardIDsByProviderID = store.importedCardIDsByProviderID()
        var completed = 0
        var wasCancelled = false
        var fallbackSubjects: [PriceRefreshController.FallbackCandidate] = vendorNative.map {
            PriceRefreshController.FallbackCandidate(target: $0, card: nil)
        }
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
                group.addTask { [tcgdex, scryfall, importedResolver] in
                    await PriceRefreshController.fetchBatch(
                        batch,
                        tcgdex: tcgdex,
                        scryfall: scryfall,
                        importedResolver: importedResolver
                    )
                }
            }

            while let outcomes = await group.next() {
                for outcome in outcomes {
                    let printing = outcome.printing
                    let now = Date.now
                    switch outcome.result {
                    case let .card(card):
                        if printing.importedIdentity != nil {
                            for importedCardID in importedCardIDsByProviderID[printing.printingID] ?? [] {
                                guard let importedCard = modelContext.model(for: importedCardID) as? CollectedCard
                                else { continue }
                                importedCard.applyCatalogMetadata(from: card)
                                CollectionCatalogNormalizer.recordCatalogMetadataCheck(
                                    on: importedCard,
                                    at: now
                                )
                            }
                        }
                        if card.game == .magic {
                            checkedUnstampedProvider = true
                        }
                        for target in byPrinting[printing] ?? [] {
                            let lookup = CardPricing.price(
                                for: card,
                                variant: target.variantID.map(PhysicalVariant.resolving),
                                magicTreatments: card.magicTreatments(
                                    for: target.variantID.map(PhysicalVariant.resolving)
                                ),
                                pokemonPrintRun: target.pokemonPrintRun,
                                at: now
                            )
                            if PriceRefreshController.needsFallback(lookup) {
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
                        _ = await commitStaged()
                    }
                }

                if cursor < requestBatches.count,
                   !providerUnreachable,
                   !wasCancelled,
                   !Task.isCancelled {
                    let batch = requestBatches[cursor]
                    cursor += 1
                    group.addTask { [tcgdex, scryfall, importedResolver] in
                        await PriceRefreshController.fetchBatch(
                            batch,
                            tcgdex: tcgdex,
                            scryfall: scryfall,
                            importedResolver: importedResolver
                        )
                    }
                }
            }
        }

        await publishCatalogProgress(force: true)
        _ = await commitStaged()
        if wasCancelled || Task.isCancelled {
            return .cancelled
        }

        let fallbackResult = await runFallback(
            fallbackSubjects,
            usesPriceFallback: request.usesPriceFallback,
            progress: progress,
            store: store
        )
        if fallbackResult.priced > 0 {
            priced += fallbackResult.priced
            changedPrices = true
        }
        persistenceFailed = persistenceFailed || fallbackResult.persistenceFailed

        let gradedResult = await refreshGraded(
            targets,
            usesPriceFallback: request.usesPriceFallback,
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

        if Task.isCancelled { return .cancelled }
        let latest = latestSourceUpdate ?? previousLatest
        let finalPriceDeltas = takePriceDeltas(from: store)
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

    private func applyActiveBatch(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget]
    ) -> Bool {
        guard let store = refreshStore,
              let identities = identityStore,
              let identityIndex else { return false }
        let applied = PriceRefreshController.applyVendorBatchHit(
            card: card,
            variant: variant,
            owners: owners,
            store: store,
            identities: identities,
            artworkRowsByPriceKey: artworkRowsByPriceKey,
            identityRowsByPriceKey: identityRowsByPriceKey,
            identityIndex: identityIndex
        )
        if applied {
            activeFallbackStagedWrites += owners.count
            owners.forEach { rememberPriceKey($0.priceKey) }
        }
        return applied
    }

    private func recordActiveArtworkMiss(for owners: [MarketPriceTarget]) {
        PriceRefreshController.recordSealedArtworkMiss(
            for: owners,
            rowsByPriceKey: artworkRowsByPriceKey
        )
        activeFallbackStagedWrites += owners.count
    }

    @discardableResult
    private func saveActiveContext() -> Bool {
        guard let identities = identityStore, let store = refreshStore else { return false }
        // Both wrappers point at this actor's one context. Keep the existing
        // identity-then-price checkpoint order; changing it would widen the
        // already-known non-atomic window between synced and local stores.
        guard identities.save(index: identityIndex) else {
            refreshStore?.index?.reload()
            return false
        }
        return store.save()
    }

    /// The coordinator calls its checkpoint callback after a successful vendor
    /// batch. That callback is a durability opportunity, not a requirement to
    /// save every batch: keep the same wall-clock budget as the other lanes.
    private func checkpointActiveContextIfDue() -> Bool {
        let due = activeFallbackStagedWrites >= PriceRefreshController.stagedWriteCeiling
            || Date.now.timeIntervalSince(activeFallbackLastCommitAt)
                >= PriceRefreshController.checkpointBudget
        guard due else { return true }
        let saved = saveActiveContext()
        if saved {
            activeFallbackStagedWrites = 0
            activeFallbackLastCommitAt = .now
        }
        return saved
    }

    private func runFallback(
        _ candidates: [PriceRefreshController.FallbackCandidate],
        usesPriceFallback: Bool,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void,
        store: PriceStore
    ) async -> (priced: Int, persistenceFailed: Bool) {
        guard !candidates.isEmpty else {
            await progress(.fallbackIdle)
            return (0, false)
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
            return (0, false)
        }
        guard PriceVendorCredentials.hasKey else {
            await progress(.fallbackUnconfigured(pending: eligibleCandidates.count))
            return (0, false)
        }

        let (identities, identityIndex) = makeIdentityState()
        let artworkPending = PriceRefreshController.rowsMissingArtworkIDs(in: modelContext)
        let identityRows = PriceRefreshController.rowsByPriceKeyIDs(in: modelContext)
        artworkRowIDsByPriceKey = artworkPending
        identityRowIDsByPriceKey = identityRows
        artworkRowsByPriceKey = PriceRefreshController.materializedRows(
            from: artworkPending,
            in: modelContext
        )
        identityRowsByPriceKey = PriceRefreshController.materializedRows(
            from: identityRows,
            in: modelContext
        )
        activeFallbackLastCommitAt = .now
        activeFallbackStagedWrites = 0
        defer {
            artworkRowIDsByPriceKey = [:]
            identityRowIDsByPriceKey = [:]
            artworkRowsByPriceKey = [:]
            identityRowsByPriceKey = [:]
            activeFallbackLastCommitAt = .distantPast
            activeFallbackStagedWrites = 0
        }

        var priced = 0
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
            } else {
                persistenceFailed = true
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
            if Task.isCancelled { break }
            let useDelta = JustTCGSyncLedger()
                .checkpoint(game: game, apiVersion: JustTCGV1Client.apiVersion)
                .supportsDeltaSync
            let report = await coordinator.refresh(
                targets,
                game: game,
                lane: .background,
                useDelta: useDelta,
                apply: { [self] card, variant, owners in
                    await self.applyActiveBatch(card: card, variant: variant, owners: owners)
                },
                unmatched: { [self] owners in
                    await self.recordActiveArtworkMiss(for: owners)
                },
                checkpoint: { [self] in
                    await self.checkpointActiveContextIfDue()
                }
            )
            priced += report.variantsUpdated
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
            if Task.isCancelled { break }
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
        return (priced, persistenceFailed)
    }

    private func refreshGraded(
        _ targets: [PriceTarget],
        usesPriceFallback: Bool,
        store: PriceStore,
        progress: @escaping @Sendable (PriceRefreshProgress) async -> Void
    ) async -> (
        priced: Int,
        persistenceFailed: Bool,
        lookupMisses: Int,
        transportFailures: Int
    ) {
        let slabs = targets.filter {
            guard $0.itemKind == .gradedCard else { return false }
            if $0.marketVariantID != nil { return true }
            return $0.canResolveGradedVariant
        }
        guard !slabs.isEmpty, usesPriceFallback, PriceVendorCredentials.hasKey else {
            return (0, false, 0, 0)
        }

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

        // Binding is a collection-row mutation, but it happens in the same
        // model context as the price write. Keeping these maps local avoids a
        // fetch per slab while a response is being matched, and lets a newly
        // bound row use its canonical vendor price key immediately.
        let gradedRows: [CollectedCard]
        do {
            gradedRows = try modelContext.fetch(FetchDescriptor<CollectedCard>())
        } catch {
            // A graded response must never be written against a fabricated
            // empty ownership table. Keep the prior state and report the pass
            // as incomplete so a later refresh can retry.
            return (0, true, 0, 0)
        }
        let rowsByCollectionKey = Dictionary(
            grouping: gradedRows.filter { $0.itemKind == .gradedCard },
            by: \.collectionKey
        )
        var rowsByVariantID = Dictionary(
            grouping: gradedRows.compactMap { row -> (String, CollectedCard)? in
                guard row.itemKind == .gradedCard,
                      let variantID = row.justTCGVariantID else { return nil }
                return (variantID, row)
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

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

        func row(for target: PriceTarget) -> CollectedCard? {
            if let handle = target.marketVariantID,
               let existing = rowsByVariantID[handle]?.first {
                return existing
            }
            return rowsByCollectionKey[target.printingID]?.first
        }

        func bind(
            _ variant: GradedVariant,
            to target: PriceTarget
        ) -> CollectedCard? {
            guard target.marketVariantID == nil else { return row(for: target) }
            guard let card = row(for: target) else { return nil }
            card.justTCGVariantID = variant.id
            card.justTCGCardID = variant.cardID ?? card.justTCGCardID
            card.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
            card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
            rowsByVariantID[variant.id, default: []].append(card)
            return card
        }

        func checkpoint(force: Bool = false) async {
            let due = force
                || stagedWriteCount >= PriceRefreshController.stagedWriteCeiling
                || Date.now.timeIntervalSince(lastCommitAt)
                    >= PriceRefreshController.checkpointBudget
            guard due, stagedWriteCount > 0 else { return }
            if store.save() {
                priced += stagedPriced
                stagedPriced = 0
                stagedWriteCount = 0
                lastCommitAt = .now
                let deltas = takePriceDeltas(from: store)
                if !deltas.isEmpty { await progress(.prices(deltas)) }
            } else {
                persistenceFailed = true
            }
        }

        func stampUnsupported(_ target: PriceTarget) {
            let accepted = store.recordUnsupportedProvider(
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

        for (_, group) in byCard.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { break }
            guard let identity = group.first?.gradedIdentity,
                  let game = group.first?.game else { continue }
            let variants: [GradedVariant]
            do {
                let lookup = try await client.lookup(
                    identity: identity,
                    game: game,
                    companies: Set(group.compactMap(\.gradingCompany)),
                    grades: Set(group.compactMap(\.grade)),
                    lane: .background
                )
                switch lookup {
                case let .matched(values):
                    variants = values
                case .cardFoundWithoutGradedVariants, .noProductMatch:
                    lookupMisses += group.count
                    for target in group where target.marketVariantID == nil {
                        stampUnsupported(target)
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
                let variant: GradedVariant?
                if let handle = target.marketVariantID {
                    variant = byVariantID[handle]
                } else {
                    variant = selectGradedVariant(from: variants, target: target)
                }
                guard let variant else {
                    lookupMisses += 1
                    if target.marketVariantID == nil {
                        stampUnsupported(target)
                    }
                    continue
                }

                let owner = bind(variant, to: target)
                let printingID = owner?.priceStorageID
                    ?? "justtcg:\(JustTCGV2GradedClient.apiVersion):\(variant.id)"
                let lookup: PriceLookup = if let amount = variant.marketPriceUSD {
                    .price(
                        NormalizedPrice(
                            unitMarketPriceUSD: amount,
                            currencyCode: "USD",
                            source: .justTCG,
                            sourceVariantID: variant.id,
                            sourceUpdatedAt: variant.updatedAt,
                            fetchedAt: .now
                        )
                    )
                } else {
                    .unavailable(.justTCG)
                }
                let accepted = store.store(
                    lookup,
                    game: target.game,
                    printingID: printingID,
                    variantID: target.variantID,
                    marketVariantID: variant.id,
                    treatmentIDs: target.magicTreatmentIDsRaw
                )
                let canonicalKey = PriceRecord.key(
                    game: target.game,
                    printingID: printingID,
                    variantID: target.variantID,
                    treatmentIDs: target.magicTreatmentIDsRaw
                )
                if let record = store.record(forKey: canonicalKey) {
                    record.marketVariantID = variant.id
                    record.itemKindRaw = CollectionItemKind.gradedCard.rawValue
                }
                if accepted {
                    if variant.marketPriceUSD != nil { stagedPriced += 1 }
                    stagedWriteCount += 1
                    rememberPriceKey(canonicalKey)
                }
                else { persistenceFailed = true }
            }
            await checkpoint()
        }
        await checkpoint(force: true)
        return (priced, persistenceFailed, lookupMisses, transportFailures)
    }
}

/// One priced thing: a printing plus the physical variant the user owns.
struct PriceTarget: Hashable, Identifiable, Sendable {
    let game: CardGame
    let printingID: String
    let catalogPrintingID: String?
    let setCode: String
    let variantID: String?
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
}

struct PriceRefreshResult: Sendable, Equatable {
    let didRun: Bool
    let targetBuildFailed: Bool
}

fileprivate enum PriceRefreshProgress: Sendable {
    case catalog(completed: Int, total: Int)
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

fileprivate struct PriceRefreshWorkResult: Sendable {
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
    let priceDeltas: [PriceDelta]
}

fileprivate enum PriceRefreshWorkOutcome: Sendable {
    case noTargets
    case targetBuildFailed
    case cancelled
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
    private var lastProgressPublicationAt: Date?
    private var lastPublishedProgressPercent: Int?
    private weak var registeredPortfolio: PortfolioEngine?
    private weak var registeredPriceSnapshotStore: PriceSnapshotStore?
    private weak var registeredRevisionStore: StoreRevisionStore?
    /// A caller that arrives during a pass must not lose its newer targets.
    /// Keep a trailing request; the actor rebuilds its targets from the live
    /// context when it reaches that request rather than retaining model rows.
    private var pendingRefreshRequests: [PendingRefreshRequest] = []

    private struct PendingRefreshRequest {
        var request: PriceRefreshRequest
    }

    private var isRefreshing: Bool {
        if case .refreshing = status { return true }
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
                gradedLookupMisses: result.gradedLookupMisses,
                gradedTransportFailures: result.gradedTransportFailures
            )
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
            if target.lastFailureReasonRaw == PricingDiagnosticReason.noSupportedProvider.rawValue {
                let isStillUnsupported = target.itemKind == .gradedCard
                    && target.marketVariantID == nil
                if !isStillUnsupported { return true }
                // Manual refreshes are an explicit request to re-evaluate a
                // capability stamp. Automatic/background passes keep the long
                // retry interval so unsupported rows cannot create churn.
                if forceUnsupportedRetry { return true }
                guard usesPriceFallback else { return false }
                return target.lastCheckedAt.map {
                    now.timeIntervalSince($0) >= noSupportedProviderRetryInterval
                } ?? true
            }
            // A previous "unavailable" result is not permanent. Manual refreshes
            // must always be able to revisit cards that still have no price.
            if !target.hasPrice { return true }
            if target.needsArtwork { return true }

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

    /// A non-USD catalog observation remains useful when fallback is off, but
    /// becomes unfinished the moment the user opts into a USD fallback.
    nonisolated static func hasFinishedPrice(
        amount: Double?,
        currencyCode: String?,
        usesFallback: Bool
    ) -> Bool {
        guard amount != nil else { return false }
        return !usesFallback
            || currencyCode?.caseInsensitiveCompare("USD") == .orderedSame
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
        container: ModelContainer
    ) async -> PriceRefreshResult {
        if let activeRefresh {
            enqueuePending(request)
            return await activeRefresh.value
        }

        // The active task represents the whole queue, not just the first pass.
        // A caller that joins after the first pass has completed must remain
        // suspended until its trailing targets have been processed too.
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return PriceRefreshResult(didRun: false, targetBuildFailed: false)
            }
            return await self.runRefreshQueue(startingWith: request, container: container)
        }
        activeRefresh = task
        let result = await task.value
        if let pending = pendingFallbackWork {
            await updateFallbackAvailability(pending: pending)
        }
        return result
    }

    /// Stops the pass in progress. The only legitimate reason is that the work
    /// has genuinely been abandoned — never that its own writes changed the
    /// data some view is keyed on.
    func cancelRefresh() {
        activeRefresh?.cancel()
        pendingRefreshRequests.removeAll()
    }

    private func runRefreshQueue(
        startingWith initialRequest: PriceRefreshRequest,
        container: ModelContainer
    ) async -> PriceRefreshResult {
        // The active marker is cleared in the same actor turn as the final
        // empty-queue check. A late caller can therefore either join a live
        // queue or start a new one; it cannot enqueue work after this queue has
        // already decided there is nothing left to process.
        registeredPortfolio?.beginPriceRefresh()
        lastProgressPublicationAt = nil
        lastPublishedProgressPercent = nil
        defer {
            // The replay gate is settled for every terminal outcome, including
            // cancellation and target-build failure. It is intentionally tied
            // to the controller's queue, not to the happy-path summary.
            registeredPortfolio?.endPriceRefresh(context: container.mainContext)
            activeRefresh = nil
        }
        let worker = PriceRefreshModelActor(modelContainer: container)
        let relay = PriceRefreshProgressRelay { [weak self] value in
            self?.consume(value)
        }
        let progress: @Sendable (PriceRefreshProgress) async -> Void = { value in
            await relay.offer(value)
        }
        var request = initialRequest
        var didRun = false
        var targetBuildFailed = false
        while true {
            let outcome = await worker.run(request, progress: progress)
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
            case .cancelled:
                if let fingerprint = await worker.priceValuesFingerprint() {
                    registeredRevisionStore?.expectPriceValuesFingerprint(fingerprint)
                }
                // Cancellation can happen after one or more durable
                // checkpoints. The live delta channel may have been partial;
                // finish with the same authoritative read used by success so
                // the snapshot cannot remain stale until an unrelated edit.
                await registeredPriceSnapshotStore?.rebuild(container: container)
                status = .idle
                return PriceRefreshResult(
                    didRun: didRun,
                    targetBuildFailed: targetBuildFailed
                )
            case let .completed(result):
                didRun = true
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
                if let fingerprint = await worker.priceValuesFingerprint() {
                    registeredRevisionStore?.expectPriceValuesFingerprint(fingerprint)
                }
                await registeredPriceSnapshotStore?.rebuild(container: container)
                status = .idle
                return PriceRefreshResult(
                    didRun: didRun,
                    targetBuildFailed: targetBuildFailed
                )
            }
            guard let pending = takePendingRefresh() else { break }
            request = pending.request
        }
        return PriceRefreshResult(
            didRun: didRun,
            targetBuildFailed: targetBuildFailed
        )
    }

    private func enqueuePending(_ request: PriceRefreshRequest) {
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
                    || request.markRecentlyCheckedIfEmpty
            )
        } else {
            pendingRefreshRequests.append(PendingRefreshRequest(request: request))
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
    nonisolated static func needsFallback(_ lookup: PriceLookup) -> Bool {
        PriceFallbackQuoteResolver.needsFallback(lookup)
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
    /// Collection rows with no picture yet, keyed by the price key a batched
    /// response writes back to.
    nonisolated fileprivate static func rowsMissingArtworkIDs(
        in context: ModelContext
    ) -> [String: [PersistentIdentifier]] {
        let rows = (try? context.fetch(
            FetchDescriptor<CollectedCard>(predicate: #Predicate { $0.imageURL == nil })
        )) ?? []
        return rows.reduce(into: [String: [PersistentIdentifier]]()) { result, row in
            result[row.priceKey, default: []].append(row.persistentModelID)
        }
    }

    nonisolated fileprivate static func rowsByPriceKeyIDs(
        in context: ModelContext
    ) -> [String: [PersistentIdentifier]] {
        let rows = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return rows.reduce(into: [String: [PersistentIdentifier]]()) { result, row in
            result[row.priceKey, default: []].append(row.persistentModelID)
        }
    }

    nonisolated fileprivate static func rows(
        for ids: [PersistentIdentifier],
        in context: ModelContext
    ) -> [CollectedCard] {
        ids.compactMap { context.model(for: $0) as? CollectedCard }
    }

    nonisolated fileprivate static func materializedRows(
        from index: [String: [PersistentIdentifier]],
        in context: ModelContext
    ) -> [String: [CollectedCard]] {
        index.mapValues { rows(for: $0, in: context) }
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

    nonisolated fileprivate static func recordSealedArtworkMiss(
        for owners: [MarketPriceTarget],
        rowIDsByPriceKey: [String: [PersistentIdentifier]],
        context: ModelContext,
        checkedAt: Date = .now
    ) {
        recordSealedArtworkMiss(
            for: owners,
            rowsByPriceKey: materializedRows(from: rowIDsByPriceKey, in: context),
            checkedAt: checkedAt
        )
    }

    /// One matched vendor response, applied in dependency order. Identity and
    /// artwork deliberately happen before the optional price so a null market
    /// amount cannot discard valid product metadata.
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
        // This callback is a second line of defence after the coordinator's
        // treatment-aware owner grouping. A response without a direct product
        // handle must never be written to a treatment-qualified Magic key, even
        // if a future caller accidentally supplies a mixed owner array.
        guard owners.allSatisfy({ !$0.isTreatmentQualified || $0.hasDirectVendorHandle }) else {
            return false
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
            guard identityStored else { return false }
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

        guard let amount = variant.marketPriceUSD else { return true }
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
    }

    @discardableResult
    nonisolated fileprivate static func applyVendorBatchHit(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        artworkRowIDsByPriceKey: [String: [PersistentIdentifier]],
        identityRowIDsByPriceKey: [String: [PersistentIdentifier]],
        context: ModelContext,
        identityIndex: ProductIdentityIndex? = nil,
        fetchedAt: Date = .now
    ) -> Bool {
        // The IDs were captured before the network await. Re-fetching here
        // makes deletion, rollback, or a sync merge during that await harmless.
        return applyVendorBatchHit(
            card: card,
            variant: variant,
            owners: owners,
            store: store,
            identities: identities,
            artworkRowsByPriceKey: materializedRows(
                from: artworkRowIDsByPriceKey,
                in: context
            ),
            identityRowsByPriceKey: materializedRows(
                from: identityRowIDsByPriceKey,
                in: context
            ),
            identityIndex: identityIndex,
            fetchedAt: fetchedAt
        )
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

    func dismissSummary() {
        switch status {
        case .finished, .recentlyChecked:
            status = .idle
        case .idle, .refreshing:
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
            return !summary.targetBuildFailed
                && !summary.providerUnreachable
                && summary.failed == 0
                && !summary.persistenceFailed
                && summary.gradedLookupMisses == 0
                && summary.gradedTransportFailures == 0
                && summary.reconciledDuplicateRecords == 0
        case .recentlyChecked:
            return true
        case .idle, .refreshing:
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
        tcgdex: TCGdexService,
        scryfall: ScryfallService,
        importedResolver: ImportedCardResolver
    ) async -> [PriceFetchOutcome] {
        guard !printings.isEmpty else { return [] }
        guard printings.count > 1,
              printings.allSatisfy({ $0.game == .magic && $0.importedIdentity == nil }) else {
            return await withTaskGroup(of: PriceFetchOutcome.self) { group in
                for printing in printings {
                    group.addTask {
                        await fetch(
                            printing,
                            tcgdex: tcgdex,
                            scryfall: scryfall,
                            importedResolver: importedResolver
                        )
                    }
                }
                var outcomes: [PriceFetchOutcome] = []
                for await outcome in group { outcomes.append(outcome) }
                return outcomes
            }
        }

        do {
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
            return printings.map { PriceFetchOutcome(printing: $0, result: .cancelled) }
        } catch let error as URLError where error.code == .cancelled {
            return printings.map { PriceFetchOutcome(printing: $0, result: .cancelled) }
        } catch let error as URLError where PriceFetchOutcome.isUnreachable(error) {
            return printings.map { PriceFetchOutcome(printing: $0, result: .unreachable) }
        } catch let error as ScryfallError {
            let result: PriceFetchOutcome.Result
            switch error {
            case .badResponse, .endpointNotFound, .providerUnavailable, .rateLimited:
                result = .unreachable
            default:
                result = .failed
            }
            return printings.map { PriceFetchOutcome(printing: $0, result: result) }
        } catch {
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
        tcgdex: TCGdexService,
        scryfall: ScryfallService,
        importedResolver: ImportedCardResolver
    ) async -> PriceFetchOutcome {
        do {
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
                let printedCode = SetCodeMap.definitions.values.first {
                    $0.tcgdexSetID.caseInsensitiveCompare(set.id) == .orderedSame
                }?.printedCode ?? set.id.uppercased()
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
