import XCTest
@testable import TradingCardScanner

final class SlabFramingRegionTests: XCTestCase {
    func testPSAGeometryUsesSlabAspectAndKeepsBandsInsideOuterGuide() {
        let geometry = SlabFramingRegion.geometry(for: .psa)

        XCTAssertEqual(geometry.slabAspect, 3.25 / 5.25, accuracy: 0.0001)
        XCTAssertEqual(geometry.cardWindow, CGRect(x: 0.115, y: 0.105, width: 0.77, height: 0.666))
        XCTAssertTrue(geometry.cardWindow.maxY < geometry.labelBand.minY)
        XCTAssertTrue(geometry.labelBand.maxY <= 1)
        XCTAssertTrue(geometry.footerBand.minY >= geometry.cardWindow.minY)
        XCTAssertTrue(geometry.footerBand.maxY <= geometry.cardWindow.maxY)
        XCTAssertTrue(geometry.titleBand.minY >= geometry.cardWindow.minY)
        XCTAssertTrue(geometry.titleBand.maxY <= geometry.cardWindow.maxY)
    }

    func testGenericLabelBandIsOutsideCardWindow() {
        let geometry = SlabFramingRegion.geometry(for: nil)

        XCTAssertGreaterThanOrEqual(geometry.labelBand.minY, geometry.cardWindow.maxY)
        XCTAssertEqual(SlabFramingRegion.labelVisionRect(), SlabFramingRegion.labelVisionRect(for: nil))
    }

    func testGenericLabelRegionIsContainedByProvisionalGuide() {
        let provisionalGuide = SlabFramingRegion.slabVisionRect(for: nil)
        let labelRegion = SlabFramingRegion.labelVisionRect(for: nil)

        XCTAssertTrue(provisionalGuide.contains(labelRegion))
    }

    func testUnboundFooterROIUsesTheProductionUnion() {
        let rawFooterRegion = CardFramingRegion.visionRect
        let slabFooterRegion = SlabFramingRegion.footerVisionRect(for: nil)
        let expected = rawFooterRegion.union(slabFooterRegion)
        let scanner = CardScanner()

        XCTAssertEqual(scanner.footerRegionOfInterestForTesting, expected)
    }

    func testOuterSlabGuideHasExpectedPhysicalAspect() {
        let rect = SlabFramingRegion.slabVisionRect(for: .cgc)
        let normalizedAspect = rect.width / rect.height
        let sourceAspect = CGFloat(9.0 / 16.0)

        XCTAssertEqual(normalizedAspect * sourceAspect, 3.25 / 5.25, accuracy: 0.0001)
        XCTAssertEqual(rect.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rect.midY, 0.5, accuracy: 0.0001)
    }
}
