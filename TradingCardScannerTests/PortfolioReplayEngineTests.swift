import XCTest
@testable import TradingCardScanner

/// The one-pass replay, and its equivalence with the engine it replaces.
///
/// Equivalence is asserted before anything is rewired, so the cutover is a
/// wiring change rather than a second redesign of the accounting.
final class PortfolioReplayEngineTests: XCTestCase {
    private let zoneID = "America/Denver"
    private var timeZone: TimeZone { TimeZone(identifier: zoneID)! }

    private func day(_ index: Int) -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = index
        return PortfolioCalendar.calendar(in: timeZone).date(from: components)!
    }

    private func at(_ index: Int, hour: Int) -> Date {
        day(index).addingTimeInterval(Double(hour) * 3600)
    }

    private func usd(_ dollars: Double) -> Money { Money(rounding: dollars)! }

    private func event(
        _ kind: InventoryEventKind = .acquire,
        delta: Int,
        at occurredAt: Date,
        position: String = "position",
        instrument: String = "instrument",
        priceReceivedAt: Date? = nil,
        operationID: UUID = UUID(),
        leg: InventoryCorrectionLeg? = nil,
        reverses: UUID? = nil,
        id: UUID = UUID()
    ) -> LedgerEntry {
        LedgerEntry(
            eventID: id, operationID: operationID, leg: leg, kind: kind,
            occurredAt: occurredAt, recordedAt: occurredAt, reversesEventID: reverses,
            collectionKey: position, priceStorageKey: instrument,
            deltaQuantity: delta, unitPrice: nil, priceReceivedAtEvent: priceReceivedAt
        )
    }

    private func observation(
        _ dollars: Double?,
        at receivedAt: Date,
        instrument: String = "instrument",
        kind: PriceObservationKind = .marketUpdate,
        id: UUID = UUID()
    ) -> ObservationEntry {
        ObservationEntry(
            id: id, instrumentKey: instrument, kind: kind,
            amount: dollars.map(usd), receivedAt: receivedAt
        )
    }

    private func input(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        coverage: PortfolioCoverageIndex = PortfolioCoverageIndex(),
        epoch: Date,
        through: Date
    ) -> PortfolioReplayInput {
        PortfolioReplayInput(
            events: events, observations: observations, coverage: coverage,
            epoch: epoch, through: through, timeZoneIdentifier: zoneID
        )
    }

    // MARK: - Equivalence with the engine being replaced

    /// The replay's still-open day must attribute exactly as
    /// `PortfolioClose.attribute` does over the same window.
    private func assertLiveMatchesLegacy(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        epoch: Date,
        boundary: Date,
        now: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = PortfolioReplayEngine.replay(
            input(events: events, observations: observations, epoch: epoch, through: now)
        )
        guard let live = result.live else {
            return XCTFail("replay produced no open day", file: file, line: line)
        }

        let legacy = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: now,
            currentValue: PortfolioClose.state(
                events: events, observations: observations, asOf: now.addingTimeInterval(1)
            ).value
        )

        XCTAssertEqual(live.attribution.closeValue, legacy.closeValue, "close", file: file, line: line)
        XCTAssertEqual(live.attribution.market, legacy.market, "market", file: file, line: line)
        XCTAssertEqual(live.attribution.added, legacy.added, "added", file: file, line: line)
        XCTAssertEqual(live.attribution.removed, legacy.removed, "removed", file: file, line: line)
        XCTAssertEqual(live.attribution.corrections, legacy.corrections, "corrections", file: file, line: line)
        XCTAssertEqual(
            live.attribution.newlyAddedValue, legacy.newlyAddedValue,
            "newly added value", file: file, line: line
        )
        XCTAssertEqual(
            live.attribution.pricingAdjustment, legacy.pricingAdjustment,
            "pricing adjustment", file: file, line: line
        )
        XCTAssertEqual(live.attribution.currentValue, legacy.currentValue, "current", file: file, line: line)
        XCTAssertEqual(live.attribution.unexplained, .zero, "unexplained", file: file, line: line)
    }

    func testPartialIntradayDisposalMatchesLegacyEngine() {
        let events = [
            event(delta: 10, at: at(1, hour: 9)),
            event(.dispose, delta: -5, at: at(3, hour: 12))
        ]
        let observations = [
            observation(10, at: at(1, hour: 8)),
            observation(12, at: at(3, hour: 17))
        ]
        assertLiveMatchesLegacy(
            events: events, observations: observations,
            epoch: at(1, hour: 0), boundary: day(3), now: at(3, hour: 20)
        )
    }

    func testIntradayAdditionThenMovementMatchesLegacyEngine() {
        assertLiveMatchesLegacy(
            events: [event(delta: 1, at: at(3, hour: 10))],
            observations: [observation(310, at: at(3, hour: 9)), observation(312, at: at(3, hour: 15))],
            epoch: at(1, hour: 0), boundary: day(3), now: at(3, hour: 20)
        )
    }

    func testCorrectionMatchesLegacyEngine() {
        let operationID = UUID()
        assertLiveMatchesLegacy(
            events: [
                event(delta: 1, at: at(1, hour: 9), position: "wrong", instrument: "cheap"),
                event(.correction, delta: -1, at: at(3, hour: 10), position: "wrong",
                      instrument: "cheap", operationID: operationID, leg: .from),
                event(.correction, delta: 1, at: at(3, hour: 10), position: "right",
                      instrument: "dear", operationID: operationID, leg: .to)
            ],
            observations: [
                observation(8, at: at(1, hour: 8), instrument: "cheap"),
                observation(74, at: at(1, hour: 8), instrument: "dear")
            ],
            epoch: at(1, hour: 0), boundary: day(3), now: at(3, hour: 20)
        )
    }

    func testFirstEverPriceMatchesLegacyEngine() {
        assertLiveMatchesLegacy(
            events: [event(delta: 1, at: at(3, hour: 9))],
            observations: [observation(100, at: at(3, hour: 14))],
            epoch: at(1, hour: 0), boundary: day(3), now: at(3, hour: 20)
        )
    }

    func testRestatementAndInvalidationMatchLegacyEngine() {
        assertLiveMatchesLegacy(
            events: [event(delta: 2, at: at(1, hour: 9))],
            observations: [
                observation(10, at: at(1, hour: 8)),
                observation(12, at: at(3, hour: 10), kind: .sourceRestatement),
                observation(nil, at: at(3, hour: 16), kind: .explicitInvalidation)
            ],
            epoch: at(1, hour: 0), boundary: day(3), now: at(3, hour: 20)
        )
    }

    func testSameTimestampBasisMatchesLegacyEngineInBothDirections() {
        let instant = at(3, hour: 11)
        for basis in [instant, at(1, hour: 8)] {
            assertLiveMatchesLegacy(
                events: [event(delta: 1, at: instant, priceReceivedAt: basis)],
                observations: [observation(10, at: at(1, hour: 8)), observation(20, at: instant)],
                epoch: at(1, hour: 0), boundary: day(3), now: at(3, hour: 20)
            )
        }
    }

    func testSeededRandomisedSequenceMatchesLegacyEngine() {
        var generator = SeededGenerator(seed: 0x5EED_1234)
        let instruments = (0..<4).map { "instrument:\($0)" }
        let positions = (0..<6).map { "position:\($0)" }
        var events: [LedgerEntry] = []
        var observations: [ObservationEntry] = []
        var held: [String: Int] = [:]

        for instrument in instruments {
            observations.append(
                observation(
                    Double(Int.random(in: 1...9_000, using: &generator)) / 100,
                    at: at(1, hour: 1), instrument: instrument
                )
            )
        }

        for step in 0..<300 {
            let moment = at(1, hour: 2).addingTimeInterval(Double(step) * 900)
            let index = Int.random(in: 0..<positions.count, using: &generator)
            let position = positions[index]
            let instrument = instruments[index % instruments.count]

            switch Int.random(in: 0..<10, using: &generator) {
            case 0...3:
                let quantity = Int.random(in: 1...4, using: &generator)
                held[position, default: 0] += quantity
                events.append(event(delta: quantity, at: moment, position: position, instrument: instrument))
            case 4...5 where (held[position] ?? 0) > 0:
                let quantity = Int.random(in: 1...(held[position] ?? 1), using: &generator)
                held[position]! -= quantity
                events.append(event(.dispose, delta: -quantity, at: moment, position: position, instrument: instrument))
            default:
                observations.append(
                    observation(
                        Double(Int.random(in: 1...9_000, using: &generator)) / 100,
                        at: moment, instrument: instrument
                    )
                )
            }
        }

        let boundary = day(2)
        assertLiveMatchesLegacy(
            events: events, observations: observations,
            epoch: at(1, hour: 0), boundary: boundary, now: at(2, hour: 23)
        )
    }

    // MARK: - What only the one-pass engine can do

    func testSharedInstrumentSplitsContributionAcrossPositionsExactly() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [
                    event(delta: 2, at: at(1, hour: 9), position: "a", instrument: "shared"),
                    event(delta: 3, at: at(1, hour: 9), position: "b", instrument: "shared")
                ],
                observations: [
                    observation(10, at: at(1, hour: 8), instrument: "shared"),
                    observation(15, at: at(2, hour: 10), instrument: "shared")
                ],
                epoch: at(1, hour: 0),
                through: at(2, hour: 20)
            )
        )

        XCTAssertEqual(result.live?.attribution.market, usd(25))
        XCTAssertEqual(result.live?.contributions["a"], usd(10))
        XCTAssertEqual(result.live?.contributions["b"], usd(15))
        XCTAssertEqual(result.live?.contributions.values.sum(), result.live?.attribution.market)
    }

    func testMovementDetailsPreserveUnitMovementAndAffectedQuantity() throws {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 3, at: at(1, hour: 9))],
                observations: [
                    observation(10, at: at(1, hour: 8)),
                    observation(9.95, at: at(2, hour: 10))
                ],
                epoch: at(1, hour: 0),
                through: at(2, hour: 20)
            )
        )

        let detail = try XCTUnwrap(result.live?.movementDetails["position"])
        XCTAssertEqual(detail.totalImpact, usd(-0.15))
        XCTAssertEqual(detail.cumulativeUnitMovement, usd(-0.05))
        XCTAssertEqual(detail.affectedQuantities, [3])
        XCTAssertEqual(result.live?.attribution.market, usd(-0.15))
    }

    func testMovementDetailsRefuseExactPerCardMathWhenQuantityChanges() throws {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [
                    event(delta: 3, at: at(1, hour: 9)),
                    event(.dispose, delta: -2, at: at(2, hour: 9))
                ],
                observations: [
                    observation(10, at: at(1, hour: 8)),
                    observation(9.95, at: at(2, hour: 8)),
                    observation(9.90, at: at(2, hour: 10))
                ],
                epoch: at(1, hour: 0),
                through: at(2, hour: 20)
            )
        )

        let detail = try XCTUnwrap(result.live?.movementDetails["position"])
        XCTAssertEqual(detail.totalImpact, usd(-0.20))
        XCTAssertEqual(detail.cumulativeUnitMovement, usd(-0.10))
        XCTAssertEqual(detail.affectedQuantities, [1, 3])
        XCTAssertFalse(detail.hasConsistentQuantity)
    }

    func testOffsettingContributorsRemainVisibleAtZeroNetMarketMovement() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [
                    event(delta: 1, at: at(1, hour: 9), position: "a", instrument: "a"),
                    event(delta: 1, at: at(1, hour: 9), position: "b", instrument: "b")
                ],
                observations: [
                    observation(100, at: at(1, hour: 8), instrument: "a"),
                    observation(100, at: at(1, hour: 8), instrument: "b"),
                    observation(150, at: at(2, hour: 10), instrument: "a"),
                    observation(50, at: at(2, hour: 10), instrument: "b")
                ],
                epoch: at(1, hour: 0),
                through: at(2, hour: 20)
            )
        )

        XCTAssertEqual(result.live?.attribution.market, .zero)
        XCTAssertEqual(result.live?.contributions, ["a": usd(50), "b": usd(-50)])
        XCTAssertFalse(result.live?.contributions.isEmpty ?? true)
        XCTAssertTrue(result.live?.hasEligibleMarketMovement ?? false)
    }

    func testCancelledUpdatesForOnePositionRetainTheEligibleMovementState() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 1, at: at(1, hour: 9))],
                observations: [
                    observation(100, at: at(1, hour: 8)),
                    observation(150, at: at(2, hour: 10)),
                    observation(100, at: at(2, hour: 11))
                ],
                epoch: at(1, hour: 0),
                through: at(2, hour: 20)
            )
        )

        XCTAssertEqual(result.live?.attribution.market, .zero)
        XCTAssertTrue(result.live?.contributions.isEmpty ?? false)
        XCTAssertTrue(result.live?.hasEligibleMarketMovement ?? false)
        XCTAssertTrue(result.contributionIndex.daysWithEligibleMarketMovement.contains(day(2)))
    }

    func testNonMarketUpdatesNeverCreateContributions() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 1, at: at(1, hour: 9))],
                observations: [
                    observation(10, at: at(1, hour: 8)),
                    observation(30, at: at(2, hour: 10), kind: .sourceRestatement),
                    observation(40, at: at(2, hour: 11), kind: .sourceTransition)
                ],
                epoch: at(1, hour: 0),
                through: at(2, hour: 20)
            )
        )

        XCTAssertEqual(result.live?.attribution.market, .zero)
        XCTAssertTrue(result.live?.contributions.isEmpty ?? false)
    }

    func testEveryDayFromTheEpochIsEmittedOnce() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 1, at: at(1, hour: 9))],
                observations: [observation(10, at: at(1, hour: 8))],
                epoch: at(1, hour: 0),
                through: at(5, hour: 12)
            )
        )

        XCTAssertEqual(result.days.map(\.displayDay), [day(1), day(2), day(3), day(4)])
        XCTAssertEqual(result.live?.day, day(5))
        // Carry-forward is free: no new observation means no market movement.
        XCTAssertEqual(result.days.last?.market, .zero)
        XCTAssertEqual(result.days.last?.closeValue, usd(10))
    }

    func testDaysAreHalfOpenSoABoundaryEntryOpensTheNextDay() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 1, at: day(3))],
                observations: [observation(10, at: at(1, hour: 8))],
                epoch: at(1, hour: 0),
                through: at(3, hour: 12)
            )
        )

        XCTAssertEqual(result.days.first { $0.displayDay == day(2) }?.closeValue, .zero)
        XCTAssertEqual(result.live?.attribution.added, usd(10))
    }

    func testCoverageComesFromTheIndexRatherThanFromPriceMovement() {
        // A confirmed-unchanged price is coverage but not news, so the day has
        // an observation-free market of zero and still reads as refreshed.
        let index = PortfolioCoverageIndex(checkedByDay: [day(2): ["instrument"]])
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 1, at: at(1, hour: 9))],
                observations: [observation(10, at: at(1, hour: 8))],
                coverage: index,
                epoch: at(1, hour: 0),
                through: at(3, hour: 12)
            )
        )

        let checked = result.days.first { $0.displayDay == day(2) }
        let notChecked = result.days.first { $0.displayDay == day(1) }
        XCTAssertEqual(checked?.coverage.state, .complete)
        XCTAssertEqual(checked?.coverage.refreshed, 1)
        XCTAssertEqual(checked?.carriedForwardValue, .zero)
        XCTAssertEqual(notChecked?.coverage.state, .partial)
        XCTAssertEqual(notChecked?.carriedForwardValue, usd(10))
    }

    func testDailyPerformanceFactorsChainAcrossDays() {
        let result = PortfolioReplayEngine.replay(
            input(
                events: [event(delta: 1, at: at(1, hour: 9))],
                observations: [
                    observation(100, at: at(1, hour: 8)),
                    observation(110, at: at(2, hour: 10)),
                    observation(121, at: at(3, hour: 10))
                ],
                epoch: at(1, hour: 0),
                through: at(3, hour: 20)
            )
        )

        XCTAssertEqual(result.days.first { $0.displayDay == day(2) }?.performanceFactor, Decimal(11) / Decimal(10))
        XCTAssertEqual(result.live?.performanceFactor, Decimal(11) / Decimal(10))
        XCTAssertTrue(result.performanceAvailable)
    }

    func testShuffledInputProducesIdenticalReplay() {
        var events: [LedgerEntry] = []
        var observations: [ObservationEntry] = []
        for index in 0..<10 {
            events.append(event(delta: 1, at: at(2, hour: index), position: "p\(index)"))
            observations.append(observation(Double(index) + 1.25, at: at(2, hour: index)))
        }
        let baseline = PortfolioReplayEngine.replay(
            input(events: events, observations: observations, epoch: at(1, hour: 0), through: at(3, hour: 5))
        )

        var generator = SeededGenerator(seed: 99)
        for _ in 0..<20 {
            let shuffled = PortfolioReplayEngine.replay(
                input(
                    events: events.shuffled(using: &generator),
                    observations: observations.shuffled(using: &generator),
                    epoch: at(1, hour: 0), through: at(3, hour: 5)
                )
            )
            XCTAssertEqual(shuffled, baseline)
        }
    }

    // MARK: - High cardinality

    /// Gate 14: a year of high-cardinality history behaves exactly like a small
    /// one. The invariant is per day — each close is the previous close plus
    /// everything the day claims happened — so a replay that drifts anywhere in
    /// 365 days fails here rather than in someone's portfolio.
    func testYearLongHighCardinalityReplayBalancesEveryDay() {
        var generator = SeededGenerator(seed: 0xA11CE)
        let instrumentCount = 200
        let dayCount = 365
        var events: [LedgerEntry] = []
        var observations: [ObservationEntry] = []
        var checkedByDay: [Date: Set<String>] = [:]

        let epoch = day(1)
        for index in 0..<instrumentCount {
            events.append(
                event(.initialBalance, delta: Int.random(in: 1...9, using: &generator),
                      at: epoch, position: "pos\(index)", instrument: "inst\(index)")
            )
            observations.append(
                observation(Double(Int.random(in: 25...900_00, using: &generator)) / 100,
                            at: epoch, instrument: "inst\(index)")
            )
        }

        var cursor = epoch
        for _ in 0..<dayCount {
            var checked: Set<String> = []
            // A realistic day: most instruments checked, a minority actually
            // moving, and the occasional flow.
            for index in 0..<instrumentCount where Int.random(in: 0..<10, using: &generator) < 8 {
                checked.insert("inst\(index)")
                if Int.random(in: 0..<4, using: &generator) == 0 {
                    observations.append(
                        observation(
                            Double(Int.random(in: 25...900_00, using: &generator)) / 100,
                            at: cursor.addingTimeInterval(3600 + Double(index)),
                            instrument: "inst\(index)"
                        )
                    )
                }
            }
            if Int.random(in: 0..<3, using: &generator) == 0 {
                let index = Int.random(in: 0..<instrumentCount, using: &generator)
                events.append(
                    event(delta: 1, at: cursor.addingTimeInterval(7200),
                          position: "pos\(index)", instrument: "inst\(index)")
                )
            }
            checkedByDay[cursor] = checked
            cursor = PortfolioCalendar.boundary(afterDay: cursor, in: timeZone)
        }

        let result = PortfolioReplayEngine.replay(
            input(
                events: events, observations: observations,
                coverage: PortfolioCoverageIndex(checkedByDay: checkedByDay),
                epoch: epoch, through: cursor.addingTimeInterval(3600)
            )
        )

        XCTAssertEqual(result.days.count, dayCount)

        var previousClose = Money.zero
        for replayDay in result.days {
            let claimed = replayDay.market
                + replayDay.added
                - replayDay.removed
                + replayDay.corrections
                + replayDay.newlyAddedValue
                + replayDay.pricingAdjustment
            XCTAssertEqual(
                replayDay.closeValue - previousClose, claimed,
                "day \(replayDay.displayDay) does not reconcile"
            )
            previousClose = replayDay.closeValue
        }

        // And coverage came from the index, not from whether prices moved.
        XCTAssertTrue(result.days.contains { $0.coverage.state == .partial })
    }

    func testSpringForwardDayStillClosesAtMidnight() {
        // 2025-03-09 in Denver is 23 hours long.
        var components = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = 9
        let springDay = PortfolioCalendar.calendar(in: timeZone).date(from: components)!
        let result = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: [event(delta: 1, at: springDay.addingTimeInterval(3600))],
                observations: [observation(10, at: springDay)],
                epoch: springDay,
                through: springDay.addingTimeInterval(48 * 3600),
                timeZoneIdentifier: zoneID
            )
        )

        let first = result.days.first
        XCTAssertEqual(first?.displayDay, springDay)
        XCTAssertEqual(first?.boundary.timeIntervalSince(springDay), 23 * 3600)
    }
}
