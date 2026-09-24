import XCTest
@testable import TradingCardScanner

final class GradedLabelParserTests: XCTestCase {
    private func visionLine(
        _ text: String,
        _ centerX: CGFloat,
        _ centerY: CGFloat,
        width: CGFloat = 0.20
    ) -> RecognizedLine {
        RecognizedLine(
            text: text,
            boundingBox: CGRect(
                x: centerX - width / 2,
                y: centerY - 0.03,
                width: width,
                height: 0.06
            )
        )
    }

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

    func testModernPSALabelsParseWhenLogoIsMisreadOrMissing() throws {
        func line(
            _ text: String,
            _ centerX: CGFloat,
            _ centerY: CGFloat,
            width: CGFloat = 0.20
        ) -> RecognizedLine {
            RecognizedLine(
                text: text,
                boundingBox: CGRect(
                    x: centerX - width / 2,
                    y: centerY - 0.03,
                    width: width,
                    height: 0.06
                )
            )
        }

        // Captured Vision coordinates from the modern PSA label. The collector
        // number is in the right column above the grade, and the logo reads PA.
        let zapdos = try XCTUnwrap(GradedLabelParser.parse([
            line("023 POKEMON MEW EN", 0.28, 0.69, width: 0.42),
            line("APDOS ex", 0.28, 0.60, width: 0.24),
            line("PECIAL ILLUSTRATION RARE", 0.28, 0.51, width: 0.46),
            line("PA", 0.44, 0.41, width: 0.06),
            line("#202", 0.86, 0.73, width: 0.10),
            line("GEM MT", 0.82, 0.64, width: 0.16),
            line("10", 0.89, 0.55, width: 0.06),
            line("157154355", 0.79, 0.45, width: 0.20)
        ]))

        XCTAssertEqual(zapdos.company, .psa)
        XCTAssertEqual(zapdos.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(zapdos.certificationNumber, "157154355")

        // Sylveon's logo was not recognized at all. Its measured coordinates
        // still show the card number above the grade and the cert below it.
        let sylveon = try XCTUnwrap(GradedLabelParser.parse([
            line("2025 POKEMON PRE EN", 0.28, 0.56, width: 0.42),
            line("SYLVEON ex", 0.28, 0.66, width: 0.24),
            line("SPECIAL ILLUSTRATION RARE", 0.28, 0.61, width: 0.46),
            line("#156", 0.83, 0.57, width: 0.10),
            line("MINT", 0.83, 0.49, width: 0.16),
            line("9", 0.87, 0.41, width: 0.06),
            line("157154347", 0.77, 0.33, width: 0.20)
        ]))

        XCTAssertEqual(sylveon.company, .psa)
        XCTAssertEqual(sylveon.grade, CardGrade(value: "9", label: "Mint"))
        XCTAssertEqual(sylveon.certificationNumber, "157154347")
    }

    func testPSAGradeMatchesByColumnWhenLogoIsFarAwayInVisionOrder() throws {
        func line(
            _ text: String,
            _ centerX: CGFloat,
            _ centerY: CGFloat,
            width: CGFloat = 0.20
        ) -> RecognizedLine {
            RecognizedLine(
                text: text,
                boundingBox: CGRect(
                    x: centerX - width / 2,
                    y: centerY - 0.03,
                    width: width,
                    height: 0.06
                )
            )
        }

        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            line("PSA", 0.44, 0.41, width: 0.08),
            line("2025 POKEMON PRE EN", 0.28, 0.56, width: 0.42),
            line("SYLVEON ex", 0.28, 0.66, width: 0.24),
            line("SPECIAL ILLUSTRATION RARE", 0.28, 0.61, width: 0.46),
            line("#156", 0.83, 0.57, width: 0.10),
            line("LABEL", 0.28, 0.30, width: 0.18),
            line("MINT", 0.83, 0.49, width: 0.16),
            line("9", 0.87, 0.41, width: 0.06),
            line("157154347", 0.77, 0.33, width: 0.20)
        ]))

        XCTAssertEqual(evidence.company, .psa)
        XCTAssertEqual(evidence.grade, CardGrade(value: "9", label: "Mint"))
        XCTAssertEqual(evidence.certificationNumber, "157154347")
    }

    func testPSAInferenceNeedsModernLayoutAndGeometry() {
        XCTAssertNil(GradedLabelParser.parse([
            RecognizedLine(text: "2025 POKEMON PRE EN"),
            RecognizedLine(text: "#156"),
            RecognizedLine(text: "MINT"),
            RecognizedLine(text: "9"),
            RecognizedLine(text: "157154347")
        ]))

        func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> RecognizedLine {
            RecognizedLine(
                text: text,
                boundingBox: CGRect(x: x, y: y, width: 0.18, height: 0.06)
            )
        }
        XCTAssertNil(GradedLabelParser.parse([
            line("2025 POKEMON PRE EN", 0.19, 0.53),
            line("#156", 0.19, 0.54),
            line("MINT", 0.74, 0.46),
            line("9", 0.78, 0.38),
            line("157154347", 0.68, 0.30)
        ]))
    }

    func testCollectorNumberIsNeverTheGrade() throws {
        // Captured Vision positions from the real Machamp slab read. The probe
        // text isolates a 1–10 collector number beside a printed grade number.
        let collectorProbe = [
            visionLine("1999 POKEMON GAME", 0.32, 0.76, width: 0.45),
            visionLine("MACHAMP-HOLO", 0.27, 0.62, width: 0.36),
            visionLine("1ST EDITION", 0.22, 0.47, width: 0.25),
            visionLine("PSA", 0.52, 0.30, width: 0.04),
            visionLine("#4", 0.87, 0.74, width: 0.06),
            visionLine("GEM MT", 0.82, 0.60, width: 0.15),
            visionLine("10", 0.88, 0.45, width: 0.03),
            visionLine("158106351", 0.79, 0.32, width: 0.22)
        ]

        let evidence = try XCTUnwrap(GradedLabelParser.parse(collectorProbe))
        XCTAssertEqual(evidence.company, .psa)
        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Gem Mint"))

        XCTAssertNil(GradedLabelParser.parse(collectorProbe.filter { $0.text != "10" }))

        let smallCollectorProbe = collectorProbe.map { line in
            let replacement: String
            switch line.text {
            case "#4": replacement = "#8"
            case "GEM MT": replacement = "MINT"
            case "10": replacement = "9"
            default: replacement = line.text
            }
            return RecognizedLine(text: replacement, boundingBox: line.boundingBox)
        }
        let smallCollector = try XCTUnwrap(GradedLabelParser.parse(smallCollectorProbe))
        XCTAssertEqual(smallCollector.grade, CardGrade(value: "9", label: "Mint"))

        let hashPrefixed = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "PSA GEM MT 10"),
            RecognizedLine(text: "#12345678")
        ]))
        XCTAssertNil(hashPrefixed.certificationNumber)

        // Captured band read from the same slab: `# 8` keeps its hash identity
        // across the OCR whitespace, so it cannot fill in a missing grade.
        XCTAssertNil(GradedLabelParser.parse([
            visionLine("1999 POKEMON GAME", 0.32, 0.69, width: 0.46),
            visionLine("MACHAMP-HOLO", 0.27, 0.61, width: 0.37),
            visionLine("1ST EDITION", 0.22, 0.52, width: 0.25),
            visionLine("P", 0.47, 0.41, width: 0.05),
            visionLine("# 8", 0.87, 0.68, width: 0.06),
            visionLine("NM-MT", 0.82, 0.60, width: 0.15),
            visionLine("158106351", 0.79, 0.42, width: 0.22)
        ]))
    }

    func testSubgradeValuesAreNeverTheGrade() throws {
        // Captured band read from a real CGC Cubone slab, with the large Mint 9
        // grade value omitted so only the four subgrade values remain.
        XCTAssertNil(GradedLabelParser.parse([
            visionLine("CGC UNIVERSAL GRADE", 0.52, 0.83, width: 0.80),
            visionLine("Cubone", 0.63, 0.73, width: 0.18),
            visionLine("Mint", 0.21, 0.69, width: 0.07),
            visionLine("Pokémon (1998) Japanese", 0.62, 0.65, width: 0.51),
            visionLine("Vending Series 3", 0.62, 0.59, width: 0.26),
            visionLine("Centering", 0.41, 0.47, width: 0.14),
            visionLine("8.5", 0.41, 0.42, width: 0.04),
            visionLine("Surface", 0.57, 0.47, width: 0.11),
            visionLine("9.5", 0.56, 0.42, width: 0.04),
            visionLine("Corners", 0.71, 0.47, width: 0.11),
            visionLine("10", 0.72, 0.42, width: 0.04),
            visionLine("Edges", 0.85, 0.47, width: 0.09),
            visionLine("10", 0.85, 0.42, width: 0.04),
            visionLine("LV.14 HP40", 0.69, 0.06, width: 0.20)
        ]))

        // Captured full CGC Cubone label read.
        let cubone = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("CGC UNIVERSAL GRADE", 0.52, 0.95, width: 0.80),
            visionLine("Cubone", 0.63, 0.81, width: 0.18),
            visionLine("Mint", 0.21, 0.76, width: 0.07),
            visionLine("9", 0.21, 0.57, width: 0.07),
            visionLine("Pokémon (1998) Japanese", 0.62, 0.69, width: 0.51),
            visionLine("Vending Series 3", 0.62, 0.59, width: 0.26),
            visionLine("Centering", 0.41, 0.40, width: 0.14),
            visionLine("8.5", 0.41, 0.33, width: 0.04),
            visionLine("Surface", 0.57, 0.41, width: 0.11),
            visionLine("9.5", 0.57, 0.33, width: 0.05),
            visionLine("Corners", 0.71, 0.41, width: 0.11),
            visionLine("10", 0.72, 0.33, width: 0.04),
            visionLine("Edges", 0.85, 0.40, width: 0.09),
            visionLine("10", 0.85, 0.33, width: 0.04)
        ]))
        XCTAssertEqual(cubone.company, .cgc)
        XCTAssertEqual(cubone.grade, CardGrade(value: "9", label: "Mint"))

        let bgs = try XCTUnwrap(GradedLabelParser.parse([
            RecognizedLine(text: "BGS 9.5 GEM MINT"),
            RecognizedLine(text: "CENTERING 10")
        ]))
        XCTAssertEqual(bgs.grade, CardGrade(value: "9.5", label: "Gem Mint"))
    }

    func testModernPSAFallbackReadsTwoTokenGrades() throws {
        // Captured real Machamp PSA label read; its logo was recognized as A.
        let machamp = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("1999 POKEMON GAME", 0.32, 0.76, width: 0.45),
            visionLine("MACHAMP-HOLO", 0.27, 0.62, width: 0.36),
            visionLine("1ST EDITION", 0.22, 0.47, width: 0.25),
            visionLine("A", 0.52, 0.30, width: 0.04),
            visionLine("#8", 0.87, 0.74, width: 0.06),
            visionLine("NM-MT", 0.82, 0.60, width: 0.15),
            visionLine("8", 0.88, 0.45, width: 0.03),
            visionLine("158106351", 0.79, 0.32, width: 0.22)
        ]))
        XCTAssertEqual(machamp.company, .psa)
        XCTAssertEqual(machamp.grade, CardGrade(value: "8", label: "NM-MT"))
        XCTAssertEqual(machamp.certificationNumber, "158106351")

        // Captured real Venusaur PSA label read; its logo was recognized as PEA.
        let venusaur = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("1999 POKEMON GAME", 0.31, 0.72, width: 0.43),
            visionLine("VENUSAUR-HOLO", 0.27, 0.57, width: 0.35),
            visionLine("SHADOWLESS", 0.23, 0.42, width: 0.29),
            visionLine("PEA", 0.47, 0.22, width: 0.10),
            visionLine("#15", 0.81, 0.73, width: 0.07),
            visionLine("NM-MT", 0.78, 0.58, width: 0.14),
            visionLine("8", 0.84, 0.43, width: 0.02),
            visionLine("165284199", 0.75, 0.28, width: 0.21)
        ]))
        XCTAssertEqual(venusaur.company, .psa)
        XCTAssertEqual(venusaur.grade.value, "8")
        XCTAssertEqual(venusaur.certificationNumber, "165284199")
    }

    func testModernPSAFallbackAcceptsLetterPrefixedCardNumbers() throws {
        // Captured real Mimikyu PSA label read, with no PSA logo recognized.
        let mimikyu = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("2022 POKEMON SWSH", 0.31, 0.69, width: 0.51),
            visionLine("FA/MIMIKYU VMAX", 0.28, 0.53, width: 0.44),
            visionLine("BRILLIANT STARS", 0.26, 0.36, width: 0.40),
            visionLine("#TG17", 0.85, 0.69, width: 0.15),
            visionLine("GEM MT", 0.83, 0.53, width: 0.19),
            visionLine("10", 0.90, 0.37, width: 0.05),
            visionLine("137672473", 0.80, 0.20, width: 0.24)
        ]))
        XCTAssertEqual(mimikyu.company, .psa)
        XCTAssertEqual(mimikyu.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(mimikyu.certificationNumber, "137672473")
    }

    func testModernPSAFallbackIsGameAgnostic() throws {
        // Captured real Zuko Magic label read; its PSA logo was recognized PEA.
        let zuko = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("2025 MTG TLA EN", 0.29, 0.67, width: 0.37),
            visionLine("FIRE LORD ZUKO", 0.27, 0.54, width: 0.33),
            visionLine("BOOK 3 SCENE BORDERLESS-FOIL", 0.47, 0.44, width: 0.72),
            visionLine("PEA", 0.49, 0.27, width: 0.09),
            visionLine("#0315", 0.85, 0.76, width: 0.14),
            visionLine("GEM MT", 0.83, 0.63, width: 0.19),
            visionLine("10", 0.89, 0.49, width: 0.05),
            visionLine("171286143", 0.80, 0.35, width: 0.23)
        ]))
        XCTAssertEqual(zuko.company, .psa)
        XCTAssertEqual(zuko.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(zuko.certificationNumber, "171286143")

        // Captured real Atog label read: no card number and no readable logo.
        XCTAssertNil(GradedLabelParser.parse([
            visionLine("1994 MAGIC - GATHERING", 0.38, 0.73, width: 0.60),
            visionLine("ATOG", 0.14, 0.58, width: 0.13),
            visionLine("REVISED", 0.17, 0.46, width: 0.20),
            visionLine("MINT", 0.86, 0.62, width: 0.12),
            visionLine("9", 0.91, 0.49, width: 0.03),
            visionLine("53902302", 0.81, 0.36, width: 0.23)
        ]))
    }

    func testCGCLogoFusedWithIconIsCompanyEvidence() throws {
        // Captured real Katara Signature Series CGC label read. Its logo mark
        // was fused into the single OCR token SACGC and lacks the usual company line.
        let katara = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("SACGC", 0.13, 0.89, width: 0.14),
            visionLine("Katara, the Fearless", 0.23, 0.73, width: 0.32),
            visionLine("Magic: The Gathering (2025)", 0.30, 0.65, width: 0.45),
            visionLine("Avatar: the Last Airbender - 0305", 0.34, 0.57, width: 0.53),
            visionLine("Rare - Foil - Borderless Scene", 0.31, 0.49, width: 0.48),
            visionLine("MAE WHITMAN, 3/26/26", 0.27, 0.41, width: 0.38),
            visionLine("6166347198", 0.55, 0.31, width: 0.14),
            visionLine("Signature SERIES", 0.77, 0.88, width: 0.32),
            visionLine("PRISTINE", 0.82, 0.71, width: 0.18),
            visionLine("10", 0.82, 0.45, width: 0.20)
        ]))
        XCTAssertEqual(katara.company, .cgc)
        XCTAssertEqual(katara.grade, CardGrade(value: "10", label: "Pristine"))
        XCTAssertEqual(katara.certificationNumber, "6166347198")

        // Captured real Yveltal CGC band read, with ACGC as its logo mark.
        let yveltal = try XCTUnwrap(GradedLabelParser.parse([
            visionLine("ACGC", 0.17, 0.76, width: 0.17),
            visionLine("Yveltal", 0.14, 0.66, width: 0.13),
            visionLine("Pokémon (2016)", 0.22, 0.60, width: 0.28),
            visionLine("Generations - RC16/RC32", 0.30, 0.54, width: 0.42),
            visionLine("Radiant Collection - Holo", 0.29, 0.48, width: 0.43),
            visionLine("6146900028", 0.53, 0.39, width: 0.15),
            visionLine("BASIC", 0.14, 0.07, width: 0.12),
            visionLine("veltal", 0.36, 0.04, width: 0.15),
            visionLine("PRISTINE", 0.78, 0.64, width: 0.17),
            visionLine("\"10", 0.79, 0.48, width: 0.19)
        ]))
        XCTAssertEqual(yveltal.company, .cgc)
        XCTAssertEqual(yveltal.grade.value, "10")
    }

    func testModernPSAFallbackAcceptsAnEightDigitCertificate() throws {
        func line(_ text: String, _ centerX: CGFloat, _ centerY: CGFloat) -> RecognizedLine {
            RecognizedLine(
                text: text,
                boundingBox: CGRect(
                    x: centerX - 0.09,
                    y: centerY - 0.03,
                    width: 0.18,
                    height: 0.06
                )
            )
        }

        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            line("2025 POKEMON PRE EN", 0.28, 0.56),
            line("#156", 0.83, 0.57),
            line("MINT", 0.83, 0.49),
            line("9", 0.87, 0.41),
            line("12345678", 0.77, 0.33)
        ]))

        XCTAssertEqual(evidence.company, .psa)
        XCTAssertEqual(evidence.grade, CardGrade(value: "9", label: "Mint"))
        XCTAssertEqual(evidence.certificationNumber, "12345678")
    }

    func testPSAGradePhraseSurvivesMergedLeftAndRightOCRRow() throws {
        func line(
            _ text: String,
            _ centerX: CGFloat,
            _ centerY: CGFloat,
            width: CGFloat = 0.18
        ) -> RecognizedLine {
            RecognizedLine(
                text: text,
                boundingBox: CGRect(
                    x: centerX - width / 2,
                    y: centerY - 0.03,
                    width: width,
                    height: 0.06
                )
            )
        }

        let evidence = try XCTUnwrap(GradedLabelParser.parse([
            line("PSA", 0.44, 0.41),
            line("2025 POKEMON PRE EN", 0.28, 0.69, width: 0.42),
            line("#202", 0.86, 0.73, width: 0.10),
            line("157154355", 0.79, 0.45, width: 0.20),
            line("ZAPDOS ex GEM MT", 0.52, 0.64, width: 0.84),
            line("10", 0.89, 0.55, width: 0.06)
        ]))

        XCTAssertEqual(evidence.company, .psa)
        XCTAssertEqual(evidence.grade, CardGrade(value: "10", label: "Gem Mint"))
        XCTAssertEqual(evidence.certificationNumber, "157154355")
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
