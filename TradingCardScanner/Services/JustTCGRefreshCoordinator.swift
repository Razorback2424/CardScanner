import Foundation

/// One thing whose market price needs refreshing.
///
/// Carries both the storage key it writes back to and the identifiers it can be
/// looked up by, so deduplication and correlation never need a second pass over
/// the collection.
struct MarketPriceTarget: Hashable, Sendable {
    let priceKey: String
    let game: CardGame
    let printingID: String
    let variantID: String?
    let itemKind: CollectionItemKind
    /// The vendor's stable variant UUID, when identity has been resolved.
    let marketVariantID: String?
    /// Fallback identifiers, best-first by the vendor's precedence.
    let lookupCandidates: [JustTCGBatchLookup]
    let currentAmount: Double?
    let lastCheckedAt: Date?
    /// The collection identity this target writes. It is deliberately separate
    /// from the vendor lookup handle because the vendor may not distinguish a
    /// treatment even though the app must keep its price records distinct.
    let magicTreatmentIDsRaw: [String]
    /// This row has never had a complete answer from the vendor, so "unchanged
    /// since the cutoff" tells it nothing.
    ///
    /// `updated_after` is only meaningful for a row that already holds what the
    /// response would be confirming. For a row with no price yet, or a sealed
    /// product still waiting on its artwork, an omitted variant is
    /// indistinguishable from one that was never fetched — which is the exact
    /// ambiguity the delta clock is supposed to prevent. Such a row forces its
    /// whole chunk to ask for a full response.
    var requiresFullResponse: Bool = false

    init(
        priceKey: String,
        game: CardGame,
        printingID: String,
        variantID: String?,
        itemKind: CollectionItemKind,
        marketVariantID: String?,
        lookupCandidates: [JustTCGBatchLookup],
        currentAmount: Double?,
        lastCheckedAt: Date?,
        magicTreatmentIDsRaw: [String] = [],
        requiresFullResponse: Bool = false
    ) {
        self.priceKey = priceKey
        self.game = game
        self.printingID = printingID
        self.variantID = variantID
        self.itemKind = itemKind
        self.marketVariantID = marketVariantID
        self.lookupCandidates = lookupCandidates
        self.currentAmount = currentAmount
        self.lastCheckedAt = lastCheckedAt
        self.magicTreatmentIDsRaw = magicTreatmentIDsRaw
        self.requiresFullResponse = requiresFullResponse
    }

    /// The single identifier this target should be sent as.
    var lookup: JustTCGBatchLookup? {
        if let marketVariantID { return .variantID(marketVariantID) }
        return JustTCGBatchLookup.best(from: lookupCandidates)
    }
}

/// What one batched refresh pass did.
struct MarketRefreshReport: Equatable, Sendable {
    var requestsUsed = 0
    var batchesCompleted = 0
    var batchesPlanned = 0
    var variantsUpdated = 0
    var variantsRequested = 0
    /// True only when every batch succeeded. The sync checkpoint may only
    /// advance when this holds.
    var completedFully = false
    var stoppedReason: StopReason?

    enum StopReason: Equatable, Sendable {
        case dailyBudget(resetAt: Date)
        case monthlyBudget(resetAt: Date)
        case rateLimited(retryAt: Date)
        case cancelled
        case transportFailure
    }

    /// The progress line the collection shows.
    var progressDescription: String {
        "Refreshing batch \(batchesCompleted + 1) of \(batchesPlanned)"
    }

    var updatedDescription: String {
        "Updated \(variantsUpdated) of \(variantsRequested) variants"
    }
}

/// Turns a collection's worth of stale prices into as few HTTP requests as the
/// plan allows.
///
/// The arithmetic that justifies this type: 500 unique variants is 25 requests
/// on the free tier instead of 500. Duplicated copies cost nothing — eight
/// owned copies of one printing are one variant, one lookup, one returned price
/// applied to every copy.
/// Main-actor isolated because its callbacks mutate SwiftData, which is
/// main-actor bound. The network work still happens off it: `JustTCGTransport`
/// is its own actor, and each `await` here releases the main actor while a
/// request is in flight.
@MainActor
struct JustTCGRefreshCoordinator {
    private let client: JustTCGV1Client
    private let syncLedger: JustTCGSyncLedger

    init(client: JustTCGV1Client, syncLedger: JustTCGSyncLedger = JustTCGSyncLedger()) {
        self.client = client
        self.syncLedger = syncLedger
    }

    /// Collapse targets to the unique variants that actually need asking about.
    ///
    /// Two separate reductions, and both matter:
    ///
    /// - many owned copies share one variant, so they share one lookup;
    /// - a target with no usable identifier cannot be batched at all and is
    ///   returned separately rather than silently dropped, because "we never
    ///   asked" and "the vendor has nothing" are different diagnoses.
    nonisolated static func deduplicate(
        _ targets: [MarketPriceTarget]
    ) -> (batched: [JustTCGBatchLookup: [MarketPriceTarget]], unresolved: [MarketPriceTarget]) {
        var batched: [JustTCGBatchLookup: [MarketPriceTarget]] = [:]
        var unresolved: [MarketPriceTarget] = []
        for target in targets {
            guard let lookup = target.lookup else {
                unresolved.append(target)
                continue
            }
            batched[lookup, default: []].append(target)
        }
        return (batched, unresolved)
    }

