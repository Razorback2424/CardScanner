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
            PortfolioEpoch.establishIfNeeded(context: context, defaults: defaults, at: now),
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

        _ = PortfolioEngine.publish(
            closesUpTo: lastDay,
            epoch: epochDay.addingTimeInterval(30),
            events: [event],
            observations: [price],
            timeZone: zone,
            context: context
        )

        let closes = PortfolioEngine.allCloses(in: context)
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

        let events = InventoryLedger(context: context).allEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.deltaQuantity, 1)
        XCTAssertTrue(
            LedgerIntegrityLog.shared.defects.contains {
                $0.reason == .conflictingPayloadForIdempotencyKey
            }
        )
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
                fetchedAt: .now
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .explicitInvalidation,
                amount: nil,
                source: .justTCG,
                sourceVariantID: "v",
                marketVariantID: nil,
                effectiveAt: .now,
                receivedAt: .now,
                isSourceStamped: false
            )
        )
        try context.save()

        XCTAssertNil(InventoryLedger(context: context).valuation(forPriceKey: "instrument").unitPrice)
    }
}
