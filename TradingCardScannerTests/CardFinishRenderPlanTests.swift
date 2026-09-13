import XCTest
@testable import TradingCardScanner

final class CardFinishRenderPlanTests: XCTestCase {
    private let confirmed = VariantResolution.uniqueInCatalog

    func testConfirmedRawFoilUsesDispersedCollectionCadence() {
        let plan = CardFinishRenderPlan.make(
            variant: .foil,
            resolution: confirmed,
            treatments: [],
            motionUsage: .passive,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .live
        )

        XCTAssertEqual(plan.family, .dispersed)
        XCTAssertEqual(plan.mode, .live)
        XCTAssertFalse(plan.isReverse)
    }

    func testNeonTreatmentUsesNeonFamilyForDetail() {
        let plan = CardFinishRenderPlan.make(
            variant: .foil,
            resolution: confirmed,
            treatments: [.neonInk],
            motionUsage: .detail,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .live
        )

        XCTAssertEqual(plan.family, .neon)
        XCTAssertEqual(plan.mode, .live)
    }

    func testReverseIsEligibleButNonfoilIsDisabled() {
        let reverse = CardFinishRenderPlan.make(
            variant: .reverse,
            resolution: confirmed,
            treatments: [],
            motionUsage: .passive,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .live
        )
        let nonfoil = CardFinishRenderPlan.make(
            variant: .nonfoil,
            resolution: confirmed,
            treatments: [],
            motionUsage: .passive,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .live
        )

        XCTAssertEqual(reverse.family, .dispersed)
        XCTAssertTrue(reverse.isReverse)
        XCTAssertEqual(nonfoil.mode, .disabled)
        XCTAssertNil(nonfoil.family)
    }

    func testUnconfirmedResolutionDoesNotRenderEvenForFoil() {
        for resolution in [nil, VariantResolution.catalogSilent, .imported] {
            let plan = CardFinishRenderPlan.make(
                variant: .foil,
                resolution: resolution,
                treatments: [],
                motionUsage: .passive,
                reduceMotion: false,
                reduceTransparency: false,
                policy: .live
            )

            XCTAssertEqual(plan.mode, .disabled)
            XCTAssertNil(plan.family)
        }
    }

    func testAccessibilityAndPolicyModesKeepStaticIdentityOrDisableTransparency() {
        let reducedMotion = CardFinishRenderPlan.make(
            variant: .holo,
            resolution: confirmed,
            treatments: [],
            motionUsage: .passive,
            reduceMotion: true,
            reduceTransparency: false,
            policy: .live
        )
        let staticCollection = CardFinishRenderPlan.make(
            variant: .holo,
            resolution: confirmed,
            treatments: [],
            motionUsage: .passive,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .staticCollection
        )
        let transparent = CardFinishRenderPlan.make(
            variant: .holo,
            resolution: confirmed,
            treatments: [],
            motionUsage: .passive,
            reduceMotion: false,
            reduceTransparency: true,
            policy: .live
        )

        XCTAssertEqual(reducedMotion.mode, .staticSurface)
        XCTAssertEqual(staticCollection.mode, .staticSurface)
        XCTAssertEqual(transparent.mode, .disabled)
    }

    func testStaticCollectionPolicyKeepsDetailMotionLive() {
        let plan = CardFinishRenderPlan.make(
            variant: .holo,
            resolution: confirmed,
            treatments: [],
            motionUsage: .detail,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .staticCollection
        )

        XCTAssertEqual(plan.mode, .live)
    }

    func testEmergencyPoliciesHaveExplicitOutcomes() {
        let staticAll = CardFinishRenderPlan.make(
            variant: .foil,
            resolution: confirmed,
            treatments: [],
            motionUsage: .detail,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .staticAll
        )
        let disabled = CardFinishRenderPlan.make(
            variant: .foil,
            resolution: confirmed,
            treatments: [],
            motionUsage: .detail,
            reduceMotion: false,
            reduceTransparency: false,
            policy: .disabled
        )

        XCTAssertEqual(staticAll.mode, .staticSurface)
        XCTAssertEqual(disabled.mode, .disabled)
        XCTAssertNil(disabled.family)
    }

#if DEBUG || CARD_FINISH_PERF_HARNESS
    func testPerformanceFixtureSpecKeepsRequestedFinishCountAndControls() {
        let finishFixture = PortfolioDebugFixtures.cardFinishPerformanceFixtureSpec(
            scenario: .gridOnly,
            rowCount: 48
        )
        let controlFixture = PortfolioDebugFixtures.cardFinishPerformanceFixtureSpec(
            scenario: .nonfoilControl,
            rowCount: 12
        )

        XCTAssertEqual(finishFixture.eligibleFinishRowCount, 48)
        XCTAssertEqual(finishFixture.nonfoilControlRowCount, 1)
        XCTAssertEqual(finishFixture.sealedControlRowCount, 1)
        XCTAssertEqual(finishFixture.rawCardRowCount, 49)
        XCTAssertEqual(finishFixture.totalRowCount, 50)

        XCTAssertEqual(controlFixture.eligibleFinishRowCount, 0)
        XCTAssertEqual(controlFixture.nonfoilControlRowCount, 12)
        XCTAssertEqual(controlFixture.sealedControlRowCount, 1)
        XCTAssertEqual(controlFixture.totalRowCount, 13)
    }
#endif
}
