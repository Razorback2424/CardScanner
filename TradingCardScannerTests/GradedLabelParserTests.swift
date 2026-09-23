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

    func testPSARequiresAnEightOrNineDigitCertificate() throws {
        let nineDigit = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10"),
            RecognizedLine(text: "123456789")
        ]))
        XCTAssertEqual(nineDigit.certificationNumber, "123456789")

        let tenDigit = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10"),
            RecognizedLine(text: "1234567890")
        ]))
        XCTAssertNil(tenDigit.certificationNumber)
    }

    func testGradeWordMayBeWrappedAcrossAdjacentLines() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA"),
            RecognizedLine(text: "GEM"),
            RecognizedLine(text: "MT 10"),
            RecognizedLine(text: "12345678")
        ]))

        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(evidence.certificationNumber, "12345678")
    }

    func testCompanyAndGradeMayBeSeparatedByTwoVisionLines() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA"),
            RecognizedLine(text: "1999 POKEMON"),
            RecognizedLine(text: "GEM MT 10"),
            RecognizedLine(text: "12345678")
        ]))

        XCTAssertEqual(evidence.company, .psa)
        XCTAssertEqual(evidence.grade.value, "10")
    }

    func testPrintedFinishAndPrintRunComeFromLeftoverLabelText() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10"),
            RecognizedLine(text: "1999 POKEMON GAME"),
            RecognizedLine(text: "CHARIZARD REVERSE HOLO 1ST EDITION"),
            RecognizedLine(text: "12345678")
        ]))

        XCTAssertEqual(evidence.printedFinish, .reverse)
        XCTAssertEqual(evidence.printedPrintRun, .firstEdition)
    }

    func testNegatedFinishTokensNeverBecomePositiveFinishEvidence() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10"),
            RecognizedLine(text: "CHARIZARD NON-HOLO NON-FOIL"),
            RecognizedLine(text: "12345678")
        ]))

        XCTAssertNil(evidence.printedFinish)
    }

    func testFinishPhrasesDoNotCrossUnrelatedLabelLines() throws {
        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10"),
            RecognizedLine(text: "CHARIZARD"),
            RecognizedLine(text: "REVERSE"),
            RecognizedLine(text: "PRINTING"),
            RecognizedLine(text: "12345678")
        ]))

        XCTAssertNil(evidence.printedFinish)
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

    func testModernCGCSpinarakLabelWithInterleavedColumns() throws {
        // Printed text and a plausible interleaved OCR order from the supplied
        // 2004 slab photo; this is not a capture of the device's Vision output.
        // The stylized logo can be misread; the printed company name must be
        // sufficient to identify the grader.
        let lines = [
            RecognizedLine(text: "ECGC"),
            RecognizedLine(text: "CERTIFIED GUARANTY COMPANY"),
            RecognizedLine(text: "Spinarak"),
            RecognizedLine(text: "GEM MINT"),
            RecognizedLine(text: "Pokémon (2004)"),
            RecognizedLine(text: "10"),
            RecognizedLine(text: "EX Team Rocket Returns 78/109"),
            RecognizedLine(text: "6080494242")
        ]

        let evidence = try XCTUnwrap(GradedLabelParser.parse(lines))
        XCTAssertEqual(evidence.company, .cgc)
        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(evidence.certificationNumber, "6080494242")
        XCTAssertTrue(evidence.labelCardText.contains("Spinarak"))
        XCTAssertFalse(evidence.labelCardText.contains("GEM MINT"))
    }

    func testModernCGCGradeNumberUsesRightColumnGeometry() throws {
        func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> RecognizedLine {
            RecognizedLine(
                text: text,
                boundingBox: CGRect(x: x, y: y, width: 0.14, height: 0.07)
            )
        }

        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            line("CGC", 0.10, 0.84),
            line("CERTIFIED GUARANTY COMPANY", 0.40, 0.84),
            line("Spinarak 9", 0.12, 0.71),
            line("GEM MINT", 0.73, 0.70),
            line("Pokémon (2004)", 0.12, 0.61),
            line("10", 0.77, 0.54),
            line("EX Team Rocket Returns 78/109", 0.12, 0.47),
            line("6080494242", 0.50, 0.25)
        ]))

        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(evidence.certificationNumber, "6080494242")
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

    func testTAGRequiresCertificateAndBGSBlackLabelNeedsItsNumericGrade() throws {
        XCTAssertNil(GradedLabelParser.parse([RecognizedLine(text: "TAG 10")]))
        let tag = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "TAG 9.5 123456")
        ]))
        XCTAssertEqual(tag.grade, CardGrade(value: "9.5"))
        XCTAssertEqual(tag.certificationNumber, "123456")

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

    func testTAGCardNamesAndSetWordsAreNotGradingCompanyEvidence() {
        for rawCardText in ["TAG TEAM", "TAG BOLT", "TAG ALL", "TAG GX"] {
            XCTAssertNil(
                GradedLabelParser.parse([RecognizedLine(text: "\(rawCardText) 10 123456")]),
                "\(rawCardText) should not activate TAG slab parsing"
            )
        }
    }

    func testShortEXNMAndVGLabelsNeedAnAdjacentNumberInGraderOrder() throws {
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "PSA EX"),
            RecognizedLine(text: "12345678")
        ]))

        let psa = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA EX 9 12345678")
        ]))
        XCTAssertEqual(psa.grade, CardGrade(value: "9", label: "EX"))

        let bgs = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "BGS 8 NM 1234567890")
        ]))
        XCTAssertEqual(bgs.grade, CardGrade(value: "8", label: "NM"))
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
