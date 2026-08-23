import XCTest
@testable import TradingCardScanner

final class ScanParserTests: XCTestCase {
    func testStandardIdentifier() {
        XCTAssertEqual(ScanParser.parsePokemon("OBF 223/197")?.displayIdentifier, "OBF 223/197")
    }

    func testMergedSetCodeAndNumber() {
        XCTAssertEqual(ScanParser.parsePokemon("OBF223/197")?.displayIdentifier, "OBF 223/197")
    }

    func testMergedRegulationMarkAndNumber() {
        XCTAssertEqual(ScanParser.parsePokemon("OBF G223/197")?.displayIdentifier, "OBF 223/197")
    }

    func testCommonLetterOneConfusion() {
        XCTAssertEqual(ScanParser.parsePokemon("OBF 223/l97")?.displayIdentifier, "OBF 223/197")
    }

    func testLeadingZeroLocalID() {
        guard case let .pokemon(_, cardNumber, _, _)? = ScanParser.parsePokemon("MEW 006/165") else {
            return XCTFail("Expected a Pokémon identifier")
        }
        XCTAssertEqual(cardNumber, "006")
    }

    func testCurrentMegaEvolutionSets() {
        guard case let .pokemon(_, _, _, megSet)? = ScanParser.parsePokemon("MEG001/132"),
              case let .pokemon(_, _, _, ascSet)? = ScanParser.parsePokemon("ASC217/217") else {
            return XCTFail("Expected current Pokémon set identifiers")
        }
        XCTAssertEqual(megSet.tcgdexSetID, "me01")
        XCTAssertEqual(ascSet.tcgdexSetID, "me02.5")
    }

    func testSetCodeEmbeddedInIllustratorNameIsIgnored() {
        XCTAssertEqual(
            ScanParser.parsePokemon("ILLUS. MASCAGNI OBF 223/197")?.displayIdentifier,
            "OBF 223/197"
        )
    }

    func testLineStructureKeepsCodePairedWithItsNumber() {
        XCTAssertEqual(
            ScanParser.parsePokemon(["ILLUS. MASCAGNI", "OBF 223/197"])?.displayIdentifier,
            "OBF 223/197"
        )
    }

    func testTwoValidCardIdentifiersAreTreatedAsAmbiguous() {
        XCTAssertNil(ScanParser.parsePokemon(["SVI 198/198", "OBF 223/197"]))
        XCTAssertNil(ScanParser.parsePokemon("SVI 198/198 OBF 223/197"))
    }

    func testSplitIdentifierFallsBackToJoinedLines() {
        XCTAssertEqual(
            ScanParser.parsePokemon(["OBF", "223/197"])?.displayIdentifier,
            "OBF 223/197"
        )
    }

    func testZeroCardNumberIsRejected() {
        XCTAssertNil(ScanParser.parsePokemon("OBF OOO/197"))
        XCTAssertNil(ScanParser.parsePokemon("OBF 000/197"))
    }

    func testWrongDenominatorIsRejected() {
        XCTAssertNil(ScanParser.parsePokemon("OBF 223/191"))
    }

    func testUnknownSetIsRejected() {
        XCTAssertNil(ScanParser.parsePokemon("XYZ 223/197"))
    }

