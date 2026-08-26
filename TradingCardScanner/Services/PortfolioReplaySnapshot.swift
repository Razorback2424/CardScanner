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
@MainActor
enum PortfolioReplaySnapshotBuilder {

    struct Snapshot {
        var input: PortfolioReplayInput
        /// Straight from the ledger read plus the projection: whether anything
        /// derived from this snapshot may be published as history.
        var isAuthoritative: Bool
        var defects: [LedgerIntegrityDefect]
        var projection: LogicalCollectionProjection
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
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)

        let events = reading.events.map(PortfolioEngine.entry(from:))
        let observations = PortfolioEngine.observations(in: context)

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
            isAuthoritative: reading.isAuthoritative && projection.defects.isEmpty,
            defects: reading.defects + projection.defects,
            projection: projection
        )
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
