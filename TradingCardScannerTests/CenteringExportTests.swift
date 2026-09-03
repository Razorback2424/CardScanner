import XCTest
import UIKit
@testable import TradingCardScanner

final class CenteringExportTests: XCTestCase {
    private func measurement(
        width: Int = 672,
        height: Int = 936,
        outer: CardCenteringEdges = CardCenteringEdges(left: 20, top: 24, right: 652, bottom: 912),
        inner: CardCenteringEdges = CardCenteringEdges(left: 60, top: 64, right: 612, bottom: 872)
    ) -> CardCenteringMeasurement {
        var value = CardCenteringMeasurement(
            imageWidth: width,
            imageHeight: height,
            outer: outer,
            inner: inner,
            warnings: []
        )
        value.refreshWarnings()
        return value
    }

    private func photo(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: - Composition

    /// The whole point of the export: the figures travel with the picture, so
    /// the canvas is always taller than the photo it contains.
    func testExportAddsAPanelBelowThePhoto() {
        let value = measurement()
        let rendered = CardCenteringExport.render(
            image: photo(width: value.imageWidth, height: value.imageHeight),
            measurement: value,
            rotationDegrees: 0
        )

        let photoHeight = rendered.size.width * CGFloat(value.imageHeight) / CGFloat(value.imageWidth)
        XCTAssertGreaterThan(rendered.size.height, photoHeight)
    }

    func testLargeImageKeepsItsOwnWidth() {
        let value = measurement(width: 1_200, height: 1_672)
        let rendered = CardCenteringExport.render(
            image: photo(width: 1_200, height: 1_672),
            measurement: value,
            rotationDegrees: 0
        )

        XCTAssertEqual(rendered.size.width, 1_200)
    }

    /// A small photo is widened rather than rendered with labels too small to
    /// read. The export is meant to be looked at, not just stored.
    func testSmallImageIsWidenedSoLabelsStayLegible() {
        let value = measurement(width: 320, height: 446)
        let rendered = CardCenteringExport.render(
            image: photo(width: 320, height: 446),
            measurement: value,
            rotationDegrees: 0
        )

        XCTAssertEqual(rendered.size.width, 900)
    }

    /// A warning is part of the measurement's meaning, so it has to fit rather
    /// than be clipped off the bottom of the canvas.
    func testWarningBandMakesRoomForItself() {
        let clean = measurement()
        var warned = measurement()
        warned.inner.left = warned.outer.left - 5
        warned.refreshWarnings()
        XCTAssertFalse(warned.warnings.isEmpty)

        let image = photo(width: clean.imageWidth, height: clean.imageHeight)
        let cleanHeight = CardCenteringExport.render(
            image: image, measurement: clean, rotationDegrees: 0
        ).size.height
        let warnedHeight = CardCenteringExport.render(
            image: image, measurement: warned, rotationDegrees: 0
        ).size.height

        XCTAssertGreaterThan(warnedHeight, cleanHeight)
    }

    func testExportEncodesAsPNG() {
        let value = measurement()
        let rendered = CardCenteringExport.render(
            image: photo(width: value.imageWidth, height: value.imageHeight),
            measurement: value,
            rotationDegrees: 0
        )

        XCTAssertNotNil(rendered.pngData())
    }

    // MARK: - Filename

    /// The centering ratio carries a slash, which a path component cannot hold.
    func testFilenameCarriesTheRatioWithoutASlash() {
        let name = CardCenteringExport.filename(for: measurement())

        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasPrefix("Card Centering "))
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    func testFilenameFallsBackWhenThereIsNoRatioToName() {
        // Zero-width borders produce "—" for both ratios, which names nothing.
        let flat = measurement(
            outer: CardCenteringEdges(left: 10, top: 10, right: 100, bottom: 100),
            inner: CardCenteringEdges(left: 10, top: 10, right: 100, bottom: 100)
        )

        XCTAssertEqual(CardCenteringExport.filename(for: flat), "Card Centering.png")
    }
}

final class CardCenteringAnalyzerTests: XCTestCase {
    /// Reproduces the scanner-bed failure mode: the physical side edges are
    /// soft, the printed frame is strong, and an unrelated line sits near the
    /// right edge of the scan. The detector must choose one coherent card box.
    func testVerticalOuterEdgesUsePhysicalSilhouetteInsteadOfPlausibleFalsePair() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 420, height: 600),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 420, height: 600))

            // A low-contrast physical border, typical of a white scanner bed.
            UIColor(white: 0.90, alpha: 1).setFill()
            context.fill(CGRect(x: 35, y: 45, width: 350, height: 490))

            // Strong print/frame transitions inside the physical card.
            UIColor(white: 0.18, alpha: 1).setFill()
            // This left print edge plus the scanner seam make an almost exact
            // 5:7 box, which is why aspect-ratio fitting made the bug worse.
            context.fill(CGRect(x: 68, y: 45, width: 297, height: 490))

            // A scanner-bed seam that edge-candidate scoring can mistake for
            // the card's right edge.
            UIColor.black.setFill()
            context.fill(CGRect(x: 418, y: 100, width: 1, height: 400))
        }

        let result = try CardCenteringAnalyzer.analyze(XCTUnwrap(image.pngData()))

        XCTAssertEqual(result.measurement.outer.left, 35, accuracy: 2)
        XCTAssertEqual(result.measurement.outer.right, 384, accuracy: 2)
        XCTAssertEqual(result.measurement.outer.top, 44, accuracy: 2)
        XCTAssertEqual(result.measurement.outer.bottom, 534, accuracy: 2)
        XCTAssertEqual(result.measurement.inner.left, 67, accuracy: 2)
        XCTAssertEqual(result.measurement.inner.right, 364, accuracy: 2)
    }

    // MARK: - Auto-detected guides

    /// A card on a background, with an artwork rect inset by known borders.
    /// `angle` leans the card the way a hand-held photo does.
    private func syntheticCard(
        canvas: CGSize,
        cardRect: CGRect,
        borders: (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat),
        angle: CGFloat = 0,
        textured: Bool = false,
        decoyInsetFromArtTop: CGFloat? = nil,
        background: UIColor = UIColor(white: 0.55, alpha: 1),
        borderColor: UIColor = UIColor(red: 0.98, green: 0.85, blue: 0.20, alpha: 1),
        artFill: UIColor = UIColor(red: 0.10, green: 0.25, blue: 0.55, alpha: 1)
    ) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))

            cg.saveGState()
            cg.translateBy(x: cardRect.midX, y: cardRect.midY)
            cg.rotate(by: angle * .pi / 180)
            cg.translateBy(x: -cardRect.midX, y: -cardRect.midY)

            borderColor.setFill()
            cg.fill(cardRect)
            let art = CGRect(
                x: cardRect.minX + borders.left,
                y: cardRect.minY + borders.top,
                width: cardRect.width - borders.left - borders.right,
                height: cardRect.height - borders.top - borders.bottom
            )
            artFill.setFill()
            cg.fill(art)
            if let decoy = decoyInsetFromArtTop {
                // A high-contrast horizontal feature just inside the artwork,
                // like the banner across the top of many card designs.
                UIColor(white: 0.97, alpha: 1).setFill()
                cg.fill(CGRect(x: art.minX, y: art.minY + decoy, width: art.width, height: 10))
            }
            if textured {
                UIColor(white: 0.92, alpha: 1).setFill()
                cg.fill(CGRect(x: art.minX + 6, y: art.minY + 8, width: art.width - 12, height: 26))
                UIColor(red: 0.75, green: 0.20, blue: 0.15, alpha: 1).setFill()
                cg.fill(CGRect(x: art.minX + 10, y: art.midY, width: art.width - 20, height: 40))
                UIColor(white: 0.15, alpha: 1).setFill()
                cg.fill(CGRect(x: art.minX + 6, y: art.maxY - 40, width: art.width - 12, height: 18))
            }
            cg.restoreGState()
        }.pngData()!
    }

    /// Borders are compared with a tolerance because the guides land on whole
    /// pixels and a resampled edge is a pixel wide. The assertion that matters
    /// is that the four borders are recovered at all — every failure this
    /// covers produced numbers that were wrong by tens of pixels while still
    /// looking internally consistent, so nothing warned the person reading them.
    private func assertBorders(
        _ data: Data,
        _ expected: (left: Int, top: Int, right: Int, bottom: Int),
        tolerance: Int = 4,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let m = try CardCenteringAnalyzer.analyze(data).measurement
            let actual = (m.leftBorder, m.topBorder, m.rightBorder, m.bottomBorder)
            let deltas = [
                abs(actual.0 - expected.left), abs(actual.1 - expected.top),
                abs(actual.2 - expected.right), abs(actual.3 - expected.bottom)
            ]
            XCTAssertTrue(
                deltas.allSatisfy { $0 <= tolerance },
                "\(label): borders \(actual) differ from \(expected) by more than \(tolerance)px",
                file: file, line: line
            )
        } catch {
            XCTFail("\(label): analyze threw \(error)", file: file, line: line)
        }
    }

    private let offCenter = (left: 20, top: 25, right: 60, bottom: 55)

    /// The scanner case, which is the one the detector was tuned for.
    func testRecoversBordersWhenTheCardFillsTheFrame() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (20, 25, 60, 55)
        ), offCenter, "fills frame")
    }

    /// A photographed card sits well inside the frame. The outer edges used to
    /// be searched for only in the outer 22% of the *image*, so a card whose
    /// top edge lands at 30% was measured against a strip of pure background
    /// and the reported centering was meaningless.
    func testRecoversBordersWhenTheCardIsSmallInTheFrame() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 800, height: 1000),
            cardRect: CGRect(x: 240, y: 300, width: 320, height: 400),
            borders: (20, 25, 60, 55)
        ), offCenter, "card at 40% of frame")
    }

    /// A pale border on a pale background makes the outer edge weaker than the
    /// border-to-artwork edge just inside it. Picking the first gradient peak
    /// past a threshold therefore locked onto the inner edge and measured every
    /// border from the wrong baseline.
    func testRecoversBordersWhenTheOuterEdgeIsLowContrast() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (20, 25, 60, 55),
            background: UIColor(white: 0.88, alpha: 1),
            borderColor: UIColor(white: 0.98, alpha: 1)
        ), offCenter, "white border on light background")
    }

    /// Artwork with its own strong internal edges must not be mistaken for the
    /// border transition.
    func testArtworkDetailDoesNotDisplaceTheInnerGuides() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (20, 25, 60, 55),
            textured: true
        ), offCenter, "textured artwork")
    }

    /// Inner edges are found by averaging gradients down whole columns and
    /// across whole rows, so a couple of degrees of lean smears the transition
    /// over twenty pixels and leaves no peak to find. The analyzer straightens
    /// the card before measuring rather than requiring it by hand.
    func testStraightensASkewedCardBeforeMeasuring() {
        for angle in [CGFloat(-2), -1, 0.5, 1, 2] {
            assertBorders(syntheticCard(
                canvas: CGSize(width: 500, height: 700),
                cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                borders: (20, 25, 60, 55),
                angle: angle
            ), offCenter, "skewed \(angle)°")
        }
    }

    /// The correction has to run the right way. Rotating with the lean instead
    /// of against it doubles the skew, and the straightened pass then measures
    /// worse than the crooked one it replaced.
    func testSkewCorrectionOpposesTheLean() throws {
        for angle in [CGFloat(-2), 2] {
            let analysis = try CardCenteringAnalyzer.analyze(syntheticCard(
                canvas: CGSize(width: 500, height: 700),
                cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                borders: (20, 25, 60, 55),
                angle: angle
            ))
            XCTAssertEqual(
                analysis.appliedRotationDegrees,
                Double(-angle),
                accuracy: 0.4,
                "a card leaning \(angle)° must be rotated back the other way"
            )
        }
    }

    /// An explicit rotation is the person's answer and must be honoured rather
    /// than silently replaced by the detector's own estimate.
    func testManualRotationIsNotOverriddenByAutoCorrection() throws {
        let analysis = try CardCenteringAnalyzer.analyze(
            syntheticCard(
                canvas: CGSize(width: 500, height: 700),
                cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                borders: (20, 25, 60, 55),
                angle: 2
            ),
            rotationDegrees: 5
        )
        XCTAssertEqual(analysis.appliedRotationDegrees, 5)
    }

    /// Borders differ from each other by design here — that is the whole point
    /// of a centering measurement, and the reading for one side must not be
    /// influenced by what the others came out as.
    func testUnequalBordersAreEachMeasuredOnTheirOwnEvidence() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (15, 20, 75, 70)
        ), (left: 15, top: 20, right: 75, bottom: 70), "strong miscut")
    }

    /// Three sides alike and one very different. Scoring a candidate by how
    /// close it sits to the other sides' widths made the odd side the one most
    /// likely to be read wrong.
    func testOneOddBorderIsNotPulledTowardTheOthers() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (15, 15, 15, 70)
        ), (left: 15, top: 15, right: 15, bottom: 70), "one odd side")
    }

    /// The case the old border prior got badly wrong: a thin top border with a
    /// banner just inside the artwork, on a card whose other three borders are
    /// wide. The peer median sat nearer the banner than the truth, so the top
    /// border read 49px instead of 15 — a miscut card reported as far better
    /// centred than it is. Strength and shallowness decide it now, so the
    /// banner behind the border no longer wins.
    func testArtworkBannerDoesNotWinOverAThinBorder() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (60, 15, 60, 60),
            decoyInsetFromArtTop: 25
        ), (left: 60, top: 15, right: 60, bottom: 60), "thin border behind a banner")
    }

    /// A dark border against dark artwork, with a bright banner just inside it.
    /// The border transition is faint and the banner is brilliant, so the
    /// loudest edge in the band is the wrong one by thirty pixels — the reason
    /// the inner guides follow the border's colour rather than its contrast.
    func testFaintBorderIsFollowedPastLouderArtwork() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (40, 40, 40, 40),
            decoyInsetFromArtTop: 30,
            borderColor: UIColor(white: 0.06, alpha: 1),
            artFill: UIColor(white: 0.16, alpha: 1)
        ), (left: 40, top: 40, right: 40, bottom: 40), "faint border, loud artwork")
    }

    // MARK: - Saying when it does not know

    /// The ordinary case must stay quiet. A note that appears on good scans is
    /// worse than none, because it trains people to ignore it.
    func testAConfidentMeasurementCarriesNoNotes() throws {
        let m = try CardCenteringAnalyzer.analyze(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (20, 25, 60, 55)
        )).measurement
        XCTAssertTrue(m.detectionNotes.isEmpty, "unexpected notes: \(m.detectionNotes)")
        XCTAssertTrue(m.warnings.isEmpty, "unexpected warnings: \(m.warnings)")
    }

    /// Nothing card-shaped in the frame at all. The gradient scan still returns
    /// numbers — it always does — so the note is the only thing separating that
    /// from a measurement.
    func testAnImageWithNoCardSaysTheOutlineWasNotFound() throws {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 700)).image { ctx in
            UIColor(white: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 500, height: 700))
        }.pngData()!

        let m = try CardCenteringAnalyzer.analyze(blank).measurement
        XCTAssertTrue(
            m.warnings.contains { $0.contains("outline") },
            "a guess must not look like a measurement: \(m.warnings)"
        )
    }

    /// A card photographed sideways is still a card, and every number this
    /// screen reports is per edge rather than per axis.
    func testACardPhotographedSidewaysIsStillFound() {
        assertBorders(syntheticCard(
            canvas: CGSize(width: 1000, height: 800),
            cardRect: CGRect(x: 160, y: 160, width: 680, height: 480),
            borders: (25, 20, 55, 60)
        ), (left: 25, top: 20, right: 55, bottom: 60), "landscape card")
    }

    /// Beyond the correctable range the lean is not something to take out
    /// arithmetically. Rotation here is display-only and does not re-run
    /// detection, so the person is told to straighten the source instead.
    func testAStronglyRotatedCardAsksForAStraighterPhoto() throws {
        let m = try CardCenteringAnalyzer.analyze(syntheticCard(
            canvas: CGSize(width: 900, height: 1000),
            cardRect: CGRect(x: 210, y: 160, width: 480, height: 680),
            borders: (20, 25, 60, 55),
            angle: 30
        )).measurement
        XCTAssertTrue(
            m.warnings.contains { $0.contains("rotated") },
            "expected a rotation note, got \(m.warnings)"
        )
    }

    /// Notes describe how the guides were found, so they must survive the
    /// geometry checks that rerun every time a guide is dragged.
    func testDetectionNotesSurviveAGuideAdjustment() {
        var m = CardCenteringMeasurement(
            imageWidth: 500,
            imageHeight: 700,
            outer: CardCenteringEdges(left: 10, top: 10, right: 490, bottom: 690),
            inner: CardCenteringEdges(left: 30, top: 35, right: 430, bottom: 635),
            warnings: [],
            detectionNotes: ["Outline note."]
        )
        m.refreshWarnings()
        XCTAssertEqual(m.warnings, ["Outline note."])
    }

    /// A card bled to the edges of the frame leaves no surrounding surface to
    /// recognise it against, so the outline settles on the artwork and the
    /// "borders" get measured inside the picture. The image is genuinely
    /// ambiguous — the old detector read it the same way — but the result must
    /// not be handed over looking like a measurement.
    func testABledToEdgeCardIsNotReportedAsCertain() throws {
        let m = try CardCenteringAnalyzer.analyze(syntheticCard(
            canvas: CGSize(width: 480, height: 680),
            cardRect: CGRect(x: 0, y: 0, width: 480, height: 680),
            borders: (20, 25, 60, 55)
        )).measurement
        XCTAssertFalse(m.warnings.isEmpty, "a reading this far off must say so")
    }
}
