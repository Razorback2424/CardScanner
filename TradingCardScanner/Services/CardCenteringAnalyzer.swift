import CoreGraphics
import UIKit

enum CardCenteringAnalyzerError: LocalizedError {
    case unreadableImage
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "The selected image could not be opened."
        case .renderFailed: "The image could not be prepared for measurement."
        }
    }
}

struct CardCenteringAnalysis {
    let image: UIImage
    let measurement: CardCenteringMeasurement
}

/// Native port of the tuned Python centering detector. It scores long color
/// transitions instead of isolated details, then uses the top border as the
/// reference when choosing plausible left, right, and bottom frame edges.
enum CardCenteringAnalyzer {
    private struct Pixel {
        let l: Float
        let a: Float
        let b: Float
    }

    private struct Candidate {
        let position: Int
        let strength: Float
    }

    private struct CandidateSet {
        let candidates: [Candidate]
        let baseline: Float
    }

    static func analyze(_ data: Data, rotationDegrees: Double = 0) throws -> CardCenteringAnalysis {
        guard let source = UIImage(data: data), let prepared = prepare(source, rotationDegrees: rotationDegrees) else {
            throw CardCenteringAnalyzerError.unreadableImage
        }
        let pixels = try pixels(from: prepared)
        let width = Int(prepared.size.width * prepared.scale)
        let height = Int(prepared.size.height * prepared.scale)
        guard width > 20, height > 20 else { throw CardCenteringAnalyzerError.renderFailed }

        let lab = pixels.map(rgbToLab)
        var gx = [Float](repeating: 0, count: height * (width - 1))
        var gy = [Float](repeating: 0, count: (height - 1) * width)

        for y in 0..<height {
            for x in 0..<(width - 1) {
                gx[y * (width - 1) + x] = distance(lab[y * width + x], lab[y * width + x + 1])
            }
        }
        for y in 0..<(height - 1) {
            for x in 0..<width {
                gy[y * width + x] = distance(lab[y * width + x], lab[(y + 1) * width + x])
            }
        }

        let yRange = roundedRange(0.10, 0.90, length: height)
        let xRange = roundedRange(0.18, 0.82, length: width)
        let outerX = max(20, Int((Double(width) * 0.22).rounded()))
        let outerY = max(20, Int((Double(height) * 0.22).rounded()))

        let leftOuterSet = candidates(verticalScores(gx, width: width, height: height, xRange: 0..<outerX, yRange: yRange), offset: 0)
        let rightStart = max(0, width - outerX - 1)
        let rightOuterSet = candidates(verticalScores(gx, width: width, height: height, xRange: rightStart..<(width - 1), yRange: yRange), offset: rightStart)
        let topOuterSet = candidates(horizontalScores(gy, width: width, height: height, yRange: 0..<outerY, xRange: xRange), offset: 0)
        let bottomStart = max(0, height - outerY - 1)
        let bottomOuterSet = candidates(horizontalScores(gy, width: width, height: height, yRange: bottomStart..<(height - 1), xRange: xRange), offset: bottomStart)

        let outer = CardCenteringEdges(
            left: leftOuterSet.candidates.first!.position,
            top: topOuterSet.candidates.first!.position,
            right: rightOuterSet.candidates.last!.position,
            bottom: bottomOuterSet.candidates.last!.position
        )

        let cardWidth = max(1, outer.right - outer.left)
        let cardHeight = max(1, outer.bottom - outer.top)
        let minX = max(4, Int((Double(cardWidth) * 0.01).rounded()))
        let maxX = max(minX + 8, Int((Double(cardWidth) * 0.18).rounded()))
        let minY = max(4, Int((Double(cardHeight) * 0.01).rounded()))
        let maxY = max(minY + 8, Int((Double(cardHeight) * 0.18).rounded()))

        let leftStart = clamped(outer.left + minX, 0, width - 2)
        let leftEnd = clamped(outer.left + maxX, leftStart + 1, width - 1)
        let rightStartInner = clamped(outer.right - maxX, 0, width - 2)
        let rightEndInner = clamped(outer.right - minX, rightStartInner + 1, width - 1)
        let topStart = clamped(outer.top + minY, 0, height - 2)
        let topEnd = clamped(outer.top + maxY, topStart + 1, height - 1)
        let bottomStartInner = clamped(outer.bottom - maxY, 0, height - 2)
        let bottomEndInner = clamped(outer.bottom - minY, bottomStartInner + 1, height - 1)

        let innerSets: [Side: CandidateSet] = [
            .left: candidates(verticalScores(gx, width: width, height: height, xRange: leftStart..<leftEnd, yRange: yRange), offset: leftStart, madMultiplier: 1.1),
            .right: candidates(verticalScores(gx, width: width, height: height, xRange: rightStartInner..<rightEndInner, yRange: yRange), offset: rightStartInner, madMultiplier: 1.1),
            .top: candidates(horizontalScores(gy, width: width, height: height, yRange: topStart..<topEnd, xRange: xRange), offset: topStart, madMultiplier: 1.1),
            .bottom: candidates(horizontalScores(gy, width: width, height: height, yRange: bottomStartInner..<bottomEndInner, xRange: xRange), offset: bottomStartInner, madMultiplier: 1.1)
        ]

        let firstPass: [Side: Candidate] = [
            .left: innerSets[.left]!.candidates.first!,
            .right: innerSets[.right]!.candidates.last!,
            .top: innerSets[.top]!.candidates.first!,
            .bottom: innerSets[.bottom]!.candidates.last!
        ]
        let firstBorders = Dictionary(uniqueKeysWithValues: Side.allCases.map {
            ($0, border(for: $0, position: firstPass[$0]!.position, outer: outer))
        })
        let topSet = innerSets[.top]!
        let topConfidence = firstPass[.top]!.strength / max(topSet.baseline, 0.000_001)
        let topBorder = firstBorders[.top]!

        var chosen: [Side: Candidate] = [:]
        for side in Side.allCases {
            let peerBorders = firstBorders.filter { $0.key != side && $0.value > 0 }.map(\.value)
            let expected = side != .top && topBorder > 0 && topConfidence >= 3
                ? Double(topBorder)
                : median(peerBorders.map(Double.init))
            chosen[side] = chooseInner(side: side, set: innerSets[side]!, outer: outer, expectedBorder: expected)
        }

        let inner = CardCenteringEdges(
            left: chosen[.left]!.position,
            top: chosen[.top]!.position,
            right: chosen[.right]!.position,
            bottom: chosen[.bottom]!.position
        )
        var measurement = CardCenteringMeasurement(
            imageWidth: width,
            imageHeight: height,
            outer: outer,
            inner: inner,
            warnings: []
        )
        measurement.refreshWarnings()
        return CardCenteringAnalysis(image: prepared, measurement: measurement)
    }

