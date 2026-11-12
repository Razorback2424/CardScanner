import CryptoKit
import Darwin
import UIKit
import SwiftUI
import XCTest
@testable import TradingCardScanner

/// The same view model that publishes guides to the Centering screen loads
/// the original camera bytes. Photo review points enter only after analysis.
@MainActor final class CenteringPrintPilotTests: XCTestCase {
    private func resource(_ name: String, type: String, folder: String) throws -> Data {
        try Data(
            contentsOf: XCTUnwrap(
                Bundle(for: Self.self).url(
                    forResource: name, withExtension: type,
                    subdirectory: "TradingCards/" + folder)))
    }

    private func reference(_ name: String = "fin-289") throws -> CardCenteringPrintReference {
        try JSONDecoder().decode(
            CardCenteringPrintReference.self, from: resource(name, type: "json", folder: "PrintReferences"))
    }

    private func settle(_ model: CardCenteringViewModel) async throws -> CardCenteringMeasurement {
        let deadline = Date().addingTimeInterval(20)
        while model.isAnalyzing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isAnalyzing)
        return try XCTUnwrap(model.measurement)
    }

    func testKnownPrintUsesMeasuredArtworkAndRequiresReview() async throws {
        let model = CardCenteringViewModel(printReference: try reference())
        let bytes = try resource("IMG_0780", type: "HEIC", folder: "HEIC")
        let start = CFAbsoluteTimeGetCurrent()
        model.loadCapturedPhoto(bytes)
        let m = try await settle(model)
        let seconds = CFAbsoluteTimeGetCurrent() - start
        print("CENTERING_PRINT seconds=\(seconds) reference=\(m.referenceDefinition)")
        XCTAssertEqual(m.referenceDefinition, .matchedArtwork)
        XCTAssertFalse(m.canReportRatios)
        let mapping = try XCTUnwrap(m.coordinateMapping)
        let q = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        let strips: [(CardCenteringSide, [(Double, Double)])] = [
            (.left, [(347, 800), (348.5, 1200), (350.1, 1600), (351.4, 2000)]),
            (.right, [(2612.4, 800), (2617.4, 1200), (2622.6, 1600), (2626.9, 2000)]),
            (.top, [(700, 558.4), (1200, 556.3), (1650, 553.8), (2250, 551.9)]),
            (.bottom, [(700, 2226), (1200, 2222.5), (1650, 2219.3), (2250, 2215.3)]),
        ]
        for (side, pts) in strips {
            let (a, b) = q.segment(side)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let worst = pts.map { abs(dx * ($0.1 - a.y) - dy * ($0.0 - a.x)) / hypot(dx, dy) }.max()!
            print("PRINT_EDGE \(side) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side.rawValue)
        }
        let left = 100 * m.leftBorderDistance / (m.leftBorderDistance + m.rightBorderDistance)
        let top = 100 * m.topBorderDistance / (m.topBorderDistance + m.bottomBorderDistance)
        print("PRINT_MARGIN left=\(left) top=\(top)")
        XCTAssertEqual(left, 49.91953, accuracy: 2)
        XCTAssertEqual(top, 19.83572, accuracy: 2)
        XCTAssertEqual(m.selectedLines.filter { $0.frame == .inner && $0.reason == .detectorProposal }.count, 4)
        model.confirmFrames()
        let confirmed = try XCTUnwrap(model.measurement)
        XCTAssertTrue(confirmed.canReportRatios)
        XCTAssertEqual(confirmed.confidence, m.confidence)
        XCTAssertTrue(
            CardCenteringExport.reportNotes(for: confirmed).contains {
                $0.contains("20.0%") && $0.contains("Published design")
            })
    }

    func testKnownPrintedFrameUsesPhotoEdgesAndRequiresReview() async throws {
        let design = try reference("gengar-151-094")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("Document_2026-06-06_150759", type: "png", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let analysis = try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }
        }
        let m = analysis.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedPrintedBorder)
        XCTAssertEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
        XCTAssertFalse(m.canReportRatios)
        XCTAssertEqual(m.selectedLines.filter { $0.frame == .inner && $0.role == .printedBorder }.count, 4)
        let left = 100 * m.leftBorderDistance / (m.leftBorderDistance + m.rightBorderDistance)
        let top = 100 * m.topBorderDistance / (m.topBorderDistance + m.bottomBorderDistance)
        print("PRINTED_FRAME left=\(left) top=\(top)")
        // Cross-implementation agreement with the frozen supported native paths,
        // not independent physical truth or a new historical accuracy pass.
        XCTAssertEqual(left, 49.16557, accuracy: 2)
        XCTAssertEqual(top, 45.23626, accuracy: 2)
        let mapping = try XCTUnwrap(analysis.coordinateMapping)
        let native = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        // Frozen, directly supported Python photo observations; compare each side
        // so opposing edge errors cannot cancel in the two aggregate ratios.
        let observations: [(CardCenteringSide, [(Double, Double)])] = [
            (.left, [(102.731,468.079),(99.878,718.331),(97.837,968.591),(96.634,1135.433)]),
            (.top, [(306.552,179.438),(478.396,181.350),(650.249,182.397),(764.812,183.615)]),
            (.right, [(966.361,476.512),(965.052,726.597),(962.465,976.676),(960.683,1143.394)]),
            (.bottom, [(294.671,1428.357),(640.868,1431.683),(756.270,1432.471)]),
        ]
        for (side, points) in observations {
            let (a,b) = native.segment(side)
            let dx = b.x-a.x, dy = b.y-a.y
            let worst = points.map { abs(dx*($0.1-a.y)-dy*($0.0-a.x))/hypot(dx,dy) }.max()!
            print("PRINTED_EDGE \(side) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side.rawValue)
        }
        let model = CardCenteringViewModel(printReference: design)
        model.loadCapturedPhoto(bytes)
        let published = try await settle(model)
        XCTAssertEqual(published, m)
        model.confirmFrames()
        let confirmed = try XCTUnwrap(model.measurement)
        XCTAssertTrue(confirmed.canReportRatios)
        XCTAssertEqual(confirmed.referenceDefinition, .matchedPrintedBorder)
        XCTAssertEqual(confirmed.confidence, m.confidence)
        XCTAssertTrue(CardCenteringExport.reportNotes(for: confirmed).contains { $0.contains("Printed frame placement") })
    }

    func testPrintedFrameRejectsSharedLayoutAndWrongDesign() throws {
        let design = try reference("gengar-151-094")
        for name in ["IMG_0797", "IMG_1038", "IMG_0347", "IMG_0780"] {
            let bytes = try resource(name, type: "HEIC", folder: "HEIC")
            let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
            let assisted = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes).measurement
            }
            XCTAssertEqual(assisted, ordinary, name)
            XCTAssertFalse(assisted.canReportRatios)
        }
    }

    func testGoldPikachuPrintedFrameResearchTransfer() throws {
        let design = try reference("pikachu-ssp-247")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("Document_2026-06-06_152530", type: "png", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let analysis = try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }
        }
        let m = analysis.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedPrintedBorder)
        XCTAssertEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
        XCTAssertFalse(m.canReportRatios)
        let left = 100 * m.leftBorderDistance / (m.leftBorderDistance + m.rightBorderDistance)
        let top = 100 * m.topBorderDistance / (m.topBorderDistance + m.bottomBorderDistance)
        print("GOLD_PIKACHU left=\(left) top=\(top)")
        XCTAssertEqual(left, 50.78649, accuracy: 2)
        XCTAssertEqual(top, 52.25576, accuracy: 2)
        let mapping = try XCTUnwrap(analysis.coordinateMapping)
        let q = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        // Photo observations nearest four preselected sampling positions. Native
        // crop review corrected two foil-texture matches (top second, bottom third).
        // This remains a transfer diagnostic, not independent physical calibration.
        let observations: [(CardCenteringSide, [(Double, Double)])] = [
            (.left, [(462.809,1660.029),(479.196,2310.985),(492.233,2961.998),(503.257,3558.777)]),
            (.top, [(1191.402,584.704),(1611.388,578.5),(2108.155,566.104),(2566.516,556.012)]),
            (.right, [(3337.106,1602.668),(3352.804,2254.734),(3366.273,2906.848),(3379.264,3558.972)]),
            (.bottom, [(1266.525,4652.439),(1727.870,4643.287),(2150.927,4634.0),(2650.553,4624.701)]),
        ]
        for (side, points) in observations {
            let (a,b) = q.segment(side)
            let dx = b.x-a.x, dy = b.y-a.y
            let worst = points.map { abs(dx*($0.1-a.y)-dy*($0.0-a.x))/hypot(dx,dy) }.max()!
            print("GOLD_PIKACHU_EDGE \(side) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side.rawValue)
        }
        let other = try resource("Document_2026-06-06_151610", type: "png", folder: "HEIC")
        let otherOrdinary = try CardCenteringAnalyzer.analyze(other).measurement
        let otherAssisted = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(other).measurement
        }
        XCTAssertEqual(otherAssisted, otherOrdinary)
    }

    func testPrintedMeasurementSpanUsesBoundedBracketingObservations() {
        let samples = (0..<61).map { 0.15 + 0.70 * Double($0) / 60 }
        // Remove the samples immediately adjacent to an endpoint: the surviving
        // observations still bracket it with fewer than six missing samples.
        let bracketed = samples.filter { !($0 > 0.18 && $0 < 0.21) }
        XCTAssertTrue(CardCenteringPrintMatcher.hasSupportedMeasurementSpan(bracketed))
        XCTAssertFalse(CardCenteringPrintMatcher.hasSupportedMeasurementSpan(samples.filter { $0 > 0.20 }))
        XCTAssertFalse(CardCenteringPrintMatcher.hasSupportedMeasurementSpan(samples.filter { $0 < 0.80 }))
        XCTAssertFalse(CardCenteringPrintMatcher.hasSupportedMeasurementSpan(samples.filter { !($0 > 0.40 && $0 < 0.51) }))
        XCTAssertFalse(CardCenteringPrintMatcher.hasSupportedMeasurementSpan(Array(samples.prefix(29))))
    }

    func testReferenceLibraryDevelopmentCorpusSelectsGoldPikachu() throws {
        let gengar = try reference("gengar-151-094"), town = try reference(), pikachu = try reference("pikachu-ssp-247")
        try verifyDevelopmentLibrary([gengar, town, pikachu], expected: [
            "Document_2026-06-06_150759.png": gengar, "IMG_0780.HEIC": town,
            "Document_2026-06-06_152530.png": pikachu,
        ])
    }

    func testReferenceLibraryDevelopmentCorpusSelectsPrismaticPikachu() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        try verifyDevelopmentLibrary([gengar, town, ssp, pre], expected: [
            "Document_2026-06-06_150759.png": gengar, "IMG_0780.HEIC": town,
            "Document_2026-06-06_152530.png": ssp, "Document_2026-06-06_151610.png": pre,
        ])
    }

    func testPhysicalCutRejectsCompetingTransitionsAndInconsistentBackground() throws {
        func image(_ mode: Int) -> UIImage {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: CGSize(width: 700, height: 900), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 700, height: 900))
                if mode == 1 {
                    UIColor(white: 0.5, alpha: 1).setFill()
                    context.fill(CGRect(x: 105, y: 100, width: 475, height: 700))
                }
                UIColor.black.setFill(); context.fill(CGRect(x: 120, y: 100, width: 460, height: 700))
                if mode == 2 {
                    UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 450, width: 700, height: 450))
                    UIColor.white.setFill(); context.fill(CGRect(x: 120, y: 450, width: 460, height: 350))
                }
            }
        }
        let seed = CardCenteringQuad(topLeft: .init(x: 130, y: 100), topRight: .init(x: 580, y: 100),
            bottomRight: .init(x: 580, y: 800), bottomLeft: .init(x: 130, y: 800))
        let accepted = try XCTUnwrap(CardCenteringPrintMatcher.physicalSide(.left, seed: seed, source: image(0)))
        XCTAssertEqual(accepted.nativeLine.start.x, 120, accuracy: 1)
        XCTAssertEqual(accepted.nativeLine.end.x, 120, accuracy: 1)
        XCTAssertNil(CardCenteringPrintMatcher.physicalSide(.left, seed: seed, source: image(1)))
        XCTAssertNil(CardCenteringPrintMatcher.physicalSide(.left, seed: seed, source: image(2)))
        let clipped = CardCenteringQuad(topLeft: .init(x: 20, y: 100), topRight: seed.topRight,
            bottomRight: seed.bottomRight, bottomLeft: .init(x: 20, y: 800))
        XCTAssertNil(CardCenteringPrintMatcher.physicalSide(.left, seed: clipped, source: image(0)))
    }

    func testNativePhysicalCutPreservesArtworkOnKyoshiAndTheOoze() throws {
        let cases: [(String, String, Double, Double, [(CardCenteringSide, [(Double, Double)])])] = [
            ("IMG_0802", "avatar-kyoshi-tla-186", 51.62639, 20.09219, [
                (.left, [(210.370,1285.117),(211.615,1995.327),(216.968,2705.509)]),
                (.top, [(954.248,229.726),(1462.163,231.931),(1970.081,233.865)]),
                (.right, [(2734.410,1292.093),(2736.918,1997.475),(2738.935,2702.859)]),
                (.bottom, [(974.751,3764.485),(1480.917,3763.274),(1987.083,3761.923)]),
            ]),
            ("IMG_0809", "the-ooze-tmt-177", 51.10941, 19.16061, [
                (.left, [(207.743,1252.910),(213.090,1967.348),(219.275,2681.784)]),
                (.top, [(957.416,197.967),(1461.678,198.062),(1965.923,202.924)]),
                (.right, [(2737.292,1253.642),(2738.030,1963.178),(2745.534,2672.625)]),
                (.bottom, [(976.877,3743.646),(1488.991,3741.331),(2001.098,3738.080)]),
            ]),
        ]
        for (file, name, expectedLeft, expectedTop, observations) in cases {
            let design = try reference(name)
            let bytes = try resource(file, type: "HEIC", folder: "HEIC")
            let baseline = try CardCenteringPrintMatcher.$physicalRefinementEnabled.withValue(false) {
                try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                    try CardCenteringAnalyzer.analyze(bytes)
                }
            }
            let result = try CardCenteringPrintMatcher.$physicalRefinementEnabled.withValue(true) {
                try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
                    try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                        try CardCenteringAnalyzer.analyze(bytes)
                    }
                }
            }
            let m = result.measurement
            XCTAssertEqual(m.geometryInnerQuad, baseline.measurement.geometryInnerQuad, file)
            XCTAssertEqual(m.confidence, baseline.measurement.confidence)
            XCTAssertFalse(m.canReportRatios)
            XCTAssertNotEqual(m.geometryOuterQuad, baseline.measurement.geometryOuterQuad)
            XCTAssertEqual(m.boundaryCandidates.filter { $0.source == "selected.physical_background" }.count, 4)
            let mapping = try XCTUnwrap(result.coordinateMapping)
            let native = mapping.nativeQuad(fromWorking: m.geometryOuterQuad)
            for (side, points) in observations {
                let (a,b) = native.segment(side)
                let dx = b.x-a.x, dy = b.y-a.y
                let worst = points.map { abs(dx*($0.1-a.y)-dy*($0.0-a.x))/hypot(dx,dy) }.max()!
                print("PHYSICAL_EDGE \(file) \(side) worst=\(worst)")
                XCTAssertLessThanOrEqual(worst, 4, file+" "+side.rawValue)
            }
            let left = 100*m.leftBorderDistance/(m.leftBorderDistance+m.rightBorderDistance)
            let top = 100*m.topBorderDistance/(m.topBorderDistance+m.bottomBorderDistance)
            print("PHYSICAL_SHARES \(file) left=\(left) top=\(top)")
            XCTAssertEqual(left, expectedLeft, accuracy: 2)
            XCTAssertEqual(top, expectedTop, accuracy: 2)
            let attachment = XCTAttachment(data: try JSONEncoder().encode(native), uniformTypeIdentifier: "public.json")
            attachment.name = "native-physical-"+file; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testSpinerockAutomaticCurvedReviewConfirmationAndUndo() async throws {
        let model = CardCenteringViewModel(printReferences: [try reference(),try reference("spinerock-ecl-159")])
        model.loadCapturedPhoto(try resource("IMG_0803",type:"HEIC",folder:"HEIC"))
        let detected = try await settle(model)
        XCTAssertTrue(detected.hasObservedPaths)
        XCTAssertEqual(detected.referenceDefinition,.matchedArtwork)
        XCTAssertFalse(detected.canReportRatios)
        XCTAssertEqual(detected.leftRightCentering,"—")
        XCTAssertTrue(detected.selectedLines.isEmpty)
        XCTAssertNil(detected.spatialMeasurement)
        let paths = try XCTUnwrap(detected.observedPrintMeasurement)
        XCTAssertEqual(paths.leftShare,49.7806246074,accuracy:0.00001)
        XCTAssertEqual(paths.topShare,19.7570216846,accuracy:0.00001)
        XCTAssertEqual(detected.observedGuidePaths(outer:true).count,4)
        XCTAssertEqual(detected.observedGuidePaths(outer:false).count,4)
        model.adjustRotation(by:1)
        XCTAssertEqual(model.rotationDegrees,0)
        model.confirmFrames()
        let reviewed = try XCTUnwrap(model.measurement)
        XCTAssertTrue(reviewed.canReportRatios)
        XCTAssertEqual(reviewed.confidence,detected.confidence)
        XCTAssertEqual(reviewed.leftRightCentering,"49.8 / 50.2")
        XCTAssertEqual(reviewed.topBottomCentering,"19.8 / 80.2")
        XCTAssertNotNil(reviewed.spatialRatioDetail(horizontal:true))
        let picture = try XCTUnwrap(model.image)
        let export = CardCenteringExport.render(image:picture,measurement:reviewed,rotationDegrees:0)
        let rendered = XCTAttachment(image:export); rendered.name = "spinerock-curved-export"; rendered.lifetime = .keepAlways; add(rendered)
        let canvas = CardCenteringCanvas(image:picture,measurement:reviewed,rotationDegrees:0,imageRevision:1,
            selection:.constant(nil),onBeginEdit:{},onEdit:{_ in},onAccessibilityNudge:{_ in})
            .frame(width:390,height:720)
        let renderer = ImageRenderer(content:canvas)
        renderer.scale = 2
        let preview = XCTAttachment(image:try XCTUnwrap(renderer.uiImage))
        preview.name = "spinerock-curved-canvas"; preview.lifetime = .keepAlways; add(preview)
        let metadata = XCTAttachment(data:try JSONEncoder().encode(paths),uniformTypeIdentifier:"public.json")
        metadata.name = "spinerock-integrated-paths"; metadata.lifetime = .keepAlways; add(metadata)
        model.beginManualGuides()
        let manual = try XCTUnwrap(model.measurement)
        XCTAssertFalse(manual.hasObservedPaths)
        XCTAssertFalse(manual.canReportRatios)
        XCTAssertNotEqual(manual.geometryRevision,reviewed.geometryRevision)
        model.undo()
        XCTAssertEqual(model.measurement,reviewed)
        model.resetGuides()
        XCTAssertEqual(model.measurement,detected)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsSpinerock() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177"), spinerock = try reference("spinerock-ecl-159")
        try verifyDevelopmentLibrary([gengar,town,ssp,pre,foil,kyoshi,ooze,spinerock],expected:[
            "Document_2026-06-06_150759.png":gengar,"IMG_0780.HEIC":town,
            "Document_2026-06-06_152530.png":ssp,"Document_2026-06-06_151610.png":pre,
            "IMG_0802.HEIC":kyoshi,"IMG_0809.HEIC":ooze,"IMG_0803.HEIC":spinerock,
        ])
    }

    func testMichelangeloObservedArtworkAndPhysicalTransfer() throws {
        let design = try reference("michelangelo-tmt-121")
        let bytes = try resource("IMG_0811", type: "HEIC", folder: "HEIC")
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "8e2adabc21e6572a3af4084efa923d2500fc314c6e35567054d3a39d50358ad2")
        let result = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(bytes)
        }
        let m = result.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedArtwork)
        XCTAssertFalse(m.canReportRatios)
        let observed = try XCTUnwrap(m.observedPrintMeasurement)
        // Frozen photo observations precede native execution. Neither recognition
        // nor expected ratios supply the detector with these coordinates.
        let inner: [(String, [(Double, Double)])] = [
            ("left", [(426.057,1103.546),(425.616,1421.950),(425.170,1740.253)]),
            ("top", [(1074.357,629.637),(1506.210,631.893),(1937.057,634.229)]),
            ("right", [(2581.140,1113.310),(2581.218,1429.867),(2580.365,1746.322)]),
            ("bottom", [(1072.396,2218.148),(1503.912,2218.231),(1934.424,2218.334)]),
        ]
        let outer: [(String, [(Double, Double)])] = [
            ("left", [(228.130,1274.470),(230.106,1986.794),(233.221,2699.119)]),
            ("top", [(984.237,219.797),(1492.274,223.095),(2000.285,229.264)]),
            ("right", [(2763.174,1288.443),(2764.407,1994.905),(2766.644,2701.366)]),
            ("bottom", [(984.841,3759.374),(1495.191,3758.399),(2005.545,3758.716)]),
        ]
        for (paths, expected) in [(observed.innerPaths, inner), (observed.outerPaths, outer)] {
            for (side, points) in expected {
                let path = try XCTUnwrap(paths.first { $0.side == side })
                let horizontal = side == "top" || side == "bottom"
                let sorted = path.observations.compactMap { $0 }.sorted {
                    horizontal ? $0.x < $1.x : $0.y < $1.y
                }
                for (x,y) in points {
                    let along = horizontal ? x : y
                    let index = try XCTUnwrap(sorted.indices.dropLast().first {
                        (horizontal ? sorted[$0].x : sorted[$0].y) <= along &&
                        (horizontal ? sorted[$0+1].x : sorted[$0+1].y) >= along
                    }, side)
                    let a = sorted[index], b = sorted[index+1]
                    let t = (along-(horizontal ? a.x : a.y))/(horizontal ? b.x-a.x : b.y-a.y)
                    let value = horizontal ? a.y+t*(b.y-a.y) : a.x+t*(b.x-a.x)
                    XCTAssertEqual(value, horizontal ? y : x, accuracy: 4, side)
                }
            }
        }
        XCTAssertEqual(observed.leftShare, 51.571911, accuracy: 0.5)
        XCTAssertEqual(observed.topShare, 21.050789, accuracy: 0.5)
        print("MICHELANGELO_PAIRED left=\(observed.leftShare) top=\(observed.topShare)")
        let attachment = XCTAttachment(data: try JSONEncoder().encode(observed), uniformTypeIdentifier: "public.json")
        attachment.name = "michelangelo-native-paired-paths"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsMichelangelo() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177"), spinerock = try reference("spinerock-ecl-159")
        let michelangelo = try reference("michelangelo-tmt-121")
        try verifyDevelopmentLibrary([gengar,town,ssp,pre,foil,kyoshi,ooze,spinerock,michelangelo],expected:[
            "Document_2026-06-06_150759.png":gengar,"IMG_0780.HEIC":town,
            "Document_2026-06-06_152530.png":ssp,"Document_2026-06-06_151610.png":pre,
            "IMG_0802.HEIC":kyoshi,"IMG_0809.HEIC":ooze,"IMG_0803.HEIC":spinerock,
            "IMG_0811.HEIC":michelangelo,
        ])
    }

    private struct FrozenPhotoPaths: Decodable {
        let file, reference, inputSHA256: String
        let inner: [String: [[Double]]]
        let outer: [String: [[Double]]]?
        let leftShare, topShare: Double?
        let innerSeed, outerSeed: CardCenteringQuad?
    }

    private func verifyPhotoPaths(_ paths: [CardCenteringPrintMatcher.ObservedPath],
                                  against expected: [String: [[Double]]]) throws {
        XCTAssertEqual(Set(paths.map(\.side)), Set(expected.keys))
        for (side, points) in expected {
            let path = try XCTUnwrap(paths.first { $0.side == side })
            let horizontal = side == "top" || side == "bottom"
            let samples = path.observations.enumerated().compactMap { index, point in
                point.map { (index, $0) }
            }.sorted { horizontal ? $0.1.x < $1.1.x : $0.1.y < $1.1.y }
            var worst = 0.0
            for point in points {
                XCTAssertEqual(point.count, 2)
                let along = point[horizontal ? 0 : 1]
                let index = try XCTUnwrap(samples.indices.dropLast().first {
                    (horizontal ? samples[$0].1.x : samples[$0].1.y) <= along &&
                    (horizontal ? samples[$0+1].1.x : samples[$0+1].1.y) >= along
                }, "Unsupported frozen observation on \(side)")
                let a = samples[index], b = samples[index+1]
                XCTAssertLessThanOrEqual(abs(b.0-a.0)-1, 6, "Unsupported gap on \(side)")
                let t = (along-(horizontal ? a.1.x : a.1.y))/(horizontal ? b.1.x-a.1.x : b.1.y-a.1.y)
                let value = horizontal ? a.1.y+t*(b.1.y-a.1.y) : a.1.x+t*(b.1.x-a.1.x)
                worst = max(worst, abs(value-point[horizontal ? 1 : 0]))
            }
            print("FROZEN_PATH \(side) count=\(points.count) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side)
        }
    }

    func testYshtolaObservedArtworkAndPhysicalTransfer() throws {
        let frozen = try JSONDecoder().decode(FrozenPhotoPaths.self,
            from: resource("yshtola-photo-paths", type: "json", folder: "Supplementary"))
        let design = try reference(frozen.reference)
        let bytes = try resource("IMG_0813", type: "HEIC", folder: "HEIC")
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), frozen.inputSHA256)
        let result = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(bytes)
        }
        XCTAssertEqual(result.measurement.referenceDefinition, .matchedArtwork)
        XCTAssertFalse(result.measurement.canReportRatios)
        let observed = try XCTUnwrap(result.measurement.observedPrintMeasurement)
        try verifyPhotoPaths(observed.innerPaths, against: frozen.inner)
        try verifyPhotoPaths(observed.outerPaths, against: XCTUnwrap(frozen.outer))
        XCTAssertEqual(observed.leftShare, try XCTUnwrap(frozen.leftShare), accuracy: 0.5)
        XCTAssertEqual(observed.topShare, try XCTUnwrap(frozen.topShare), accuracy: 0.5)
        print("YSHTOLA_PAIRED left=\(observed.leftShare) top=\(observed.topShare)")
        let attachment = XCTAttachment(data: try JSONEncoder().encode(observed), uniformTypeIdentifier: "public.json")
        attachment.name = "yshtola-native-paired-paths"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testOjerAxonilArtworkPathsResearch() throws {
        let frozen = try JSONDecoder().decode(FrozenPhotoPaths.self,
            from: resource("ojer-axonil-artwork-photo-paths", type: "json", folder: "Supplementary"))
        let design = try reference(frozen.reference)
        let bytes = try resource("IMG_1477-2", type: "HEIC", folder: "HEIC")
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), frozen.inputSHA256)
        let baseline = try CardCenteringAnalyzer.analyze(bytes)
        let source = try XCTUnwrap(UIImage(data: bytes))
        let paths = try CardCenteringPrecisionSide.allCases.map { side in
            try XCTUnwrap(CardCenteringPrintMatcher.observedArtworkPath(side,
                reference: design, analysis: baseline, source: source))
        }
        try verifyPhotoPaths(paths, against: frozen.inner)
        XCTAssertFalse(baseline.measurement.canReportRatios)
        let attachment = XCTAttachment(data: try JSONEncoder().encode(paths), uniformTypeIdentifier: "public.json")
        attachment.name = "ojer-axonil-native-artwork-paths"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsYshtola() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177"), spinerock = try reference("spinerock-ecl-159")
        let michelangelo = try reference("michelangelo-tmt-121"), yshtola = try reference("yshtola-fin-086")
        try verifyDevelopmentLibrary([gengar,town,ssp,pre,foil,kyoshi,ooze,spinerock,michelangelo,yshtola],expected:[
            "Document_2026-06-06_150759.png":gengar,"IMG_0780.HEIC":town,
            "Document_2026-06-06_152530.png":ssp,"Document_2026-06-06_151610.png":pre,
            "IMG_0802.HEIC":kyoshi,"IMG_0809.HEIC":ooze,"IMG_0803.HEIC":spinerock,
            "IMG_0811.HEIC":michelangelo,"IMG_0813.HEIC":yshtola,
        ])
    }

    func testKyoshiSagaObservedArtworkAndPhysicalTransfer() throws {
        let frozen = try JSONDecoder().decode(FrozenPhotoPaths.self,
            from: resource("kyoshi-saga-photo-paths", type: "json", folder: "Supplementary"))
        let design = try reference(frozen.reference)
        let bytes = try resource("IMG_0801", type: "HEIC", folder: "HEIC")
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), frozen.inputSHA256)
        let result = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(bytes)
        }
        XCTAssertEqual(result.measurement.referenceDefinition, .matchedArtwork)
        XCTAssertFalse(result.measurement.canReportRatios)
        let placement = try XCTUnwrap(result.measurement.reviewedDesign)
        // This is deliberately asymmetric artwork, not a symmetric border grade.
        XCTAssertEqual(placement.designLeft, 100*370.0/426.0, accuracy: 0.000001)
        XCTAssertEqual(placement.designTop, 100*115.0/282.0, accuracy: 0.000001)
        let observed = try XCTUnwrap(result.measurement.observedPrintMeasurement)
        try verifyPhotoPaths(observed.innerPaths, against: frozen.inner)
        try verifyPhotoPaths(observed.outerPaths, against: XCTUnwrap(frozen.outer))
        XCTAssertEqual(observed.leftShare, try XCTUnwrap(frozen.leftShare), accuracy: 0.5)
        XCTAssertEqual(observed.topShare, try XCTUnwrap(frozen.topShare), accuracy: 0.5)
        print("KYOSHI_SAGA_PAIRED left=\(observed.leftShare) top=\(observed.topShare)")
        let attachment = XCTAttachment(data: try JSONEncoder().encode(observed), uniformTypeIdentifier: "public.json")
        attachment.name = "kyoshi-saga-native-paired-paths"; attachment.lifetime = .keepAlways; add(attachment)
        let reverseBytes = try resource("IMG_0802", type: "HEIC", folder: "HEIC")
        let ordinaryReverse = try CardCenteringAnalyzer.analyze(reverseBytes).measurement
        let wrongFace = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(reverseBytes).measurement
        }
        XCTAssertEqual(wrongFace, ordinaryReverse)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsKyoshiSaga() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177"), spinerock = try reference("spinerock-ecl-159")
        let michelangelo = try reference("michelangelo-tmt-121"), yshtola = try reference("yshtola-fin-086")
        let saga = try reference("kyoshi-saga-tla-186")
        try verifyDevelopmentLibrary([gengar,town,ssp,pre,foil,kyoshi,ooze,spinerock,michelangelo,yshtola,saga],expected:[
            "Document_2026-06-06_150759.png":gengar,"IMG_0780.HEIC":town,
            "Document_2026-06-06_152530.png":ssp,"Document_2026-06-06_151610.png":pre,
            "IMG_0802.HEIC":kyoshi,"IMG_0809.HEIC":ooze,"IMG_0803.HEIC":spinerock,
            "IMG_0811.HEIC":michelangelo,"IMG_0813.HEIC":yshtola,"IMG_0801.HEIC":saga,
        ])
    }

    func testUniformBorderModelsRecoverKnownTransitionAndRejectFlat() throws {
        for logistic in [false,true] {
            let raw = (-28...28).map { x -> SIMD3<Double> in
                let z = (Double(x)-2.35)/2.4
                let step = logistic ? 1/(1+exp(-1.7*z)) : 0.5*(1+erf(z/sqrt(2)))
                return SIMD3<Double>(30,40,25)+SIMD3<Double>(0.1,-0.1,0.05)*Double(x)+SIMD3<Double>(20,-15,8)*step
            }
            let fit = try XCTUnwrap(CardCenteringPrintMatcher.fitBorderRegion(raw,logistic:logistic))
            XCTAssertTrue(fit.accepted)
            XCTAssertEqual(fit.center,2.35,accuracy:0.05)
            XCTAssertEqual(fit.width,2.4,accuracy:0.05)
        }
        let flat = [SIMD3<Double>](repeating:SIMD3(repeating:5),count:57)
        XCTAssertFalse(try XCTUnwrap(CardCenteringPrintMatcher.fitBorderRegion(flat,logistic:false)).accepted)
        let weakOuter = (-80...80).map { x -> SIMD3<Double> in
            let interior = 0.5*(1+erf((Double(x)+20)/(2*sqrt(2))))
            let border = 0.5*(1+erf((Double(x)-20)/(2*sqrt(2))))
            return SIMD3(repeating:5+30*(1-interior)+10*(1-border))
        }
        let exterior = [SIMD3<Double>](repeating:SIMD3(repeating:5),count:25)
        XCTAssertEqual(try XCTUnwrap(CardCenteringPrintMatcher.uniformBorderProposal(weakOuter,exterior:exterior)),20,accuracy:1)
        XCTAssertNil(CardCenteringPrintMatcher.uniformBorderProposal(
            [SIMD3<Double>](repeating:SIMD3(repeating:5),count:161),exterior:exterior))
    }

    func testMagicBackSelectivePhotoTransfer() throws {
        let frozen = try JSONDecoder().decode(FrozenPhotoPaths.self,
            from:resource("magic-back-selective-photo-paths",type:"json",folder:"Supplementary"))
        let bytes = try resource("IMG_0810",type:"HEIC",folder:"HEIC")
        XCTAssertEqual(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),frozen.inputSHA256)
        let baseline = try CardCenteringAnalyzer.analyze(bytes)
        print("MAGIC_REFERENCE \(baseline.measurement.referenceDefinition)")
        let mapping = try XCTUnwrap(baseline.coordinateMapping)
        let outerSeed = mapping.nativeQuad(fromWorking:baseline.measurement.geometryOuterQuad)
        let innerSeed = mapping.nativeQuad(fromWorking:try XCTUnwrap(baseline.measurement.geometryInnerQuad))
        let source = try XCTUnwrap(UIImage(data:bytes))
        let outer = try CardCenteringPrecisionSide.allCases.map {
            try XCTUnwrap(CardCenteringPrintMatcher.observedPhysicalPath($0,seed:outerSeed,source:source))
        }
        let bottom = try XCTUnwrap(outer.first { $0.side == "bottom" })
        let inner = try CardCenteringPrecisionSide.allCases.map { side in
            try XCTUnwrap(side == .bottom
                ? CardCenteringPrintMatcher.observedUniformBorderPath(side,seed:innerSeed,physical:bottom,source:source)
                : CardCenteringPrintMatcher.observedPrintedSeedPath(side,seed:innerSeed,source:source))
        }
        let raw = XCTAttachment(data:try JSONEncoder().encode(["innerPaths":inner,"outerPaths":outer]),uniformTypeIdentifier:"public.json")
        raw.name = "magic-back-native-boundary-paths";raw.lifetime = .keepAlways;add(raw)
        try verifyPhotoPaths(inner,against:frozen.inner)
        try verifyPhotoPaths(outer,against:try XCTUnwrap(frozen.outer))
        let observed = try XCTUnwrap(CardCenteringPrintMatcher.measureObservedPaths(
            outer:outer,inner:inner,outerSeed:outerSeed,innerSeed:innerSeed))
        XCTAssertEqual(observed.leftShare,try XCTUnwrap(frozen.leftShare),accuracy:0.5)
        XCTAssertEqual(observed.topShare,try XCTUnwrap(frozen.topShare),accuracy:0.5)
        XCTAssertFalse(baseline.measurement.canReportRatios)
        print("MAGIC_SELECTIVE left=\(observed.leftShare) top=\(observed.topShare)")
        let automatic = try CardCenteringAnalyzer.$activeSelectiveBorderRepair.withValue(true) {
            try CardCenteringAnalyzer.analyze(bytes)
        }.measurement
        XCTAssertEqual(automatic.referenceDefinition,.magicClassicBack)
        XCTAssertNil(automatic.reviewedDesign)
        XCTAssertEqual(automatic.observedPrintMeasurement,observed)
        XCTAssertFalse(automatic.canReportRatios)
        let attachment = XCTAttachment(data:try JSONEncoder().encode(observed),uniformTypeIdentifier:"public.json")
        attachment.name = "magic-back-native-paired-paths";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testSquirtleExistingNativePathDiagnostic() throws {
        let frozen = try JSONDecoder().decode(FrozenPhotoPaths.self,
            from: resource("squirtle-foil-photo-paths", type: "json", folder: "Supplementary"))
        let bytes = try resource("Document_2026-06-06_175439", type: "png", folder: "HEIC")
        XCTAssertEqual(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),frozen.inputSHA256)
        let source = try XCTUnwrap(UIImage(data:bytes))
        let innerSeed = try XCTUnwrap(frozen.innerSeed), outerSeed = try XCTUnwrap(frozen.outerSeed)
        let inner = CardCenteringPrecisionSide.allCases.compactMap { side in
            let path = CardCenteringPrintMatcher.observedPrintedContinuityPath(side,seed:innerSeed,source:source)
            if path == nil { print("SQUIRTLE_BASELINE inner \(side.rawValue) unavailable") }
            return path
        }
        let outer = CardCenteringPrecisionSide.allCases.compactMap { side in
            let path = CardCenteringPrintMatcher.observedPhysicalPath(side,seed:outerSeed,source:source)
            if path == nil { print("SQUIRTLE_BASELINE outer \(side.rawValue) unavailable") }
            return path
        }
        for (frame, paths) in [("inner",inner),("outer",outer)] {
            for path in paths {
                print("SQUIRTLE_BASELINE \(frame) \(path.side) supported=\(path.observations.compactMap { $0 }.count)")
            }
        }
        let attachment = XCTAttachment(data:try JSONEncoder().encode(["innerPaths":inner,"outerPaths":outer]),
                                       uniformTypeIdentifier:"public.json")
        attachment.name = "squirtle-native-baseline-paths";attachment.lifetime = .keepAlways;add(attachment)
        XCTAssertEqual(inner.count,4,"All printed sides must be present for comparison")
        XCTAssertGreaterThanOrEqual(outer.count,1,"Keep diagnostics for the available physical sides")
        XCTAssertFalse(try CardCenteringAnalyzer.analyze(bytes).measurement.canReportRatios)
    }

    func testSquirtleClippedShadowContactIsOnlyAnUnidentifiedAlternative() throws {
        let bytes = try resource("Document_2026-06-06_175439",type:"png",folder:"HEIC")
        let baseline = try CardCenteringAnalyzer.analyze(bytes)
        let investigated = try CardCenteringAnalyzer.$activeShadowContactSides.withValue([.bottom]) {
            try CardCenteringAnalyzer.analyze(bytes)
        }
        let before = baseline.measurement, after = investigated.measurement
        XCTAssertEqual(after.geometryOuterQuad,before.geometryOuterQuad)
        XCTAssertEqual(after.geometryInnerQuad,before.geometryInnerQuad)
        XCTAssertEqual(after.confidence,before.confidence)
        XCTAssertEqual(after.boundaryCandidates.dropLast(),before.boundaryCandidates[...])
        XCTAssertFalse(after.canReportRatios)
        let candidate = try XCTUnwrap(after.boundaryCandidates.last)
        XCTAssertEqual(candidate.id,"research-shadow-contact-bottom")
        XCTAssertEqual(candidate.proposedRole,.unknown)
        XCTAssertEqual(candidate.selectionReason,.competingCandidate)
        let points = try XCTUnwrap(candidate.observedPoints)
        let stations = try XCTUnwrap(candidate.observedPointStations)
        XCTAssertEqual(points.count,stations.count)
        XCTAssertGreaterThanOrEqual(points.count,30)
        XCTAssertLessThan(points.count,61,"Unavailable or ambiguous stations must remain absent")
        XCTAssertEqual(stations,stations.sorted())
        let alternatives = after.reviewCandidates(frame:.outer,side:.bottom)
        XCTAssertTrue(alternatives.contains { $0.id == candidate.id })
        print("SQUIRTLE_SHADOW_CANDIDATE supported=\(points.count) residual=\(candidate.fitResidualNativePixels ?? -1) reviewIndex=\(alternatives.firstIndex { $0.id == candidate.id } ?? -1)")
        var expected = before
        expected.retainUnverifiedBoundaryCandidate(candidate)
        XCTAssertEqual(after,expected,"All existing measurement state and evidence must remain intact")
        // Broad source-photo review intervals identify the end of visible foil,
        // not a calibrated physical cut or the earlier shadow-following path.
        let intervals: [(Double,ClosedRange<Double>)] = [
            (500,4454...4461),(1000,4457...4464),(1500,4457...4464),
            (2000,4460...4467),(2500,4462...4469),
        ]
        let a = candidate.nativeLine.start,b = candidate.nativeLine.end
        for (x,band) in intervals {
            let y = a.y+(x-a.x)*(b.y-a.y)/(b.x-a.x)
            XCTAssertTrue(band.contains(y),"The candidate missed the reviewed source band at x=\(x): \(y)")
        }
        var selected = after
        XCTAssertTrue(selected.selectBoundaryCandidate(id:candidate.id,as:.physicalCut))
        XCTAssertFalse(selected.canReportRatios,"An explicit edge choice must not grant frame confirmation")
        XCTAssertEqual(selected.confidence,before.confidence)
        for old in after.selectedLines where !(old.frame == .outer && old.side == .bottom) {
            let current = try XCTUnwrap(selected.selectedLines.first { $0.frame == old.frame && $0.side == old.side })
            XCTAssertTrue(current.nativeLine.coincides(with:old.nativeLine),"Other supporting lines must stay fixed")
        }
        let attachment = XCTAttachment(data:try JSONEncoder().encode(candidate),uniformTypeIdentifier:"public.json")
        attachment.name = "squirtle-unidentified-shadow-contact";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testShadowContactCandidateKeepsSpoofAndClippingUncertain() throws {
        func image(_ mode: String) throws -> UIImage {
            let width = 600,height = 400,cut = mode == "clipped" ? 392 : 350,rule = 320
            var rgba = [UInt8](repeating:255,count:width*height*4)
            for y in 0..<height {
                for x in 0..<width {
                    var value = 255
                    if x >= 50 && x < 550 && y >= 50 && y < (mode == "spoof" ? height : cut) {
                        value = 135+((x*37+y*17+x*y*13)%81)
                    }
                    if x >= 50 && x < 550 {
                        if mode == "clipped",y >= cut { value = 50 }
                        if mode == "rule",y >= cut,y < cut+7 { value = 50 }
                        if mode == "rule",y >= cut+7,y < cut+17 { value = 50+(y-cut-6)*20 }
                        if y >= rule,y < rule+7 { value = 50 }
                        if mode == "spoof",y >= rule+7,y < rule+17 { value = 50+(y-rule-6)*20 }
                        if mode == "spoof",y >= rule+17 { value = 250 }
                    }
                    let index = (y*width+x)*4
                    rgba[index] = UInt8(value);rgba[index+1] = UInt8(value);rgba[index+2] = UInt8(value)
                }
            }
            let data = Data(rgba) as CFData
            let provider = try XCTUnwrap(CGDataProvider(data:data))
            let cg = try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,
                bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
            return UIImage(cgImage:cg)
        }
        func seed(_ bottom: Int) -> CardCenteringQuad {
            .axisAligned(.init(left:50,top:50,right:550,bottom:bottom))
        }
        let real = try XCTUnwrap(CardCenteringPrintMatcher.unverifiedShadowContactCandidate(
            .bottom,seed:seed(350),source:image("rule")))
        XCTAssertEqual(real.nativeLine.start.y,350,accuracy:2)
        XCTAssertEqual(real.proposedRole,.unknown)
        // This fake printed stripe is intentionally indistinguishable to the
        // local visual cue; it must stay an option, never a certified cut.
        let spoof = try XCTUnwrap(CardCenteringPrintMatcher.unverifiedShadowContactCandidate(
            .bottom,seed:seed(350),source:image("spoof")))
        XCTAssertEqual(spoof.nativeLine.start.y,320,accuracy:2)
        XCTAssertEqual(spoof.proposedRole,.unknown)
        XCTAssertEqual(spoof.selectionReason,.competingCandidate)
        XCTAssertNil(CardCenteringPrintMatcher.unverifiedShadowContactCandidate(
            .bottom,seed:seed(392),source:try image("clipped")))
    }

    func testPokemonBackPrintedContinuityAndPairedTransfer() throws {
        let design = try reference("pokemon-classic-back")
        let cases = try JSONDecoder().decode([FrozenPhotoPaths].self,
            from: resource("pokemon-back-paired-photo-paths", type: "json", folder: "Supplementary"))
        XCTAssertEqual(cases.count,2)
        var records: [String: CardCenteringPrintMatcher.ObservedMeasurement] = [:]
        for frozen in cases {
            let file = URL(fileURLWithPath:frozen.file)
            let bytes = try resource(file.deletingPathExtension().lastPathComponent,
                type:file.pathExtension,folder:"HEIC")
            XCTAssertEqual(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),frozen.inputSHA256)
            let baseline = try CardCenteringAnalyzer.analyze(bytes)
            let mapping = try XCTUnwrap(baseline.coordinateMapping)
            let outerSeed = mapping.nativeQuad(fromWorking:baseline.measurement.geometryOuterQuad)
            let innerSeed = mapping.nativeQuad(fromWorking:try XCTUnwrap(baseline.measurement.geometryInnerQuad))
            let source = try XCTUnwrap(UIImage(data:bytes))
            let inner = try CardCenteringPrecisionSide.allCases.map {
                try XCTUnwrap(CardCenteringPrintMatcher.observedPrintedContinuityPath($0,seed:innerSeed,source:source))
            }
            let outer = try CardCenteringPrecisionSide.allCases.map {
                try XCTUnwrap(CardCenteringPrintMatcher.observedPhysicalPath($0,seed:outerSeed,source:source))
            }
            print("BACK_PAIRED \(frozen.file)")
            try verifyPhotoPaths(inner,against:frozen.inner)
            try verifyPhotoPaths(outer,against:try XCTUnwrap(frozen.outer))
            let observed = try XCTUnwrap(CardCenteringPrintMatcher.measureObservedPaths(
                outer:outer,inner:inner,outerSeed:outerSeed,innerSeed:innerSeed))
            XCTAssertEqual(observed.leftShare,try XCTUnwrap(frozen.leftShare),accuracy:0.5)
            XCTAssertEqual(observed.topShare,try XCTUnwrap(frozen.topShare),accuracy:0.5)
            XCTAssertFalse(baseline.measurement.canReportRatios)
            print("BACK_SHARES \(frozen.file) left=\(observed.leftShare) top=\(observed.topShare)")
            let automatic = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }.measurement
            XCTAssertEqual(automatic.referenceDefinition,.matchedPrintedBorder)
            XCTAssertEqual(automatic.innerReference,.printedBorder)
            XCTAssertTrue(automatic.hasObservedPaths)
            XCTAssertEqual(automatic.observedPrintMeasurement,observed)
            XCTAssertFalse(automatic.canReportRatios)
            records[frozen.file] = observed
        }
        let attachment = XCTAttachment(data:try JSONEncoder().encode(records),uniformTypeIdentifier:"public.json")
        attachment.name = "pokemon-back-native-paired-paths"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsPokemonBacks() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177"), spinerock = try reference("spinerock-ecl-159")
        let michelangelo = try reference("michelangelo-tmt-121"), yshtola = try reference("yshtola-fin-086")
        let saga = try reference("kyoshi-saga-tla-186"), back = try reference("pokemon-classic-back")
        try verifyDevelopmentLibrary([gengar,town,ssp,pre,foil,kyoshi,ooze,spinerock,michelangelo,yshtola,saga,back],expected:[
            "Document_2026-06-06_150759.png":gengar,"IMG_0780.HEIC":town,
            "Document_2026-06-06_152530.png":ssp,"Document_2026-06-06_151610.png":pre,
            "IMG_0802.HEIC":kyoshi,"IMG_0809.HEIC":ooze,"IMG_0803.HEIC":spinerock,
            "IMG_0811.HEIC":michelangelo,"IMG_0813.HEIC":yshtola,"IMG_0801.HEIC":saga,
            "IMG_0798.HEIC":back,"IMG_0800.HEIC":back,
        ])
    }

    func testDevelopmentCorpusSelectivelyRepairsMagicBack() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177"), spinerock = try reference("spinerock-ecl-159")
        let michelangelo = try reference("michelangelo-tmt-121"), yshtola = try reference("yshtola-fin-086")
        let saga = try reference("kyoshi-saga-tla-186"), back = try reference("pokemon-classic-back")
        try verifyDevelopmentLibrary([gengar,town,ssp,pre,foil,kyoshi,ooze,spinerock,michelangelo,yshtola,saga,back],expected:[
            "Document_2026-06-06_150759.png":gengar,"IMG_0780.HEIC":town,
            "Document_2026-06-06_152530.png":ssp,"Document_2026-06-06_151610.png":pre,
            "IMG_0802.HEIC":kyoshi,"IMG_0809.HEIC":ooze,"IMG_0803.HEIC":spinerock,
            "IMG_0811.HEIC":michelangelo,"IMG_0813.HEIC":yshtola,"IMG_0801.HEIC":saga,
            "IMG_0798.HEIC":back,"IMG_0800.HEIC":back,
        ],selectiveRepairs:["IMG_0810.HEIC"])
    }

    func testPokemonBackPhysicalPathTransfer() throws {
        struct FrozenCut: Decodable {
            let file, inputSHA256: String
            let outer: [String: [[Double]]]
        }
        let cases = try JSONDecoder().decode([FrozenCut].self,
            from: resource("pokemon-back-physical-photo-paths", type: "json", folder: "Supplementary"))
        XCTAssertEqual(cases.count, 2)
        var records: [String: [CardCenteringPrintMatcher.ObservedPath]] = [:]
        for frozen in cases {
            let file = URL(fileURLWithPath: frozen.file)
            let bytes = try resource(file.deletingPathExtension().lastPathComponent,
                type: file.pathExtension, folder: "HEIC")
            XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), frozen.inputSHA256)
            let baseline = try CardCenteringAnalyzer.analyze(bytes)
            let mapping = try XCTUnwrap(baseline.coordinateMapping)
            let seed = mapping.nativeQuad(fromWorking: baseline.measurement.geometryOuterQuad)
            let source = try XCTUnwrap(UIImage(data: bytes))
            let paths = try CardCenteringPrecisionSide.allCases.map {
                try XCTUnwrap(CardCenteringPrintMatcher.observedPhysicalPath($0, seed: seed, source: source))
            }
            print("BACK_PHYSICAL \(frozen.file)")
            try verifyPhotoPaths(paths, against: frozen.outer)
            XCTAssertFalse(baseline.measurement.canReportRatios)
            records[frozen.file] = paths
        }
        let attachment = XCTAttachment(data: try JSONEncoder().encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "pokemon-back-native-physical-paths"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSpinerockPairedCurvedMeasurementResearch() throws {
        let design = try reference("spinerock-ecl-159")
        let bytes = try resource("IMG_0803", type: "HEIC", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes)
        let result = try XCTUnwrap(CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            CardCenteringPrintMatcher.observedMeasurement(reference: design,analysis: ordinary,
                source: try XCTUnwrap(UIImage(data: bytes)))
        })
        XCTAssertEqual(result.outerPaths.count,4)
        XCTAssertEqual(result.innerPaths.count,4)
        XCTAssertEqual(result.localLeftShares.count,31)
        XCTAssertEqual(result.localTopShares.count,31)
        XCTAssertEqual(result.leftShare,49.79899,accuracy: 0.5)
        XCTAssertEqual(result.topShare,19.75491,accuracy: 0.5)
        XCTAssertFalse(ordinary.measurement.canReportRatios)
        print("SPINEROCK_PAIRED left=\(result.leftShare) top=\(result.topShare)")
        let attachment = XCTAttachment(data: try JSONEncoder().encode(result), uniformTypeIdentifier: "public.json")
        attachment.name = "spinerock-native-paired-paths"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPairedCurvedPathsRecoverKnownGeometryAndRejectMissingSupport() throws {
        typealias P = CardCenteringPoint
        typealias Q = CardCenteringQuad
        typealias Path = CardCenteringPrintMatcher.ObservedPath
        let outer = Q(topLeft: P(x:0,y:0),topRight: P(x:1,y:0),bottomRight: P(x:1,y:1),bottomLeft: P(x:0,y:1))
        let inner = Q(topLeft: P(x:0.04,y:0.12),topRight: P(x:0.94,y:0.12),bottomRight: P(x:0.94,y:0.52),bottomLeft: P(x:0.04,y:0.52))
        func project(_ p: P) -> P {
            let d = 0.08*p.x+0.15*p.y+1
            return P(x:(1800*p.x+150*p.y+250)/d,y:(50*p.x+2800*p.y+100)/d)
        }
        func projected(_ q: Q) -> Q {
            Q(topLeft:project(q.topLeft),topRight:project(q.topRight),bottomRight:project(q.bottomRight),bottomLeft:project(q.bottomLeft))
        }
        func paths(_ q: Q, _ mode: Int) -> [Path] {
            CardCenteringPrecisionSide.allCases.map { side in
                let a = q.points[side.index], b = q.points[(side.index+1)%4]
                let points: [P?] = (0..<61).map { i in
                    let t = 0.1+0.8*Double(i)/60
                    var p = P(x:a.x+t*(b.x-a.x),y:a.y+t*(b.y-a.y))
                    if mode == 2 { p.y = p.y*(0.9+0.2*p.x)+0.02*pow(2*p.x-1,2) }
                    if mode == 3 { p.x = p.x*(0.9+0.2*p.y)+0.02*pow(2*p.y-1,2) }
                    return mode == 0 ? p : project(p)
                }
                return Path(side:side.rawValue,observations:points)
            }
        }
        for mode in 0...3 {
            let result = try XCTUnwrap(CardCenteringPrintMatcher.measureObservedPaths(
                outer:paths(outer,mode),inner:paths(inner,mode),
                outerSeed:mode == 0 ? outer : projected(outer),innerSeed:mode == 0 ? inner : projected(inner)))
            XCTAssertEqual(result.leftShare,40,accuracy:0.005)
            XCTAssertEqual(result.topShare,20,accuracy:0.005)
        }
        for kind in 0...2 {
            var broken = paths(inner,0)
            let index = try XCTUnwrap(broken.firstIndex { $0.side == (kind == 1 ? "top" : "left") })
            var points = broken[index].observations
            if kind == 0 { for i in 0..<25 { points[i] = nil } }
            if kind == 1 { for i in 25..<33 { points[i] = nil } }
            if kind == 2 { points = points.map { $0.map { P(x:-0.01,y:$0.y) } } }
            broken[index] = Path(side:broken[index].side,observations:points)
            XCTAssertNil(CardCenteringPrintMatcher.measureObservedPaths(outer:paths(outer,0),inner:broken,
                outerSeed:outer,innerSeed:inner))
        }
    }

    func testSpinerockCurvedArtworkPathResearch() throws {
        let design = try reference("spinerock-ecl-159")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("IMG_0803", type: "HEIC", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes)
        let source = try XCTUnwrap(UIImage(data: bytes))
        let path = try XCTUnwrap(CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            CardCenteringPrintMatcher.observedArtworkPath(.top, reference: design, analysis: ordinary, source: source)
        })
        XCTAssertEqual(path.observations.count, 61)
        let positions = path.observations.enumerated().compactMap { index, point in
            point == nil ? nil : 0.1+0.8*Double(index)/60
        }
        XCTAssertTrue(CardCenteringPrintMatcher.hasSupportedMeasurementSpan(positions))
        let observed = path.observations.compactMap { $0 }.sorted { $0.x < $1.x }
        // Frozen offline photo-gradient locations, before native implementation.
        // This checks transfer on the same capture, not physical calibration.
        let comparison: [(Double, Double)] = [
            (799.361795, 632.637167),
            (828.266044, 632.425683),
            (857.184213, 631.976639),
            (886.119832, 631.590198),
            (915.075802, 631.512764),
            (944.042169, 630.893160),
            (973.025185, 630.264029),
            (1002.026481, 629.763376),
            (1031.045520, 629.344123),
            (1060.084807, 629.218950),
            (1089.138853, 628.917829),
            (1118.212311, 628.836933),
            (1147.301873, 628.692488),
            (1176.407880, 628.512252),
            (1205.533912, 628.600865),
            (1234.674832, 628.518388),
            (1263.831804, 628.362789),
            (1293.008642, 628.458627),
            (1322.203331, 628.632595),
            (1351.410605, 628.433725),
            (1380.637242, 628.439593),
            (1409.882388, 628.575893),
            (1439.142586, 628.546276),
            (1468.423165, 628.804498),
            (1497.720914, 629.074983),
            (1527.036352, 629.401009),
            (1556.374306, 630.193307),
            (1585.721524, 630.319041),
            (1615.089947, 630.796695),
            (1644.474623, 631.202003),
            (1673.877978, 631.740821),
            (1703.295505, 632.027187),
            (1732.729314, 632.239863),
            (1762.179274, 632.366481),
            (1791.650091, 632.807483),
            (1821.137157, 633.168231),
            (1850.645866, 633.907942),
            (1880.174513, 634.879821),
            (1909.717562, 635.609730),
            (1939.274231, 636.029759),
            (1968.849147, 636.533577),
            (1998.447217, 637.539060),
            (2028.064488, 638.707250),
            (2057.692599, 639.322868),
            (2087.339167, 640.035196),
            (2116.999582, 640.449097),
            (2146.690279, 641.966832)
        ]
        var worst = 0.0
        for (x,y) in comparison {
            let i = try XCTUnwrap(observed.indices.dropFirst().first { observed[$0].x >= x })
            let a = observed[i-1], b = observed[i]
            XCTAssertGreaterThanOrEqual(x, a.x)
            let measured = a.y+(b.y-a.y)*(x-a.x)/(b.x-a.x)
            worst = max(worst,abs(y-measured))
        }
        print("SPINEROCK_PATH supported=\(observed.count) worst=\(worst)")
        XCTAssertLessThanOrEqual(worst, 4)
        XCTAssertFalse(ordinary.measurement.canReportRatios)
        let attachment = XCTAttachment(data: try JSONEncoder().encode(path), uniformTypeIdentifier: "public.json")
        attachment.name = "spinerock-native-top-path"; attachment.lifetime = .keepAlways; add(attachment)
        let otherBytes = try resource("IMG_0809", type: "HEIC", folder: "HEIC")
        let other = try CardCenteringAnalyzer.analyze(otherBytes)
        XCTAssertNil(CardCenteringPrintMatcher.observedArtworkPath(.top, reference: design,
            analysis: other, source: try XCTUnwrap(UIImage(data: otherBytes))))
        var duplicated = design
        duplicated.boundaryProfiles = (design.boundaryProfiles ?? [])+(design.boundaryProfiles ?? [])
        XCTAssertFalse(duplicated.isValid)
    }

    func testTheOozeArtworkTransferResearch() throws {
        let design = try reference("the-ooze-tmt-177")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("IMG_0809", type: "HEIC", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let result = try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }
        }
        let m = result.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedArtwork)
        XCTAssertNotEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
        XCTAssertFalse(m.canReportRatios)
        let mapping = try XCTUnwrap(result.coordinateMapping)
        let native = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        let observations: [(CardCenteringSide, [(Double, Double)])] = [
            (.left, [(397.377,1054.681),(398.588,1374.044),(399.759,1693.407)]),
            (.top, [(1043.043,573.065),(1475.889,572.826),(1908.739,575.144)]),
            (.right, [(2555.701,1049.492),(2557.627,1368.081),(2559.106,1686.670)]),
            (.bottom, [(1048.742,2168.566),(1480.880,2166.863),(1913.018,2165.276)]),
        ]
        for (side, points) in observations {
            let (a,b) = native.segment(side)
            let dx = b.x-a.x, dy = b.y-a.y
            let worst = points.map { abs(dx*($0.1-a.y)-dy*($0.0-a.x))/hypot(dx,dy) }.max()!
            print("THE_OOZE_EDGE \(side) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side.rawValue)
        }
        let left = 100*m.leftBorderDistance/(m.leftBorderDistance+m.rightBorderDistance)
        let top = 100*m.topBorderDistance/(m.topBorderDistance+m.bottomBorderDistance)
        print("THE_OOZE left=\(left) top=\(top)")
        XCTAssertEqual(left, 51.60175, accuracy: 2)
        XCTAssertEqual(top, 20.10379, accuracy: 2)
        let attachment = XCTAttachment(data: try JSONEncoder().encode(native), uniformTypeIdentifier: "public.json")
        attachment.name = "the-ooze-native-inner"; attachment.lifetime = .keepAlways; add(attachment)
        let other = try resource("IMG_0802", type: "HEIC", folder: "HEIC")
        let otherOrdinary = try CardCenteringAnalyzer.analyze(other).measurement
        let assisted = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(other).measurement
        }
        XCTAssertEqual(assisted, otherOrdinary)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsTheOoze() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        let ooze = try reference("the-ooze-tmt-177")
        try verifyDevelopmentLibrary([gengar, town, ssp, pre, foil, kyoshi, ooze], expected: [
            "Document_2026-06-06_150759.png": gengar, "IMG_0780.HEIC": town,
            "Document_2026-06-06_152530.png": ssp, "Document_2026-06-06_151610.png": pre,
            "IMG_0802.HEIC": kyoshi, "IMG_0809.HEIC": ooze,
        ])
    }

    func testAvatarKyoshiArtworkTransferResearch() throws {
        let design = try reference("avatar-kyoshi-tla-186")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("IMG_0802", type: "HEIC", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let result = try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }
        }
        let m = result.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedArtwork)
        XCTAssertNotEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
        XCTAssertFalse(m.canReportRatios)
        let mapping = try XCTUnwrap(result.coordinateMapping)
        let native = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        // Frozen native-photo observations of the artwork's outer black rule.
        // The title-side edge below the white stripe is a different boundary.
        let observations: [(CardCenteringSide, [(Double, Double)])] = [
            (.left, [(400.77,1100.25),(401.58,1420.31),(402.14,1740.37)]),
            (.top, [(1047.25,621.70),(1479.41,623.54),(1911.58,625.33)]),
            (.right, [(2555.00,1100.50),(2555.90,1418.70),(2556.25,1736.90)]),
            (.bottom, [(1051,2209.5),(1483,2208.5),(1915,2206.8)]),
        ]
        for (side, points) in observations {
            let (a,b) = native.segment(side)
            let dx = b.x-a.x, dy = b.y-a.y
            let worst = points.map { abs(dx*($0.1-a.y)-dy*($0.0-a.x))/hypot(dx,dy) }.max()!
            print("AVATAR_KYOSHI_EDGE \(side) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side.rawValue)
        }
        let attachment = XCTAttachment(data: try JSONEncoder().encode(native), uniformTypeIdentifier: "public.json")
        attachment.name = "avatar-kyoshi-native-inner"; attachment.lifetime = .keepAlways; add(attachment)
        print("AVATAR_KYOSHI left=\(100*m.leftBorderDistance/(m.leftBorderDistance+m.rightBorderDistance)) top=\(100*m.topBorderDistance/(m.topBorderDistance+m.bottomBorderDistance))")
        XCTAssertEqual(100*m.leftBorderDistance/(m.leftBorderDistance+m.rightBorderDistance), 52.33061, accuracy: 2)
        XCTAssertEqual(100*m.topBorderDistance/(m.topBorderDistance+m.bottomBorderDistance), 20.21077, accuracy: 2)
        // Same Magic family is insufficient: the existing artwork control stays ordinary.
        let other = try resource("IMG_0780", type: "HEIC", folder: "HEIC")
        let otherOrdinary = try CardCenteringAnalyzer.analyze(other).measurement
        let assisted = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(other).measurement
        }
        XCTAssertEqual(assisted, otherOrdinary)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsAvatarKyoshi() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057"), kyoshi = try reference("avatar-kyoshi-tla-186")
        try verifyDevelopmentLibrary([gengar, town, ssp, pre, foil, kyoshi], expected: [
            "Document_2026-06-06_150759.png": gengar, "IMG_0780.HEIC": town,
            "Document_2026-06-06_152530.png": ssp, "Document_2026-06-06_151610.png": pre,
            "IMG_0802.HEIC": kyoshi,
        ])
    }

    func testFoilGengarNativeFrameTransferResearch() throws {
        let design = try reference("gengar-paf-057")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("IMG_1038", type: "HEIC", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let result = try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }
        }
        let m = result.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedPrintedBorder)
        XCTAssertEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
        XCTAssertFalse(m.canReportRatios)
        // This first transfer check records the proposed frame for source-photo
        // review; producing a quad alone is not an accuracy acceptance.
        let mapping = try XCTUnwrap(result.coordinateMapping)
        let q = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        let attachment = XCTAttachment(data: try JSONEncoder().encode(q), uniformTypeIdentifier: "public.json")
        attachment.name = "foil-gengar-native-inner"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("FOIL_GENGAR left=\(100*m.leftBorderDistance/(m.leftBorderDistance+m.rightBorderDistance)) top=\(100*m.topBorderDistance/(m.topBorderDistance+m.bottomBorderDistance))")
        let other = try resource("Document_2026-06-06_150759", type: "png", folder: "HEIC")
        let otherOrdinary = try CardCenteringAnalyzer.analyze(other).measurement
        let assisted = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(other).measurement
        }
        XCTAssertEqual(assisted, otherOrdinary)
    }

    func testReferenceLibraryDevelopmentCorpusSelectsFoilGengar() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let ssp = try reference("pikachu-ssp-247"), pre = try reference("pikachu-pre-179")
        let foil = try reference("gengar-paf-057")
        try verifyDevelopmentLibrary([gengar, town, ssp, pre, foil], expected: [
            "Document_2026-06-06_150759.png": gengar, "IMG_0780.HEIC": town,
            "Document_2026-06-06_152530.png": ssp, "Document_2026-06-06_151610.png": pre,
            "IMG_1038.HEIC": foil,
        ])
    }

    func testColorReferenceRejectsRepeatedSignals() throws {
        let bytes = try resource("pikachu-pre-179", type: "json", folder: "PrintReferences")
        let valid = try JSONDecoder().decode(CardCenteringPrintReference.self, from: bytes)
        XCTAssertTrue(valid.isValid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var patches = try XCTUnwrap(object["patches"] as? [[String: Any]])
        let index = try XCTUnwrap(patches.firstIndex { $0["colorAlternatives"] != nil })
        let alternatives = try XCTUnwrap(patches[index]["colorAlternatives"] as? [[String: Any]])
        patches[index]["colorAlternatives"] = [alternatives[0], alternatives[0]]
        object["patches"] = patches
        let invalid = try JSONDecoder().decode(CardCenteringPrintReference.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(invalid.isValid)
    }

    func testPrintedSeedConsensusRejectsDistinctSupportedEdges() {
        typealias Line = CardCenteringNativeLine
        let a = Line(start: .init(x: 0, y: 0), end: .init(x: 1000, y: 0))
        let near = Line(start: .init(x: 0, y: 3), end: .init(x: 1000, y: 3))
        let far = Line(start: .init(x: 0, y: 5), end: .init(x: 1000, y: 5))
        let crossing = Line(start: .init(x: 0, y: -10), end: .init(x: 1000, y: 10))
        XCTAssertTrue(CardCenteringPrintMatcher.supportedLinesAgree([a,near]))
        XCTAssertFalse(CardCenteringPrintMatcher.supportedLinesAgree([a,far]))
        XCTAssertFalse(CardCenteringPrintMatcher.supportedLinesAgree([a,crossing]))
        XCTAssertFalse(CardCenteringPrintMatcher.supportedLinesAgree([]))
    }

    func testPrismaticPrintUsesColorIdentityAndNativePhotoEdges() throws {
        let design = try reference("pikachu-pre-179")
        XCTAssertTrue(design.isValid)
        let bytes = try resource("Document_2026-06-06_151610", type: "png", folder: "HEIC")
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let result = try CardCenteringPrintMatcher.$diagnosticSink.withValue({ print($0) }) {
            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                try CardCenteringAnalyzer.analyze(bytes)
            }
        }
        let m = result.measurement
        XCTAssertEqual(m.referenceDefinition, .matchedPrintedBorder)
        XCTAssertEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
        XCTAssertFalse(m.canReportRatios)
        let left = 100 * m.leftBorderDistance / (m.leftBorderDistance + m.rightBorderDistance)
        let top = 100 * m.topBorderDistance / (m.topBorderDistance + m.bottomBorderDistance)
        print("PRISMATIC_PIKACHU left=\(left) top=\(top)")
        XCTAssertEqual(left, 44.16108, accuracy: 2)
        XCTAssertEqual(top, 49.00374, accuracy: 2)
        let mapping = try XCTUnwrap(result.coordinateMapping)
        let q = mapping.nativeQuad(fromWorking: try XCTUnwrap(m.geometryInnerQuad))
        // Source-crop observations frozen before the native hybrid experiment;
        // decorative overlaps are recorded separately, not treated as panel edges.
        let observations: [(CardCenteringSide, [(Double, Double)])] = [
            (.left, [(437.165,2196.419),(433.934,2793.766),(431.140,3499.728)]),
            (.right, [(3323.886,1884.223),(3324.648,2753.984),(3319.008,3406.286)]),
            (.top, [(1195.748,489.783),(1654.784,492.281),(2113.814,495.822),(2572.861,495.673)]),
            (.bottom, [(1173.845,4557.384),(1634.941,4560.403),(2057.610,4563.546),(2557.138,4565.549)]),
        ]
        for (side, points) in observations {
            let (a,b) = q.segment(side)
            let dx = b.x-a.x, dy = b.y-a.y
            let worst = points.map { abs(dx*($0.1-a.y)-dy*($0.0-a.x))/hypot(dx,dy) }.max()!
            print("PRISMATIC_EDGE \(side) worst=\(worst)")
            XCTAssertLessThanOrEqual(worst, 4, side.rawValue)
        }
        let other = try resource("Document_2026-06-06_152530", type: "png", folder: "HEIC")
        let otherOrdinary = try CardCenteringAnalyzer.analyze(other).measurement
        let otherAssisted = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
            try CardCenteringAnalyzer.analyze(other).measurement
        }
        XCTAssertEqual(otherAssisted, otherOrdinary)
    }

    func testPrintedFrameDevelopmentCorpusPreservesUnrelatedProposals() throws {
        let design = try reference("gengar-151-094")
        try verifyDevelopmentLibrary([design], expected: ["Document_2026-06-06_150759.png": design])
    }

    func testReferenceLibraryDevelopmentCorpusSelectsBothDesigns() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        try verifyDevelopmentLibrary([gengar, town], expected: [
            "Document_2026-06-06_150759.png": gengar, "IMG_0780.HEIC": town,
        ])
    }

    private func verifyDevelopmentLibrary(_ designs: [CardCenteringPrintReference],
                                          expected: [String: CardCenteringPrintReference],
                                          selectiveRepairs: Set<String> = []) throws {
        struct Manifest: Decodable {
            struct Entry: Decodable { let file, split, sha256: String }
            let entries: [Entry]
        }
        struct Record: Encodable {
            let file: String
            let matched: Bool
            let outer: CardCenteringQuad
            let inner: CardCenteringQuad?
            let elapsedSeconds: Double
            var observed: CardCenteringPrintMatcher.ObservedMeasurement? = nil
            var selectiveRepair: Bool? = nil
        }
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: resource("corpus-manifest", type: "json", folder: "Supplementary"))
        let entries = manifest.entries.filter { $0.split.hasPrefix("DEV") }
        XCTAssertEqual(entries.count, 34)
        var records: [Record] = []
        for entry in entries {
            try autoreleasepool {
                let url = URL(fileURLWithPath: entry.file)
                let bytes = try resource(url.deletingPathExtension().lastPathComponent, type: url.pathExtension, folder: "HEIC")
                XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), entry.sha256)
                let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
                let started = CFAbsoluteTimeGetCurrent()
                let result = try CardCenteringAnalyzer.$activePrintReferences.withValue(designs) {
                    try CardCenteringAnalyzer.$activeSelectiveBorderRepair.withValue(!selectiveRepairs.isEmpty) {
                        try CardCenteringAnalyzer.analyze(bytes)
                    }
                }
                let seconds = CFAbsoluteTimeGetCurrent() - started
                let m = result.measurement
                let matched = m.reviewedDesign != nil
                if let design = expected[entry.file] {
                    XCTAssertTrue(matched)
                    if design.isPrintedBorder && !m.hasObservedPaths {
                        XCTAssertEqual(m.geometryOuterQuad, ordinary.geometryOuterQuad)
                    } else if !m.hasObservedPaths {
                        let unrefined = try CardCenteringPrintMatcher.$physicalRefinementEnabled.withValue(false) {
                            try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                                try CardCenteringAnalyzer.analyze(bytes).measurement
                            }
                        }
                        XCTAssertEqual(m.geometryInnerQuad, unrefined.geometryInnerQuad, entry.file)
                    }
                    let single = try CardCenteringAnalyzer.$activePrintReference.withValue(design) {
                        try CardCenteringAnalyzer.analyze(bytes).measurement
                    }
                    XCTAssertEqual(m, single, entry.file)
                } else if selectiveRepairs.contains(entry.file) {
                    XCTAssertTrue(m.hasObservedPaths,entry.file)
                    XCTAssertEqual(m.referenceDefinition,.magicClassicBack)
                    XCTAssertFalse(matched)
                    let single = try CardCenteringAnalyzer.$activeSelectiveBorderRepair.withValue(true) {
                        try CardCenteringAnalyzer.analyze(bytes).measurement
                    }
                    XCTAssertEqual(m,single,entry.file)
                } else {
                    XCTAssertEqual(m, ordinary, entry.file)
                    XCTAssertFalse(matched, entry.file)
                }
                XCTAssertFalse(m.canReportRatios, entry.file)
                let mapping = try XCTUnwrap(result.coordinateMapping)
                records.append(.init(file: entry.file, matched: matched,
                    outer: mapping.nativeQuad(fromWorking: m.geometryOuterQuad),
                    inner: m.geometryInnerQuad.map(mapping.nativeQuad(fromWorking:)), elapsedSeconds: seconds,
                    observed:m.observedPrintMeasurement,
                    selectiveRepair:m.hasObservedPaths && m.referenceDefinition == .magicClassicBack ? true : nil))
                print("PRINTED_CORPUS file=\(entry.file) matched=\(matched) seconds=\(seconds)")
            }
        }
        XCTAssertEqual(records.count, entries.count)
        XCTAssertEqual(records.filter(\.matched).count, expected.count)
        XCTAssertEqual(records.filter { $0.selectiveRepair == true }.count,selectiveRepairs.count)
        let attachment = XCTAttachment(data: try JSONEncoder().encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "printed-frame-development-corpus"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testReferenceLibraryOrderDuplicatesAndAmbiguity() throws {
        let gengar = try reference("gengar-151-094"), town = try reference()
        let bytes = try resource("Document_2026-06-06_150759", type: "png", folder: "HEIC")
        func analyze(_ designs: [CardCenteringPrintReference]) throws -> CardCenteringMeasurement {
            try CardCenteringAnalyzer.$activePrintReferences.withValue(designs) {
                try CardCenteringAnalyzer.analyze(bytes).measurement
            }
        }
        let ordinary = try CardCenteringAnalyzer.analyze(bytes).measurement
        let selected = try analyze([gengar])
        XCTAssertEqual(selected.referenceDefinition, .matchedPrintedBorder)
        XCTAssertEqual(try analyze([town,gengar]), selected)
        XCTAssertEqual(try analyze([gengar,town]), selected)
        XCTAssertEqual(try analyze([gengar,gengar]), selected)
        var conflicting = try XCTUnwrap(JSONSerialization.jsonObject(with:
            resource("gengar-151-094", type: "json", folder: "PrintReferences")) as? [String: Any])
        conflicting["label"] = "Conflicting printed-frame interpretation"
        conflicting["left"] = gengar.left + 0.005
        let alternate = try JSONDecoder().decode(CardCenteringPrintReference.self,
            from: JSONSerialization.data(withJSONObject: conflicting))
        XCTAssertTrue(alternate.isValid)
        XCTAssertEqual(try analyze([gengar,alternate]), ordinary)
        XCTAssertEqual(try analyze([alternate,gengar]), ordinary)
        XCTAssertEqual(try analyze([]), ordinary)
    }

    func testReferenceLibraryViewModelSwitchesDesignsAndHandlesSupersededCapture() async throws {
        let designs = try [reference("gengar-151-094"), reference()]
        let model = CardCenteringViewModel(printReferences: designs)
        model.loadCapturedPhoto(try resource("IMG_0780", type: "HEIC", folder: "HEIC"))
        let town = try await settle(model)
        XCTAssertEqual(town.referenceDefinition, .matchedArtwork)
        model.loadCapturedPhoto(try resource("Document_2026-06-06_150759", type: "png", folder: "HEIC"))
        let gengar = try await settle(model)
        XCTAssertEqual(gengar.referenceDefinition, .matchedPrintedBorder)
        XCTAssertFalse(gengar.canReportRatios)
        let unrelated = try resource("IMG_0797", type: "HEIC", folder: "HEIC")
        model.loadCapturedPhoto(try resource("IMG_0780", type: "HEIC", folder: "HEIC"))
        model.loadCapturedPhoto(unrelated)
        let latest = try await settle(model)
        XCTAssertEqual(latest, try CardCenteringAnalyzer.analyze(unrelated).measurement)
        XCTAssertFalse(latest.canReportRatios)
    }

    func testUnrelatedPhotosFallBackAndLatencyStaysWithinBudget() async throws {
        let model = CardCenteringViewModel(printReference: try reference())
        var durations: [Double] = []
        for tag in ["0347", "0348", "0349", "0350", "0351", "0352", "0780", "0781", "0782", "0783"] {
            let bytes = try resource("IMG_" + tag, type: "HEIC", folder: "HEIC")
            let start = CFAbsoluteTimeGetCurrent()
            model.loadCapturedPhoto(bytes)
            let measured = try await settle(model)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("PRINT_TIMING \(tag) seconds=\(elapsed)")
            durations.append(elapsed)
            if tag == "0780" {
                XCTAssertEqual(measured.referenceDefinition, .matchedArtwork)
                continue
            }
            var diagnostics = CardCenteringAnalyzer.Diagnostics()
            // Match ordinary analysis, without the diagnostic-only front-bottom experiment.
            diagnostics.frontBottomCandidateGenerationEnabled = false
            diagnostics.analysisDiagnosticSink = { diagnostic in
                print("PRINT_BASE_STAGES \(tag) \(diagnostic.stageTimings)")
            }
            XCTAssertEqual(measured, try diagnostics.analyze(bytes).measurement, tag)
            XCTAssertFalse(measured.canReportRatios)
            XCTAssertNil(measured.reviewedDesign)
        }
        XCTAssertLessThanOrEqual(durations.sorted()[5], 0.8)
        XCTAssertLessThanOrEqual(durations.max()!, 1.5)
    }

    func testMissingReferenceAndSupersededCaptureUseOrdinaryReview() async throws {
        let town = try resource("IMG_0780", type: "HEIC", folder: "HEIC")
        let back = try resource("IMG_0347", type: "HEIC", folder: "HEIC")
        let standalone = CardCenteringViewModel()
        standalone.loadCapturedPhoto(town)
        let ordinary = try await settle(standalone)
        XCTAssertEqual(ordinary, try CardCenteringAnalyzer.analyze(town).measurement)
        let assisted = CardCenteringViewModel(printReference: try reference())
        assisted.loadCapturedPhoto(town)
        assisted.loadCapturedPhoto(back)
        let latest = try await settle(assisted)
        XCTAssertEqual(latest, try CardCenteringAnalyzer.analyze(back).measurement)
    }
}

