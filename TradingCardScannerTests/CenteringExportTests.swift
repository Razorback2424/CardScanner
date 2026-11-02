import XCTest
import SwiftUI
import UIKit
@testable import TradingCardScanner

final class CenteringNativePrecisionTests: XCTestCase {
    func testPinchHandoffUsesClampedBaselineAndRetainsTranslationAtEveryBoundary() {
        for overshoot in [CGSize(width: -500, height: 0), CGSize(width: 500, height: 0),
                          CGSize(width: 0, height: -500), CGSize(width: 0, height: 500)] {
            let checkpoint = CGSize(width: 37, height: -19)
            let handoff = CardCenteringPanHandoff(pan: overshoot, translation: checkpoint) {
                CGSize(width: min(100, max(-100, $0.width)), height: min(100, max(-100, $0.height)))
            }
            XCTAssertEqual(handoff.translation, checkpoint)
            let reverse = CGSize(width: overshoot.width == 0 ? 0 : (overshoot.width > 0 ? -1 : 1),
                                 height: overshoot.height == 0 ? 0 : (overshoot.height > 0 ? -1 : 1))
            let continued = CGSize(width: handoff.pan.width + checkpoint.width + reverse.width - handoff.translation.width,
                                   height: handoff.pan.height + checkpoint.height + reverse.height - handoff.translation.height)
            XCTAssertEqual(abs(continued.width) + abs(continued.height), 99,
                           "The first reversed point must move immediately off the displayed boundary")
        }
    }

    @MainActor func testUndoCannotRestoreApprovalAcrossRotationResetOrChangedPhoto() throws {
        for exactValues in [false, true] {
            let model = CardCenteringViewModel()
            model.image = synthetic()
            model.measurement = fixture()
            model.confirmFrames()
            XCTAssertNotNil(model.exportSnapshot())
            if exactValues {
                model.updateInner(\.left, to: 65, within: 1...200)
            } else {
                model.recordUndoPoint()
                model.applyGuideEdit(try XCTUnwrap(model.measurement))
            }
            model.recordUndoPoint()
            model.adjustRotation(by: 0.01)
            model.resetRotation()
            model.undo()
            model.undo()
            model.resetGuides()
            XCTAssertFalse(try XCTUnwrap(model.measurement).canReportRatios)
            XCTAssertNil(model.exportSnapshot())
            model.confirmFrames()
            XCTAssertNotNil(model.exportSnapshot())
            model.recordUndoPoint()
            model.image = synthetic()
            model.undo()
            XCTAssertFalse(try XCTUnwrap(model.measurement).canReportRatios)
            XCTAssertNil(model.exportSnapshot())
            model.confirmFrames()
            XCTAssertNotNil(model.exportSnapshot())
        }
    }

    private final class InputProbe: ObservableObject {
        @Published var value = 119.005754
        @Published var focusReset = 0
        var updates: [Double] = []
    }
    private struct InputProbeView: View {
        @ObservedObject var probe: InputProbe
        var body: some View {
            CardCenteringPrecisionNumberField(label: "Native position", accessibilityName: "Input probe",
                value: probe.value, step: 0.1, focusReset: probe.focusReset) {
                    probe.updates.append($0); probe.value = $0
                }
        }
    }

