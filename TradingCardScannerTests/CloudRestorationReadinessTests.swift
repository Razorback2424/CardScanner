import XCTest
@testable import TradingCardScanner

final class CloudRestorationReadinessTests: XCTestCase {
    private let storeID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testUnprovenProductionSourceFailsClosed() async {
        let source = UnprovenCloudRestorationReadinessSource()
        let result = await source.readiness(
            storeID: storeID,
            accountFingerprint: "account-a",
            generation: 7
        )
        XCTAssertEqual(result, .failed(category: "restoration-readiness-not-proven"))
        XCTAssertFalse(result.isReady)
    }

    func testFixedSourcePreservesEmptyAndPopulatedEvidence() async {
        for expected in [
            CloudRestorationReadiness.readyEmpty(remoteGeneration: "generation-a"),
            .readyPopulated(remoteGeneration: "generation-a")
        ] {
            let source = FixedCloudRestorationReadinessSource(result: expected)
            let result = await source.readiness(
                storeID: storeID,
                accountFingerprint: "account-a",
                generation: 8
            )
            XCTAssertEqual(result, expected)
            XCTAssertTrue(result.isReady)
        }
    }

    func testImportingAndFailureStatesAreNeverReady() {
        let states: [CloudRestorationReadiness] = [
            .notApplicable,
            .checkingRemoteCollection,
            .importingRemoteCollection,
            .failed(category: "import-not-proven")
        ]
        for state in states {
            XCTAssertFalse(state.isReady)
        }
    }

    func testReadinessContractVersionIsExplicit() {
        XCTAssertGreaterThan(CloudRestorationReadinessContract.currentMechanismVersion, 0)
    }
}