/// Bounded experiment: supplied layout regions, unchanged pixel fitter. Review
/// bands below check boundary identity only; they are not precision annotations.
final class CenteringBoundaryResolverExperimentTests: XCTestCase {
    private struct Case {
        let name: String
        let plan: CardCenteringAnalyzer.ReferenceWindowPlan
        let midpointBands: [ClosedRange<Double>] // left x, top y, right x, bottom y
    }
    private struct Result: Encodable {
        let fixture: String
        let probe: CardCenteringAnalyzer.ReferenceWindowProbe
        let baselineInner: CardCenteringQuad?
        let midpointBands: [[Double]]
        let measuredMidpoints: [Double]?
        let identityChecks: [Bool]
    }
    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name,
            withExtension: "HEIC", subdirectory: "TradingCards/HEIC")))
    }
    private func midpoints(_ q: CardCenteringQuad) -> [Double] {
        [(q.topLeft.x + q.bottomLeft.x) / 2, (q.topLeft.y + q.topRight.y) / 2,
         (q.topRight.x + q.bottomRight.x) / 2, (q.bottomLeft.y + q.bottomRight.y) / 2]
    }
    private func attach<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let item = XCTAttachment(data: try encoder.encode(value), uniformTypeIdentifier: "public.json")
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func overlay(_ analysis: CardCenteringAnalysis,
                         probe: CardCenteringAnalyzer.ReferenceWindowProbe, name: String) throws {
        let mapping = try XCTUnwrap(analysis.coordinateMapping)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: analysis.image.size, format: format).image { context in
            analysis.image.draw(at: .zero)
            func draw(_ q: CardCenteringQuad, color: UIColor, dashed: Bool) {
                let cg = context.cgContext
                cg.setStrokeColor(color.cgColor); cg.setLineWidth(2)
                cg.setLineDash(phase: 0, lengths: dashed ? [6, 4] : [])
                cg.beginPath(); cg.move(to: CGPoint(x: q.points[0].x, y: q.points[0].y))
                for p in q.points.dropFirst() { cg.addLine(to: CGPoint(x: p.x, y: p.y)) }
                cg.closePath(); cg.strokePath()
            }
            if let q = analysis.measurement.geometryInnerQuad { draw(q, color: .yellow, dashed: true) }
            if let q = probe.innerNative { draw(mapping.workingQuad(fromNative: q), color: .cyan, dashed: false) }
        }
        let item = XCTAttachment(image: image)
        item.name = "\(name)-layout-cyan-baseline-yellow"; item.lifetime = .keepAlways; add(item)
    }

    func testSuppliedLayoutRecoversReviewedBoundaryRegions() throws {
        // Fixed before running this experiment, from original-image review.
        // The artwork target is the image rectangle, excluding both gold
        // banners. No historical ratio or exact corner is supplied to the probe.
        let cases: [Case] = [
            .init(name: "IMG_0348", plan: .perimeterPrintedFrame,
                  midpointBands: [320...350, 200...240, 2745...2775, 3690...3730]),
            .init(name: "IMG_0351", plan: .perimeterPrintedFrame,
                  midpointBands: [290...330, 245...295, 2655...2720, 3680...3750]),
            .init(name: "IMG_0780", plan: .landscapeArtworkWindow,
                  midpointBands: [335...375, 535...575, 2600...2670, 2190...2250])
        ]
        var results: [Result] = []
        for test in cases {
            try autoreleasepool {
                let bytes = try data(test.name)
                let baseline = try CardCenteringAnalyzer.analyze(bytes)
                let mapping = try XCTUnwrap(baseline.coordinateMapping)
                let probe = try CardCenteringAnalyzer.probeReferenceWindow(bytes, baseline: baseline, plan: test.plan)
                let measured = probe.innerNative.map(midpoints)
                let checks = test.midpointBands.enumerated().map { index, band in
                    measured.map { band.contains($0[index]) } ?? false
                }
                results.append(.init(fixture: test.name, probe: probe,
                    baselineInner: baseline.measurement.geometryInnerQuad.map(mapping.nativeQuad(fromWorking:)),
                    midpointBands: test.midpointBands.map { [$0.lowerBound, $0.upperBound] },
                    measuredMidpoints: measured, identityChecks: checks))
                try overlay(baseline, probe: probe, name: test.name)
                XCTAssertFalse(baseline.measurement.canReportRatios)
                let after = try CardCenteringAnalyzer.analyze(bytes)
                XCTAssertEqual(after.measurement, baseline.measurement, "Probe must not leak layout options")
                print("CENTERING_LAYOUT fixture=\(test.name) midpoints=\(String(describing: measured)) identityChecks=\(checks) failures=\(probe.failures)")
            }
        }
        try attach(results, name: "supplied-layout-control")
        // Deliberately remains an accuracy gate. A failure stops promotion; it
        // must not be converted into an assertion that merely expects a result.
        for result in results {
            XCTAssertTrue(result.identityChecks.allSatisfy { $0 },
                          "\(result.fixture): supplied layout did not recover all reviewed boundaries; stop before automatic routing")
        }
    }

    func testKnownArtworkWindowsAreMeasuredFromPixelsAcrossPositions() throws {
        // Two different positions inside the same broad plan prevent a canned
        // plan rectangle from satisfying this control.
        for rect in [CGRect(x: 78, y: 120, width: 448, height: 330),
                     CGRect(x: 84, y: 140, width: 430, height: 320)] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 840), format: format).image { c in
                UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 840))
                UIColor.black.setFill(); c.fill(CGRect(x: 20, y: 20, width: 560, height: 800))
                UIColor.cyan.setFill(); c.fill(rect)
            }
            let bytes = try XCTUnwrap(image.pngData())
            let baseline = try CardCenteringAnalyzer.analyze(bytes)
            let probe = try CardCenteringAnalyzer.probeReferenceWindow(bytes, baseline: baseline, plan: .landscapeArtworkWindow)
            let q = try XCTUnwrap(probe.innerNative, "\(probe.failures)")
            for (actual, expected) in zip(midpoints(q), [rect.minX, rect.minY, rect.maxX, rect.maxY]) {
                XCTAssertEqual(actual, Double(expected), accuracy: 2)
            }
            XCTAssertFalse(baseline.measurement.canReportRatios)
            XCTAssertEqual(probe.profiles.count, 4)
            XCTAssertEqual(probe.profiles.first { $0.side == "bottom" }?.normalizedDepthEnd, 0.506)
        }
    }

    func testProbeRejectsGeometryFromAnotherCapture() throws {
        let baseline = try CardCenteringAnalyzer.analyze(data("IMG_0348"))
        XCTAssertThrowsError(try CardCenteringAnalyzer.probeReferenceWindow(data("IMG_0780"),
            baseline: baseline, plan: .landscapeArtworkWindow))
    }
}

