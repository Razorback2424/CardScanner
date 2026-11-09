import XCTest
import SwiftUI
@testable import TradingCardScanner

final class CenteringReviewTests: XCTestCase {
    private func candidate() -> CardCenteringBoundaryCandidate {
        .init(id: "alternative", frame: .inner, side: .left,
            nativeLine: .init(start: .init(x: 70, y: 740), end: .init(x: 70, y: 80)),
            source: "test", proposedRole: .artwork, competingRoles: [.printedBorder], signal: "test",
            strength: nil, polarity: nil, coverage: nil, fitResidualNativePixels: nil,
            sampleBands: [.init(start: .init(x: 70, y: 100), end: .init(x: 70, y: 200), sampleCount: nil)],
            exclusions: [.init(role: .shadow, reason: "Test exclusion",
                nativeBand: .init(start: .init(x: 70, y: 300), end: .init(x: 70, y: 400), sampleCount: nil))],
            selectionReason: .competingCandidate, reason: "Test alternative")
    }

    private func fixture(confirmed: Bool = true) -> CardCenteringMeasurement {
        var value = CardCenteringMeasurement(imageWidth: 600, imageHeight: 840,
            outerQuad: .init(topLeft: .init(x: 35, y: 40), topRight: .init(x: 555, y: 55),
                bottomRight: .init(x: 570, y: 800), bottomLeft: .init(x: 25, y: 785)),
            innerQuad: .init(topLeft: .init(x: 60, y: 80), topRight: .init(x: 520, y: 95),
                bottomRight: .init(x: 525, y: 755), bottomLeft: .init(x: 50, y: 740)),
            warnings: [], boundaryCandidates: [candidate()])
        if confirmed { XCTAssertTrue(value.confirmFrames(reference: .userPrintedBorder)) }
        return value
    }

