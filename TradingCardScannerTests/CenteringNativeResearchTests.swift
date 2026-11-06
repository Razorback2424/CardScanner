import CryptoKit
import Darwin
import UIKit
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

    private func reference() throws -> CardCenteringPrintReference {
        try JSONDecoder().decode(
            CardCenteringPrintReference.self, from: resource("fin-289", type: "json", folder: "PrintReferences"))
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
            XCTAssertEqual(measured, try CardCenteringAnalyzer.analyze(bytes).measurement, tag)
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