    /// One batched pass.
    ///
    /// - Parameter apply: called once per returned variant with every target
    ///   that shares it. Mutation lives with the caller so this type stays free
    ///   of SwiftData and stays testable.
    /// - Parameter checkpoint: called after each successful batch, so a
    ///   cancelled or rate-limited run keeps the work it already paid for.
    func refresh(
        _ targets: [MarketPriceTarget],
        game: CardGame,
        lane: JustTCGRequestLane = .background,
        useDelta: Bool = false,
        onProgress: (MarketRefreshReport) -> Void = { _ in },
        apply: (JustTCGCard, JustTCGVariant, [MarketPriceTarget]) -> Void,
        unmatched: ([MarketPriceTarget]) -> Void = { _ in },
        checkpoint: () -> Void
    ) async -> MarketRefreshReport {
        let (batched, unresolved) = Self.deduplicate(targets)
        var report = MarketRefreshReport()
        report.variantsRequested = batched.count + unresolved.count

        guard !batched.isEmpty else {
            report.completedFully = unresolved.isEmpty
            return report
        }

        let lookups = Array(batched.keys)
        let chunks = lookups.chunked(into: JustTCGQuota.batchSize)
        report.batchesPlanned = chunks.count
        onProgress(report)

        // `updated_after` is only safe once a complete pass has succeeded.
        // Before that a variant absent from the response is indistinguishable
        // from one that was never fetched at all.
        //
        // The game-level clock is not sufficient on its own: it is advanced by
        // whatever pass happened to succeed, and a pass only ever covers the
        // rows that were stale that minute. A row added afterwards would then be
        // asked with a cutoff it has no evidence behind. So the clock decides
        // whether delta is *available*, and each chunk decides whether delta is
        // *usable* for the rows it actually carries.
        let clock = useDelta
            ? syncLedger.deltaCutoff(game: game, apiVersion: JustTCGV1Client.apiVersion)
            : nil

        for chunk in chunks {
            if Task.isCancelled {
                report.stoppedReason = .cancelled
                return report
            }

            let chunkOwners = chunk.flatMap { batched[$0] ?? [] }
            // One row with nothing to compare against makes the whole chunk ask
            // for a full response. A full request costs exactly the same single
            // request as a delta one — `updated_after` narrows the response, not
            // the batch — so this buys correctness for no quota at all.
            let cutoff = chunkOwners.contains(where: \.requiresFullResponse) ? nil : clock

            do {
                let response = try await client.batchCards(
                    chunk,
                    updatedAfter: cutoff,
                    includePriceHistory: false,
                    lane: lane
                )
                report.requestsUsed += 1

                for lookup in chunk {
                    guard let owners = batched[lookup] else { continue }
                    var applied = false

                    // A card-level lookup can serve several owned finishes. The
                    // request is still deduplicated, but the returned listing
                    // must be selected and applied per physical variant.
                    for finishOwners in Dictionary(grouping: owners, by: \.variantID).values {
                        guard case let .matched(card, variant) = Self.exactListing(
                            lookup: lookup,
                            owners: finishOwners,
                            response: response
                        ) else {
                            // Absent from a delta response means "unchanged", and a
                            // cached price must never be cleared because of it — so
                            // nothing is reported for those.
                            //
                            // A full response is different. The vendor was asked
                            // about this exact variant and returned no listing for
                            // it, which is a real, current answer. Reporting it lets
                            // the caller record that the question was asked; without
                            // that, a row whose only outstanding need is something a
                            // non-match can never supply — sealed artwork — stays
                            // stale forever and spends a request on every refresh
                            // for the life of the collection.
                            //
                            // The value is still left exactly as it was either way.
                            if cutoff == nil { unmatched(finishOwners) }
                            continue
                        }
                        apply(card, variant, finishOwners)
                        applied = true
                    }
                    // Keep this counter at one per network lookup, preserving
                    // the report's existing meaning even when one response
                    // contains several owned finishes.
                    report.variantsUpdated += applied ? 1 : 0
                }

                report.batchesCompleted += 1
                // Committed per batch so an interruption keeps what it bought.
                checkpoint()
                onProgress(report)
            } catch let error as JustTCGTransport.TransportError {
                report.stoppedReason = Self.stopReason(for: error)
                return report
            } catch {
                report.stoppedReason = .transportFailure
                return report
            }
        }

        // Only a pass where every batch succeeded may advance the delta clock.
        report.completedFully = report.batchesCompleted == report.batchesPlanned
        if report.completedFully, unresolved.isEmpty {
            syncLedger.recordCompleteSync(game: game, apiVersion: JustTCGV1Client.apiVersion)
        }
        return report
    }