/// Development evaluator only. Nothing in this file is linked into the app.
/// Fits describe transitions, not physical identity or calibrated uncertainty.
private enum NativeResearch {
    enum Signal: String, Codable, CaseIterable {
        case weightedBrightness, arithmeticMean, chroma, redMinusGreen, blueMinusGreen
        func value(_ rgb: (Double, Double, Double)) -> Double {
            switch self {
            case .weightedBrightness: return 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
            case .arithmeticMean: return (rgb.0 + rgb.1 + rgb.2) / 3
            case .chroma: return max(rgb.0, rgb.1, rgb.2) - min(rgb.0, rgb.1, rgb.2)
            case .redMinusGreen: return rgb.0 - rgb.1
            case .blueMinusGreen: return rgb.2 - rgb.1
            }
        }
    }
    struct Configuration: Codable, Equatable {
        let signal: Signal
        let sigma: Double
        let threshold: Double?
        var id: String { "\(signal.rawValue)_sigma\(sigma)_\(threshold.map { "crossing\($0)" } ?? "signedGradient")" }
        // Encoded sRGB values, not linear-light or perceptual luminance.
        private(set) var units = "encoded_sRGB_8bit; gradient_per_native_pixel; sigma_native_pixels"
        static let ablations: [Self] = Signal.allCases.flatMap { signal in
            [0.6, 1, 1.5, 2, 3].map { Self(signal: signal, sigma: $0, threshold: nil) }
        } + [100.0, 125, 150, 175, 200, 225].map {
            Self(signal: .arithmeticMean, sigma: 0, threshold: $0)
        } + [10.0, 15, 20, 25, 30].map {
            Self(signal: .chroma, sigma: 1, threshold: $0)
        }
    }
    struct Seed: Codable, Equatable {
        let id: String
        let frame: CardCenteringPrecisionFrame
        let side: CardCenteringPrecisionSide
        let line: CardCenteringNativeLine
        let role: CardCenteringBoundaryRole
        let competingRoles: [CardCenteringBoundaryRole]
    }
    struct Observation: Codable, Equatable {
        let progress: Double
        let offset: Double
        let signedStrength: Double
    }
    struct Fit: Codable, Equatable {
        let line: CardCenteringNativeLine
        let observations: [Observation]
        let rms: Double
        let coverage: Double
        let leaveOneBandOutMaximumShift: Double?
        let heldOutBandRMS: [Double]
        let rejectionReasons: [String]
        var eligible: Bool { rejectionReasons.isEmpty }
    }
    struct Trial: Codable, Equatable {
        let seed: Seed
        let configuration: Configuration
        let fits: [Fit]
        let missingSamplePositions: [Double]
        let unsupportedSamplePositions: [Double]
        let cropPixelCount: Int
        let disposition: String
    }
    struct Memory: Codable, Equatable {
        let residentBytes: UInt64
        /// OS process-lifetime high-water mark. Its increase is scoped to a
        /// stage, but allocations from unrelated threads may contribute.
        let processPeakResidentBytes: UInt64
        static func read() -> Self? {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            guard status == KERN_SUCCESS else { return nil }
            return Self(residentBytes: info.resident_size, processPeakResidentBytes: info.resident_size_max)
        }
    }
    struct Result: Codable, Equatable {
        let inputSHA256: String
        let inputRevision: Int
        let geometryRevision: Int
        let trials: [Trial]
        let seconds: Double
        let decodeSeconds: Double
        let firstCropSeconds: Double?
        let memoryBeforeDecode: Memory?
        let memoryAfterDecode: Memory?
        let memoryAfterFirstCrop: Memory?
        let memoryAtEnd: Memory?
        private(set) var policy = "research_only; no_identity_inference; no_automatic_reporting"
    }

