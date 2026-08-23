import XCTest
@testable import TradingCardScanner

final class ScanParserTests: XCTestCase {
    func testStandardIdentifier() {
        XCTAssertEqual(ScanParser.parse("OBF 223/197")?.displayIdentifier, "OBF 223/197")
    }

    func testMergedSetCodeAndNumber() {
        XCTAssertEqual(ScanParser.parse("OBF223/197")?.displayIdentifier, "OBF 223/197")
    }

    func testMergedRegulationMarkAndNumber() {
        XCTAssertEqual(ScanParser.parse("OBF G223/197")?.displayIdentifier, "OBF 223/197")
    }

    func testCommonLetterOneConfusion() {
        XCTAssertEqual(ScanParser.parse("OBF 223/l97")?.displayIdentifier, "OBF 223/197")
    }

    func testLeadingZeroLocalID() {
        XCTAssertEqual(ScanParser.parse("MEW 006/165")?.cardNumber, "006")
    }

    func testCurrentMegaEvolutionSets() {
        XCTAssertEqual(ScanParser.parse("MEG001/132")?.setDefinition.tcgdexSetID, "me01")
        XCTAssertEqual(ScanParser.parse("ASC217/217")?.setDefinition.tcgdexSetID, "me02.5")
    }

    func testSetCodeEmbeddedInIllustratorNameIsIgnored() {
        XCTAssertEqual(
            ScanParser.parse("ILLUS. MASCAGNI OBF 223/197")?.displayIdentifier,
            "OBF 223/197"
        )
    }

    func testLineStructureKeepsCodePairedWithItsNumber() {
        XCTAssertEqual(
            ScanParser.parse(["ILLUS. MASCAGNI", "OBF 223/197"])?.displayIdentifier,
            "OBF 223/197"
        )
    }

    func testTwoValidCardIdentifiersAreTreatedAsAmbiguous() {
        XCTAssertNil(ScanParser.parse(["SVI 198/198", "OBF 223/197"]))
        XCTAssertNil(ScanParser.parse("SVI 198/198 OBF 223/197"))
    }

    func testSplitIdentifierFallsBackToJoinedLines() {
        XCTAssertEqual(
            ScanParser.parse(["OBF", "223/197"])?.displayIdentifier,
            "OBF 223/197"
        )
    }

    func testZeroCardNumberIsRejected() {
        XCTAssertNil(ScanParser.parse("OBF OOO/197"))
        XCTAssertNil(ScanParser.parse("OBF 000/197"))
    }

    func testWrongDenominatorIsRejected() {
        XCTAssertNil(ScanParser.parse("OBF 223/191"))
    }

    func testUnknownSetIsRejected() {
        XCTAssertNil(ScanParser.parse("XYZ 223/197"))
    }

    func testConfirmationAllowsOneMissBetweenMatches() {
        let candidate = try! XCTUnwrap(ScanParser.parse("OBF223/197"))
        var window = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(candidate))
        XCTAssertNil(window.observe(nil))
        XCTAssertEqual(window.observe(candidate), candidate)
    }

    func testConfirmationDoesNotKeepStaleCandidateForever() {
        let candidate = try! XCTUnwrap(ScanParser.parse("OBF223/197"))
        var window = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(candidate))
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(candidate))
    }
}
