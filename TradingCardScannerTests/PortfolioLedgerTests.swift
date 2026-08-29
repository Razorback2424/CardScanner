import XCTest
@testable import TradingCardScanner

/// The foundation the portfolio ledger stands on: exact money, the rules that
/// decide when a provider answer is worth recording and what it means, day
/// boundaries, and the separation of "we checked" from "we got a price".
final class PortfolioLedgerTests: XCTestCase {

    // MARK: - Factories

    private func value(
        amount: Money? = Money(rounding: 42)!,
        currency: String = "USD",
        source: PriceSource = .justTCG,
        sourceVariantID: String? = "v1",
        marketVariantID: String? = "m1"
    ) -> PriceObservationValue {
        PriceObservationValue(
            amount: amount,
            currencyCode: currency,
            sourceRaw: source.rawValue,
            sourceVariantID: sourceVariantID,
            marketVariantID: marketVariantID
        )
    }

    private func candidate(
        value: PriceObservationValue? = nil,
        source: PriceSource = .justTCG,
        sourceUpdatedAt: Date?,
        receivedAt: Date
    ) -> PriceObservationRules.Candidate {
        PriceObservationRules.Candidate(
            value: value ?? self.value(source: source),
            source: source,
            sourceUpdatedAt: sourceUpdatedAt,
            receivedAt: receivedAt
        )
    }

    private func previous(
        value: PriceObservationValue? = nil,
        effectiveAt: Date,
        receivedAt: Date? = nil,
        isSourceStamped: Bool = true
    ) -> PriceObservationRules.Previous {
        PriceObservationRules.Previous(
            value: value ?? self.value(),
            effectiveAt: effectiveAt,
            receivedAt: receivedAt ?? effectiveAt,
            isSourceStamped: isSourceStamped
        )
    }

