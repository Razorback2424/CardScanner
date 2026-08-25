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
}