    private enum Side: CaseIterable, Hashable {
        case left, right, top, bottom
    }

    private static func prepare(_ image: UIImage, rotationDegrees: Double) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        let maxDimension: CGFloat = 1_200
        let scale = min(1, maxDimension / max(originalWidth, originalHeight))
        let size = CGSize(width: originalWidth * scale, height: originalHeight * scale)
        let radians = CGFloat(rotationDegrees * .pi / 180)
        let rotatedBounds = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: radians)).standardized

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: rotatedBounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rotatedBounds.size))
            context.cgContext.translateBy(x: rotatedBounds.width / 2, y: rotatedBounds.height / 2)
            context.cgContext.rotate(by: radians)
            image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }

    private static func pixels(from image: UIImage) throws -> [(Float, Float, Float)] {
        guard let cgImage = image.cgImage else { throw CardCenteringAnalyzerError.renderFailed }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CardCenteringAnalyzerError.renderFailed }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var result: [(Float, Float, Float)] = []
        result.reserveCapacity(width * height)
        var index = 0
        while index < bytes.count {
            let red = Float(bytes[index]) / 255
            let green = Float(bytes[index + 1]) / 255
            let blue = Float(bytes[index + 2]) / 255
            result.append((red, green, blue))
            index += 4
        }
        return result
    }

    private static func rgbToLab(_ rgb: (Float, Float, Float)) -> Pixel {
        func linear(_ value: Float) -> Float {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(rgb.0), g = linear(rgb.1), b = linear(rgb.2)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ value: Float) -> Float {
            value > 0.008856 ? pow(value, 1 / 3) : 7.787 * value + 16 / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return Pixel(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    private static func distance(_ lhs: Pixel, _ rhs: Pixel) -> Float {
        let l = lhs.l - rhs.l, a = lhs.a - rhs.a, b = lhs.b - rhs.b
        return sqrt(l * l + a * a + b * b)
    }

    private static func verticalScores(_ gradient: [Float], width: Int, height: Int, xRange: Range<Int>, yRange: Range<Int>) -> [Float] {
        let gradientWidth = width - 1
        return xRange.map { x in
            var total: Float = 0
            for y in yRange { total += gradient[y * gradientWidth + x] }
            return total / Float(max(1, yRange.count))
        }
    }

    private static func horizontalScores(_ gradient: [Float], width: Int, height: Int, yRange: Range<Int>, xRange: Range<Int>) -> [Float] {
        yRange.map { y in
            var total: Float = 0
            for x in xRange { total += gradient[y * width + x] }
            return total / Float(max(1, xRange.count))
        }
    }

    private static func candidates(_ scores: [Float], offset: Int, madMultiplier: Float = 1.2) -> CandidateSet {
        guard !scores.isEmpty else { return CandidateSet(candidates: [Candidate(position: offset, strength: 0)], baseline: 0) }
        let smoothed = scores.indices.map { index -> Float in
            let range = max(0, index - 2)...min(scores.count - 1, index + 2)
            return range.reduce(0) { $0 + scores[$1] } / Float(range.count)
        }
        let baseline = median(smoothed)
        let mad = median(smoothed.map { abs($0 - baseline) })
        let maximum = smoothed.max() ?? 0
        let threshold = max(baseline + madMultiplier * max(mad, 0.000_001), 0.12 * maximum)
        var found: [Int: Float] = [:]

        for index in smoothed.indices {
            let left = index == 0 ? -Float.infinity : smoothed[index - 1]
            let right = index == smoothed.count - 1 ? -Float.infinity : smoothed[index + 1]
            guard smoothed[index] >= left, smoothed[index] >= right, smoothed[index] >= threshold else { continue }
            let refinement = max(0, index - 2)...min(scores.count - 1, index + 2)
            let rawIndex = refinement.max(by: { scores[$0] < scores[$1] }) ?? index
            let position = offset + rawIndex
            found[position] = max(found[position] ?? 0, scores[rawIndex])
        }
        if found.isEmpty, let strongest = scores.indices.max(by: { scores[$0] < scores[$1] }) {
            found[offset + strongest] = scores[strongest]
        }
        return CandidateSet(
            candidates: found.map { Candidate(position: $0.key, strength: $0.value) }.sorted { $0.position < $1.position },
            baseline: baseline
        )
    }

    private static func chooseInner(side: Side, set: CandidateSet, outer: CardCenteringEdges, expectedBorder: Double) -> Candidate {
        let strongest = max(set.candidates.map(\.strength).max() ?? 0, 0.000_001)
        let expected = max(4, expectedBorder)
        func score(_ candidate: Candidate) -> Double {
            let width = border(for: side, position: candidate.position, outer: outer)
            guard width > 0 else { return -Double.greatestFiniteMagnitude }
            let strength = Double(candidate.strength / strongest)
            let distance = abs(Double(width) - expected) / expected
            return strength - 0.8 * distance
        }
        return set.candidates.max { lhs, rhs in
            score(lhs) < score(rhs)
        } ?? set.candidates[0]
    }

    private static func border(for side: Side, position: Int, outer: CardCenteringEdges) -> Int {
        switch side {
        case .left: position - outer.left
        case .right: outer.right - position
        case .top: position - outer.top
        case .bottom: outer.bottom - position
        }
    }

    private static func roundedRange(_ start: Double, _ end: Double, length: Int) -> Range<Int> {
        let lower = clamped(Int((Double(length) * start).rounded()), 0, length - 1)
        let upper = clamped(Int((Double(length) * end).rounded()), lower + 1, length)
        return lower..<upper
    }

    private static func clamped(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func median<T: BinaryFloatingPoint>(_ values: [T]) -> T {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