    private func date(_ offsetHours: Double) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(offsetHours * 3600)
    }

    // MARK: - Money is exact

    func testOddCentSequenceReconcilesToExactlyZero() {
        // Case 24. The prices and quantities here all round badly in binary
        // floating point; the identity has to land on zero, not near it.
        let prices = [4.07, 0.19, 13.33, 99.99, 0.01, 7.77, 1234.56, 0.03]
        let quantities = [3, 17, 1, 8, 401, 5, 2, 999]

        var total = Money.zero
        for (price, quantity) in zip(prices, quantities) {
            total += Money(rounding: price)! * quantity
        }

        var unwound = total
        for (price, quantity) in zip(prices, quantities) {
            unwound -= Money(rounding: price)! * quantity
        }

        XCTAssertEqual(unwound, .zero)
        XCTAssertEqual(unwound.tenThousandths, 0)
    }

    func testDoubleSummationOfTheSameSequenceDoesNotReachZero() {
        // The reason `Money` exists rather than a tolerance on `Double`.
        let prices = [0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07]
        let doubleTotal = prices.reduce(0, +) - 0.7
        let moneyTotal = prices.compactMap { Money(rounding: $0) }.sum() - Money(rounding: 0.7)!

        XCTAssertNotEqual(doubleTotal, 0)
        XCTAssertEqual(moneyTotal, .zero)
    }

    func testRoundingIsHalfAwayFromZeroAtTheStoredScale() {
        XCTAssertEqual(Money(rounding: 0.00005)!.tenThousandths, 1)
        XCTAssertEqual(Money(rounding: -0.00005)!.tenThousandths, -1)
        XCTAssertEqual(Money(rounding: 42)!.tenThousandths, 420_000)
        XCTAssertEqual(Money(rounding: 1234.5678)!.tenThousandths, 12_345_678)
    }

    func testNonsenseProviderValuesDoNotTrapThePricingPipeline() {
        XCTAssertNil(Money(rounding: .nan))
        XCTAssertNil(Money(rounding: .infinity))
        XCTAssertNil(Money(rounding: 1e30))
        XCTAssertNil(Money(rounding: -1e30))
    }

    func testQuantityMultiplicationScalesExactly() {
        XCTAssertEqual(Money(rounding: 0.03)! * 999, Money(tenThousandths: 299_700))
    }

    // MARK: - When an observation is worth writing

    func testUnchangedValueAndProvenanceWritesNoObservation() {
        // Case 13. A successful check that confirms the same price is coverage,
        // not news. Appending here would add a row per instrument per refresh.
        let decision = PriceObservationRules.decide(
            candidate: candidate(sourceUpdatedAt: date(1), receivedAt: date(2)),
            previous: previous(effectiveAt: date(0))
        )

        XCTAssertEqual(decision, .unchanged)
    }

    func testProvenanceOnlyChangeIsStillValueSetting() {
        // Case 18. Same $42, different market variant: the vendor has remapped
        // what is being priced, and a log whose job is to explain where numbers
        // came from has to say so even though the dollar figure did not move.
        let decision = PriceObservationRules.decide(
            candidate: candidate(
                value: value(marketVariantID: "m2"),
                sourceUpdatedAt: date(3),
                receivedAt: date(3)
            ),
            previous: previous(value: value(marketVariantID: "m1"), effectiveAt: date(1))
        )

        XCTAssertEqual(decision, .append(.sourceTransition))
    }

    func testFirstEverObservationIsAMarketUpdate() {
        let decision = PriceObservationRules.decide(
            candidate: candidate(sourceUpdatedAt: date(1), receivedAt: date(1)),
            previous: nil
        )

        XCTAssertEqual(decision, .append(.marketUpdate))
    }

    // MARK: - Classification uses provider semantics, at ingestion

    func testProviderClockAtOrBeforeThePreviousOneIsARestatement() {
        // Case 8. JustTCG publishes its own clock, so a value stamped for a
        // period already reported is history being restated — not a gain.
        for offset in [-1.0, 0.0] {
            let decision = PriceObservationRules.decide(
                candidate: candidate(
                    value: value(amount: Money(rounding: 51)),
                    sourceUpdatedAt: date(5 + offset),
                    receivedAt: date(9)
                ),
                previous: previous(effectiveAt: date(5))
            )

            XCTAssertEqual(decision, .append(.sourceRestatement), "offset \(offset)")
        }
    }

    func testProviderClockAfterThePreviousOneIsAMarketUpdate() {
        let decision = PriceObservationRules.decide(
            candidate: candidate(
                value: value(amount: Money(rounding: 51)),
                sourceUpdatedAt: date(6),
                receivedAt: date(9)
            ),
            previous: previous(effectiveAt: date(5))
        )

        XCTAssertEqual(decision, .append(.marketUpdate))
    }

    func testProviderWithNoPublishedClockIsAlwaysAMarketUpdate() {
        // Scryfall publishes no "current through" stamp, so the app has no
        // evidence of a restatement and must not invent one. The stored
        // `effectiveAt` falls back to knowledge time.
        let scryfall = candidate(
            value: value(amount: Money(rounding: 51), source: .scryfall),
            source: .scryfall,
            sourceUpdatedAt: nil,
            receivedAt: date(1)
        )

        XCTAssertFalse(scryfall.isSourceStamped)
        XCTAssertEqual(scryfall.effectiveAt, date(1))
        XCTAssertEqual(
            PriceObservationRules.decide(
                candidate: scryfall,
                previous: previous(
                    value: value(source: .scryfall),
                    effectiveAt: date(4),
                    isSourceStamped: false
                )
            ),
            .append(.marketUpdate)
        )
    }

    func testAnUnstampedPreviousObservationCannotAnchorARestatement() {
        // Comparing a provider clock against a fetch time compares two
        // different kinds of moment, which is how a stale-looking timestamp
        // would silently reclassify a real market move.
        let decision = PriceObservationRules.decide(
            candidate: candidate(
                value: value(amount: Money(rounding: 51)),
                sourceUpdatedAt: date(1),
                receivedAt: date(9)
            ),
            previous: previous(effectiveAt: date(5), isSourceStamped: false)
        )

        XCTAssertEqual(decision, .append(.marketUpdate))
    }

    // MARK: - Coverage evidence is separate from price values

    func testFailureLeavesTheEvidenceOfAnEarlierSuccessIntact() {
        // Case 14. `lastCheckedAt` records both outcomes, so on its own it
        // would report a 3 PM timeout as "refreshed at 3 PM" and erase the
        // proof of a good 9 AM check.
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v1",
                sourceUpdatedAt: date(8),
                fetchedAt: date(9)
            )
        )

        record.recordFailure(at: date(15))

        XCTAssertEqual(record.lastCheckedAt, date(15))
        XCTAssertEqual(record.lastSuccessfulCheckAt, date(9))
        XCTAssertEqual(record.unitMarketPriceUSD, 42)
    }

    func testUnavailableIsASuccessfulCheckThatCarriesThePriorValueForward() {
        // Case 17. "The provider has nothing for this exact variant" is a real,
        // current answer. It counts as coverage and must not remove a price.
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v1",
                sourceUpdatedAt: date(8),
                fetchedAt: date(9)
            )
        )

        record.applyUnavailable(source: .justTCG, at: date(20))

        XCTAssertEqual(record.unitMarketPriceUSD, 42)
        XCTAssertEqual(record.lastSuccessfulCheckAt, date(20))
        XCTAssertNil(record.lastFailureAt)
    }

    func testAnImportIsNotAProviderCheck() {
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        record.applyImported(amount: 42, sourceUpdatedAt: nil, importedAt: date(1))

        XCTAssertNil(record.lastCheckedAt)
        XCTAssertNil(record.lastSuccessfulCheckAt)
    }

    // MARK: - Day boundaries

    private func zone(_ identifier: String) -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else {
            fatalError("Missing time zone \(identifier)")
        }
        return zone
    }

    func testDaysAreHalfOpenSoAnEventOnTheBoundaryBelongsToTheNextDay() {
        // Case 22. Exactly `startOfDay` is the *next* day's first instant —
        // never both days and never neither.
        let denver = zone("America/Denver")
        let day = PortfolioCalendar.day(
            containing: Date(timeIntervalSince1970: 1_700_000_000),
            in: denver
        )
        let boundary = PortfolioCalendar.boundary(afterDay: day, in: denver)

        XCTAssertEqual(PortfolioCalendar.day(containing: boundary, in: denver), boundary)
        XCTAssertEqual(
            PortfolioCalendar.day(containing: boundary.addingTimeInterval(-1), in: denver),
            day
        )
    }

    func testSpringForwardDayClosesAtMidnightNotTwentyThreeHundred() {
        // Adding 86,400 seconds would close this day at 11 PM.
        let denver = zone("America/Denver")
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 12
        let calendar = PortfolioCalendar.calendar(in: denver)
        let noon = calendar.date(from: components)!

        let day = PortfolioCalendar.day(containing: noon, in: denver)
        let boundary = PortfolioCalendar.boundary(afterDay: day, in: denver)

        XCTAssertEqual(boundary.timeIntervalSince(day), 23 * 3600)
        XCTAssertEqual(calendar.component(.hour, from: boundary), 0)
        XCTAssertEqual(calendar.component(.day, from: boundary), 9)
    }

    func testFallBackDayClosesAtMidnightNotZeroOneHundred() {
        let denver = zone("America/Denver")
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 1
        components.hour = 12
        let calendar = PortfolioCalendar.calendar(in: denver)
        let noon = calendar.date(from: components)!

        let day = PortfolioCalendar.day(containing: noon, in: denver)
        let boundary = PortfolioCalendar.boundary(afterDay: day, in: denver)

        XCTAssertEqual(boundary.timeIntervalSince(day), 25 * 3600)
        XCTAssertEqual(calendar.component(.hour, from: boundary), 0)
        XCTAssertEqual(calendar.component(.day, from: boundary), 2)
    }

    func testTheSameInstantFallsOnDifferentPortfolioDaysInDifferentZones() {
        // Why the zone is pinned rather than followed: this is the difference a
        // flight would otherwise make to every published close.
        let instant = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC
        let auckland = PortfolioCalendar.day(containing: instant, in: zone("Pacific/Auckland"))
        let denver = PortfolioCalendar.day(containing: instant, in: zone("America/Denver"))

        XCTAssertNotEqual(auckland, denver)
    }

    func testPinnedZoneIsCapturedOnceAndReadBackThereafter() {
        let defaults = UserDefaults(suiteName: "PortfolioLedgerTests.\(UUID().uuidString)")!
        defer { defaults.removeSuite(named: defaults.description) }

        XCTAssertNil(PortfolioCalendar.pinnedTimeZone(defaults: defaults))

        let captured = PortfolioCalendar.timeZone(defaults: defaults)

        XCTAssertEqual(PortfolioCalendar.pinnedTimeZone(defaults: defaults), captured)
        XCTAssertEqual(PortfolioCalendar.timeZone(defaults: defaults), captured)
    }
}
