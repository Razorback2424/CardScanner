import XCTest
@testable import TradingCardScanner

/// Everything that has to be true between "scan the card name" appearing and a
/// title reading being accepted.
///
/// Reproduced from a device scan of Spinarak 78/109 (EX Team Rocket Returns).
/// The footer of that card prints `GKD-3F0-0SG` beside the collector number, and
/// title capture read it three times with the usual 0/O wobble before the user
/// could move the camera.
final class WholeCardHistoricalCaptureTests: XCTestCase {
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

    func testWholeCardRegionsAreContainedAndDoNotOverlap() {
        let card = CardFramingRegion.cardVisionRect
        let footer = CardFramingRegion.visionRect
        let title = CardFramingRegion.titleVisionRect

        XCTAssertTrue(card.contains(footer))
        XCTAssertTrue(card.contains(title))
        XCTAssertFalse(footer.intersects(title))
        XCTAssertLessThan(footer.midY, title.midY)
    }

    func testWholeCardGuideHasPhysicalTradingCardAspectRatioInSourcePixels() {
        let card = CardFramingRegion.cardVisionRect
        let sourcePixelAspect = card.width
            / card.height
            * CardFramingRegion.sourceImageAspectRatio

        XCTAssertEqual(
            sourcePixelAspect,
            CardFramingRegion.physicalCardAspectRatio,
            accuracy: 0.001
        )
    }

    func testHistoricalTitleRunsOnlyForAnOrdinaryFooterMiss() {
        let fraction = [RecognizedLine(text: "3/102")]
        XCTAssertEqual(
            HistoricalTitleRequestPolicy.number(for: .nothing, footerLines: fraction),
            PokemonPrintedNumberEvidence(localID: "3", denominator: 102, scheme: .officialSet)
        )
        XCTAssertNil(HistoricalTitleRequestPolicy.number(for: .ambiguous, footerLines: fraction))
        XCTAssertNil(
            HistoricalTitleRequestPolicy.number(
                for: .spatiallyRejectedMagicCollector,
                footerLines: fraction
            )
        )
    }

    func testAssistanceNeedsPersistentEvidenceAndNilScaleDoesNotMeanTooFar() {
        var monitor = CaptureAssistanceMonitor()
        let unknownScale = assessment(textHeight: nil)
        for _ in 0..<5 {
            XCTAssertNil(monitor.observe(unknownScale, hasFooterText: true).message)
        }

        monitor = CaptureAssistanceMonitor()
        let tinyText = assessment(textHeight: 5)
        XCTAssertNil(monitor.observe(tinyText, hasFooterText: true).message)
        XCTAssertNil(monitor.observe(tinyText, hasFooterText: true).message)
        XCTAssertNil(monitor.observe(tinyText, hasFooterText: true).message)
        XCTAssertEqual(monitor.observe(tinyText, hasFooterText: true).message, "Move closer")
    }

    func testStablePresentationSurvivesOneBlankOCRFrame() {
        var monitor = CaptureAssistanceMonitor()
        let tinyText = assessment(textHeight: 5)

        for _ in 0..<4 {
            _ = monitor.observe(tinyText, hasFooterText: true)
        }
        XCTAssertEqual(monitor.presentation, .cardStable)

        let blankFrame = monitor.observe(tinyText, hasFooterText: false)
        XCTAssertEqual(monitor.presentation, .cardStable)
        XCTAssertEqual(blankFrame.message, "Move closer")

        _ = monitor.observe(tinyText, hasFooterText: false)
        XCTAssertEqual(monitor.presentation, .cardStable)

        _ = monitor.observe(tinyText, hasFooterText: false)
        XCTAssertEqual(monitor.presentation, .unknown)
    }

    func testStablePresentationCounterIsBoundedAfterLongRun() {
        var monitor = CaptureAssistanceMonitor()
        let readableText = assessment(textHeight: 12)

        for _ in 0..<60 {
            _ = monitor.observe(readableText, hasFooterText: true)
        }
        XCTAssertEqual(monitor.presentation, .cardStable)

        var releaseFrame: Int?
        for frame in 1...4 {
            _ = monitor.observe(readableText, hasFooterText: false)
            if monitor.presentation == .unknown {
                releaseFrame = frame
                break
            }
        }

        XCTAssertNotNil(releaseFrame)
        XCTAssertLessThanOrEqual(releaseFrame ?? .max, 3)
    }

    func testCameraSettlingNeverProducesAComplaint() {
        var monitor = CaptureAssistanceMonitor()
        let settling = assessment(textHeight: 4, adjustingFocus: true)
        for _ in 0..<5 {
            XCTAssertNil(monitor.observe(settling, hasFooterText: true).message)
        }
    }

    private func assessment(
        textHeight: Float?,
        adjustingFocus: Bool = false
    ) -> CaptureAssessment {
        CaptureAssessment(
            detailSharpness: nil,
            horizontalMotion: nil,
            verticalMotion: nil,
            textPixelHeight: textHeight,
            localContrast: nil,
            clippedHighlightArea: nil,
            meanOCRConfidence: 0.8,
            isAdjustingFocus: adjustingFocus,
            isAdjustingExposure: false,
            exposureDuration: 1.0 / 120.0,
            iso: 100,
            lensPosition: nil,
            minimumFocusDistance: nil
        )
    }

}
