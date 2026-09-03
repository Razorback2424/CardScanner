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
    /// The rotation the measurement was taken at. Non-zero when the analyzer
    /// straightened the card itself, so the screen's rotation control can show
    /// what was applied instead of claiming zero.
    var appliedRotationDegrees: Double = 0
}

/// Native port of the tuned Python centering detector. It scores long color
/// transitions instead of isolated details, separates the physical card from
/// a scanner background, then uses the top border as the reference when
/// choosing plausible left, right, and bottom frame edges.
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
    }

    /// Skew below this is left alone: it is within the noise of the edge fit,
    /// and re-rendering costs a resample for no measurable gain.
    private static let minimumCorrectableSkew = 0.35
    /// Beyond this the card is not merely skewed, and a blind rotation would be
    /// a guess. The measurement is still returned, at the given rotation.
    private static let maximumCorrectableSkew = 25.0

    static func analyze(_ data: Data, rotationDegrees: Double = 0) throws -> CardCenteringAnalysis {
        // Only an automatic pass may straighten the card. Once the person has
        // touched the rotation control, that value is the answer.
        try analyze(data, rotationDegrees: rotationDegrees, correctingSkew: rotationDegrees == 0)
    }

    private static func analyze(
        _ data: Data,
        rotationDegrees: Double,
        correctingSkew: Bool,
        padding: UIColor? = nil
    ) throws -> CardCenteringAnalysis {
        guard let source = UIImage(data: data),
              let prepared = prepare(
                  source,
                  rotationDegrees: rotationDegrees,
                  padding: padding ?? .white
              ) else {
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

        let xRange = roundedRange(0.18, 0.82, length: width)
        let outerX = max(20, Int((Double(width) * 0.22).rounded()))
        let outerY = max(20, Int((Double(height) * 0.22).rounded()))

        let topOuterSet = candidates(horizontalScores(gy, width: width, height: height, yRange: 0..<outerY, xRange: xRange), offset: 0)
        let bottomStart = max(0, height - outerY - 1)
        let bottomOuterSet = candidates(horizontalScores(gy, width: width, height: height, yRange: bottomStart..<(height - 1), xRange: xRange), offset: bottomStart)
        let outerTop = topOuterSet.candidates.first!.position
        let outerBottom = bottomOuterSet.candidates.last!.position

        // Measure the vertical edges only along the straight body of the card.
        // This avoids rounded corners and prevents scanner-bed marks above or
        // below the card from looking like full-height card edges.
        let detectedHeight = max(1, outerBottom - outerTop)
        let verticalInset = max(2, Int((Double(detectedHeight) * 0.08).rounded()))
        let yStart = clamped(outerTop + verticalInset, 0, height - 1)
        let yEnd = clamped(outerBottom - verticalInset, yStart + 1, height)
        let yRange = yStart..<yEnd

        // On a scanner, the physical card is one continuous foreground region.
        // Detect that silhouette before looking at print transitions; artwork
        // and the edge of the scan can otherwise form a convincing false pair.
        let leftOuterSet = candidates(
            verticalScores(gx, width: width, height: height, xRange: 0..<outerX, yRange: yRange),
            offset: 0
        )
        let rightStart = max(0, width - outerX - 1)
        let rightOuterSet = candidates(
            verticalScores(gx, width: width, height: height, xRange: rightStart..<(width - 1), yRange: yRange),
            offset: rightStart
        )
        let silhouette = verticalSilhouetteEdges(
            lab: lab,
            width: width,
            height: height,
            yRange: yRange,
            cardHeight: detectedHeight
        )

        // The card's own outline, when it can be found, outranks every gradient
        // heuristic above.
        //
        // Those heuristics only look for the outer edges inside the outer 22% of
        // the *image*, and take the most extreme peak they find there. Both
        // assumptions fail on an ordinary photo: a card occupying the middle
        // 40% of the frame has its top edge at 30%, outside the band entirely,
        // so the scan finds nothing above threshold and falls back to the
        // strongest index in a strip of pure background — which is noise. And a
        // pale border against a pale background produces an outer edge weaker
        // than the border-to-artwork edge just inside it, so the first peak past
        // the threshold is the *inner* edge and every measurement downstream is
        // taken from the wrong baseline.
        //
        // Neither failure is visible in the result: the numbers stay
        // self-consistent, so `refreshWarnings` reports nothing and the screen
        // states a wrong centering ratio with confidence.
        let outline = cardOutline(lab: lab, width: width, height: height)
        var notes: [String] = []
        if outline == nil {
            // The gradient scan below is a guess in exactly the conditions that
            // defeat the outline: a card that does not stand out from what it is
            // lying on, or one bled to the edges of the frame. Say so, rather
            // than letting a guess wear the same face as a measurement.
            notes.append("The card outline could not be found automatically — check the outer guides before reading the result.")
        }

        // Inner edges are found by averaging the gradient down whole columns
        // and across whole rows, so a skewed card smears its border transition
        // over as many pixels as the card drifts — about 22 on a 680px card at
        // two degrees. There is no peak left to find, and the border prior then
        // settles the answer on whatever narrow candidate is nearest. Rotating
        // first is what makes the rest of this measurable, and it is the manual
        // step this screen was making people perform by hand.
        if correctingSkew,
           let skew = outline?.skewDegrees,
           abs(skew) >= minimumCorrectableSkew,
           abs(skew) <= maximumCorrectableSkew {
            return try analyze(
                data,
                rotationDegrees: -skew,
                correctingSkew: false,
                // Measured from this unrotated pass, where there are no corner
                // wedges to contaminate it.
                padding: borderColor(pixels: pixels, width: width, height: height)
            )
        }

        // Past the correctable range this is no longer a lean to be taken out;
        // it is a photo taken at an angle, and rotating by a fitted number would
        // be a guess. Rotation on this screen is a display adjustment and does
        // not re-run detection, so the person has to straighten the source.
        if let skew = outline?.skewDegrees, abs(skew) > maximumCorrectableSkew {
            notes.append("The card looks strongly rotated. Straighten the photo and load it again for an accurate reading.")
        }

        let outer = outline?.edges
            ?? CardCenteringEdges(
                left: silhouette?.left ?? leftOuterSet.candidates.first!.position,
                top: outerTop,
                right: silhouette?.right ?? rightOuterSet.candidates.last!.position,
                bottom: outerBottom
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

        // Each side is chosen on its own evidence.
        //
        // This used to score candidates by how close their border width was to
        // the *other* sides' — the top border specifically, when the top looked
        // confident. That prior assumes the four borders are alike, which is
        // the one thing a centering tool may not assume: a miscut card has
        // unequal borders by definition, and the prior pulled every reading
        // back toward the card being well centred. It failed hardest exactly
        // where the measurement matters most. On a card with a thin top border
        // and a banner just inside the artwork, the peer median sat nearer the
        // banner than the truth and the top border read 49px instead of 15.
        let searchDepths: [Side: Int] = [.left: maxX, .right: maxX, .top: maxY, .bottom: maxY]
        var chosen: [Side: Int] = [:]
        for side in Side.allCases {
            let depth = searchDepths[side] ?? maxX
            // Where the border colour stops is the measurement. Gradient
            // strength only stands in for it, and stands in badly whenever the
            // artwork behind the border is louder than the border itself — a
            // black-bordered card on dark art has a faint outer transition and
            // a brilliant banner a few pixels further in, and the loudest edge
            // is then the wrong one by thirty pixels.
            let minimum = side == .left || side == .right ? minX : minY
            chosen[side] = borderEnd(
                side: side,
                lab: lab,
                width: width,
                height: height,
                outer: outer,
                minimum: minimum,
                maximum: depth
            ) ?? chooseInner(
                side: side,
                set: innerSets[side]!,
                outer: outer
            ).position
        }

        let inner = CardCenteringEdges(
            left: chosen[.left]!,
            top: chosen[.top]!,
            right: chosen[.right]!,
            bottom: chosen[.bottom]!
        )
        // A border that stopped at the very first pixel searched, or ran the
        // whole depth without stopping, is not a border that was found — it is
        // the search hitting its own limits. That happens when the outer edges
        // are wrong, most notably on a card bled to the frame with no
        // surrounding surface to recognise it against, where the outline lands
        // on the artwork and the "borders" are measured inside the picture.
        //
        // Checked as one condition rather than diagnosed case by case: whatever
        // the cause, a reading pinned to the end of its own range is one to look
        // at before trusting. A genuinely extreme miscut trips it too, and that
        // is the right outcome.
        let pinned = [
            (inner.left - outer.left, minX, maxX),
            (outer.right - inner.right, minX, maxX),
            (inner.top - outer.top, minY, maxY),
            (outer.bottom - inner.bottom, minY, maxY)
        ].contains { border, lower, upper in border <= lower || border >= upper }
        if pinned, notes.isEmpty {
            notes.append("The border edges could not be followed confidently — check all four guides before reading the result.")
        }

        var measurement = CardCenteringMeasurement(
            imageWidth: width,
            imageHeight: height,
            outer: outer,
            inner: inner,
            warnings: [],
            detectionNotes: notes
        )
        measurement.refreshWarnings()
        return CardCenteringAnalysis(
            image: prepared,
            measurement: measurement,
            appliedRotationDegrees: rotationDegrees
        )
    }

    private enum Side: CaseIterable, Hashable {
        case left, right, top, bottom
    }

    private static func prepare(
        _ image: UIImage,
        rotationDegrees: Double,
        padding: UIColor
    ) -> UIImage? {
        guard image.cgImage != nil else { return nil }
        // Camera photos commonly carry their portrait rotation in
        // `imageOrientation` while the CGImage remains landscape. Using the raw
        // CGImage dimensions here and then drawing the oriented UIImage stretches
        // the card before edge detection. Work from UIImage's display size so the
        // pixels and the orientation describe the same rectangle.
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        let maxDimension: CGFloat = 1_200
        let scale = min(1, maxDimension / max(originalWidth, originalHeight))
        let size = CGSize(width: originalWidth * scale, height: originalHeight * scale)
        let radians = CGFloat(rotationDegrees * .pi / 180)
        let rotatedBounds = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: radians)).standardized

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: rotatedBounds.size, format: format).image { context in
            // Whatever surrounds the card, not white. Rotation leaves wedges in
            // the corners of the enlarged canvas, and filling them with a fixed
            // colour makes them foreground against any darker background — so
            // the silhouette grew to the whole canvas and the straightened pass
            // measured worse than the crooked one it was correcting.
            padding.setFill()
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
        guard !scores.isEmpty else { return CandidateSet(candidates: [Candidate(position: offset, strength: 0)]) }
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
            candidates: found.map { Candidate(position: $0.key, strength: $0.value) }.sorted { $0.position < $1.position }
        )
    }

    /// Separates a card from the scanner bed by comparing every row with robust
    /// background samples at the far left and right. A real card occupies a
    /// wide, continuous run of columns; dust and scanner seams do not.
    private static func verticalSilhouetteEdges(
        lab: [Pixel],
        width: Int,
        height: Int,
        yRange: Range<Int>,
        cardHeight: Int
    ) -> (left: Int, right: Int)? {
        guard width > 20, height > 20, !yRange.isEmpty else { return nil }
        let sampleWidth = clamped(Int((Double(width) * 0.02).rounded()), 6, min(24, width / 4))
        var foregroundCounts = [Int](repeating: 0, count: width)

        for y in yRange {
            let row = y * width
            let leftSamples = (0..<sampleWidth).map { lab[row + $0] }
            let rightSamples = ((width - sampleWidth)..<width).map { lab[row + $0] }
            let leftBackground = medianPixel(leftSamples)
            let rightBackground = medianPixel(rightSamples)

            for x in 0..<width {
                let progress = Float(x) / Float(max(width - 1, 1))
                let background = Pixel(
                    l: leftBackground.l + progress * (rightBackground.l - leftBackground.l),
                    a: leftBackground.a + progress * (rightBackground.a - leftBackground.a),
                    b: leftBackground.b + progress * (rightBackground.b - leftBackground.b)
                )
                if distance(lab[row + x], background) >= 8 {
                    foregroundCounts[x] += 1
                }
            }
        }

        let occupancy = foregroundCounts.map { Float($0) / Float(yRange.count) }
        let smoothed = occupancy.indices.map { index -> Float in
            let range = max(0, index - 4)...min(width - 1, index + 4)
            return range.reduce(0) { $0 + occupancy[$1] } / Float(range.count)
        }

        var runs: [(lower: Int, upper: Int)] = []
        var runStart: Int?
        for x in smoothed.indices {
            if smoothed[x] >= 0.60, runStart == nil {
                runStart = x
            }
            if let start = runStart, smoothed[x] < 0.60 || x == width - 1 {
                let end = smoothed[x] < 0.60 ? x - 1 : x
                if end > start { runs.append((start, end)) }
                runStart = nil
            }
        }

        let plausible = runs.filter {
            let aspect = Double($0.upper - $0.lower) / Double(max(cardHeight, 1))
            return (0.62...0.82).contains(aspect)
        }
        guard let card = plausible.max(by: {
            ($0.upper - $0.lower) < ($1.upper - $1.lower)
        }) else { return nil }

        return (max(0, card.lower - 1), min(width - 1, card.upper))
    }

    // MARK: - Card outline

    /// The card's bounding box, from where it stops looking like the background.
    ///
    /// Background is estimated from a thin ring around the image and taken as a
    /// median, so it survives a card that touches one or two edges. A pixel is
    /// foreground when it differs from that background by more than the
    /// background's own spread, which is what lets a near-white border be found
    /// against a light table without also turning film grain into a card.
    ///
    /// Occupancy is compared against the strongest column and row rather than
    /// against the image, because "how much of the frame does a card fill" is
    /// exactly the thing that cannot be assumed here.
    ///
    /// Returns `nil` rather than a guess whenever the result is not shaped like
    /// a card — a bled-to-the-edge scan, a busy background — and the caller
    /// falls back to the gradient scan.
    /// The median colour of a thin ring around the image — what the card is
    /// sitting on. Taken in RGB so it can be used directly as a fill.
    private static func borderColor(
        pixels: [(Float, Float, Float)],
        width: Int,
        height: Int
    ) -> UIColor {
        let ring = ringWidth(width: width, height: height)
        var red: [Float] = [], green: [Float] = [], blue: [Float] = []
        for index in ringIndices(width: width, height: height, ring: ring) {
            let pixel = pixels[index]
            red.append(pixel.0); green.append(pixel.1); blue.append(pixel.2)
        }
        guard !red.isEmpty else { return .white }
        return UIColor(
            red: CGFloat(median(red)),
            green: CGFloat(median(green)),
            blue: CGFloat(median(blue)),
            alpha: 1
        )
    }

    private static func ringWidth(width: Int, height: Int) -> Int {
        clamped(Int((Double(Swift.min(width, height)) * 0.01).rounded()), 2, 24)
    }

    /// Indices of the ring, sampled the same way for the colour and the mask so
    /// the two always describe the same pixels.
    private static func ringIndices(width: Int, height: Int, ring: Int) -> [Int] {
        var indices: [Int] = []
        indices.reserveCapacity((width + height) * ring)
        for y in 0..<height {
            if y < ring || y >= height - ring {
                for x in stride(from: 0, to: width, by: 2) { indices.append(y * width + x) }
            } else {
                for x in 0..<ring { indices.append(y * width + x) }
                for x in (width - ring)..<width { indices.append(y * width + x) }
            }
        }
        return indices
    }

    private struct CardOutline {
        let edges: CardCenteringEdges
        /// Positive means the card leans clockwise in image coordinates.
        let skewDegrees: Double
    }

    private static func cardOutline(
        lab: [Pixel],
        width: Int,
        height: Int
    ) -> CardOutline? {
        let ring = ringWidth(width: width, height: height)
        let samples = ringIndices(width: width, height: height, ring: ring).map { lab[$0] }
        guard samples.count > 32 else { return nil }

        let background = medianPixel(samples)
        let spread = median(samples.map { distance($0, background) })
        let threshold = Swift.max(5, spread * 3)

        var columnCounts = [Int](repeating: 0, count: width)
        var rowCounts = [Int](repeating: 0, count: height)
        // Where the card starts and stops on each row, kept so the same single
        // pass that finds the outline can also measure how far it leans.
        var firstForeground = [Int](repeating: -1, count: height)
        var lastForeground = [Int](repeating: -1, count: height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where distance(lab[row + x], background) >= threshold {
                columnCounts[x] += 1
                rowCounts[y] += 1
                if firstForeground[y] < 0 { firstForeground[y] = x }
                lastForeground[y] = x
            }
        }

        guard let columns = longestRun(columnCounts),
              let rows = longestRun(rowCounts) else { return nil }

        let boxWidth = columns.upper - columns.lower
        let boxHeight = rows.upper - rows.lower
        guard boxWidth > 8, boxHeight > 8 else { return nil }

        // A trading card is 2.5 x 3.5 inches, so 0.714 — either way up, because
        // a card photographed sideways is still a card and every measurement
        // below is stated per edge rather than per axis. The range is wide
        // because a few degrees of skew and a tight crop both move it, but it
        // still rejects a background that happened to form a long run.
        let aspect = Double(boxWidth) / Double(boxHeight)
        guard (0.50...1.00).contains(aspect) || (1.00...2.00).contains(aspect) else { return nil }

        // Both vertical edges are fitted and averaged. One alone can be dragged
        // by a shadow down one side; the two disagreeing is itself the signal
        // that neither should be trusted, so the fit is discarded then.
        let inset = Swift.max(2, Int((Double(boxHeight) * 0.1).rounded()))
        let fitRows = (rows.lower + inset)...(rows.upper - inset)
        guard fitRows.lowerBound < fitRows.upperBound else { return nil }

        let leftSlope = slope(of: firstForeground, over: fitRows)
        let rightSlope = slope(of: lastForeground, over: fitRows)
        let skew: Double
        if let leftSlope, let rightSlope, abs(leftSlope - rightSlope) <= 0.08 {
            // `dx/dy` of the edges, negated. Image space has y increasing
            // downward, so a card leaning clockwise puts its lower rows further
            // *left* and the raw slope comes out negative; without the negation
            // the corrective pass rotates the same way the card already leans
            // and doubles the skew it was meant to remove.
            skew = -atan((leftSlope + rightSlope) / 2) * 180 / .pi
        } else {
            skew = 0
        }

        return CardOutline(
            edges: CardCenteringEdges(
                left: columns.lower,
                top: rows.lower,
                right: columns.upper,
                bottom: rows.upper
            ),
            skewDegrees: skew
        )
    }

    /// Least-squares `dx/dy` of one card edge, ignoring rows where the mask
    /// found nothing.
    private static func slope(of positions: [Int], over rows: ClosedRange<Int>) -> Double? {
        var n = 0.0, sumY = 0.0, sumX = 0.0, sumYY = 0.0, sumXY = 0.0
        for y in rows where positions[y] >= 0 {
            let dy = Double(y), dx = Double(positions[y])
            n += 1; sumY += dy; sumX += dx; sumYY += dy * dy; sumXY += dx * dy
        }
        guard n >= 8 else { return nil }
        let denominator = n * sumYY - sumY * sumY
        guard abs(denominator) > .ulpOfOne else { return nil }
        return (n * sumXY - sumY * sumX) / denominator
    }

    /// The longest run of indices whose count is a solid fraction of the
    /// strongest one. Self-normalising, so it does not need to know how much of
    /// the frame the card fills.
    private static func longestRun(_ counts: [Int]) -> (lower: Int, upper: Int)? {
        guard let peak = counts.max(), peak > 0 else { return nil }
        let needed = Swift.max(1, Int((Double(peak) * 0.6).rounded()))
        var best: (lower: Int, upper: Int)?
        var start: Int?

        func close(_ end: Int) {
            guard let lower = start else { return }
            if best == nil || (end - lower) > (best!.upper - best!.lower) {
                best = (lower, end)
            }
            start = nil
        }

        for index in counts.indices {
            if counts[index] >= needed {
                if start == nil { start = index }
            } else {
                close(index - 1)
            }
        }
        close(counts.count - 1)
        return best
    }

    private static func medianPixel(_ pixels: [Pixel]) -> Pixel {
        Pixel(
            l: median(pixels.map(\.l)),
            a: median(pixels.map(\.a)),
            b: median(pixels.map(\.b))
        )
    }

    /// Walks in from the cut edge until the border colour stops.
    ///
    /// The border is a flat printed region, so it can be recognised by what it
    /// *is* rather than by how sharply it ends — which is what makes this work
    /// where gradients do not. The colour is sampled from a thin strip just
    /// inside the cut edge, and the tolerance comes from that strip's own
    /// variation, so a faint border on dark art is followed just as well as a
    /// bright one and a slightly uneven border is not mistaken for its end.
    ///
    /// Sampled across the middle of the card only, away from rounded corners
    /// and edge wear. Returns `nil` — deferring to the gradient scan — when the
    /// border does not end inside the search band, which is what happens if the
    /// strip was never border in the first place.
    private static func borderEnd(
        side: Side,
        lab: [Pixel],
        width: Int,
        height: Int,
        outer: CardCenteringEdges,
        minimum: Int,
        maximum: Int
    ) -> Int? {
        let horizontal = side == .left || side == .right
        // Positions to walk through, and the span to average each one over.
        let spanLower: Int, spanUpper: Int
        if horizontal {
            let inset = Int(Double(outer.bottom - outer.top) * 0.2)
            spanLower = clamped(outer.top + inset, 0, height - 1)
            spanUpper = clamped(outer.bottom - inset, spanLower + 1, height)
        } else {
            let inset = Int(Double(outer.right - outer.left) * 0.2)
            spanLower = clamped(outer.left + inset, 0, width - 1)
            spanUpper = clamped(outer.right - inset, spanLower + 1, width)
        }
        guard spanUpper - spanLower >= 8 else { return nil }

        func sample(depth: Int) -> [Pixel] {
            let position: Int
            switch side {
            case .left: position = outer.left + depth
            case .right: position = outer.right - depth
            case .top: position = outer.top + depth
            case .bottom: position = outer.bottom - depth
            }
            guard position >= 0 else { return [] }
            if horizontal {
                guard position < width else { return [] }
                return (spanLower..<spanUpper).map { lab[$0 * width + position] }
            }
            guard position < height else { return [] }
            return (spanLower..<spanUpper).map { lab[position * width + $0] }
        }

        // The border's own colour and its own unevenness, from a strip that is
        // inside any border wide enough to be worth measuring.
        var strip: [Pixel] = []
        for depth in 1...3 { strip.append(contentsOf: sample(depth: depth)) }
        guard strip.count >= 24 else { return nil }
        let borderColor = medianPixel(strip)
        let unevenness = median(strip.map { distance($0, borderColor) })
        let tolerance = Swift.max(4, unevenness * 4)

        for depth in minimum...maximum {
            let line = sample(depth: depth)
            guard !line.isEmpty else { return nil }
            if distance(medianPixel(line), borderColor) > tolerance {
                switch side {
                case .left: return outer.left + depth
                case .right: return outer.right - depth
                case .top: return outer.top + depth
                case .bottom: return outer.bottom - depth
                }
            }
        }
        return nil
    }

    /// The strongest transition in the band, used when `borderEnd` cannot
    /// follow the border — an uneven or foiled one, mainly.
    ///
    /// Strength alone, deliberately. The previous rule scored candidates by how
    /// close their border width came to the *other three sides'*, which assumes
    /// the four borders are alike — the one thing a centering measurement may
    /// not assume, since unequal borders are precisely what it exists to report.
    /// It biased every reading toward the card being well centred.
    ///
    /// Nothing has replaced that prior. A shallowness preference was tried here
    /// and removed again: it changed no measurement in any case that could be
    /// constructed, and a weight that earns its keep in no test is a number
    /// waiting to be wrong in a real one.
    private static func chooseInner(
        side: Side,
        set: CandidateSet,
        outer: CardCenteringEdges
    ) -> Candidate {
        set.candidates
            .filter { border(for: side, position: $0.position, outer: outer) > 0 }
            .max { $0.strength < $1.strength }
            ?? set.candidates[0]
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
