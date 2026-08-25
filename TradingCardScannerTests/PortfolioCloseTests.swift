import XCTest
@testable import TradingCardScanner

/// The accounting identity, exercised on the cases that decide whether the
/// numbers can be defended:
///
///     Unexplained = current − Close(D) − market − added + removed
///                   − corrections − pricingAdjustment
///
/// Every test here asserts `unexplained == .zero` exactly. Not within an
/// epsilon — the point of integer money is that the books balance or they do
/// not.
final class PortfolioCloseTests: XCTestCase {

    // MARK: - Factories

    private let instrument = "pokemon:sv08.5-074:reverse"
    private let position = "sv08.5-074#reverse"

    private func at(_ hours: Double) -> Date {
        // 2023-11-14 in UTC; the walk never cares which day, only about order.
        Date(timeIntervalSince1970: 1_699_920_000).addingTimeInterval(hours * 3600)
    }

    private func usd(_ dollars: Double) -> Money { Money(rounding: dollars) }

    private func event(
        kind: InventoryEventKind,
        delta: Int,
        at occurredAt: Date,
        position: String? = nil,
        instrument: String? = nil,
        price: Money? = nil,
        priceReceivedAt: Date? = nil,
        operationID: UUID = UUID(),
        leg: InventoryCorrectionLeg? = nil
    ) -> LedgerEntry {
        LedgerEntry(
            eventID: UUID(),
            operationID: operationID,
            leg: leg,
            kind: kind,
            occurredAt: occurredAt,
            recordedAt: occurredAt,
            collectionKey: position ?? self.position,
            priceStorageKey: instrument ?? self.instrument,
            deltaQuantity: delta,
            unitPrice: price,
            priceReceivedAtEvent: priceReceivedAt
        )
    }

    private func observation(
        _ amount: Money?,
        at receivedAt: Date,
        kind: PriceObservationKind = .marketUpdate,
        instrument: String? = nil
    ) -> ObservationEntry {
        ObservationEntry(
            id: UUID(),
            instrumentKey: instrument ?? self.instrument,
            kind: kind,
            amount: amount,
            receivedAt: receivedAt
        )
    }

    /// Runs a scenario and asserts the identity holds exactly, returning the
    /// attribution so a test can also state *which* line moved.
    @discardableResult
    private func attribute(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        boundary: Date,
        now: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PortfolioClose.Attribution {
        // Current value is measured independently, by replaying the whole
        // timeline to `now`. That is the same thing the collection itself would
        // report, and keeping it separate from the walk is what makes the
        // residual mean anything.
        let current = PortfolioClose.state(
            events: events,
            observations: observations,
            asOf: now.addingTimeInterval(1)
        ).value

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: now,
            currentValue: current
        )
        XCTAssertEqual(
            result.unexplained, .zero,
            "identity did not balance: \(result)",
            file: file, line: line
        )
        return result
    }

    // MARK: - Adding and removing are not performance

    func testAddingACardRaisesValueButNotMarketMovement() {
        // Case 1.
        let result = attribute(
            events: [event(kind: .acquire, delta: 1, at: at(30))],
            observations: [observation(usd(10), at: at(-5))],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.added, usd(10))
        XCTAssertEqual(result.currentValue, usd(10))
    }

    func testRemovingACardLowersValueButNotPerformance() {
        // Case 2.
        let result = attribute(
            events: [
                event(kind: .acquire, delta: 2, at: at(-10)),
                event(kind: .dispose, delta: -1, at: at(30))
            ],
            observations: [observation(usd(10), at: at(-11))],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.removed, usd(10))
        XCTAssertEqual(result.closeValue, usd(20))
        XCTAssertEqual(result.currentValue, usd(10))
    }