    @MainActor func testTypedLocalizedDraftPreservesAllDigitsAndCommitsOnlyOnDone() async throws {
        for (identifier, text, expected) in [("fr_FR", "119,11", 119.11), ("fr_FR", "-0,25", -0.25), ("en_US", "123.45", 123.45)] {
            let probe = InputProbe()
            let host = UIHostingController(rootView: InputProbeView(probe: probe).environment(\.locale, Locale(identifier: identifier)))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            host.loadViewIfNeeded(); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(80))
            func field(in view: UIView) -> UITextField? {
                if let value = view as? UITextField { return value }
                return view.subviews.compactMap { field(in: $0) }.first
            }
            let input = try XCTUnwrap(field(in: host.view))
            XCTAssertTrue(input.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(40))
            probe.focusReset += 1
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertTrue(probe.updates.isEmpty, "Focus/Done without editing must preserve the unrounded Double")
            XCTAssertEqual(probe.value, 119.005754, accuracy: 1e-12)
            XCTAssertTrue(input.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(40))
            input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
            input.insertText(text)
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertEqual(input.text, text, "Every typed digit must survive while focused: \(identifier)")
            XCTAssertTrue(probe.updates.isEmpty, "An unfinished draft must not move the guide")
            let committed = expectation(description: "Done commits the localized draft: \(identifier)")
            let commitObservation = probe.$value.dropFirst().sink { _ in committed.fulfill() }
            probe.focusReset += 1 // The production keyboard toolbar's Done action.
            await fulfillment(of: [committed], timeout: 2)
            commitObservation.cancel()
            XCTAssertEqual(try XCTUnwrap(probe.updates.last), expected, accuracy: 1e-10)
            XCTAssertEqual(probe.value, expected, accuracy: 1e-10)
            XCTAssertEqual(input.text, expected.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: identifier))))
        }
    }

    @MainActor func testNativeDetailLineUsesExactNonSquareImageBoundsWithoutLetterboxDrift() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 112), format: format).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 128, height: 112))
        }
        let content = CardCenteringNativeDetailImage(image: photo, origin: .init(x: 100, y: 200),
            pixelWidth: 128, pixelHeight: 112, guideStart: .init(x: -1000, y: 228),
            guideEnd: .init(x: 1000, y: 228), guideColor: Color(red: 1, green: 0, blue: 0))
            .frame(width: 340, height: 220)
        let renderer = ImageRenderer(content: content); renderer.scale = 3
        let cg = try XCTUnwrap(renderer.uiImage?.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var red: [(x: Int, y: Int)] = []
        for y in 0..<cg.height { for x in 0..<cg.width {
            let i = (y * cg.width + x) * 4
            if bytes[i] > 200 && bytes[i + 1] < 60 && bytes[i + 2] < 60 { red.append((x, y)) }
        } }
        let minimumX = try XCTUnwrap(red.map(\.x).min(), "The injected guide must be present in the actual raster")
        let maximumX = try XCTUnwrap(red.map(\.x).max())
        let fittedWidth = 220.0 * 128 / 112, left = (340 - fittedWidth) / 2
        XCTAssertEqual(Double(minimumX), left * 3, accuracy: 1)
        XCTAssertEqual(Double(maximumX) + 1, (left + fittedWidth) * 3, accuracy: 1)
        let meanY = red.map { Double($0.y) + 0.5 }.reduce(0, +) / Double(red.count)
        XCTAssertEqual(meanY, 28.0 / 112 * 220 * 3, accuracy: 1)
    }
    @MainActor func testExplicitMissingDebugInputNeverFallsBackToSyntheticEvidence() {
        let model = CardCenteringViewModel()
        model.loadDebugFixtureIfNeeded(arguments: ["app", "-ui_debug_fixture_path", "/missing-centering-development-fixture.jpeg"])
        XCTAssertNil(model.image)
        XCTAssertNil(model.measurement)
        XCTAssertEqual(model.errorMessage, "The requested development image could not be read.")
    }

    @MainActor func testNativeDetailKeepsOneSmallCropAndInvalidatesItOnNewInput() async throws {
        func solid(_ color: UIColor) -> Data {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 168), format: format).image { c in
                color.setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 168))
            }.pngData()!
        }
        let model = CardCenteringViewModel()
        func waitUntilSettled() async throws {
            let deadline = Date().addingTimeInterval(10)
            while model.isAnalyzing && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(model.isAnalyzing)
        }
        let red = solid(.red)
        model.loadCapturedPhoto(red); try await waitUntilSettled()
        XCTAssertEqual(model.nativeSourceData, red)
        let first = try XCTUnwrap(model.nativeDetailCrop(in: CGRect(x: 20.1, y: 20.1, width: 64, height: 64)))
        let repeated = try XCTUnwrap(model.nativeDetailCrop(in: CGRect(x: 20.2, y: 20.2, width: 64, height: 64)))
        XCTAssertTrue(first.image === repeated.image)
        XCTAssertLessThanOrEqual(first.width * first.height, 65 * 65)
        XCTAssertGreaterThan(first.rgba[0], 240)
        let blue = solid(.blue)
        model.loadCapturedPhoto(blue); try await waitUntilSettled()
        XCTAssertEqual(model.nativeSourceData, blue)
        let second = try XCTUnwrap(model.nativeDetailCrop(in: CGRect(x: 20.1, y: 20.1, width: 64, height: 64)))
        XCTAssertFalse(first.image === second.image)
        XCTAssertGreaterThan(second.rgba[2], 240)
        XCTAssertLessThan(second.rgba[0], 15)
    }

    func testPrecisionDecimalFormatsPreserveCommaAndNegativeInput() throws {
        for (identifier, position, angle) in [("en_US", "50.10", "-0.25"), ("fr_FR", "50,10", "-0,25"), ("de_DE", "50,10", "-0,25")] {
            let parsedPosition = try XCTUnwrap(CardCenteringPrecisionNumberField.parsedValue(position, locale: Locale(identifier: identifier)))
            let parsedAngle = try XCTUnwrap(CardCenteringPrecisionNumberField.parsedValue(angle, locale: Locale(identifier: identifier)))
            var value = fixture()
            XCTAssertTrue(value.setPrecisionInnerSide(.left, positionNativePixels: parsedPosition))
            XCTAssertTrue(value.setPrecisionInnerSide(.top, angleDegrees: parsedAngle))
            XCTAssertEqual(try XCTUnwrap(value.precisionInnerLine(.left)).position, 50.1, accuracy: 1e-8)
            XCTAssertEqual(try XCTUnwrap(value.precisionInnerLine(.top)).angle, -0.25, accuracy: 1e-8)
        }
        for invalid in ["", "-", "NaN", "Infinity", "inf", "not a number"] {
            XCTAssertNil(CardCenteringPrecisionNumberField.parsedValue(invalid, locale: Locale(identifier: "en_US")))
        }
    }

    func testNativeV2bDevelopmentPerformanceUsesUnchangedBudget() throws {
        guard ProcessInfo.processInfo.environment["RUN_NATIVE_REFINEMENT_BENCHMARK"] == "1" else {
            throw XCTSkip("Experimental native refinement is disabled in production; set RUN_NATIVE_REFINEMENT_BENCHMARK=1 for its unchanged-budget development gate.")
        }
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        var durations: [Double] = []
        for name in ["IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351", "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"] {
            let path = try XCTUnwrap(bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC"))
            let data = try Data(contentsOf: path)
            var diagnostics = CardCenteringAnalyzer.Diagnostics()
            diagnostics.nativeLocalRefinementEnabled = true
            diagnostics.nativeRefinementStrategy = .coherentDistinctTracks
            // Match production's disabled research generator. Its candidates
            // do not participate in this native refinement; timing it would
            // conflate the new stage with an unrelated DEBUG experiment.
            diagnostics.frontBottomCandidateGenerationEnabled = false
            var stage: CardCenteringAnalysisDiagnostic?
            diagnostics.analysisDiagnosticSink = { stage = $0 }
            let start = CFAbsoluteTimeGetCurrent()
            _ = try diagnostics.analyze(data)
            let duration = CFAbsoluteTimeGetCurrent() - start
            durations.append(duration)
            print("CENTERING_NATIVE_V2B_TIMING \(name) seconds=\(duration)")
            if let stage {
                print("CENTERING_NATIVE_V2B_STAGE \(name) native=\(stage.nativeLocalRefinementSeconds ?? 0) innerGeneration=\(stage.stageTimings.innerCandidateGeneration) vision=\(stage.stageTimings.visionRequests) scalar=\(stage.stageTimings.scalarFields) researchGenerator=false")
            }
        }
        let sorted = durations.sorted()
        XCTAssertLessThanOrEqual(sorted[sorted.count / 2], 0.8)
        XCTAssertLessThanOrEqual(sorted.last!, 1.5)
    }
    private func fixture() -> CardCenteringMeasurement {
        CardCenteringMeasurement(imageWidth: 600, imageHeight: 840,
            outerQuad: .axisAligned(.init(left: 20, top: 20, right: 580, bottom: 820)),
            innerQuad: .axisAligned(.init(left: 50, top: 50, right: 550, bottom: 790)), warnings: [],
            confidence: .manualConfirmationRequired(preserving: .legacyConfident, reason: "Review"))
    }

    func testSubpixelEditSurvivesUnchangedIntegerProjectionAndKeepsConfirmation() throws {
        var value = fixture(); XCTAssertTrue(value.confirmFrames())
        let old = value.inner
        XCTAssertTrue(value.setPrecisionInnerSide(.left, positionNativePixels: 50.1))
        XCTAssertEqual(value.inner, old)
        XCTAssertEqual(value.innerQuad!.topLeft.x, 50.1, accuracy: 1e-10)
        XCTAssertTrue(value.canReportRatios)
    }

    func testSelectedSideTurnsAboutMidpointWithAdjacentSupportingLinesFixed() throws {
        var value = fixture()
        XCTAssertTrue(value.setPrecisionInnerSide(.left, angleDegrees: 89.7))
        let inner = try XCTUnwrap(value.innerQuad)
        XCTAssertEqual((inner.topLeft.x + inner.bottomLeft.x) / 2, 50, accuracy: 1e-8)
        XCTAssertEqual(inner.topLeft.y, 50, accuracy: 1e-8)
        XCTAssertEqual(inner.bottomLeft.y, 790, accuracy: 1e-8)
        XCTAssertEqual(inner.topRight, .init(x: 550, y: 50))
        XCTAssertEqual(inner.bottomRight, .init(x: 550, y: 790))
        XCTAssertFalse(value.canReportRatios)
    }

    func testInvalidPrecisionChangesRetainExactLastValidShape() {
        for position in [Double.nan, .infinity, -20, 551] {
            var value = fixture(); let before = value
            XCTAssertFalse(value.setPrecisionInnerSide(.left, positionNativePixels: position))
            XCTAssertEqual(value, before)
        }
        var value = fixture(); let before = value
        XCTAssertFalse(value.setPrecisionInnerSide(.left, angleDegrees: 0))
        XCTAssertEqual(value, before)
    }

    func testOuterPrecisionSideRepairsSlopeWithoutMovingInnerOrOppositeLine() throws {
        var value = fixture(); value.confirmFrames()
        let inner = value.innerQuad, oldTop = value.outerQuad.topLeft
        let previousRectification = value.rectification
        XCTAssertTrue(value.setPrecisionSide(.bottom, frame: .outer, angleDegrees: 0.5))
        XCTAssertEqual(value.outerQuad.topLeft, oldTop)
        XCTAssertEqual(value.outerQuad.topRight, .init(x: 580, y: 20))
        XCTAssertEqual(value.innerQuad, inner)
        XCTAssertNotEqual(value.rectification, previousRectification)
        XCTAssertTrue(value.hasValidFrameGeometry)
        XCTAssertTrue(value.canReportRatios)
        XCTAssertEqual((value.outerQuad.bottomLeft.y + value.outerQuad.bottomRight.y) / 2, 820, accuracy: 1e-8)
    }

    func testVerticalPrecisionAngleDoesNotJumpAcrossNinetyDegrees() throws {
        var value = fixture()
        XCTAssertTrue(value.setPrecisionInnerSide(.left, angleDegrees: 90.01))
        XCTAssertEqual(try XCTUnwrap(value.precisionInnerLine(.left)).angle, 90.01, accuracy: 1e-8)
    }

    func testNativeUnitsRespectUnequalAxisScalesAndPhotoTransform() throws {
        var value = fixture()
        value.coordinateMapping = .init(orientedSourceSize: .init(width: 1203, height: 2527),
            workingSize: .init(width: 600, height: 840))
        let position = try XCTUnwrap(value.precisionInnerLine(.left)).position
        XCTAssertEqual(position, 100.25, accuracy: 1e-9)
        XCTAssertTrue(value.setPrecisionInnerSide(.left, positionNativePixels: position + 0.1))
        XCTAssertEqual(value.innerQuad!.topLeft.x, 50 + 0.1 * 600 / 1203, accuracy: 1e-9)
    }

    func testOldCoordinateMappingDecodesWithoutNewMetadata() throws {
        let json = #"{"orientedSourceSize":{"width":1112,"height":1536},"workingSize":{"width":883,"height":1210},"unrotatedWorkingSize":{"width":869,"height":1200},"appliedRotationDegrees":-0.6246188985801678}"#
        let mapping = try JSONDecoder().decode(CardCenteringCoordinateMapping.self, from: Data(json.utf8))
        XCTAssertNil(mapping.rawRasterSize)
        XCTAssertNil(mapping.rawEXIFOrientation)
    }

    func testEXIFPixelCentresMatchIndependentlyRenderedLandmarksAndCropOrigins() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let raw = UIGraphicsImageRenderer(size: CGSize(width: 7, height: 5), format: format).image { c in
            UIColor.black.setFill(); c.fill(CGRect(x: 0, y: 0, width: 7, height: 5))
            UIColor.red.setFill(); c.fill(CGRect(x: 1, y: 2, width: 1, height: 1))
        }.cgImage!
        // Independent raster-cell locations for the red source cell (1,2),
        // tabulated for all eight EXIF operations, rather than inverse tests.
        let cases: [(UIImage.Orientation, Int, Int, Int)] = [(.up, 1, 1, 2), (.upMirrored, 2, 5, 2),
            (.down, 3, 5, 2), (.downMirrored, 4, 1, 2), (.leftMirrored, 5, 2, 1),
            (.right, 6, 2, 1), (.rightMirrored, 7, 2, 5), (.left, 8, 2, 5)]
        for (orientation, exif, expectedX, expectedY) in cases {
            let source = UIImage(cgImage: raw, scale: 3, orientation: orientation)
            let size = source.centeringRasterOrientation.orientedSize
            let crop = try XCTUnwrap(CardCenteringNativeRefiner.crop(source: source,
                orientedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height)))
            XCTAssertEqual(crop.width, exif >= 5 ? 5 : 7)
            let index = (expectedY * crop.width + expectedX) * 4
            XCTAssertGreaterThan(crop.rgba[index], 240, "EXIF \(exif)")
            XCTAssertLessThan(crop.rgba[index + 1], 15, "EXIF \(exif)")
            let mapped = source.centeringRasterOrientation.orientedPoint(fromRaw: .init(x: 1.5, y: 2.5))
            XCTAssertEqual(mapped, .init(x: Double(expectedX) + 0.5, y: Double(expectedY) + 0.5))
            let detail = try XCTUnwrap(CardCenteringNativeRefiner.crop(source: source,
                orientedRect: CGRect(x: 1, y: 1, width: 3, height: 3)))
            XCTAssertEqual(detail.originOrientedNative, .init(x: 1, y: 1))
        }
    }

    private func synthetic(occluded: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 840), format: format).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 840))
            UIColor.black.setFill(); c.fill(CGRect(x: 20, y: 20, width: 560, height: 800))
            let path = UIBezierPath(); path.move(to: CGPoint(x: 50, y: 50)); path.addLine(to: CGPoint(x: 550, y: 54))
            path.addLine(to: CGPoint(x: 547, y: 790)); path.addLine(to: CGPoint(x: 53, y: 788)); path.close()
            UIColor.yellow.setFill(); path.fill()
            if occluded { UIColor.black.setFill(); c.fill(CGRect(x: 35, y: 220, width: 50, height: 470)) }
        }
    }

    func testActualRasterLandmarksMatchRoundedResizeAndRotationsAtUIImageScaleThree() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let raw = UIGraphicsImageRenderer(size: CGSize(width: 317, height: 211), format: format).image { c in
            UIColor.black.setFill(); c.fill(CGRect(x: 0, y: 0, width: 317, height: 211))
            UIColor.red.setFill(); c.fill(CGRect(x: 100, y: 90, width: 5, height: 5))
        }.cgImage!
        for orientation in [UIImage.Orientation.up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left] {
            for rotation in [-7.0, 0, 7] {
                let source = UIImage(cgImage: raw, scale: 3, orientation: orientation)
                let (image, mapping) = try XCTUnwrap(CardCenteringAnalyzer.prepareRasterForCoordinateTest(source, rotationDegrees: rotation, maxDimension: 200))
                let cg = image.cgImage!
                let crop = try XCTUnwrap(CardCenteringNativeRefiner.crop(source: image,
                    orientedRect: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)))
                var sum = 0.0, sx = 0.0, sy = 0.0
                for y in 0..<crop.height {
                    for x in 0..<crop.width {
                        let i = (y * crop.width + x) * 4
                        let weight = max(0, Double(crop.rgba[i]) - Double(crop.rgba[i + 1]))
                        sum += weight; sx += (Double(x) + 0.5) * weight; sy += (Double(y) + 0.5) * weight
                    }
                }
                XCTAssertGreaterThan(sum, 0)
                let oriented = source.centeringRasterOrientation.orientedPoint(fromRaw: .init(x: 102.5, y: 92.5))
                let expected = mapping.workingPoint(fromNative: oriented)
                XCTAssertLessThanOrEqual(hypot(sx / sum - expected.x, sy / sum - expected.y), 0.5,
                    "orientation=\(orientation) rotation=\(rotation)")
                XCTAssertEqual(max(mapping.unrotatedWorkingSize.width, mapping.unrotatedWorkingSize.height), 200)
            }
        }
    }

    func testNativeTransitionsRecoverIndependentInnerSlopesWithoutEqualBorderPrior() throws {
        let value = fixture()
        let result = CardCenteringNativeRefiner.refine(source: synthetic(), outer: value.outerQuad, inner: value.innerQuad!)
        let inner = try XCTUnwrap(result.inner)
        XCTAssertEqual(atan2(inner.topRight.y - inner.topLeft.y, inner.topRight.x - inner.topLeft.x), atan2(4, 500), accuracy: 0.002)
        XCTAssertEqual(inner.topLeft.x, 50, accuracy: 1.2)
        XCTAssertEqual(inner.bottomLeft.x, 53, accuracy: 1.2)
        XCTAssertGreaterThan(result.evidence.filter { $0.disposition == "accepted_local_fit" }.count, 2)
        XCTAssertTrue(result.evidence.filter { $0.disposition == "accepted_local_fit" }.allSatisfy {
            $0.spatialCoverage >= 0.56 && $0.lineCoefficientsOrientedNative?.count == 3 && ($0.fitResidualNativePixels ?? 2) <= 1.1
        })
    }

    func testCoherentNativeFitRetainsUsefulPeaksAcrossContaminatedPositions() throws {
        let base = synthetic()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: base.size, format: format).image { c in
            base.draw(at: .zero)
            UIColor.blue.setFill(); c.fill(CGRect(x: 56, y: 240, width: 4, height: 420))
        }
        let value = fixture()
        for strategy in [CardCenteringNativeRefiner.Strategy.coherentCandidates, .coherentDistinctTracks] {
            let result = CardCenteringNativeRefiner.refine(source: image, outer: value.outerQuad, inner: value.innerQuad!, strategy: strategy)
            let left = try XCTUnwrap(result.evidence.first { $0.frame == "inner" && $0.side == "left" })
            XCTAssertEqual(left.disposition, "accepted_local_fit")
            XCTAssertEqual(try XCTUnwrap(result.inner).topLeft.x, 50, accuracy: 1.2)
            XCTAssertTrue(left.samples!.contains { ($0.candidatePeaks?.count ?? 0) > 1 })
            XCTAssertGreaterThanOrEqual(left.acceptedSampleCount, 15)
        }
    }

    func testCoarseAlternativeCanRecoverBoundaryOutsideSelectedNativeBand() throws {
        var value = fixture()
        value.setManualInnerEdge(\.left, to: 90)
        let legacy = CardCenteringNativeRefiner.refine(source: synthetic(), outer: value.outerQuad, inner: value.innerQuad!)
        XCTAssertNotEqual(legacy.evidence.first { $0.frame == "inner" && $0.side == "left" }?.disposition, "accepted_local_fit")
        for strategy in [CardCenteringNativeRefiner.Strategy.coherentCandidates, .coherentDistinctTracks] {
            let result = CardCenteringNativeRefiner.refine(source: synthetic(), outer: value.outerQuad, inner: value.innerQuad!,
                strategy: strategy, coarseSeeds: [.init(side: .left,
                    geometryOrientedNative: [.init(x: 50.3, y: 120), .init(x: 52.7, y: 720)], source: "existing_coarse_profile_alternative")])
            let left = try XCTUnwrap(result.evidence.first { $0.frame == "inner" && $0.side == "left" })
            XCTAssertEqual(left.disposition, "accepted_local_fit")
            XCTAssertEqual(left.seedSource, "existing_coarse_profile_alternative")
            XCTAssertEqual(try XCTUnwrap(result.inner).topLeft.x, 50, accuracy: 1.2)
        }
    }

    func testTwoCoherentNativeBoundariesStayAmbiguousInsteadOfChoosingStrongest() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 840), format: format).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 840))
            UIColor.black.setFill(); c.fill(CGRect(x: 20, y: 20, width: 560, height: 800))
            UIColor.yellow.setFill(); c.fill(CGRect(x: 50, y: 50, width: 500, height: 740))
            UIColor.blue.setFill(); c.fill(CGRect(x: 56, y: 50, width: 4, height: 740))
        }
        let value = fixture()
        for strategy in [CardCenteringNativeRefiner.Strategy.coherentCandidates, .coherentDistinctTracks] {
            let result = CardCenteringNativeRefiner.refine(source: image, outer: value.outerQuad, inner: value.innerQuad!, strategy: strategy)
            let left = try XCTUnwrap(result.evidence.first { $0.frame == "inner" && $0.side == "left" })
            XCTAssertEqual(left.reason, "competing_coherent_native_lines")
            XCTAssertEqual(left.disposition, "unrefined")
            XCTAssertNil(left.lineCoefficientsOrientedNative)
        }
    }

    func testOccludedSideDoesNotInventIndependentSlopeFromAdjacentSamples() {
        let value = fixture()
        let result = CardCenteringNativeRefiner.refine(source: synthetic(occluded: true), outer: value.outerQuad, inner: value.innerQuad!)
        XCTAssertNotEqual(result.evidence.first { $0.frame == "inner" && $0.side == "left" }?.disposition, "accepted_local_fit")
    }

    func testNativeStripMemoryBoundRejectsLargeArea() {
        XCTAssertNil(CardCenteringNativeRefiner.crop(source: synthetic(), orientedRect: .infinite))
        XCTAssertNil(CardCenteringNativeRefiner.crop(source: synthetic(), orientedRect: .null))
    }

    func testNativeRefinementTransformsWithAllEXIFOrientations() throws {
        let value = fixture(), raw = synthetic().cgImage!
        for orientation in [UIImage.Orientation.up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left] {
            let source = UIImage(cgImage: raw, scale: 2, orientation: orientation)
            let orientationMap = source.centeringRasterOrientation
            // Reorder a transformed rectangle by its orientation's physical
            // top/left corners, rather than assuming raw corner identities.
            func transformed(_ quad: CardCenteringQuad) -> CardCenteringQuad {
                let points = quad.points.map(orientationMap.orientedPoint(fromRaw:))
                let byY = points.sorted { $0.y < $1.y }
                let top = byY.prefix(2).sorted { $0.x < $1.x }, bottom = byY.suffix(2).sorted { $0.x < $1.x }
                return .init(topLeft: top[0], topRight: top[1], bottomRight: bottom[1], bottomLeft: bottom[0])
            }
            let result = CardCenteringNativeRefiner.refine(source: source, outer: transformed(value.outerQuad), inner: transformed(value.innerQuad!))
            XCTAssertNotNil(result.inner, "orientation \(orientation)")
            XCTAssertGreaterThan(result.evidence.filter { $0.disposition == "accepted_local_fit" }.count, 2)
        }
    }

    func testRepresentativeLargeNativeSourceUsesBoundedStrips() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let source = UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024), format: format).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
            UIColor.black.setFill(); c.fill(CGRect(x: 100, y: 100, width: 3832, height: 2824))
            UIColor.yellow.setFill(); c.fill(CGRect(x: 150, y: 150, width: 3732, height: 2724))
        }
        let outer = CardCenteringQuad.axisAligned(.init(left: 100, top: 100, right: 3932, bottom: 2924))
        let inner = CardCenteringQuad.axisAligned(.init(left: 151, top: 151, right: 3881, bottom: 2873))
        let result = CardCenteringNativeRefiner.refine(source: source, outer: outer, inner: inner)
        XCTAssertNotNil(result.inner)
        XCTAssertEqual(result.evidence.count, 8)
        XCTAssertTrue(result.evidence.allSatisfy { $0.rawSampleCount == 25 })
        // Reject a full native Lab-style allocation by construction; crop
        // region limits are checked before allocating RGBA/renderer buffers.
        XCTAssertNil(CardCenteringNativeRefiner.crop(source: source, orientedRect: CGRect(x: 0, y: 0, width: 4032, height: 3024)))
    }

    func testUnsupportedNativeEvidenceKeepsOldGuidesAndRecordsReason() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let source = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 840), format: format).image { c in
            UIColor.gray.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 840))
        }
        let value = fixture()
        let result = CardCenteringNativeRefiner.refine(source: source, outer: value.outerQuad, inner: value.innerQuad!)
        XCTAssertNil(result.inner)
        XCTAssertTrue(result.evidence.filter { $0.frame == "inner" }.allSatisfy {
            $0.disposition == "unrefined" && $0.reason != nil && $0.acceptedSampleCount == 0
        })
    }

    func testCancelledAnalyzerStopsBeforeDecodingOrProducingGuides() async {
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try CardCenteringAnalyzer.analyze(Data())
                return false
            } catch { return error is CancellationError }
        }.value
        XCTAssertTrue(cancelled)
    }

    func testCancelledNativeJobDoesNotConstructPartialGuides() async {
        let image = synthetic(), value = fixture()
        let result = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return CardCenteringNativeRefiner.refine(source: image, outer: value.outerQuad, inner: value.innerQuad!)
        }.value
        XCTAssertNil(result.inner)
        XCTAssertTrue(result.evidence.isEmpty)
    }

    func testRimAndStrongerShadowAreRetainedAsAmbiguousOuterEvidence() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let source = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 840), format: format).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 840))
            UIColor(white: 0.65, alpha: 1).setFill(); c.fill(CGRect(x: 20, y: 20, width: 560, height: 806))
            UIColor.black.setFill(); c.fill(CGRect(x: 20, y: 20, width: 560, height: 800))
            UIColor.yellow.setFill(); c.fill(CGRect(x: 50, y: 50, width: 500, height: 740))
        }
        let value = fixture()
        let result = CardCenteringNativeRefiner.refine(source: source, outer: value.outerQuad, inner: value.innerQuad!)
        let bottom = try XCTUnwrap(result.evidence.first { $0.frame == "outer" && $0.side == "bottom" })
        XCTAssertNotNil(bottom.alternativeSeparationNativePixels)
        XCTAssertEqual(bottom.disposition, "observed_only")
        XCTAssertEqual(bottom.reason, "card_edge_and_shadow_may_overlap")
        XCTAssertNil(bottom.lineCoefficientsOrientedNative, "native gradient must not replace the physical outer semantic choice")
    }

    @MainActor func testCoarseEditsClearPrecisionUndoHistory() throws {
        let model = CardCenteringViewModel(); model.measurement = fixture()
        model.updatePrecisionSide(.left, position: 50.1)
        model.updateOuter(\.left, to: 21, within: 0...599)
        let coarse = model.measurement
        model.resetPrecisionEdits(); model.undoPrecisionEdit()
        XCTAssertEqual(model.measurement, coarse)
    }

    @MainActor func testPhotoRotationAndResetInvalidateApprovalAndStaleExport() throws {
        let model = CardCenteringViewModel(); model.image = synthetic(); model.measurement = fixture()
        model.confirmFrames(); let old = try XCTUnwrap(model.exportSnapshot())
        let inner = model.measurement?.innerQuad, outer = model.measurement?.outerQuad
        model.adjustRotation(by: 0.1)
        XCTAssertFalse(model.measurement!.canReportRatios)
        XCTAssertNil(model.exportSnapshot()); XCTAssertFalse(model.matches(old))
        XCTAssertEqual(model.measurement?.innerQuad, inner); XCTAssertEqual(model.measurement?.outerQuad, outer)
        XCTAssertTrue(model.measurement!.warnings.contains { $0.contains("photo moved") })
        model.confirmFrames(); let rotated = try XCTUnwrap(model.exportSnapshot())
        model.resetRotation()
        XCTAssertFalse(model.matches(rotated)); XCTAssertNil(model.exportSnapshot())
        XCTAssertFalse(model.measurement!.canReportRatios)
    }

    @MainActor func testPrecisionUndoAndResetRecoverExactGeometry() throws {
        let model = CardCenteringViewModel(); model.measurement = fixture()
        XCTAssertFalse(model.canUndoPrecisionEdit)
        XCTAssertFalse(model.canResetPrecisionEdits)
        let before = model.measurement
        model.updatePrecisionSide(.left, position: 50.1)
        XCTAssertTrue(model.canUndoPrecisionEdit)
        XCTAssertTrue(model.canResetPrecisionEdits)
        XCTAssertNotEqual(model.measurement, before)
        model.undoPrecisionEdit(); XCTAssertEqual(model.measurement, before)
        XCTAssertFalse(model.canUndoPrecisionEdit)
        XCTAssertFalse(model.canResetPrecisionEdits)
        model.updatePrecisionSide(.left, angle: 89.8)
        model.resetPrecisionEdits(); XCTAssertEqual(model.measurement, before)
    }

    @MainActor func testNativePrecisionIncludesPhotoOnlyRotationInItsSourceMapping() throws {
        let model = CardCenteringViewModel(); model.measurement = fixture()
        model.adjustRotation(by: 7)
        let precision = try XCTUnwrap(model.precisionMeasurement)
        let mapping = try XCTUnwrap(precision.coordinateMapping)
        XCTAssertEqual(mapping.appliedRotationDegrees, 7)
        let line = try XCTUnwrap(precision.precisionInnerLine(.top))
        XCTAssertEqual(line.angle, -7, accuracy: 1e-8)
        model.updatePrecisionSide(.top, position: line.position + 0.1)
        XCTAssertNil(model.measurement?.coordinateMapping, "temporary effective mapping must not overwrite source provenance")
        XCTAssertTrue(model.measurement!.hasValidFrameGeometry)
    }
}

