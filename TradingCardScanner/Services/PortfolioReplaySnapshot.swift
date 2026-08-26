import Foundation
import SwiftData

/// The storage boundary for portfolio replay.
///
/// Everything SwiftData-shaped happens here, once, and comes out as `Sendable`
/// values. `PortfolioReplayEngine` never sees a `ModelContext`, a
/// `FetchDescriptor` or an actor — which is what makes a whole year of
/// accounting testable from literal arrays, and what will let the replay move
/// off the main actor without touching its logic.
///
/// The rule this type exists to enforce: **fetch once, in bulk**. The engine it
/// replaces asked SwiftData for a `PriceCheckDay` row per held instrument per
/// day, twice — 1,284 instruments over 180 days is over 460,000 fetch
/// opportunities before any arithmetic happens. Coverage is now one query and a
/// dictionary.
/// Current price evidence for every instrument, resolved once.
///
/// The same lesson as the coverage index, learned twice. Asking
/// `InventoryLedger.valuation(forPriceKey:)` per position is one fetch per
/// position against the whole observation log — fine when recording a single
/// event, ruinous when valuing a collection. Two thousand positions against a
/// year of observations took 52 seconds this way while the replay itself took
/// two.
struct InstrumentValuationIndex: Sendable {
    private let byInstrument: [String: InventoryValuation]

    init(byInstrument: [String: InventoryValuation]) {
        self.byInstrument = byInstrument
    }

    func valuation(for instrument: String) -> InventoryValuation {
        byInstrument[instrument] ?? .unpriced
    }

    /// The key a card is valued through: the first of its lookup keys that
    /// actually holds a value, matching what `PriceStore` prefers so the ledger
    /// and the grid never disagree about which number is in use.
    func priceStorageKey(for card: CollectedCard) -> String {
        let keys = card.priceLookupKeys
        for key in keys where byInstrument[key]?.unitPrice != nil {
            return key
        }
        return keys.first ?? card.priceKey
    }
}

enum PortfolioReplaySnapshotBuilder {

    struct Snapshot {
        var input: PortfolioReplayInput
        var valuations: InstrumentValuationIndex
        /// Instruments holding a real price in a currency the total has no rate
        /// to convert from. Excluded and counted separately, never converted.
        var otherCurrencyInstruments: Set<String>
        /// Straight from the ledger read plus the projection: whether anything
        /// derived from this snapshot may be published as history.
        var isAuthoritative: Bool
        var defects: [LedgerIntegrityDefect]
        var projection: LogicalCollectionProjection
    }

    /// The computation as it crosses back to the UI: fully `Sendable`, with no
    /// SwiftData model anywhere in it.
    struct Computation: Sendable {
        var valuation: PortfolioEngine.CurrentValuation
        var defects: [LedgerIntegrityDefect]
        var isAuthoritative: Bool
        var replay: PortfolioReplayResult
        var coverage: PortfolioCoverageIndex
        var holdings: [PortfolioHoldingSnapshot]
    }

    /// Everything expensive, in one place, off the main actor.
    static func compute(
        context: ModelContext,
        epoch: Date,
        through: Date,
        timeZone: TimeZone
    ) -> Computation {
        let snapshot = make(context: context, epoch: epoch, through: through, timeZone: timeZone)
        return Computation(
            valuation: PortfolioEngine.currentValuation(
                projection: snapshot.projection,
                valuations: snapshot.valuations,
                otherCurrencyInstruments: snapshot.otherCurrencyInstruments
            ),
            defects: snapshot.defects
                + PortfolioEngine.reconcile(
                    projection: snapshot.projection,
                    events: snapshot.input.events
                ),
            isAuthoritative: snapshot.isAuthoritative,
            replay: PortfolioReplayEngine.replay(snapshot.input),
            coverage: snapshot.input.coverage,
            holdings: holdingSnapshots(projection: snapshot.projection, valuations: snapshot.valuations)
        )
    }

    private static func holdingSnapshots(
        projection: LogicalCollectionProjection,
        valuations: InstrumentValuationIndex
    ) -> [PortfolioHoldingSnapshot] {
        projection.positions.compactMap { position in
            guard position.quantity > 0 else { return nil }
            let card = position.representative
            let price = valuations.valuation(for: position.priceStorageKey).unitPrice
            let detailParts = [card.setName, card.variantLabel ?? card.itemKindLabel]
                .filter { !$0.isEmpty }
            return PortfolioHoldingSnapshot(
                collectionKey: position.collectionKey,
                name: card.name,
                detail: detailParts.joined(separator: " · "),
                artworkURL: URL(string: card.thumbnailURL ?? card.imageURL ?? ""),
                quantity: position.quantity,
                currentValue: price.map { $0 * position.quantity }
            )
        }
    }

