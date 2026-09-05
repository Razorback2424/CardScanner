import Foundation
import SwiftData

/// The result of one catalog fetch during a refresh.
///
/// The outcome distinguishes an ordinary provider failure from cancellation so
/// leaving the collection cannot turn an abandoned request into a recorded check.
/// File scope rather than nested, so it cannot inherit the controller's
/// main-actor isolation.
private struct PriceFetchOutcome: Sendable {
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
    /// Treatment ids are part of the price identity but not of the vendor's
    /// finish lookup. A provider response may serve several treatment-aware
    /// records; each record is still written under its own exact key.
    var magicTreatmentIDsRaw: [String] = []

    /// Whether this row exists only in the market vendor's catalogue.
    ///
    /// A booster box has no TCGdex or Scryfall identity by construction, so
    /// asking those providers about one spends a request to learn nothing and
    /// then stamps a price failure that reads as though something went wrong.
    /// These go straight to the vendor, keyed by the handle the row carries.
    ///
    /// Sealed products have no external catalog identity. Graded slabs are
    /// vendor-native only after their stored variant handle is available; an
    /// imported slab without that handle is not queryable by either provider
    /// and is classified as unsupported before the catalog pass. Raw cards are
    /// intentionally not vendor-native: a catalog response may still provide
    /// a free price or the identity needed for a later fallback.
    var isVendorNative: Bool {
        itemKind == .sealedProduct
            || (itemKind == .gradedCard && marketVariantID != nil)
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
    }

    enum Status: Equatable {
        case idle
        case recentlyChecked
        case refreshing(completed: Int, total: Int)
        case finished(Summary)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var fallbackStatus: FallbackStatus = .idle

    private let tcgdex = TCGdexService()
    private let scryfall = ScryfallService()
    private let importedResolver = ImportedCardResolver()
    private let fallbackService = ProductPriceService.shared
    /// One transport for every JustTCG client, so pacing and the request ledger
    /// are shared rather than each client keeping its own idea of the allowance.
    private let sharedTransport = JustTCGTransport.shared

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
    private static let maxConcurrentRequests = 4

    /// A short run of in-flight requests failing to reach the provider is taken
    /// as the provider being down. Small on purpose: the cost of being wrong is
    /// one retry, and the cost of being slow is minutes of timeouts.
    private static let unreachableThreshold = maxConcurrentRequests

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
    private var activeRefresh: Task<Void, Never>?
    /// A caller that arrives during a pass must not lose its newer targets.
    /// Keep them as a trailing queue; the owner drains it before exposing the
    /// refresh as finished.
    private var pendingRefreshBatches: [PendingRefreshBatch] = []

    private struct PendingRefreshBatch {
        var targets: [PriceTarget]
    }

    private var isRefreshing: Bool {
        if case .refreshing = status { return true }
        return false
    }

