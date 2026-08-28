import XCTest
@testable import TradingCardScanner

/// What happens between asking for the card name and the user getting there.
///
/// On device the prompt appears while the camera is still on the number band, so
/// the first frames of title capture read whatever is printed near it — the
/// copyright line, the illustrator credit, the resistance/weakness row. None of
/// that is a card name, and treating it as one both burns the prompt and files
/// an unresolved scan for a card the user never got to present.
final class HistoricalTitleCaptureTests: XCTestCase {
    private let number = PokemonPrintedNumberEvidence(
        localID: "90",
        denominator: 202,
        scheme: .officialSet
    )

    /// Verbatim from a device scan of 90/202.
    func testCardFurnitureIsNotACardName() {
        let furniture = [
            "2020 Pokémon / Nintendo / Creatures / GAME FREAK",
            "©2020 Pokémon",
            "Illus. Shin Nagasawa",
            "resistance",
            "weakness",
            "retreat",
            "d",
            "HP",
            "Stage 1",
            "Basic",
            "Evolves from Pidgey"
        ]

        for line in furniture {
            XCTAssertNil(
                PokemonHistoricalScanParser.parse(number: number, titleLines: [line]),
                "\(line.debugDescription) is printed on every card and can never be its name"
            )
        }
    }

    /// The filter must not eat real names, including Trainer cards that contain
    /// the word Pokémon and energy cards that begin with "Basic".
    func testRealCardNamesSurvive() {
        let names = [
            "Pidgeotto", "Blaine's Growlithe", "Charizard ex",
            "Pokémon Catcher", "Basic Lightning Energy", "Professor's Research"
        ]

        for name in names {
            XCTAssertNotNil(
                PokemonHistoricalScanParser.parse(number: number, titleLines: [name]),
                "\(name.debugDescription) is a real card name"
            )
        }
    }

    /// A frame that is all furniture yields no evidence at all, so nothing
    /// confirms and the prompt stays up while the user moves the camera.
    func testAFrameOfPureFurnitureYieldsNoEvidence() {
        XCTAssertNil(
            PokemonHistoricalScanParser.parse(
                number: number,
                titleLines: [
                    "2020 pokemon nintendo", "d", "Illus. Shin Nagasawa",
                    "resistance", "weakness"
                ]
            )
        )
    }

    // MARK: - One card, one unresolved row

    /// Title OCR wobbles — "nintend" and "nintendo" a frame apart — so the same
    /// unreadable card produced two evidence values and two rows in the list.
    /// The printed number is what identifies the physical card here.
    func testUnresolvedScansAreOneRowPerPrintedNumber() {
        let first = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["2020 pokemon nintend"])
        )
        let second = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["2020 pokemon nintendo"])
        )

        var scans = UnresolvedScan.merging([], with: first)
        scans = UnresolvedScan.merging(scans, with: second)

        XCTAssertEqual(scans.count, 1, "one card, one row")
        XCTAssertEqual(
            scans[0].titleCandidates.sorted(),
            ["2020 pokemon nintend", "2020 pokemon nintendo"],
            "both readings are kept so the user can see what it actually read"
        )
    }

    /// A genuinely different card still gets its own row.
    func testADifferentPrintedNumberIsADifferentRow() {
        let other = PokemonPrintedNumberEvidence(
            localID: "91", denominator: 202, scheme: .officialSet
        )
        var scans = UnresolvedScan.merging([], with: .pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["a"])
        ))
        scans = UnresolvedScan.merging(scans, with: .pokemonHistorical(
            PokemonHistoricalScanEvidence(number: other, titleCandidates: ["b"])
        ))

        XCTAssertEqual(scans.count, 2)
    }

    func testCatalogMissNeedsThreeFreshSuppressionKeyMatchesInFiveFrames() {
        let first = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["first title"])
        )
        let titleVariant = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["second title"])
        )
        let different = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: "91", denominator: 202, scheme: .officialSet
                ),
                titleCandidates: ["other"]
            )
        )
        var window = SuppressionKeyVerificationWindow()

        XCTAssertFalse(window.observe(first))
        XCTAssertFalse(window.observe(different))
        XCTAssertFalse(window.observe(titleVariant))
        XCTAssertTrue(window.observe(first))
    }

    func testUnresolvedMergeUsesSuppressionKeyAcrossHistoricalTitleVariants() {
        let first = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["one"])
        )
        let second = ScanIdentifier.pokemonHistorical(
            PokemonHistoricalScanEvidence(number: number, titleCandidates: ["two"])
        )

        var scans = UnresolvedScan.merging([], with: first)
        scans = UnresolvedScan.merging(scans, with: second)

        XCTAssertEqual(scans.count, 1)
        XCTAssertEqual(scans[0].titleCandidates.sorted(), ["one", "two"])
    }
}
