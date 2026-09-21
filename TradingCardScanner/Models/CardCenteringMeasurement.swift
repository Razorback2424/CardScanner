import CoreGraphics
import Foundation

struct CardCenteringEdges: Codable, Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

/// A pixel coordinate in the oriented image used by the centering pipeline.
/// This is intentionally not `CGPoint`: keeping the value Codable makes the
/// same representation usable by the ground-truth and screenshot harnesses.
struct CardCenteringPoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
}

/// The two percentages that make up one centering axis at a sampled position.
/// `firstPercentage` is the left or top side; `secondPercentage` is the right
/// or bottom side, depending on the axis this pair belongs to.
struct CardCenteringRatioPair: Codable, Equatable {
    let firstPercentage: Double
    let secondPercentage: Double

    init?(firstDistance: Double, secondDistance: Double) {
        let total = firstDistance + secondDistance
        guard total.isFinite, total > .ulpOfOne,
              firstDistance.isFinite, secondDistance.isFinite else {
            return nil
        }
        firstPercentage = 100 * firstDistance / total
        secondPercentage = 100 * secondDistance / total
    }
}

/// The observed range of one ratio axis over the positional samples. Both
/// sides are retained because the complement relationship is useful when
/// inspecting raw diagnostics and avoids throwing away information.
struct CardCenteringRatioRange: Codable, Equatable {
    let firstMinimum: Double
    let firstMaximum: Double
    let firstSpread: Double
    let secondMinimum: Double
    let secondMaximum: Double
    let secondSpread: Double

    init?(samples: [CardCenteringRatioPair]) {
        guard !samples.isEmpty else { return nil }
        let firstValues = samples.map(\.firstPercentage)
        let secondValues = samples.map(\.secondPercentage)
        guard let firstMinimum = firstValues.min(),
              let firstMaximum = firstValues.max(),
              let secondMinimum = secondValues.min(),
              let secondMaximum = secondValues.max() else {
            return nil
        }
        self.firstMinimum = firstMinimum
        self.firstMaximum = firstMaximum
        self.firstSpread = firstMaximum - firstMinimum
        self.secondMinimum = secondMinimum
        self.secondMaximum = secondMaximum
        self.secondSpread = secondMaximum - secondMinimum
    }
}

/// One positional sample of the reported centering ratios. Positions are
/// normalized along the corresponding measured span: 0 is the top/left end
/// and 1 is the bottom/right end.
struct CardCenteringPositionalRatioSample: Codable, Equatable {
    let normalizedPosition: Double
    let leftRight: CardCenteringRatioPair
    let topBottom: CardCenteringRatioPair
}

/// Internal-consistency evidence for a measurement. This is observational
/// only: a low spread must not be treated as proof that the selected edges are
/// the physical card edges, since parallel sleeve edges can be equally stable.
struct CardCenteringPositionalConsistency: Codable, Equatable {
    static let defaultSampleCount = 5

    let samples: [CardCenteringPositionalRatioSample]
    let leftRight: CardCenteringRatioRange
    let topBottom: CardCenteringRatioRange

    init?(
        outer: CardCenteringQuad,
        inner: CardCenteringQuad,
        sampleCount: Int = CardCenteringPositionalConsistency.defaultSampleCount
    ) {
        guard sampleCount >= CardCenteringPositionalConsistency.defaultSampleCount else {
            return nil
        }

        let positions = (0..<sampleCount).map { index in
            Double(index) / Double(sampleCount - 1)
        }
        let samples = positions.compactMap { position -> CardCenteringPositionalRatioSample? in
            let distances = outer.borderDistances(at: position, to: inner)
            guard let leftRight = CardCenteringRatioPair(
                firstDistance: distances.left,
                secondDistance: distances.right
            ), let topBottom = CardCenteringRatioPair(
                firstDistance: distances.top,
                secondDistance: distances.bottom
            ) else {
                return nil
            }
            return CardCenteringPositionalRatioSample(
                normalizedPosition: position,
                leftRight: leftRight,
                topBottom: topBottom
            )
        }
        guard samples.count == positions.count,
              let leftRight = CardCenteringRatioRange(samples: samples.map(\.leftRight)),
              let topBottom = CardCenteringRatioRange(samples: samples.map(\.topBottom)) else {
            return nil
        }

        self.samples = samples
        self.leftRight = leftRight
        self.topBottom = topBottom
    }
}

