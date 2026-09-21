import XCTest
import SwiftUI
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

    func testFilenameDistinguishesAUserRotation() {
        let name = CardCenteringExport.filename(for: measurement(), rotationDegrees: 2.5)

        XCTAssertTrue(name.contains("rotated 2.50°"))
        XCTAssertFalse(name.contains("/"))
    }

    func testExportGuidesRotateWithThePhoto() throws {
        let value = measurement(
            width: 100,
            height: 140,
            outer: CardCenteringEdges(left: 20, top: 24, right: 80, bottom: 116),
            inner: CardCenteringEdges(left: 30, top: 34, right: 70, bottom: 106)
        )
        let rendered = CardCenteringExport.render(
            image: photo(width: value.imageWidth, height: value.imageHeight),
            measurement: value,
            rotationDegrees: 7
        )
        let cgImage = try XCTUnwrap(rendered.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func guideCenters(at y: Int) -> [Int] {
            let row = y * width * 4
            var runs: [Int] = []
            var start: Int?
            for x in 0..<width {
                let offset = row + x * 4
                let isRed = bytes[offset] > 150 && bytes[offset + 1] < 130 && bytes[offset + 2] < 130
                if isRed, start == nil { start = x }
                if !isRed, let lower = start {
                    runs.append((lower + x - 1) / 2)
                    start = nil
                }
            }
            if let lower = start { runs.append((lower + width - 1) / 2) }
            return runs.filter { $0 > 20 && $0 < width - 20 }
        }

        let upper = guideCenters(at: 320)
        let lower = guideCenters(at: 940)
        XCTAssertGreaterThanOrEqual(upper.count, 2)
        XCTAssertGreaterThanOrEqual(lower.count, 2)
        XCTAssertGreaterThan(
            abs(upper[0] - lower[0]),
            40,
            "the left guide stayed vertical instead of sharing the photo transform"
        )
    }

    func testExportGuidesFollowDetectedQuadEdgesInsteadOfItsBoundingBox() throws {
        let outer = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 200, y: 200),
            topRight: CardCenteringPoint(x: 800, y: 400),
            bottomRight: CardCenteringPoint(x: 800, y: 1200),
            bottomLeft: CardCenteringPoint(x: 200, y: 1000)
        )
        let inner = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 300, y: 320),
            topRight: CardCenteringPoint(x: 700, y: 450),
            bottomRight: CardCenteringPoint(x: 700, y: 1080),
            bottomLeft: CardCenteringPoint(x: 300, y: 930)
        )
        let value = CardCenteringMeasurement(
            imageWidth: 1_000,
            imageHeight: 1_400,
            outerQuad: outer,
            innerQuad: inner,
            warnings: []
        )
        let rendered = CardCenteringExport.render(
            image: photo(width: value.imageWidth, height: value.imageHeight),
            measurement: value,
            rotationDegrees: 0
        )
        let cgImage = try XCTUnwrap(rendered.cgImage)
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        func isRed(x: Int, y: Int) -> Bool {
            let offset = (y * cgImage.width + x) * 4
            return bytes[offset] > 150 && bytes[offset + 1] < 130 && bytes[offset + 2] < 130
        }

        XCTAssertTrue(isRed(x: 500, y: 300), "the sloped top edge should cross the center")
        XCTAssertFalse(isRed(x: 800, y: 300), "a projected right edge would be wrong here")
    }

    func testQuadBordersUsePerpendicularDistancesAcrossSkew() {
        func transformedQuad(shear: Double, inset: (left: Double, top: Double, right: Double, bottom: Double)) -> CardCenteringQuad {
            func point(_ x: Double, _ y: Double) -> CardCenteringPoint {
                CardCenteringPoint(x: x + shear * y, y: y)
            }
            return CardCenteringQuad(
                topLeft: point(inset.left, inset.top),
                topRight: point(400 - inset.right, inset.top),
                bottomRight: point(400 - inset.right, 600 - inset.bottom),
                bottomLeft: point(inset.left, 600 - inset.bottom)
            )
        }

        let ratios = [0.0, 0.10, 0.25].map { shear in
            let outer = transformedQuad(shear: shear, inset: (0, 0, 0, 0))
            let inner = transformedQuad(shear: shear, inset: (20, 30, 40, 50))
            let value = CardCenteringMeasurement(
                imageWidth: 500,
                imageHeight: 700,
                outerQuad: outer,
                innerQuad: inner,
                warnings: []
            )
            return (value.leftRightCentering, value.topBottomCentering)
        }

        XCTAssertEqual(ratios[0].0, ratios[1].0)
        XCTAssertEqual(ratios[1].0, ratios[2].0)
        XCTAssertEqual(ratios[0].1, ratios[1].1)
        XCTAssertEqual(ratios[1].1, ratios[2].1)
    }

    func testPositionalConsistencyReportsFiveSamplesAndBothRatioRanges() throws {
        let outer = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 0, y: 0),
            topRight: CardCenteringPoint(x: 1_000, y: 0),
            bottomRight: CardCenteringPoint(x: 1_000, y: 1_400),
            bottomLeft: CardCenteringPoint(x: 0, y: 1_400)
        )
        let inner = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 100, y: 120),
            topRight: CardCenteringPoint(x: 900, y: 170),
            bottomRight: CardCenteringPoint(x: 860, y: 1_280),
            bottomLeft: CardCenteringPoint(x: 180, y: 1_240)
        )
        let value = CardCenteringMeasurement(
            imageWidth: 1_000,
            imageHeight: 1_400,
            outerQuad: outer,
            innerQuad: inner,
            warnings: []
        )

        let diagnostic = try XCTUnwrap(value.positionalConsistency)
        XCTAssertEqual(diagnostic.samples.count, 5)
        XCTAssertEqual(
            diagnostic.samples.map(\.normalizedPosition),
            [0, 0.25, 0.5, 0.75, 1]
        )
        XCTAssertGreaterThan(diagnostic.leftRight.firstSpread, 0)
        XCTAssertGreaterThan(diagnostic.topBottom.firstSpread, 0)
        XCTAssertEqual(
            diagnostic.leftRight.firstSpread,
            diagnostic.leftRight.firstMaximum - diagnostic.leftRight.firstMinimum,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            diagnostic.topBottom.firstSpread,
            diagnostic.topBottom.firstMaximum - diagnostic.topBottom.firstMinimum,
            accuracy: 0.000_001
        )
        for sample in diagnostic.samples {
            XCTAssertEqual(sample.leftRight.firstPercentage + sample.leftRight.secondPercentage, 100, accuracy: 0.000_001)
            XCTAssertEqual(sample.topBottom.firstPercentage + sample.topBottom.secondPercentage, 100, accuracy: 0.000_001)
        }
    }

    func testPositionalConsistencyIsUnavailableWithoutAnInnerReference() {
        let value = CardCenteringMeasurement(
            imageWidth: 1_000,
            imageHeight: 1_400,
            outerQuad: .axisAligned(CardCenteringEdges(left: 0, top: 0, right: 1_000, bottom: 1_400)),
            innerQuad: nil,
            warnings: [],
            innerReference: .none
        )

        XCTAssertNil(value.positionalConsistency)
    }

    func testCoordinateMappingRoundTripsNativeAndWorkingPoints() {
        let mapping = CardCenteringCoordinateMapping(
            orientedSourceSize: CardCenteringSize(width: 3024, height: 4032),
            workingSize: CardCenteringSize(width: 900, height: 1200),
            appliedRotationDegrees: 0
        )
        let native = CardCenteringPoint(x: 1_234, y: 2_345)
        let working = mapping.workingPoint(fromNative: native)
        let roundTrip = mapping.nativePoint(fromWorking: working)

        XCTAssertEqual(roundTrip.x, native.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.y, native.y, accuracy: 0.000_001)
        XCTAssertEqual(mapping.workingToNativeScale, 3.36, accuracy: 0.000_001)
    }

    func testRotatedCoordinateMappingRoundTripsTheEnlargedWorkingCanvas() {
        let angle = 7.0 * Double.pi / 180
        let unrotated = CardCenteringSize(width: 900, height: 1_200)
        let rotated = CardCenteringSize(
            width: abs(cos(angle)) * unrotated.width + abs(sin(angle)) * unrotated.height,
            height: abs(sin(angle)) * unrotated.width + abs(cos(angle)) * unrotated.height
        )
        let mapping = CardCenteringCoordinateMapping(
            orientedSourceSize: CardCenteringSize(width: 3024, height: 4032),
            workingSize: rotated,
            appliedRotationDegrees: 7,
            unrotatedWorkingSize: unrotated
        )
        let native = CardCenteringPoint(x: 1_234, y: 2_345)
        let working = mapping.workingPoint(fromNative: native)
        let roundTrip = mapping.nativePoint(fromWorking: working)

        XCTAssertEqual(roundTrip.x, native.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.y, native.y, accuracy: 0.000_001)
        XCTAssertEqual(mapping.workingSize, rotated)
        XCTAssertEqual(mapping.appliedRotationDegrees, 7)
    }

    func testPerspectiveRectificationMapsOuterAndInnerQuadsIntoCardSpace() {
        let outer = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 110, y: 80),
            topRight: CardCenteringPoint(x: 890, y: 125),
            bottomRight: CardCenteringPoint(x: 840, y: 1125),
            bottomLeft: CardCenteringPoint(x: 140, y: 1080)
        )
        let inner = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 190, y: 170),
            topRight: CardCenteringPoint(x: 805, y: 205),
            bottomRight: CardCenteringPoint(x: 765, y: 985),
            bottomLeft: CardCenteringPoint(x: 215, y: 950)
        )

        let rectification = CardCenteringRectification(outerQuad: outer)
        let rectifiedOuter = rectification.rectifiedQuad(from: outer)
        let rectifiedInner = rectification.rectifiedQuad(from: inner)

        XCTAssertEqual(rectifiedOuter.topLeft.x, 0, accuracy: 0.001)
        XCTAssertEqual(rectifiedOuter.topLeft.y, 0, accuracy: 0.001)
        XCTAssertEqual(rectifiedOuter.topRight.x, rectification.targetSize.width, accuracy: 0.001)
        XCTAssertEqual(rectifiedOuter.bottomLeft.y, rectification.targetSize.height, accuracy: 0.001)
        XCTAssertEqual(rectifiedOuter.topRight.y, 0, accuracy: 0.001)
        XCTAssertEqual(rectifiedOuter.bottomRight.x, rectification.targetSize.width, accuracy: 0.001)

        let distances = rectifiedOuter.borderDistances(to: rectifiedInner)
        XCTAssertTrue([distances.left, distances.top, distances.right, distances.bottom].allSatisfy { $0 > 0 })
        XCTAssertLessThan(distances.left + distances.right, rectification.targetSize.width)
        XCTAssertLessThan(distances.top + distances.bottom, rectification.targetSize.height)
        XCTAssertLessThanOrEqual(rectification.residualDegrees, 0.30)
        XCTAssertGreaterThan(rectification.aspectResidual, 0)
        XCTAssertTrue(rectification.reprojectionRMS.isFinite)
    }

    func testRectificationGuardRejectsAConfidentLookingNonCardQuad() {
        let outer = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 120, y: 80),
            topRight: CardCenteringPoint(x: 880, y: 80),
            bottomRight: CardCenteringPoint(x: 880, y: 560),
            bottomLeft: CardCenteringPoint(x: 120, y: 560)
        )

        let rectification = CardCenteringRectification(outerQuad: outer)

        XCTAssertGreaterThan(rectification.aspectResidual, 0.04)
        XCTAssertFalse(rectification.isValid)
    }

    func testGuideGeometryUsesTheSameFittedImageFrameForQuadPoints() {
        let quad = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 100, y: 200),
            topRight: CardCenteringPoint(x: 900, y: 200),
            bottomRight: CardCenteringPoint(x: 900, y: 1_000),
            bottomLeft: CardCenteringPoint(x: 100, y: 1_000)
        )
        let frame = CGRect(x: 40, y: 20, width: 200, height: 400)
        let mapped = CardCenteringGuideGeometry.screenPoints(
            for: quad,
            imageSize: CardCenteringSize(width: 1_000, height: 1_400),
            in: frame
        )

        XCTAssertEqual(mapped[0].x, 60, accuracy: 0.000_1)
        XCTAssertEqual(mapped[0].y, 77.142_857, accuracy: 0.000_1)
        XCTAssertEqual(mapped[2].x, 220, accuracy: 0.000_1)
        XCTAssertEqual(mapped[2].y, 305.714_285, accuracy: 0.000_1)
    }

    @MainActor
    func testOnScreenGuidesRotateWithInjectedGeometry() throws {
        let value = CardCenteringMeasurement(
            imageWidth: 100,
            imageHeight: 140,
            outerQuad: CardCenteringQuad(
                topLeft: CardCenteringPoint(x: 20, y: 20),
                topRight: CardCenteringPoint(x: 80, y: 20),
                bottomRight: CardCenteringPoint(x: 80, y: 120),
                bottomLeft: CardCenteringPoint(x: 20, y: 120)
            ),
            innerQuad: nil,
            warnings: [],
            innerReference: .none
        )

        func redSlope(rotation: Double) throws -> Double {
            let rendered = ImageRenderer(
                content: CardCenteringImage(
                    image: photo(width: value.imageWidth, height: value.imageHeight),
                    measurement: value,
                    rotationDegrees: rotation,
                    onFrameChange: { _ in }
                )
                .frame(width: 300, height: 420)
            ).uiImage
            let cgImage = try XCTUnwrap(rendered?.cgImage)
            var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &bytes,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

            var samples: [(x: Double, y: Double)] = []
            for y in 100..<(cgImage.height - 100) {
                let xs = (0..<cgImage.width).compactMap { x -> Double? in
                    let offset = (y * cgImage.width + x) * 4
                    let isRed = bytes[offset] > 150
                        && bytes[offset + 1] < 130
                        && bytes[offset + 2] < 130
                    return isRed ? Double(x) : nil
                }
                guard !xs.isEmpty else { continue }
                samples.append((xs.reduce(0, +) / Double(xs.count), Double(y)))
            }
            let meanX = samples.map { $0.x }.reduce(0, +) / Double(samples.count)
            let meanY = samples.map { $0.y }.reduce(0, +) / Double(samples.count)
            let denominator = samples.reduce(0) { $0 + pow($1.y - meanY, 2) }
            return samples.reduce(0) { $0 + ($1.y - meanY) * ($1.x - meanX) } / denominator
        }

        let unrotatedSlope = try redSlope(rotation: 0)
        let rotatedSlope = try redSlope(rotation: 7)
        XCTAssertLessThan(abs(unrotatedSlope), 0.03)
        XCTAssertGreaterThan(abs(rotatedSlope), 0.05)
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

        let measurement = result.measurement
        XCTAssertEqual(measurement.outer.left, 35, accuracy: 2)
        XCTAssertEqual(measurement.outer.right, 384, accuracy: 2)
        XCTAssertEqual(measurement.outer.top, 44, accuracy: 2)
        XCTAssertEqual(measurement.outer.bottom, 534, accuracy: 2)
        XCTAssertEqual(measurement.inner.left, 67, accuracy: 2)
        XCTAssertEqual(measurement.inner.right, 364, accuracy: 2)
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

    /// A centred card photographed at an angle: its two side edges converge
    /// toward the far edge instead of remaining parallel.
    private func perspectiveCard() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: 600, height: 800),
            format: format
        ).image { ctx in
            let cg = ctx.cgContext
            UIColor(white: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))

            let outer = CGMutablePath()
            outer.move(to: CGPoint(x: 150, y: 80))
            outer.addLine(to: CGPoint(x: 450, y: 80))
            outer.addLine(to: CGPoint(x: 530, y: 720))
            outer.addLine(to: CGPoint(x: 70, y: 720))
            outer.closeSubpath()
            UIColor(red: 0.98, green: 0.85, blue: 0.20, alpha: 1).setFill()
            cg.addPath(outer)
            cg.fillPath()

            let inner = CGMutablePath()
            inner.move(to: CGPoint(x: 175, y: 110))
            inner.addLine(to: CGPoint(x: 425, y: 110))
            inner.addLine(to: CGPoint(x: 495, y: 690))
            inner.addLine(to: CGPoint(x: 105, y: 690))
            inner.closeSubpath()
            UIColor(red: 0.10, green: 0.25, blue: 0.55, alpha: 1).setFill()
            cg.addPath(inner)
            cg.fillPath()
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
            let analysis = try CardCenteringAnalyzer.analyze(data)
            let m = analysis.measurement
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

