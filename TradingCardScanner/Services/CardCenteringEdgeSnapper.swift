import CoreGraphics
import Foundation

/// A grayscale copy of the centering photo for edge searches while a guide is
/// dragged. It is built once per photo, off the main thread, and capped in
/// size so a search stays well inside one frame.
struct CardCenteringLumaField: @unchecked Sendable {
    let width: Int
    let height: Int
    /// Field pixels per measurement pixel.
    let scale: Double
    let values: [UInt8]

    init?(image: CGImage, measurementSize: CardCenteringSize, maximumPixels: Double = 6_000_000) {
        let area = measurementSize.width * measurementSize.height
        guard measurementSize.width >= 2, measurementSize.height >= 2, area.isFinite else { return nil }
        let scale = min(1, (maximumPixels / area).squareRoot())
        let width = max(2, Int((measurementSize.width * scale).rounded()))
        let height = max(2, Int((measurementSize.height * scale).rounded()))
        var values = [UInt8](repeating: 0, count: width * height)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.scale = Double(width) / measurementSize.width
        self.values = values
    }

    /// Bilinear luma at a measurement-space point, or nil outside the photo.
    func luma(at point: CardCenteringPoint) -> Double? {
        let x = point.x * scale - 0.5, y = point.y * scale - 0.5
        guard x.isFinite, y.isFinite, x >= 0, y >= 0,
              x < Double(width - 1), y < Double(height - 1) else { return nil }
        let column = Int(x), row = Int(y)
        let fx = x - Double(column), fy = y - Double(row)
        let index = row * width + column
        let top = Double(values[index]) * (1 - fx) + Double(values[index + 1]) * fx
        let bottom = Double(values[index + width]) * (1 - fx) + Double(values[index + width + 1]) * fx
        return top * (1 - fy) + bottom * fy
    }
}

/// Finds the straight edge in the photo that a dragged guide should rest on.
///
/// The search slides a copy of the guide across a narrow band around the
/// finger and scores each position by the luma step across it, summed with
/// its sign along the guide. A printed border or a cut edge changes
/// brightness the same way along its whole length, so most of its steps
/// agree; artwork and texture step both ways and are rejected. Nearer
/// positions are preferred, so the guide settles on the edge under the
/// finger rather than a stronger one further away.
///
/// A slide also tries the guide a few pixels off its own angle at each end:
/// over a long side a fraction of a degree would otherwise smear the edge
/// across several positions and hide it. The guide keeps its angle and rests
/// where it crosses the edge at its middle.
enum CardCenteringEdgeSnapper {
    struct Snap: Equatable {
        /// Distance to move the guide along `normal`, in measurement pixels.
        /// For a pivot this is how far the swinging end moves.
        let offset: Double
        /// Mean luma step across the edge, 0–255.
        let contrast: Double
    }

    /// The weakest edge worth snapping to, as a mean luma step per pixel.
    static let minimumContrast = 9.0
    /// How much of the step along the guide must agree in direction:
    /// `|Σ step| / Σ |step|`. A straight edge is near 1; texture is near 0.
    static let minimumCoherence = 0.6
    /// How far off the guide's angle a slide searches, as the shift at each
    /// end in field pixels.
    static let endTolerances: [Double] = [-3, -1.5, 0, 1.5, 3]
    /// Off-angle tries give texture more chances to line up by luck, so they
    /// must agree more closely. Along a real straight edge nearly every step
    /// has the same sign.
    static let tiltedCoherence = 0.85