struct CardCenteringSize: Codable, Equatable, Hashable {
    var width: Double
    var height: Double
}

/// The four corners of one physical or printed rectangle, always ordered
/// clockwise from the image-space top-left corner.
struct CardCenteringQuad: Codable, Equatable {
    var topLeft: CardCenteringPoint
    var topRight: CardCenteringPoint
    var bottomRight: CardCenteringPoint
    var bottomLeft: CardCenteringPoint

    init(
        topLeft: CardCenteringPoint,
        topRight: CardCenteringPoint,
        bottomRight: CardCenteringPoint,
        bottomLeft: CardCenteringPoint
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    var points: [CardCenteringPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    /// A scalar projection retained for the existing stepper UI and filename
    /// surface. It is never used as the source of the centering calculation.
    var projectedEdges: CardCenteringEdges {
        CardCenteringEdges(
            left: Int(points.map(\.x).min()!.rounded()),
            top: Int(points.map(\.y).min()!.rounded()),
            right: Int(points.map(\.x).max()!.rounded()),
            bottom: Int(points.map(\.y).max()!.rounded())
        )
    }

    static func axisAligned(_ edges: CardCenteringEdges) -> CardCenteringQuad {
        CardCenteringQuad(
            topLeft: CardCenteringPoint(x: Double(edges.left), y: Double(edges.top)),
            topRight: CardCenteringPoint(x: Double(edges.right), y: Double(edges.top)),
            bottomRight: CardCenteringPoint(x: Double(edges.right), y: Double(edges.bottom)),
            bottomLeft: CardCenteringPoint(x: Double(edges.left), y: Double(edges.bottom))
        )
    }

    var topLength: Double { distance(topLeft, topRight) }
    var rightLength: Double { distance(topRight, bottomRight) }
    var bottomLength: Double { distance(bottomLeft, bottomRight) }
    var leftLength: Double { distance(topLeft, bottomLeft) }

    var rectifiedWidth: Double { (topLength + bottomLength) / 2 }
    var rectifiedHeight: Double { (leftLength + rightLength) / 2 }

    /// Width / height after the quad has been fitted. Using corresponding edge
    /// lengths avoids the bounding-box aspect error introduced by skew.
    var rectifiedAspectRatio: Double {
        rectifiedHeight > .ulpOfOne ? rectifiedWidth / rectifiedHeight : 0
    }

    /// Perpendicular distances from each inner edge to the corresponding outer
    /// edge. A shear or in-plane rotation changes both members of a pair by the
    /// same scale, so the resulting centering ratio is invariant to it.
    func borderDistances(to inner: CardCenteringQuad) -> (left: Double, top: Double, right: Double, bottom: Double) {
        (
            left: averageDistance(inner.topLeft, inner.bottomLeft, from: topLeft, to: bottomLeft),
            top: averageDistance(inner.topLeft, inner.topRight, from: topLeft, to: topRight),
            right: averageDistance(inner.topRight, inner.bottomRight, from: topRight, to: bottomRight),
            bottom: averageDistance(inner.bottomLeft, inner.bottomRight, from: bottomLeft, to: bottomRight)
        )
    }

    /// Border distances at one normalized position along each corresponding
    /// edge. This is used only for positional diagnostics; the production
    /// ratio continues to use the established endpoint-average calculation.
    func borderDistances(
        at normalizedPosition: Double,
        to inner: CardCenteringQuad
    ) -> (left: Double, top: Double, right: Double, bottom: Double) {
        let position = min(1, max(0, normalizedPosition))
        let innerLeft = interpolate(inner.topLeft, inner.bottomLeft, at: position)
        let innerTop = interpolate(inner.topLeft, inner.topRight, at: position)
        let innerRight = interpolate(inner.topRight, inner.bottomRight, at: position)
        let innerBottom = interpolate(inner.bottomLeft, inner.bottomRight, at: position)

        return (
            left: perpendicularDistance(innerLeft, from: topLeft, to: bottomLeft),
            top: perpendicularDistance(innerTop, from: topLeft, to: topRight),
            right: perpendicularDistance(innerRight, from: topRight, to: bottomRight),
            bottom: perpendicularDistance(innerBottom, from: bottomLeft, to: bottomRight)
        )
    }

    private func averageDistance(
        _ first: CardCenteringPoint,
        _ second: CardCenteringPoint,
        from lineStart: CardCenteringPoint,
        to lineEnd: CardCenteringPoint
    ) -> Double {
        (perpendicularDistance(first, from: lineStart, to: lineEnd)
            + perpendicularDistance(second, from: lineStart, to: lineEnd)) / 2
    }

    private func perpendicularDistance(
        _ point: CardCenteringPoint,
        from lineStart: CardCenteringPoint,
        to lineEnd: CardCenteringPoint
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > .ulpOfOne else { return 0 }
        return abs(dx * (point.y - lineStart.y) - dy * (point.x - lineStart.x)) / length
    }

    private func interpolate(
        _ start: CardCenteringPoint,
        _ end: CardCenteringPoint,
        at position: Double
    ) -> CardCenteringPoint {
        CardCenteringPoint(
            x: start.x + (end.x - start.x) * position,
            y: start.y + (end.y - start.y) * position
        )
    }

    private func distance(_ lhs: CardCenteringPoint, _ rhs: CardCenteringPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }
}

/// A projective transform from the photographed card quad into a fronto-
/// parallel card space. The source image is intentionally left untouched for
/// presentation; this transform is the measurement space used for borders and
/// ratios, so a perspective lean cannot masquerade as a centering error.
struct CardCenteringRectification: Codable, Equatable {
    let targetSize: CardCenteringSize
    let coefficients: [Double]
    /// The remaining opposite-edge angle after the transform. A homography
    /// maps the four fitted edge lines to the target rectangle; the residual is
    /// retained as an auditable guard instead of silently assuming success.
    let residualDegrees: Double
    /// Relative difference between the fitted card aspect and the standard
    /// trading-card aspect. This is separate from `residualDegrees`: a
    /// homography can make a non-card-shaped quadrilateral perfectly parallel.
    let aspectResidual: Double
    /// Round-trip error after solving the inverse homography. It catches a
    /// singular or numerically unstable fit without relying on the same
    /// forward mapping twice.
    let reprojectionRMS: Double
    /// Whether the fitted transform is safe to use as an automatic reading.
    /// A failed guard is surfaced through confidence rather than hidden by a
    /// plausible-looking ratio.
    let isValid: Bool

    init(outerQuad: CardCenteringQuad, expectedAspectRatio: Double = 5.0 / 7.0) {
        let targetWidth = (outerQuad.topLength + outerQuad.bottomLength) / 2
        let targetHeight = (outerQuad.leftLength + outerQuad.rightLength) / 2
        targetSize = CardCenteringSize(width: targetWidth, height: targetHeight)

        let source = outerQuad.points
        let destination = [
            CardCenteringPoint(x: 0, y: 0),
            CardCenteringPoint(x: targetWidth, y: 0),
            CardCenteringPoint(x: targetWidth, y: targetHeight),
            CardCenteringPoint(x: 0, y: targetHeight)
        ]
        let solved = Self.solveHomography(source: source, destination: destination)
        coefficients = solved ?? Self.identityCoefficients

        let rectified = CardCenteringQuad(
            topLeft: Self.map(source[0], coefficients: coefficients),
            topRight: Self.map(source[1], coefficients: coefficients),
            bottomRight: Self.map(source[2], coefficients: coefficients),
            bottomLeft: Self.map(source[3], coefficients: coefficients)
        )
        residualDegrees = Self.parallelismResidual(for: rectified)
        let measuredAspect = targetHeight > .ulpOfOne ? targetWidth / targetHeight : 0
        let shortToLongAspect = measuredAspect > 1 ? 1 / measuredAspect : measuredAspect
        aspectResidual = expectedAspectRatio > .ulpOfOne
            ? abs(shortToLongAspect - expectedAspectRatio) / expectedAspectRatio
            : .infinity
        reprojectionRMS = Self.reprojectionRMS(
            source: source,
            destination: destination,
            coefficients: coefficients
        )
        let coefficientsAreFinite = coefficients.count == 8 && coefficients.allSatisfy(\.isFinite)
        let targetIsFinite = targetWidth.isFinite && targetHeight.isFinite
            && targetWidth > .ulpOfOne && targetHeight > .ulpOfOne
        let residualIsFinite = residualDegrees.isFinite && reprojectionRMS.isFinite
        // Four percent is the hard confidence boundary used by INV-10. The
        // stricter 1.5% comparison remains an evaluator metric against the
        // independently annotated object aspect; runtime cannot read that GT.
        isValid = solved != nil
            && coefficientsAreFinite
            && targetIsFinite
            && residualIsFinite
            && residualDegrees <= 0.30
            && aspectResidual <= 0.04
            && reprojectionRMS <= max(2.0, min(targetWidth, targetHeight) * 0.01)
    }

    init(targetSize: CardCenteringSize, coefficients: [Double], residualDegrees: Double) {
        self.targetSize = targetSize
        self.coefficients = coefficients
        self.residualDegrees = residualDegrees
        self.aspectResidual = 0
        self.reprojectionRMS = 0
        self.isValid = coefficients.count == 8
            && coefficients.allSatisfy(\.isFinite)
            && residualDegrees.isFinite
    }

    func rectifiedPoint(from point: CardCenteringPoint) -> CardCenteringPoint {
        Self.map(point, coefficients: coefficients)
    }

    func rectifiedQuad(from quad: CardCenteringQuad) -> CardCenteringQuad {
        CardCenteringQuad(
            topLeft: rectifiedPoint(from: quad.topLeft),
            topRight: rectifiedPoint(from: quad.topRight),
            bottomRight: rectifiedPoint(from: quad.bottomRight),
            bottomLeft: rectifiedPoint(from: quad.bottomLeft)
        )
    }

    private static let identityCoefficients = [
        1.0, 0, 0,
        0, 1.0, 0,
        0, 0
    ]

    private static func map(_ point: CardCenteringPoint, coefficients: [Double]) -> CardCenteringPoint {
        guard coefficients.count == 8 else { return point }
        let denominator = coefficients[6] * point.x + coefficients[7] * point.y + 1
        guard abs(denominator) > 1e-12 else { return point }
        return CardCenteringPoint(
            x: (coefficients[0] * point.x + coefficients[1] * point.y + coefficients[2]) / denominator,
            y: (coefficients[3] * point.x + coefficients[4] * point.y + coefficients[5]) / denominator
        )
    }

    private static func reprojectionRMS(
        source: [CardCenteringPoint],
        destination: [CardCenteringPoint],
        coefficients: [Double]
    ) -> Double {
        guard source.count == 4, destination.count == 4,
              let inverse = solveHomography(source: destination, destination: source) else {
            return .infinity
        }
        let squaredError = zip(source, destination).reduce(0.0) { total, pair in
            let recovered = map(pair.1, coefficients: inverse)
            let dx = recovered.x - pair.0.x
            let dy = recovered.y - pair.0.y
            return total + dx * dx + dy * dy
        }
        return sqrt(squaredError / Double(source.count))
    }

    private static func solveHomography(
        source: [CardCenteringPoint],
        destination: [CardCenteringPoint]
    ) -> [Double]? {
        guard source.count == 4, destination.count == 4 else { return nil }
        var matrix = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        for index in 0..<4 {
            let x = source[index].x
            let y = source[index].y
            let u = destination[index].x
            let v = destination[index].y
            let row = index * 2
            matrix[row] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            matrix[row + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }

        for pivot in 0..<8 {
            guard let best = (pivot..<8).max(by: {
                abs(matrix[$0][pivot]) < abs(matrix[$1][pivot])
            }), abs(matrix[best][pivot]) > 1e-12 else {
                return nil
            }
            if best != pivot { matrix.swapAt(best, pivot) }
            let divisor = matrix[pivot][pivot]
            for column in pivot..<9 { matrix[pivot][column] /= divisor }
            for row in 0..<8 where row != pivot {
                let factor = matrix[row][pivot]
                guard abs(factor) > 1e-15 else { continue }
                for column in pivot..<9 {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
            }
        }
        return (0..<8).map { matrix[$0][8] }
    }

    private static func parallelismResidual(for quad: CardCenteringQuad) -> Double {
        let top = atan2(quad.topRight.y - quad.topLeft.y, quad.topRight.x - quad.topLeft.x)
        let bottom = atan2(quad.bottomRight.y - quad.bottomLeft.y, quad.bottomRight.x - quad.bottomLeft.x)
        let left = atan2(quad.bottomLeft.y - quad.topLeft.y, quad.bottomLeft.x - quad.topLeft.x)
        let right = atan2(quad.bottomRight.y - quad.topRight.y, quad.bottomRight.x - quad.topRight.x)
        func difference(_ first: Double, _ second: Double) -> Double {
            var result = (first - second).truncatingRemainder(dividingBy: .pi)
            if result > .pi / 2 { result -= .pi }
            if result < -.pi / 2 { result += .pi }
            return abs(result)
        }
        return max(difference(top, bottom), difference(left, right)) * 180 / .pi
    }
}

/// Exact conversion between the oriented source pixels and the downscaled,
/// optionally rotated working image used by detection.
struct CardCenteringCoordinateMapping: Codable, Equatable {
    var orientedSourceSize: CardCenteringSize
    var workingSize: CardCenteringSize
    var appliedRotationDegrees: Double
    /// The unrotated working canvas. It is equal to `workingSize` for the
    /// normal path and is retained separately when rotation enlarges the canvas.
    var unrotatedWorkingSize: CardCenteringSize

    init(
        orientedSourceSize: CardCenteringSize,
        workingSize: CardCenteringSize,
        appliedRotationDegrees: Double = 0,
        unrotatedWorkingSize: CardCenteringSize? = nil
    ) {
        self.orientedSourceSize = orientedSourceSize
        self.workingSize = workingSize
        self.appliedRotationDegrees = appliedRotationDegrees
        self.unrotatedWorkingSize = unrotatedWorkingSize ?? workingSize
    }

    var workingToNativeScale: Double {
        let x = orientedSourceSize.width / max(unrotatedWorkingSize.width, .ulpOfOne)
        let y = orientedSourceSize.height / max(unrotatedWorkingSize.height, .ulpOfOne)
        return (x + y) / 2
    }

    var nativeToWorkingScale: Double {
        workingToNativeScale > .ulpOfOne ? 1 / workingToNativeScale : 0
    }

    func workingPoint(fromNative point: CardCenteringPoint) -> CardCenteringPoint {
        let xScale = unrotatedWorkingSize.width / max(orientedSourceSize.width, .ulpOfOne)
        let yScale = unrotatedWorkingSize.height / max(orientedSourceSize.height, .ulpOfOne)
        let unrotated = CardCenteringPoint(x: point.x * xScale, y: point.y * yScale)
        return rotate(unrotated, by: appliedRotationDegrees, from: unrotatedWorkingSize, into: workingSize)
    }

    func nativePoint(fromWorking point: CardCenteringPoint) -> CardCenteringPoint {
        let unrotated = rotate(point, by: -appliedRotationDegrees, from: workingSize, into: unrotatedWorkingSize)
        return CardCenteringPoint(
            x: unrotated.x * orientedSourceSize.width / max(unrotatedWorkingSize.width, .ulpOfOne),
            y: unrotated.y * orientedSourceSize.height / max(unrotatedWorkingSize.height, .ulpOfOne)
        )
    }

    func workingQuad(fromNative quad: CardCenteringQuad) -> CardCenteringQuad {
        map(quad, with: workingPoint(fromNative:))
    }

    func nativeQuad(fromWorking quad: CardCenteringQuad) -> CardCenteringQuad {
        map(quad, with: nativePoint(fromWorking:))
    }

    private func map(_ quad: CardCenteringQuad, with transform: (CardCenteringPoint) -> CardCenteringPoint) -> CardCenteringQuad {
        CardCenteringQuad(
            topLeft: transform(quad.topLeft),
            topRight: transform(quad.topRight),
            bottomRight: transform(quad.bottomRight),
            bottomLeft: transform(quad.bottomLeft)
        )
    }

    private func rotate(
        _ point: CardCenteringPoint,
        by degrees: Double,
        from sourceSize: CardCenteringSize,
        into destinationSize: CardCenteringSize
    ) -> CardCenteringPoint {
        let radians = degrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let sourceCenter = CardCenteringPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        let dx = point.x - sourceCenter.x
        let dy = point.y - sourceCenter.y
        return CardCenteringPoint(
            x: destinationSize.width / 2 + cosine * dx - sine * dy,
            y: destinationSize.height / 2 + sine * dx + cosine * dy
        )
    }
}

/// Maps detector-space pixels into the exact fitted image frame used by a
/// guide overlay. Keeping this independent of SwiftUI and UIKit makes the
/// screen and export paths use the same geometry contract.
enum CardCenteringGuideGeometry {
    static func screenPoints(
        for quad: CardCenteringQuad,
        imageSize: CardCenteringSize,
        in frame: CGRect
    ) -> [CGPoint] {
        let xScale = frame.width / CGFloat(max(imageSize.width, .ulpOfOne))
        let yScale = frame.height / CGFloat(max(imageSize.height, .ulpOfOne))
        return quad.points.map { point in
            CGPoint(
                x: frame.minX + CGFloat(point.x) * xScale,
                y: frame.minY + CGFloat(point.y) * yScale
            )
        }
    }
}

enum CardCenteringInnerReference: String, Codable, Equatable {
    case artWindow = "art_window"
    case printedBorder = "printed_border"
    case none
}

enum CardCenteringConfidenceState: String, Codable, Equatable {
    case confident
    /// The detector found usable starting frames, but the product contract
    /// requires the person to confirm or adjust the outer card and inner frame
    /// before any ratio is treated as a reading.
    case manualConfirmationRequired
    case declined
}

/// Numeric confidence is deliberately decomposed into the evidence that made
/// it up. A single opaque score would make a decline impossible to audit.
struct CardCenteringConfidence: Codable, Equatable {
    var score: Double
    var state: CardCenteringConfidenceState
    var edgeSupport: Double
    var aspectResidual: Double
    var rectificationResidual: Double
    var sleeveAmbiguity: Double
    var innerReferencePresent: Bool
    var reason: String?

    static var legacyConfident: CardCenteringConfidence {
        CardCenteringConfidence(
            score: 1,
            state: .confident,
            edgeSupport: 1,
            aspectResidual: 0,
            rectificationResidual: 0,
            sleeveAmbiguity: 0,
            innerReferencePresent: true,
            reason: nil
        )
    }

    static func declined(reason: String) -> CardCenteringConfidence {
        CardCenteringConfidence(
            score: 0,
            state: .declined,
            edgeSupport: 0,
            aspectResidual: 0,
            rectificationResidual: 0,
            sleeveAmbiguity: 0,
            innerReferencePresent: false,
            reason: reason
        )
    }

    static func manualConfirmationRequired(
        preserving confidence: CardCenteringConfidence,
        reason: String
    ) -> CardCenteringConfidence {
        var result = confidence
        result.state = .manualConfirmationRequired
        result.reason = reason
        return result
    }
}

struct CardCenteringMeasurement: Equatable {
    var imageWidth: Int
    var imageHeight: Int
    var outer: CardCenteringEdges
    var inner: CardCenteringEdges
    var warnings: [String]
    /// What the detector could not establish for itself, set once when the
    /// measurement is made.
    ///
    /// Kept separate from `warnings` because those are recomputed from the
    /// guide positions every time one is dragged, and a note about how the
    /// guides were *found* must survive that. Without it a fallback reading
    /// looks exactly like a confident one: the numbers stay self-consistent, so
    /// the geometry checks below pass and the screen states a ratio it has no
    /// grounds for.
    var detectionNotes: [String] = []

    /// Geometry is kept alongside the legacy scalar projection so callers that
    /// already bind to the four guide steppers remain source compatible.
    var outerQuad: CardCenteringQuad
    var innerQuad: CardCenteringQuad?
    var coordinateMapping: CardCenteringCoordinateMapping?
    var innerReference: CardCenteringInnerReference
    var confidence: CardCenteringConfidence
    /// Measurement-space homography. The displayed image and guide geometry
    /// stay in the photographed coordinates; ratios use this rectified space.
    var rectification: CardCenteringRectification?
    private(set) var usesQuadGeometry: Bool

    init(
        imageWidth: Int,
        imageHeight: Int,
        outer: CardCenteringEdges,
        inner: CardCenteringEdges,
        warnings: [String],
        detectionNotes: [String] = []
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.outer = outer
        self.inner = inner
        self.warnings = warnings
        self.detectionNotes = detectionNotes
        self.outerQuad = .axisAligned(outer)
        self.innerQuad = .axisAligned(inner)
        self.coordinateMapping = nil
        self.innerReference = .artWindow
        self.confidence = .legacyConfident
        self.rectification = nil
        self.usesQuadGeometry = false
    }

    init(
        imageWidth: Int,
        imageHeight: Int,
        outerQuad: CardCenteringQuad,
        innerQuad: CardCenteringQuad?,
        warnings: [String],
        detectionNotes: [String] = [],
        coordinateMapping: CardCenteringCoordinateMapping? = nil,
        innerReference: CardCenteringInnerReference = .artWindow,
        confidence: CardCenteringConfidence? = nil,
        rectification: CardCenteringRectification? = nil
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.outerQuad = outerQuad
        self.innerQuad = innerQuad
        self.outer = outerQuad.projectedEdges
        self.inner = innerQuad?.projectedEdges ?? outerQuad.projectedEdges
        self.warnings = warnings
        self.detectionNotes = detectionNotes
        self.coordinateMapping = coordinateMapping
        self.innerReference = innerReference
        let resolvedRectification = rectification ?? CardCenteringRectification(outerQuad: outerQuad)
        if let confidence {
            self.confidence = confidence
        } else if innerQuad == nil || innerReference == .none {
            self.confidence = .declined(
                reason: "The image does not contain a stable gradeable inner reference."
            )
        } else if !resolvedRectification.isValid {
            self.confidence = .declined(
                reason: "The detected card geometry cannot be rectified reliably."
            )
        } else {
            self.confidence = .legacyConfident
        }
        self.rectification = resolvedRectification
        self.usesQuadGeometry = true
    }

    /// Ratios are reportable only after the product has a confident or
    /// manually-confirmed card frame. A detector candidate is intentionally not
    /// enough: the hybrid release path must never present unconfirmed automatic
    /// outer or inner geometry as fact.
    var isDeclined: Bool { confidence.state != .confident }
    var requiresManualOuterConfirmation: Bool {
        confidence.state == .manualConfirmationRequired
    }
    var requiresManualInnerConfirmation: Bool {
        confidence.state == .manualConfirmationRequired && geometryInnerQuad != nil
    }
    var requiresManualFrameConfirmation: Bool {
        requiresManualOuterConfirmation && requiresManualInnerConfirmation
    }
    var confidenceScore: Double { confidence.score }
    var declineReason: String? { confidence.reason }

    var geometryOuterQuad: CardCenteringQuad {
        usesQuadGeometry ? outerQuad : .axisAligned(outer)
    }

    var geometryInnerQuad: CardCenteringQuad? {
        guard innerReference != .none else { return nil }
        return usesQuadGeometry ? innerQuad : .axisAligned(inner)
    }

    /// Samples the reported ratios at five evenly spaced positions along the
    /// measured spans. This is an internal-consistency diagnostic only: it is
    /// deliberately not folded into confidence or selection because a sleeve
    /// can produce a stable, low-spread pair of parallel edges too.
    var positionalConsistency: CardCenteringPositionalConsistency? {
        guard let inner = geometryInnerQuad else { return nil }
        let measuredOuter = rectification?.rectifiedQuad(from: geometryOuterQuad) ?? geometryOuterQuad
        let measuredInner = rectification?.rectifiedQuad(from: inner) ?? inner
        return CardCenteringPositionalConsistency(
            outer: measuredOuter,
            inner: measuredInner
        )
    }

    var leftBorderDistance: Double {
        guard let innerQuad = geometryInnerQuad else { return 0 }
        return measurementBorderDistances(to: innerQuad).left
    }

    var topBorderDistance: Double {
        guard let innerQuad = geometryInnerQuad else { return 0 }
        return measurementBorderDistances(to: innerQuad).top
    }

    var rightBorderDistance: Double {
        guard let innerQuad = geometryInnerQuad else { return 0 }
        return measurementBorderDistances(to: innerQuad).right
    }

    var bottomBorderDistance: Double {
        guard let innerQuad = geometryInnerQuad else { return 0 }
        return measurementBorderDistances(to: innerQuad).bottom
    }

    private func measurementBorderDistances(to inner: CardCenteringQuad) -> (left: Double, top: Double, right: Double, bottom: Double) {
        guard let rectification else {
            return geometryOuterQuad.borderDistances(to: inner)
        }
        return rectification
            .rectifiedQuad(from: geometryOuterQuad)
            .borderDistances(to: rectification.rectifiedQuad(from: inner))
    }

    var leftBorder: Int { Int(leftBorderDistance.rounded()) }
    var rightBorder: Int { Int(rightBorderDistance.rounded()) }
    var topBorder: Int { Int(topBorderDistance.rounded()) }
    var bottomBorder: Int { Int(bottomBorderDistance.rounded()) }

    var leftRightCentering: String {
        guard !isDeclined else { return "—" }
        return Self.centeringString(leftBorderDistance, rightBorderDistance)
    }

    var topBottomCentering: String {
        guard !isDeclined else { return "—" }
        return Self.centeringString(topBorderDistance, bottomBorderDistance)
    }

    mutating func refreshWarnings() {
        var updated: [String] = detectionNotes
        if let reason = confidence.reason, !updated.contains(reason) {
            updated.append(reason)
        }
        guard geometryInnerQuad != nil else {
            warnings = updated
            return
        }
        if usesQuadGeometry {
            let distances = measurementBorderDistances(to: geometryInnerQuad!)
            if !(distances.left > 0 && distances.right > 0) {
                updated.append("Check the left and right guide positions.")
            }
            if !(distances.top > 0 && distances.bottom > 0) {
                updated.append("Check the top and bottom guide positions.")
            }
            if [distances.left, distances.right, distances.top, distances.bottom].contains(where: { $0 <= 0 }) {
                updated.append("Each inner guide must be inside the card edge.")
            }
        } else {
            if !(outer.left < inner.left && inner.left < inner.right && inner.right < outer.right) {
                updated.append("Check the left and right guide positions.")
            }
            if !(outer.top < inner.top && inner.top < inner.bottom && inner.bottom < outer.bottom) {
                updated.append("Check the top and bottom guide positions.")
            }
            if [leftBorder, rightBorder, topBorder, bottomBorder].contains(where: { $0 <= 0 }) {
                updated.append("Each inner guide must be inside the card edge.")
            }
        }
        warnings = updated
    }

    mutating func setManualOuterEdge(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int
    ) {
        outer[keyPath: keyPath] = value
        outerQuad = .axisAligned(outer)
        rectification = nil
        usesQuadGeometry = false
        if geometryInnerQuad != nil {
            confidence = .legacyConfident
        }
    }

    mutating func setManualInnerEdge(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int
    ) {
        inner[keyPath: keyPath] = value
        innerQuad = .axisAligned(inner)
        rectification = nil
        usesQuadGeometry = false
        innerReference = .artWindow
        if geometryInnerQuad != nil {
            confidence = .legacyConfident
        }
    }

    private static func centeringString(_ first: Double, _ second: Double) -> String {
        let total = first + second
        guard total > 0 else { return "—" }
        return String(format: "%.1f / %.1f", 100 * first / total, 100 * second / total)
    }
}
