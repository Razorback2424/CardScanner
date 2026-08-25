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

    func testModernPokemonCollectorSuffixIsPreserved() {
        guard case let .pokemon(_, cardNumber, _, _)? = ScanParser.parsePokemon("PBL 040a/084") else {
            return XCTFail("Expected a suffix-bearing Pokémon identifier")
        }
        XCTAssertEqual(cardNumber, "040a")
        XCTAssertEqual(ScanParser.parsePokemon("PBL 040a/084")?.displayIdentifier, "PBL 40a/84")
        XCTAssertNotEqual(
            ScanParser.parsePokemon("PBL 040a/084"),
            ScanParser.parsePokemon("PBL 040/084")
        )
    }

    func testBlackStarPromoPrefixesResolveWithoutInventingADenominator() {
        let fixtures: [(text: String, setID: String, localID: String, display: String)] = [
            ("BW01", "bwp", "BW01", "BW 01"),
            ("XY 01", "xyp", "XY01", "XY 01"),
            ("SM01", "smp", "SM01", "SM 01"),
            ("SWSH001", "swshp", "SWSH001", "SWSH 001"),
            ("SVP EN 001", "svp", "001", "SVP 001"),
            ("MEP EN 083", "mep", "083", "MEP 083")
        ]

        for fixture in fixtures {
            guard case let .pokemonPromo(_, localID, definition)? = ScanParser.parsePokemon(fixture.text) else {
                return XCTFail("Expected promo identifier for \(fixture.text)")
            }
            XCTAssertEqual(definition.tcgdexSetID, fixture.setID)
            XCTAssertEqual(localID, fixture.localID)
            XCTAssertEqual(ScanParser.parsePokemon(fixture.text)?.displayIdentifier, fixture.display)
        }
    }

    func testPromoParserDoesNotReinterpretModernExpansionIdentifier() {
        XCTAssertEqual(ScanParser.parsePokemon("OBF 223/197")?.displayIdentifier, "OBF 223/197")
        XCTAssertNil(ScanParser.parsePokemon("MEP 083/084"))
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

    // MARK: - Historical Pokémon evidence and strict resolution

    func testHistoricalFooterAndTitleCanBeCapturedInSeparateSteps() throws {
        let number = try XCTUnwrap(
            PokemonHistoricalScanParser.numberEvidence(in: ["066/196"])
        )
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(number: number, titleLines: ["Gengar"])
        )

        guard case let .pokemonHistorical(evidence) = identifier else {
            return XCTFail("Expected historical evidence")
        }
        XCTAssertEqual(evidence.number.displayIdentifier, "66/196")
        XCTAssertEqual(evidence.titleCandidates, ["gengar"])
    }

    func testHistoricalNumberRequiresRepeatedObservationBeforeTitleCapture() throws {
        let number = try XCTUnwrap(
            PokemonHistoricalScanParser.numberEvidence(in: ["066/196"])
        )
        var window = HistoricalNumberConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(number))
        XCTAssertEqual(window.observe(number), number)
    }

    func testHistoricalParserKeepsHoloSubsetDenominatorSeparateFromSetCount() throws {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(
                numberLines: ["H11/H32"],
                titleLines: ["Houndoom"]
            )
        )
        guard case let .pokemonHistorical(evidence) = identifier else {
            return XCTFail("Expected historical Pokémon evidence")
        }
        XCTAssertEqual(evidence.number.localID, "H11")
        XCTAssertEqual(evidence.number.denominator, 32)
        XCTAssertEqual(evidence.number.scheme, .subset(prefix: "H"))
        XCTAssertEqual(identifier.displayIdentifier, "H11/H32")
        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.candidateSetIDs(for: evidence, in: []),
            ["ecard2", "ecard3"]
        )
    }

    func testHistoricalParserTreatsOrdinaryNumberAsOfficialSetScheme() throws {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(
                numberLines: ["62/132"],
                titleLines: ["Blaine's Growlithe"]
            )
        )
        guard case let .pokemonHistorical(evidence) = identifier else {
            return XCTFail("Expected historical Pokémon evidence")
        }
        XCTAssertEqual(evidence.number.scheme, .officialSet)
        XCTAssertEqual(evidence.titleCandidates, ["blaine s growlithe"])
        let directory = try historicalDirectory([
            ("gym1", 132, 132),
            ("gym2", 132, 132),
            ("me01", 132, 132),
            ("different", 131, 132)
        ])
        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.candidateSetIDs(for: evidence, in: directory),
            ["gym1", "gym2", "me01"]
        )
    }

    func testHistoricalCollectorSuffixIsIdentityNotDecoration() throws {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(
                numberLines: ["40a/70"],
                titleLines: ["Example"]
            )
        )
        guard case let .pokemonHistorical(evidence) = identifier else {
            return XCTFail("Expected historical evidence")
        }
        XCTAssertEqual(evidence.number.localID, "40a")

        let candidates = [
            historicalCard("set-40", set: "set", number: "40", name: "Example"),
            historicalCard("set-40a", set: "set", number: "40a", name: "Example")
        ]
        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.resolve(
                evidence,
                candidateSetIDs: ["set"],
                in: candidates
            ),
            .unique(candidates[1])
        )
    }

    func testHistoricalParserRejectsMismatchedSubsetPrefixes() {
        XCTAssertNil(
            PokemonHistoricalScanParser.parse(
                numberLines: ["H11/TG32"],
                titleLines: ["Houndoom"]
            )
        )
    }

    func testGymNameNumberDenominatorCollisionIsAmbiguous() throws {
        let evidence = try historicalEvidence(number: "62/132", title: "Blaine's Growlithe")
        let cards = [
            historicalCard("gym1-62", set: "gym1", number: "62", name: "Blaine's Growlithe"),
            historicalCard("gym2-62", set: "gym2", number: "62", name: "Blaine's Growlithe")
        ]

        guard case let .ambiguous(matches) = PokemonHistoricalIdentityResolver.resolve(
            evidence,
            candidateSetIDs: ["gym1", "gym2"],
            in: cards
        ) else {
            return XCTFail("A real cross-set collision must never select the first candidate")
        }
        XCTAssertEqual(matches.map(\.providerID), ["gym1-62", "gym2-62"])
    }

    func testEveryKnownGymIdenticalNameAndNumberPairRemainsAmbiguous() throws {
        let collisions: [(String, String)] = [
            ("62", "Blaine's Growlithe"),
            ("127", "Fighting Energy"),
            ("128", "Fire Energy"),
            ("129", "Grass Energy"),
            ("130", "Lightning Energy"),
            ("131", "Psychic Energy"),
            ("132", "Water Energy")
        ]

        for (number, name) in collisions {
            let evidence = try historicalEvidence(number: "\(number)/132", title: name)
            let cards = [
                historicalCard("gym1-\(number)", set: "gym1", number: number, name: name),
                historicalCard("gym2-\(number)", set: "gym2", number: number, name: name)
            ]
            guard case .ambiguous = PokemonHistoricalIdentityResolver.resolve(
                evidence,
                candidateSetIDs: ["gym1", "gym2"],
                in: cards
            ) else {
                return XCTFail("\(name) \(number)/132 must remain ambiguous")
            }
        }
    }

    func testBothKnownECardHoloCollisionsRemainAmbiguous() throws {
        for (number, name) in [("H2", "Arcanine"), ("H11", "Houndoom")] {
            let evidence = try historicalEvidence(number: "\(number)/H32", title: name)
            let cards = [
                historicalCard("ecard2-\(number)", set: "ecard2", number: number, name: name),
                historicalCard("ecard3-\(number)", set: "ecard3", number: number, name: name)
            ]
            guard case .ambiguous = PokemonHistoricalIdentityResolver.resolve(
                evidence,
                candidateSetIDs: ["ecard2", "ecard3"],
                in: cards
            ) else {
                return XCTFail("\(name) \(number)/H32 must remain ambiguous")
            }
        }
    }

    func testUniqueHistoricalCandidateCanResolve() throws {
        let evidence = try historicalEvidence(number: "H1/H32", title: "Ampharos")
        let expected = historicalCard("ecard2-H01", set: "ecard2", number: "H01", name: "Ampharos")
        let cards = [
            expected,
            historicalCard("ecard3-H01", set: "ecard3", number: "H01", name: "Alakazam")
        ]

        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.resolve(
                evidence,
                candidateSetIDs: ["ecard2", "ecard3"],
                in: cards
            ),
            .unique(expected)
        )
    }

    func testHistoricalScannerDoesNotUseRelaxedCSVNameMatching() throws {
        let evidence = try historicalEvidence(number: "1/102", title: "Mew")
        let misleading = historicalCard(
            "base1-1",
            set: "base1",
            number: "1",
            name: "Mew ex"
        )
        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.resolve(
                evidence,
                candidateSetIDs: ["base1", "hgss4"],
                in: [misleading]
            ),
            .unsupported
        )
    }

    func testOfficialCount32DoesNotMasqueradeAsHoloSubset() throws {
        let ordinary = try historicalEvidence(number: "11/32", title: "Houndoom")
        let directory = try historicalDirectory([("ordinary32", 32, 32)])
        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.candidateSetIDs(for: ordinary, in: directory),
            ["ordinary32"]
        )

        let subset = try historicalEvidence(number: "H11/H32", title: "Houndoom")
        XCTAssertEqual(
            PokemonHistoricalIdentityResolver.candidateSetIDs(for: subset, in: directory),
            ["ecard2", "ecard3"]
        )
    }

    func testSecretInclusiveTotalsAreNotAcceptedAsPrintedDenominators() throws {
        let neoRevelationTotal = try historicalEvidence(number: "1/66", title: "Ampharos")
        let neoDestinyTotal = try historicalEvidence(number: "1/113", title: "Dark Ampharos")
        let directory = try historicalDirectory([
            ("neo3", 64, 66),
            ("neo4", 105, 113)
        ])
        XCTAssertTrue(
            PokemonHistoricalIdentityResolver.candidateSetIDs(
                for: neoRevelationTotal,
                in: directory
            ).isEmpty
        )
        XCTAssertTrue(
            PokemonHistoricalIdentityResolver.candidateSetIDs(
                for: neoDestinyTotal,
                in: directory
            ).isEmpty
        )
    }

    func testBaseSetAndTriumphantDugtrioCollisionIsAmbiguous() throws {
        try assertDirectoryDerivedHistoricalCollision(
            number: "19/102",
            title: "Dugtrio",
            sets: ["base1", "hgss4"]
        )
    }

    func testSouthernIslandsAndDetectivePikachuLickitungCollisionIsAmbiguous() throws {
        try assertDirectoryDerivedHistoricalCollision(
            number: "16/18",
            title: "Lickitung",
            sets: ["det1", "si1"]
        )
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

    private func historicalEvidence(
        number: String,
        title: String
    ) throws -> PokemonHistoricalScanEvidence {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(numberLines: [number], titleLines: [title])
        )
        guard case let .pokemonHistorical(evidence) = identifier else {
            throw NSError(domain: "ScanParserTests", code: 1)
        }
        return evidence
    }

    private func historicalCard(
        _ providerID: String,
        set: String,
        number: String,
        name: String
    ) -> PokemonCatalogCardIdentity {
        PokemonCatalogCardIdentity(
            providerID: providerID,
            setID: set,
            setName: set,
            localID: number,
            name: name
        )
    }

    private func historicalDirectory(
        _ sets: [(id: String, official: Int, total: Int)]
    ) throws -> [CatalogSetReference] {
        try sets.map { set in
            let json = """
            {
              "id": "\(set.id)",
              "name": "\(set.id)",
              "cardCount": { "total": \(set.total), "official": \(set.official) }
            }
            """
            return try JSONDecoder().decode(
                CatalogSetReference.self,
                from: try XCTUnwrap(json.data(using: .utf8))
            )
        }
    }

    private func assertDirectoryDerivedHistoricalCollision(
        number: String,
        title: String,
        sets: [String]
    ) throws {
        let evidence = try historicalEvidence(number: number, title: title)
        let denominator = try XCTUnwrap(Int(number.split(separator: "/").last ?? ""))
        let localID = String(number.split(separator: "/")[0])
        let directory = try historicalDirectory(
            sets.map { ($0, denominator, denominator) }
        )
        let candidateSetIDs = PokemonHistoricalIdentityResolver.candidateSetIDs(
            for: evidence,
            in: directory
        )
        XCTAssertEqual(candidateSetIDs, sets.sorted())

        let cards = sets.map {
            historicalCard("\($0)-\(localID)", set: $0, number: localID, name: title)
        }
        guard case let .ambiguous(matches) = PokemonHistoricalIdentityResolver.resolve(
            evidence,
            candidateSetIDs: candidateSetIDs,
            in: cards
        ) else {
            return XCTFail("\(title) \(number) must remain ambiguous")
        }
        XCTAssertEqual(matches.map(\.setID), sets.sorted())
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

    // MARK: - Magic footer geometry

    func testFarRightFractionIsRejectedFromMagicFooterRole() {
        let profile = MagicScanProfile(definitions: [
            .init(code: "FIN", printedSize: nil)
        ])
        let lines = [
            // Vision can merge the anchors with a long artist credit. Its width
            // must not become the allowed gap to the number.
            recognized("FIN • EN / TOSHIAKI TAKAYAMA", x: 0.10, width: 0.48),
            recognized("3/3", x: 0.82, width: 0.08)
        ]

        XCTAssertEqual(profile.parseOutcome(lines), .spatiallyRejectedCollector)
        XCTAssertNil(profile.parseOutcome(lines).identifier)
    }

    func testLeftCollectorNumberWinsWhileFarRightFractionIsIgnored() {
        let profile = MagicScanProfile(definitions: [
            .init(code: "FIN", printedSize: nil)
        ])
        let lines = [
            // Match the observed top-to-bottom Vision shape on FIN 36.
            recognized("3/3", x: 0.82, width: 0.08),
            recognized("0036 FFVII", x: 0.04, width: 0.18),
            recognized("FIN • EN / TOSHIAKI TAKAYAMA", x: 0.10, width: 0.48),
            // Mythic rarity corroborates that this is footer text. It is not a
            // set code or content-kind marker and must not change identity.
            recognized("M © 2025 WIZARDS", x: 0.58, width: 0.30)
        ]

        XCTAssertEqual(profile.parseOutcome(lines).identifier?.displayIdentifier, "FIN 36 EN")
    }

    func testRightSideHistoricalFractionRemainsEligibleWithoutMagicAnchors() {
        let lines = [recognized("3/3", x: 0.82, width: 0.08)]
        let profile = MagicScanProfile(definitions: [
            .init(code: "FIN", printedSize: nil)
        ])

        XCTAssertEqual(profile.parseOutcome(lines), .nothing)
        XCTAssertEqual(
            PokemonHistoricalScanParser.numberEvidence(in: lines.map(\.text))?.displayIdentifier,
            "3/3"
        )
    }

    func testSpatiallyRejectedMagicFractionSuppressesOnlyFallbackOutcome() {
        let profile = RecognitionProfile(
            magic: MagicScanProfile(definitions: [
                .init(code: "FIN", printedSize: nil)
            ])
        )
        let lines = [
            recognized("FIN", x: 0.10, width: 0.08),
            recognized("EN", x: 0.22, width: 0.06),
            recognized("3/3", x: 0.82, width: 0.08)
        ]

        XCTAssertEqual(profile.identify(lines), .spatiallyRejectedMagicCollector)
    }

    private func recognized(
        _ text: String,
        x: CGFloat,
        width: CGFloat,
        y: CGFloat = 0.40,
        height: CGFloat = 0.12
    ) -> RecognizedLine {
        RecognizedLine(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
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
