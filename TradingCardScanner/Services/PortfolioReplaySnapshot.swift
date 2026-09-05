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
        timeZone: TimeZone,
        existingObservations: [PriceObservation]? = nil
    ) -> Computation {
        let snapshot = make(
            context: context,
            epoch: epoch,
            through: through,
            timeZone: timeZone,
            existingObservations: existingObservations
        )
        let valuation = PortfolioEngine.currentValuation(
            projection: snapshot.projection,
            valuations: snapshot.valuations,
            otherCurrencyInstruments: snapshot.otherCurrencyInstruments
        )
        let replay = PortfolioReplayEngine.replay(snapshot.input)
        var defects = snapshot.defects
            + PortfolioEngine.reconcile(
                projection: snapshot.projection,
                events: snapshot.input.events
            )
        if valuation.hasArithmeticOverflow || replay.hasArithmeticOverflow {
            defects.append(
                LedgerIntegrityDefect(
                    reason: .moneyArithmeticOverflow,
                    collectionKey: "portfolio",
                    detail: "At least one portfolio calculation exceeded Int64's safe money range.",
                    canRepairQuantity: false
                )
            )
        }
        return Computation(
            valuation: valuation,
            defects: defects,
            isAuthoritative: snapshot.isAuthoritative && defects.isEmpty,
            replay: replay,
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
            let artworkURL = card.highImageURL
            let artworkFallbackURL = card.lowImageURL == artworkURL ? nil : card.lowImageURL
            return PortfolioHoldingSnapshot(
                collectionKey: position.collectionKey,
                name: card.name,
                detail: detailParts.joined(separator: " · "),
                userArtworkFilename: card.userArtworkFilename,
                artworkURL: artworkURL,
                artworkFallbackURL: artworkFallbackURL,
                quantity: position.quantity,
                currentValue: price?.multiplied(by: position.quantity)
            )
        }
    }

    static func make(
        context: ModelContext,
        epoch: Date,
        through: Date,
        timeZone: TimeZone,
        existingObservations: [PriceObservation]? = nil
    ) -> Snapshot {
        let ledger = InventoryLedger(context: context)
        let reading = ledger.read()
        var defects = reading.defects
        let cards: [CollectedCard]
        do {
            cards = try context.fetch(FetchDescriptor<CollectedCard>())
        } catch {
            cards = []
            defects.append(Self.unreadableDefect(for: "CollectedCard", error: error))
        }
        let activities: [CollectionActivity]
        do {
            activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        } catch {
            activities = []
            defects.append(Self.unreadableDefect(for: "CollectionActivity", error: error))
        }

        // One materialisation of each table, reused. Fetching the observation
        // log twice — once to replay and once to value the collection — doubled
        // the dominant cost of the whole recomputation.
        let rows: [PriceObservation]
        if let existingObservations {
            rows = existingObservations
        } else {
            do {
                rows = try context.fetch(
                    FetchDescriptor<PriceObservation>(
                        sortBy: [SortDescriptor(\.receivedAt, order: .forward)]
                    )
                )
            } catch {
                rows = []
                defects.append(Self.unreadableDefect(for: "PriceObservation", error: error))
            }
        }
        let observations = rows.map { PortfolioEngine.observationEntry(from: $0) }
        let records: [PriceRecord]
        do {
            records = try context.fetch(FetchDescriptor<PriceRecord>())
        } catch {
            records = []
            defects.append(Self.unreadableDefect(for: "PriceRecord", error: error))
        }
        let valuations = valuationIndex(observations: rows, records: records)
        let otherCurrencyInstruments = Set(
            records
                .filter { $0.effectiveUnitMarketPriceUSD != nil && $0.currencyCode != "USD" }
                .map(\.key)
        )
        let projection = LogicalCollection.project(cards: cards) {
            valuations.priceStorageKey(for: $0)
        }
        // A newer device can rekey treatment-qualified ledger rows before an
        // older device receives the matching collection-row migration. Treat
        // that canonical event key as an alias of the still-present legacy
        // position until the next write heals the physical row.
        let collectionKeyAliases = LogicalCollection.readThroughAliases(
            projection: projection,
            eventKeys: Set(reading.events.map(\.collectionKey))
        )
        let events = reading.events.map { event -> LedgerEntry in
            var entry = PortfolioEngine.entry(from: event)
            entry.collectionKey = collectionKeyAliases[entry.collectionKey] ?? entry.collectionKey
            return entry
        }
        let activityDefects = CollectionActivity.integrityDefects(
            activities: activities,
            events: reading.events,
            collectionKeyAliases: collectionKeyAliases
        )

        let epochDay = PortfolioCalendar.day(containing: epoch, in: timeZone)
        let coverage: PortfolioCoverageIndex
        do {
            coverage = try coverageIndexThrowing(
                context: context,
                from: epochDay,
                through: through,
                timeZone: timeZone
            )
        } catch {
            coverage = PortfolioCoverageIndex(checkedByDay: [:])
            defects.append(Self.unreadableDefect(for: "PriceCheckDay", error: error))
        }

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
            isAuthoritative: reading.isAuthoritative
                && defects.isEmpty
                && projection.defects.isEmpty
                && activityDefects.isEmpty,
            defects: defects + projection.defects + activityDefects,
            projection: projection
        )
    }

    private static func unreadableDefect(for table: String, error: Error) -> LedgerIntegrityDefect {
        LedgerIntegrityDefect(
            reason: .unreadableStore,
            collectionKey: "store:\(table)",
            detail: "\(table) rows could not be read: \(error)",
            canRepairQuantity: false
        )
    }

    /// Current value per instrument, from two bulk reads.
    ///
    /// The newest usable USD observation wins; a `PriceRecord` fills in when
    /// the newest observation cannot be used for a USD total. An explicit
    /// invalidation blocks that fallback. The evidence-resolution rule lives
    /// in `InventoryLedger` and is shared with scalar reads.
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

        var recordsByKey: [String: PriceRecord] = [:]
        for record in records where recordsByKey[record.key] == nil {
            recordsByKey[record.key] = record
        }

        var index: [String: InventoryValuation] = [:]
        for key in Set(newest.keys).union(recordsByKey.keys) {
            index[key] = InventoryLedger.resolveValuation(
                observation: newest[key],
                record: recordsByKey[key]
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
        (try? coverageIndexThrowing(
            context: context,
            from: start,
            through: end,
            timeZone: timeZone
        )) ?? PortfolioCoverageIndex(checkedByDay: [:])
    }

    private static func coverageIndexThrowing(
        context: ModelContext,
        from start: Date,
        through end: Date,
        timeZone: TimeZone
    ) throws -> PortfolioCoverageIndex {
        // The last day the replay can close is the one containing `end`, so the
        // index has to reach that day's start.
        let lastDay = PortfolioCalendar.day(containing: end, in: timeZone)
        let descriptor = FetchDescriptor<PriceCheckDay>(
            predicate: #Predicate { $0.portfolioDay >= start && $0.portfolioDay <= lastDay }
        )
        let checks = try context.fetch(descriptor)

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
        // Seed observations for any instrument that has a usable price but no
        // local observation, before the replay reads them.
        //
        // Observations are device-local by design while `PriceRecord`s sync, so
        // a record arriving from another device values the collection — the
        // valuation index falls back to the record — while contributing no
        // price transition to the walk. The difference then surfaces as
        // Unexplained, which is a true statement about the walk but a false one
        // about the portfolio. Launch-time backfill alone left that gap open
        // for the whole session; running it here closes it on the pass that
        // would otherwise report the gap, and off the main actor, which is the
        // reason this type exists.
        // The log performs its absence check and initial fetch while holding a
        // process-wide backfill lock. That lock must cover the fetch itself;
        // fetching here first would let a second context carry a stale empty
        // snapshot into the critical section.
        let observations = PriceObservationLog(context: modelContext)
            .backfillFromRecordsAndReturnObservations()
        if observations.isEmpty {
            // An empty result may be a genuinely empty log or an unreadable
            // table. Let the builder perform its normal fetch so the latter is
            // surfaced as an `.unreadableStore` defect rather than hidden by an
            // explicitly supplied empty array.
            return PortfolioReplaySnapshotBuilder.compute(
                context: modelContext,
                epoch: epoch,
                through: through,
                timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
            )
        }

        return PortfolioReplaySnapshotBuilder.compute(
            context: modelContext,
            epoch: epoch,
            through: through,
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current,
            existingObservations: observations
        )
    }
}
