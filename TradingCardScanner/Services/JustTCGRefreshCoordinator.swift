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
        let cutoff = useDelta
            ? syncLedger.deltaCutoff(game: game, apiVersion: JustTCGV1Client.apiVersion)
            : nil

        for chunk in chunks {
            if Task.isCancelled {
                report.stoppedReason = .cancelled
                return report
            }

            do {
                let response = try await client.batchCards(
                    chunk,
                    updatedAfter: cutoff,
                    includePriceHistory: false,
                    lane: lane
                )
                report.requestsUsed += 1

                let returned = response.variantsByID
                for lookup in chunk {
                    guard let owners = batched[lookup] else { continue }
                    guard let hit = Self.match(lookup: lookup, in: returned, response: response) else {
                        // Absent from a delta response means "unchanged", and a
                        // cached price must never be cleared because of it. In a
                        // full response absence is ambiguous — unresolved or
                        // unavailable — and is likewise left alone rather than
                        // guessed at.
                        continue
                    }
                    apply(hit.card, hit.variant, owners)
                    report.variantsUpdated += owners.isEmpty ? 0 : 1
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
    private nonisolated static func match(
        lookup: JustTCGBatchLookup,
        in returned: [String: (card: JustTCGCard, variant: JustTCGVariant)],
        response: JustTCGBatchResponse
    ) -> (card: JustTCGCard, variant: JustTCGVariant)? {
        switch lookup {
        case let .variantID(id):
            return returned[id]
        case let .cardID(id):
            guard let card = response.data.first(where: { $0.id == id }),
                  let variant = card.variants?.first else { return nil }
            return (card, variant)
        case let .tcgplayerID(id):
            guard let card = response.data.first(where: { $0.tcgplayerId == id }),
                  let variant = card.variants?.first else { return nil }
            return (card, variant)
        case .tcgplayerSKUID, .mtgjsonID, .scryfallID:
            // These resolve to exactly one card per request item, so a single
            // returned card is unambiguous. More than one means the assumption
            // is wrong, and guessing which is the failure mode to avoid.
            guard response.data.count == 1,
                  let card = response.data.first,
                  let variant = card.variants?.first else { return nil }
            return (card, variant)
        }
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
