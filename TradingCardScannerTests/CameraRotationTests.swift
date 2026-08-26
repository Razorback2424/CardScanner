import ImageIO
import XCTest
@testable import TradingCardScanner

/// The Vision → metadata transform is the one place in the camera pipeline where a
/// sign error is invisible in code review and expensive on device: the preview looks
/// plausible, the guide band simply sits on the wrong part of the card and OCR reads
/// nothing. It used to be hardcoded to portrait; now that an iPad can hold the sensor
/// any of four ways, each way is pinned here.
final class CameraRotationTests: XCTestCase {
    /// A deliberately asymmetric rect, so a transform that swaps or mirrors an axis
    /// cannot accidentally produce the right answer.
    private let visionRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

    func testUprightSensorOnlyFlipsTheVerticalAxis() {
        let rect = CardFramingRegion.metadataRect(fromVisionRect: visionRect, rotationAngle: 0)
        assertRect(rect, equals: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.4))
    }

    func testPortraitMatchesTheOriginalHardcodedTransform() {
        let rect = CardFramingRegion.metadataRect(fromVisionRect: visionRect, rotationAngle: 90)
        // The transform this replaced: x = 1 - maxY, y = 1 - maxX, axes swapped.
        assertRect(rect, equals: CGRect(x: 0.4, y: 0.6, width: 0.4, height: 0.3))
    }

    func testHalfTurnMirrorsBothAxesWithoutSwappingThem() {
        let rect = CardFramingRegion.metadataRect(fromVisionRect: visionRect, rotationAngle: 180)
        assertRect(rect, equals: CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.4))
    }

    func testUpsideDownPortraitSwapsAxesWithoutMirroring() {
        let rect = CardFramingRegion.metadataRect(fromVisionRect: visionRect, rotationAngle: 270)
        assertRect(rect, equals: CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.3))
    }

    /// Every quarter turn must map the full frame back onto the full frame. A
    /// transform that leaks outside the unit square is pointing Vision off the sensor.
    func testFullFrameIsPreservedAtEveryQuarterTurn() {
        for angle in [CGFloat(0), 90, 180, 270] {
            let rect = CardFramingRegion.metadataRect(
                fromVisionRect: CardFramingRegion.fullFrameRect,
                rotationAngle: angle
            )
            assertRect(rect, equals: CardFramingRegion.fullFrameRect, "angle \(angle)")
        }
    }

    /// The card guide is centred, so it must stay centred however the device is held.
    func testCentredRectStaysCentred() {
        for angle in [CGFloat(0), 90, 180, 270] {
            let rect = CardFramingRegion.metadataRect(
                fromVisionRect: CardFramingRegion.cardVisionRect,
                rotationAngle: angle
            )
            XCTAssertEqual(rect.midX, 0.5, accuracy: 0.0001, "angle \(angle)")
            XCTAssertEqual(rect.midY, 0.5, accuracy: 0.0001, "angle \(angle)")
        }
    }

    /// The transform subtracts normalized coordinates from 1, so results land a
    /// float ulp or two from the literal they are compared against.
    private func assertRect(
        _ rect: CGRect,
        equals expected: CGRect,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(rect.minX, expected.minX, accuracy: 0.0001, "minX \(message)", file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: 0.0001, "minY \(message)", file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 0.0001, "width \(message)", file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 0.0001, "height \(message)", file: file, line: line)
    }

    func testImageOrientationFollowsTheRotationApplied() {
        XCTAssertEqual(CardFramingRegion.imageOrientation(forRotationAngle: 0), .up)
        XCTAssertEqual(CardFramingRegion.imageOrientation(forRotationAngle: 90), .right)
        XCTAssertEqual(CardFramingRegion.imageOrientation(forRotationAngle: 180), .down)
        XCTAssertEqual(CardFramingRegion.imageOrientation(forRotationAngle: 270), .left)
    }

    func testVisionSourceSizeSwapsOnlyForQuarterTurns() {
        let landscape = (width: 1920, height: 1080)
        for angle in [CGFloat(90), 270] {
            let size = CardFramingRegion.visionSourceSize(
                forRotationAngle: angle,
                sensorWidth: landscape.width,
                sensorHeight: landscape.height
            )
            XCTAssertEqual(size, CGSize(width: 1080, height: 1920), "angle \(angle)")
        }
        for angle in [CGFloat(0), 180] {
            let size = CardFramingRegion.visionSourceSize(
                forRotationAngle: angle,
                sensorWidth: landscape.width,
                sensorHeight: landscape.height
            )
            XCTAssertEqual(size, CGSize(width: 1920, height: 1080), "angle \(angle)")
        }
    }

    /// The angle arrives from `RotationCoordinator` as a `CGFloat`, so the transform
    /// must not depend on exact float equality with a literal.
    func testAngleNormalizationSnapsToQuarterTurnsAndWraps() {
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(89.999), 90)
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(360), 0)
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(450), 90)
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(-90), 270)
    }
}
