import XCTest
@testable import TradingCardScanner

/// Everything that has to be true between "scan the card name" appearing and a
/// title reading being accepted.
///
/// Reproduced from a device scan of Spinarak 78/109 (EX Team Rocket Returns).
/// The footer of that card prints `GKD-3F0-0SG` beside the collector number, and
/// title capture read it three times with the usual 0/O wobble before the user
/// could move the camera.
final class TitleCaptureGateTests: XCTestCase {
    private let number = PokemonPrintedNumberEvidence(
        localID: "78",
        denominator: 109,
        scheme: .officialSet
    )

    /// The footer band as Vision returns it.
    private let footer = [
        "GKD-3F0-0SG", "©2004 Pokémon/Nintendo", "78/109",
        "weakness", "resistance", "retreat cost"
    ]

    // MARK: - Not the same band twice

    func testTextAlreadySeenInTheFooterIsNotACardName() {
        let signature = PokemonHistoricalScanParser.footerSignature(from: footer)

        for line in footer {
            XCTAssertNil(
                PokemonHistoricalScanParser.parse(
                    number: number,
                    titleLines: [line],
                    excludingFooter: signature
                ),
                "\(line.debugDescription) was already read from the footer"
            )
        }
    }

    /// The three readings from the device differ only by OCR confusing 0 and O.
    /// Rejecting the exact string would have let the other two through.
    func testFooterRejectionSurvivesCharacterConfusion() {
        let signature = PokemonHistoricalScanParser.footerSignature(from: footer)

        for wobble in ["gkd 3fo 0sg", "gkd 3fo osg", "GKD 3F0 OSG"] {
            XCTAssertNil(
                PokemonHistoricalScanParser.parse(
                    number: number,
                    titleLines: [wobble],
                    excludingFooter: signature
                ),
                "\(wobble.debugDescription) is the print code read badly"
            )
        }
    }

    /// The actual card name must still get through the same filter.
    func testTheCardNameIsStillAccepted() {
        let signature = PokemonHistoricalScanParser.footerSignature(from: footer)

        XCTAssertNotNil(
            PokemonHistoricalScanParser.parse(
                number: number,
                titleLines: ["Spinarak", "50 HP"],
                excludingFooter: signature
            )
        )
    }

    // MARK: - Time to reposition

    /// The prompt appears while the camera is still on the footer. Reading
    /// immediately means the first frames are whatever is next to the number,
    /// so title capture waits long enough to read the message and move.
    func testTitleCaptureWaitsBeforeReadingAnything() {
        var gate = TitleCaptureGate(startedAt: 100)

        XCTAssertFalse(gate.isOpen(at: 100), "same instant as the prompt")
        XCTAssertFalse(gate.isOpen(at: 100 + TitleCaptureGate.settleInterval - 0.01))
        XCTAssertTrue(gate.isOpen(at: 100 + TitleCaptureGate.settleInterval))
        XCTAssertTrue(gate.isOpen(at: 200), "and stays open afterwards")
    }

    /// Short enough not to feel like a stall.
    func testSettleIntervalIsAHumanPauseNotADelay() {
        XCTAssertGreaterThanOrEqual(TitleCaptureGate.settleInterval, 0.6)
        XCTAssertLessThanOrEqual(TitleCaptureGate.settleInterval, 1.5)
    }
}