    private func photo(size: CGSize = .init(width: 600, height: 840), draw: (CGContext) -> Void = { _ in }) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(.init(origin: .zero, size: size)); draw(context.cgContext)
        }
    }

    private func pixels(_ image: UIImage) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: .init(x: 0, y: 0, width: cg.width, height: cg.height))
        return (bytes, cg.width, cg.height)
    }

    @MainActor func testProductionCanvasDrawsOuterAndInnerGuidesOnPhotoCoordinates() throws {
        let outer = CardCenteringQuad.axisAligned(.init(left: 35, top: 40, right: 565, bottom: 800))
        let inner = CardCenteringQuad.axisAligned(.init(left: 60, top: 80, right: 540, bottom: 760))
        let value = CardCenteringMeasurement(imageWidth: 600, imageHeight: 840,
            outerQuad: outer, innerQuad: inner, warnings: [])
        var photoFrame: CGRect?
        let canvas = CardCenteringCanvas(image: photo(), measurement: value,
            rotationDegrees: 0, imageRevision: 0, lumaField: nil,
            selection: .constant(nil), onBeginEdit: {}, onEdit: { _ in },
            onAccessibilityNudge: { _ in }, onFrameChange: { photoFrame = $0 })
            .frame(width: 300, height: 420)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        let raster = try pixels(XCTUnwrap(renderer.uiImage))
        let frame = try XCTUnwrap(photoFrame)
        XCTAssertEqual(raster.width, 600)
        XCTAssertEqual(raster.height, 840)
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let offset = (y * raster.width + x) * 4
            return (Int(raster.bytes[offset]), Int(raster.bytes[offset + 1]), Int(raster.bytes[offset + 2]))
        }
        // The canvas fits the card, rather than leaving the whole photo at
        // zoom 1. Sample the same photo coordinates in its rendered frame.
        func pixelAtPhotoCoordinate(_ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int) {
            pixel(Int((frame.minX + x / 600 * frame.width) * renderer.scale),
                  Int((frame.minY + y / 840 * frame.height) * renderer.scale))
        }
        let red = pixelAtPhotoCoordinate(300, 40), cyan = pixelAtPhotoCoordinate(300, 80)
        let photoPixel = pixelAtPhotoCoordinate(300, 60)
        XCTAssertGreaterThan(red.0, red.1 + 50)
        XCTAssertGreaterThan(red.0, red.2 + 50)
        XCTAssertGreaterThan(cyan.1, cyan.0 + 30)
        XCTAssertGreaterThan(cyan.2, cyan.0 + 30)
        XCTAssertGreaterThan(photoPixel.0, 220)
        XCTAssertGreaterThan(photoPixel.1, 220)
        XCTAssertGreaterThan(photoPixel.2, 220)
    }

    @MainActor func testPerspectiveRasterLandmarksMatchOuterPointTransformWithPhotoRotation() throws {
        let value = fixture(), spatial = try XCTUnwrap(value.spatialMeasurement)
        let target = spatial.rectification.targetSize
        let fractions = [(0.2, 0.2), (0.8, 0.3), (0.35, 0.75), (0.7, 0.8)]
        for degrees in [0.0, -7.0, 12.0] {
            let raster = photo { context in
                context.setFillColor(UIColor.red.cgColor)
                for (x,y) in fractions {
                    let q = spatial.rectification.sourcePoint(fromRectified: .init(x: x * target.width, y: y * target.height))
                    let angle = -degrees * .pi / 180, dx = q.x - 300, dy = q.y - 420
                    let p = CGPoint(x: cos(angle) * dx - sin(angle) * dy + 300,
                                    y: sin(angle) * dx + cos(angle) * dy + 420)
                    context.fillEllipse(in: .init(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
            }
            let output = try CardCenteringReviewRenderer.render(image: raster, measurement: value, rotationDegrees: degrees)
            let data = try pixels(output.rectified)
            for (x,y) in fractions {
                let expectedX = x * Double(data.width), expectedY = y * Double(data.height)
                var count = 0.0, sumX = 0.0, sumY = 0.0
                for row in Int(expectedY - 10)...Int(expectedY + 10) {
                    for column in Int(expectedX - 10)...Int(expectedX + 10) {
                        let i = (row * data.width + column) * 4
                        if data.bytes[i] > 180 && data.bytes[i+1] < 80 && data.bytes[i+2] < 80 {
                            count += 1; sumX += Double(column) + 0.5; sumY += Double(row) + 0.5
                        }
                    }
                }
                XCTAssertGreaterThan(count, 10, "The known landmark must survive rectification")
                XCTAssertEqual(sumX / count, expectedX, accuracy: 1.5)
                XCTAssertEqual(sumY / count, expectedY, accuracy: 1.5)
            }
            XCTAssertEqual(output.revision, value.geometryRevision)
            XCTAssertEqual(value.spatialMeasurement, spatial, "Rendering must not normalize the selected inner lines")

            // Exercise the actual aspect-constrained SwiftUI panel, including
            // its horizontal padding, at phone/iPad widths and 2x/3x scale.
            // The intermediate-raster tolerance above is not the display gate.
            for width in [240.0, 362.0] { for scale in [2.0, 3.0] {
                let content = CardCenteringReviewImage(image: output.rectified, measurement: value, rectified: true)
                    .frame(width: width, height: 340)
                let renderer = ImageRenderer(content: content); renderer.scale = scale
                let screen = try pixels(XCTUnwrap(renderer.uiImage))
                let aspect = target.width / target.height
                let fittedHeight = min(340, width / aspect), fittedWidth = fittedHeight * aspect
                let left = (width - fittedWidth) / 2, top = (340 - fittedHeight) / 2
                var maximumError = 0.0
                for (x, y) in fractions {
                    let expectedX = (left + x * fittedWidth) * scale
                    let expectedY = (top + y * fittedHeight) * scale
                    var count = 0.0, sumX = 0.0, sumY = 0.0
                    for row in Int(expectedY - 10)...Int(expectedY + 10) {
                        for column in Int(expectedX - 10)...Int(expectedX + 10) {
                            let i = (row * screen.width + column) * 4
                            if screen.bytes[i] > 180 && screen.bytes[i+1] < 80 && screen.bytes[i+2] < 80 {
                                count += 1; sumX += Double(column) + 0.5; sumY += Double(row) + 0.5
                            }
                        }
                    }
                    XCTAssertGreaterThan(count, 10, "The displayed landmark must remain visible")
                    let error = hypot(sumX / count - expectedX, sumY / count - expectedY)
                    maximumError = max(maximumError, error)
                    XCTAssertLessThanOrEqual(error, 1, "Keep the existing one-device-pixel agreement gate")
                    XCTAssertLessThanOrEqual(error / scale, 0.5, "Keep the existing half-point agreement gate")
                }
                print("CENTERING_REVIEW_ALIGNMENT rotation=\(degrees) widthPoints=\(width) scale=\(scale) maximumDevicePixelError=\(maximumError)")
            } }
        }
    }

    func testReviewRastersHaveBoundedDimensionsAndRejectInvalidGeometry() throws {
        var value = fixture()
        value = .init(imageWidth: 2400, imageHeight: 3360,
            outerQuad: .axisAligned(.init(left: 40, top: 40, right: 2360, bottom: 3320)),
            innerQuad: .axisAligned(.init(left: 80, top: 80, right: 2320, bottom: 3280)), warnings: [])
        let output = try CardCenteringReviewRenderer.render(image: photo(), measurement: value, rotationDegrees: 0)
        for image in [output.photo, output.rectified] {
            XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1200)
        }
        value.innerQuad = nil
        XCTAssertThrowsError(try CardCenteringReviewRenderer.render(image: photo(), measurement: value, rotationDegrees: 0))
        XCTAssertThrowsError(try CardCenteringReviewRenderer.render(image: photo(), measurement: fixture(), rotationDegrees: .nan))
    }

    func testCancelledReviewCannotPublishARaster() async throws {
        let image = photo(), value = fixture()
        let job = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CardCenteringReviewRenderer.render(image: image, measurement: value, rotationDegrees: 0)
        }
        do { _ = try await job.value; XCTFail("Cancelled work must be rejected") }
        catch is CancellationError { }
    }

    @MainActor func testReviewAndShareSnapshotsExpireOnEditsRotationInputAndAnalysis() throws {
        let model = CardCenteringViewModel(); model.image = photo(); model.measurement = fixture()
        let initial = try XCTUnwrap(model.reviewSnapshot())
        model.compareBoundary("alternative")
        let share = try XCTUnwrap(model.exportSnapshot())
        XCTAssertNotNil(share.sensitivity?.boundaryChoices)
        model.updatePrecisionSide(.left, position: 72)
        XCTAssertFalse(model.matchesReview(initial)); XCTAssertFalse(model.matches(share))
        XCTAssertTrue(model.comparedCandidateIDs.isEmpty)
        model.undoPrecisionEdit()
        model.compareBoundary("alternative")
        let beforeRotation = try XCTUnwrap(model.reviewSnapshot())
        model.rotationDegrees = 1
        XCTAssertFalse(model.matchesReview(beforeRotation)); XCTAssertTrue(model.comparedCandidateIDs.isEmpty)
        XCTAssertNil(model.exportSnapshot())
        model.confirmFrames(reference: .userPrintedBorder)
        model.compareBoundary("alternative")
        let beforeInput = try XCTUnwrap(model.reviewSnapshot())
        model.image = photo()
        XCTAssertFalse(model.matchesReview(beforeInput)); XCTAssertNil(model.exportSnapshot())
        XCTAssertNil(model.boundaryComparison)
        model.isAnalyzing = true
        XCTAssertNil(model.reviewSnapshot())
    }

    @MainActor func testInspectingAnAlternativeDoesNotConfirmOrChangeGuidesAndSelectionIsUndoable() throws {
        let model = CardCenteringViewModel(); model.image = photo(); model.measurement = fixture(confirmed: false)
        let original = try XCTUnwrap(model.measurement)
        model.compareBoundary("alternative")
        XCTAssertEqual(model.measurement, original); XCTAssertNil(model.boundaryComparison)
        XCTAssertNotNil(model.reviewSnapshot()); XCTAssertNil(model.exportSnapshot())
        model.selectBoundaryCandidate("alternative")
        XCTAssertFalse(try XCTUnwrap(model.measurement).canReportRatios)
        XCTAssertEqual(model.measurement?.confidence, original.confidence)
        XCTAssertNotEqual(model.measurement?.innerQuad, original.innerQuad)
        model.undoPrecisionEdit()
        XCTAssertEqual(model.measurement, original)
    }

    func testReportSeparatesReviewVariationAndExplicitComparisonFromUnknownAccuracy() throws {
        let value = fixture(), sensitivity = value.boundarySensitivity(comparing: ["alternative"])
        let notes = CardCenteringExport.reportNotes(for: value, sensitivity: sensitivity).joined(separator: "\n")
        XCTAssertTrue(notes.contains("printed border chosen by you"))
        XCTAssertTrue(notes.contains("Across card:"))
        XCTAssertTrue(notes.contains("Compared boundary choices:"))
        XCTAssertTrue(notes.contains("not an accuracy interval"))
        XCTAssertFalse(CardCenteringExport.reportNotes(for: value).joined().contains("Compared boundary choices:"))
        let pending = fixture(confirmed: false)
        let hidden = CardCenteringExport.reportNotes(for: pending, sensitivity: sensitivity).joined()
        XCTAssertFalse(hidden.contains("Across card:")); XCTAssertFalse(hidden.contains("Compared boundary choices:"))
        XCTAssertFalse(hidden.contains("Frames reviewed by you"))
    }

    func testReportRejectsComparisonFromDifferentReferenceMappingRotationOrInput() {
        let value = fixture(), sensitivity = value.boundarySensitivity(comparing: ["alternative"])
        var changed = value
        XCTAssertTrue(changed.confirmFrames(reference: .userArtwork))
        XCTAssertFalse(CardCenteringExport.reportNotes(for: changed, sensitivity: sensitivity).joined().contains("Compared boundary choices:"))
        XCTAssertFalse(CardCenteringExport.reportNotes(for: value, sensitivity: sensitivity, rotationDegrees: 2).joined().contains("Compared boundary choices:"))
        let rotated = value.includingPhotoRotation(2).boundarySensitivity(comparing: ["alternative"])
        XCTAssertTrue(CardCenteringExport.reportNotes(for: value, sensitivity: rotated, rotationDegrees: 2).joined().contains("Compared boundary choices:"))
        changed = value.includingPhotoRotation(1)
        XCTAssertFalse(CardCenteringExport.reportNotes(for: changed, sensitivity: sensitivity).joined().contains("Compared boundary choices:"))
        let mapping = CardCenteringCoordinateMapping(orientedSourceSize: .init(width: 600, height: 840),
            workingSize: .init(width: 600, height: 840), appliedRotationDegrees: 0)
        let record = CardCenteringInputRecord(sha256: "new-source", byteCount: 100,
            rawRasterSize: .init(width: 600, height: 840), exifOrientation: 1, sourceColorSpace: nil,
            detectorMapping: mapping, presentationMapping: mapping, priorProcessingHistory: "unknown")
        var other = CardCenteringMeasurement(imageWidth: 600, imageHeight: 840, outerQuad: value.outerQuad,
            innerQuad: value.innerQuad, warnings: [], inputRecord: record, boundaryCandidates: [candidate()])
        XCTAssertTrue(other.confirmFrames(reference: .userPrintedBorder))
        XCTAssertFalse(CardCenteringExport.reportNotes(for: other, sensitivity: sensitivity).joined().contains("Compared boundary choices:"))
    }

    @MainActor func testSupportAndSpatialExclusionsRenderOnlyForRequestedAlternative() throws {
        let value = fixture(), image = photo()
        for id in [nil, "alternative"] as [String?] {
            let view = CardCenteringReviewImage(image: image, measurement: value, rectified: false, candidateID: id)
                .frame(width: 240, height: 336)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let data = try pixels(XCTUnwrap(renderer.uiImage))
            var green = [(Int,Int)](), orange = [(Int,Int)]()
            for row in 0..<data.height { for column in 0..<data.width {
                let i = (row * data.width + column) * 4
                let r = data.bytes[i], g = data.bytes[i+1], b = data.bytes[i+2]
                if g > 100 && Int(g) > Int(r) + 40 && Int(g) > Int(b) + 40 { green.append((column,row)) }
                if r > 200 && g > 70 && g < 190 && b < 70 { orange.append((column,row)) }
            } }
            if id == nil { XCTAssertTrue(green.isEmpty); XCTAssertTrue(orange.isEmpty) }
            else {
                XCTAssertGreaterThan(green.count, 20); XCTAssertGreaterThan(orange.count, 20)
                for (x,y) in green + orange {
                    XCTAssertEqual(Double(x), 70.0 * 0.8, accuracy: 7)
                    XCTAssertTrue((75...165).contains(y) || (235...325).contains(y), "Evidence must stay on its recorded side segment")
                }
            }
        }
    }

    func testOldExclusionWithoutSpatialBandDecodesAsUnknown() throws {
        let old = Data(#"{"role":"shadow","reason":"Interpretation only"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(CardCenteringBoundaryExclusion.self, from: old).nativeBand)
    }
}