    /// Targets that a refresh should bother with.
    nonisolated static func staleTargets(
        from targets: [PriceTarget],
        now: Date = .now,
        usesPriceFallback: Bool = true
    ) -> [PriceTarget] {
        targets.filter { target in
            if target.lastFailureReasonRaw == PricingDiagnosticReason.noSupportedProvider.rawValue {
                let isStillUnsupported = target.isTreatmentQualified
                    || (target.itemKind == .gradedCard && target.marketVariantID == nil)
                if !isStillUnsupported { return true }
                // A capability stamp is only actionable while the optional
                // provider is enabled. If the setting changes, the next
                // enabled pass must be allowed to revisit it immediately.
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

    /// - Parameter targets: already in display order, so whatever the user is
    ///   looking at becomes fresh first.
    ///
    /// A second caller arriving while a pass is already running waits for that
    /// pass and queues any targets it added. Returning the second caller's
    /// targets was a silent no-op: pulling to refresh during the automatic
    /// startup check looked like a button that did nothing.
    func refresh(_ targets: [PriceTarget], store: PriceStore) async {
        if let activeRefresh {
            enqueuePending(targets)
            await activeRefresh.value
            return
        }
        guard !targets.isEmpty else { return }

        // The active task represents the whole queue, not just the first pass.
        // A caller that joins after the first pass has completed must remain
        // suspended until its trailing targets have been processed too.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefreshQueue(startingWith: targets, store: store)
        }
        activeRefresh = task
        await task.value
        if let pending = pendingFallbackWork {
            await updateFallbackAvailability(pending: pending)
        }
    }

    /// Stops the pass in progress. The only legitimate reason is that the work
    /// has genuinely been abandoned — never that its own writes changed the
    /// data some view is keyed on.
    func cancelRefresh() {
        activeRefresh?.cancel()
        pendingRefreshBatches.removeAll()
    }

    private func runRefreshQueue(
        startingWith initialTargets: [PriceTarget],
        store initialStore: PriceStore
    ) async {
        // The active marker is cleared in the same actor turn as the final
        // empty-queue check. A late caller can therefore either join a live
        // queue or start a new one; it cannot enqueue work after this queue has
        // already decided there is nothing left to process.
        defer { activeRefresh = nil }
        var targets = initialTargets
        // A refresh is a long-lived workflow. Its context is deliberately
        // independent from the UI/main context so a collection mutation or
        // import rollback cannot discard its staged price evidence, and its
        // checkpoints cannot commit unrelated UI work.
        let refreshContext = ModelContext(initialStore.context.container)
        let store = PriceStore(context: refreshContext)
        while !targets.isEmpty {
            await performRefresh(targets, store: store)

            guard !Task.isCancelled else { return }
            guard let pending = takePendingRefresh() else { break }
            targets = pending.targets
        }
    }

    private func enqueuePending(_ targets: [PriceTarget]) {
        guard !targets.isEmpty else { return }
        if let index = pendingRefreshBatches.indices.last {
            var byID: [String: PriceTarget] = [:]
            var order: [String] = []
            for target in pendingRefreshBatches[index].targets {
                if byID[target.id] == nil { order.append(target.id) }
                byID[target.id] = target
            }
            for target in targets {
                if byID[target.id] == nil { order.append(target.id) }
                byID[target.id] = target
            }
            pendingRefreshBatches[index].targets = order.compactMap { byID[$0] }
        } else {
            pendingRefreshBatches.append(
                PendingRefreshBatch(
                    targets: targets
                )
            )
        }
    }

    private func takePendingRefresh() -> PendingRefreshBatch? {
        guard !pendingRefreshBatches.isEmpty else { return nil }
        return pendingRefreshBatches.removeFirst()
    }

    private func performRefresh(_ targets: [PriceTarget], store: PriceStore) async {
        guard !isRefreshing, !targets.isEmpty else { return }

        // A sealed box or a graded slab has no catalog identity to look up, so
        // it never enters the catalog pass. It carries the vendor's own variant
        // handle instead and goes straight to the batched stage below.
        let unsupported = targets.filter {
            $0.isTreatmentQualified
                || ($0.itemKind == .gradedCard && $0.marketVariantID == nil)
        }
        for target in unsupported {
            store.recordUnsupportedProvider(
                game: target.game,
                printingID: target.printingID,
                variantID: target.variantID,
                treatmentIDs: target.magicTreatmentIDsRaw
            )
        }
        // Partitioned by instrument id rather than by `Array.contains`. A
        // synthesized `PriceTarget ==` compares two dozen fields including
        // arrays, so the linear membership test was quadratic over the whole
        // collection before a single request went out.
        let unsupportedIDs = Set(unsupported.map(\.id))
        let supportedTargets = targets.filter { !unsupportedIDs.contains($0.id) }
        let vendorNative = supportedTargets.filter(\.isVendorNative)

        // Group by printing: every variant of one card shares a single response.
        var order: [PriceTarget.Printing] = []
        var byPrinting: [PriceTarget.Printing: [PriceTarget]] = [:]
        for target in supportedTargets where !target.isVendorNative {
            if byPrinting[target.printing] == nil { order.append(target.printing) }
            byPrinting[target.printing, default: []].append(target)
        }

        let previousLatest = latestKnownSourceUpdate(in: store)
        let importedCardIDsByProviderID = store.importedCardIDsByProviderID()
        var completed = 0
        var priced = 0
        var failed = 0
        var latestSourceUpdate: Date?
        var checkedUnstampedProvider = false
        var changedPrices = false
        var wasCancelled = false
        /// Collected during the catalog pass, resolved after it. Running the
        /// fallback inline would interleave a paced, rate-limited vendor with
        /// the unmetered catalog and slow the whole refresh to the vendor's
        /// speed.
        var fallbackSubjects: [FallbackCandidate] = vendorNative.map {
            FallbackCandidate(target: $0, card: nil)
        }
        /// Consecutive responses where the provider could not be reached at all.
        var consecutiveUnreachable = 0
        var providerUnreachable = false
        status = .refreshing(completed: 0, total: order.count)

        var cursor = 0
        await withTaskGroup(of: PriceFetchOutcome.self) { group in
            let initial = min(Self.maxConcurrentRequests, order.count)
            for _ in 0..<initial {
                let printing = order[cursor]
                cursor += 1
                group.addTask { [tcgdex, scryfall, importedResolver] in
                    await Self.fetch(
                        printing,
                        tcgdex: tcgdex,
                        scryfall: scryfall,
                        importedResolver: importedResolver
                    )
                }
            }

            while let outcome = await group.next() {
                let printing = outcome.printing
                let now = Date.now
                switch outcome.result {
                case let .card(card):
                    if printing.importedIdentity != nil {
                        for importedCardID in importedCardIDsByProviderID[printing.printingID] ?? [] {
                        guard let importedCard = store.context.model(for: importedCardID) as? CollectedCard
                        else { continue }
                        importedCard.applyCatalogMetadata(from: card)
                        CollectionCatalogNormalizer.recordCatalogMetadataCheck(
                            on: importedCard,
                            at: now
                        )
                        }
                    }
                    if card.game == .magic {
                        // Scryfall never supplies a provider-side price timestamp,
                        // including when its price object contains no usable value.
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
                        // The catalog answered, but not in a way that finishes
                        // the job: either it has no price for this finish, or it
                        // has one in a currency the collection cannot total.
                        // Both are handed to the fallback, which quotes USD.
                        // Whatever is stored below stays put if the fallback
                        // finds nothing, so Cardmarket remains the last resort
                        // rather than being dropped.
                        if Self.needsFallback(lookup) {
                            fallbackSubjects.append(
                                FallbackCandidate(target: target, card: card)
                            )
                        }
                        if case let .price(price) = lookup {
                            priced += 1
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
                        if previousAmount != newAmount { changedPrices = true }

                        store.store(
                            lookup,
                            game: target.game,
                            printingID: target.printingID,
                            variantID: target.variantID,
                            at: now,
                            treatmentIDs: target.magicTreatmentIDsRaw
                        )
                    }

                case .failed:
                    // Nothing is overwritten. The old price keeps its old age.
                    //
                    // `catalogMetadataCheckedAt` is deliberately *not* stamped
                    // here. It records when the catalog normalizer last tried to
                    // resolve this card's identity, and the normalizer uses it to
                    // decide when to try again. Writing it on a price failure
                    // starved exactly the cards that needed normalizing most: a
                    // card with no identity cannot be priced, the failed price
                    // check refreshed the timestamp, the normalizer then skipped
                    // the card as recently-checked, and the loop repeated forever.
                    // A price failure is already recorded on the price record.
                    failed += 1
                    for target in byPrinting[printing] ?? [] {
                        store.recordFailure(
                            game: target.game,
                            printingID: target.printingID,
                            variantID: target.variantID,
                            at: now,
                            treatmentIDs: target.magicTreatmentIDsRaw
                        )
                        // A card the catalog could not even identify is the
                        // strongest fallback candidate there is — it has no
                        // price and no artwork today. The row's persisted
                        // fallback identity is all the vendor needs.
                        fallbackSubjects.append(
                            FallbackCandidate(target: target, card: nil)
                        )
                    }

                case .unreachable:
                    // Every card in the queue is about to fail the same way, one
                    // short timeout at a time. Four hundred of those at a
                    // concurrency of four is thirteen minutes of watching a
                    // progress bar crawl before the fallback even starts.
                    //
                    // So a short run of unreachable responses ends the catalog
                    // pass. Nothing is recorded as a price failure: these cards
                    // were never actually asked about, and stamping them would
                    // misreport an outage as four hundred missing cards.
                    fallbackSubjects.append(contentsOf: (byPrinting[printing] ?? []).map {
                        FallbackCandidate(target: $0, card: nil)
                    })
                    consecutiveUnreachable += 1
                    // Latched on `providerUnreachable`, not just on the
                    // threshold. `cursor` stops advancing the moment the outage
                    // is declared, so every one of the still in-flight replies
                    // would otherwise sweep in the *same* untouched tail again
                    // — up to `maxConcurrentRequests` copies of the remaining
                    // queue, each costing a paid identity request below.
                    if !providerUnreachable, consecutiveUnreachable >= Self.unreachableThreshold {
                        providerUnreachable = true
                        // The remaining queue has not been asked yet. Include it
                        // in this fallback pass instead of waiting for another
                        // refresh to discover each stale card.
                        for pending in order.dropFirst(cursor) {
                            fallbackSubjects.append(contentsOf: (byPrinting[pending] ?? []).map {
                                FallbackCandidate(target: $0, card: nil)
                            })
                        }
                    }

                case .cancelled:
                    wasCancelled = true
                }

                switch outcome.result {
                case .card, .failed:
                    // The provider answered, even if that answer was not usable
                    // for this row. Do not turn a few missing cards into an
                    // outage declaration.
                    consecutiveUnreachable = 0
                case .unreachable, .cancelled:
                    break
                }
                completed += 1
                status = .refreshing(completed: completed, total: order.count)

                // Checkpoint periodically, matching the fallback stage's own
                // interval. A pass over a few hundred cards is minutes long,
                // and holding all of it unsaved meant any unrelated
                // `ModelContext.rollback` in that window — a scan or an import
                // that failed and took the context back — discarded the whole
                // refresh along with itself.
                //
                // Deliberately not once per printing. Every save republishes
                // the collection's `@Query`s, and each republish costs a full
                // pass over the observed tables; ten printings keeps the
                // exposure window to seconds while leaving that churn an order
                // of magnitude smaller.
                if completed.isMultiple(of: Self.catalogCheckpointInterval) {
                    store.save()
                }

                if cursor < order.count, !providerUnreachable, !wasCancelled, !Task.isCancelled {
                    let next = order[cursor]
                    cursor += 1
                    group.addTask { [tcgdex, scryfall, importedResolver] in
                        await Self.fetch(
                            next,
                            tcgdex: tcgdex,
                            scryfall: scryfall,
                            importedResolver: importedResolver
                        )
                    }
                }
            }
        }

        store.save()

        if wasCancelled || Task.isCancelled {
            status = .idle
            return
        }

        // Second stage. Only what the catalog could not finish, and only when
        // the user has opted in and supplied a key.
        let fallbackPriced = await runFallback(fallbackSubjects, store: store)
        if fallbackPriced > 0 {
            priced += fallbackPriced
            changedPrices = true
            store.save()
        }

        // Graded slabs, which neither the catalog nor the v1 batch can price.
        let gradedPriced = await refreshGraded(targets, store: store)
        if gradedPriced > 0 {
            priced += gradedPriced
            changedPrices = true
            store.save()
        }

        if Task.isCancelled {
            status = .idle
            return
        }

        let checkedAt = Date.now
        status = .finished(
            Summary(
                checkedAt: checkedAt,
                priced: priced,
                failed: failed,
                latestSourceUpdate: latestSourceUpdate ?? previousLatest,
                checkedUnstampedProvider: checkedUnstampedProvider,
                changedPrices: changedPrices,
                foundNothingNewer: !isNewer(latestSourceUpdate, than: previousLatest),
                providerUnreachable: providerUnreachable
            )
        )
    }

    // MARK: - Fallback stage

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
    private struct FallbackCandidate {
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
        /// What is left is the marketplace id, and Scryfall publishes it only
        /// for ordinary printings. Art cards and tokens — precisely the
        /// fall-through population — come back `null`. Those have no keyed
        /// route at all and must resolve by search once, after which the stored
        /// variant handle makes every later refresh a batch.
        var externalLookups: [JustTCGBatchLookup] {
            guard !target.isTreatmentQualified else { return [] }
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
    private static func collapsingDuplicates(
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
    /// Returns how many cards it managed to price. Anything it cannot answer is
    /// left exactly as the catalog left it — including a Cardmarket euro price,
    /// which stays as the last resort rather than being cleared.
    private func runFallback(_ candidates: [FallbackCandidate], store: PriceStore) async -> Int {
        // WotC editions used to be excluded outright, because the vendor names
        // them in its own vocabulary and an unverified mapping would have
        // attached an Unlimited price to a 1st Edition card. That vocabulary is
        // now mapped from live responses — see `ProductEdition` — so these are
        // priced like anything else, and an edition the vendor does not
        // distinguish simply finds no matching printing and stays unpriced.
        guard !candidates.isEmpty else {
            fallbackStatus = .idle
            return 0
        }
        // One row can reach this pass by more than one route — its catalog
        // request failed *and* it was swept in when the provider was declared
        // unreachable. The batched stage collapses duplicates on its own, but
        // the identity stage below is one paid request per candidate and does
        // not, so they are collapsed here where it is still free. A candidate
        // that carries catalog identity wins over one that does not: it can
        // batch, while the bare one would have to pay for a search.
        let deduplicatedCandidates = Self.collapsingDuplicates(candidates)
        let eligibleCandidates = deduplicatedCandidates.filter {
            Self.permitsVendorWork(for: $0.target, usesFallback: usesPriceFallback)
        }
        guard !eligibleCandidates.isEmpty else {
            fallbackStatus = .disabled(pending: deduplicatedCandidates.count)
            return 0
        }
        guard PriceVendorCredentials.hasKey else {
            fallbackStatus = .unconfigured(pending: eligibleCandidates.count)
            return 0
        }

        let identities = ProductIdentityStore(context: store.context)
        var priced = 0
        var completed = 0
        var stoppedByAllowance = false
        var budget = await fallbackService.budgetSnapshot()
        status = .refreshing(completed: 0, total: eligibleCandidates.count)
        fallbackStatus = .running(
            completed: 0,
            total: eligibleCandidates.count,
            remainingToday: budget.remainingToday
        )

        // Two workloads, and only the second of them batches.
        //
        // A card the vendor can already be *asked about* — because a previous
        // pass resolved its variant handle, or because its Scryfall id is
        // itself a supported lookup key — goes into a batch, twenty per
        // request. A card with neither still needs one search to establish
        // identity, and that search is paid for exactly once: the handle it
        // returns is persisted, and every later refresh finds it in the first
        // group.
        var batchable: [CardGame: [MarketPriceTarget]] = [:]
        var needsIdentity: [FallbackCandidate] = []

        for candidate in eligibleCandidates {
            let key = ProductIdentity.key(
                game: candidate.target.game,
                printingID: candidate.target.printingID,
                variantID: candidate.target.variantID,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw
            )
            if candidate.target.isTreatmentQualified {
                // The current vendor wire model has no treatment-specific
                // identity or listing. This is a capability gap, not a vendor
                // miss, so leave the identity store untouched; it must never
                // consume an ordinary foil handle or create a 30-day negative.
                completed += 1
                continue
            }
            // The handle stored on the row wins. It was written when the item
            // was added out of the vendor's own catalogue, and for a sealed box
            // or a graded slab it is the only identity that exists — there is no
            // search that could rediscover it and nothing to resolve.
            let cachedVariant = candidate.target.marketVariantID
                ?? identities.cachedVariantID(forKey: key)
            let cachedCard = identities.cachedCardID(forKey: key)
            // A card already known to be absent from the vendor costs nothing
            // on every subsequent refresh.
            if cachedVariant == nil, cachedCard == nil,
               !identities.needsResolution(forKey: key) {
                continue
            }

            let external = candidate.externalLookups
            guard cachedVariant != nil || !external.isEmpty else {
                needsIdentity.append(candidate)
                continue
            }

            // A graded slab's handle comes from the v2 beta, and v2 ids are a
            // different namespace: posting one to `POST /v1/cards` as
            // `variantId` returns `data: []`. Batching them here would spend
            // batch slots to resolve nothing, silently, forever. Graded pricing
            // needs the v2 path — see `JustTCGV2GradedClient` — and until it
            // has one these are left alone rather than pretended over.
            guard candidate.target.itemKind != .gradedCard else { continue }

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
                    // Nothing to compare a delta against: either the row has
                    // never been priced, or it is a sealed product still
                    // missing the artwork only a returned listing can supply.
                    // "Unchanged" would be an answer to a question it has not
                    // yet been able to ask.
                    requiresFullResponse: !candidate.target.hasPrice
                        || candidate.target.needsArtwork
                )
            )
        }

        // Rows that still have no artwork, indexed by the price key the batch
        // writes back to. A sealed product's picture and its price come from the
        // same response, so the refresh that pays for one may as well store the
        // other rather than leaving a placeholder box on screen forever.
        let artworkPending = Self.rowsMissingArtworkIDs(in: store.context)
        // Artwork is an optional backfill, but marketplace identity is useful
        // for every owned row. Keep separate indexes so an already illustrated
        // card still receives the product/SKU handles returned by this pass.
        let identityRows = Self.rowsByPriceKeyIDs(in: store.context)

        // MARK: Batched pass
        let coordinator = JustTCGRefreshCoordinator(
            client: JustTCGV1Client(transport: sharedTransport)
        )
        for (game, targets) in batchable {
            if Task.isCancelled { break }
            // A delta is only safe once a complete pass has succeeded for this
            // game. Before that, a variant missing from an `updated_after`
            // response is indistinguishable from one never fetched at all.
            let syncLedger = JustTCGSyncLedger()
            let useDelta = syncLedger
                .checkpoint(game: game, apiVersion: JustTCGV1Client.apiVersion)
                .supportsDeltaSync

            let report = await coordinator.refresh(
                targets,
                game: game,
                lane: .background,
                useDelta: useDelta,
                apply: { card, variant, owners in
                    Self.applyVendorBatchHit(
                        card: card,
                        variant: variant,
                        owners: owners,
                        store: store,
                        identities: identities,
                        artworkRowIDsByPriceKey: artworkPending,
                        identityRowIDsByPriceKey: identityRows,
                        context: store.context
                    )
                },
                unmatched: { owners in
                    Self.recordSealedArtworkMiss(
                        for: owners,
                        rowIDsByPriceKey: artworkPending,
                        context: store.context
                    )
                },
                checkpoint: {
                    identities.save()
                    store.save()
                }
            )
            priced += report.variantsUpdated
            completed += report.variantsRequested
            status = .refreshing(completed: completed, total: eligibleCandidates.count)

            switch report.stoppedReason {
            case let .dailyBudget(resetAt), let .monthlyBudget(resetAt):
                stoppedByAllowance = true
                fallbackStatus = .budgetReached(
                    pending: max(eligibleCandidates.count - completed, 0),
                    resetAt: resetAt
                )
            case let .rateLimited(retryAt):
                stoppedByAllowance = true
                fallbackStatus = .rateLimited(
                    pending: max(eligibleCandidates.count - completed, 0),
                    retryAt: retryAt
                )
            case .cancelled, .transportFailure, .none:
                break
            }
            if stoppedByAllowance { break }
        }

        // MARK: Identity pass
        //
        // Only what could not be batched, and only if the allowance survived
        // the batched pass.
        for candidate in (stoppedByAllowance ? [] : needsIdentity) {
            if Task.isCancelled { break }
            defer {
                completed += 1
                status = .refreshing(completed: completed, total: eligibleCandidates.count)
            }
            let key = ProductIdentity.key(
                game: candidate.target.game,
                printingID: candidate.target.printingID,
                variantID: candidate.target.variantID,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw
            )
            // A card already known to be absent from the vendor is skipped
            // outright — that is what makes a collection of unmatchable cards
            // cost nothing on every subsequent refresh.
            let cached = identities.cachedCardID(forKey: key)
            if cached == nil, !identities.needsResolution(forKey: key) { continue }

            guard let subject = candidate.subject(vendorCardID: cached) else { continue }
            let variant = candidate.target.variantID.map(PhysicalVariant.resolving)
            let outcome = await fallbackService.quote(
                for: subject,
                variant: variant,
                lane: .background
            )
            identities.record(
                outcome,
                forKey: key,
                treatmentIDs: candidate.target.magicTreatmentIDsRaw
            )

            switch outcome {
            case let .price(price, _, _):
                store.store(
                    .price(price),
                    game: candidate.target.game,
                    printingID: candidate.target.printingID,
                    variantID: candidate.target.variantID,
                    treatmentIDs: candidate.target.magicTreatmentIDsRaw
                )
                priced += 1
            case let .budgetReached(resetAt):
                stoppedByAllowance = true
                fallbackStatus = .budgetReached(
                    pending: eligibleCandidates.count - completed,
                    resetAt: resetAt
                )
            case let .rateLimited(retryAt):
                stoppedByAllowance = true
                fallbackStatus = .rateLimited(
                    pending: eligibleCandidates.count - completed,
                    retryAt: retryAt
                )
            case .noListingForVariant, .noProductMatch, .unsupportedFinish, .unsupportedTreatment, .requestFailed:
                break
            }

            if stoppedByAllowance { break }

            budget = await fallbackService.budgetSnapshot()
            fallbackStatus = .running(
                completed: completed + 1,
                total: eligibleCandidates.count,
                remainingToday: budget.remainingToday
            )

            // Checkpoint. A first run over a few hundred cards is paced to the
            // vendor's rate limit and can take many minutes, so the work is
            // committed as it goes rather than staked on reaching the end.
            // Resolved handles are the expensive part and must survive being
            // interrupted.
            if completed.isMultiple(of: Self.fallbackCheckpointInterval) {
                identities.save()
                store.save()
            }
        }

        identities.save()
        if !stoppedByAllowance, !Task.isCancelled {
            budget = await fallbackService.budgetSnapshot()
            fallbackStatus = .finished(
                checked: completed,
                priced: priced,
                remainingToday: budget.remainingToday
            )
        }
        return priced
    }

    /// Graded slabs, repriced through the v2 beta.
    ///
    /// Graded variants exist only in v2 and cannot be batched: posting a v2
    /// variant id to `POST /v1/cards` returns an empty result, because raw and
    /// graded variants are separate objects. So this is one request per
    /// *underlying card* — every owned grade of one card comes back together —
    /// narrowed to the graders and grades actually owned, which keeps a card
    /// with a hundred grader/grade permutations to a single small response.
    private func refreshGraded(_ targets: [PriceTarget], store: PriceStore) async -> Int {
        let slabs = targets.filter {
            $0.itemKind == .gradedCard
                && $0.marketVariantID != nil
                && !$0.isTreatmentQualified
        }
        guard !slabs.isEmpty, usesPriceFallback, PriceVendorCredentials.hasKey else { return 0 }

        // One request serves every grade of one card, so group before asking.
        var byCard: [String: [PriceTarget]] = [:]
        for slab in slabs {
            guard let identity = slab.gradedIdentity else { continue }
            byCard[identity.groupingKey(game: slab.game), default: []].append(slab)
        }

        let client = JustTCGV2GradedClient(transport: sharedTransport)
        var priced = 0

        for (_, group) in byCard.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { break }
            guard let identity = group.first?.gradedIdentity, let game = group.first?.game else {
                continue
            }
            let variants: [GradedVariant]
            do {
                variants = try await client.gradedVariants(
                    identity: identity,
                    game: game,
                    companies: Set(group.compactMap(\.gradingCompany)),
                    grades: Set(group.compactMap(\.grade)),
                    lane: .background
                )
            } catch {
                // Budget, rate limit or transport. Nothing is recorded: none of
                // those is evidence about the slab.
                break
            }

            let byVariantID = Dictionary(
                variants.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for target in group {
                guard let handle = target.marketVariantID,
                      let variant = byVariantID[handle],
                      let amount = variant.marketPriceUSD else { continue }
                store.store(
                    .price(
                        NormalizedPrice(
                            unitMarketPriceUSD: amount,
                            currencyCode: "USD",
                            source: .justTCG,
                            sourceVariantID: variant.id,
                            sourceUpdatedAt: variant.updatedAt,
                            fetchedAt: .now
                        )
                    ),
                    game: target.game,
                    printingID: target.printingID,
                    variantID: target.variantID,
                    marketVariantID: variant.id,
                    treatmentIDs: target.magicTreatmentIDsRaw
                )
                if let record = store.record(forKey: target.id) {
                    record.marketVariantID = variant.id
                    record.itemKindRaw = CollectionItemKind.gradedCard.rawValue
                }
                priced += 1
            }
            store.save()
        }
        return priced
    }

    /// Collection rows with no picture yet, keyed by the price key a batched
    /// response writes back to.
    private static func rowsMissingArtwork(
        in context: ModelContext
    ) -> [String: [CollectedCard]] {
        let rows = (try? context.fetch(
            FetchDescriptor<CollectedCard>(predicate: #Predicate { $0.imageURL == nil })
        )) ?? []
        return Dictionary(grouping: rows, by: \.priceKey)
    }

    private static func rowsByPriceKey(
        in context: ModelContext
    ) -> [String: [CollectedCard]] {
        let rows = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return Dictionary(grouping: rows, by: \.priceKey)
    }

    private static func rowsMissingArtworkIDs(
        in context: ModelContext
    ) -> [String: [PersistentIdentifier]] {
        let rows = (try? context.fetch(
            FetchDescriptor<CollectedCard>(predicate: #Predicate { $0.imageURL == nil })
        )) ?? []
        return rows.reduce(into: [String: [PersistentIdentifier]]()) { result, row in
            result[row.priceKey, default: []].append(row.persistentModelID)
        }
    }

    private static func rowsByPriceKeyIDs(
        in context: ModelContext
    ) -> [String: [PersistentIdentifier]] {
        let rows = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return rows.reduce(into: [String: [PersistentIdentifier]]()) { result, row in
            result[row.priceKey, default: []].append(row.persistentModelID)
        }
    }

    private static func rows(
        for ids: [PersistentIdentifier],
        in context: ModelContext
    ) -> [CollectedCard] {
        ids.compactMap { context.model(for: $0) as? CollectedCard }
    }

    private static func materializedRows(
        from index: [String: [PersistentIdentifier]],
        in context: ModelContext
    ) -> [String: [CollectedCard]] {
        index.mapValues { rows(for: $0, in: context) }
    }

    /// Applies product artwork independently of whether the returned variant
    /// has a market price. A completed response without a usable marketplace
    /// image is stamped at the current resolver version so an already-priced
    /// row does not spend one request per refresh learning the same fact.
    static func recordSealedArtwork(
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
    static func recordSealedArtworkMiss(
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

    private static func recordSealedArtworkMiss(
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
    static func applyVendorBatchHit(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        artworkRowsByPriceKey: [String: [CollectedCard]],
        identityRowsByPriceKey: [String: [CollectedCard]],
        fetchedAt: Date = .now
    ) {
        // This callback is a second line of defence after the coordinator's
        // treatment-aware owner grouping. A generic vendor response must never
        // be written to a treatment-qualified Magic key, even if a future
        // caller accidentally supplies a mixed owner array.
        guard owners.allSatisfy({ !$0.isTreatmentQualified }) else { return }
        recordSealedArtwork(
            from: card,
            for: owners,
            rowsByPriceKey: artworkRowsByPriceKey,
            checkedAt: fetchedAt
        )
        for owner in owners {
            identities.recordBatchResolution(
                forKey: owner.priceKey,
                cardID: card.uuid ?? card.id,
                variantID: variant.variantId,
                treatmentIDs: owner.magicTreatmentIDsRaw,
                at: fetchedAt
            )
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

        guard let amount = variant.marketPriceUSD else { return }
        let normalized = NormalizedPrice(
            unitMarketPriceUSD: amount,
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: variant.variantId ?? "batch",
            sourceUpdatedAt: variant.updatedAt,
            fetchedAt: fetchedAt
        )
        for owner in owners {
            store.store(
                .price(normalized),
                game: owner.game,
                printingID: owner.printingID,
                variantID: owner.variantID,
                marketVariantID: variant.variantId,
                treatmentIDs: owner.magicTreatmentIDsRaw
            )
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
    }

    private static func applyVendorBatchHit(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        artworkRowIDsByPriceKey: [String: [PersistentIdentifier]],
        identityRowIDsByPriceKey: [String: [PersistentIdentifier]],
        context: ModelContext,
        fetchedAt: Date = .now
    ) {
        // The IDs were captured before the network await. Re-fetching here
        // makes deletion, rollback, or a sync merge during that await harmless.
        applyVendorBatchHit(
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
            fetchedAt: fetchedAt
        )
    }

    /// Compatibility overload for callers that already have one row index.
    /// Identity persistence is now intentionally broader than artwork
    /// backfill, but existing support/test callers should keep compiling while
    /// they migrate to the two-index form.
    static func applyVendorBatchHit(
        card: JustTCGCard,
        variant: JustTCGVariant,
        owners: [MarketPriceTarget],
        store: PriceStore,
        identities: ProductIdentityStore,
        rowsByPriceKey: [String: [CollectedCard]],
        fetchedAt: Date = .now
    ) {
        applyVendorBatchHit(
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

    /// How often the fallback commits progress mid-run.
    private static let fallbackCheckpointInterval = 10
    /// The catalog pass's equivalent, in answered printings.
    private static let catalogCheckpointInterval = 10

    /// A check that returns the same market timestamp is not an update, and
    /// saying "prices updated" when nothing moved is the kind of small lie that
    /// makes a whole collection feel untrustworthy.
    private func isNewer(_ candidate: Date?, than previous: Date?) -> Bool {
        guard let candidate else { return false }
        guard let previous else { return true }
        return candidate > previous
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
            return !summary.providerUnreachable && summary.failed == 0
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

    private func latestKnownSourceUpdate(in store: PriceStore) -> Date? {
        store.allRecords().compactMap(\.sourceUpdatedAt).max()
    }

    private nonisolated static func fetch(
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
            if case .badResponse = error, printing.game == .magic {
                return PriceFetchOutcome(printing: printing, result: .unreachable)
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
