import XCTest
@testable import TradingCardScanner

final class GradedLabelParserTests: XCTestCase {
    func testPSAReadsGradeQualifierCertificateAndCardText() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA"),
            RecognizedLine(text: "GEM MT 10 OC"),
            RecognizedLine(text: "1999 POKEMON GAME"),
            RecognizedLine(text: "4 CHARIZARD-HOLO"),
            RecognizedLine(text: "12345678")
        ]))

        XCTAssertEqual(evidence.company, .psa)
        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Gem Mint", qualifier: "OC"))
        XCTAssertEqual(evidence.certificationNumber, "12345678")
        XCTAssertEqual(evidence.labelCardText, ["1999 POKEMON GAME", "4 CHARIZARD-HOLO"])
    }

    func testBGSReadsBlackLabelAndTenDigitCertificate() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "BECKETT"),
            RecognizedLine(text: "10 BLACK LABEL"),
            RecognizedLine(text: "0987654321")
        ]))

        XCTAssertEqual(evidence.company, .bgs)
        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Black Label"))
        XCTAssertEqual(evidence.certificationNumber, "0987654321")
    }

    func testCGCAndSGCAcceptNumberBeforeGradeWord() throws {
        let cgc = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "CGC"),
            RecognizedLine(text: "9.5 MINT+"),
            RecognizedLine(text: "123456789")
        ]))
        XCTAssertEqual(cgc.company, .cgc)
        XCTAssertEqual(cgc.grade, CardGrade(value: "9.5", label: "Mint+"))
        XCTAssertEqual(cgc.certificationNumber, "123456789")

        let sgc = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "SGC"),
            RecognizedLine(text: "10 PRISTINE"),
            RecognizedLine(text: "1234567890")
        ]))
        XCTAssertEqual(sgc.company, .sgc)
        XCTAssertEqual(sgc.grade, CardGrade(value: "10", label: "Pristine"))
        XCTAssertEqual(sgc.certificationNumber, "1234567890")
    }

    func testTAGSupportsNumericGradeWhileKeepingItsCertificateConservative() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "TAG"),
            RecognizedLine(text: "9.5"),
            RecognizedLine(text: "TAG 123456")
        ]))

        XCTAssertEqual(evidence.company, .tag)
        XCTAssertEqual(evidence.grade, CardGrade(value: "9.5"))
        XCTAssertEqual(evidence.certificationNumber, "123456")
    }

    func testBareGradesDistinguishTenNinePointFiveAndBlackLabel() throws {
        let ten = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "TAG 10")
        ]))
        XCTAssertEqual(ten.grade, CardGrade(value: "10"))

        let ninePointFive = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "TAG 9.5")
        ]))
        XCTAssertEqual(ninePointFive.grade, CardGrade(value: "9.5"))

        let blackLabel = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "BGS"),
            RecognizedLine(text: "10 BLACK LABEL")
        ]))
        XCTAssertEqual(blackLabel.grade, CardGrade(value: "10", label: "Black Label"))
    }

    func testOCRConfusionsAreUsedOnlyForNumericEvidence() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA"),
            RecognizedLine(text: "GEM MT IO"),
            RecognizedLine(text: "12O45678")
        ]))

        XCTAssertEqual(evidence.grade.value, "10")
        XCTAssertEqual(evidence.certificationNumber, "12045678")
        XCTAssertEqual(evidence.grade.label, "Gem Mint")
    }

    func testCompanyWithoutGradeIsRejected() {
        XCTAssertNil(GradedLabelParser.parse([RecognizedLine(text: "PSA")]))
        XCTAssertNil(GradedLabelParser.parse([RecognizedLine(text: "TAG TEAM")]))
    }

    func testNonTAGBareNumberNearCompanyIsNotAGrade() {
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "PSA"),
            RecognizedLine(text: "4 CHARIZARD-HOLO"),
            RecognizedLine(text: "12345678")
        ]))
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "CGC"),
            RecognizedLine(text: "9.5 CHARIZARD")
        ]))
    }

    func testRawFooterAndCollectorFractionAreRejected() {
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "OBF 223/197")
        ]))
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "PSA"),
            RecognizedLine(text: "4/102 CHARIZARD")
        ]))
    }

    func testTwoDifferentCompaniesInOneBandAreRejected() {
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "PSA 10"),
            RecognizedLine(text: "CGC 10")
        ]))
    }

    func testCardNamesContainingCompanyTokensNeedGradeEvidence() {
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "TAG TEAM")
        ]))
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "PSA APPROVED")
        ]))
    }

    func testSuppressionFragmentIncludesGradeAndCertificateIdentity() throws {
        let withCertificate = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10 12345678")
        ]))
        let withoutCertificate = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10")
        ]))

        XCTAssertNotEqual(
            withCertificate.suppressionFragment,
            withoutCertificate.suppressionFragment
        )
        XCTAssertTrue(withCertificate.suppressionFragment.contains("cert=12345678"))
    }
}