    /// One request and one completed result at a time; changes cancel old work.
    /// Keys include exact bytes, geometry, settings and both caller revisions.
    actor Session {
        struct Key: Equatable {
            let data: Data
            let seeds: [Seed]
            let configurations: [Configuration]
            let inputRevision: Int
            let geometryRevision: Int
        }
        private var current: Key?
        private var job: Task<Result, Error>?
        private var completed: Result?
        private var generation = 0
        private(set) var executionCount = 0

        func evaluate(_ key: Key) async throws -> Result {
            try Task.checkCancellation()
            if current == key, let completed { return completed }
            if current != key {
                job?.cancel()
                completed = nil
                current = key
                generation += 1
                executionCount += 1
                job = Task.detached(priority: .utility) { try run(key) }
            }
            guard let task = job else { throw CancellationError() }
            let revision = generation
            let result: Result
            do {
                result = try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }
            } catch {
                if revision == generation { current = nil; job = nil; completed = nil }
                throw error
            }
            try Task.checkCancellation()
            guard current == key, generation == revision else { throw CancellationError() }
            completed = result
            job = nil
            return result
        }
        func invalidate() {
            generation += 1
            job?.cancel(); job = nil; completed = nil; current = nil
        }
    }

    static func seeds(_ measurement: CardCenteringMeasurement) -> [Seed] {
        let size = CardCenteringSize(width: Double(measurement.imageWidth), height: Double(measurement.imageHeight))
        let mapping = measurement.coordinateMapping ?? .init(orientedSourceSize: size, workingSize: size)
        return CardCenteringPrecisionFrame.allCases.flatMap { frame in
            CardCenteringPrecisionSide.allCases.flatMap { side -> [Seed] in
                guard let quad = frame == .outer ? measurement.outerQuad : measurement.innerQuad else { return [] }
                let points = mapping.nativeQuad(fromWorking: quad).points
                let selected = Seed(id: "selected_\(frame.rawValue)_\(side.rawValue)", frame: frame, side: side,
                    line: .init(start: points[side.index], end: points[(side.index + 1) % 4]),
                    role: frame == .outer ? .physicalCut : measurement.referenceDefinition.role,
                    competingRoles: frame == .outer ? [.shadow, .sleeveOrSlab] : [.printedBorder, .artwork, .unknown])
                var result = [selected]
                // A fixed work cap, independent of any favorable resulting ratio.
                for candidate in measurement.reviewCandidates(frame: frame, side: side) {
                    if !result.contains(where: { $0.line.coincides(with: candidate.nativeLine) }) {
                        result.append(.init(id: candidate.id, frame: frame, side: side, line: candidate.nativeLine,
                            role: candidate.proposedRole, competingRoles: candidate.competingRoles))
                    }
                    if result.count == 7 { break }
                }
                return result
            }
        }
    }

    static func run(_ key: Session.Key) throws -> Result {
        try Task.checkCancellation()
        let start = CFAbsoluteTimeGetCurrent(), before = Memory.read()
        guard let source = UIImage(data: key.data) else { throw CardCenteringAnalyzerError.unreadableImage }
        let decoded = CFAbsoluteTimeGetCurrent(), afterDecode = Memory.read()
        var trials: [Trial] = [], firstCropSeconds: Double?, afterCrop: Memory?
        for seed in key.seeds.prefix(56) {
            try Task.checkCancellation()
            try autoreleasepool {
                let p = seed.line.start, q = seed.line.end
                let length = hypot(q.x - p.x, q.y - p.y)
                guard length > 24, seed.line.isValid else {
                    trials += key.configurations.map { .init(seed: seed, configuration: $0, fits: [],
                        missingSamplePositions: positions, unsupportedSamplePositions: positions,
                        cropPixelCount: 0, disposition: "invalid_or_short_seed") }
                    return
                }
                let tx = (q.x - p.x) / length, ty = (q.y - p.y) / length, nx = -ty, ny = tx
                func point(_ t: Double, _ offset: Double, _ tangent: Double = 0) -> CardCenteringPoint {
                    .init(x: p.x + (q.x - p.x) * t + nx * offset + tx * tangent,
                          y: p.y + (q.y - p.y) * t + ny * offset + ty * tangent)
                }
                let a = point(0.12, 0), b = point(0.88, 0)
                let cropStart = CFAbsoluteTimeGetCurrent()
                let crop = CardCenteringNativeRefiner.crop(source: source,
                    orientedRect: CGRect(x: min(a.x, b.x) - 24, y: min(a.y, b.y) - 24,
                        width: abs(a.x - b.x) + 48, height: abs(a.y - b.y) + 48),
                    rgbColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                if firstCropSeconds == nil { firstCropSeconds = CFAbsoluteTimeGetCurrent() - cropStart; afterCrop = Memory.read() }
                guard let crop else {
                    trials += key.configurations.map { .init(seed: seed, configuration: $0, fits: [],
                        missingSamplePositions: positions, unsupportedSamplePositions: positions,
                        cropPixelCount: 0, disposition: "unavailable_bounded_crop") }
                    return
                }
                // Reuse the bounded native samples across all correlated signals.
                // 25 positions × 81 offsets × 3 tangent samples, never a full raster.
                var profiles: [Signal: [[Double]?]] = [:]
                for signal in Signal.allCases {
                    profiles[signal] = positions.map { t in
                        var values: [Double] = []
                        for offset in offsets {
                            let colors = [-2.0, 0, 2].compactMap { crop.color(at: point(t, offset, $0)) }
                            guard colors.count == 3 else { return nil }
                            values.append(median(colors.map(signal.value)))
                        }
                        return values
                    }
                }
                for configuration in key.configurations {
                    try Task.checkCancellation()
                    let raw = profiles[configuration.signal]!
                    let buckets = zip(positions, raw).map { t, values in
                        values.map { observations($0, at: t, configuration: configuration) } ?? []
                    }
                    let fits = fitTracks(buckets, seed: seed)
                    let eligible = fits.filter(\.eligible)
                    trials.append(.init(seed: seed, configuration: configuration, fits: fits,
                        missingSamplePositions: zip(positions, raw).compactMap { $0.1 == nil ? $0.0 : nil },
                        unsupportedSamplePositions: zip(positions, buckets).compactMap { $0.1.isEmpty ? $0.0 : nil },
                        cropPixelCount: crop.width * crop.height,
                        disposition: eligible.count > 1 ? "competing_transitions" : eligible.isEmpty
                            ? "unsupported" : "one_local_transition_identity_unverified"))
                }
            }
        }
        try Task.checkCancellation()
        return .init(inputSHA256: SHA256.hash(data: key.data).map { String(format: "%02x", $0) }.joined(),
            inputRevision: key.inputRevision, geometryRevision: key.geometryRevision, trials: trials,
            seconds: CFAbsoluteTimeGetCurrent() - start, decodeSeconds: decoded - start,
            firstCropSeconds: firstCropSeconds, memoryBeforeDecode: before, memoryAfterDecode: afterDecode,
            memoryAfterFirstCrop: afterCrop, memoryAtEnd: Memory.read())
    }

    static let positions = (0..<25).map { 0.12 + 0.76 * Double($0) / 24 }
    static let offsets = (0...80).map { -20.0 + Double($0) * 0.5 }
    static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    static func smooth(_ values: [Double], sigma: Double) -> [Double] {
        guard sigma > 0 else { return values }
        let radius = Int(ceil(3 * sigma / 0.5))
        let kernel = (-radius...radius).map { exp(-0.5 * pow(Double($0) * 0.5 / sigma, 2)) }
        let total = kernel.reduce(0, +)
        return values.indices.map { i in
            (-radius...radius).reduce(0.0) { $0 + values[min(values.count - 1, max(0, i + $1))] * kernel[$1 + radius] } / total
        }
    }
    static func observations(_ values: [Double], at t: Double, configuration: Configuration) -> [Observation] {
        let smoothed = smooth(values, sigma: configuration.sigma)
        if let threshold = configuration.threshold {
            return (1..<smoothed.count).compactMap { i in
                let a = smoothed[i - 1], b = smoothed[i]
                guard (a < threshold && b >= threshold) || (a > threshold && b <= threshold), a != b else { return nil }
                let offset = offsets[i - 1] + 0.5 * (threshold - a) / (b - a)
                guard abs(offset) < 9 else { return nil }
                return Observation(progress: t, offset: offset, signedStrength: (b - a) / 0.5)
            }
        }
        let gradient = values.indices.map { i -> Double in
            guard i > 0, i < values.count - 1 else { return 0 }
            return smoothed[i + 1] - smoothed[i - 1] // denominator is 1 native pixel
        }
        let scores = gradient.map(abs), baseline = median(scores), mad = median(scores.map { abs($0 - baseline) })
        return (2..<(scores.count - 2)).filter {
            abs(offsets[$0]) < 9 && scores[$0] >= scores[$0 - 1] && scores[$0] > scores[$0 + 1]
                && scores[$0] >= max(3, baseline + 1.5 * mad)
        }.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1] }.prefix(4).map { i in
            let denominator = scores[i - 1] - 2 * scores[i] + scores[i + 1]
            let fraction = abs(denominator) > 1e-9
                ? max(-0.5, min(0.5, 0.5 * (scores[i - 1] - scores[i + 1]) / denominator)) : 0
            return .init(progress: t, offset: offsets[i] + fraction * 0.5, signedStrength: gradient[i])
        }
    }
    static func regression(_ points: [Observation]) -> (intercept: Double, slope: Double)? {
        guard points.count >= 5 else { return nil }
        let mt = points.map(\.progress).reduce(0, +) / Double(points.count)
        let mo = points.map(\.offset).reduce(0, +) / Double(points.count)
        let variance = points.reduce(0) { $0 + pow($1.progress - mt, 2) }
        guard variance > 1e-9 else { return nil }
        let slope = points.reduce(0) { $0 + ($1.progress - mt) * ($1.offset - mo) } / variance
        return (mo - slope * mt, slope)
    }
    static func fitTracks(_ buckets: [[Observation]], seed: Seed) -> [Fit] {
        let p = seed.line.start, q = seed.line.end, length = hypot(q.x - p.x, q.y - p.y)
        let nx = -(q.y - p.y) / length, ny = (q.x - p.x) / length
        var fits: [(Double, Double, Fit)] = []
        for ia in stride(from: 0, to: 25, by: 6) {
            if Task.isCancelled { return [] }
            for ib in stride(from: ia + 12, to: 25, by: 6) {
                for a in buckets[ia] { for b in buckets[ib] {
                    var slope = (b.offset - a.offset) / (b.progress - a.progress), intercept = a.offset - slope * a.progress
                    guard max(abs(intercept + slope * 0.12), abs(intercept + slope * 0.88)) <= 10 else { continue }
                    var points: [Observation] = []
                    for _ in 0..<3 {
                        points = buckets.compactMap { bucket in
                            let closest = bucket.min { abs($0.offset - intercept - slope * $0.progress) < abs($1.offset - intercept - slope * $1.progress) }
                            return closest.flatMap { abs($0.offset - intercept - slope * $0.progress) <= 1.5 ? $0 : nil }
                        }
                        guard let fit = regression(points) else { break }
                        intercept = fit.intercept; slope = fit.slope
                    }
                    guard let first = points.first, let last = points.last, points.count >= 5 else { continue }
                    let rms = sqrt(points.reduce(0) { $0 + pow($1.offset - intercept - slope * $1.progress, 2) } / Double(points.count))
                    let coverage = last.progress - first.progress
                    func band(_ point: Observation) -> Int { min(4, Int((point.progress - 0.12) / 0.76 * 5)) }
                    let bands = Set(points.map(band))
                    var shifts: [Double] = [], heldOut: [Double] = []
                    for omitted in bands.sorted() {
                        let retained = points.filter { band($0) != omitted }, excluded = points.filter { band($0) == omitted }
                        if let fit = regression(retained) {
                            shifts.append([0.12, 0.88].map { abs(fit.intercept - intercept + (fit.slope - slope) * $0) }.max()!)
                            heldOut.append(sqrt(excluded.reduce(0) { $0 + pow($1.offset - fit.intercept - fit.slope * $1.progress, 2) } / Double(excluded.count)))
                        }
                    }
                    var reasons: [String] = []
                    if points.count < 15 { reasons.append("sample_count_below_15") }
                    if coverage < 0.56 { reasons.append("coverage_below_0.56") }
                    if bands.count < 4 { reasons.append("fewer_than_4_spatial_bands") }
                    if rms > 1.1 { reasons.append("residual_above_1.1_native_pixels") }
                    if shifts.count != bands.count || shifts.max() ?? .infinity > 1.1 { reasons.append("unstable_leave_one_band_out") }
                    if abs(slope / length) > tan(2 * .pi / 180) { reasons.append("slope_change_above_2_degrees") }
                    if max(abs(intercept + slope * 0.12), abs(intercept + slope * 0.88)) > 8 { reasons.append("acceptance_band_exceeded") }
                    let line = CardCenteringNativeLine(start: .init(x: p.x + nx * intercept, y: p.y + ny * intercept),
                        end: .init(x: q.x + nx * (intercept + slope), y: q.y + ny * (intercept + slope)))
                    let fit = Fit(line: line, observations: points, rms: rms, coverage: coverage,
                        leaveOneBandOutMaximumShift: shifts.max(), heldOutBandRMS: heldOut, rejectionReasons: reasons)
                    func preferred(_ a: Fit, _ b: Fit) -> Bool {
                        if a.eligible != b.eligible { return a.eligible }
                        if a.observations.count != b.observations.count { return a.observations.count > b.observations.count }
                        return a.rms < b.rms
                    }
                    if let duplicate = fits.firstIndex(where: {
                        max(abs($0.0 - intercept + ($0.1 - slope) * 0.12), abs($0.0 - intercept + ($0.1 - slope) * 0.88)) < 1
                    }) {
                        if preferred(fit, fits[duplicate].2) { fits[duplicate] = (intercept, slope, fit) }
                    } else { fits.append((intercept, slope, fit)) }
                    fits.sort { preferred($0.2, $1.2) }
                    if fits.count > 6 { fits.removeLast(fits.count - 6) }
                } }
            }
        }
        return fits.map(\.2)
    }
}