    func testConfirmationAllowsOneMissBetweenMatches() {
        let candidate = try! XCTUnwrap(ScanParser.parsePokemon("OBF223/197"))
        var window = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(candidate))
        XCTAssertNil(window.observe(nil))
        XCTAssertEqual(window.observe(candidate), candidate)
    }

    func testConfirmationDoesNotKeepStaleCandidateForever() {
        let candidate = try! XCTUnwrap(ScanParser.parsePokemon("OBF223/197"))
        var window = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(candidate))
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(candidate))
    }

    private var magicProfile: MagicScanProfile {
        MagicScanProfile(definitions: [
            .init(code: "ECL", printedSize: 269),
            .init(code: "MH3", printedSize: nil),
            .init(code: "PLST", printedSize: nil)
        ])
    }

    func testMagicFooterIdentifierOnOneLine() {
        XCTAssertEqual(
            magicProfile.parse(["ILLUS. REBECCA GUAY", "ECL • 0218 • EN", "© 2026 WIZARDS"])?.displayIdentifier,
            "ECL 218 EN"
        )
    }

    func testMagicPairsAdjacentStructuredCollectorNumberWithFooter() {
        XCTAssertEqual(
            magicProfile.parse(["ILLUS. REBECCA GUAY", "R 0218", "ECL • EN", "© 2026 WIZARDS"])?.displayIdentifier,
            "ECL 218 EN"
        )
    }

    func testMagicDoesNotTreatAdjacentCopyrightYearAsCollectorNumber() {
        XCTAssertNil(magicProfile.parse(["ECL • EN", "© 2026 WIZARDS"]))
    }

    func testMagicRequiresEnglishFooterMarker() {
        XCTAssertNil(magicProfile.parse(["R 0218", "ECL • FR"]))
    }

    func testMagicRejectsMismatchedKnownPrintedDenominator() {
        XCTAssertNil(magicProfile.parse(["ECL • 218/268 • EN"]))
    }

    func testMagicNormalizesLeadingZeroCollectorNumber() {
        XCTAssertEqual(magicProfile.parse(["MH3 • 001 • EN"])?.displayIdentifier, "MH3 1 EN")
    }

    // MARK: - Vision splits the footer differently every frame

    func testMagicReadsAFullySplitFooter() {
        XCTAssertEqual(
            magicProfile.parse(["0218", "ECL", "EN"])?.displayIdentifier,
            "ECL 218 EN"
        )
    }

    func testMagicReadsTheRealTwoLineFooterShape() {
        XCTAssertEqual(
            magicProfile.parse(["0218/0269 U", "ECL • EN", "™ & © 2026 WIZARDS"])?.displayIdentifier,
            "ECL 218 EN"
        )
    }

    /// A bare four-digit number in a footer is a copyright year far more often
    /// than a collector number.
    func testMagicRejectsABareYearAsACollectorNumber() {
        XCTAssertNil(magicProfile.parse(["2026", "ECL", "EN"]))
    }

    func testMagicAcceptsALegitimateFourDigitCollectorNumber() {
        XCTAssertEqual(
            magicProfile.parse(["1234", "PLST", "EN"])?.displayIdentifier,
            "PLST 1234 EN"
        )
    }

    /// Footer association is bounded. Text four observations away is not footer.
    func testMagicDoesNotAssociateADistantNumberWithTheFooter() {
        XCTAssertNil(magicProfile.parse(["0218", "GRIZZLY BEARS", "CREATURE — BEAR", "ECL", "EN"]))
    }

    func testMagicSupportsFourCharacterPrintedCodes() {
        XCTAssertEqual(
            magicProfile.parse(["0042", "PLST", "EN"])?.displayIdentifier,
            "PLST 42 EN"
        )
    }

    func testMagicStillRejectsTwoIdentitiesInOneFrame() {
        XCTAssertNil(magicProfile.parse(["ECL • 0218 • EN", "MH3 • 0044 • EN"]))
    }

    // MARK: - Automatic game recognition

    private var combinedProfile: RecognitionProfile {
        RecognitionProfile(magic: magicProfile)
    }

    func testPokemonCardIsRecognisedWithoutBeingToldTheGame() {
        XCTAssertEqual(
            combinedProfile.identify(["ILLUS. MASCAGNI", "OBF 223/197"]),
            .identified(ScanParser.parsePokemon("OBF 223/197")!)
        )
    }

    func testMagicCardIsRecognisedWithoutBeingToldTheGame() {
        guard case let .identified(identifier) = combinedProfile.identify(["0218/0269 U", "ECL • EN"]) else {
            return XCTFail("Expected a Magic identification")
        }
        XCTAssertEqual(identifier.game, .magic)
        XCTAssertEqual(identifier.displayIdentifier, "ECL 218 EN")
    }

    /// One frame cannot be two different cards. Rejecting is what a later pass is
    /// for; ranking would be a guess.
    func testFrameClaimingBothGamesIsRejected() {
        XCTAssertEqual(
            combinedProfile.identify(["OBF 223/197", "ECL • 0218 • EN"]),
            .ambiguous
        )
    }

    func testFrameWithNothingReadableIsNotAnIdentification() {
        XCTAssertEqual(combinedProfile.identify(["ILLUS. MASCAGNI"]), .nothing)
    }

    /// The printed English marker is what separates the games even when a set
    /// code exists in both directories.
    func testCollidingSetCodeDoesNotMakeAPokemonCardAmbiguous() {
        let overlapping = RecognitionProfile(
            magic: MagicScanProfile(definitions: [.init(code: "OBF", printedSize: nil)])
        )

        guard case let .identified(identifier) = overlapping.identify(["OBF 223/197"]) else {
            return XCTFail("Expected a Pokémon identification")
        }
        XCTAssertEqual(identifier.game, .pokemon)
    }

    func testVisionVocabularyCarriesBothGamesWithoutDuplicates() {
        let words = RecognitionProfile(
            magic: MagicScanProfile(definitions: [.init(code: "OBF", printedSize: nil), .init(code: "ECL", printedSize: nil)])
        ).customWords

        XCTAssertTrue(words.contains("OBF"))
        XCTAssertTrue(words.contains("ECL"))
        XCTAssertTrue(words.contains("EN"))
        XCTAssertEqual(words.count, Set(words).count)
    }

    /// Without a Magic directory the scanner still reads Pokémon, which is what
    /// makes installing the directory a background concern.
    func testPokemonWorksBeforeTheMagicDirectoryIsInstalled() {
        guard case let .identified(identifier) = RecognitionProfile.pokemonOnly.identify(["OBF 223/197"]) else {
            return XCTFail("Expected a Pokémon identification")
        }
        XCTAssertEqual(identifier.game, .pokemon)
        XCTAssertEqual(RecognitionProfile.pokemonOnly.identify(["ECL • 0218 • EN"]), .nothing)
    }

    // MARK: - Bundled set directory

    func testBundledMagicSnapshotIsUsable() {
        let snapshot = MagicSetSnapshot.definitions
        XCTAssertGreaterThan(snapshot.count, 100)
        XCTAssertEqual(snapshot.count, Set(snapshot.map(\.code)).count, "codes must be unique")

        for definition in snapshot {
            XCTAssertEqual(definition.code, definition.code.uppercased())
            XCTAssertTrue((3...4).contains(definition.code.count), "\(definition.code) has an unusable length")
        }
    }
}
