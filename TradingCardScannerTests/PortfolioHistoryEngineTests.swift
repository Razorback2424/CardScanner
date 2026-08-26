import XCTest
@testable import TradingCardScanner

final class PortfolioHistoryEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour))!
    }

    private func money(_ dollars: Int64) -> Money {
        Money(tenThousandths: dollars * Money.scale)
    }

    private func event(
        _ kind: InventoryEventKind = .acquire,
        quantity: Int,
        at occurredAt: Date,
        priceReceivedAt: Date? = nil,
        operationID: UUID = UUID(),
        instrument: String = "card"
    ) -> LedgerEntry {
        LedgerEntry(
            eventID: UUID(), operationID: operationID, leg: nil, kind: kind,
            occurredAt: occurredAt, recordedAt: occurredAt, reversesEventID: nil,
            collectionKey: UUID().uuidString, priceStorageKey: instrument,
            deltaQuantity: quantity, unitPrice: nil, priceReceivedAtEvent: priceReceivedAt
        )
    }

    private func observation(_ amount: Int64, at receivedAt: Date, instrument: String = "card") -> ObservationEntry {
        ObservationEntry(
            id: UUID(), instrumentKey: instrument, kind: .marketUpdate,
            amount: money(amount), receivedAt: receivedAt
        )
    }

    private func close(
        _ day: Int,
        value: Int64,
        revision: Int = 1,
        market: Int64 = 0,
        flow: Int64 = 0,
        coverage: PortfolioCoverageState = .complete,
        reason: PortfolioRevisionReason? = nil
    ) -> PortfolioPublishedClose {
        PortfolioPublishedClose(
            date: date(day), revision: revision, timeZoneIdentifier: "UTC",
            closeValue: money(value), market: money(market), flow: money(flow),
            corrections: .zero, pricingAdjustment: .zero, carriedForwardValue: .zero,
            coverage: coverage, refreshedInstrumentCount: 1,
            carriedForwardInstrumentCount: coverage == .partial ? 1 : 0,
            pricedPositionCount: 1, excludedCount: 0, revisionReason: reason
        )
    }

    private func input(
        closes: [PortfolioPublishedClose],
        events: [LedgerEntry] = [],
        observations: [ObservationEntry] = [],
        currentValue: Int64,
        now: Date,
        attribution: PortfolioClose.Attribution? = nil
    ) -> PortfolioHistoryInput {
        PortfolioHistoryInput(
            closes: closes, events: events, observations: observations,
            summary: PortfolioSummary(
                currentValue: money(currentValue), attribution: attribution,
                closeDate: closes.max { $0.date < $1.date }?.date,
                coverage: PortfolioCoverage(refreshed: 1, carriedForward: 0, state: .complete)
            ),
            epoch: closes.first?.date,
            timeZoneIdentifier: "UTC", now: now
        )
    }

    func testClosedPeriodsExcludeEndingMidnightAndNextPeriodIncludesItOnce() {
        let midnightEvent = event(quantity: 1, at: date(2))
        let first = PortfolioClose.attribute(
            events: [midnightEvent], observations: [observation(10, at: date(1))],
            boundary: date(1), now: date(2), currentValue: .zero,
            includeEndpoint: false
        )
        let second = PortfolioClose.attribute(
            events: [midnightEvent], observations: [observation(10, at: date(1))],
            boundary: date(2), now: date(3), currentValue: money(10),
            includeEndpoint: false
        )

        XCTAssertEqual(first.added, .zero)
        XCTAssertEqual(second.added, money(10))
        XCTAssertEqual(
            PortfolioClose.state(events: [midnightEvent], observations: [], asOf: date(3)).quantities.values.reduce(0, +),
            1
        )
    }

    func testLargeInventoryFlowChangesValueButNotPerformance() {
        let events = [event(quantity: 500, at: date(2, hour: 1))]
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100), close(2, value: 50_100, flow: 50_000)],
                events: events, observations: [observation(100, at: date(1, hour: 1))],
                currentValue: 50_100, now: date(3, hour: 1)
            ),
            mode: .performance, range: .all
        )

        XCTAssertEqual(result.points.last?.value, money(50_100))
        XCTAssertEqual(result.performanceFactor, Decimal(1))
        XCTAssertEqual(result.accounting?.netInventoryActivity, money(50_000))
    }

    func testChainedMarketReturnsMultiply() {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100), close(2, value: 110, market: 10), close(3, value: 121, market: 11)],
                events: [event(quantity: 1, at: date(1, hour: 1))],
                observations: [
                    observation(100, at: date(1)),
                    observation(110, at: date(2)),
                    observation(121, at: date(3))
                ],
                currentValue: 121, now: date(4, hour: 1)
            ),
            mode: .performance, range: .all
        )

        XCTAssertEqual(result.performanceFactor, Decimal(string: "1.21"))
    }

    func testZeroDenominatorMakesPerformanceUnavailable() {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 0), close(2, value: 10, market: 10)],
                events: [event(quantity: 1, at: date(1, hour: 1))],
                observations: [observation(0, at: date(1)), observation(10, at: date(2))],
                currentValue: 10, now: date(3, hour: 1)
            ),
            mode: .performance, range: .all
        )

        XCTAssertFalse(result.performanceAvailable)
        XCTAssertNil(result.performanceFactor)
    }

    func testLatestRevisionIsTheOnlyChartPointAndAuditRetainsOriginal() {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [
                    close(1, value: 100),
                    close(2, value: 110, revision: 1),
                    close(2, value: 115, revision: 2, reason: .lateInventoryTruth),
                    close(3, value: 120)
                ],
                currentValue: 120, now: date(3)
            ),
            mode: .value, range: .all
        )

        XCTAssertEqual(result.points.filter { !$0.isLive }.map(\.value), [money(100), money(115), money(120)])
        XCTAssertEqual(result.revisions.count, 1)
        XCTAssertEqual(result.revisions.first?.original.closeValue, money(110))
        XCTAssertEqual(result.revisions.first?.latest.closeValue, money(115))
    }

    func testAnchorContributionsAreExcludedAndResidualIsVisible() {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100, market: 100), close(2, value: 120, market: 20)],
                currentValue: 120, now: date(2)
            ),
            mode: .value, range: .all
        )

        XCTAssertEqual(result.accounting?.market, money(20))
        XCTAssertEqual(result.accounting?.totalChange, money(20))
        XCTAssertEqual(result.accounting?.unexplained, .zero)
    }
}
