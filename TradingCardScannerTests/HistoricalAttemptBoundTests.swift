import XCTest
@testable import TradingCardScanner

@MainActor
final class HistoricalAttemptBoundTests: XCTestCase {
    private let number = PokemonPrintedNumberEvidence(
        localID: "78",
        denominator: 109,
        scheme: .officialSet
    )

    func testRetryCapStopsTheTitlePassUntilTheTTLElapses() {
        let scanner = CardScanner()
        let start: CFAbsoluteTime = 1_000

        for index in 0..<6 {
            XCTAssertTrue(
                scanner.advanceHistoricalAttemptForTesting(number, at: start + Double(index) * 0.24),
                "attempt \(index) should be allowed inside the retry cap"
            )
        }

        // Exhausted, and still inside the TTL: further frames must not run the
        // title pass at all. This is the regression — clearing the attempt here
        // let the very next frame start over.
        XCTAssertFalse(scanner.advanceHistoricalAttemptForTesting(number, at: start + 1.45))
        XCTAssertFalse(scanner.advanceHistoricalAttemptForTesting(number, at: start + 1.49))

        // Past the TTL a genuinely new attempt begins.
        XCTAssertTrue(scanner.advanceHistoricalAttemptForTesting(number, at: start + 1.6))
    }

    func testADifferentPrintedNumberStartsAFreshAttemptImmediately() {
        let scanner = CardScanner()
        let start: CFAbsoluteTime = 2_000
        for index in 0..<6 {
            scanner.advanceHistoricalAttemptForTesting(number, at: start + Double(index) * 0.24)
        }
        XCTAssertFalse(scanner.advanceHistoricalAttemptForTesting(number, at: start + 1.45))

        let other = PokemonPrintedNumberEvidence(
            localID: "12",
            denominator: 109,
            scheme: .officialSet
        )
        XCTAssertTrue(scanner.advanceHistoricalAttemptForTesting(other, at: start + 1.46))
    }

    func testRawTitleEvidenceExpiresAtTTLAttemptRenewal() {
        let scanner = CardScanner()
        let start: CFAbsoluteTime = 3_000
        XCTAssertTrue(scanner.advanceHistoricalAttemptForTesting(number, at: start))
        scanner.setHistoricalTitleCandidatesForTesting(["dustox"])

        for index in 1..<6 {
            XCTAssertTrue(
                scanner.advanceHistoricalAttemptForTesting(
                    number,
                    at: start + Double(index) * 0.2
                )
            )
        }
        XCTAssertFalse(scanner.advanceHistoricalAttemptForTesting(number, at: start + 1.3))

        XCTAssertTrue(scanner.advanceHistoricalAttemptForTesting(number, at: start + 1.6))
        XCTAssertEqual(scanner.historicalTitleCandidatesForTesting, [])
    }

    func testExhaustedRawAttemptReturnsAccumulatedEvidenceWithoutAnotherTitlePass() {
        let scanner = CardScanner()
        let start: CFAbsoluteTime = 4_000
        for index in 0..<6 {
            XCTAssertTrue(
                scanner.advanceHistoricalAttemptForTesting(
                    number,
                    at: start + Double(index) * 0.2
                )
            )
            if index == 0 {
                scanner.setHistoricalTitleCandidatesForTesting(["dustox"])
            }
        }

        let identifier = scanner.exhaustedHistoricalIdentifierForTesting(number)
        guard case let .pokemonHistorical(evidence)? = identifier else {
            return XCTFail("Expected the capped attempt to return its title evidence")
        }
        XCTAssertEqual(evidence.titleCandidates, ["dustox"])
    }
}
