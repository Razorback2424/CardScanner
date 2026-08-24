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