    /// Correlate one requested identifier back to a returned variant.
    ///
    /// Never positional. The vendor is not obliged to preserve request order,
    /// and matching by index would attach one card's price to another.
    /// The result of correlating a direct marketplace lookup with an exact
    /// physical listing. `noExactListing` is deliberately distinct from
    /// `unresolved`: the former means the provider returned the verified
    /// product but not the requested finish/condition, while the latter is not
    /// evidence about the card at all.
    enum ExactLookupResult {
        case matched(card: JustTCGCard, variant: JustTCGVariant)
        case noExactListing
        case unresolved
    }

    /// The exact-variant selection contract shared by collection refresh and
    /// interactive Price Check refreshes.
    nonisolated static func exactListing(
        lookup: JustTCGBatchLookup,
        owners: [MarketPriceTarget],
        response: JustTCGBatchResponse
    ) -> ExactLookupResult {
        let returned = response.variantsByID
        switch lookup {
        case let .variantID(id):
            // Already the exact printing and finish. Nothing to choose.
            guard let hit = returned[id] else { return .unresolved }
            return .matched(card: hit.card, variant: hit.variant)
        case let .cardID(id):
            guard let card = response.data.first(where: { $0.uuid == id || $0.id == id }) else {
                return .unresolved
            }
            return listing(on: card, for: owners).map {
                .matched(card: $0.card, variant: $0.variant)
            } ?? .noExactListing
        case let .tcgplayerID(id):
            guard let card = response.data.first(where: { $0.tcgplayerId == id }) else {
                return .unresolved
            }
            return listing(on: card, for: owners).map {
                .matched(card: $0.card, variant: $0.variant)
            } ?? .noExactListing
        case .tcgplayerSKUID, .mtgjsonID, .scryfallID:
            // These resolve to exactly one card per request item, so a single
            // returned card is unambiguous. More than one means the assumption
            // is wrong, and guessing which is the failure mode to avoid.
            guard response.data.count == 1, let card = response.data.first else {
                return .unresolved
            }
            return listing(on: card, for: owners).map {
                .matched(card: $0.card, variant: $0.variant)
            } ?? .noExactListing
        }
    }

    /// The listing on a card-level hit that belongs to the finish being priced.
    ///
    /// A card-keyed lookup returns every condition and every printing the vendor
    /// carries, and that array is neither ordered nor monotonic in condition —
    /// a live response had Heavily Played above Near Mint on the same card.
    /// Taking the first entry published whatever happened to be at index zero as
    /// the market price, which could be a Damaged copy or another finish
    /// entirely. Condition is pinned the same way the search path pins it, and
    /// the finish must be the one the owner actually holds.
    nonisolated static func listing(
        on card: JustTCGCard,
        for owners: [MarketPriceTarget]
    ) -> (card: JustTCGCard, variant: JustTCGVariant)? {
        let variants = card.variants ?? []
        let wanted = owners.compactMap {
            ProductFinish.printing(for: $0.variantID.map(PhysicalVariant.resolving))
        }

        if let match = variants.first(where: { variant in
            variant.condition?.caseInsensitiveCompare(ProductFinish.condition) == .orderedSame
                && wanted.contains { variant.printing?.caseInsensitiveCompare($0) == .orderedSame }
        }) {
            return (card, match)
        }

        // A sealed product has no condition grade and exactly one listing.
        if owners.allSatisfy({ $0.itemKind == .sealedProduct }),
           let sealed = variants.first(where: \.isSealed) {
            return (card, sealed)
        }

        // No finish was requested — an imported row whose finish was never
        // recorded. One Near Mint listing is unambiguous; several are not, and
        // guessing between them is how a foil's price lands on a plain copy.
        // An explicit but unmapped finish is different from an absent finish:
        // it is known physical evidence that this resolver cannot translate,
        // so it must remain unpriced rather than borrowing the sole Near Mint
        // listing by accident.
        guard wanted.isEmpty, owners.allSatisfy({ $0.variantID == nil }) else { return nil }
        let nearMint = variants.filter {
            $0.condition?.caseInsensitiveCompare(ProductFinish.condition) == .orderedSame
        }
        guard nearMint.count == 1 else { return nil }
        return (card, nearMint[0])
    }

    private nonisolated static func stopReason(
        for error: JustTCGTransport.TransportError
    ) -> MarketRefreshReport.StopReason {
        switch error {
        case let .budgetReached(resetAt): return .dailyBudget(resetAt: resetAt)
        case let .monthlyBudgetReached(resetAt): return .monthlyBudget(resetAt: resetAt)
        case let .rateLimited(retryAt): return .rateLimited(retryAt: retryAt)
        case .missingCredentials, .invalidURL, .badResponse: return .transportFailure
        }
    }
}

extension Array {
    /// Split into fixed-size chunks. Used to turn a collection into batches of
    /// the plan's maximum size.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
