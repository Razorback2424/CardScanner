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

    private func observation(
        _ amount: Int64,
        at receivedAt: Date,
        instrument: String = "card",
        kind: PriceObservationKind = .marketUpdate
    ) -> ObservationEntry {
        ObservationEntry(
            id: UUID(), instrumentKey: instrument, kind: kind,
            amount: money(amount), receivedAt: receivedAt
        )
    }

    private func invalidation(at receivedAt: Date, instrument: String = "card") -> ObservationEntry {
        ObservationEntry(
            id: UUID(), instrumentKey: instrument, kind: .explicitInvalidation,
            amount: nil, receivedAt: receivedAt
        )
    }

    private func close(
        _ day: Int,
        value: Int64,
        revision: Int = 1,
        market: Int64 = 0,
        flow: Int64 = 0,
        added: Int64? = nil,
        removed: Int64? = nil,
        newlyAddedValue: Int64 = 0,
        coverage: PortfolioCoverageState = .complete,
        reason: PortfolioRevisionReason? = nil
    ) -> PortfolioPublishedClose {
        PortfolioPublishedClose(
            date: date(day), revision: revision, timeZoneIdentifier: "UTC",
            closeValue: money(value), market: money(market), flow: money(flow),
            corrections: .zero, newlyAddedValue: money(newlyAddedValue),
            pricingAdjustment: .zero, carriedForwardValue: .zero,
            coverage: coverage, refreshedInstrumentCount: 1,
            carriedForwardInstrumentCount: coverage == .partial ? 1 : 0,
            pricedPositionCount: 1, excludedCount: 0, revisionReason: reason,
            added: added.map { money($0) }, removed: removed.map { money($0) }
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
        // Performance factors come from the replay, the same way production
        // produces them — the history engine no longer walks history itself.
        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: events,
                observations: observations,
                epoch: closes.map(\.date).min() ?? now,
                through: now,
                timeZoneIdentifier: "UTC"
            )
        )
        return PortfolioHistoryInput(
            closes: closes,
            summary: PortfolioSummary(
                currentValue: money(currentValue), attribution: attribution,
                closeDate: closes.max { $0.date < $1.date }?.date,
                coverage: PortfolioCoverage(refreshed: 1, carriedForward: 0, state: .complete)
            ),
            epoch: closes.first?.date,
            timeZoneIdentifier: "UTC", now: now,
            factors: PortfolioPerformanceFactors(
                daily: Dictionary(
                    replay.days.compactMap { day in
                        day.performanceFactor.map { (day.displayDay, $0) }
                    },
                    uniquingKeysWith: { _, latest in latest }
                ),
                live: replay.live?.performanceFactor
            ),
            contributions: replay.contributionIndex
        )
    }

    func testContributionAggregationUsesTheAccountingIntervalNotTheAnchorDay() {
        let dayOne = date(1)
        let dayTwo = date(2)
        let result = PortfolioHistoryEngine.calculate(
            input: PortfolioHistoryInput(
                closes: [
                    close(1, value: 100, market: 100),
                    close(2, value: 130, market: 30)
                ],
                summary: PortfolioSummary(currentValue: money(130)),
                epoch: dayOne,
                timeZoneIdentifier: "UTC",
                now: dayTwo,
                contributions: PortfolioContributionIndex(
                    byDay: [dayOne: ["anchor": money(100)], dayTwo: ["card": money(30)]]
                )
            ),
            mode: .value,
            range: .all
        )

        XCTAssertEqual(result.accounting?.market, money(30))
        XCTAssertEqual(result.contributions, ["card": money(30)])
        XCTAssertEqual(result.accountingInterval?.includedClosedDays, [dayTwo])
    }

    func testPeriodChangeUsesTimeWeightedDollarsForPerformanceAndTotalForValue() throws {
        let accounting = PortfolioHistoryAccounting(
            anchorValue: money(100),
            endValue: money(107),
            market: money(-10),
            added: money(17),
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustments: .zero,
            unexplained: .zero
        )

        XCTAssertEqual(
            PortfolioHistoryDisplay.periodChange(
                for: .performance,
                accounting: accounting,
                performanceFactor: Decimal(string: "1.25")
            ),
            Optional(money(25))
        )
        XCTAssertEqual(
            PortfolioHistoryDisplay.periodChange(
                for: .value,
                accounting: accounting,
                performanceFactor: nil
            ),
            Optional(money(7))
        )

        let initial = event(quantity: 1, at: date(1, hour: 1))
        let inflow = event(quantity: 500, at: date(2, hour: 1))
        let inflowResult = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [
                    close(1, value: 100),
                    close(2, value: 55_110, market: 5_010, flow: 50_000)
                ],
                events: [initial, inflow],
                observations: [
                    observation(100, at: date(1, hour: 2)),
                    observation(110, at: date(2, hour: 2))
                ],
                currentValue: 55_110,
                now: date(3, hour: 1)
            ),
            mode: .performance,
            range: .all
        )

        XCTAssertEqual(inflowResult.accounting?.market, money(5_010))
        XCTAssertEqual(
            PortfolioHistoryDisplay.periodChange(
                for: .performance,
                accounting: try XCTUnwrap(inflowResult.accounting),
                performanceFactor: inflowResult.performanceFactor
            ),
            Optional(money(10))
        )
    }

    func testMarketMovementPeriodChangeUsesAccountingMarket() {
        let accounting = PortfolioHistoryAccounting(
            anchorValue: money(100),
            endValue: money(107),
            market: money(-17),
            added: money(24),
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustments: .zero,
            unexplained: .zero
        )

        XCTAssertEqual(
            PortfolioHistoryDisplay.periodChange(
                for: .marketMovement,
                accounting: accounting,
                performanceFactor: Decimal(string: "1.25")
            ),
            Optional(money(-17))
        )
    }

    func testHistoryAccountingSeparatesAddedAndRemovedValue() {
        var attribution = PortfolioClose.Attribution()
        attribution.added = money(500)
        attribution.removed = money(300)

        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100)],
                currentValue: 300,
                now: date(2, hour: 1),
                attribution: attribution
            ),
            mode: .value,
            range: .all
        )

        XCTAssertEqual(result.accounting?.added, money(500))
        XCTAssertEqual(result.accounting?.removed, money(300))
        XCTAssertEqual(result.accounting?.totalChange, money(200))
        XCTAssertEqual(result.accounting?.unexplained, .zero)
    }

    func testClosedClosePreservesAddedAndRemovedSides() throws {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [
                    close(1, value: 100),
                    close(2, value: 300, flow: 200, added: 500, removed: 300)
                ],
                currentValue: 300,
                now: date(3, hour: 1)
            ),
            mode: .value,
            range: .all
        )
        let accounting = try XCTUnwrap(result.accounting)

        XCTAssertEqual(accounting.added, money(500))
        XCTAssertEqual(accounting.removed, money(300))
        XCTAssertEqual(accounting.totalChange, money(200))
        XCTAssertEqual(accounting.unexplained, .zero)
    }

    func testMarketMovementSeriesStartsAtZeroAndEndsAtAccountingMarket() {
        var attribution = PortfolioClose.Attribution()
        attribution.market = money(3)
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [
                    close(1, value: 100, market: 100),
                    close(2, value: 110, market: 10),
                    close(3, value: 108, market: -2)
                ],
                currentValue: 111,
                now: date(4, hour: 1),
                attribution: attribution
            ),
            mode: .marketMovement,
            range: .all
        )

        XCTAssertEqual(
            result.points.map(\.cumulativeMarketMovement),
            [money(0), money(10), money(8), money(11)]
        )
        XCTAssertEqual(result.points.first?.cumulativeMarketMovement, .zero)
        XCTAssertEqual(result.accounting?.market, money(11))
        XCTAssertEqual(result.points.last?.cumulativeMarketMovement, result.accounting?.market)
    }

    func testMarketMovementRangesUseTheSameIntervalLogicAndContributorTotal() {
        let timeZoneID = "UTC"
        let now = zonedDay(2025, 12, 31, timeZoneID: timeZoneID).addingTimeInterval(60 * 60)
        let calendar = PortfolioCalendar.calendar(in: TimeZone(identifier: timeZoneID)!)
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }

        let closes = [
            close(at: day(-400), value: 100, timeZoneID: timeZoneID, market: 100),
            close(at: day(-370), value: 101, timeZoneID: timeZoneID, market: 1),
            close(at: day(-200), value: 103, timeZoneID: timeZoneID, market: 2),
            close(at: day(-100), value: 106, timeZoneID: timeZoneID, market: 3),
            close(at: day(-40), value: 110, timeZoneID: timeZoneID, market: 4),
            close(at: day(-20), value: 115, timeZoneID: timeZoneID, market: 5),
            close(at: day(-6), value: 121, timeZoneID: timeZoneID, market: 6),
            close(at: day(-1), value: 128, timeZoneID: timeZoneID, market: 7),
            close(at: day(0), value: 136, timeZoneID: timeZoneID, market: 8)
        ]
        let contributions = PortfolioContributionIndex(
            byDay: Dictionary(uniqueKeysWithValues: closes.map { ($0.date, ["market": $0.market]) })
        )
        let historyInput = PortfolioHistoryInput(
            closes: closes,
            summary: PortfolioSummary(currentValue: money(136)),
            epoch: closes.first?.date,
            timeZoneIdentifier: timeZoneID,
            now: now,
            contributions: contributions
        )

        let expectedMarkets: [(PortfolioHistoryRange, Int64)] = [
            (.oneWeek, 15),
            (.oneMonth, 21),
            (.threeMonths, 26),
            (.oneYear, 33),
            (.all, 36)
        ]

        for (range, expectedDollars) in expectedMarkets {
            let result = PortfolioHistoryEngine.calculate(
                input: historyInput,
                mode: .marketMovement,
                range: range
            )
            let expected = money(expectedDollars)

            XCTAssertEqual(result.accounting?.market, expected, "market total for \(range.rawValue)")
            XCTAssertEqual(result.points.first?.cumulativeMarketMovement, .zero)
            XCTAssertEqual(result.points.last?.cumulativeMarketMovement, expected)
            XCTAssertEqual(result.contributions["market"], expected, "contributors for \(range.rawValue)")
        }
    }

    func testInventoryActivityChangesPortfolioValueButNotMarketMovement() {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [
                    close(1, value: 100),
                    close(2, value: 50_100, flow: 50_000)
                ],
                currentValue: 50_100,
                now: date(2)
            ),
            mode: .marketMovement,
            range: .all
        )

        XCTAssertEqual(result.accounting?.totalChange, money(50_000))
        XCTAssertEqual(result.accounting?.added, money(50_000))
        XCTAssertEqual(result.accounting?.removed, .zero)
        XCTAssertEqual(result.accounting?.market, .zero)
        XCTAssertTrue(result.contributions.isEmpty)
    }

    func testAccountingAdjustmentsDoNotBecomeMarketContributors() {
        var adjustedClose = close(2, value: 110)
        adjustedClose.corrections = money(4)
        adjustedClose.newlyAddedValue = money(2)
        adjustedClose.pricingAdjustment = money(4)

        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100), adjustedClose],
                currentValue: 110,
                now: date(2)
            ),
            mode: .marketMovement,
            range: .all
        )

        XCTAssertEqual(result.accounting?.market, .zero)
        XCTAssertEqual(result.accounting?.corrections, money(4))
        XCTAssertEqual(result.accounting?.newlyAddedValue, money(2))
        XCTAssertEqual(result.accounting?.pricingAdjustments, money(4))
        XCTAssertEqual(result.accounting?.unexplained, .zero)
        XCTAssertTrue(result.contributions.isEmpty)
    }

    @MainActor
    func testLegacyPerformancePreferenceCannotRestorePrimaryHistoryMode() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "portfolioHistoryMode")
        defer {
            if let previous {
                defaults.set(previous, forKey: "portfolioHistoryMode")
            } else {
                defaults.removeObject(forKey: "portfolioHistoryMode")
            }
        }

        defaults.set(PortfolioHistoryMode.performance.rawValue, forKey: "portfolioHistoryMode")
        XCTAssertEqual(PortfolioHistoryStore().mode, .marketMovement)
    }

    func testNewlyAddedValueFlowsThroughHistoryWithoutBecomingPricingAdjustment() {
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [
                    close(1, value: 0),
                    close(2, value: 100, newlyAddedValue: 100)
                ],
                currentValue: 100,
                now: date(3, hour: 1)
            ),
            mode: .value,
            range: .all
        )

        XCTAssertEqual(result.accounting?.newlyAddedValue, money(100))
        XCTAssertEqual(result.accounting?.pricingAdjustments, .zero)
        XCTAssertEqual(result.accounting?.unexplained, .zero)
    }

    func testPerformanceDollarsScaleFactorFromAnchorValue() {
        XCTAssertEqual(
            PortfolioHistoryDisplay.performanceDollars(
                factor: Decimal(string: "1.25"),
                anchorValue: money(100)
            ),
            25
        )
    }

    func testZeroAnchorOmitsPerformancePercentageAndDollarScaling() {
        let accounting = PortfolioHistoryAccounting(
            anchorValue: .zero,
            endValue: money(10),
            market: money(10),
            added: .zero,
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustments: .zero,
            unexplained: .zero
        )

        XCTAssertNil(
            PortfolioHistoryDisplay.periodChange(
                for: .performance,
                accounting: accounting,
                performanceFactor: Decimal(string: "1.25")
            )
        )
        XCTAssertNil(
            PortfolioHistoryDisplay.percentChange(amount: money(10), anchor: .zero)
        )
        XCTAssertNil(
            PortfolioHistoryDisplay.performanceDollars(
                factor: Decimal(string: "1.25"),
                anchorValue: .zero
            )
        )
    }

    func testUnavailablePerformanceFactorProducesNoPeriodChange() {
        let accounting = PortfolioHistoryAccounting(
            anchorValue: money(100),
            endValue: money(100),
            market: .zero,
            added: .zero,
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustments: .zero,
            unexplained: .zero
        )

        XCTAssertNil(
            PortfolioHistoryDisplay.periodChange(
                for: .performance,
                accounting: accounting,
                performanceFactor: nil
            )
        )
    }

    func testBreakdownPolicyMatchesEveryDisclosureComponent() {
        let zero = PortfolioHistoryAccounting(
            anchorValue: money(100),
            endValue: money(100),
            market: .zero,
            added: .zero,
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustments: .zero,
            unexplained: .zero
        )
        XCTAssertFalse(PortfolioHistoryDisplay.hasBreakdown(zero))

        for component in [
            PortfolioHistoryAccounting(
                anchorValue: money(100), endValue: money(100), market: .zero,
                added: money(1), removed: .zero, corrections: .zero,
                newlyAddedValue: .zero,
                pricingAdjustments: .zero, unexplained: .zero
            ),
            PortfolioHistoryAccounting(
                anchorValue: money(100), endValue: money(100), market: .zero,
                added: .zero, removed: .zero, corrections: money(1),
                newlyAddedValue: .zero,
                pricingAdjustments: .zero, unexplained: .zero
            ),
            PortfolioHistoryAccounting(
                anchorValue: money(100), endValue: money(100), market: .zero,
                added: .zero, removed: .zero, corrections: .zero,
                newlyAddedValue: money(1),
                pricingAdjustments: .zero, unexplained: .zero
            ),
            PortfolioHistoryAccounting(
                anchorValue: money(100), endValue: money(100), market: .zero,
                added: .zero, removed: .zero, corrections: .zero,
                pricingAdjustments: money(1), unexplained: .zero
            ),
            PortfolioHistoryAccounting(
                anchorValue: money(100), endValue: money(100), market: .zero,
                added: .zero, removed: .zero, corrections: .zero,
                newlyAddedValue: .zero,
                pricingAdjustments: .zero, unexplained: money(1)
            )
        ] {
            XCTAssertTrue(PortfolioHistoryDisplay.hasBreakdown(component))
        }
    }

    func testCurrencyAxisPrecisionFollowsDomainSpan() {
        XCTAssertEqual(PortfolioHistoryDisplay.currencyFractionDigits(forSpan: 9.99), 2)
        XCTAssertEqual(PortfolioHistoryDisplay.currencyFractionDigits(forSpan: 10), 0)
        XCTAssertEqual(PortfolioHistoryDisplay.currencyFractionDigits(forSpan: 100), 0)
    }

    func testSignedDisplayLeavesZeroUnsigned() {
        XCTAssertEqual(
            PortfolioHistoryDisplay.signedCurrency(.zero),
            Money.zero.formatted()
        )
        XCTAssertEqual(
            PortfolioHistoryDisplay.signedPercent(0),
            0.0.formatted(.percent.precision(.fractionLength(2)))
        )
    }

    private func zonedDay(_ year: Int, _ month: Int, _ day: Int, timeZoneID: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func close(
        at displayDay: Date,
        value: Int64,
        revision: Int = 1,
        timeZoneID: String,
        market: Int64 = 0,
        flow: Int64 = 0
    ) -> PortfolioPublishedClose {
        PortfolioPublishedClose(
            date: displayDay, revision: revision, timeZoneIdentifier: timeZoneID,
            closeValue: money(value), market: money(market), flow: money(flow),
            corrections: .zero, pricingAdjustment: .zero, carriedForwardValue: .zero,
            coverage: .complete, refreshedInstrumentCount: 1,
            carriedForwardInstrumentCount: 0, pricedPositionCount: 1,
            excludedCount: 0, revisionReason: nil
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
        XCTAssertEqual(result.accounting?.added, money(50_000))
        XCTAssertEqual(result.accounting?.removed, .zero)
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

    func testNewlyAddedAssetParticipatesInSubsequentMarketReturns() {
        let assetA = event(quantity: 1, at: date(1, hour: 1), instrument: "a")
        let assetB = event(quantity: 1, at: date(2, hour: 1), instrument: "b")
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100), close(2, value: 160, market: 10, flow: 50)],
                events: [assetA, assetB],
                observations: [
                    observation(100, at: date(1, hour: 2), instrument: "a"),
                    observation(50, at: date(2, hour: 2), instrument: "b"),
                    observation(60, at: date(2, hour: 3), instrument: "b")
                ],
                currentValue: 160, now: date(3, hour: 1)
            ),
            mode: .performance, range: .all
        )

        XCTAssertEqual(result.performanceFactor, Decimal(string: "1.0666666666666667"))
    }

    func testNonMarketObservationKindsDoNotCreatePerformanceLinks() {
        let ownership = event(quantity: 1, at: date(1, hour: 1))
        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [close(1, value: 100), close(2, value: 100)],
                events: [ownership],
                observations: [
                    observation(100, at: date(1, hour: 2)),
                    observation(110, at: date(2, hour: 1), kind: .sourceRestatement),
                    observation(120, at: date(2, hour: 2), kind: .sourceTransition),
                    invalidation(at: date(2, hour: 3)),
                    observation(130, at: date(2, hour: 4))
                ],
                currentValue: 100, now: date(3, hour: 1)
            ),
            mode: .performance, range: .all
        )

        XCTAssertTrue(result.performanceAvailable)
        XCTAssertEqual(result.performanceFactor, Decimal(1))
    }

    func testSamePeriodUndoCollapsesButLaterReversalIsCorrection() {
        let original = event(quantity: 1, at: date(2, hour: 1))
        var samePeriodUndo = event(quantity: -1, at: date(2, hour: 2), operationID: UUID())
        samePeriodUndo.reversesEventID = original.eventID
        let collapsed = PortfolioClose.attribute(
            events: [original, samePeriodUndo], observations: [observation(10, at: date(1, hour: 1))],
            boundary: date(2), now: date(3), currentValue: .zero, includeEndpoint: false
        )
        XCTAssertEqual(collapsed.added, .zero)
        XCTAssertEqual(collapsed.corrections, .zero)

        var laterReversal = event(quantity: -1, at: date(4, hour: 1), operationID: UUID())
        laterReversal.reversesEventID = original.eventID
        let firstPeriod = PortfolioClose.attribute(
            events: [original, laterReversal], observations: [observation(10, at: date(1, hour: 1))],
            boundary: date(2), now: date(3), currentValue: money(10), includeEndpoint: false
        )
        let laterPeriod = PortfolioClose.attribute(
            events: [original, laterReversal], observations: [observation(10, at: date(1, hour: 1))],
            boundary: date(4), now: date(5), currentValue: .zero, includeEndpoint: false
        )
        XCTAssertEqual(firstPeriod.added, money(10))
        XCTAssertEqual(laterPeriod.corrections, money(-10))
        XCTAssertEqual(laterPeriod.added, .zero)
        XCTAssertEqual(laterPeriod.removed, .zero)
    }

    func testCrossMidnightUndoBelongsToNextClosedPeriod() {
        let original = event(quantity: 1, at: date(1, hour: 23))
        var undo = event(quantity: -1, at: date(2), operationID: UUID())
        undo.reversesEventID = original.eventID
        let observations = [observation(10, at: date(1, hour: 1))]

        let first = PortfolioClose.attribute(
            events: [original, undo], observations: observations,
            boundary: date(1), now: date(2), currentValue: money(10), includeEndpoint: false
        )
        let second = PortfolioClose.attribute(
            events: [original, undo], observations: observations,
            boundary: date(2), now: date(3), currentValue: .zero, includeEndpoint: false
        )

        XCTAssertEqual(first.added, money(10))
        XCTAssertEqual(first.corrections, .zero)
        XCTAssertEqual(second.corrections, money(-10))
    }

    func testCalendarRangeAndCloseInstantRespectDST() {
        let zone = "America/Denver"
        let march9 = zonedDay(2024, 3, 9, timeZoneID: zone)
        let march10 = zonedDay(2024, 3, 10, timeZoneID: zone)
        let march11 = zonedDay(2024, 3, 11, timeZoneID: zone)
        let springClose = close(at: march9, value: 100, timeZoneID: zone)
        let nextClose = close(at: march10, value: 100, timeZoneID: zone)

        XCTAssertEqual(springClose.instant, march10)
        XCTAssertEqual(nextClose.instant, march11)
        XCTAssertEqual(nextClose.instant.timeIntervalSince(springClose.instant), 23 * 60 * 60)

        let result = PortfolioHistoryEngine.calculate(
            input: input(
                closes: [springClose, nextClose], currentValue: 100,
                now: zonedDay(2024, 4, 10, timeZoneID: zone)
            ),
            mode: .value, range: .oneMonth
        )
        XCTAssertEqual(result.points.first?.displayDay, march10)
    }

    func testLiveEndpointIsNotDuplicatedAtCloseBoundary() {
        let closeBoundary = PortfolioCalendar.boundary(afterDay: date(2), in: TimeZone(secondsFromGMT: 0)!)
        let atBoundary = PortfolioHistoryEngine.calculate(
            input: input(closes: [close(1, value: 100), close(2, value: 110)], currentValue: 110, now: closeBoundary),
            mode: .value, range: .all
        )
        let afterBoundary = PortfolioHistoryEngine.calculate(
            input: input(closes: [close(1, value: 100), close(2, value: 110)], currentValue: 110, now: date(3, hour: 1)),
            mode: .value, range: .all
        )

        XCTAssertEqual(atBoundary.points.count, 2)
        XCTAssertEqual(afterBoundary.points.count, 3)
        XCTAssertTrue(afterBoundary.points.last?.isLive == true)
    }

    func testEmptyHistoryIsExplicitlyEmpty() {
        let empty = PortfolioHistoryEngine.calculate(
            input: input(closes: [], currentValue: 0, now: date(3)), mode: .value, range: .all
        )

        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.hasTwoPublishedPoints)
    }

    func testOneCloseAtItsOwnBoundaryPlotsExactlyOnePoint() {
        // `date(3)` *is* the economic instant of day 2's close. A live point
        // there would draw the same moment twice under two different labels.
        let atBoundary = PortfolioHistoryEngine.calculate(
            input: input(closes: [close(2, value: 100)], currentValue: 100, now: date(3)),
            mode: .value, range: .all
        )

        XCTAssertEqual(atBoundary.points.count, 1)
        XCTAssertEqual(atBoundary.points.first?.isLive, false)
        XCTAssertFalse(atBoundary.hasTwoPublishedPoints)
    }

    func testOneCloseGainsALivePointOnceTimeMovesPastTheBoundary() {
        // One hour later there is a genuinely distinct instant to plot, but
        // still only one *published* close — so the range picker stays
        // unavailable.
        let afterBoundary = PortfolioHistoryEngine.calculate(
            input: input(closes: [close(2, value: 100)], currentValue: 100, now: date(3, hour: 1)),
            mode: .value, range: .all
        )

        XCTAssertEqual(afterBoundary.points.count, 2)
        XCTAssertEqual(afterBoundary.points.last?.isLive, true)
        XCTAssertFalse(afterBoundary.hasTwoPublishedPoints)
    }

    func testContributionsAreScopedToTheSelectedHistoryRange() {
        let historyInput = PortfolioHistoryInput(
            closes: [
                close(1, value: 100),
                close(2, value: 112, market: 12),
                close(3, value: 112),
                close(4, value: 112)
            ],
            summary: PortfolioSummary(currentValue: money(112)),
            epoch: date(1),
            timeZoneIdentifier: "UTC",
            now: date(10),
            contributions: PortfolioContributionIndex(
                byDay: [date(2): ["card": money(12)]]
            )
        )
        let resultForThreeMonths = PortfolioHistoryEngine.calculate(
            input: historyInput,
            mode: .marketMovement,
            range: .threeMonths
        )
        let resultForOneWeek = PortfolioHistoryEngine.calculate(
            input: historyInput,
            mode: .marketMovement,
            range: .oneWeek
        )

        XCTAssertEqual(resultForThreeMonths.contributions, ["card": money(12)])
        XCTAssertTrue(resultForOneWeek.contributions.isEmpty)
        XCTAssertNotEqual(
            resultForThreeMonths.accountingInterval?.anchorDate,
            resultForOneWeek.accountingInterval?.anchorDate
        )
    }

    func testHistoryPointsUseTheSameLiveDayWindowAsAccounting() throws {
        let historyInput = PortfolioHistoryInput(
            closes: [
                close(1, value: 100),
                close(2, value: 100),
                close(3, value: 100),
                close(4, value: 100)
            ],
            summary: PortfolioSummary(currentValue: money(100)),
            epoch: date(1),
            timeZoneIdentifier: "UTC",
            now: date(10)
        )

        for range in PortfolioHistoryRange.allCases {
            let result = PortfolioHistoryEngine.calculate(
                input: historyInput,
                mode: .value,
                range: range
            )
            let interval = try XCTUnwrap(result.accountingInterval)
            let expectedDays = Set(
                interval.includedClosedDays
                    + (interval.includesLiveDay ? [interval.liveDay].compactMap { $0 } : [])
            )
            // The first point is the anchor close, not a contribution inside
            // the selected period. All later points must match the interval.
            let plottedDays = Set(result.points.dropFirst().map(\.displayDay))

            XCTAssertEqual(plottedDays, expectedDays, "range \(range.rawValue)")
            XCTAssertEqual(
                result.points.contains(where: \.isLive),
                interval.includesLiveDay,
                "range \(range.rawValue)"
            )
        }
    }

    func testShuffledInputsProduceIdenticalHistory() {
        let first = event(quantity: 1, at: date(2, hour: 1), instrument: "a")
        let second = event(quantity: 1, at: date(2, hour: 1), instrument: "b")
        let observations = [
            observation(10, at: date(1, hour: 1), instrument: "a"),
            observation(20, at: date(1, hour: 1), instrument: "b"),
            observation(11, at: date(2, hour: 2), instrument: "a"),
            observation(22, at: date(2, hour: 2), instrument: "b")
        ]
        let closes = [close(1, value: 0), close(2, value: 33)]
        let baseline = PortfolioHistoryEngine.calculate(
            input: input(closes: closes, events: [first, second], observations: observations, currentValue: 33, now: date(3)),
            mode: .performance, range: .all
        )
        let shuffled = PortfolioHistoryEngine.calculate(
            input: input(closes: closes.reversed(), events: [second, first], observations: observations.reversed(), currentValue: 33, now: date(3)),
            mode: .performance, range: .all
        )

        XCTAssertEqual(baseline, shuffled)
    }
}