#if DEBUG
    /// Diagnostic only: compare the edge-profile evidence that the guarded
    /// Vision refinement sees in the retained synthetic regression corpus.
    /// This is intentionally not a correctness gate; it exists to keep a
    /// future selective guard grounded in evidence from both photos and the
    /// known artwork-decoy cases.
    func testEDumpOuterRefinementDecisionsForSyntheticRegressionCorpus() throws {
        let cases: [(String, Data)] = [
            (
                "fills-frame",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (20, 25, 60, 55)
                )
            ),
            (
                "low-contrast",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (20, 25, 60, 55),
                    background: UIColor(white: 0.88, alpha: 1),
                    borderColor: UIColor(white: 0.98, alpha: 1)
                )
            ),
            (
                "textured",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (20, 25, 60, 55),
                    textured: true
                )
            ),
            (
                "unequal",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (15, 20, 75, 70)
                )
            ),
            (
                "odd-border",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (15, 15, 15, 70)
                )
            ),
            (
                "thin-banner",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (60, 15, 60, 60),
                    decoyInsetFromArtTop: 25
                )
            ),
            (
                "faint-border-loud-art",
                syntheticCard(
                    canvas: CGSize(width: 500, height: 700),
                    cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
                    borders: (40, 40, 40, 40),
                    decoyInsetFromArtTop: 30,
                    borderColor: UIColor(white: 0.06, alpha: 1),
                    artFill: UIColor(white: 0.16, alpha: 1)
                )
            ),
            (
                "landscape",
                syntheticCard(
                    canvas: CGSize(width: 1000, height: 800),
                    cardRect: CGRect(x: 160, y: 160, width: 680, height: 480),
                    borders: (25, 20, 55, 60)
                )
            )
        ]

        for (name, data) in cases {
            var reports: [CardCenteringOuterRefinementDiagnostic] = []
            CardCenteringAnalyzer.outerRefinementDiagnosticSink = { reports.append($0) }
            defer { CardCenteringAnalyzer.outerRefinementDiagnosticSink = nil }
            _ = try CardCenteringAnalyzer.analyze(data)
            func median(_ values: [Double]) -> String {
                guard !values.isEmpty else { return "nil" }
                let sorted = values.sorted()
                let middle = sorted.count / 2
                let value = sorted.count.isMultiple(of: 2)
                    ? (sorted[middle - 1] + sorted[middle]) / 2
                    : sorted[middle]
                return String(format: "%.3f", value)
            }
            for report in reports {
                let offsetMedianText = report.offsetMedian.map { String(format: "%.2f", $0) } ?? "nil"
                let mad = report.offsetMAD.map { String(format: "%.2f", $0) } ?? "nil"
                print(
                    "E-D-SYNTH name=\(name) side=\(report.side) "
                        + "accepted=\(report.accepted) "
                        + "median=\(offsetMedianText) mad=\(mad) "
                        + "width=\(median(report.acceptedTransitionWidths)) "
                        + "contrast=\(median(report.acceptedContrastDeltas)) "
                        + "strength=\(median(report.acceptedStrengths)) "
                        + "count=\(report.acceptedOffsets.count)/\(report.minimumAccepted) "
                        + "guard=\(String(format: "%.2f", report.maximumLocalOffset)) "
                        + "reason=\(report.reason ?? "none")"
                )
            }
        }
    }