    /// - Parameters:
    ///   - start: The guide's first end, in measurement pixels, already at the
    ///     finger. It stays fixed when `pivotsOnStart` is true.
    ///   - end: The guide's other end.
    ///   - pivotsOnStart: Whether only `end` moves, as when an end is swung.
    ///   - radius: How far either side of the finger to search, in
    ///     measurement pixels.
    ///   - photoRotationDegrees: The person's display rotation. The guides
    ///     stay put while the photo turns beneath them, so a guide point is
    ///     turned back into photo pixels before sampling.
    ///   - imageSize: The measurement image, whose centre the photo turns on.
    ///   - preferredOffset: The offset of the edge the guide rests on now, if
    ///     any. While that edge still qualifies the guide stays on it, so it
    ///     cannot hop to another edge until the finger leaves this one.
    static func snap(
        start: CardCenteringPoint,
        end: CardCenteringPoint,
        pivotsOnStart: Bool,
        radius: Double,
        field: CardCenteringLumaField,
        photoRotationDegrees: Double,
        imageSize: CardCenteringSize,
        preferredOffset: Double? = nil
    ) -> Snap? {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length.isFinite, length * field.scale >= 12, radius.isFinite, radius > 0 else { return nil }
        let normal = CardCenteringPoint(x: -dy / length, y: dx / length)

        let radians = -photoRotationDegrees * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let center = CardCenteringPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        func photoLuma(_ x: Double, _ y: Double) -> Double? {
            let rx = x - center.x, ry = y - center.y
            return field.luma(at: CardCenteringPoint(
                x: center.x + cosine * rx - sine * ry,
                y: center.y + sine * rx + cosine * ry
            ))
        }

        // Sample the stretch of the guide the finger controls: the middle for
        // a slide, the swinging half for a pivot. Corners are left out, where
        // the neighbouring side's edge would add its own step.
        let fractions: [Double] = {
            let range = pivotsOnStart ? (0.5, 0.94) : (0.12, 0.88)
            let count = min(48, max(12, Int(length * field.scale / 6)))
            return (0..<count).map { range.0 + (range.1 - range.0) * Double($0) / Double(count - 1) }
        }()
        let fieldPixel = 1 / field.scale
        // Probing half a field pixel either side measures the step across one
        // pixel, which peaks at the steepest point of the edge.
        let probe = fieldPixel / 2
        let step = fieldPixel / 2
        let steps = min(240, Int((radius / step).rounded()))
        guard steps >= 2 else { return nil }

        let tolerances = pivotsOnStart ? [0] : endTolerances.map { $0 * fieldPixel }
        var scores = [Double](repeating: 0, count: 2 * steps + 1)
        for index in scores.indices {
            let offset = Double(index - steps) * step
            for tolerance in tolerances {
                var sum = 0.0, magnitude = 0.0, count = 0
                for fraction in fractions {
                    let shift = pivotsOnStart ? offset * fraction : offset + tolerance * (2 * fraction - 1)
                    let x = start.x + dx * fraction + normal.x * shift
                    let y = start.y + dy * fraction + normal.y * shift
                    guard let ahead = photoLuma(x + normal.x * probe, y + normal.y * probe),
                          let behind = photoLuma(x - normal.x * probe, y - normal.y * probe) else { continue }
                    sum += ahead - behind
                    magnitude += abs(ahead - behind)
                    count += 1
                }
                guard count * 10 >= fractions.count * 7, magnitude > 0,
                      abs(sum) / magnitude >= (tolerance == 0 ? minimumCoherence : tiltedCoherence) else { continue }
                scores[index] = max(scores[index], abs(sum) / Double(count))
            }
        }

        let median = scores.sorted()[scores.count / 2]
        func qualifies(_ index: Int) -> Bool {
            scores[index] >= minimumContrast && scores[index] >= median * 2
        }
        let held = preferredOffset.flatMap { preferred -> Int? in
            let near = scores.indices.filter { abs(Double($0 - steps) * step - preferred) <= 1.5 * fieldPixel }
            return near.max(by: { scores[$0] < scores[$1] }).flatMap { qualifies($0) ? $0 : nil }
        }
        let weighted = scores.indices.map { index -> Double in
            let distance = Double(index - steps) / Double(steps)
            return scores[index] * (1 - 0.45 * distance * distance)
        }
        guard let best = held ?? weighted.indices.max(by: { weighted[$0] < weighted[$1] }),
              qualifies(best) else { return nil }
        let contrast = scores[best]

        // Refine to a fraction of a step from the neighbouring scores.
        var refinement = 0.0
        if best > 0, best < scores.count - 1 {
            let left = scores[best - 1], right = scores[best + 1]
            let curvature = left - 2 * contrast + right
            if curvature < -1e-9 {
                refinement = min(0.5, max(-0.5, 0.5 * (left - right) / curvature))
            }
        }
        return Snap(offset: (Double(best - steps) + refinement) * step, contrast: contrast)
    }
}
