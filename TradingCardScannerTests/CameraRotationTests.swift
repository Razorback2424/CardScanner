import ImageIO
import UIKit
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
    /// The scanner is portrait-locked on iPhone, so this is the whole of its
    /// rotation behaviour there — and it must stay exactly what the code did when
    /// the angle was a hardcoded 90.
    func testPortraitIsAlwaysNinetyDegrees() {
        XCTAssertEqual(CameraRotationTracker.angle(for: .portrait), 90)
        XCTAssertEqual(CameraRotationTracker.defaultAngle, 90)
        XCTAssertEqual(CameraRotationTracker.angle(for: .unknown), 90, "no orientation yet")
    }

    /// The guarantee that matters: on iPhone every part of the scanner's geometry
    /// resolves to exactly what the code did when the angle was hardcoded. If this
    /// fails, the phone scanner has been changed, whatever else was intended.
    func testPhoneGeometryIsIdenticalToTheOriginalHardcodedPipeline() {
        // A view with no window — and, on a phone host, any view at all.
        XCTAssertEqual(UIView().cameraRotationAngle, 90)

        let angle = CameraRotationTracker.defaultAngle
        XCTAssertEqual(CardFramingRegion.imageOrientation(forRotationAngle: angle), .right)
        XCTAssertEqual(
            CardFramingRegion.visionSourceSize(forRotationAngle: angle, sensorWidth: 1920, sensorHeight: 1080),
            CGSize(width: 1080, height: 1920),
            "the original swapped the landscape buffer's dimensions"
        )
        assertRect(
            CardFramingRegion.metadataRect(fromVisionRect: visionRect, rotationAngle: angle),
            equals: CGRect(
                // The original expression, written out.
                x: 1 - visionRect.maxY,
                y: 1 - visionRect.maxX,
                width: visionRect.height,
                height: visionRect.width
            )
        )
    }

    /// Each interface orientation must map to a distinct quarter turn, and
    /// landscapeRight to the sensor's own native orientation.
    func testEachInterfaceOrientationMapsToItsOwnQuarterTurn() {
        let angles: [UIInterfaceOrientation: CGFloat] = [
            .portrait: 90,
            .portraitUpsideDown: 270,
            .landscapeLeft: 180,
            .landscapeRight: 0
        ]
        for (orientation, expected) in angles {
            XCTAssertEqual(CameraRotationTracker.angle(for: orientation), expected)
        }
        XCTAssertEqual(Set(angles.values).count, 4, "no two orientations share an angle")
    }

    /// The angle is read on the Vision queue every frame while being written from
    /// the main thread on rotation, so the mirror must be readable from anywhere.
    func testReportedAngleIsVisibleToOtherQueues() {
        let tracker = CameraRotationTracker()
        XCTAssertEqual(tracker.currentAngle, 90)

        tracker.report(180)

        let read = expectation(description: "read off the main thread")
        DispatchQueue.global().async {
            XCTAssertEqual(tracker.currentAngle, 180)
            read.fulfill()
        }
        wait(for: [read], timeout: 1)
    }

    func testAngleNormalizationSnapsToQuarterTurnsAndWraps() {
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(89.999), 90)
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(360), 0)
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(450), 90)
        XCTAssertEqual(CardFramingRegion.normalizedRotationAngle(-90), 270)
    }
}