final class CenteringNativeResearchTests: XCTestCase {
    private func synthetic(ambiguous: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 840), format: format).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 840))
            UIColor.black.setFill(); c.fill(CGRect(x: 20, y: 20, width: 560, height: 800))
            UIColor(white: 0.5, alpha: 1).setFill(); c.fill(CGRect(x: 50, y: 50, width: 500, height: 740))
            if ambiguous { UIColor.white.setFill(); c.fill(CGRect(x: 55, y: 50, width: 495, height: 740)) }
        }.pngData()!
    }
    private func key(_ data: Data, revision: Int = 0) -> NativeResearch.Session.Key {
        .init(data: data, seeds: [.init(id: "known_inner_left", frame: .inner, side: .left,
            line: .init(start: .init(x: 50, y: 790), end: .init(x: 50, y: 50)), role: .printedBorder,
            competingRoles: [.artwork])], configurations: [.init(signal: .arithmeticMean, sigma: 0.6, threshold: nil)],
            inputRevision: 0, geometryRevision: revision)
    }
    func testSignalsAndHistoricalParametersHaveExplicitEncodedUnits() {
        XCTAssertEqual(NativeResearch.Signal.arithmeticMean.value((255, 0, 0)), 85)
        XCTAssertEqual(NativeResearch.Signal.weightedBrightness.value((255, 0, 0)), 54.213, accuracy: 1e-10)
        XCTAssertEqual(NativeResearch.Signal.chroma.value((100, 40, 10)), 90)
        XCTAssertEqual(NativeResearch.Signal.redMinusGreen.value((10, 80, 30)), -70)
        XCTAssertEqual(Set(NativeResearch.Configuration.ablations.map(\.id)).count, 36)
        let gradient = NativeResearch.observations(NativeResearch.offsets.map { $0 < 0 ? 255 : 0 }, at: 0.5,
            configuration: .init(signal: .arithmeticMean, sigma: 1, threshold: nil))
        XCTAssertEqual(gradient.count, 1)
        XCTAssertLessThan(gradient[0].signedStrength, 0)
        XCTAssertEqual(gradient[0].offset, -0.25, accuracy: 0.01)
    }
    func testSupportedTransitionAndCompetingLinesRetainBandEvidence() throws {
        for ambiguous in [false, true] {
            let result = try NativeResearch.run(key(synthetic(ambiguous: ambiguous)))
            let trial = try XCTUnwrap(result.trials.first)
            let fits = trial.fits.filter(\.eligible)
            if ambiguous {
                XCTAssertGreaterThanOrEqual(fits.count, 2)
                XCTAssertTrue(fits.contains { abs($0.line.start.x - 50) < 0.5 && abs($0.line.end.x - 50) < 0.5 })
                XCTAssertTrue(fits.contains { abs($0.line.start.x - 55) < 0.5 && abs($0.line.end.x - 55) < 0.5 })
            } else { XCTAssertEqual(fits.count, 1) }
            XCTAssertEqual(trial.disposition, ambiguous ? "competing_transitions" : "one_local_transition_identity_unverified")
            XCTAssertTrue(fits.allSatisfy { $0.coverage >= 0.56 && $0.heldOutBandRMS.count >= 4 && ($0.leaveOneBandOutMaximumShift ?? 2) < 1.1 })
            XCTAssertLessThanOrEqual(trial.cropPixelCount, 2_000_000)
            XCTAssertNotNil(result.memoryBeforeDecode)
            XCTAssertNotNil(result.memoryAfterFirstCrop)
            XCTAssertGreaterThan(result.memoryAtEnd?.processPeakResidentBytes ?? 0, 0)
            XCTAssertEqual(try JSONDecoder().decode(NativeResearch.Result.self, from: JSONEncoder().encode(result)), result)
        }
    }
    func testOmittedBandAndOcclusionCannotCreateSupport() {
        let seed = key(synthetic()).seeds[0]
        let buckets = NativeResearch.positions.map { t -> [NativeResearch.Observation] in
            t < 0.65 ? [.init(progress: t, offset: 1, signedStrength: 30)] : []
        }
        let fits = NativeResearch.fitTracks(buckets, seed: seed)
        XCTAssertFalse(fits.isEmpty)
        XCTAssertTrue(fits.allSatisfy { !$0.eligible && $0.rejectionReasons.contains("coverage_below_0.56") })
    }
    func testSessionReusesExactRequestAndInvalidatesRevisionsAndCancellation() async throws {
        let session = NativeResearch.Session(), request = key(synthetic())
        let first = try await session.evaluate(request), second = try await session.evaluate(request)
        XCTAssertEqual(first, second)
        let count = await session.executionCount
        XCTAssertEqual(count, 1)
        let changed = try await session.evaluate(key(request.data, revision: 1))
        XCTAssertEqual(changed.geometryRevision, 1)
        let newCount = await session.executionCount
        XCTAssertEqual(newCount, 2)
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await session.evaluate(request); return false } catch { return error is CancellationError }
        }.value
        XCTAssertTrue(cancelled)
        await session.invalidate()
        _ = try await session.evaluate(request)
        let finalCount = await session.executionCount
        XCTAssertEqual(finalCount, 3)
    }

    func testSupersededResearchAndInvalidSeedsNeverReturnPartialSuccess() async throws {
        let session = NativeResearch.Session(), request = key(synthetic(ambiguous: true))
        let longRequest = NativeResearch.Session.Key(data: request.data,
            seeds: Array(repeating: request.seeds[0], count: 56), configurations: NativeResearch.Configuration.ablations,
            inputRevision: 0, geometryRevision: 0)
        let first = Task { try await session.evaluate(longRequest) }
        while await session.executionCount == 0 { await Task.yield() }
        let next = try await session.evaluate(key(request.data, revision: 1))
        XCTAssertEqual(next.geometryRevision, 1)
        do { _ = try await first.value; XCTFail("Superseded research must not publish") }
        catch { XCTAssertTrue(error is CancellationError) }
        let invalid = NativeResearch.Seed(id: "short", frame: .inner, side: .left,
            line: .init(start: .init(x: 10, y: 10), end: .init(x: 10, y: 11)), role: .unknown, competingRoles: [])
        let result = try NativeResearch.run(.init(data: request.data, seeds: [invalid], configurations: request.configurations,
            inputRevision: 1, geometryRevision: 0))
        XCTAssertEqual(result.trials.count, 1)
        XCTAssertEqual(result.trials[0].disposition, "invalid_or_short_seed")
        XCTAssertEqual(result.trials[0].unsupportedSamplePositions.count, 25)
    }

    /// All ten already-exposed development fixtures, including the unmeasurable
    /// front. No HOLDOUT-INTERIM bytes or outcomes enter this evaluation.
    func testDevelopmentAblationsRecordRecallSelectionAbstentionAndFullRatioError() throws {
        struct GroundTruth: Decodable {
            let cardOuterQuad: [[Double]]
            let innerQuad: [[Double]]?
            let face: String
            let encasement: String
            let ambiguousEdges: [String]
            let edgeBands: [String: Double]
        }
        struct SideMetric: Codable {
            let frame: String
            let side: String
            let annotationAmbiguous: Bool
            let annotationBandNativePixels: Double?
            let originalSeedMaximumLineError: Double
            let coarseCandidateRecallAtTwoNativePixels: Bool
            let refinedCandidateRecallAtTwoNativePixels: Bool
            let candidateCount: Int
            let eligibleCount: Int
            let selectedMaximumLineError: Double?
            let disposition: String
        }
        struct Metric: Codable {
            let fixture: String
            let face: String
            let encasement: String
            let configuration: NativeResearch.Configuration
            let sides: [SideMetric]
            let baselineLRAbsoluteErrorPP: Double?
            let baselineTBAbsoluteErrorPP: Double?
            let localFitLRAbsoluteErrorPP: Double?
            let localFitTBAbsoluteErrorPP: Double?
            let fittedQuadValid: Bool
        }
        let bundle = Bundle(for: Self.self)
        func quad(_ values: [[Double]]) -> CardCenteringQuad {
            let p = values.map { CardCenteringPoint(x: $0[0], y: $0[1]) }
            return .init(topLeft: p[0], topRight: p[1], bottomRight: p[2], bottomLeft: p[3])
        }
        func line(_ quad: CardCenteringQuad, side: CardCenteringPrecisionSide) -> CardCenteringNativeLine {
            .init(start: quad.points[side.index], end: quad.points[(side.index + 1) % 4])
        }
        func error(_ candidate: CardCenteringNativeLine, _ reference: CardCenteringNativeLine) -> Double {
            let dx = candidate.end.x - candidate.start.x, dy = candidate.end.y - candidate.start.y
            return [0.12, 0.88].map { t in
                let p = CardCenteringPoint(x: reference.start.x + (reference.end.x - reference.start.x) * t,
                    y: reference.start.y + (reference.end.y - reference.start.y) * t)
                return abs(dx * (p.y - candidate.start.y) - dy * (p.x - candidate.start.x)) / hypot(dx, dy)
            }.max()!
        }
        func ratios(_ value: CardCenteringMeasurement) -> (Double, Double)? {
            guard value.hasValidFrameGeometry,
                  let lr = CardCenteringRatioPair(firstDistance: value.leftBorderDistance, secondDistance: value.rightBorderDistance),
                  let tb = CardCenteringRatioPair(firstDistance: value.topBorderDistance, secondDistance: value.bottomBorderDistance) else { return nil }
            return (lr.firstPercentage, tb.firstPercentage)
        }
        let names = ["IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351", "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"]
        var allMetrics: [Metric] = []
        for name in names {
            try autoreleasepool {
                let data = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")))
                let recordData = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth")))
                let gt = try JSONDecoder().decode(GroundTruth.self, from: recordData)
                let analysis = try CardCenteringAnalyzer.analyze(data)
                let mapping = try XCTUnwrap(analysis.coordinateMapping)
                let width = Int(mapping.orientedSourceSize.width), height = Int(mapping.orientedSourceSize.height)
                let original = analysis.measurement
                let native = CardCenteringMeasurement(imageWidth: width, imageHeight: height,
                    outerQuad: mapping.nativeQuad(fromWorking: original.outerQuad),
                    innerQuad: original.innerQuad.map(mapping.nativeQuad(fromWorking:)), warnings: [])
                let reference = CardCenteringMeasurement(imageWidth: width, imageHeight: height,
                    outerQuad: quad(gt.cardOuterQuad), innerQuad: gt.innerQuad.map(quad), warnings: [])
                let expected = ratios(reference), baseline = ratios(native)
                let seeds = NativeResearch.seeds(original)
                let result = try NativeResearch.run(.init(data: data, seeds: seeds,
                    configurations: NativeResearch.Configuration.ablations, inputRevision: 0, geometryRevision: 0))
                let attachment = XCTAttachment(data: try JSONEncoder().encode(result), uniformTypeIdentifier: "public.json")
                attachment.name = "\(name)-native-research-v1"; attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertLessThanOrEqual(seeds.count, 56)
                XCTAssertTrue(result.trials.allSatisfy { $0.cropPixelCount <= 2_000_000 })
                XCTAssertFalse(original.canReportRatios)
                for configuration in NativeResearch.Configuration.ablations {
                    var sideMetrics: [SideMetric] = []
                    var proposed = native
                    for frame in CardCenteringPrecisionFrame.allCases {
                        guard let target = frame == .outer ? Optional(reference.outerQuad) : reference.innerQuad else { continue }
                        for side in CardCenteringPrecisionSide.allCases {
                            let gtLine = line(target, side: side)
                            let sideSeeds = seeds.filter { $0.frame == frame && $0.side == side }
                            guard let selected = sideSeeds.first else { continue }
                            let trials = result.trials.filter { $0.seed.frame == frame && $0.seed.side == side && $0.configuration == configuration }
                            let fits = trials.flatMap(\.fits)
                            var eligible: [NativeResearch.Fit] = []
                            for fit in fits.filter(\.eligible) {
                                if !eligible.contains(where: { max(error($0.line, fit.line), error(fit.line, $0.line)) < 1 }) { eligible.append(fit) }
                            }
                            // A unique local transition is still identity-unverified.
                            // Outer proposals never change on gradient evidence.
                            let chosen = frame == .inner && eligible.count == 1 ? eligible[0] : nil
                            var acceptedLine = chosen?.line
                            var jointRejection = false
                            if let chosen, let current = proposed.innerQuad {
                                let candidate = CardCenteringBoundaryCandidate(id: "research", frame: frame, side: side,
                                    nativeLine: chosen.line, source: "test_only", proposedRole: .printedBorder,
                                    competingRoles: [.artwork], signal: configuration.id, strength: nil, polarity: nil,
                                    coverage: chosen.coverage, fitResidualNativePixels: chosen.rms, sampleBands: [], exclusions: [],
                                    selectionReason: .competingCandidate, reason: "Experimental local fit; identity unverified")
                                var replacement = CardCenteringMeasurement(imageWidth: width, imageHeight: height,
                                    outerQuad: proposed.outerQuad, innerQuad: current, warnings: [], boundaryCandidates: [candidate])
                                if replacement.selectBoundaryCandidate(id: "research", as: .printedBorder) { proposed = replacement }
                                else { acceptedLine = nil; jointRejection = true }
                            }
                            sideMetrics.append(.init(frame: frame.rawValue, side: side.rawValue,
                                annotationAmbiguous: gt.ambiguousEdges.contains(side.rawValue), annotationBandNativePixels: gt.edgeBands[side.rawValue],
                                originalSeedMaximumLineError: error(selected.line, gtLine),
                                coarseCandidateRecallAtTwoNativePixels: sideSeeds.contains { error($0.line, gtLine) <= 2 },
                                refinedCandidateRecallAtTwoNativePixels: fits.contains { error($0.line, gtLine) <= 2 },
                                candidateCount: fits.count, eligibleCount: eligible.count,
                                selectedMaximumLineError: acceptedLine.map { error($0, gtLine) },
                                disposition: jointRejection ? "rejected_invalid_intersections" : frame == .outer ? "observed_only_identity_unverified" : eligible.count > 1
                                    ? "abstain_competing_transitions" : eligible.isEmpty ? "abstain_unsupported" : "experimental_local_fit"))
                        }
                    }
                    let fitted = ratios(proposed)
                    allMetrics.append(.init(fixture: name, face: gt.face, encasement: gt.encasement, configuration: configuration,
                        sides: sideMetrics,
                        baselineLRAbsoluteErrorPP: expected.flatMap { gt in baseline.map { abs($0.0 - gt.0) } },
                        baselineTBAbsoluteErrorPP: expected.flatMap { gt in baseline.map { abs($0.1 - gt.1) } },
                        localFitLRAbsoluteErrorPP: expected.flatMap { gt in fitted.map { abs($0.0 - gt.0) } },
                        localFitTBAbsoluteErrorPP: expected.flatMap { gt in fitted.map { abs($0.1 - gt.1) } }, fittedQuadValid: proposed.hasValidFrameGeometry))
                }
                print("CENTERING_RESEARCH fixture=\(name) seeds=\(seeds.count) trials=\(result.trials.count) seconds=\(result.seconds) decode=\(result.decodeSeconds) firstCrop=\(result.firstCropSeconds ?? 0) processPeakBytes=\(result.memoryAtEnd?.processPeakResidentBytes ?? 0)")
            }
        }
        let attachment = XCTAttachment(data: try JSONEncoder().encode(allMetrics), uniformTypeIdentifier: "public.json")
        attachment.name = "development-metrics-v1"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(allMetrics.count, names.count * NativeResearch.Configuration.ablations.count)
        for configuration in NativeResearch.Configuration.ablations {
            let metrics = allMetrics.filter { $0.configuration == configuration }
            let sides = metrics.flatMap(\.sides).filter { $0.frame == "inner" }
            let errors = metrics.compactMap(\.localFitLRAbsoluteErrorPP) + metrics.compactMap(\.localFitTBAbsoluteErrorPP)
            print("CENTERING_ABLATION config=\(configuration.id) innerSides=\(sides.count) coarseRecall=\(sides.filter(\.coarseCandidateRecallAtTwoNativePixels).count) refinedRecall=\(sides.filter(\.refinedCandidateRecallAtTwoNativePixels).count) abstained=\(sides.filter { $0.selectedMaximumLineError == nil }.count) selectedWrong=\(sides.filter { ($0.selectedMaximumLineError ?? 0) > 2 }.count) ratioErrorMedianPP=\(errors.isEmpty ? -1 : NativeResearch.median(errors)) ratioErrorWorstPP=\(errors.max() ?? -1)")
        }
    }

    @MainActor func testNativeDetailProfilesColdDecodeAndCacheWithoutClaimingBoundedDecoderMemory() async throws {
        let bundle = Bundle(for: Self.self)
        let data = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "IMG_0347", withExtension: "HEIC", subdirectory: "TradingCards/HEIC")))
        let model = CardCenteringViewModel()
        model.loadCapturedPhoto(data)
        let deadline = Date().addingTimeInterval(15)
        while model.isAnalyzing && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.isAnalyzing)
        let before = NativeResearch.Memory.read(), start = CFAbsoluteTimeGetCurrent()
        let first = try XCTUnwrap(model.nativeDetailCrop(in: CGRect(x: 300, y: 300, width: 128, height: 128)))
        let cold = CFAbsoluteTimeGetCurrent() - start, after = NativeResearch.Memory.read()
        let cacheStart = CFAbsoluteTimeGetCurrent()
        let cached = try XCTUnwrap(model.nativeDetailCrop(in: CGRect(x: 300, y: 300, width: 128, height: 128)))
        let cache = CFAbsoluteTimeGetCurrent() - cacheStart
        XCTAssertTrue(first.image === cached.image)
        XCTAssertEqual(first.width * first.height, 128 * 128)
        print("CENTERING_DETAIL coldSeconds=\(cold) cacheSeconds=\(cache) residentBefore=\(before?.residentBytes ?? 0) residentAfter=\(after?.residentBytes ?? 0) processPeakBefore=\(before?.processPeakResidentBytes ?? 0) processPeakAfter=\(after?.processPeakResidentBytes ?? 0)")
    }
}