#endif

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

    /// An automatic candidate must remain visibly unconfirmed until the user
    /// accepts both frame guides. Once accepted, the ordinary case is quiet.
    func testAutomaticMeasurementRequiresFrameConfirmationBeforeBecomingQuiet() throws {
        var m = try CardCenteringAnalyzer.analyze(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (20, 25, 60, 55)
        )).measurement
        XCTAssertTrue(m.detectionNotes.isEmpty, "unexpected notes: \(m.detectionNotes)")
        XCTAssertTrue(m.requiresManualFrameConfirmation)
        XCTAssertTrue(m.isDeclined)
        XCTAssertTrue(
            m.warnings.contains { $0.contains("Confirm or adjust both") },
            "expected the pending-frame warning: \(m.warnings)"
        )

        m.confirmManualPlacement()

        XCTAssertFalse(m.isDeclined)
        XCTAssertTrue(m.warnings.isEmpty, "unexpected warnings after confirmation: \(m.warnings)")
    }

    func testPerspectiveCardSaysItsEdgesAreNotParallel() throws {
        let m = try CardCenteringAnalyzer.analyze(perspectiveCard()).measurement

        XCTAssertTrue(
            m.detectionNotes.contains { $0.contains("not parallel") },
            "expected a perspective note, got \(m.detectionNotes)"
        )
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

    func testAnalyzerPublishesQuadGeometryAndCoordinateMapping() throws {
        let analysis = try CardCenteringAnalyzer.analyze(syntheticCard(
            canvas: CGSize(width: 500, height: 700),
            cardRect: CGRect(x: 10, y: 10, width: 480, height: 680),
            borders: (20, 25, 60, 55)
        ))

        XCTAssertTrue(analysis.measurement.usesQuadGeometry)
        XCTAssertNotNil(analysis.measurement.innerQuad)
        XCTAssertEqual(
            analysis.measurement.outerQuad.rectifiedAspectRatio,
            480.0 / 680.0,
            accuracy: 0.03
        )
        XCTAssertEqual(analysis.measurement.coordinateMapping, analysis.coordinateMapping)
    }
}
