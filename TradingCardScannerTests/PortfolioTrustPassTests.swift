import XCTest
@testable import TradingCardScanner

/// The two trust rules that are easy to regress silently: never labelling one
/// period's accounting with another period's name, and never letting a timer
/// clear a problem nobody fixed.
final class PortfolioTrustPassTests: XCTestCase {

    // MARK: - A result belongs to exactly one range

    private func result(range: PortfolioHistoryRange) -> PortfolioHistoryResult {
        PortfolioHistoryResult(
            range: range,
            points: [],
            accounting: nil,
            performanceFactor: nil,
            performanceAvailable: true,
            coverage: PortfolioHistoryCoverage(),
            revisions: [],
            trackingBeganDate: nil,
            hasTwoPublishedPoints: false,
            accountingInterval: nil,
            contributions: [:],
            hasEligibleMarketMovement: false
        )
    }

    func testAResultOnlyMatchesItsOwnRange() {
        let oneMonth = result(range: .oneMonth)

        XCTAssertTrue(oneMonth.matches(range: .oneMonth))
        // Stale range: this is the 1M total that must never render under a 3M
        // heading while the replacement computes.
        XCTAssertFalse(oneMonth.matches(range: .threeMonths))
    }

    func testCardMovementStateKeepsRecordingAndNoMovementVisible() {
        let recording = result(range: .oneMonth)
        XCTAssertEqual(recording.cardMovement(for: "card"), .historyRecording)

        var settled = recording
        settled.hasTwoPublishedPoints = true
        settled.accountingInterval = PortfolioAccountingInterval(
            anchorDate: Date(timeIntervalSince1970: 1),
            includedClosedDays: [],
            includesLiveDay: true,
            liveDay: Date(timeIntervalSince1970: 2)
        )
        XCTAssertEqual(
            settled.cardMovement(for: "card"),
            .noRecordedMarketMovement
        )

        settled.movementDetails = [
            "card": PortfolioContributionDetail(
                totalImpact: Money(tenThousandths: -500),
                cumulativeUnitMovement: Money(tenThousandths: -500),
                affectedQuantities: [1]
            )
        ]
        if case .recorded(let detail) = settled.cardMovement(for: "card") {
            XCTAssertEqual(detail.totalImpact, Money(tenThousandths: -500))
        } else {
            XCTFail("Expected a recorded card movement")
        }
    }

    // MARK: - Unresolved failures outlive transient feedback

    private func summary(failed: Int, unreachable: Bool) -> PriceRefreshController.Summary {
        var summary = PriceRefreshController.Summary(
            checkedAt: Date(timeIntervalSince1970: 1_700_000_000),
            priced: 12,
            failed: failed,
            latestSourceUpdate: nil,
            checkedUnstampedProvider: false,
            changedPrices: true,
            foundNothingNewer: false
        )
        summary.providerUnreachable = unreachable
        return summary
    }

    func testAFailedRefreshIsNotTransientFeedback() {
        // The ten-second timer clears feedback. A refresh that failed is not
        // feedback — it is a condition, and the Portfolio attention indicator
        // reads it. Clearing it would make the app look healthy while nothing
        // had been fixed.
        XCTAssertFalse(
            PriceRefreshController.isTransientSuccessStatus(
                .finished(summary(failed: 3, unreachable: false))
            )
        )
        XCTAssertFalse(
            PriceRefreshController.isTransientSuccessStatus(
                .finished(summary(failed: 0, unreachable: true))
            )
        )
    }

    func testAGradedLookupMissIsNotTransientFeedback() {
        var result = summary(failed: 0, unreachable: false)
        result.gradedLookupMisses = 1

        XCTAssertFalse(
            PriceRefreshController.isTransientSuccessStatus(.finished(result))
        )
    }

    func testASuccessfulRefreshIsTransientFeedbackAndResolvesTheFailure() {
        // A clean retry is both dismissable and the thing that clears the
        // attention state, because the status it replaces is the state.
        XCTAssertTrue(
            PriceRefreshController.isTransientSuccessStatus(
                .finished(summary(failed: 0, unreachable: false))
            )
        )
        XCTAssertTrue(PriceRefreshController.isTransientSuccessStatus(.recentlyChecked))
    }

    func testInFlightAndIdleStatusesAreNeverDismissed() {
        XCTAssertFalse(PriceRefreshController.isTransientSuccessStatus(.idle))
        XCTAssertFalse(
            PriceRefreshController.isTransientSuccessStatus(.refreshing(completed: 2, total: 9))
        )
    }
}