    func testVariantCorrectionIsCorrectionsNotMarketGain() {
        // Case 3. $8 recorded, really a $74 printing.
        let cheap = "instrument:cheap"
        let dear = "instrument:dear"
        let operationID = UUID()

        let result = attribute(
            events: [
                event(kind: .acquire, delta: 1, at: at(-10), position: "wrong", instrument: cheap),
                event(kind: .correction, delta: -1, at: at(30), position: "wrong", instrument: cheap, operationID: operationID, leg: .from),
                event(kind: .correction, delta: 1, at: at(30), position: "right", instrument: dear, operationID: operationID, leg: .to)
            ],
            observations: [
                observation(usd(8), at: at(-11), instrument: cheap),
                observation(usd(74), at: at(-11), instrument: dear)
            ],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.corrections, usd(66))
        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.removed, .zero)
    }

    // MARK: - Market movement scales with what is actually held

    func testMarketMovementMultipliesByQuantity() {
        // Case 4. Eight copies of one printing are one price and eight times
        // the movement.
        let result = attribute(
            events: [event(kind: .acquire, delta: 8, at: at(-10))],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(usd(11), at: at(30))
            ],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.market, usd(8))
    }

    func testOneObservationValuesEveryPositionSharingTheInstrument() {
        // Case 10. Three collection rows, one instrument — a raw copy recorded
        // three separate times still moves as three copies, once.
        let result = attribute(
            events: [
                event(kind: .acquire, delta: 1, at: at(-10), position: "a"),
                event(kind: .acquire, delta: 1, at: at(-10), position: "b"),
                event(kind: .acquire, delta: 1, at: at(-10), position: "c")
            ],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(usd(12), at: at(30))
            ],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.market, usd(6))
    }

    func testPartialIntradayDisposalMovesOnlyWhatIsStillHeld() {
        // Case 11, the scenario that broke the first draft. Ten at $10 close at
        // $100; five leave at noon; the price rises to $12 by 5 PM. The
        // afternoon's move applies to five copies, not ten — which no formula
        // over start-and-end states can see.
        let result = attribute(
            events: [
                event(kind: .acquire, delta: 10, at: at(-10)),
                event(kind: .dispose, delta: -5, at: at(36))
            ],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(usd(12), at: at(41))
            ],
            boundary: at(24),
            now: at(48)
        )

        XCTAssertEqual(result.closeValue, usd(100))
        XCTAssertEqual(result.removed, usd(50))
        XCTAssertEqual(result.market, usd(10))
        XCTAssertEqual(result.currentValue, usd(60))
    }

    func testIntradayAdditionThenMovement() {
        // Case 12. Added at $310, price ticks to $312.
        let result = attribute(
            events: [event(kind: .acquire, delta: 1, at: at(30))],
            observations: [
                observation(usd(310), at: at(29)),
                observation(usd(312), at: at(33))
            ],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.added, usd(310))
        XCTAssertEqual(result.market, usd(2))
        XCTAssertEqual(result.currentValue, usd(312))
    }

    // MARK: - Silence is not movement

    func testNoObservationsMeansZeroMarketMovement() {
        // Case 5. An outage cannot manufacture a gain: with no new value-setting
        // observation the running price never changes, so the market term is
        // exactly zero rather than approximately zero.
        let result = attribute(
            events: [event(kind: .acquire, delta: 4, at: at(-10))],
            observations: [observation(usd(37.13), at: at(-11))],
            boundary: at(24),
            now: at(48)
        )

        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.totalChange, .zero)
        XCTAssertEqual(result.currentValue, result.closeValue)
    }

    func testSuccessfulCheckWithAnUnchangedPriceMovesNothing() {
        // Case 13, from the walk's side: an unchanged price writes no
        // observation at all, so there is nothing here to move the total.
        let result = attribute(
            events: [event(kind: .acquire, delta: 3, at: at(-10))],
            observations: [observation(usd(4.25), at: at(-11))],
            boundary: at(24),
            now: at(48)
        )

        XCTAssertEqual(result.market, .zero)
    }

    // MARK: - Knowledge changing is not the market moving

    func testFirstEverPriceOnAnUnpricedPositionIsAPricingAdjustment() {
        // Case 16. A card added offline records no price and flows through as
        // `added $0`; the value arriving later is the app learning something,
        // not the card appreciating.
        let result = attribute(
            events: [event(kind: .acquire, delta: 1, at: at(26))],
            observations: [observation(usd(100), at: at(30))],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.pricingAdjustment, usd(100))
        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.currentValue, usd(100))
    }

    func testSourceRestatementIsAPricingAdjustmentNotAGain() {
        // Case 8, from the walk's side.
        let result = attribute(
            events: [event(kind: .acquire, delta: 2, at: at(-10))],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(usd(12), at: at(30), kind: .sourceRestatement)
            ],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.pricingAdjustment, usd(4))
    }

    func testExplicitInvalidationRemovesValueAsAPricingAdjustment() {
        // The only thing that can withdraw a price. It leaves through the
        // pricing line, never through performance.
        let result = attribute(
            events: [event(kind: .acquire, delta: 2, at: at(-10))],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(nil, at: at(30), kind: .explicitInvalidation)
            ],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.pricingAdjustment, usd(-20))
        XCTAssertEqual(result.currentValue, .zero)
    }

    // MARK: - Boundaries

    func testBackdatedArrivalAfterTheCutoffDoesNotMoveTheClose() {
        // Case 15. The provider's own clock precedes the boundary; knowledge
        // time does not. Close eligibility is governed by `receivedAt`, so
        // yesterday is untouched and the value lands today.
        let events = [event(kind: .acquire, delta: 1, at: at(-10))]
        let observations = [
            observation(usd(10), at: at(-11)),
            observation(usd(15), at: at(30))
        ]

        XCTAssertEqual(
            PortfolioClose.closeValue(events: events, observations: observations, boundary: at(24)),
            usd(10)
        )

        let result = attribute(
            events: events, observations: observations, boundary: at(24), now: at(36)
        )
        XCTAssertEqual(result.market, usd(5))
    }

    func testAnEventExactlyOnTheBoundaryBelongsToTheNewDay() {
        // Case 22. Half-open `[start, next)`: on the boundary is the next day's
        // first instant, counted once and only once.
        let result = attribute(
            events: [event(kind: .acquire, delta: 1, at: at(24))],
            observations: [observation(usd(10), at: at(-11))],
            boundary: at(24),
            now: at(36)
        )

        XCTAssertEqual(result.closeValue, .zero)
        XCTAssertEqual(result.added, usd(10))
    }

    // MARK: - Ordering (contract 6)

    func testSameTimestampResolvesFromTheEventsOwnValuationBasis() {
        // Case 21, both directions. An add and an observation at the identical
        // instant: if the event was priced *using* that observation, the
        // observation is processed first, so the new price is what the copy is
        // added at and the market term is zero. If it was not, the event goes
        // first and the observation moves the copy it just gained.
        let instant = at(30)

        let pricedFromIt = attribute(
            events: [
                event(kind: .acquire, delta: 1, at: instant, priceReceivedAt: instant)
            ],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(usd(20), at: instant)
            ],
            boundary: at(24),
            now: at(36)
        )
        XCTAssertEqual(pricedFromIt.added, usd(20))
        XCTAssertEqual(pricedFromIt.market, .zero)

        let pricedFromTheOldValue = attribute(
            events: [
                event(kind: .acquire, delta: 1, at: instant, priceReceivedAt: at(-11))
            ],
            observations: [
                observation(usd(10), at: at(-11)),
                observation(usd(20), at: instant)
            ],
            boundary: at(24),
            now: at(36)
        )
        XCTAssertEqual(pricedFromTheOldValue.added, usd(10))
        XCTAssertEqual(pricedFromTheOldValue.market, usd(10))
    }

    func testCorrectionLegsAreNeverInterleavedWithAnObservation() {
        // Contract 6.3. Both legs move at one price basis; a price landing
        // between them would value the outgoing identity before a change and
        // the incoming one after it.
        let cheap = "instrument:cheap"
        let dear = "instrument:dear"
        let operationID = UUID()
        let instant = at(30)

        let result = attribute(
            events: [
                event(kind: .acquire, delta: 1, at: at(-10), position: "wrong", instrument: cheap),
                event(kind: .correction, delta: -1, at: instant, position: "wrong", instrument: cheap, operationID: operationID, leg: .from),
                event(kind: .correction, delta: 1, at: instant, position: "right", instrument: dear, operationID: operationID, leg: .to)
            ],
            observations: [
                observation(usd(8), at: at(-11), instrument: cheap),
                observation(usd(74), at: at(-11), instrument: dear),
                observation(usd(80), at: instant, instrument: dear)
            ],
            boundary: at(24),
            now: at(36)
        )

        // The observation is not referenced by either leg's valuation basis, so
        // the legs go first: the correction is worth $74 − $8, and the $6 move
        // afterwards is market movement on the copy now held.
        XCTAssertEqual(result.corrections, usd(66))
        XCTAssertEqual(result.market, usd(6))
    }

    func testOrderingIsReproducibleAcrossShuffledInput() {
        // Contract 6.4. Never left to Swift's sort stability: the same inputs in
        // any order must produce byte-identical attribution.
        var events: [LedgerEntry] = []
        var observations: [ObservationEntry] = []
        for index in 0..<12 {
            events.append(event(kind: .acquire, delta: 1, at: at(Double(24 + index))))
            observations.append(observation(usd(Double(index) + 1.5), at: at(Double(24 + index))))
        }

        let reference = PortfolioClose.attribute(
            events: events, observations: observations,
            boundary: at(24), now: at(48), currentValue: .zero
        )

        var generator = SystemRandomNumberGenerator()
        for _ in 0..<25 {
            let shuffled = PortfolioClose.attribute(
                events: events.shuffled(using: &generator),
                observations: observations.shuffled(using: &generator),
                boundary: at(24), now: at(48), currentValue: .zero
            )
            XCTAssertEqual(shuffled, reference)
        }
    }

    // MARK: - The identity, under pressure

    func testSeededRandomisedSequenceBalancesExactly() {
        // Adds, removes, corrections, undos and price changes, in a seeded
        // order so any failure is exactly reproducible. Odd-cent prices
        // throughout: the residual has to be zero, not small.
        var generator = SeededGenerator(seed: 0xC0FFEE)
        let instruments = (0..<5).map { "instrument:\($0)" }
        let positions = (0..<7).map { "position:\($0)" }
        var instrumentOf: [String: String] = [:]
        for (index, position) in positions.enumerated() {
            instrumentOf[position] = instruments[index % instruments.count]
        }

        var events: [LedgerEntry] = []
        var observations: [ObservationEntry] = []
        var held: [String: Int] = [:]

        // An opening price for every instrument, before the boundary.
        for instrument in instruments {
            observations.append(
                observation(
                    Money(tenThousandths: Int64.random(in: 1_000...900_000, using: &generator)),
                    at: at(-20),
                    instrument: instrument
                )
            )
        }

        for step in 0..<400 {
            let moment = at(Double(step) * 0.25)
            let position = positions.randomElement(using: &generator)!
            let instrument = instrumentOf[position]!

            switch Int.random(in: 0..<10, using: &generator) {
            case 0...3:
                let quantity = Int.random(in: 1...4, using: &generator)
                held[position, default: 0] += quantity
                events.append(
                    event(kind: .acquire, delta: quantity, at: moment,
                          position: position, instrument: instrument)
                )
            case 4...5 where (held[position] ?? 0) > 0:
                let quantity = Int.random(in: 1...(held[position] ?? 1), using: &generator)
                held[position]! -= quantity
                events.append(
                    event(kind: .dispose, delta: -quantity, at: moment,
                          position: position, instrument: instrument)
                )
            case 6 where (held[position] ?? 0) > 0:
                let other = positions.randomElement(using: &generator)!
                guard other != position else { break }
                let operationID = UUID()
                held[position]! -= 1
                held[other, default: 0] += 1
                events.append(
                    event(kind: .correction, delta: -1, at: moment,
                          position: position, instrument: instrument,
                          operationID: operationID, leg: .from)
                )
                events.append(
                    event(kind: .correction, delta: 1, at: moment,
                          position: other, instrument: instrumentOf[other]!,
                          operationID: operationID, leg: .to)
                )
            default:
                observations.append(
                    observation(
                        Money(tenThousandths: Int64.random(in: 1...900_000, using: &generator)),
                        at: moment,
                        kind: Bool.random(using: &generator) ? .marketUpdate : .sourceRestatement,
                        instrument: instrument
                    )
                )
            }
        }

        attribute(events: events, observations: observations, boundary: at(10), now: at(200))
    }
}

/// A reproducible generator, so a failure in the randomised case is a failure
/// anyone can rerun.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