    static func make(
        context: ModelContext,
        epoch: Date,
        through: Date,
        timeZone: TimeZone
    ) -> Snapshot {
        let ledger = InventoryLedger(context: context)
        let reading = ledger.read()
        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []

        let events = reading.events.map(PortfolioEngine.entry(from:))

        // One materialisation of each table, reused. Fetching the observation
        // log twice — once to replay and once to value the collection — doubled
        // the dominant cost of the whole recomputation.
        let rows = (try? context.fetch(
            FetchDescriptor<PriceObservation>(
                sortBy: [SortDescriptor(\.receivedAt, order: .forward)]
            )
        )) ?? []
        let observations = rows.map(PortfolioEngine.observationEntry(from:))
        let records = (try? context.fetch(FetchDescriptor<PriceRecord>())) ?? []
        let valuations = valuationIndex(observations: rows, records: records)
        let otherCurrencyInstruments = Set(
            records
                .filter { $0.unitMarketPriceUSD != nil && $0.currencyCode != "USD" }
                .map(\.key)
        )
        let projection = LogicalCollection.project(cards: cards) {
            valuations.priceStorageKey(for: $0)
        }

        let epochDay = PortfolioCalendar.day(containing: epoch, in: timeZone)
        let coverage = coverageIndex(
            context: context,
            from: epochDay,
            through: through,
            timeZone: timeZone
        )

        return Snapshot(
            input: PortfolioReplayInput(
                events: events,
                observations: observations,
                coverage: coverage,
                epoch: epoch,
                through: through,
                timeZoneIdentifier: timeZone.identifier
            ),
            valuations: valuations,
            otherCurrencyInstruments: otherCurrencyInstruments,
            isAuthoritative: reading.isAuthoritative && projection.defects.isEmpty,
            defects: reading.defects + projection.defects,
            projection: projection
        )
    }

    /// Current value per instrument, from two bulk reads.
    ///
    /// The newest observation wins; a `PriceRecord` fills in only for
    /// instruments priced before the log existed. Mirrors
    /// `InventoryLedger.valuation(forPriceKey:)` exactly, in bulk.
    static func valuationIndex(
        observations: [PriceObservation],
        records: [PriceRecord]
    ) -> InstrumentValuationIndex {
        var newest: [String: PriceObservation] = [:]
        for observation in observations {
            if let existing = newest[observation.instrumentKey],
               existing.receivedAt >= observation.receivedAt { continue }
            newest[observation.instrumentKey] = observation
        }

        var index: [String: InventoryValuation] = [:]
        for (key, observation) in newest {
            // An invalidation is authoritative: falling through to the mutable
            // PriceRecord would resurrect exactly the price the log withdrew.
            if observation.kind == .explicitInvalidation {
                index[key] = .unpriced
                continue
            }
            guard let amount = observation.amount, observation.currencyCode == "USD" else {
                index[key] = .unpriced
                continue
            }
            index[key] = InventoryValuation(
                unitPrice: amount,
                source: observation.source,
                effectiveAt: observation.effectiveAt,
                receivedAt: observation.receivedAt,
                observationID: observation.id
            )
        }

        for record in records where index[record.key] == nil {
            guard let amount = record.unitMarketPriceUSD,
                  record.currencyCode == "USD",
                  let money = Money(rounding: amount) else {
                index[record.key] = .unpriced
                continue
            }
            index[record.key] = InventoryValuation(
                unitPrice: money,
                source: record.source,
                effectiveAt: record.sourceUpdatedAt ?? record.fetchedAt,
                receivedAt: record.fetchedAt,
                observationID: nil
            )
        }

        return InstrumentValuationIndex(byInstrument: index)
    }

    /// One query for the whole range, reduced in memory.
    ///
    /// Deliberately not a loop over dates issuing a query per day: the entire
    /// point of the replay rewrite is to stop multiplying queries by history
    /// length.
    static func coverageIndex(
        context: ModelContext,
        from start: Date,
        through end: Date,
        timeZone: TimeZone
    ) -> PortfolioCoverageIndex {
        // The last day the replay can close is the one containing `end`, so the
        // index has to reach that day's start.
        let lastDay = PortfolioCalendar.day(containing: end, in: timeZone)
        let descriptor = FetchDescriptor<PriceCheckDay>(
            predicate: #Predicate { $0.portfolioDay >= start && $0.portfolioDay <= lastDay }
        )
        let checks = (try? context.fetch(descriptor)) ?? []

        var checkedByDay: [Date: Set<String>] = [:]
        for check in checks {
            checkedByDay[check.portfolioDay, default: []].insert(check.instrumentKey)
        }
        return PortfolioCoverageIndex(checkedByDay: checkedByDay)
    }
}

/// Owns a private `ModelContext` so fetching and flattening the portfolio's
/// inputs happens away from the UI.
///
/// Moving only the pure replay off the main actor would have moved the cheap
/// part: measured end to end, the replay is roughly 0.3s of a 2.5s
/// recomputation and the rest is SwiftData materialising observation and
/// check-day rows. That is the work that has to leave.
@ModelActor
actor PortfolioComputationActor {
    func compute(
        epoch: Date,
        through: Date,
        timeZoneIdentifier: String
    ) -> PortfolioReplaySnapshotBuilder.Computation {
        PortfolioReplaySnapshotBuilder.compute(
            context: modelContext,
            epoch: epoch,
            through: through,
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
        )
    }
}
