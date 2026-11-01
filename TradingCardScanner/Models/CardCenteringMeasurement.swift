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
              firstDistance.isFinite, secondDistance.isFinite,
              firstDistance > 0, secondDistance > 0 else {
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

    /// Each named side's extreme coordinate for the existing stepper UI.
    /// Keep side identities even when an edit crosses the opposite guide.
    /// This is never the source of the centering calculation.
    var projectedEdges: CardCenteringEdges {
        CardCenteringEdges(
            left: Int(exactly: min(topLeft.x, bottomLeft.x).rounded()) ?? 0,
            top: Int(exactly: min(topLeft.y, topRight.y).rounded()) ?? 0,
            right: Int(exactly: max(topRight.x, bottomRight.x).rounded()) ?? 0,
            bottom: Int(exactly: max(bottomLeft.y, bottomRight.y).rounded()) ?? 0
        )
    }

    /// Move one supporting line, preserving its slope and the other three
    /// lines. The numeric control addresses the extreme corner of that side.
    func movingEdge(_ keyPath: WritableKeyPath<CardCenteringEdges, Int>, to value: Int) -> CardCenteringQuad? {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let side: Int
        let horizontalCoordinate: Bool
        let minimum: Bool
        switch keyPath {
        case \.left: (side, horizontalCoordinate, minimum) = (3, true, true)
        case \.right: (side, horizontalCoordinate, minimum) = (1, true, false)
        case \.top: (side, horizontalCoordinate, minimum) = (0, false, true)
        case \.bottom: (side, horizontalCoordinate, minimum) = (2, false, false)
        default: return nil
        }
        if projectedEdges[keyPath: keyPath] == value { return self }
        var corners = points
        var lines = (0..<4).map { index -> (a: Double, b: Double, c: Double) in
            let start = corners[index], end = corners[(index + 1) % 4]
            let a = end.y - start.y, b = start.x - end.x
            return (a, b, a * start.x + b * start.y)
        }
        let next = (side + 1) % 4
        func coordinate(_ index: Int) -> Double { horizontalCoordinate ? corners[index].x : corners[index].y }
        let anchor = (minimum ? coordinate(side) <= coordinate(next) : coordinate(side) >= coordinate(next)) ? side : next
        let neighbour = lines[anchor == side ? (side + 3) % 4 : next]
        let target = Double(value)
        let point: CardCenteringPoint
        if horizontalCoordinate {
            guard abs(neighbour.b) > 1e-12 else { return nil }
            point = CardCenteringPoint(x: target, y: (neighbour.c - neighbour.a * target) / neighbour.b)
        } else {
            guard abs(neighbour.a) > 1e-12 else { return nil }
            point = CardCenteringPoint(x: (neighbour.c - neighbour.b * target) / neighbour.a, y: target)
        }
        lines[side].c = lines[side].a * point.x + lines[side].b * point.y
        func intersection(_ first: Int, _ second: Int) -> CardCenteringPoint? {
            let lhs = lines[first], rhs = lines[second]
            let determinant = lhs.a * rhs.b - rhs.a * lhs.b
            guard determinant.isFinite, abs(determinant) > 1e-12 else { return nil }
            let result = CardCenteringPoint(
                x: (lhs.c * rhs.b - rhs.c * lhs.b) / determinant,
                y: (lhs.a * rhs.c - rhs.a * lhs.c) / determinant
            )
            return result.x.isFinite && result.y.isFinite ? result : nil
        }
        guard let start = intersection((side + 3) % 4, side),
              let end = intersection(side, next) else { return nil }
        corners[side] = start
        corners[next] = end
        let result = CardCenteringQuad(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3])
        // A collapsed adjacent edge loses its supporting line, making the next
        // edit impossible. Leave the existing editable frame intact instead.
        guard [result.topLength, result.rightLength, result.bottomLength, result.leftLength]
            .allSatisfy({ $0 > .ulpOfOne }) else { return nil }
        return result
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

    /// Manual placement still requires a sound transform, independently of
    /// the detector's standard-card aspect eligibility guard.
    var isNumericallyValid: Bool {
        guard coefficients.count == 8, coefficients.allSatisfy(\.isFinite) else { return false }
        let c = coefficients
        let determinant = c[0] * (c[4] - c[5] * c[7]) - c[1] * (c[3] - c[5] * c[6])
            + c[2] * (c[3] * c[7] - c[4] * c[6])
        return determinant.isFinite && abs(determinant) > 1e-12
            && targetSize.width.isFinite && targetSize.height.isFinite
            && targetSize.width > .ulpOfOne && targetSize.height > .ulpOfOne
            && residualDegrees.isFinite && residualDegrees <= 0.30
            && reprojectionRMS.isFinite
            && reprojectionRMS <= max(2, min(targetSize.width, targetSize.height) * 0.01)
    }

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

    /// Maps a rectified card-space point back into the photographed
    /// coordinates the guides are drawn in.
    func sourcePoint(fromRectified point: CardCenteringPoint) -> CardCenteringPoint {
        Self.map(point, coefficients: inverseCoefficients)
    }

    func sourceQuad(fromRectified quad: CardCenteringQuad) -> CardCenteringQuad {
        CardCenteringQuad(
            topLeft: sourcePoint(fromRectified: quad.topLeft),
            topRight: sourcePoint(fromRectified: quad.topRight),
            bottomRight: sourcePoint(fromRectified: quad.bottomRight),
            bottomLeft: sourcePoint(fromRectified: quad.bottomLeft)
        )
    }

    /// The adjugate of the forward matrix in the same eight-term form. A
    /// singular transform yields no coefficients, which `map` rejects.
    private var inverseCoefficients: [Double] {
        guard coefficients.count == 8 else { return [] }
        let c = coefficients
        let adjugate = [
            c[4] - c[5] * c[7], c[2] * c[7] - c[1], c[1] * c[5] - c[2] * c[4],
            c[5] * c[6] - c[3], c[0] - c[2] * c[6], c[2] * c[3] - c[0] * c[5],
            c[3] * c[7] - c[4] * c[6], c[1] * c[6] - c[0] * c[7], c[0] * c[4] - c[1] * c[3]
        ]
        let scale = adjugate[8]
        guard scale.isFinite, abs(scale) > 1e-12 else { return [] }
        return adjugate.prefix(8).map { $0 / scale }
    }

    private static let identityCoefficients = [
        1.0, 0, 0,
        0, 1.0, 0,
        0, 0
    ]

    private static func map(_ point: CardCenteringPoint, coefficients: [Double]) -> CardCenteringPoint {
        guard coefficients.count == 8, coefficients.allSatisfy(\.isFinite) else {
            return CardCenteringPoint(x: .nan, y: .nan)
        }
        let denominator = coefficients[6] * point.x + coefficients[7] * point.y + 1
        guard denominator.isFinite, abs(denominator) > 1e-12 else {
            return CardCenteringPoint(x: .nan, y: .nan)
        }
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
        guard source.count == 4, destination.count == 4,
              (source + destination).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
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
        let result = (0..<8).map { matrix[$0][8] }
        return result.allSatisfy(\.isFinite) ? result : nil
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
    /// Optional provenance for old records. Coordinates use continuous raster
    /// edges: the first pixel centre is (0.5, 0.5), not (0, 0).
    var rawRasterSize: CardCenteringSize? = nil
    var rawEXIFOrientation: Int? = nil

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

/// EXIF transforms in continuous raw raster coordinates. These are independent
/// of UIImage point size/scale and preserve pixel centres under every mirror.
struct CardCenteringRasterOrientation {
    let rawSize: CardCenteringSize
    let exif: Int

    var orientedSize: CardCenteringSize {
        (5...8).contains(exif)
            ? CardCenteringSize(width: rawSize.height, height: rawSize.width) : rawSize
    }

    func orientedPoint(fromRaw p: CardCenteringPoint) -> CardCenteringPoint {
        let w = rawSize.width, h = rawSize.height
        switch exif {
        case 2: return .init(x: w - p.x, y: p.y)
        case 3: return .init(x: w - p.x, y: h - p.y)
        case 4: return .init(x: p.x, y: h - p.y)
        case 5: return .init(x: p.y, y: p.x)
        case 6: return .init(x: h - p.y, y: p.x)
        case 7: return .init(x: h - p.y, y: w - p.x)
        case 8: return .init(x: p.y, y: w - p.x)
        default: return p
        }
    }

    func rawPoint(fromOriented p: CardCenteringPoint) -> CardCenteringPoint {
        let inverse = [1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 8, 7: 7, 8: 6][exif] ?? 1
        return CardCenteringRasterOrientation(rawSize: orientedSize, exif: inverse).orientedPoint(fromRaw: p)
    }
}

struct CardCenteringNativeSideEvidence: Codable, Equatable {
    let version: Int
    let frame: String
    let side: String
    let disposition: String
    let reason: String?
    let rawSampleCount: Int
    let acceptedSampleCount: Int
    let spatialCoverage: Double
    let fitResidualNativePixels: Double?
    let rejectedSampleCount: Int
    let alternativeSeparationNativePixels: Double?
    let observedPointsOrientedNative: [CardCenteringPoint]
    let lineCoefficientsOrientedNative: [Double]?
    var samples: [CardCenteringNativeSampleEvidence]? = nil
    /// Native-only local search scale. This is an estimator setting, not an
    /// accuracy bound or independent multi-scale agreement.
    var derivativeRadiusNativePixels: Double? = nil
    var configuration: String? = nil
    var seedSource: String? = nil
    var candidateLines: [CardCenteringNativeLineCandidateEvidence]? = nil
}

struct CardCenteringNativeSampleEvidence: Codable, Equatable {
    let progress: Double
    let pointOrientedNative: CardCenteringPoint?
    let contrastRGB: Double?
    let luminancePolarity: Double?
    let transitionHalfHeightWidthNativePixels: Double?
    let profileBaselineRGB: Double
    let profileMADRGB: Double
    let competingPeakSeparationNativePixels: Double?
    let disposition: String
    var candidatePeaks: [CardCenteringNativePeakEvidence]? = nil
}

struct CardCenteringNativePeakEvidence: Codable, Equatable {
    let normalOffsetNativePixels: Double
    let pointOrientedNative: CardCenteringPoint
    let contrastRGB: Double
}

struct CardCenteringNativeLineCandidateEvidence: Codable, Equatable {
    let seedSource: String
    let lineCoefficientsOrientedNative: [Double]
    let observedSampleCount: Int
    let spatialCoverage: Double
    let fitResidualNativePixels: Double
    let medianContrastRGB: Double
    let rejectionReasons: [String]
}

enum CardCenteringPrecisionSide: String, Codable, CaseIterable, Identifiable {
    case left, top, right, bottom
    var id: String { rawValue }
    var index: Int {
        switch self { case .top: 0; case .right: 1; case .bottom: 2; case .left: 3 }
    }
    var isVertical: Bool { self == .left || self == .right }
    var label: String { rawValue.capitalized }
}

enum CardCenteringPrecisionFrame: String, Codable, CaseIterable, Identifiable {
    case outer, inner
    var id: String { rawValue }
    var label: String { self == .outer ? "Card edge" : "Inner frame" }
}

extension CardCenteringMeasurement {
    func precisionInnerLine(_ side: CardCenteringPrecisionSide) -> (position: Double, angle: Double)? {
        precisionLine(side, frame: .inner)
    }

    func precisionLine(_ side: CardCenteringPrecisionSide, frame: CardCenteringPrecisionFrame) -> (position: Double, angle: Double)? {
        guard let selected = frame == .outer ? geometryOuterQuad : geometryInnerQuad else { return nil }
        let native = coordinateMapping?.nativeQuad(fromWorking: selected) ?? selected
        let p = native.points[side.index], q = native.points[(side.index + 1) % 4]
        var angle = atan2(q.y - p.y, q.x - p.x) * 180 / .pi
        if side.isVertical {
            while angle < 0 { angle += 180 }
            while angle >= 180 { angle -= 180 }
        } else {
            while angle > 90 { angle -= 180 }
            while angle <= -90 { angle += 180 }
        }
        return (side.isVertical ? (p.x + q.x) / 2 : (p.y + q.y) / 2, angle)
    }

    /// Replace one supporting line about its midpoint; adjacent supporting
    /// lines stay fixed. Reject the entire edit rather than clamp/snap it.
    /// Position is native x for a vertical side and native y otherwise.
    @discardableResult
    mutating func setPrecisionInnerSide(_ side: CardCenteringPrecisionSide,
                                       positionNativePixels: Double? = nil,
                                       angleDegrees: Double? = nil) -> Bool {
        setPrecisionSide(side, frame: .inner, positionNativePixels: positionNativePixels, angleDegrees: angleDegrees)
    }

    @discardableResult
    mutating func setPrecisionSide(_ side: CardCenteringPrecisionSide, frame: CardCenteringPrecisionFrame,
                                  positionNativePixels: Double? = nil, angleDegrees: Double? = nil) -> Bool {
        guard let selected = frame == .outer ? geometryOuterQuad : geometryInnerQuad else { return false }
        let native = coordinateMapping?.nativeQuad(fromWorking: selected) ?? selected
        var corners = native.points
        let i = side.index, j = (i + 1) % 4
        let p = corners[i], q = corners[j]
        var midpoint = CardCenteringPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        if let positionNativePixels {
            guard positionNativePixels.isFinite else { return false }
            if side.isVertical { midpoint.x = positionNativePixels } else { midpoint.y = positionNativePixels }
        }
        let angle = angleDegrees.map { $0 * .pi / 180 } ?? atan2(q.y - p.y, q.x - p.x)
        guard angle.isFinite else { return false }
        let direction = CardCenteringPoint(x: cos(angle), y: sin(angle))
        func intersect(_ a: CardCenteringPoint, _ b: CardCenteringPoint) -> CardCenteringPoint? {
            let dx = b.x - a.x, dy = b.y - a.y
            let determinant = direction.x * dy - direction.y * dx
            guard determinant.isFinite, abs(determinant) > 1e-10 else { return nil }
            let t = ((a.x - midpoint.x) * dy - (a.y - midpoint.y) * dx) / determinant
            let value = CardCenteringPoint(x: midpoint.x + t * direction.x, y: midpoint.y + t * direction.y)
            return value.x.isFinite && value.y.isFinite ? value : nil
        }
        guard let start = intersect(corners[(i + 3) % 4], p),
              let end = intersect(q, corners[(i + 2) % 4]) else { return false }
        corners[i] = start; corners[j] = end
        let editedNative = CardCenteringQuad(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3])
        var candidate = self
        let edited = coordinateMapping?.workingQuad(fromNative: editedNative) ?? editedNative
        if frame == .outer {
            candidate.outerQuad = edited
            candidate.outer = edited.projectedEdges
            candidate.rectification = CardCenteringRectification(outerQuad: edited)
        } else {
            candidate.innerQuad = edited
            candidate.inner = edited.projectedEdges
        }
        candidate.usesQuadGeometry = true
        guard candidate.hasValidFrameGeometry else { return false }
        candidate.requireConfirmationAfterManualEditIfNeeded()
        candidate.refreshWarnings()
        self = candidate
        return true
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
    /// Immutable evidence for the automatic proposal, not the person's later
    /// edited geometry and not a calibrated physical accuracy interval.
    var nativeRefinementEvidence: [CardCenteringNativeSideEvidence]? = nil

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
    var canReportRatios: Bool { confidence.state == .confident && hasValidFrameGeometry }
    var isDeclined: Bool { !canReportRatios }
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
    var declineReason: String? {
        hasValidFrameGeometry ? confidence.reason : "Place valid inner guides inside the card edges before confirming both frames."
    }

    var hasValidFrameGeometry: Bool {
        guard imageWidth > 0, imageHeight > 0, let inner = geometryInnerQuad else { return false }
        let outer = geometryOuterQuad
        func cross(_ a: CardCenteringPoint, _ b: CardCenteringPoint, _ p: CardCenteringPoint) -> Double {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        func isConvex(_ quad: CardCenteringQuad) -> Bool {
            let points = quad.points
            guard points.allSatisfy({
                $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.y >= 0
                    && $0.x <= Double(imageWidth) && $0.y <= Double(imageHeight)
            }) else { return false }
            let turns = (0..<4).map { cross(points[$0], points[($0 + 1) % 4], points[($0 + 2) % 4]) }
            // Clockwise winding alone also accepts two inverted axes. Named
            // side midpoints must still run left-to-right and top-to-bottom.
            return turns.allSatisfy { $0 > .ulpOfOne }
                && quad.topLeft.x + quad.bottomLeft.x < quad.topRight.x + quad.bottomRight.x
                && quad.topLeft.y + quad.topRight.y < quad.bottomLeft.y + quad.bottomRight.y
        }
        guard isConvex(outer), isConvex(inner) else { return false }
        if let rectification {
            let coefficients = rectification.coefficients
            guard rectification.isNumericallyValid,
                  rectification.rectifiedQuad(from: outer).points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                  rectification.rectifiedQuad(from: inner).points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
            let denominators = outer.points.map { coefficients[6] * $0.x + coefficients[7] * $0.y + 1 }
            guard denominators.allSatisfy({ $0 > 1e-12 }) || denominators.allSatisfy({ $0 < -1e-12 }) else { return false }
        } else if usesQuadGeometry {
            return false
        }
        let points = outer.points
        let clockwise = cross(points[0], points[1], points[2]) > 0
        guard inner.points.allSatisfy({ point in
            (0..<4).allSatisfy { index in
                let side = cross(points[index], points[(index + 1) % 4], point)
                return clockwise ? side > .ulpOfOne : side < -.ulpOfOne
            }
        }) else { return false }
        let distances = measurementBorderDistances(to: inner)
        return [distances.left, distances.top, distances.right, distances.bottom]
            .allSatisfy { $0.isFinite && $0 > 0 }
    }

    @discardableResult
    mutating func confirmFrames() -> Bool {
        guard hasValidFrameGeometry else { return false }
        confidence.state = .confident
        confidence.innerReferencePresent = true
        confidence.reason = nil
        refreshWarnings()
        return true
    }

    /// Redraws the inner frame with each edge parallel to its card edge in the
    /// rectified card, at that side's measured border distance.
    ///
    /// Detector inner sources fit each edge's slope independently of the card
    /// edge, and a back-template fit can disagree with it by a couple of
    /// degrees. No guide control can change a slope — the steppers translate
    /// an edge and rotation turns the photo beneath both frames — so that
    /// disagreement could never be aligned away. Each border is the distance at
    /// the inner edge's midpoint either way, so the ratios are unchanged.
    mutating func squareInnerFrameToCardEdge() {
        guard usesQuadGeometry, hasValidFrameGeometry,
              let rectification, let current = geometryInnerQuad else { return }
        let border = measurementBorderDistances(to: current)
        let size = rectification.targetSize
        let left = border.left, top = border.top
        let right = size.width - border.right, bottom = size.height - border.bottom
        guard left < right, top < bottom else { return }
        let squared = CardCenteringQuad(
            topLeft: rectification.sourcePoint(fromRectified: CardCenteringPoint(x: left, y: top)),
            topRight: rectification.sourcePoint(fromRectified: CardCenteringPoint(x: right, y: top)),
            bottomRight: rectification.sourcePoint(fromRectified: CardCenteringPoint(x: right, y: bottom)),
            bottomLeft: rectification.sourcePoint(fromRectified: CardCenteringPoint(x: left, y: bottom))
        )
        guard squared.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        innerQuad = squared
        inner = squared.projectedEdges
    }

    mutating func invalidateFrameConfirmationForPhotoRotation() {
        confidence = .manualConfirmationRequired(preserving: confidence,
            reason: "The photo moved beneath the guides. Realign and confirm both frames before reading centering.")
        refreshWarnings()
    }

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

    var leftBorder: Int { Int(exactly: leftBorderDistance.rounded()) ?? 0 }
    var rightBorder: Int { Int(exactly: rightBorderDistance.rounded()) ?? 0 }
    var topBorder: Int { Int(exactly: topBorderDistance.rounded()) ?? 0 }
    var bottomBorder: Int { Int(exactly: bottomBorderDistance.rounded()) ?? 0 }

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
        if !usesQuadGeometry {
            outer[keyPath: keyPath] = value
            outerQuad = .axisAligned(outer)
            requireConfirmationAfterManualEditIfNeeded()
            return
        }
        guard let edited = geometryOuterQuad.movingEdge(keyPath, to: value) else { return }
        // Quad measurements retain both frames and their perspective correction.
        outerQuad = edited
        outer = edited.projectedEdges
        rectification = CardCenteringRectification(outerQuad: edited)
        requireConfirmationAfterManualEditIfNeeded()
    }

    mutating func setManualInnerEdge(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int
    ) {
        if !usesQuadGeometry {
            inner[keyPath: keyPath] = value
            innerQuad = .axisAligned(inner)
            if innerReference == .none { innerReference = .artWindow }
            requireConfirmationAfterManualEditIfNeeded()
            return
        }
        // Without an inner frame, start from the card edge's own lines moved to
        // the positions the steppers show, so a new cyan edge inherits the red
        // edge's angle instead of the image axes.
        let startingQuad = geometryInnerQuad ?? [\CardCenteringEdges.left, \.top, \.right, \.bottom]
            .reduce(geometryOuterQuad) { quad, side in quad.movingEdge(side, to: inner[keyPath: side]) ?? quad }
        guard let edited = startingQuad.movingEdge(keyPath, to: value) else { return }
        innerQuad = edited
        inner = edited.projectedEdges
        if innerReference == .none { innerReference = .artWindow }
        requireConfirmationAfterManualEditIfNeeded()
    }

    private mutating func requireConfirmationAfterManualEditIfNeeded() {
        guard confidence.state != .confident else { return }
        confidence = .manualConfirmationRequired(
            preserving: confidence,
            reason: "Confirm both outer and inner frames before reading centering."
        )
    }

    private static func centeringString(_ first: Double, _ second: Double) -> String {
        let total = first + second
        guard total > 0 else { return "—" }
        return String(format: "%.1f / %.1f", 100 * first / total, 100 * second / total)
    }
}

// MARK: - Direct guide editing

/// One side of a guide frame.
enum CardCenteringSide: String, CaseIterable, Hashable {
    case left, top, right, bottom

    /// Left and right guides run top to bottom.
    var isVertical: Bool { self == .left || self == .right }

    /// The side's position in the quad's clockwise line order.
    fileprivate var clockwiseIndex: Int {
        switch self {
        case .top: 0
        case .right: 1
        case .bottom: 2
        case .left: 3
        }
    }
}

/// One of the eight guide lines: a side of the red card edge or of the cyan
/// inner frame.
struct CardCenteringGuide: Hashable {
    enum Frame: Hashable {
        case outer
        case inner
    }

    var frame: Frame
    var side: CardCenteringSide

    static let all: [CardCenteringGuide] = [Frame.outer, .inner].flatMap { frame in
        CardCenteringSide.allCases.map { CardCenteringGuide(frame: frame, side: $0) }
    }
}

/// An end of a guide in reading order: the top end of a left or right guide
/// and the left end of a top or bottom one is `.start`.
enum CardCenteringGuideEnd: Hashable {
    case start
    case end

    var opposite: CardCenteringGuideEnd { self == .start ? .end : .start }
}

extension CardCenteringQuad {
    /// A side's endpoints in reading order.
    func segment(_ side: CardCenteringSide) -> (start: CardCenteringPoint, end: CardCenteringPoint) {
        switch side {
        case .left: (topLeft, bottomLeft)
        case .top: (topLeft, topRight)
        case .right: (topRight, bottomRight)
        case .bottom: (bottomLeft, bottomRight)
        }
    }

    /// Replaces one side's line with the line through `point` along
    /// `direction`, re-solving that side's two corners against the
    /// neighbouring lines. Nil when the result would collapse a side.
    func replacingLine(
        _ side: CardCenteringSide,
        through point: CardCenteringPoint,
        direction: CardCenteringPoint
    ) -> CardCenteringQuad? {
        let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
        guard length.isFinite, length > 1e-9, point.x.isFinite, point.y.isFinite,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var corners = points
        let index = side.clockwiseIndex
        let previous = (corners[(index + 3) % 4], corners[index])
        let next = (corners[(index + 1) % 4], corners[(index + 2) % 4])
        let replacement = (point, CardCenteringPoint(x: point.x + direction.x, y: point.y + direction.y))
        guard let start = Self.intersection(previous, replacement),
              let end = Self.intersection(replacement, next) else { return nil }
        corners[index] = start
        corners[(index + 1) % 4] = end
        let result = CardCenteringQuad(
            topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3]
        )
        guard [result.topLength, result.rightLength, result.bottomLength, result.leftLength]
            .allSatisfy({ $0.isFinite && $0 > .ulpOfOne }) else { return nil }
        return result
    }

    /// The quad turned about `pivot`, clockwise positive in the image's y-down
    /// coordinates.
    func rotated(by radians: Double, about pivot: CardCenteringPoint) -> CardCenteringQuad {
        let cosine = cos(radians), sine = sin(radians)
        func turn(_ point: CardCenteringPoint) -> CardCenteringPoint {
            let dx = point.x - pivot.x, dy = point.y - pivot.y
            return CardCenteringPoint(x: pivot.x + cosine * dx - sine * dy, y: pivot.y + sine * dx + cosine * dy)
        }
        return CardCenteringQuad(
            topLeft: turn(topLeft), topRight: turn(topRight),
            bottomRight: turn(bottomRight), bottomLeft: turn(bottomLeft)
        )
    }

    private static func intersection(
        _ lhs: (CardCenteringPoint, CardCenteringPoint),
        _ rhs: (CardCenteringPoint, CardCenteringPoint)
    ) -> CardCenteringPoint? {
        let a1 = lhs.1.y - lhs.0.y, b1 = lhs.0.x - lhs.1.x
        let a2 = rhs.1.y - rhs.0.y, b2 = rhs.0.x - rhs.1.x
        let c1 = a1 * lhs.0.x + b1 * lhs.0.y
        let c2 = a2 * rhs.0.x + b2 * rhs.0.y
        let determinant = a1 * b2 - a2 * b1
        guard determinant.isFinite, abs(determinant) > 1e-12 else { return nil }
        let point = CardCenteringPoint(
            x: (c1 * b2 - c2 * b1) / determinant,
            y: (a1 * c2 - a2 * c1) / determinant
        )
        return point.x.isFinite && point.y.isFinite ? point : nil
    }
}

extension CardCenteringMeasurement {
    /// The most the inner frame may tilt against the card edge. Real print
    /// tilt is a fraction of a degree, so anything larger is a mis-drag.
    static let maximumInnerTiltDegrees = 5.0
    /// The most one card-edge side may turn in a single edit.
    static let maximumOuterTurnDegrees = 10.0

    func segment(for guide: CardCenteringGuide) -> (start: CardCenteringPoint, end: CardCenteringPoint)? {
        switch guide.frame {
        case .outer: geometryOuterQuad.segment(guide.side)
        case .inner: geometryInnerQuad?.segment(guide.side)
        }
    }

    func borderDistance(_ side: CardCenteringSide) -> Double {
        switch side {
        case .left: leftBorderDistance
        case .top: topBorderDistance
        case .right: rightBorderDistance
        case .bottom: bottomBorderDistance
        }
    }

    /// The inner frame's tilt against the card edge in the rectified card,
    /// averaged over its four sides; clockwise positive. Zero once the frame
    /// is squared to the card edge.
    var innerTiltDegrees: Double? {
        guard let inner = geometryInnerQuad else { return nil }
        let space = innerEditSpace
        let outer = space?.rectifiedQuad(from: geometryOuterQuad) ?? geometryOuterQuad
        let measured = space?.rectifiedQuad(from: inner) ?? inner
        var total = 0.0
        for side in CardCenteringSide.allCases {
            let card = outer.segment(side), print = measured.segment(side)
            var difference = atan2(print.end.y - print.start.y, print.end.x - print.start.x)
                - atan2(card.end.y - card.start.y, card.end.x - card.start.x)
            while difference > .pi / 2 { difference -= .pi }
            while difference <= -.pi / 2 { difference += .pi }
            total += difference
        }
        let degrees = total / 4 * 180 / .pi
        return degrees.isFinite ? degrees : nil
    }

    /// Slides one guide, keeping its angle, so its line passes through
    /// `point`. Inner sides slide in the rectified card, so a cyan side keeps
    /// its angle to the red one however the photo leans.
    mutating func moveGuide(_ guide: CardCenteringGuide, through point: CardCenteringPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        switch guide.frame {
        case .outer:
            let quad = geometryOuterQuad
            let line = quad.segment(guide.side)
            guard let edited = quad.replacingLine(
                guide.side, through: point, direction: Self.vector(from: line.start, to: line.end)
            ) else { return }
            applyOuterEdit(edited)
        case .inner:
            guard let quad = geometryInnerQuad else { return }
            let space = innerEditSpace
            let working = space?.rectifiedQuad(from: quad) ?? quad
            let line = working.segment(guide.side)
            guard let edited = working.replacingLine(
                guide.side,
                through: space?.rectifiedPoint(from: point) ?? point,
                direction: Self.vector(from: line.start, to: line.end)
            ) else { return }
            applyInnerEdit(space?.sourceQuad(fromRectified: edited) ?? edited)
        }
    }

    /// Moves one guide by `pixels` along the image axis it controls: x for the
    /// left and right sides, y for the top and bottom.
    mutating func nudgeGuide(_ guide: CardCenteringGuide, by pixels: Double) {
        guard pixels.isFinite, let line = segment(for: guide) else { return }
        let middle = CardCenteringPoint(x: (line.start.x + line.end.x) / 2, y: (line.start.y + line.end.y) / 2)
        moveGuide(guide, through: guide.side.isVertical
            ? CardCenteringPoint(x: middle.x + pixels, y: middle.y)
            : CardCenteringPoint(x: middle.x, y: middle.y + pixels))
    }

    /// Turns one guide about its `fixed` end, clockwise positive.
    ///
    /// A card-edge side turns on its own, since perspective gives every side
    /// of the photographed card its own angle. The inner frame turns as one
    /// rectangle in the rectified card, because a print is tilted as a piece;
    /// its tilt is held within `maximumInnerTiltDegrees`.
    mutating func turnGuide(
        _ guide: CardCenteringGuide,
        about fixed: CardCenteringGuideEnd,
        byDegrees degrees: Double
    ) {
        guard degrees.isFinite, let line = segment(for: guide) else { return }
        switch guide.frame {
        case .outer:
            let limit = Self.maximumOuterTurnDegrees
            let radians = min(limit, max(-limit, degrees)) * .pi / 180
            let direction = Self.vector(from: line.start, to: line.end)
            let turned = CardCenteringPoint(
                x: direction.x * cos(radians) - direction.y * sin(radians),
                y: direction.x * sin(radians) + direction.y * cos(radians)
            )
            guard let edited = geometryOuterQuad.replacingLine(
                guide.side, through: fixed == .start ? line.start : line.end, direction: turned
            ) else { return }
            applyOuterEdit(edited)
        case .inner:
            guard let quad = geometryInnerQuad else { return }
            let space = innerEditSpace
            let working = space?.rectifiedQuad(from: quad) ?? quad
            let workingLine = working.segment(guide.side)
            let current = innerTiltDegrees ?? 0
            let limit = Self.maximumInnerTiltDegrees
            let target = min(limit, max(-limit, current + degrees))
            let turned = working.rotated(
                by: (target - current) * .pi / 180,
                about: fixed == .start ? workingLine.start : workingLine.end
            )
            applyInnerEdit(space?.sourceQuad(fromRectified: turned) ?? turned)
        }
    }

    /// Swings one end of a guide toward `point` while its other end stays put.
    mutating func pivotGuide(
        _ guide: CardCenteringGuide,
        movingEnd: CardCenteringGuideEnd,
        toward point: CardCenteringPoint
    ) {
        guard point.x.isFinite, point.y.isFinite, let line = segment(for: guide) else { return }
        // Measure the swing in the space the guide turns in.
        let space = guide.frame == .inner ? innerEditSpace : nil
        func working(_ point: CardCenteringPoint) -> CardCenteringPoint {
            space?.rectifiedPoint(from: point) ?? point
        }
        let pivot = working(movingEnd == .start ? line.end : line.start)
        let moving = working(movingEnd == .start ? line.start : line.end)
        let target = working(point)
        let reach = Self.vector(from: pivot, to: target)
        guard (reach.x * reach.x + reach.y * reach.y).squareRoot() > 1 else { return }
        var radians = atan2(reach.y, reach.x) - atan2(moving.y - pivot.y, moving.x - pivot.x)
        while radians > .pi { radians -= 2 * .pi }
        while radians <= -.pi { radians += 2 * .pi }
        turnGuide(guide, about: movingEnd.opposite, byDegrees: radians * 180 / .pi)
    }

    /// Starts an inner frame where none was found: inset from each card edge
    /// by a typical printed border and square to it in the rectified card.
    mutating func placeDefaultInnerFrame(insetFraction: Double = 0.05) {
        guard geometryInnerQuad == nil, insetFraction > 0, insetFraction < 0.25 else { return }
        if usesQuadGeometry {
            guard let space = innerEditSpace else { return }
            let size = space.targetSize
            let inset = min(size.width, size.height) * insetFraction
            let placed = space.sourceQuad(fromRectified: CardCenteringQuad(
                topLeft: CardCenteringPoint(x: inset, y: inset),
                topRight: CardCenteringPoint(x: size.width - inset, y: inset),
                bottomRight: CardCenteringPoint(x: size.width - inset, y: size.height - inset),
                bottomLeft: CardCenteringPoint(x: inset, y: size.height - inset)
            ))
            guard placed.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
            innerQuad = placed
            inner = placed.projectedEdges
        } else {
            let inset = Int((Double(min(outer.right - outer.left, outer.bottom - outer.top)) * insetFraction).rounded())
            inner = CardCenteringEdges(
                left: outer.left + inset, top: outer.top + inset,
                right: outer.right - inset, bottom: outer.bottom - inset
            )
            innerQuad = .axisAligned(inner)
        }
        innerReference = .artWindow
        requireConfirmationAfterManualEditIfNeeded()
    }

    /// The rectified card the inner frame is edited in, when the card edge
    /// can be rectified.
    private var innerEditSpace: CardCenteringRectification? {
        guard usesQuadGeometry, let rectification, rectification.isNumericallyValid else { return nil }
        return rectification
    }

    private mutating func applyOuterEdit(_ edited: CardCenteringQuad) {
        guard edited.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        if usesQuadGeometry {
            outerQuad = edited
            outer = edited.projectedEdges
            rectification = CardCenteringRectification(outerQuad: edited)
        } else {
            outer = edited.projectedEdges
            outerQuad = .axisAligned(outer)
        }
        requireConfirmationAfterManualEditIfNeeded()
    }

    private mutating func applyInnerEdit(_ edited: CardCenteringQuad) {
        guard edited.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        if usesQuadGeometry {
            innerQuad = edited
            inner = edited.projectedEdges
        } else {
            inner = edited.projectedEdges
            innerQuad = .axisAligned(inner)
        }
        requireConfirmationAfterManualEditIfNeeded()
    }

    private static func vector(from start: CardCenteringPoint, to end: CardCenteringPoint) -> CardCenteringPoint {
        CardCenteringPoint(x: end.x - start.x, y: end.y - start.y)
    }
}
