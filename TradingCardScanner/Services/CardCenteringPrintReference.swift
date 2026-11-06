#if DEBUG
    import Foundation
    import UIKit
    import simd

    /// Prepared patches belong to the publisher's image. No capture coordinates or
    /// measured ratios are inputs. The thumbnail grid is 320 by 448, in cut space.
    struct CardCenteringPrintReference: Decodable, Hashable {
        struct Patch: Decodable, Hashable {
            let x, y: Int
            let interior: Bool
            let pixels: Data
        }

        let label, sourceSHA256: String
        let left, top, right, bottom: Double
        let patches: [Patch]

        static var launchReference: Self? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-ui_debug_print_reference"), i + 1 < args.count,
                let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
            else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        }

        var isValid: Bool {
            !label.isEmpty && sourceSHA256.count == 64 && sourceSHA256.allSatisfy(\.isHexDigit)
                && left > 0 && top > 0 && right < 1 && bottom < 1 && right > left && bottom > top
                && (12...64).contains(patches.count)
                && patches.allSatisfy {
                    (8..<312).contains($0.x) && (8..<440).contains($0.y) && $0.pixels.count == 289
                }
        }
    }

    struct CardCenteringPrintPlacement: Equatable {
        let label, sourceSHA256: String
        let designLeft, designTop: Double
    }

    enum CardCenteringPrintMatcher {
        typealias Point = CardCenteringPoint
        typealias Side = CardCenteringPrecisionSide
        typealias Line = CardCenteringNativeLine

        // The registration uses local contrast, so a change of exposure does not
        // require the scan and publisher image to have identical RGB values.
        private static func registeredRegion(
            _ reference: CardCenteringPrintReference,
            in analysis: CardCenteringAnalysis
        ) -> CardCenteringQuad? {
            guard reference.isValid, let image = analysis.image.cgImage,
                let mapping = analysis.coordinateMapping
            else { return nil }
            let outer = analysis.measurement.geometryOuterQuad
            let scale = min(1, 320 / max(1, (outer.topLength + outer.bottomLength) / 2))
            let w = max(1, Int((Double(image.width) * scale).rounded()))
            let h = max(1, Int((Double(image.height) * scale).rounded()))
            var gray = [UInt8](repeating: 0, count: w * h)
            let ok = gray.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            func mix(_ a: Point, _ b: Point, _ t: Double) -> Point {
                .init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            func working(_ u: Double, _ v: Double) -> Point {
                mix(mix(outer.topLeft, outer.bottomLeft, v), mix(outer.topRight, outer.bottomRight, v), u)
            }
            var grid = [UInt8](repeating: 0, count: 320 * 448)
            let corners = outer.points.flatMap {
                [$0.x * Double(w) / Double(image.width), $0.y * Double(h) / Double(image.height)]
            }
            guard corners.allSatisfy(\.isFinite) else { return nil }
            TCSCenteringSamplePrintGrid(gray, Int32(w), Int32(h), corners, &grid)
            var matches: [(patch: CardCenteringPrintReference.Patch, dx: Double, dy: Double)] = []
            for patch in reference.patches {
                guard !Task.isCancelled else { return nil }
                var dx = 0.0
                var dy = 0.0
                let score = patch.pixels.withUnsafeBytes { bytes in
                    TCSCenteringMatchPatch(
                        grid, 320, 448, bytes.bindMemory(to: UInt8.self).baseAddress,
                        Int32(patch.x), Int32(patch.y), &dx, &dy)
                }
                if score >= 0.80 { matches.append((patch, dx, dy)) }
            }
            let inside = matches.filter { $0.patch.interior }
            guard inside.count >= 10 else { return nil }
            let dx = inside.map(\.dx).sorted()[inside.count / 2]
            let dy = inside.map(\.dy).sorted()[inside.count / 2]
            let coherent = matches.filter { abs($0.dx - dx) <= 2 && abs($0.dy - dy) <= 2 }
            let interior = coherent.filter { $0.patch.interior }
            let mx = (reference.left + reference.right) * 160
            let my = (reference.top + reference.bottom) * 224
            let quadrants = Set(interior.map { (Double($0.patch.x) > mx ? 1 : 0) + (Double($0.patch.y) > my ? 2 : 0) })
            let corroboration = coherent.filter { !$0.patch.interior }
            guard interior.count >= 10, quadrants.count == 4,
                corroboration.contains(where: { Double($0.patch.y) < reference.top * 448 }),
                corroboration.contains(where: { Double($0.patch.y) > reference.bottom * 448 }) else {
                return nil
            }
            // A cut-aligned thumbnail still has local scale and tilt differences.
            // Fit the residual displacement across the artwork from observed patch
            // positions; title/footer matches corroborate identity but do not fit it.
            var normal = simd_double3x3(diagonal: .zero)
            var rhsX = SIMD3<Double>.zero
            var rhsY = SIMD3<Double>.zero
            for match in interior {
                let row = SIMD3(1, (Double(match.patch.x) + 0.5) / 320, (Double(match.patch.y) + 0.5) / 448)
                normal.columns.0 += row * row.x
                normal.columns.1 += row * row.y
                normal.columns.2 += row * row.z
                rhsX += row * match.dx
                rhsY += row * match.dy
            }
            guard abs(normal.determinant) > 1e-8 else { return nil }
            let xFit = normal.inverse * rhsX
            let yFit = normal.inverse * rhsY
            func corner(_ x: Double, _ y: Double) -> Point {
                let row = SIMD3(1, x, y)
                return mapping.nativePoint(
                    fromWorking: working(x + simd_dot(row, xFit) / 320, y + simd_dot(row, yFit) / 448))
            }
            return .init(
                topLeft: corner(reference.left, reference.top), topRight: corner(reference.right, reference.top),
                bottomRight: corner(reference.right, reference.bottom),
                bottomLeft: corner(reference.left, reference.bottom))
        }

        private static func intersection(_ l: Line, _ r: Line) -> Point? {
            let x = l.end.x - l.start.x
            let y = l.end.y - l.start.y
            let u = r.end.x - r.start.x
            let v = r.end.y - r.start.y
            let det = x * v - y * u
            guard abs(det) > 1e-8 else { return nil }
            let t = ((r.start.x - l.start.x) * v - (r.start.y - l.start.y) * u) / det
            return .init(x: l.start.x + t * x, y: l.start.y + t * y)
        }

        private static func quad(_ lines: [Side: Line]) -> CardCenteringQuad? {
            guard let l = lines[.left], let r = lines[.right], let t = lines[.top], let b = lines[.bottom],
                let tl = intersection(t, l), let tr = intersection(t, r), let br = intersection(b, r),
                let bl = intersection(b, l)
            else { return nil }
            return .init(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
        }

        private static func edge(_ q: CardCenteringQuad, _ s: Side) -> Line {
            .init(start: q.points[s.index], end: q.points[(s.index + 1) % 4])
        }
        private static func distance(_ p: Point, _ line: Line) -> Double {
            let x = line.end.x - line.start.x
            let y = line.end.y - line.start.y
            return abs(x * (p.y - line.start.y) - y * (p.x - line.start.x)) / max(1e-9, hypot(x, y))
        }

        // Refine the observed candidate, not the projected template. Fit independent
        // side angles from signed inward brightness drops along bounded native strips.
        private static func fit(_ side: Side, seed: CardCenteringQuad, source: UIImage)
            -> CardCenteringBoundaryCandidate?
        {
            let line = edge(seed, side)
            let a = line.start
            let b = line.end
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 24 else { return nil }
            let nx = -(b.y - a.y) / length
            let ny = (b.x - a.x) / length
            let box = CGRect(
                x: min(a.x, b.x) - 13, y: min(a.y, b.y) - 13, width: abs(a.x - b.x) + 26, height: abs(a.y - b.y) + 26)
            guard let crop = CardCenteringNativeRefiner.crop(source: source, orientedRect: box) else { return nil }
            typealias Sample = (t: Double, depth: Double)
            var samples: [Sample] = []
            func point(_ t: Double, _ d: Double) -> Point {
                .init(x: a.x + t * (b.x - a.x) + d * nx, y: a.y + t * (b.y - a.y) + d * ny)
            }
            for i in 0..<61 {
                let t = 0.15 + 0.70 * Double(i) / 60
                var peak = 2.5
                var selected: Double?
                for k in -14...14 {
                    let d = Double(k) / 2
                    guard let u = crop.color(at: point(t, d - 1.5)), let v = crop.color(at: point(t, d + 1.5)) else {
                        continue
                    }
                    let strength = (u.0 + u.1 + u.2 - v.0 - v.1 - v.2) / 3
                    if strength > peak {
                        peak = strength
                        selected = d
                    }
                }
                if let selected { samples.append((t, selected)) }
            }
            guard samples.count >= 25 else { return nil }
            var slopes: [Double] = []
            for (i, p) in samples.enumerated() {
                for q in samples.dropFirst(i + 1) where q.t - p.t > 0.22 {
                    slopes.append((q.depth - p.depth) / (q.t - p.t))
                }
            }
            guard !slopes.isEmpty else { return nil }
            let slope = slopes.sorted()[slopes.count / 2]
            let offset = samples.map { $0.depth - $0.t * slope }.sorted()[samples.count / 2]
            let kept = samples.filter { abs($0.depth - offset - $0.t * slope) <= 3 }
            guard kept.count >= 25, Set(kept.map { min(4, Int(($0.t - 0.15) * 5 / 0.70)) }).count >= 4 else {
                return nil
            }
            let mt = kept.map(\.t).reduce(0, +) / Double(kept.count)
            let md = kept.map(\.depth).reduce(0, +) / Double(kept.count)
            let variance = kept.reduce(0) { $0 + pow($1.t - mt, 2) }
            guard variance > 0 else { return nil }
            let m = kept.reduce(0) { $0 + ($1.t - mt) * ($1.depth - md) } / variance
            let d = md - m * mt
            let fit = Line(start: point(0, d), end: point(1, d + m))
            let points = kept.map { point($0.t, $0.depth) }
            let rms = sqrt(points.reduce(0) { $0 + pow(distance($1, fit), 2) } / Double(points.count))
            return .init(
                id: "exact-print-\(side.rawValue)", frame: .inner, side: side, nativeLine: fit,
                source: "selected.print_artwork", proposedRole: .artwork, competingRoles: [.printedBorder],
                signal: "inward_brightness_drop", strength: nil, polarity: -1, coverage: Double(kept.count) / 61,
                fitResidualNativePixels: rms,
                sampleBands: [.init(start: fit.start, end: fit.end, sampleCount: points.count)],
                exclusions: [], selectionReason: .detectorProposal, reason: "Artwork located from the supplied print.",
                observedPoints: points)
        }

        static func apply(_ reference: CardCenteringPrintReference, baseline: CardCenteringAnalysis, source: UIImage,
                          candidateScan: () throws -> [CardCenteringBoundaryCandidate])
            -> CardCenteringAnalysis
        {
            guard !Task.isCancelled, let region = registeredRegion(reference, in: baseline),
                let mapping = baseline.coordinateMapping, let pool = try? candidateScan()
            else { return baseline }
            var seeds: [Side: Line] = [:]
            for side in Side.allCases {
                let target = edge(region, side)
                let ranked = pool.filter { $0.side == side && $0.frame == .inner }.map { candidate in
                    (
                        candidate.nativeLine,
                        (distance(candidate.nativeLine.start, target) + distance(candidate.nativeLine.end, target)) / 2
                    )
                }.sorted { $0.1 < $1.1 }
                guard let best = ranked.first, best.1 < 24, ranked.count == 1 || ranked[1].1 - best.1 >= 1 else {
                    return baseline
                }
                seeds[side] = best.0
            }
            guard let seed = quad(seeds) else { return baseline }
            let fits = Side.allCases.compactMap { fit($0, seed: seed, source: source) }
            guard fits.count == 4,
                let native = quad(Dictionary(uniqueKeysWithValues: fits.map { ($0.side, $0.nativeLine) })),
                !Task.isCancelled
            else { return baseline }
            let old = baseline.measurement
            let alternatives = pool.map { candidate in
                CardCenteringBoundaryCandidate(
                    id: "print-probe-" + candidate.id, frame: candidate.frame, side: candidate.side,
                    nativeLine: candidate.nativeLine, source: candidate.source, proposedRole: candidate.proposedRole,
                    competingRoles: candidate.competingRoles, signal: candidate.signal, strength: candidate.strength,
                    polarity: candidate.polarity, coverage: candidate.coverage,
                    fitResidualNativePixels: candidate.fitResidualNativePixels,
                    sampleBands: candidate.sampleBands, exclusions: candidate.exclusions,
                    selectionReason: .competingCandidate,
                    reason: candidate.reason, observedPoints: candidate.observedPoints)
            }
            var measurement = CardCenteringMeasurement(
                imageWidth: old.imageWidth, imageHeight: old.imageHeight,
                outerQuad: old.geometryOuterQuad, innerQuad: mapping.workingQuad(fromNative: native),
                warnings: old.warnings,
                detectionNotes: old.detectionNotes,
                coordinateMapping: mapping, innerReference: .artWindow,
                confidence: .declined(reason: "Artwork placement requires review."),
                inputRecord: old.inputRecord,
                boundaryCandidates: fits + old.boundaryCandidates.filter { $0.frame == .outer } + alternatives,
                referenceDefinition: .matchedArtwork)
            guard measurement.hasValidFrameGeometry else { return baseline }
            measurement.printPlacement = .init(
                label: reference.label, sourceSHA256: reference.sourceSHA256,
                designLeft: 100 * reference.left / (reference.left + 1 - reference.right),
                designTop: 100 * reference.top / (reference.top + 1 - reference.bottom))
            return .init(
                image: baseline.image, measurement: measurement, coordinateMapping: mapping,
                appliedRotationDegrees: baseline.appliedRotationDegrees,
                detectedSkewDegrees: baseline.detectedSkewDegrees, nativeSourceData: baseline.nativeSourceData)
        }
    }
#endif
