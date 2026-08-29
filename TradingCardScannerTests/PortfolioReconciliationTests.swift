import XCTest
import SwiftData
@testable import TradingCardScanner

/// Container-backed reconciliation cases: local knowledge time, missed close
/// publication, CloudKit-style duplicate rows, invalidation, and explicit undo
/// semantics. These are the contracts most likely to pass pure accounting tests
/// while failing in a real store.
@MainActor
final class PortfolioReconciliationTests: XCTestCase {
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let syncedSchema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self
        ])
        let localSchema = Schema([
            PriceObservation.self,
            PriceCheckDay.self,
            PortfolioDailyClose.self
        ])
        let fullSchema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self,
            PriceObservation.self,
            PriceCheckDay.self,
            PortfolioDailyClose.self
        ])
        let container = try ModelContainer(
            for: fullSchema,
            configurations: [
                ModelConfiguration(
                    "TestSynced",
                    schema: syncedSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
                ModelConfiguration(
                    "TestPortfolioLocal",
                    schema: localSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        LedgerIntegrityLog.shared.clear()
        super.tearDown()
    }

    private func money(_ dollars: Double) -> Money { Money(rounding: dollars)! }

    private func entry(
        id: UUID = UUID(),
        operationID: UUID = UUID(),
        kind: InventoryEventKind,
        delta: Int,
        at date: Date,
        reversesEventID: UUID? = nil,
        priceReceivedAt: Date? = nil,
        position: String = "position",
        instrument: String = "instrument"
    ) -> LedgerEntry {
        LedgerEntry(
            eventID: id,
            operationID: operationID,
            leg: nil,
            kind: kind,
            occurredAt: date,
            recordedAt: date,
            reversesEventID: reversesEventID,
            collectionKey: position,
            priceStorageKey: instrument,
            deltaQuantity: delta,
            unitPrice: nil,
            priceReceivedAtEvent: priceReceivedAt
        )
    }

    private func observation(
        _ dollars: Double,
        at date: Date,
        instrument: String = "instrument"
    ) -> ObservationEntry {
        ObservationEntry(
            id: UUID(),
            instrumentKey: instrument,
            kind: .marketUpdate,
            amount: money(dollars),
            receivedAt: date
        )
    }

    private func card(
        key: String = "position",
        quantity: Int = 1,
        dateAdded: Date = .now
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: key,
            game: .pokemon,
            providerID: key,
            name: "Portfolio Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .imported,
            quantity: quantity,
            dateAdded: dateAdded
        )
    }

    private func csvEntry(key: String, quantity: Int) -> CollectionCSVEntry {
        CollectionCSVEntry(
            collectionKey: key,
            game: .pokemon,
            providerID: key,
            name: "Portfolio Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            importedMarketPriceUSD: nil,
            importedPriceAsOf: nil,
            quantity: quantity,
            dateAdded: Date(timeIntervalSince1970: 500)
        )
    }

    // MARK: - Duplicate physical rows for one logical position
    //
    // Two devices adding the same card offline each pass their own local
    // uniqueness check, so one `collectionKey` legitimately arrives as two
    // stored rows. Every part of the app that answers "how many do I own" has
    // to answer from the sum.

    func testDuplicatePhysicalRowsProjectToOneSummedPosition() throws {
        let context = try makeContext()
        context.insert(card(key: "dupe", quantity: 1, dateAdded: Date(timeIntervalSince1970: 100)))
        context.insert(card(key: "dupe", quantity: 2, dateAdded: Date(timeIntervalSince1970: 900)))
        try context.save()

        let ledger = InventoryLedger(context: context)
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)

        XCTAssertEqual(projection.positions.count, 1)
        XCTAssertEqual(projection.byKey["dupe"]?.quantity, 3)
        XCTAssertEqual(projection.byKey["dupe"]?.physicalRowCount, 2)
        // The oldest acquisition represents the position; the newest is what
        // "recently added" should mean for it.
        XCTAssertEqual(
            projection.byKey["dupe"]?.representative.dateAdded,
            Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(projection.byKey["dupe"]?.dateAdded, Date(timeIntervalSince1970: 900))
    }

    func testMigrationBaselinesDuplicateRowsAsOneEventWithTheSummedQuantity() throws {
        // The bug this exists to stop: iterating physical rows gave both rows
        // the same deterministic baseline id, so one was deduplicated away and
        // the ledger opened at 1 instead of 3 — or, with differing quantities,
        // collided as an idempotency conflict and opened at neither.
        let context = try makeContext()
        context.insert(card(key: "dupe", quantity: 1, dateAdded: Date(timeIntervalSince1970: 100)))
        context.insert(card(key: "dupe", quantity: 2, dateAdded: Date(timeIntervalSince1970: 900)))
        try context.save()

        let defaults = UserDefaults(suiteName: "PortfolioEpochTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        try PortfolioEpoch.establishIfNeeded(context: context, defaults: defaults)

        let ledger = InventoryLedger(context: context)
        let events = ledger.allEvents()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .initialBalance)
        XCTAssertEqual(events.first?.deltaQuantity, 3)

        // And the ledger now agrees with the collection, which is the whole
        // point of the assertion this feature ships.
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)
        let defects = PortfolioEngine.reconcile(
            projection: projection,
            events: events.map(PortfolioEngine.entry(from:))
        )
        XCTAssertEqual(defects, [])
    }

    func testCSVImportAgainstDuplicateRowsMergesOnceInsteadOfTrapping() throws {
        // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, so this
        // previously crashed rather than importing.
        let context = try makeContext()
        context.insert(card(key: "dupe", quantity: 1, dateAdded: Date(timeIntervalSince1970: 100)))
        context.insert(card(key: "dupe", quantity: 2, dateAdded: Date(timeIntervalSince1970: 900)))
        try context.save()

        let plan = CollectionCSVImportPlan(
            entries: [csvEntry(key: "dupe", quantity: 4)],
            skippedRows: 0,
            skippedCSVText: nil
        )
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.insertedEntries, 0)

        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let projection = LogicalCollection.project(
            cards: cards,
            ledger: InventoryLedger(context: context)
        )
        // Three owned plus four imported, counted exactly once.
        XCTAssertEqual(projection.byKey["dupe"]?.quantity, 7)
        XCTAssertEqual(projection.positions.count, 1)
    }

    // MARK: - Undo semantics

    func testSamePeriodAddAndUndoCollapseForAttribution() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let originalID = UUID()
        let events = [
            entry(id: originalID, kind: .acquire, delta: 1, at: boundary.addingTimeInterval(60)),
            entry(kind: .acquire, delta: -1, at: boundary.addingTimeInterval(180), reversesEventID: originalID)
        ]
        let observations = [
            observation(100, at: boundary.addingTimeInterval(-60)),
            observation(120, at: boundary.addingTimeInterval(120))
        ]

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: boundary.addingTimeInterval(300),
            currentValue: .zero
        )

        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.corrections, .zero)
        XCTAssertEqual(result.unexplained, .zero)
    }

    func testSamePeriodRemoveAndUndoBehaveAsThoughTemporaryRemovalNeverHappened() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let removalID = UUID()
        let events = [
            entry(kind: .initialBalance, delta: 1, at: boundary.addingTimeInterval(-120)),
            entry(id: removalID, kind: .dispose, delta: -1, at: boundary.addingTimeInterval(60)),
            entry(kind: .dispose, delta: 1, at: boundary.addingTimeInterval(180), reversesEventID: removalID)
        ]
        let observations = [
            observation(100, at: boundary.addingTimeInterval(-60)),
            observation(120, at: boundary.addingTimeInterval(120))
        ]

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: boundary.addingTimeInterval(300),
            currentValue: money(120)
        )

        XCTAssertEqual(result.removed, .zero)
        XCTAssertEqual(result.corrections, .zero)
        XCTAssertEqual(result.market, money(20))
        XCTAssertEqual(result.unexplained, .zero)
    }

    func testReversingPublishedOperationIsCurrentPeriodCorrection() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let originalID = UUID()
        let events = [
            entry(id: originalID, kind: .acquire, delta: 1, at: boundary.addingTimeInterval(-120)),
            entry(kind: .acquire, delta: -1, at: boundary.addingTimeInterval(120), reversesEventID: originalID)
        ]
        let observations = [
            observation(100, at: boundary.addingTimeInterval(-60)),
            observation(120, at: boundary.addingTimeInterval(60))
        ]

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: boundary.addingTimeInterval(300),
            currentValue: .zero
        )

        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.market, money(20))
        XCTAssertEqual(result.corrections, money(-120))
        XCTAssertEqual(result.unexplained, .zero)
    }

    // MARK: - Ordering

    func testMixedSameTimestampUsesOldBasisThenObservationThenNewBasis() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let instant = boundary.addingTimeInterval(60)
        let old = entry(
            kind: .acquire, delta: 1, at: instant,
            priceReceivedAt: boundary.addingTimeInterval(-60),
            position: "old"
        )
        let new = entry(
            kind: .acquire, delta: 1, at: instant,
            priceReceivedAt: instant,
            position: "new"
        )
        let observations = [
            observation(10, at: boundary.addingTimeInterval(-60)),
            observation(20, at: instant)
        ]

        let result = PortfolioClose.attribute(
            events: [new, old],
            observations: observations,
            boundary: boundary,
            now: instant.addingTimeInterval(60),
            currentValue: money(40)
        )

        XCTAssertEqual(result.added, money(30))
        XCTAssertEqual(result.market, money(10))
        XCTAssertEqual(result.unexplained, .zero)
    }

    func testQuantityAdjustIsCorrectionNotAdded() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let result = PortfolioClose.attribute(
            events: [entry(kind: .quantityAdjust, delta: 2, at: boundary.addingTimeInterval(60))],
            observations: [observation(15, at: boundary.addingTimeInterval(-60))],
            boundary: boundary,
            now: boundary.addingTimeInterval(120),
            currentValue: money(30)
        )
        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.corrections, money(30))
        XCTAssertEqual(result.unexplained, .zero)
    }

    // MARK: - Local knowledge and publication

    func testFailedEpochSaveDoesNotMarkTrackingEstablishedAndRetries() throws {
        enum ExpectedFailure: Error { case save }

        let context = try makeContext()
        let defaultsName = #function
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: now.addingTimeInterval(-86_400)))
        try context.save()

        XCTAssertThrowsError(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: now,
                save: { _ in throw ExpectedFailure.save }
            )
        )
        XCTAssertNil(PortfolioEpoch.startedAt(context: context, defaults: defaults))
        XCTAssertTrue(InventoryLedger(context: context).allEvents().isEmpty)

        XCTAssertEqual(
            try PortfolioEpoch.establishIfNeeded(context: context, defaults: defaults, at: now),
            now
        )
        XCTAssertEqual(InventoryLedger(context: context).allEvents().count, 1)
    }

    func testBackfillUsesWhenThisDeviceLearnedSyncedPrice() throws {
        let context = try makeContext()
        let remoteFetch = Date(timeIntervalSince1970: 1_900_000_000)
        let localLearned = remoteFetch.addingTimeInterval(7 * 86_400)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v",
                sourceUpdatedAt: remoteFetch,
                fetchedAt: remoteFetch
            )
        )
        context.insert(record)
        try context.save()

        XCTAssertEqual(
            PriceObservationLog(context: context).backfillFromRecords(receivedAt: localLearned),
            1
        )
        XCTAssertEqual(
            PriceObservationLog(context: context).newestObservation(instrumentKey: "instrument")?.receivedAt,
            localLearned
        )
    }

    func testSyncedOwnershipEpochDoesNotBackdateLocalKnowledgeEpoch() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        let old = Date(timeIntervalSince1970: 1_900_000_000)
        let now = old.addingTimeInterval(20 * 86_400)
        context.insert(
            InventoryEvent(
                operationID: UUID(), leg: nil, kind: .initialBalance, source: .catalog,
                collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
                occurredAt: old, valuation: .unpriced
            )
        )
        try context.save()

        XCTAssertNil(PortfolioEpoch.startedAt(context: context, defaults: defaults))
        XCTAssertEqual(
            try PortfolioEpoch.establishIfNeeded(context: context, defaults: defaults, at: now),
            now
        )
    }

    func testPublisherMaterializesEveryMissedDayWithHistoricalCoverage() throws {
        let context = try makeContext()
        let zone = TimeZone(secondsFromGMT: 0)!
        let calendar = PortfolioCalendar.calendar(in: zone)
        let epochDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let event = entry(kind: .initialBalance, delta: 1, at: epochDay.addingTimeInterval(60))
        let price = observation(100, at: epochDay.addingTimeInterval(120))
        context.insert(
            PriceCheckDay(
                instrumentKey: "instrument",
                portfolioDay: epochDay,
                lastSuccessfulCheckAt: epochDay.addingTimeInterval(180),
                source: .justTCG
            )
        )

        try context.save()

        // Through the replay and the real storage adapter, so the bulk coverage
        // fetch is exercised rather than a hand-built index.
        let through = PortfolioCalendar.boundary(afterDay: lastDay, in: zone)
        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: [event],
                observations: [price],
                coverage: PortfolioReplaySnapshotBuilder.coverageIndex(
                    context: context, from: epochDay, through: through, timeZone: zone
                ),
                epoch: epochDay.addingTimeInterval(30),
                through: through,
                timeZoneIdentifier: zone.identifier
            )
        )
        _ = PortfolioEngine.publish(replay.days, timeZone: zone, context: context)

        let closes = try PortfolioEngine.allCloses(in: context)
        XCTAssertEqual(closes.count, 7)
        XCTAssertEqual(closes.first?.coverageState, .complete)
        XCTAssertEqual(closes.first?.carriedForwardValue, .zero)
        XCTAssertEqual(closes.last?.coverageState, .partial)
        XCTAssertEqual(closes.last?.carriedForwardValue, money(100))
    }

    // MARK: - Read-side idempotency and invalidation

    func testReadSideCanonicalizesCloudKitDuplicatesAndSurfacesConflicts() throws {
        let context = try makeContext()
        let operationID = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let first = InventoryEvent(
            operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: date, valuation: .unpriced
        )
        first.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let identical = InventoryEvent(
            operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: date, valuation: .unpriced
        )
        identical.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let conflict = InventoryEvent(
            operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 2,
            occurredAt: date, valuation: .unpriced
        )
        conflict.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        context.insert(first)
        context.insert(identical)
        context.insert(conflict)
        try context.save()

        let reading = InventoryLedger(context: context).read()

        // Two of the three rows are equivalent retries and collapse. The third
        // describes a different change under the same leg identity, so no row
        // from that group is counted — counting the lowest UUID would decide
        // the portfolio total by sort order.
        XCTAssertEqual(reading.events.count, 0)
        XCTAssertFalse(reading.isAuthoritative)
        XCTAssertEqual(reading.defects.map(\.reason), [.conflictingPayloadForIdempotencyKey])
    }

    func testConflictingLedgerRowsPauseHistoryWithoutHidingCurrentValue() async throws {
        let context = try makeContext()
        let operationID = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        for (index, delta) in [1, 2].enumerated() {
            let event = InventoryEvent(
                operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
                collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: delta,
                occurredAt: date, valuation: .unpriced
            )
            event.eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!
            context.insert(event)
        }
        context.insert(card(key: "position", quantity: 1))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date.addingTimeInterval(86_400 * 2))

        guard let summary = engine.summary else { return XCTFail("no summary") }
        XCTAssertFalse(summary.isAuthoritative)
        XCTAssertTrue(summary.defects.contains { $0.reason == .conflictingPayloadForIdempotencyKey })
        // Paused, not published: no close may be written from a reading the
        // app already knows is untrustworthy.
        XCTAssertNil(summary.attribution)
        XCTAssertEqual(try PortfolioEngine.allCloses(in: context).count, 0)
    }

    func testLedgerProjectionMismatchAlsoPausesPublication() async throws {
        // The ledger says one copy, the collection holds three. Today already
        // surfaced this; now it also stops the app publishing a close it has
        // just proved it cannot support.
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(
            InventoryEvent(
                operationID: UUID(), leg: nil, kind: .acquire, source: .catalog,
                collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
                occurredAt: date, valuation: .unpriced
            )
        )
        context.insert(card(key: "position", quantity: 3))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date.addingTimeInterval(86_400 * 2))

        guard let summary = engine.summary else { return XCTFail("no summary") }
        XCTAssertFalse(summary.isAuthoritative)
        XCTAssertTrue(
            summary.defects.contains {
                $0.reason == .quantityMismatch && $0.detail == "ledger 1, collection 3"
            }
        )
        XCTAssertNil(summary.attribution)
        XCTAssertEqual(try PortfolioEngine.allCloses(in: context).count, 0)
    }

    func testQuantityRepairAppendsOneAdjustmentPerMismatchedPosition() throws {
        let context = try makeContext()
        let first = card(key: "repair-one", quantity: 3)
        let second = card(key: "repair-two", quantity: 2)
        context.insert(first)
        context.insert(second)
        let ledger = InventoryLedger(context: context)
        let firstOperationID = UUID()
        _ = ledger.record(
            first,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: firstOperationID
        )
        let secondOperationID = UUID()
        _ = ledger.record(
            second,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: secondOperationID
        )
        context.insert(
            CollectionActivity(
                card: first,
                source: .scan,
                quantity: 1,
                ledgerOperationIDs: [firstOperationID]
            )
        )
        context.insert(
            CollectionActivity(
                card: second,
                source: .scan,
                quantity: 1,
                ledgerOperationIDs: [secondOperationID]
            )
        )
        try context.save()

        let defects = [first, second].map {
            LedgerIntegrityDefect(
                reason: .quantityMismatch,
                collectionKey: $0.collectionKey,
                detail: "ledger 1, collection \($0.quantity)"
            )
        }
        try CollectionStore.repairQuantityMismatches(defects, in: context)

        let events = try ledger.allEventsThrowing()
        let adjustments = events.filter { $0.kind == .quantityAdjust }
        XCTAssertEqual(adjustments.count, 2)
        XCTAssertEqual(Set(adjustments.map(\.operationID)).count, 2)
        XCTAssertEqual(InventoryLedger.quantities(from: events)[first.collectionKey], 3)
        XCTAssertEqual(InventoryLedger.quantities(from: events)[second.collectionKey], 2)
        XCTAssertEqual(first.quantity, 3)
        XCTAssertEqual(second.quantity, 2)
    }

    func testQuantityRepairRejectsMixedDefectsWithoutMutation() throws {
        let context = try makeContext()
        let owned = card(key: "repair-mixed", quantity: 2)
        context.insert(owned)
        let ledger = InventoryLedger(context: context)
        _ = ledger.record(
            owned,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: UUID()
        )
        try context.save()
        let defects = [
            LedgerIntegrityDefect(
                reason: .quantityMismatch,
                collectionKey: owned.collectionKey,
                detail: "ledger 1, collection 2"
            ),
            LedgerIntegrityDefect(
                reason: .orphanedCorrectionLeg,
                collectionKey: owned.collectionKey,
                detail: "missing correction leg"
            )
        ]

        XCTAssertThrowsError(
            try CollectionStore.repairQuantityMismatches(defects, in: context)
        )
        XCTAssertEqual(try ledger.allEventsThrowing().count, 1)
        XCTAssertEqual(owned.quantity, 2)
    }

    func testEquivalentBaselineDuplicatesCanonicalizeToEarliestOwnershipTime() throws {
        let context = try makeContext()
        let operationID = PortfolioEpoch.baselineOperationID(collectionKey: "position")
        let earlier = Date(timeIntervalSince1970: 2_000_000_000)
        let later = earlier.addingTimeInterval(86_400)

        let firstKnown = InventoryEvent(
            operationID: operationID, leg: nil, kind: .initialBalance, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: earlier, valuation: .unpriced
        )
        firstKnown.eventID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let laterRandomWinner = InventoryEvent(
            operationID: operationID, leg: nil, kind: .initialBalance, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: later, valuation: .unpriced
        )
        laterRandomWinner.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        context.insert(firstKnown)
        context.insert(laterRandomWinner)
        try context.save()

        let events = InventoryLedger(context: context).allEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventID, firstKnown.eventID)
        XCTAssertEqual(events.first?.occurredAt, earlier)
        XCTAssertFalse(
            LedgerIntegrityLog.shared.defects.contains {
                $0.reason == .conflictingPayloadForIdempotencyKey
            }
        )
    }

    // MARK: - CSV integration

    func testCSVImportedPriceAttributesValueToAddedNotPricingAdjustment() throws {
        let context = try makeContext()
        let plan = CollectionCSVImportPlan(
            entries: [
                CollectionCSVEntry(
                    collectionKey: "csv-position",
                    game: .pokemon,
                    providerID: "csv-printing",
                    name: "Imported Collection",
                    setName: "Imported Set",
                    setCode: "CSV",
                    cardNumber: "7",
                    rarity: nil,
                    imageURL: nil,
                    thumbnailURL: nil,
                    variant: nil,
                    importedMarketPriceUSD: 7_000,
                    importedPriceAsOf: Date(timeIntervalSince1970: 1_900_000_000),
                    quantity: 1,
                    dateAdded: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            skippedRows: 0,
            skippedCSVText: nil
        )

        _ = try CollectionCSV.apply(plan, to: context)

        let events = InventoryLedger(context: context).allEvents().map(PortfolioEngine.entry(from:))
        let observations = try PortfolioEngine.observations(in: context)
        let eventTime = try XCTUnwrap(events.first?.occurredAt)
        XCTAssertEqual(observations.first?.receivedAt, eventTime)
        XCTAssertEqual(events.first?.priceReceivedAtEvent, eventTime)

        let attribution = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: eventTime.addingTimeInterval(-1),
            now: eventTime.addingTimeInterval(1),
            currentValue: money(7_000)
        )

        XCTAssertEqual(attribution.added, money(7_000))
        XCTAssertEqual(attribution.pricingAdjustment, .zero)
        XCTAssertEqual(attribution.market, .zero)
        XCTAssertEqual(attribution.unexplained, .zero)
    }

    func testExplicitInvalidationCannotFallBackToMutablePriceRecord() throws {
        let context = try makeContext()
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        context.insert(record)
        let invalidatedAt = Date(timeIntervalSince1970: 2_000)
        _ = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: "instrument",
                source: .justTCG,
                at: invalidatedAt
            )
        )
        try context.save()

        XCTAssertNil(InventoryLedger(context: context).valuation(forPriceKey: "instrument").unitPrice)
        XCTAssertNil(record.unitMarketPriceUSD)
        XCTAssertEqual(record.invalidatedAt, invalidatedAt)
    }

    func testInvalidationMirrorsIntoCollectionReadPathAndBlocksLegacyFallback() throws {
        let context = try makeContext()
        let card = CollectedCard(
            collectionKey: "collection",
            game: .pokemon,
            providerID: "printing",
            name: "Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .imported
        )
        card.itemKindRaw = CollectionItemKind.sealedProduct.rawValue
        card.justTCGVariantID = "market-variant"
        card.justTCGAPIVersion = "v1"
        let canonical = PriceRecord(
            key: card.priceKey,
            game: .pokemon,
            printingID: card.priceStorageID,
            variantID: card.variantID
        )
        canonical.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "wrong-listing",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        context.insert(card)
        context.insert(canonical)
        let legacyKey = try XCTUnwrap(card.legacyPriceKeys.first)
        let legacy = PriceRecord(
            key: legacyKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: card.variantID
        )
        legacy.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 99,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "legacy-listing",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        context.insert(legacy)
        try context.save()

        let invalidatedAt = Date(timeIntervalSince1970: 200)
        let invalidation = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: canonical.key,
                source: .justTCG,
                at: invalidatedAt
            )
        )
        try context.save()

        let visible = PriceStore.record(
            for: card,
            in: [canonical.key: canonical, legacy.key: legacy]
        )
        XCTAssertEqual(invalidation.kind, .explicitInvalidation)
        XCTAssertTrue(canonical.isInvalidated)
        XCTAssertTrue(legacy.effectiveUnitMarketPriceUSD != nil)
        XCTAssertTrue(visible === canonical)
        XCTAssertNil(visible?.unitMarketPriceUSD)
        XCTAssertNil(visible?.display.amount)
        XCTAssertEqual(canonical.invalidatedAt, invalidatedAt)
    }

    func testInvalidationStillWinsOverNewerUnusableObservationInScalarAndBulkReads() throws {
        let context = try makeContext()
        let recordDate = Date(timeIntervalSince1970: 100)
        let invalidatedAt = Date(timeIntervalSince1970: 200)
        let laterObservationAt = Date(timeIntervalSince1970: 300)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "wrong-listing",
                sourceUpdatedAt: nil,
                fetchedAt: recordDate
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(42),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "wrong-listing",
                marketVariantID: nil,
                effectiveAt: recordDate,
                receivedAt: recordDate,
                isSourceStamped: false
            )
        )
        try context.save()

        _ = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: "instrument",
                source: .justTCG,
                at: invalidatedAt
            )
        )
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(99),
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "foreign-listing",
                marketVariantID: nil,
                effectiveAt: laterObservationAt,
                receivedAt: laterObservationAt,
                isSourceStamped: true
            )
        )
        try context.save()

        let scalar = InventoryLedger(context: context).valuation(forPriceKey: "instrument")
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )

        XCTAssertNil(scalar.unitPrice)
        XCTAssertNil(bulk.valuation(for: "instrument").unitPrice)
    }

    func testNewerUSDObservationCanArriveAfterInvalidationWatermark() throws {
        let context = try makeContext()
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "old-listing",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        _ = record.invalidate(at: Date(timeIntervalSince1970: 200))
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(99),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new-listing",
                marketVariantID: nil,
                effectiveAt: Date(timeIntervalSince1970: 300),
                receivedAt: Date(timeIntervalSince1970: 300),
                isSourceStamped: true
            )
        )
        try context.save()

        let scalar = InventoryLedger(context: context).valuation(forPriceKey: "instrument")
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )

        XCTAssertEqual(scalar.unitPrice, money(99))
        XCTAssertEqual(bulk.valuation(for: "instrument").unitPrice, money(99))
    }

    func testFreshPriceReplacesAnInvalidationButStalePriceCannot() throws {
        let context = try makeContext()
        let key = PriceRecord.key(game: .pokemon, printingID: "p", variantID: "normal")
        let initial = Date(timeIntervalSince1970: 100)
        let invalidatedAt = Date(timeIntervalSince1970: 200)
        let store = PriceStore(context: context)

        store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 42,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "old-listing",
                    sourceUpdatedAt: nil,
                    fetchedAt: initial
                )
            ),
            game: .pokemon,
            printingID: "p",
            variantID: "normal",
            at: initial
        )
        let record = try XCTUnwrap(store.record(forKey: key))
        _ = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: key,
                source: .justTCG,
                at: invalidatedAt
            )
        )

        store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 7,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "stale-listing",
                    sourceUpdatedAt: nil,
                    fetchedAt: initial
                )
            ),
            game: .pokemon,
            printingID: "p",
            variantID: "normal",
            at: initial
        )
        XCTAssertTrue(record.isInvalidated)
        XCTAssertNil(record.unitMarketPriceUSD)
        XCTAssertNil(InventoryLedger(context: context).valuation(forPriceKey: key).unitPrice)
        XCTAssertEqual(
            PriceObservationLog(context: context).observations(instrumentKey: key).count,
            2,
            "a response received before invalidation must not append stale value evidence"
        )

        let fresh = invalidatedAt.addingTimeInterval(1)
        store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 9,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "new-listing",
                    sourceUpdatedAt: nil,
                    fetchedAt: fresh
                )
            ),
            game: .pokemon,
            printingID: "p",
            variantID: "normal",
            at: fresh
        )

        XCTAssertFalse(record.isInvalidated)
        XCTAssertEqual(record.unitMarketPriceUSD, 9)
        XCTAssertEqual(PriceObservationLog(context: context).observations(instrumentKey: key).count, 3)
        XCTAssertEqual(InventoryLedger(context: context).valuation(forPriceKey: key).unitPrice, money(9))
    }

    func testOlderInvalidationCannotWithdrawAFreshPrice() throws {
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        let fresh = Date(timeIntervalSince1970: 300)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 9,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new-listing",
                sourceUpdatedAt: nil,
                fetchedAt: fresh
            )
        )

        XCTAssertFalse(record.invalidate(at: Date(timeIntervalSince1970: 200)))
        XCTAssertFalse(record.isInvalidated)
        XCTAssertEqual(record.unitMarketPriceUSD, 9)
    }

    func testScalarAndBulkValuationFallBackFromNewerNonUSDObservationToUSDRecord() throws {
        let context = try makeContext()
        let recordDate = Date(timeIntervalSince1970: 1_700_000_000)
        let observationDate = recordDate.addingTimeInterval(60)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "usd-listing",
                sourceUpdatedAt: recordDate,
                fetchedAt: recordDate
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(99),
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "eur-listing",
                marketVariantID: nil,
                effectiveAt: observationDate,
                receivedAt: observationDate,
                isSourceStamped: true
            )
        )
        try context.save()

        let scalar = InventoryLedger(context: context).valuation(forPriceKey: "instrument")
        let observations = try context.fetch(FetchDescriptor<PriceObservation>())
        let records = try context.fetch(FetchDescriptor<PriceRecord>())
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: observations,
            records: records
        )

        XCTAssertEqual(scalar.unitPrice, money(42))
        XCTAssertEqual(scalar.source, .justTCG)
        XCTAssertEqual(bulk.valuation(for: "instrument"), scalar)
    }
}