final class CenteringExportTests: XCTestCase {
    @MainActor
    func testRepeatedSuccessfulExportsRetireSupersededArtifacts() throws {
        let model = CardCenteringViewModel()
        model.image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { _ in }
        model.measurement = measurement()
        let first = try XCTUnwrap(model.makeExportFile())
        let second = try XCTUnwrap(model.makeExportFile())
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        CenteringExportFiles.retainForShare(second)
        model.retireExportFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path), "an active share must survive departure or replacement")
    }

    func testFrameApprovalRequiresExplicitActionAndValidNestedGeometry() {
        var value = measurement()
        value.confidence = .manualConfirmationRequired(preserving: value.confidence, reason: "Review both frames")
        value.setManualOuterEdge(\.left, to: value.outer.left)
        value.refreshWarnings()
        XCTAssertTrue(value.isDeclined)
        value.setManualInnerEdge(\.left, to: value.inner.left)
        value.refreshWarnings()
        XCTAssertTrue(value.isDeclined)
        XCTAssertTrue(value.confirmFrames())
        XCTAssertFalse(value.isDeclined)
        value.setManualInnerEdge(\.left, to: value.inner.left + 1)
        XCTAssertFalse(value.isDeclined, "valid edits remain live after approval")
        value.setManualInnerEdge(\.left, to: value.outer.left - 1)
        XCTAssertTrue(value.isDeclined)
        XCTAssertEqual(value.leftRightCentering, "—")
        XCTAssertFalse(value.confirmFrames())
    }

    func testFrameApprovalRejectsCrossedQuadAndRecoversMissingInnerReference() {
        var value = measurement()
        value.innerReference = .none
        value.confidence = .declined(reason: "No inner reference")
        XCTAssertFalse(value.confirmFrames())
        value.setManualInnerEdge(\.left, to: value.inner.left)
        XCTAssertTrue(value.isDeclined)
        XCTAssertTrue(value.confirmFrames())
        let inner = value.innerQuad!
        value.innerQuad = CardCenteringQuad(topLeft: inner.topLeft, topRight: inner.bottomRight,
                                          bottomRight: inner.topRight, bottomLeft: inner.bottomLeft)
        // A quad's bounding box alone cannot establish a usable frame.
        value = CardCenteringMeasurement(imageWidth: value.imageWidth, imageHeight: value.imageHeight,
                                        outerQuad: value.outerQuad, innerQuad: value.innerQuad, warnings: [])
        XCTAssertFalse(value.hasValidFrameGeometry)
        XCTAssertFalse(value.confirmFrames())
    }

    func testPerspectiveEditsPreserveUneditedLinesAndTheReferenceRole() throws {
        let outer = CardCenteringQuad(
            topLeft: .init(x: 110, y: 80), topRight: .init(x: 890, y: 125),
            bottomRight: .init(x: 840, y: 1125), bottomLeft: .init(x: 140, y: 1080)
        )
        let inner = CardCenteringQuad(
            topLeft: .init(x: 190, y: 170), topRight: .init(x: 805, y: 205),
            bottomRight: .init(x: 765, y: 985), bottomLeft: .init(x: 215, y: 950)
        )
        var value = CardCenteringMeasurement(imageWidth: 1000, imageHeight: 1400,
            outerQuad: outer, innerQuad: inner, warnings: [], innerReference: .printedBorder,
            confidence: .manualConfirmationRequired(preserving: .legacyConfident, reason: "Review"))
        value.setManualOuterEdge(\.left, to: value.outer.left + 5)
        XCTAssertEqual(value.outerQuad.topRight, outer.topRight)
        XCTAssertEqual(value.outerQuad.bottomRight, outer.bottomRight)
        XCTAssertEqual(value.innerQuad, inner)
        XCTAssertTrue(value.usesQuadGeometry)
        XCTAssertTrue(try XCTUnwrap(value.rectification).isNumericallyValid)
        XCTAssertFalse(value.canReportRatios)
        XCTAssertTrue(value.confirmFrames())
        value.setManualInnerEdge(\.top, to: value.inner.top + 5)
        XCTAssertEqual(value.innerReference, .printedBorder)
        XCTAssertEqual(value.innerQuad?.bottomLeft, inner.bottomLeft)
        XCTAssertEqual(value.innerQuad?.bottomRight, inner.bottomRight)
        XCTAssertTrue(value.canReportRatios)
        let distances = try XCTUnwrap(value.rectification).rectifiedQuad(from: value.outerQuad)
            .borderDistances(to: try XCTUnwrap(value.rectification).rectifiedQuad(from: try XCTUnwrap(value.innerQuad)))
        let ratio = try XCTUnwrap(CardCenteringRatioPair(firstDistance: distances.top, secondDistance: distances.bottom))
        XCTAssertEqual(value.topBottomCentering, String(format: "%.1f / %.1f", ratio.firstPercentage, ratio.secondPercentage))
    }

    func testSquaringTheInnerFrameMatchesTheCardEdgeWithoutChangingBorders() throws {
        // A leaning card whose fitted inner frame disagrees with the card edge
        // by a couple of degrees, as a back-template fit can.
        let outer = CardCenteringQuad(
            topLeft: .init(x: 110, y: 80), topRight: .init(x: 890, y: 125),
            bottomRight: .init(x: 840, y: 1125), bottomLeft: .init(x: 140, y: 1080)
        )
        let inner = CardCenteringQuad(
            topLeft: .init(x: 180, y: 160), topRight: .init(x: 815, y: 215),
            bottomRight: .init(x: 770, y: 990), bottomLeft: .init(x: 205, y: 940)
        )
        var value = CardCenteringMeasurement(imageWidth: 1000, imageHeight: 1400,
            outerQuad: outer, innerQuad: inner, warnings: [], innerReference: .printedBorder,
            confidence: .legacyConfident)
        XCTAssertTrue(value.hasValidFrameGeometry)
        let borders = [value.leftBorderDistance, value.rightBorderDistance,
                       value.topBorderDistance, value.bottomBorderDistance]
        let ratios = [value.leftRightCentering, value.topBottomCentering]

        value.squareInnerFrameToCardEdge()

        let squaredBorders = [value.leftBorderDistance, value.rightBorderDistance,
                              value.topBorderDistance, value.bottomBorderDistance]
        for (squared, original) in zip(squaredBorders, borders) {
            XCTAssertEqual(squared, original, accuracy: 1e-6)
        }
        XCTAssertEqual([value.leftRightCentering, value.topBottomCentering], ratios)
        XCTAssertTrue(value.hasValidFrameGeometry)
        XCTAssertEqual(value.inner, try XCTUnwrap(value.innerQuad).projectedEdges)
        // The rectified card is axis-aligned, so a parallel inner edge has
        // matching coordinates at both of its ends.
        let rectification = try XCTUnwrap(value.rectification)
        let squared = rectification.rectifiedQuad(from: try XCTUnwrap(value.innerQuad))
        XCTAssertEqual(squared.topLeft.y, squared.topRight.y, accuracy: 1e-6)
        XCTAssertEqual(squared.bottomLeft.y, squared.bottomRight.y, accuracy: 1e-6)
        XCTAssertEqual(squared.topLeft.x, squared.bottomLeft.x, accuracy: 1e-6)
        XCTAssertEqual(squared.topRight.x, squared.bottomRight.x, accuracy: 1e-6)
    }

    func testManualInnerFrameWithoutAReferenceInheritsTheCardEdgeAngles() throws {
        // A card turned about two degrees, with no detected inner frame.
        let outer = CardCenteringQuad(
            topLeft: .init(x: 120, y: 100), topRight: .init(x: 820, y: 124),
            bottomRight: .init(x: 786, y: 1104), bottomLeft: .init(x: 86, y: 1080)
        )
        var value = CardCenteringMeasurement(imageWidth: 1000, imageHeight: 1400,
            outerQuad: outer, innerQuad: nil, warnings: [], innerReference: .none)
        value.setManualInnerEdge(\.left, to: value.inner.left + 40)

        let inner = try XCTUnwrap(value.geometryInnerQuad)
        func direction(_ start: CardCenteringPoint, _ end: CardCenteringPoint) -> Double {
            atan2(end.y - start.y, end.x - start.x)
        }
        XCTAssertEqual(direction(inner.topLeft, inner.topRight), direction(outer.topLeft, outer.topRight), accuracy: 1e-9)
        XCTAssertEqual(direction(inner.topRight, inner.bottomRight), direction(outer.topRight, outer.bottomRight), accuracy: 1e-9)
        XCTAssertEqual(direction(inner.bottomLeft, inner.bottomRight), direction(outer.bottomLeft, outer.bottomRight), accuracy: 1e-9)
        XCTAssertEqual(direction(inner.topLeft, inner.bottomLeft), direction(outer.topLeft, outer.bottomLeft), accuracy: 1e-9)
        XCTAssertEqual(value.inner.left, 126)
    }

    /// A leaning card with its inner frame squared to the card edge.
    private func leaningSquaredMeasurement() -> CardCenteringMeasurement {
        let outer = CardCenteringQuad(
            topLeft: .init(x: 110, y: 80), topRight: .init(x: 890, y: 125),
            bottomRight: .init(x: 840, y: 1125), bottomLeft: .init(x: 140, y: 1080)
        )
        let inner = CardCenteringQuad(
            topLeft: .init(x: 180, y: 160), topRight: .init(x: 815, y: 215),
            bottomRight: .init(x: 770, y: 990), bottomLeft: .init(x: 205, y: 940)
        )
        var value = CardCenteringMeasurement(imageWidth: 1000, imageHeight: 1400,
            outerQuad: outer, innerQuad: inner, warnings: [], innerReference: .printedBorder,
            confidence: .legacyConfident)
        value.squareInnerFrameToCardEdge()
        return value
    }

    func testDraggingAnInnerGuideKeepsItSquareToTheCardEdge() throws {
        var value = leaningSquaredMeasurement()
        let before = [value.topBorderDistance, value.rightBorderDistance, value.bottomBorderDistance]
        let line = try XCTUnwrap(value.segment(for: .init(frame: .inner, side: .left)))
        let target = CardCenteringPoint(x: (line.start.x + line.end.x) / 2 + 9, y: (line.start.y + line.end.y) / 2)

        value.moveGuide(.init(frame: .inner, side: .left), through: target)

        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), 0, accuracy: 1e-6)
        let rectification = try XCTUnwrap(value.rectification)
        let rectified = rectification.rectifiedQuad(from: try XCTUnwrap(value.innerQuad))
        XCTAssertEqual(rectified.topLeft.x, rectification.rectifiedPoint(from: target).x, accuracy: 1e-6)
        XCTAssertEqual(rectified.bottomLeft.x, rectification.rectifiedPoint(from: target).x, accuracy: 1e-6)
        let after = [value.topBorderDistance, value.rightBorderDistance, value.bottomBorderDistance]
        for (moved, original) in zip(after, before) {
            XCTAssertEqual(moved, original, accuracy: 1e-6, "only the dragged side changes")
        }
        XCTAssertTrue(value.hasValidFrameGeometry)
        XCTAssertTrue(value.canReportRatios, "an edit after confirmation keeps the reading live")
    }

    func testArrowNudgesMoveAGuideOnePixel() {
        var value = CardCenteringMeasurement(imageWidth: 400, imageHeight: 560,
            outerQuad: .axisAligned(.init(left: 40, top: 40, right: 360, bottom: 520)),
            innerQuad: .axisAligned(.init(left: 60, top: 62, right: 340, bottom: 500)),
            warnings: [], innerReference: .printedBorder, confidence: .legacyConfident)
        let right = value.rightBorderDistance, top = value.topBorderDistance

        value.nudgeGuide(.init(frame: .inner, side: .left), by: 1)
        value.nudgeGuide(.init(frame: .outer, side: .top), by: -1)

        XCTAssertEqual(value.leftBorderDistance, 21, accuracy: 1e-6)
        XCTAssertEqual(value.rightBorderDistance, right, accuracy: 1e-6)
        XCTAssertEqual(value.topBorderDistance, top + 1, accuracy: 1e-6)
        XCTAssertEqual(value.inner.left, 61)
        XCTAssertEqual(value.outer.top, 39)
    }

    func testTiltingTheInnerFrameTurnsItAsOnePieceAboutTheHeldEnd() throws {
        var value = leaningSquaredMeasurement()
        let rectification = try XCTUnwrap(value.rectification)
        let heldEnd = rectification.rectifiedPoint(from: try XCTUnwrap(value.innerQuad).topRight)

        value.turnGuide(.init(frame: .inner, side: .right), about: .start, byDegrees: 0.25)

        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), 0.25, accuracy: 1e-6)
        XCTAssertTrue(value.hasReportableInnerTilt)
        let turned = rectification.rectifiedQuad(from: try XCTUnwrap(value.innerQuad))
        XCTAssertEqual(turned.topRight.x, heldEnd.x, accuracy: 1e-6)
        XCTAssertEqual(turned.topRight.y, heldEnd.y, accuracy: 1e-6)
        // A clockwise tilt widens the left border at the top and narrows it at
        // the bottom, so the reading changes along the card.
        let samples = try XCTUnwrap(value.positionalConsistency?.samples)
        let top = try XCTUnwrap(samples.first?.leftRight.firstPercentage)
        let bottom = try XCTUnwrap(samples.last?.leftRight.firstPercentage)
        XCTAssertGreaterThan(top, bottom)

        value.squareInnerFrameToCardEdge()
        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), 0, accuracy: 1e-6)
        XCTAssertFalse(value.hasReportableInnerTilt)
    }

    func testInnerTiltIsHeldWithinTheMaximum() throws {
        var value = leaningSquaredMeasurement()
        value.turnGuide(.init(frame: .inner, side: .top), about: .start, byDegrees: 30)
        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), CardCenteringMeasurement.maximumInnerTiltDegrees, accuracy: 1e-6)
        value.turnGuide(.init(frame: .inner, side: .top), about: .start, byDegrees: 1)
        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), CardCenteringMeasurement.maximumInnerTiltDegrees, accuracy: 1e-6)
    }

    func testSwingingAnInnerEndPointsTheSideAtTheFinger() throws {
        var value = CardCenteringMeasurement(imageWidth: 400, imageHeight: 560,
            outerQuad: .axisAligned(.init(left: 40, top: 40, right: 360, bottom: 520)),
            innerQuad: .axisAligned(.init(left: 60, top: 60, right: 340, bottom: 500)),
            warnings: [], innerReference: .printedBorder, confidence: .legacyConfident)
        // Swing the bottom of the right side 2 px left over its 440 px length.
        value.pivotGuide(.init(frame: .inner, side: .right), movingEnd: .end, toward: .init(x: 338, y: 500))

        let expected = atan2(2.0, 440.0) * 180 / .pi
        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), expected, accuracy: 1e-6)
        let quad = try XCTUnwrap(value.innerQuad)
        XCTAssertEqual(quad.topRight.x, 340, accuracy: 1e-6)
        XCTAssertEqual(quad.topRight.y, 60, accuracy: 1e-6)
    }

    func testTurningACardEdgeSideKeepsItsFarEndAndIsLimited() throws {
        var value = leaningSquaredMeasurement()
        let original = value.geometryOuterQuad

        value.turnGuide(.init(frame: .outer, side: .left), about: .start, byDegrees: 1)

        let turned = value.geometryOuterQuad
        XCTAssertEqual(turned.topLeft.x, original.topLeft.x, accuracy: 1e-6)
        XCTAssertEqual(turned.topLeft.y, original.topLeft.y, accuracy: 1e-6)
        XCTAssertNotEqual(turned.bottomLeft.x, original.bottomLeft.x, accuracy: 1)
        XCTAssertEqual(turned.topRight, original.topRight)
        XCTAssertEqual(turned.bottomRight, original.bottomRight)
        func angle(_ quad: CardCenteringQuad) -> Double {
            atan2(quad.bottomLeft.y - quad.topLeft.y, quad.bottomLeft.x - quad.topLeft.x) * 180 / .pi
        }
        XCTAssertEqual(angle(turned) - angle(original), 1, accuracy: 1e-6)

        value.turnGuide(.init(frame: .outer, side: .left), about: .start, byDegrees: 45)
        XCTAssertEqual(angle(value.geometryOuterQuad) - angle(turned), CardCenteringMeasurement.maximumOuterTurnDegrees, accuracy: 1e-6)
        XCTAssertEqual(value.rectification, CardCenteringRectification(outerQuad: value.geometryOuterQuad))
    }

    func testAddingAnInnerFrameStartsSquareInsideTheCardAndAwaitsConfirmation() throws {
        let outer = CardCenteringQuad(
            topLeft: .init(x: 120, y: 100), topRight: .init(x: 820, y: 124),
            bottomRight: .init(x: 786, y: 1104), bottomLeft: .init(x: 86, y: 1080)
        )
        var value = CardCenteringMeasurement(imageWidth: 1000, imageHeight: 1400,
            outerQuad: outer, innerQuad: nil, warnings: [], innerReference: .none)
        XCTAssertNil(value.geometryInnerQuad)

        value.placeDefaultInnerFrame()

        XCTAssertNotNil(value.geometryInnerQuad)
        XCTAssertTrue(value.hasValidFrameGeometry)
        XCTAssertEqual(try XCTUnwrap(value.innerTiltDegrees), 0, accuracy: 1e-6)
        XCTAssertEqual(value.leftBorderDistance, value.rightBorderDistance, accuracy: 1e-6)
        XCTAssertEqual(value.confidence.state, .manualConfirmationRequired)
        XCTAssertFalse(value.canReportRatios, "a placed frame is not a reading until confirmed")
        XCTAssertTrue(value.confirmFrames())
        XCTAssertTrue(value.canReportRatios)
    }

    private func lumaField(
        size: CGSize,
        draw: (CGContext) -> Void
    ) throws -> CardCenteringLumaField {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        return try XCTUnwrap(CardCenteringLumaField(
            image: try XCTUnwrap(image.cgImage),
            measurementSize: CardCenteringSize(width: size.width, height: size.height)
        ))
    }

    func testSnappingFindsTheNearbyEdgeAtSubpixelPrecision() throws {
        let field = try lumaField(size: CGSize(width: 400, height: 560)) { context in
            context.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 560))
            context.setFillColor(UIColor(white: 0.2, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 560))
        }
        // A guide 10 px left of the edge; its normal points left.
        let snap = try XCTUnwrap(CardCenteringEdgeSnapper.snap(
            start: .init(x: 110, y: 40), end: .init(x: 110, y: 520), pivotsOnStart: false,
            radius: 20, field: field, photoRotationDegrees: 0,
            imageSize: .init(width: 400, height: 560)
        ))
        XCTAssertEqual(snap.offset, -10, accuracy: 0.5)
        XCTAssertGreaterThan(snap.contrast, 50)

        let pivot = try XCTUnwrap(CardCenteringEdgeSnapper.snap(
            start: .init(x: 120, y: 40), end: .init(x: 112, y: 520), pivotsOnStart: true,
            radius: 20, field: field, photoRotationDegrees: 0,
            imageSize: .init(width: 400, height: 560)
        ))
        XCTAssertEqual(pivot.offset, -8, accuracy: 0.75, "the swinging end lands on the edge")
    }

    func testSnappingFindsAnEdgeSlightlyOffTheGuideAngle() throws {
        // Over this long side, 0.3° moves the edge about 5 px from end to end.
        // The step is modest, so smeared across that drift it would be too
        // faint to snap to at the guide's own angle.
        let field = try lumaField(size: CGSize(width: 600, height: 1100)) { context in
            context.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 1100))
            context.setFillColor(UIColor(white: 0.42, alpha: 1).cgColor)
            context.move(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: 197.4, y: 0))
            context.addLine(to: CGPoint(x: 202.6, y: 1100))
            context.addLine(to: CGPoint(x: 0, y: 1100))
            context.fillPath()
        }
        let snap = try XCTUnwrap(CardCenteringEdgeSnapper.snap(
            start: .init(x: 192, y: 20), end: .init(x: 192, y: 1080), pivotsOnStart: false,
            radius: 20, field: field, photoRotationDegrees: 0,
            imageSize: .init(width: 600, height: 1100)
        ))
        // The normal points left, so the edge at the middle is 8 px away.
        XCTAssertEqual(snap.offset, -8, accuracy: 0.75, "the guide rests where it crosses the edge at its middle")
    }

    func testSnappingStaysOnTheEdgeItHolds() throws {
        // Two edges either side of the guide; the stronger one is further.
        let field = try lumaField(size: CGSize(width: 400, height: 560)) { context in
            context.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 560))
            context.setFillColor(UIColor(white: 0.62, alpha: 1).cgColor)
            context.fill(CGRect(x: 192, y: 0, width: 208, height: 560))
            context.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            context.fill(CGRect(x: 212, y: 0, width: 188, height: 560))
        }
        func snap(preferred: Double?) throws -> Double {
            try XCTUnwrap(CardCenteringEdgeSnapper.snap(
                start: .init(x: 200, y: 40), end: .init(x: 200, y: 520), pivotsOnStart: false,
                radius: 20, field: field, photoRotationDegrees: 0,
                imageSize: .init(width: 400, height: 560), preferredOffset: preferred
            )).offset
        }
        // The normal points left: the faint edge is at +8, the strong at -12.
        XCTAssertEqual(try snap(preferred: nil), -12, accuracy: 0.5)
        XCTAssertEqual(try snap(preferred: 8), 8, accuracy: 0.5, "a held edge is not dropped for a stronger one")
    }

    func testLoupeAlwaysShowsSinglePixels() {
        XCTAssertGreaterThanOrEqual(CardCenteringCanvas.loupeScale(for: 0.2), 5)
        XCTAssertEqual(CardCenteringCanvas.loupeScale(for: 6), 12)
    }

    func testSnappingFollowsTheStraightenedPhoto() throws {
        // A vertical edge through the centre appears horizontal once the photo
        // is turned a quarter turn under the guides.
        let field = try lumaField(size: CGSize(width: 400, height: 400)) { context in
            context.setFillColor(UIColor(white: 0.9, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            context.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
        }
        let snap = try XCTUnwrap(CardCenteringEdgeSnapper.snap(
            start: .init(x: 60, y: 212), end: .init(x: 340, y: 212), pivotsOnStart: false,
            radius: 20, field: field, photoRotationDegrees: 90,
            imageSize: .init(width: 400, height: 400)
        ))
        XCTAssertEqual(snap.offset, -12, accuracy: 0.5)
    }

    func testSnappingIgnoresTextureAndFaintEdges() throws {
        var state: UInt32 = 12345
        let noise = try lumaField(size: CGSize(width: 300, height: 300)) { context in
            for y in stride(from: 0, to: 300, by: 3) {
                for x in stride(from: 0, to: 300, by: 3) {
                    state = state &* 1_103_515_245 &+ 12345
                    context.setFillColor(UIColor(white: CGFloat(state >> 24) / 255, alpha: 1).cgColor)
                    context.fill(CGRect(x: x, y: y, width: 3, height: 3))
                }
            }
        }
        XCTAssertNil(CardCenteringEdgeSnapper.snap(
            start: .init(x: 150, y: 20), end: .init(x: 150, y: 280), pivotsOnStart: false,
            radius: 15, field: noise, photoRotationDegrees: 0, imageSize: .init(width: 300, height: 300)
        ))

        let faint = try lumaField(size: CGSize(width: 300, height: 300)) { context in
            context.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            context.setFillColor(UIColor(white: 0.52, alpha: 1).cgColor)
            context.fill(CGRect(x: 150, y: 0, width: 150, height: 300))
        }
        XCTAssertNil(CardCenteringEdgeSnapper.snap(
            start: .init(x: 145, y: 20), end: .init(x: 145, y: 280), pivotsOnStart: false,
            radius: 15, field: faint, photoRotationDegrees: 0, imageSize: .init(width: 300, height: 300)
        ))
    }

    @MainActor
    func testHeldArrowPressesUndoInOneStep() throws {
        let model = CardCenteringViewModel()
        let original = CardCenteringMeasurement(imageWidth: 400, imageHeight: 560,
            outerQuad: .axisAligned(.init(left: 40, top: 40, right: 360, bottom: 520)),
            innerQuad: .axisAligned(.init(left: 60, top: 60, right: 340, bottom: 500)),
            warnings: [], innerReference: .printedBorder, confidence: .legacyConfident)
        model.measurement = original
        let left = CardCenteringGuideSelection(guide: .init(frame: .inner, side: .left))

        for _ in 0..<5 { model.nudge(left, by: 1) }
        XCTAssertEqual(model.measurement?.inner.left, 65)
        model.nudge(CardCenteringGuideSelection(guide: .init(frame: .inner, side: .top)), by: 1)

        model.undo()
        XCTAssertEqual(model.measurement?.inner.left, 65)
        XCTAssertEqual(model.measurement?.inner.top, 60)
        model.undo()
        XCTAssertEqual(model.measurement?.inner, original.inner)
        XCTAssertFalse(model.canUndo)
    }

    @MainActor
    func testUndoStepsThroughExactValuesAndCanvasEditsInOrder() throws {
        let model = CardCenteringViewModel()
        let original = CardCenteringMeasurement(imageWidth: 400, imageHeight: 560,
            outerQuad: .axisAligned(.init(left: 40, top: 40, right: 360, bottom: 520)),
            innerQuad: .axisAligned(.init(left: 60, top: 60, right: 340, bottom: 500)),
            warnings: [], innerReference: .printedBorder, confidence: .legacyConfident)
        model.measurement = original

        model.nudge(CardCenteringGuideSelection(guide: .init(frame: .inner, side: .left)), by: 2)
        model.updateInner(\.top, to: 70, within: 41...499)
        XCTAssertEqual(model.measurement?.inner.left, 62)
        XCTAssertEqual(model.measurement?.inner.top, 70)

        model.undo()
        XCTAssertEqual(model.measurement?.inner.top, 60, "an Exact Values edit is its own undo step")
        XCTAssertEqual(model.measurement?.inner.left, 62)
        model.undo()
        XCTAssertEqual(model.measurement?.inner, original.inner)
    }

    @MainActor
    func testCanvasEditEndsThePrecisionUndoSession() throws {
        let model = CardCenteringViewModel()
        model.measurement = CardCenteringMeasurement(imageWidth: 400, imageHeight: 560,
            outerQuad: .axisAligned(.init(left: 40, top: 40, right: 360, bottom: 520)),
            innerQuad: .axisAligned(.init(left: 60, top: 60, right: 340, bottom: 500)),
            warnings: [], innerReference: .printedBorder, confidence: .legacyConfident)

        model.updatePrecisionSide(.left, frame: .inner, position: 64)
        XCTAssertTrue(model.canUndoPrecisionEdit)
        model.nudge(CardCenteringGuideSelection(guide: .init(frame: .inner, side: .top)), by: 1)
        XCTAssertFalse(model.canUndoPrecisionEdit, "precision Undo may not restore guides from before a later drag")
        XCTAssertFalse(model.canResetPrecisionEdits)
    }

    @MainActor
    func testStepTiltingBackThroughZeroLandsSquare() throws {
        let model = CardCenteringViewModel()
        model.measurement = leaningSquaredMeasurement()
        let end = CardCenteringGuideSelection(guide: .init(frame: .inner, side: .right), end: .end)

        model.nudge(end, by: 1)
        XCTAssertEqual(try XCTUnwrap(model.measurement?.innerTiltDegrees), 0.05, accuracy: 1e-6)
        model.nudge(end, by: -1)
        XCTAssertEqual(try XCTUnwrap(model.measurement?.innerTiltDegrees), 0, accuracy: 1e-9)
    }

    func testMalformedGeometryNeverCrashesOrBecomesReportable() {
        let goodOuter = CardCenteringQuad.axisAligned(.init(left: 20, top: 20, right: 220, bottom: 316))
        let goodInner = CardCenteringQuad.axisAligned(.init(left: 30, top: 30, right: 210, bottom: 306))
        for coordinate in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude, -1] {
            var outer = goodOuter
            outer.topLeft.x = coordinate
            var value = CardCenteringMeasurement(imageWidth: 240, imageHeight: 336,
                outerQuad: outer, innerQuad: goodInner, warnings: [], confidence: .legacyConfident)
            XCTAssertFalse(value.hasValidFrameGeometry)
            XCTAssertFalse(value.confirmFrames())
            XCTAssertFalse(value.canReportRatios)
            XCTAssertEqual(value.leftRightCentering, "—")
        }
        let singular = CardCenteringRectification(targetSize: .init(width: 200, height: 296),
            coefficients: [1, 0, 0, 0, 1, 0, -1.0 / 20, 0], residualDegrees: 0)
        var value = CardCenteringMeasurement(imageWidth: 240, imageHeight: 336,
            outerQuad: goodOuter, innerQuad: goodInner, warnings: [], confidence: .legacyConfident, rectification: singular)
        XCTAssertFalse(value.confirmFrames())
        XCTAssertFalse(value.canReportRatios)
        let internalPole = CardCenteringRectification(targetSize: .init(width: 200, height: 296),
            coefficients: [1, 0, 0, 0, 1, 0, -1.0 / 100, 0], residualDegrees: 0)
        value.rectification = internalPole
        XCTAssertFalse(value.canReportRatios, "a projective pole inside the card must be rejected")
        let collapsed = CardCenteringRectification(targetSize: .init(width: 200, height: 296),
            coefficients: [1, 1, 0, 1, 1, 0, 0, 0], residualDegrees: 0)
        value.rectification = collapsed
        XCTAssertFalse(value.canReportRatios, "a singular matrix must be rejected even with finite mapped corners")
        XCTAssertNil(CardCenteringRatioPair(firstDistance: -1, secondDistance: 2))
        XCTAssertNil(CardCenteringRatioPair(firstDistance: 0, secondDistance: 2))
    }

    func testInvertedManualSidesHideRatiosAndRecoverWithoutChangingTheOppositeSide() {
        for usesQuads in [false, true] {
            let outer = CardCenteringEdges(left: 20, top: 20, right: 220, bottom: 316)
            let inner = CardCenteringEdges(left: 30, top: 30, right: 210, bottom: 306)
            var value = usesQuads
                ? CardCenteringMeasurement(imageWidth: 240, imageHeight: 336, outerQuad: .axisAligned(outer),
                    innerQuad: .axisAligned(inner), warnings: [], confidence: .legacyConfident)
                : CardCenteringMeasurement(imageWidth: 240, imageHeight: 336, outer: outer, inner: inner, warnings: [])
            XCTAssertTrue(value.canReportRatios)
            value.setManualInnerEdge(\.left, to: 211)
            XCTAssertFalse(value.canReportRatios)
            XCTAssertEqual(value.inner.left, 211, "the control must keep the edited side's position")
            XCTAssertEqual(value.inner.right, 210, "crossing a guide must not relabel the opposite side")
            value.setManualInnerEdge(\.left, to: 30)
            XCTAssertTrue(value.canReportRatios)
            XCTAssertEqual(value.geometryInnerQuad?.topRight.x, 210)
            value.setManualOuterEdge(\.top, to: 317)
            XCTAssertFalse(value.canReportRatios)
            XCTAssertEqual(value.outer.top, 317)
            XCTAssertEqual(value.outer.bottom, 316)
            value.setManualOuterEdge(\.top, to: 20)
            XCTAssertTrue(value.canReportRatios)
            XCTAssertEqual(value.geometryOuterQuad.bottomRight.y, 316)
        }
    }

    func testInvertingBothAxesNeverMakesMislabeledFramesReportable() {
        let outer = CardCenteringEdges(left: 20, top: 20, right: 220, bottom: 316)
        let inner = CardCenteringEdges(left: 30, top: 30, right: 210, bottom: 306)
        for usesQuads in [false, true] {
            var value = usesQuads
                ? CardCenteringMeasurement(imageWidth: 240, imageHeight: 336, outerQuad: .axisAligned(outer),
                    innerQuad: .axisAligned(inner), warnings: [], confidence: .legacyConfident)
                : CardCenteringMeasurement(imageWidth: 240, imageHeight: 336, outer: outer, inner: inner, warnings: [])
            value.setManualInnerEdge(\.left, to: 211)
            value.setManualInnerEdge(\.top, to: 307)
            XCTAssertFalse(value.canReportRatios)
            XCTAssertFalse(value.confirmFrames())
            XCTAssertEqual(value.leftRightCentering, "—")
            value.setManualInnerEdge(\.left, to: 30)
            value.setManualInnerEdge(\.top, to: 30)
            XCTAssertTrue(value.canReportRatios)
        }
    }

    func testCoincidentPerspectiveGuidesCannotTrapSubsequentEdits() {
        let outer = CardCenteringEdges(left: 20, top: 20, right: 220, bottom: 316)
        let inner = CardCenteringEdges(left: 30, top: 30, right: 210, bottom: 306)
        let pairs: [(WritableKeyPath<CardCenteringEdges, Int>, WritableKeyPath<CardCenteringEdges, Int>)] = [
            (\.left, \.right), (\.right, \.left), (\.top, \.bottom), (\.bottom, \.top)
        ]
        for (side, opposite) in pairs {
            var value = CardCenteringMeasurement(imageWidth: 240, imageHeight: 336,
                outerQuad: .axisAligned(outer), innerQuad: .axisAligned(inner), warnings: [], confidence: .legacyConfident)
            value.setManualOuterEdge(side, to: outer[keyPath: opposite])
            value.setManualOuterEdge(side, to: outer[keyPath: side])
            XCTAssertEqual(value.outerQuad, .axisAligned(outer))
            XCTAssertTrue(value.canReportRatios)
            value.setManualInnerEdge(side, to: inner[keyPath: opposite])
            value.setManualInnerEdge(side, to: inner[keyPath: side])
            XCTAssertEqual(value.innerQuad, .axisAligned(inner))
            XCTAssertTrue(value.canReportRatios)
        }
    }
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

    func testExportGuidesStayFixedWhenThePhotoRotates() throws {
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
        XCTAssertLessThanOrEqual(
            abs(upper[0] - lower[0]),
            1,
            "photo rotation must leave the left guide fixed"
        )
        XCTAssertEqual(try XCTUnwrap(upper.last), try XCTUnwrap(lower.last), accuracy: 1)
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
    func testOnScreenPhotoRotatesBeneathFixedGuides() throws {
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

        let stripedPhoto = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
            UIColor.green.setFill()
            context.fill(CGRect(x: 48, y: 0, width: 4, height: 140))
        }

        func slope(rotation: Double, photoStripe: Bool = false) throws -> Double {
            let rendered = ImageRenderer(
                content: CardCenteringImage(
                    image: stripedPhoto,
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
                    let matches = photoStripe
                        ? bytes[offset] < 100 && bytes[offset + 1] > 150 && bytes[offset + 2] < 100
                        : bytes[offset] > 150
                        && bytes[offset + 1] < 130
                        && bytes[offset + 2] < 130
                    return matches ? Double(x) : nil
                }
                guard let leftmost = xs.first else { continue }
                samples.append((leftmost, Double(y)))
            }
            XCTAssertGreaterThan(samples.count, 100)
            let meanX = samples.map { $0.x }.reduce(0, +) / Double(samples.count)
            let meanY = samples.map { $0.y }.reduce(0, +) / Double(samples.count)
            let denominator = samples.reduce(0) { $0 + pow($1.y - meanY, 2) }
            return samples.reduce(0) { $0 + ($1.y - meanY) * ($1.x - meanX) } / denominator
        }

        for rotation in [-7.0, 0, 7] {
            XCTAssertLessThan(abs(try slope(rotation: rotation)), 0.01)
        }
        XCTAssertLessThan(abs(try slope(rotation: 0, photoStripe: true)), 0.01)
        let clockwise = try slope(rotation: 7, photoStripe: true)
        let counterclockwise = try slope(rotation: -7, photoStripe: true)
        XCTAssertGreaterThan(abs(clockwise), 0.1)
        XCTAssertGreaterThan(abs(counterclockwise), 0.1)
        XCTAssertEqual(clockwise, -counterclockwise, accuracy: 0.01)
    }

    @MainActor
    func testRenderedGuideCentersStayWithinOneDevicePixelAfterRotationZoomAndPan() throws {
        let outer = CardCenteringQuad(topLeft: .init(x: 110, y: 100), topRight: .init(x: 880, y: 145),
            bottomRight: .init(x: 840, y: 1280), bottomLeft: .init(x: 150, y: 1230))
        let inner = CardCenteringQuad(topLeft: .init(x: 190, y: 210), topRight: .init(x: 800, y: 240),
            bottomRight: .init(x: 765, y: 1150), bottomLeft: .init(x: 215, y: 1110))
        let value = CardCenteringMeasurement(imageWidth: 1000, imageHeight: 1400,
            outerQuad: outer, innerQuad: inner, warnings: [])
        let size = CGSize(width: 320, height: 450)
        for screenScale in [CGFloat(2), 3] {
            for (rotation, zoom, pan) in [(0.0, 1.0, CGSize.zero), (7.0, 1.0, CGSize(width: 8, height: -4)),
                                          (-3.0, 2.0, CGSize(width: 120, height: 9))] {
                var reportedFrame = CGRect.zero
                let renderer = ImageRenderer(content: CardCenteringImage(
                    image: photo(width: 1000, height: 1400), measurement: value,
                    rotationDegrees: rotation, onFrameChange: { reportedFrame = $0 })
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(zoom).offset(pan)
                    .frame(width: size.width, height: size.height).clipped())
                renderer.scale = screenScale
                let cg = try XCTUnwrap(renderer.uiImage?.cgImage)
                let fit = min(size.width / 1000, size.height / 1400)
                let origin = CGPoint(x: (size.width - 1000 * fit) / 2, y: (size.height - 1400 * fit) / 2)
                XCTAssertEqual(reportedFrame.minX, origin.x, accuracy: 0.5)
                XCTAssertEqual(reportedFrame.minY + (size.height - reportedFrame.height) / 2, origin.y, accuracy: 0.5)
                var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                let context = try XCTUnwrap(CGContext(data: &bytes, width: cg.width, height: cg.height,
                    bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                var checked = 0
                for (quad, cyan) in [(outer, false), (inner, true)] {
                    for edge in 0..<4 {
                        let start = quad.points[edge], end = quad.points[(edge + 1) % 4]
                        for fraction in [0.25, 0.5, 0.75] {
                            let x = origin.x + (start.x + (end.x - start.x) * fraction) * fit - size.width / 2
                            let y = origin.y + (start.y + (end.y - start.y) * fraction) * fit - size.height / 2
                            let target = CGPoint(x: (size.width / 2 + zoom * x + pan.width) * screenScale,
                                                 y: (size.height / 2 + zoom * y + pan.height) * screenScale)
                            guard target.x > 4, target.y > 4, target.x < CGFloat(cg.width - 4), target.y < CGFloat(cg.height - 4) else { continue }
                            var nearest = Double.infinity
                            for py in (Int(target.y) - 3)...(Int(target.y) + 3) {
                                for px in (Int(target.x) - 3)...(Int(target.x) + 3) {
                                    let i = (py * cg.width + px) * 4
                                    let matches = cyan ? bytes[i] < 100 && bytes[i + 1] > 140 && bytes[i + 2] > 140
                                        : bytes[i] > 150 && bytes[i + 1] < 130 && bytes[i + 2] < 130
                                    if matches { nearest = min(nearest, hypot(Double(px) + 0.5 - target.x, Double(py) + 0.5 - target.y)) }
                                }
                            }
                            XCTAssertLessThanOrEqual(nearest, 1, "scale=\(screenScale) rotation=\(rotation) zoom=\(zoom) edge=\(edge) cyan=\(cyan)")
                            checked += 1
                        }
                    }
                }
                XCTAssertGreaterThanOrEqual(checked, 4, "each transform must check visible guide centers")
            }
        }
    }
}

final class CardCenteringAnalyzerTests: XCTestCase {
    func testOptimizedPixelKernelsAreBitExactWithTheScalarReference() {
        XCTAssertTrue(CardCenteringAnalyzer.pixelKernelsMatchReferenceForDiagnostics())
    }
    func testProfileDiagnosticsCoverAllFourSidesWhenProfilesAreEvaluated() throws {
        let data = syntheticCard(canvas: CGSize(width: 420, height: 600),
            cardRect: CGRect(x: 35, y: 45, width: 350, height: 490),
            borders: (left: 20, top: 24, right: 20, bottom: 24))
        var diagnostics = CardCenteringAnalyzer.Diagnostics()
        var profiles: [CardCenteringProfileDiagnostic] = []
        var branch: CardCenteringAnalysisDiagnostic?
        diagnostics.frontBottomCandidateGenerationEnabled = false
        diagnostics.profileDiagnosticSink = { profiles.append($0) }
        diagnostics.analysisDiagnosticSink = { branch = $0 }
        _ = try diagnostics.analyze(data)
        XCTAssertEqual(try XCTUnwrap(branch).profileDisposition, "evaluated")
        XCTAssertEqual(Set(profiles.map(\.side)), Set(["left", "top", "right", "bottom"]))
    }

    func testOverlappingDiagnosticRequestsKeepTheirCallbacksAndOptionsSeparate() async throws {
        let firstData = syntheticCard(canvas: CGSize(width: 420, height: 600),
            cardRect: CGRect(x: 35, y: 45, width: 350, height: 490),
            borders: (left: 20, top: 24, right: 20, bottom: 24))
        let secondData = syntheticCard(canvas: CGSize(width: 280, height: 400),
            cardRect: CGRect(x: 35, y: 53, width: 210, height: 294),
            borders: (left: 12, top: 15, right: 12, bottom: 15))
        @Sendable func capture(_ data: Data, reference: Bool) throws -> ([Int], [Int], CardCenteringMeasurement) {
            var options = CardCenteringAnalyzer.Diagnostics()
            options.useReferenceCalculations = reference
            options.frontBottomCandidateGenerationEnabled = false
            var widths: [Int] = []
            var ledgerWidths: [Int] = []
            options.profileDiagnosticSink = { widths.append($0.workingWidth) }
            options.candidateLedgerDiagnosticSink = { ledgerWidths.append($0.workingWidth) }
            let result = try options.analyze(data)
            return (widths, ledgerWidths, result.measurement)
        }
        async let first = Task.detached { try capture(firstData, reference: false) }.value
        async let second = Task.detached { try capture(secondData, reference: true) }.value
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.0, [420, 420, 420, 420])
        XCTAssertEqual(b.0, [280, 280, 280, 280])
        XCTAssertEqual(a.1, [420])
        XCTAssertEqual(b.1, [280])
        XCTAssertEqual(a.2, try CardCenteringAnalyzer.analyze(firstData).measurement)
        XCTAssertEqual(b.2, try CardCenteringAnalyzer.analyze(secondData).measurement)
    }

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
        var diagnostics = CardCenteringAnalyzer.Diagnostics()
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
            diagnostics.outerRefinementDiagnosticSink = { reports.append($0) }
            defer { diagnostics.outerRefinementDiagnosticSink = nil }
            _ = try diagnostics.analyze(data)
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
    /// explicitly confirms the reviewed frames. Edits alone keep the gate closed.
    /// Once confirmed, the ordinary case is quiet.
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

        m.setManualOuterEdge(\.left, to: m.outer.left)
        m.setManualInnerEdge(\.left, to: m.inner.left)
        m.refreshWarnings()

        XCTAssertTrue(m.isDeclined)
        XCTAssertTrue(m.confirmFrames())
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
