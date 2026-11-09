#if DEBUG
    import Foundation
    import UIKit
    import simd

    /// Prepared patches belong to the publisher's image. No capture coordinates or
    /// measured ratios are inputs. The thumbnail grid is 320 by 448, in cut space.
    struct CardCenteringPrintReference: Decodable, Hashable {
        enum Kind: String, Decodable, Hashable { case artwork, printedBorder }
        enum BoundaryMethod: String, Decodable, Hashable { case printedContinuity }
        enum ColorSignal: String, Decodable, Hashable { case redGreenChromaticity, blueGreenChromaticity }
        struct ColorPatch: Decodable, Hashable {
            let signal: ColorSignal
            let pixels: Data
        }
        struct Bounds: Decodable, Hashable {
            let left, top, right, bottom: Double
            var isValid: Bool { 0 < left && left < right && right < 1 && 0 < top && top < bottom && bottom < 1 }
        }
        struct Patch: Decodable, Hashable {
            let x, y: Int
            let interior: Bool
            let pixels: Data
            var identityArtwork: Bool? = nil
            var colorAlternatives: [ColorPatch]? = nil
        }
        struct BoundaryProfile: Decodable, Hashable {
            let side: String
            let sourceWidth, sourceHeight, x, y, width, height: Int
            let pixels: Data
            var isValid: Bool {
                ["left", "top", "right", "bottom"].contains(side)
                    && (2...4096).contains(sourceWidth) && (2...4096).contains(sourceHeight)
                    && x >= 0 && y >= 0 && width > 1 && height > 1
                    && width <= sourceWidth && height <= sourceHeight
                    && x <= sourceWidth-width && y <= sourceHeight-height
                    && width*height <= 250_000 && pixels.count == width*height
            }
            func sample(_ point: CardCenteringPoint) -> Double? {
                let px = point.x-Double(x), py = point.y-Double(y)
                guard px.isFinite, py.isFinite, px >= 0, py >= 0,
                      px < Double(width-1), py < Double(height-1) else { return nil }
                let ix = Int(px), iy = Int(py), dx = px-Double(ix), dy = py-Double(iy)
                return (1-dy)*((1-dx)*Double(pixels[iy*width+ix])+dx*Double(pixels[iy*width+ix+1]))
                    + dy*((1-dx)*Double(pixels[(iy+1)*width+ix])+dx*Double(pixels[(iy+1)*width+ix+1]))
            }
        }

        let label, sourceSHA256: String
        let left, top, right, bottom: Double
        let patches: [Patch]
        var kind: Kind? = nil
        var identityArtworkBounds: Bounds? = nil
        var boundaryProfiles: [BoundaryProfile]? = nil
        var boundaryMethod: BoundaryMethod? = nil
        var isPrintedBorder: Bool { kind == .printedBorder }

        static var launchReference: Self? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-ui_debug_print_reference"), i + 1 < args.count,
                let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
            else { return nil }
            return try? JSONDecoder().decode(Self.self, from: data)
        }

        static var launchLibrary: [Self] {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-ui_debug_print_reference_library"), i + 1 < args.count,
                let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
            else { return [] }
            return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
        }

        var isValid: Bool {
            !label.isEmpty && sourceSHA256.count == 64 && sourceSHA256.allSatisfy(\.isHexDigit)
                && left > 0 && top > 0 && right < 1 && bottom < 1 && right > left && bottom > top
                && (12...64).contains(patches.count)
                && patches.allSatisfy {
                    (8..<312).contains($0.x) && (8..<440).contains($0.y) && $0.pixels.count == 289
                        && ($0.colorAlternatives?.count ?? 0) <= 2
                        && ($0.colorAlternatives ?? []).allSatisfy { $0.pixels.count == 289 }
                        && Set(($0.colorAlternatives ?? []).map(\.signal)).count == ($0.colorAlternatives?.count ?? 0)
                }
                && (!isPrintedBorder || (identityArtworkBounds?.isValid == true
                    && patches.filter { $0.identityArtwork == true }.count >= 6
                    && Set(patches.map { $0.y * 320 + $0.x }).count == patches.count))
                && (boundaryMethod == nil || (isPrintedBorder && boundaryProfiles == nil))
                && (boundaryProfiles == nil || ((boundaryProfiles?.count ?? 0) <= 4
                    && (boundaryProfiles ?? []).allSatisfy(\.isValid)
                    && Set((boundaryProfiles ?? []).map(\.side)).count == boundaryProfiles?.count))
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
        @TaskLocal static var diagnosticSink: (@Sendable (String) -> Void)?
        @TaskLocal static var physicalRefinementEnabled = true

        struct ObservedPath: Codable, Equatable {
            let side: String
            /// Missing entries remain missing; interpolation cannot create evidence.
            let observations: [Point?]
        }

        /// Additive research route. No quadrilateral, report confidence or existing
        /// analyzer result is changed by observing a curved boundary.
        static func observedArtworkPath(_ side: Side, reference: CardCenteringPrintReference,
                                        analysis: CardCenteringAnalysis, source: UIImage) -> ObservedPath? {
            guard reference.boundaryProfiles?.contains(where: { $0.side == side.rawValue }) == true,
                  let region = registeredRegion(reference, in: analysis) else { return nil }
            return observedArtworkPath(side, reference: reference, region: region, source: source)
        }

        private static func observedArtworkPath(_ side: Side, reference: CardCenteringPrintReference,
                                                region: CardCenteringQuad, source: UIImage) -> ObservedPath? {
            guard let profile = reference.boundaryProfiles?.first(where: { $0.side == side.rawValue }) else { return nil }
            let rect = CardCenteringRectification(outerQuad: region)
            guard rect.isNumericallyValid else { return nil }
            let line = edge(region, side), a = line.start, b = line.end
            let length = hypot(b.x-a.x, b.y-a.y)
            guard length > 24 else { return nil }
            let tx = (b.x-a.x)/length, ty = (b.y-a.y)/length
            // edge() is clockwise, so the exterior normal is the right normal.
            let nx = ty, ny = -tx
            let box = CGRect(x: min(a.x,b.x)-100, y: min(a.y,b.y)-100,
                width: abs(b.x-a.x)+200, height: abs(b.y-a.y)+200)
            guard let crop = CardCenteringNativeRefiner.crop(source: source, orientedRect: box) else { return nil }
            func referenceValue(_ point: Point) -> Double? {
                let q = rect.rectifiedPoint(from: point)
                return profile.sample(.init(
                    x: (reference.left+q.x/rect.targetSize.width*(reference.right-reference.left))*Double(profile.sourceWidth)-0.5,
                    y: (reference.top+q.y/rect.targetSize.height*(reference.bottom-reference.top))*Double(profile.sourceHeight)-0.5))
            }
            func median(_ values: [Double]) -> Double {
                let s = values.sorted(), n = s.count
                return n%2 == 0 ? (s[n/2-1]+s[n/2])/2 : s[n/2]
            }
            func correlation(_ a: [Double], _ b: [Double]) -> Double {
                let ma = a.reduce(0,+)/Double(a.count), mb = b.reduce(0,+)/Double(b.count)
                var aa = 0.0, bb = 0.0, ab = 0.0
                for i in a.indices { let x = a[i]-ma, y = b[i]-mb; aa += x*x; bb += y*y; ab += x*y }
                return aa*bb > 1e-8 ? ab/sqrt(aa*bb) : -1
            }
            func correctedPeak(_ values: [Double], _ index: Int) -> Double {
                guard index > 0, index < values.count-1 else { return Double(index) }
                let curvature = values[index-1]-2*values[index]+values[index+1]
                guard curvature < -1e-9 else { return Double(index) }
                return Double(index)+max(-0.5,min(0.5,0.5*(values[index-1]-values[index+1])/curvature))
            }
            func gradient(_ values: [Double], sigma: Double) -> [Double] {
                let radius = Int(4*sigma+0.5)
                let weights = (-radius...radius).map { exp(-Double($0*$0)/(2*sigma*sigma)) }
                let total = weights.reduce(0,+)
                return values.indices.map { index in
                    var sum = 0.0
                    for offset in -radius...radius {
                        let j = max(0,min(values.count-1,index+offset))
                        sum += values[j]*Double(offset)/(sigma*sigma)*weights[offset+radius]/total
                    }
                    return sum
                }
            }
            var observations: [Point?] = []
            for station in 0..<61 {
                guard !Task.isCancelled else { return nil }
                let t = 0.1+0.8*Double(station)/60
                let base = Point(x: a.x+t*(b.x-a.x), y: a.y+t*(b.y-a.y))
                var positions: [Double] = [], profiles: [([Double], Double)] = []
                var valid = true
                for width in [4.0,8.0,16.0] {
                    var raw: [Double] = [], expected: [Double] = []
                    for offset in -76...76 {
                        var photo = 0.0, provider = 0.0
                        for index in 0..<9 {
                            let shift = -width+2*width*Double(index)/8
                            let point = Point(x: base.x+Double(offset)*nx+shift*tx,
                                              y: base.y+Double(offset)*ny+shift*ty)
                            guard let c = crop.color(at: point), let r = referenceValue(point) else {
                                valid = false; break
                            }
                            photo += (c.0+c.1+c.2)/3; provider += r
                        }
                        if !valid { break }
                        raw.append(photo/9); expected.append(provider/9)
                    }
                    if !valid { break }
                    profiles.append((raw, expected[78] > expected[74] ? 1 : -1))
                    for radius in [24,36] {
                        let template = Array(expected[(76-radius)...(76+radius)])
                        let scores = (-40...40).map { offset in
                            correlation(template, Array(raw[(76+offset-radius)...(76+offset+radius)]))
                        }
                        let best = scores.indices.max(by: { scores[$0] < scores[$1] })!
                        let competitors = (1..<scores.count-1).filter {
                            abs($0-best) >= 8 && scores[$0] > scores[$0-1] && scores[$0] >= scores[$0+1]
                        }.map { scores[$0] }
                        guard best > 0, best < scores.count-1, scores[best] >= 0.8,
                              scores[best]-(competitors.max() ?? -1) >= 0.05 else { valid = false; break }
                        positions.append(correctedPeak(scores,best)-40)
                    }
                    if !valid { break }
                }
                guard valid, positions.count == 6, positions.max()!-positions.min()! <= 4 else {
                    observations.append(nil); continue
                }
                let center = median(positions)
                var refined: [Double] = []
                for (raw, polarity) in profiles {
                    for sigma in [1.0,2.0] {
                        let g = gradient(raw.map { $0*polarity }, sigma: sigma)
                        let eligible = g.indices.filter { abs(Double($0-76)-center) <= 6 }
                        guard let best = eligible.max(by: { g[$0] < g[$1] }),
                              best != eligible.first, best != eligible.last, g[best] >= 2.5 else { valid = false; break }
                        refined.append(correctedPeak(g,best)-76)
                    }
                    if !valid { break }
                }
                guard valid, refined.count == 6, refined.max()!-refined.min()! <= 4 else {
                    observations.append(nil); continue
                }
                let depth = median(refined)
                observations.append(.init(x: base.x+depth*nx, y: base.y+depth*ny))
            }
            diagnosticSink?("print-path \(side.rawValue) supported=\(observations.compactMap { $0 }.count)")
            return .init(side: side.rawValue, observations: observations)
        }

        struct ObservedMeasurement: Codable, Equatable {
            let outerPaths, innerPaths: [ObservedPath]
            let leftShare, topShare: Double
            let localLeftShares, localTopShares: [Double]
            let meanMargins: [String: Double]
            let measurementOuterQuad: CardCenteringQuad
        }

        /// Research-only continuity proposal followed by independent local RGB
        /// observations. A tracked point is never evidence until all six local
        /// scale trials agree. The seed identifies a search band, not a ratio.
        static func observedPrintedContinuityPath(_ side: Side, seed: CardCenteringQuad,
                                                  source: UIImage) -> ObservedPath? {
            // Canonical scan direction matches the offline tracking experiment.
            let line = edge(seed, side)
            let reversed = side == .left || side == .bottom
            let a = reversed ? line.end : line.start, b = reversed ? line.start : line.end
            let length = hypot(b.x-a.x,b.y-a.y)
            guard length > 24 else { return nil }
            let tx = (b.x-a.x)/length, ty = (b.y-a.y)/length
            let sign = reversed ? -1.0 : 1.0
            let nx = sign*ty, ny = -sign*tx
            guard let crop = CardCenteringNativeRefiner.crop(source: source, orientedRect: CGRect(
                x: min(a.x,b.x)-130,y: min(a.y,b.y)-130,
                width: abs(b.x-a.x)+260,height: abs(b.y-a.y)+260)) else { return nil }
            let bases = (0..<61).map { i -> Point in
                let t = 0.1+0.8*Double(i)/60
                return .init(x:a.x+t*(b.x-a.x),y:a.y+t*(b.y-a.y))
            }
            func profile(_ base: Point, _ offsets: ClosedRange<Int>, _ width: Int) -> [SIMD3<Double>]? {
                var values: [SIMD3<Double>] = []
                for offset in offsets {
                    var sum = SIMD3<Double>(repeating: 0)
                    for shift in -width...width {
                        let p = Point(x:base.x+Double(offset)*nx+Double(shift)*tx,
                                      y:base.y+Double(offset)*ny+Double(shift)*ty)
                        guard let c = crop.color(at:p) else { return nil }
                        sum += SIMD3(c.0,c.1,c.2)
                    }
                    values.append(sum/Double(2*width+1))
                }
                return values
            }
            func gradient(_ values: [SIMD3<Double>], _ sigma: Double) -> [Double] {
                let radius = Int(4*sigma+0.5)
                let weights = (-radius...radius).map { exp(-Double($0*$0)/(2*sigma*sigma)) }
                let total = weights.reduce(0,+)
                return values.indices.map { index in
                    var sum = SIMD3<Double>(repeating: 0)
                    for offset in -radius...radius {
                        let j = max(0,min(values.count-1,index+offset))
                        let weight = Double(offset)*weights[offset+radius]/(sigma*sigma*total)
                        sum += values[j]*weight
                    }
                    return (abs(sum.x)+abs(sum.y)+abs(sum.z))/3
                }
            }
            var scores: [[Double]] = []
            for base in bases {
                guard !Task.isCancelled, let raw = profile(base,-80...80,4) else { return nil }
                var g = gradient(raw,2)
                for i in 0..<8 { g[i] = 0; g[g.count-1-i] = 0 }
                scores.append(g)
            }
            func anchors(_ values: [Double]) -> [Int] {
                let peaks = (1..<values.count-1).filter {
                    values[$0] > values[$0-1] && values[$0] >= values[$0+1]
                }.sorted { values[$0] > values[$1] }
                // Apply distance before prominence, as in the offline probe.
                var separated: [Int] = []
                for peak in peaks where !separated.contains(where: { abs($0-peak) < 12 }) {
                    separated.append(peak)
                }
                return Array(separated.filter { peak in
                    var lo = values[peak], hi = values[peak], i = peak-1
                    while i >= 0 && values[i] <= values[peak] { lo = min(lo,values[i]); i -= 1 }
                    i = peak+1
                    while i < values.count && values[i] <= values[peak] { hi = min(hi,values[i]); i += 1 }
                    return values[peak]-max(lo,hi) >= 0.5
                }.prefix(3))
            }
            var endpoints: (Int,Int)?, strength = -Double.infinity
            for start in anchors(scores[0]) {
                for end in anchors(scores[60]) {
                    let first = scores[0][start]/(1+pow(Double(start-80)/16,2))
                    let last = scores[60][end]/(1+pow(Double(end-80)/16,2))
                    if min(first,last) > strength { strength = min(first,last); endpoints = (start,end) }
                }
            }
            guard let (start,end) = endpoints else { return nil }
            func unary(_ row: [Double]) -> [Double] {
                let maximum = max(row.max() ?? 0,1e-6)
                return row.indices.map { i in
                    -log(max(row[i],0)/maximum+0.01)+pow(Double(i-80),2)/(2*16*16)
                }
            }
            var cost = [Double](repeating: .infinity,count:161)
            cost[start] = unary(scores[0])[start]
            var previous = [[Int]](repeating:[Int](repeating:0,count:161),count:61)
            for station in 1..<61 {
                guard !Task.isCancelled else { return nil }
                let local = unary(scores[station])
                var next = [Double](repeating:.infinity,count:161)
                for current in 0..<161 {
                    for prior in max(0,current-8)...min(160,current+8) {
                        let transition = pow(Double(current-prior),2)/(2*4*4)
                        let value = cost[prior]+transition+local[current]
                        if value < next[current] { next[current] = value; previous[station][current] = prior }
                    }
                }
                cost = next
            }
            guard cost[end].isFinite else { return nil }
            var path = [Int](repeating:0,count:61); path[60] = end
            for station in stride(from:60,through:1,by:-1) { path[station-1] = previous[station][path[station]] }
            var observations: [Point?] = []
            for station in 0..<61 {
                guard !Task.isCancelled else { return nil }
                let center = path[station]-80, base = bases[station]
                var positions: [Double] = []
                for width in [4,8,16] {
                    guard let raw = profile(base,(center-28)...(center+28),width) else { continue }
                    for sigma in [1.0,2.0] {
                        let g = gradient(raw,sigma)
                        guard let best = (22...34).max(by: { g[$0] < g[$1] }),
                              best != 22, best != 34, g[best] >= 2.5 else { continue }
                        let curvature = g[best-1]-2*g[best]+g[best+1]
                        let fraction = curvature < -1e-9
                            ? max(-0.5,min(0.5,0.5*(g[best-1]-g[best+1])/curvature)) : 0
                        positions.append(Double(center+best-28)+fraction)
                    }
                }
                guard positions.count == 6, positions.max()!-positions.min()! <= 4 else {
                    observations.append(nil); continue
                }
                let sorted = positions.sorted(), depth = (sorted[2]+sorted[3])/2
                observations.append(.init(x:base.x+depth*nx,y:base.y+depth*ny))
            }
            diagnosticSink?("printed-continuity \(side.rawValue) supported=\(observations.compactMap { $0 }.count)")
            return .init(side:side.rawValue,observations:observations)
        }

        static func observedPhysicalPath(_ side: Side, seed: CardCenteringQuad, source: UIImage) -> ObservedPath? {
            let line = edge(seed,side), a = line.start, b = line.end
            let length = hypot(b.x-a.x,b.y-a.y)
            guard length > 24 else { return nil }
            let nx = -(b.y-a.y)/length, ny = (b.x-a.x)/length
            guard let crop = CardCenteringNativeRefiner.crop(source: source, orientedRect: CGRect(
                x: min(a.x,b.x)-100, y: min(a.y,b.y)-100,
                width: abs(b.x-a.x)+200, height: abs(b.y-a.y)+200)) else { return nil }
            func point(_ t: Double, _ depth: Double) -> Point {
                .init(x: a.x+t*(b.x-a.x)+depth*nx, y: a.y+t*(b.y-a.y)+depth*ny)
            }
            func value(_ t: Double, _ depth: Double, _ width: Double) -> Double? {
                var sum = 0.0
                for i in 0..<9 {
                    guard let c = crop.color(at: point(t+(-width+2*width*Double(i)/8)/length,depth)) else { return nil }
                    sum += (c.0+c.1+c.2)/3
                }
                return sum/9
            }
            let stations = (0..<61).map { 0.1+0.8*Double($0)/60 }
            let contrasts = stations.compactMap { t -> Double? in
                guard let a = value(t,-80,4), let b = value(t,80,4) else { return nil }
                return a-b
            }
            let positive = contrasts.filter { $0 >= 10 }.count, negative = contrasts.filter { $0 <= -10 }.count
            guard contrasts.count >= 50, Double(max(positive,negative))/Double(contrasts.count) >= 0.8 else { return nil }
            let polarity = positive > negative ? 1.0 : -1.0
            var observations: [Point?] = []
            for t in stations {
                guard !Task.isCancelled else { return nil }
                var depths: [Double] = []
                for width in [4.0,8.0,16.0] {
                    let scores = (-80...80).map { d -> Double in
                        guard let a = value(t,Double(d)-1.5,width), let b = value(t,Double(d)+1.5,width) else { return -.infinity }
                        return polarity*(a-b)
                    }
                    let peaks = (1..<scores.count-1).filter {
                        scores[$0] >= 10 && scores[$0] >= scores[$0-1] && scores[$0] > scores[$0+1]
                    }.sorted { scores[$0] > scores[$1] }
                    guard let best = peaks.first,
                          !peaks.dropFirst().contains(where: { abs($0-best) >= 4 && scores[$0] >= scores[best]*0.5 }) else { continue }
                    let curvature = scores[best-1]-2*scores[best]+scores[best+1]
                    let fraction = curvature.isFinite && curvature < -1e-9
                        ? max(-0.5,min(0.5,0.5*(scores[best-1]-scores[best+1])/curvature)) : 0
                    depths.append(Double(best-80)+fraction)
                }
                guard depths.count >= 2, depths.max()!-depths.min()! <= 4 else { observations.append(nil); continue }
                let sorted = depths.sorted()
                let depth = sorted.count == 2 ? (sorted[0]+sorted[1])/2 : sorted[1]
                observations.append(point(t,depth))
            }
            diagnosticSink?("physical-path \(side.rawValue) supported=\(observations.compactMap { $0 }.count)")
            return .init(side: side.rawValue, observations: observations)
        }

        /// A review-only proposal where textured card material meets a dark,
        /// fading exterior. A printed stripe can imitate this signal, so this
        /// method must never select a cut or supply an automatic measurement.
        /// Every sample must be inside the original image; clipped strips are
        /// unavailable rather than padded or clamped into apparent evidence.
        static func unverifiedShadowContactCandidate(_ side: Side, seed: CardCenteringQuad,
                                                      source: UIImage) -> CardCenteringBoundaryCandidate? {
            let line = edge(seed,side), a = line.start, b = line.end
            let length = hypot(b.x-a.x,b.y-a.y)
            guard length > 24 else { return nil }
            let tx = (b.x-a.x)/length, ty = (b.y-a.y)/length
            let nx = ty, ny = -tx // outward from the clockwise seed
            guard let crop = CardCenteringNativeRefiner.crop(source:source,orientedRect:CGRect(
                x:min(a.x,b.x)-120,y:min(a.y,b.y)-120,
                width:abs(b.x-a.x)+240,height:abs(b.y-a.y)+240)) else { return nil }
            struct Sample { let light, texture: Double }
            func profile(_ base: Point, width: Int) -> [Sample?] {
                (-88...104).map { depth -> Sample? in
                    var sum = 0.0, difference = 0.0, previous: Double?
                    for shift in -width...width {
                        let p = Point(x:base.x+Double(depth)*nx+Double(shift)*tx,
                                      y:base.y+Double(depth)*ny+Double(shift)*ty)
                        guard let c = crop.color(at:p) else { return nil }
                        let light = (c.0+c.1+c.2)/3
                        if let previous { difference += abs(light-previous) }
                        previous = light; sum += light
                    }
                    return Sample(light:sum/Double(2*width+1),texture:difference/Double(2*width))
                }
            }
            func peak(_ samples: [Sample?]) -> Double? {
                func gradient(_ i: Int) -> Double? {
                    guard samples.indices.contains(i-1),samples.indices.contains(i+1),
                          let inside = samples[i-1],let outside = samples[i+1] else { return nil }
                    return inside.light-outside.light
                }
                func mean(_ center: Int, _ range: ClosedRange<Int>, texture: Bool = false) -> Double? {
                    var total = 0.0
                    for d in range {
                        guard samples.indices.contains(center+d),let value = samples[center+d] else { return nil }
                        total += texture ? value.texture : value.light
                    }
                    return total/Double(range.count)
                }
                var peaks: [(position:Double,strength:Double)] = []
                for i in 8..<(samples.count-24) {
                    let offset = i-88
                    guard abs(offset) <= 80, let before = gradient(i-1),let value = gradient(i),
                          let after = gradient(i+1),value >= 10,value >= before,value > after,
                          let inside = mean(i,-8 ... -3),let shadow = mean(i,2...8),
                          let background = mean(i,14...24),let insideTexture = mean(i,-8 ... -3,texture:true),
                          let outsideTexture = mean(i,14...24,texture:true),
                          inside-shadow >= 20,background-shadow >= 30,
                          insideTexture >= 3,insideTexture >= 2*outsideTexture+2 else { continue }
                    let curvature = before-2*value+after
                    let fraction = curvature < -1e-9 ? max(-0.5,min(0.5,0.5*(before-after)/curvature)) : 0
                    peaks.append((Double(offset)+fraction,value))
                }
                var distinct: [(position:Double,strength:Double)] = []
                for candidate in peaks.sorted(by: { $0.strength > $1.strength })
                    where !distinct.contains(where: { abs($0.position-candidate.position) < 4 }) {
                    distinct.append(candidate)
                }
                return distinct.count == 1 ? distinct[0].position : nil
            }
            var observed: [(station:Int,point:Point)] = []
            for station in 0..<61 {
                guard !Task.isCancelled else { return nil }
                let t = 0.1+0.8*Double(station)/60
                let base = Point(x:a.x+t*(b.x-a.x),y:a.y+t*(b.y-a.y))
                var positions: [Double] = []
                for width in [8,16,32] {
                    guard let found = peak(profile(base,width:width)) else { break }
                    positions.append(found)
                }
                guard positions.count == 3,positions.max()!-positions.min()! <= 4 else { continue }
                let depth = positions.sorted()[1]
                observed.append((station,.init(x:base.x+depth*nx,y:base.y+depth*ny)))
            }
            let bins = Set(observed.map { min(4,$0.station*5/61) })
            guard observed.count >= 30,bins.count >= 4,
                  let first = observed.first,let last = observed.last,
                  first.station <= 7,last.station >= 53 else { return nil }
            let points = observed.map { $0.point }
            let along = points.map { side.isVertical ? $0.y : $0.x }
            let across = points.map { side.isVertical ? $0.x : $0.y }
            let mx = along.reduce(0,+)/Double(along.count),my = across.reduce(0,+)/Double(across.count)
            let variance = along.reduce(0) { $0+pow($1-mx,2) }
            guard variance > 0 else { return nil }
            let slope = zip(along,across).reduce(0) { $0+($1.0-mx)*($1.1-my) }/variance
            func fitted(_ x: Double) -> Point {
                let y = my+slope*(x-mx)
                return side.isVertical ? .init(x:y,y:x) : .init(x:x,y:y)
            }
            let fittedLine = Line(start:fitted(along.min()!),end:fitted(along.max()!))
            let residual = sqrt(zip(along,across).reduce(0) { $0+pow($1.1-(my+slope*($1.0-mx)),2) }
                / Double(points.count))/sqrt(1+slope*slope)
            guard fittedLine.isValid,residual <= 4 else { return nil }
            return .init(id:"research-shadow-contact-\(side.rawValue)",frame:.outer,side:side,
                nativeLine:fittedLine,source:"research.shadow_contact_unverified",proposedRole:.unknown,
                competingRoles:[.physicalCut,.printedBorder,.shadow],signal:"texture_to_dark_exterior",
                strength:nil,polarity:nil,coverage:Double(points.count)/61,fitResidualNativePixels:residual,
                sampleBands:[.init(start:fittedLine.start,end:fittedLine.end,sampleCount:points.count)],
                exclusions:[],selectionReason:.competingCandidate,
                reason:"Unidentified edge; compare with the photo. The straight guide approximates supported points and missing stations remain unknown.",
                observedPoints:points,observedPointStations:observed.map { $0.station })
        }

        /// Keep existing selected guides and partial evidence intact. This
        /// explicit research route only adds comparable, unverified options.
        static func appendingShadowContactCandidates(baseline: CardCenteringAnalysis, source: UIImage,
                                                       sides: [Side]) -> CardCenteringAnalysis {
            guard !baseline.measurement.hasObservedPaths,let mapping = baseline.coordinateMapping else { return baseline }
            let seed = mapping.nativeQuad(fromWorking:baseline.measurement.geometryOuterQuad)
            var measurement = baseline.measurement
            var seen = Set<Side>()
            for side in sides where seen.insert(side).inserted {
                guard !Task.isCancelled else { return baseline }
                if let candidate = unverifiedShadowContactCandidate(side,seed:seed,source:source) {
                    measurement.retainUnverifiedBoundaryCandidate(candidate)
                }
            }
            guard !Task.isCancelled else { return baseline }
            return .init(image:baseline.image,measurement:measurement,coordinateMapping:mapping,
                appliedRotationDegrees:baseline.appliedRotationDegrees,detectedSkewDegrees:baseline.detectedSkewDegrees,
                nativeSourceData:baseline.nativeSourceData)
        }

        /// Ratios use corresponding observed stations, not extrapolated artwork
        /// lines. This opt-in result is kept separate from existing guide/report state.
        static func measureObservedPaths(outer: [ObservedPath], inner: [ObservedPath],
                                         outerSeed: CardCenteringQuad, innerSeed: CardCenteringQuad) -> ObservedMeasurement? {
            guard outer.count == 4, inner.count == 4,
                  Set(outer.map(\.side)) == Set(Side.allCases.map(\.rawValue)),
                  Set(inner.map(\.side)) == Set(Side.allCases.map(\.rawValue)) else { return nil }
            let rect = CardCenteringRectification(outerQuad: outerSeed)
            guard rect.isNumericallyValid else { return nil }
            func normalized(_ p: Point) -> Point {
                let q = rect.rectifiedPoint(from: p)
                return .init(x: q.x/rect.targetSize.width,y: q.y/rect.targetSize.height)
            }
            let seed = CardCenteringQuad(topLeft: normalized(innerSeed.topLeft), topRight: normalized(innerSeed.topRight),
                bottomRight: normalized(innerSeed.bottomRight), bottomLeft: normalized(innerSeed.bottomLeft))
            func span(_ sides: [Side]) -> (Double, Double)? {
                let intervals = sides.map { side -> (Double,Double) in
                    let l = edge(seed,side)
                    let a = side.isVertical ? l.start.y : l.start.x, b = side.isVertical ? l.end.y : l.end.x
                    let lo = min(a,b), hi = max(a,b)
                    return (lo+0.2*(hi-lo),lo+0.8*(hi-lo))
                }
                let lo = intervals.map { $0.0 }.max()!, hi = intervals.map { $0.1 }.min()!
                return lo > 0 && hi < 1 && lo < hi ? (lo,hi) : nil
            }
            guard let xs = span([.top,.bottom]), let ys = span([.left,.right]) else { return nil }
            func samples(_ path: ObservedPath) -> [Double]? {
                guard let side = Side(rawValue: path.side), path.observations.count == 61 else { return nil }
                let values = path.observations.enumerated().compactMap { index,p -> (Int,Double,Double)? in
                    guard let p else { return nil }; let q = normalized(p)
                    return (index,side.isVertical ? q.y : q.x,side.isVertical ? q.x : q.y)
                }.sorted { $0.1 < $1.1 }
                guard values.count >= 30, values.allSatisfy({ $0.1.isFinite && $0.2.isFinite }),
                      zip(values,values.dropFirst()).allSatisfy({ $1.1 > $0.1 }) else { return nil }
                let domain = side.isVertical ? ys : xs
                guard let first = values.lastIndex(where: { $0.1 <= domain.0 }),
                      let last = values.firstIndex(where: { $0.1 >= domain.1 }) else { return nil }
                let bracket = values[first...last]
                guard zip(bracket,bracket.dropFirst()).allSatisfy({ abs($1.0-$0.0) <= 7 }) else { return nil }
                return (0..<31).map { station in
                    let x = domain.0+(domain.1-domain.0)*Double(station)/30
                    let right = max(1,values.firstIndex(where: { $0.1 >= x })!)
                    let a = values[right-1], b = values[right]
                    return a.2+(b.2-a.2)*(x-a.1)/(b.1-a.1)
                }
            }
            var margins: [Side:[Double]] = [:]
            for side in Side.allCases {
                guard let o = samples(outer.first(where: { $0.side == side.rawValue })!),
                      let i = samples(inner.first(where: { $0.side == side.rawValue })!) else { return nil }
                let sign = side == .left || side == .top ? 1.0 : -1.0
                let widths = zip(i,o).map { ($0-$1)*sign }
                guard widths.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
                margins[side] = widths
            }
            let left = zip(margins[.left]!,margins[.right]!).map { 100*$0/($0+$1) }
            let top = zip(margins[.top]!,margins[.bottom]!).map { 100*$0/($0+$1) }
            var means: [String:Double] = [:]
            for (side,values) in margins { means[side.rawValue] = values.reduce(0,+)/31 }
            return .init(outerPaths: outer,innerPaths: inner,leftShare: left.reduce(0,+)/31,topShare: top.reduce(0,+)/31,
                         localLeftShares: left,localTopShares: top,
                         meanMargins: means,
                         measurementOuterQuad: outerSeed)
        }

        static func observedMeasurement(reference: CardCenteringPrintReference, analysis: CardCenteringAnalysis,
                                        source: UIImage) -> ObservedMeasurement? {
            guard let region = registeredRegion(reference,in: analysis) else { return nil }
            return observedMeasurement(reference: reference, analysis: analysis, region: region, source: source)
        }

        // The selected design's registration is immutable for this analysis;
        // reuse it for all four paths rather than registering each side again.
        private static func observedMeasurement(reference: CardCenteringPrintReference, analysis: CardCenteringAnalysis,
                                                region: CardCenteringQuad, source: UIImage) -> ObservedMeasurement? {
            guard let mapping = analysis.coordinateMapping else { return nil }
            let outerSeed = mapping.nativeQuad(fromWorking: analysis.measurement.geometryOuterQuad)
            let inner: [ObservedPath]
            let innerSeed: CardCenteringQuad
            if reference.boundaryMethod == .printedContinuity {
                guard let workingSeed = analysis.measurement.geometryInnerQuad else { return nil }
                innerSeed = mapping.nativeQuad(fromWorking:workingSeed)
                // Recognize the design first, then require the existing proposal
                // to identify the same frame. Publisher coordinates never replace
                // an observed cut or printed path. Reuse the 24px seed gate.
                guard Side.allCases.allSatisfy({ side in
                    let line = edge(innerSeed,side), target = edge(region,side)
                    return (distance(line.start,target)+distance(line.end,target))/2 < 24
                }) else { return nil }
                inner = Side.allCases.compactMap { observedPrintedContinuityPath($0,seed:innerSeed,source:source) }
            } else {
                innerSeed = region
                inner = Side.allCases.compactMap { observedArtworkPath($0,reference: reference,region: region,source: source) }
            }
            let outer = Side.allCases.compactMap { observedPhysicalPath($0,seed: outerSeed,source: source) }
            guard !Task.isCancelled else { return nil }
            return measureObservedPaths(outer: outer,inner: inner,outerSeed: outerSeed,innerSeed: innerSeed)
        }

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
            let signals = Set(reference.patches.flatMap { ($0.colorAlternatives ?? []).map(\.signal) })
            var colorGrids: [CardCenteringPrintReference.ColorSignal: [UInt8]] = [:]
            if !signals.isEmpty {
                var rgba = [UInt8](repeating: 0, count: w * h * 4)
                let decoded = rgba.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                        bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
                    else { return false }
                    context.interpolationQuality = .high
                    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                    return true
                }
                guard decoded else { return nil }
                for signal in signals {
                    let channel = signal == .redGreenChromaticity ? 0 : 2
                    var values = [UInt8](repeating: 0, count: w * h)
                    for i in values.indices {
                        let r = Int(rgba[4*i]), g = Int(rgba[4*i+1]), b = Int(rgba[4*i+2])
                        let difference = Int(rgba[4*i+channel]) - g
                        values[i] = UInt8(clamping: Int((127.5 * (1 + Double(difference) / Double(max(1, r+g+b)))).rounded()))
                    }
                    var sampled = [UInt8](repeating: 0, count: 320 * 448)
                    TCSCenteringSamplePrintGrid(values, Int32(w), Int32(h), corners, &sampled)
                    colorGrids[signal] = sampled
                }
            }
            var matches: [(patch: CardCenteringPrintReference.Patch, dx: Double, dy: Double)] = []
            for patch in reference.patches {
                guard !Task.isCancelled else { return nil }
                var dx = 0.0
                var dy = 0.0
                var score = patch.pixels.withUnsafeBytes { bytes in
                    TCSCenteringMatchPatch(
                        grid, 320, 448, bytes.bindMemory(to: UInt8.self).baseAddress,
                        Int32(patch.x), Int32(patch.y), &dx, &dy)
                }
                // Different signals at one position are alternative observations,
                // never extra identity votes. All original spatial gates remain.
                for alternative in patch.colorAlternatives ?? [] {
                    guard let values = colorGrids[alternative.signal] else { continue }
                    var x = 0.0, y = 0.0
                    let candidate = alternative.pixels.withUnsafeBytes { bytes in
                        TCSCenteringMatchPatch(values, 320, 448, bytes.bindMemory(to: UInt8.self).baseAddress,
                            Int32(patch.x), Int32(patch.y), &x, &y)
                    }
                    if candidate > score { score = candidate; dx = x; dy = y }
                }
                if score >= 0.80 { matches.append((patch, dx, dy)) }
            }
            let inside = matches.filter { $0.patch.interior }
            diagnosticSink?("print-match patches=\(matches.count) interior=\(inside.count)")
            guard inside.count >= 10 else { return nil }
            let dx = inside.map(\.dx).sorted()[inside.count / 2]
            let dy = inside.map(\.dy).sorted()[inside.count / 2]
            let coherent = matches.filter { abs($0.dx - dx) <= 2 && abs($0.dy - dy) <= 2 }
            let interior = coherent.filter { $0.patch.interior }
            let mx = (reference.left + reference.right) * 160
            let my = (reference.top + reference.bottom) * 224
            let quadrants = Set(interior.map { (Double($0.patch.x) > mx ? 1 : 0) + (Double($0.patch.y) > my ? 2 : 0) })
            let corroboration = coherent.filter { !$0.patch.interior }
            if reference.isPrintedBorder {
                guard let bounds = reference.identityArtworkBounds else { return nil }
                let art = interior.filter {
                    $0.patch.identityArtwork == true
                        && Double($0.patch.x) / 320 >= bounds.left && Double($0.patch.x) / 320 <= bounds.right
                        && Double($0.patch.y) / 448 >= bounds.top && Double($0.patch.y) / 448 <= bounds.bottom
                }
                let ax = (bounds.left + bounds.right) * 160
                let ay = (bounds.top + bounds.bottom) * 224
                let artQuadrants = Set(art.map { (Double($0.patch.x) > ax ? 1 : 0) + (Double($0.patch.y) > ay ? 2 : 0) })
                diagnosticSink?("print-identity artwork=\(art.count) quadrants=\(artQuadrants.count)")
                guard art.count >= 6, artQuadrants.count == 4 else { return nil }
            }
            let upperCorroboration = reference.isPrintedBorder ? 0.14 : reference.top
            let lowerCorroboration = reference.isPrintedBorder ? 0.86 : reference.bottom
            diagnosticSink?("print-coverage interior=\(interior.count) quadrants=\(quadrants.count) corroboration=\(corroboration.count)")
            guard interior.count >= 10, quadrants.count == 4,
                corroboration.contains(where: { Double($0.patch.y) < upperCorroboration * 448 }),
                corroboration.contains(where: { Double($0.patch.y) > lowerCorroboration * 448 }) else {
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
        static func hasSupportedMeasurementSpan(_ positions: [Double]) -> Bool {
            let ordered = positions.sorted()
            guard ordered.count >= 30,
                let first = ordered.lastIndex(where: { $0 <= 0.20 }),
                let last = ordered.firstIndex(where: { $0 >= 0.80 }) else { return false }
            let span = ordered[first...last]
            return zip(span, span.dropFirst()).allSatisfy { $1 - $0 <= 7 * 0.70 / 60 + 1e-9 }
        }

        static func supportedLinesAgree(_ lines: [Line]) -> Bool {
            guard !lines.isEmpty else { return false }
            for line in lines {
                for other in lines {
                    for t in [0.20, 0.50, 0.80] {
                        let point = Point(x: line.start.x + t * (line.end.x-line.start.x),
                                          y: line.start.y + t * (line.end.y-line.start.y))
                        guard distance(point, other) <= 4 else { return false }
                    }
                }
            }
            return true
        }

        private static func fit(_ side: Side, seed: CardCenteringQuad, source: UIImage, printedBorder: Bool = false,
                                stripHalfWidth: Double = 0)
            -> CardCenteringBoundaryCandidate?
        {
            let line = edge(seed, side)
            let a = line.start
            let b = line.end
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 24 else { return nil }
            let nx = -(b.y - a.y) / length
            let ny = (b.x - a.x) / length
            let padding = 13 + stripHalfWidth
            let box = CGRect(
                x: min(a.x, b.x) - padding, y: min(a.y, b.y) - padding,
                width: abs(a.x - b.x) + 2 * padding, height: abs(a.y - b.y) + 2 * padding)
            guard let crop = CardCenteringNativeRefiner.crop(source: source, orientedRect: box) else { return nil }
            typealias Sample = (t: Double, depth: Double, strength: Double)
            var samples: [Sample] = []
            func point(_ t: Double, _ d: Double) -> Point {
                .init(x: a.x + t * (b.x - a.x) + d * nx, y: a.y + t * (b.y - a.y) + d * ny)
            }
            func color(_ t: Double, _ d: Double) -> (Double, Double, Double)? {
                guard stripHalfWidth > 0 else { return crop.color(at: point(t, d)) }
                var total = (0.0, 0.0, 0.0)
                for i in 0..<9 {
                    let shift = -stripHalfWidth + 2 * stripHalfWidth * Double(i) / 8
                    guard let value = crop.color(at: point(t + shift / length, d)) else { return nil }
                    total.0 += value.0; total.1 += value.1; total.2 += value.2
                }
                return (total.0 / 9, total.1 / 9, total.2 / 9)
            }
            for i in 0..<61 {
                let t = 0.15 + 0.70 * Double(i) / 60
                var peak = 2.5
                var selected: Double?
                for k in -14...14 {
                    let d = Double(k) / 2
                    guard let u = color(t, d - 1.5), let v = color(t, d + 1.5) else {
                        continue
                    }
                    // Foil/ink can reverse brightness polarity. The recognized
                    // printed frame uses observed color contrast near its candidate;
                    // the established artwork fitter keeps its signed drop.
                    let strength = printedBorder
                        ? (abs(u.0-v.0) + abs(u.1-v.1) + abs(u.2-v.2)) / 3
                        : (u.0 + u.1 + u.2 - v.0 - v.1 - v.2) / 3
                    if strength > peak {
                        peak = strength
                        selected = d
                    }
                }
                if let selected { samples.append((t, selected, peak)) }
            }
            if let diagnosticSink,
                let data = try? JSONSerialization.data(withJSONObject: [
                    "side": side.rawValue,
                    "stripHalfWidth": stripHalfWidth,
                    "start": [a.x, a.y], "end": [b.x, b.y],
                    "samples": samples.map { [$0.t, $0.depth] },
                    "strengths": samples.map { $0.strength },
                ], options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) {
                diagnosticSink("print-observations " + json)
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
            diagnosticSink?("print-consensus \(side.rawValue) raw=\(samples.count) retained=\(kept.count) slope=\(slope) offset=\(offset) span=\(kept.map(\.t))")
            guard kept.count >= 25, Set(kept.map { min(4, Int(($0.t - 0.15) * 5 / 0.70)) }).count >= 4 else {
                return nil
            }
            // Both artwork and printed frames need observations across the
            // measured side. Sparse artwork texture must not pass as a rule
            // merely because a line can be fitted through 25 local peaks.
            guard hasSupportedMeasurementSpan(kept.map(\.t)) else { return nil }
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
                source: printedBorder ? "selected.print_border" : "selected.print_artwork",
                proposedRole: printedBorder ? .printedBorder : .artwork,
                competingRoles: printedBorder ? [.artwork] : [.printedBorder],
                signal: printedBorder ? (stripHalfWidth > 0 ? "native_color_contrast_strip_consensus" : "native_color_contrast") : "inward_brightness_drop", strength: nil,
                polarity: printedBorder ? 0 : -1, coverage: Double(kept.count) / 61,
                fitResidualNativePixels: rms,
                sampleBands: [.init(start: fit.start, end: fit.end, sampleCount: points.count)],
                exclusions: [], selectionReason: .detectorProposal,
                reason: printedBorder ? "Printed border located from the supplied design and measured in the photo." : "Artwork located from the supplied print.",
                observedPoints: points)
        }

        /// Physical cuts use observed background polarity, independently of print
        /// identity. Multiple strong transitions (including sleeves) reject.
        static func physicalSide(_ side: Side, seed: CardCenteringQuad, source: UIImage)
            -> CardCenteringBoundaryCandidate? {
            let line = edge(seed, side), a = line.start, b = line.end
            let length = hypot(b.x-a.x, b.y-a.y)
            guard length > 24 else { return nil }
            let nx = -(b.y-a.y)/length, ny = (b.x-a.x)/length
            let radius = 80, padding = 100.0
            guard let crop = CardCenteringNativeRefiner.crop(source: source, orientedRect: CGRect(
                x: min(a.x,b.x)-padding, y: min(a.y,b.y)-padding,
                width: abs(b.x-a.x)+2*padding, height: abs(b.y-a.y)+2*padding)) else { return nil }
            func point(_ t: Double, _ d: Double) -> Point {
                .init(x: a.x+t*(b.x-a.x)+d*nx, y: a.y+t*(b.y-a.y)+d*ny)
            }
            func luminance(_ t: Double, _ d: Double, _ width: Double) -> Double? {
                var sum = 0.0
                for i in 0..<9 {
                    guard let c = crop.color(at: point(t+(-width+2*width*Double(i)/8)/length,d)) else { return nil }
                    sum += (c.0+c.1+c.2)/3
                }
                return sum/9
            }
            let positions = (0..<61).map { 0.15+0.70*Double($0)/60 }
            let contrasts = positions.compactMap { t -> Double? in
                guard let outside = luminance(t,-Double(radius),4),
                    let inside = luminance(t,Double(radius),4) else { return nil }
                return outside-inside
            }
            guard contrasts.count >= 50 else { return nil }
            let positive = contrasts.filter { $0 >= 10 }.count
            let negative = contrasts.filter { $0 <= -10 }.count
            guard Double(max(positive,negative))/Double(contrasts.count) >= 0.8 else { return nil }
            let polarity = positive > negative ? 1.0 : -1.0
            var trials: [CardCenteringBoundaryCandidate] = []
            for width in [4.0,8.0,16.0] {
                if Task.isCancelled { return nil }
                var observations: [(t: Double, depth: Double, strength: Double)] = []
                for t in positions {
                    let scores = (-radius...radius).map { d -> Double in
                        guard let outside = luminance(t,Double(d)-1.5,width),
                            let inside = luminance(t,Double(d)+1.5,width) else { return -.infinity }
                        return polarity*(outside-inside)
                    }
                    let peaks = (1..<(scores.count-1)).filter {
                        scores[$0] >= 10 && scores[$0] >= scores[$0-1] && scores[$0] > scores[$0+1]
                    }.sorted { scores[$0] > scores[$1] }
                    guard let best = peaks.first,
                        !peaks.dropFirst().contains(where: { abs($0-best) >= 4 && scores[$0] >= scores[best]*0.5 })
                    else { continue }
                    let curvature = scores[best-1]-2*scores[best]+scores[best+1]
                    let fraction = curvature.isFinite && curvature < -1e-9
                        ? max(-0.5,min(0.5,0.5*(scores[best-1]-scores[best+1])/curvature)) : 0
                    observations.append((t,Double(best-radius)+fraction,scores[best]))
                }
                guard hasSupportedMeasurementSpan(observations.map(\.t)) else { continue }
                var slopes: [Double] = []
                for (i,p) in observations.enumerated() {
                    for q in observations.dropFirst(i+1) where q.t-p.t > 0.22 {
                        slopes.append((q.depth-p.depth)/(q.t-p.t))
                    }
                }
                guard !slopes.isEmpty else { continue }
                let slope = slopes.sorted()[slopes.count/2]
                let intercepts = observations.map { $0.depth-$0.t*slope }.sorted()
                let intercept = intercepts[intercepts.count/2]
                let kept = observations.filter { abs($0.depth-intercept-$0.t*slope) <= 3 }
                diagnosticSink?("physical-fit \(side.rawValue) width=\(width) raw=\(observations.count) retained=\(kept.count)")
                guard hasSupportedMeasurementSpan(kept.map(\.t)) else { continue }
                let mt = kept.map(\.t).reduce(0,+)/Double(kept.count)
                let md = kept.map(\.depth).reduce(0,+)/Double(kept.count)
                let variance = kept.reduce(0) { $0+pow($1.t-mt,2) }
                guard variance > 0 else { continue }
                let m = kept.reduce(0) { $0+($1.t-mt)*($1.depth-md) }/variance
                let d = md-m*mt
                let fitted = Line(start: point(0,d),end: point(1,d+m))
                let points = kept.map { point($0.t,$0.depth) }
                let residual = sqrt(points.reduce(0) { $0+pow(distance($1,fitted),2) }/Double(points.count))
                trials.append(.init(id: "physical-background-\(side.rawValue)-\(Int(width))", frame: .outer,
                    side: side, nativeLine: fitted, source: "selected.physical_background",
                    proposedRole: .physicalCut, competingRoles: [.shadow,.sleeveOrSlab],
                    signal: "native_background_contrast_consensus", strength: kept.map(\.strength).reduce(0,+)/Double(kept.count),
                    polarity: polarity, coverage: Double(kept.count)/61, fitResidualNativePixels: residual,
                    sampleBands: [.init(start: fitted.start,end: fitted.end,sampleCount: kept.count)],
                    exclusions: [], selectionReason: .detectorProposal,
                    reason: "Card edge measured from consistent background contrast.", observedPoints: points))
            }
            guard trials.count >= 2, supportedLinesAgree(trials.map(\.nativeLine)) else { return nil }
            return trials.first(where: { $0.id.hasSuffix("-8") }) ?? trials[0]
        }

        static func apply(_ reference: CardCenteringPrintReference, baseline: CardCenteringAnalysis, source: UIImage,
                          candidateScan: () throws -> [CardCenteringBoundaryCandidate])
            -> CardCenteringAnalysis
        {
            apply([reference], baseline: baseline, source: source) { _ in try candidateScan() }
        }

        /// Select by image evidence before fitting geometry. Neither library order
        /// nor a later fit failure resolves conflicting design identities.
        static func apply(_ references: [CardCenteringPrintReference], baseline: CardCenteringAnalysis, source: UIImage,
                          candidateScan: (CardCenteringPrintReference) throws -> [CardCenteringBoundaryCandidate])
            -> CardCenteringAnalysis
        {
            var seen = Set<CardCenteringPrintReference>()
            var selected: (reference: CardCenteringPrintReference, region: CardCenteringQuad)?
            for reference in references where seen.insert(reference).inserted {
                guard !Task.isCancelled else { return baseline }
                if let region = registeredRegion(reference, in: baseline) {
                    guard selected == nil else {
                        diagnosticSink?("print-library ambiguous; retaining ordinary result")
                        return baseline
                    }
                    selected = (reference, region)
                }
            }
            guard let selected, !Task.isCancelled else { return baseline }
            diagnosticSink?("print-library selected=\(selected.reference.label)")
            return applyMatched(selected.reference, region: selected.region, baseline: baseline, source: source) {
                try candidateScan(selected.reference)
            }
        }

        /// Straight scaffolds are only for explicit manual mode and compatibility.
        /// Curved rendering and ratios continue to use the observed paths.
        private static func guideQuad(_ paths: [ObservedPath]) -> CardCenteringQuad? {
            var lines: [Side:Line] = [:]
            for path in paths {
                guard let side = Side(rawValue: path.side) else { return nil }
                let points = path.observations.compactMap { $0 }
                guard points.count >= 30 else { return nil }
                let x = points.map { side.isVertical ? $0.y : $0.x }
                let y = points.map { side.isVertical ? $0.x : $0.y }
                let mx = x.reduce(0,+)/Double(x.count), my = y.reduce(0,+)/Double(y.count)
                let variance = x.reduce(0) { $0+pow($1-mx,2) }
                guard variance > 0 else { return nil }
                let slope = zip(x,y).reduce(0) { $0+($1.0-mx)*($1.1-my) }/variance
                func point(_ t: Double) -> Point {
                    let v = my+slope*(t-mx)
                    return side.isVertical ? .init(x:v,y:t) : .init(x:t,y:v)
                }
                lines[side] = .init(start: point(x.min()!),end: point(x.max()!))
            }
            return quad(lines)
        }

        private static func applyMatched(_ reference: CardCenteringPrintReference, region: CardCenteringQuad,
                                         baseline: CardCenteringAnalysis, source: UIImage,
                                         candidateScan: () throws -> [CardCenteringBoundaryCandidate]) -> CardCenteringAnalysis {
            if reference.boundaryProfiles?.count == 4 || reference.boundaryMethod == .printedContinuity {
                guard let mapping = baseline.coordinateMapping,
                      let observed = observedMeasurement(reference: reference,analysis: baseline,region: region,source: source),
                      let outer = guideQuad(observed.outerPaths), let inner = guideQuad(observed.innerPaths),
                      !Task.isCancelled else { return baseline }
                let old = baseline.measurement
                var measurement = CardCenteringMeasurement(imageWidth: old.imageWidth,imageHeight: old.imageHeight,
                    outerQuad: mapping.workingQuad(fromNative: outer),innerQuad: mapping.workingQuad(fromNative: inner),
                    warnings: [],coordinateMapping: mapping,innerReference: reference.isPrintedBorder ? .printedBorder : .artWindow,
                    confidence: .declined(reason: reference.isPrintedBorder
                        ? "Review the detected card and printed border edges."
                        : "Review the detected curved card and artwork edges."),
                    inputRecord: old.inputRecord,referenceDefinition: reference.isPrintedBorder ? .matchedPrintedBorder : .matchedArtwork)
                measurement.observedPrintMeasurement = observed
                measurement.printPlacement = .init(label: reference.label,sourceSHA256: reference.sourceSHA256,
                    designLeft: 100*reference.left/(reference.left+1-reference.right),
                    designTop: 100*reference.top/(reference.top+1-reference.bottom))
                guard measurement.hasValidFrameGeometry else { return baseline }
                return .init(image: baseline.image,measurement: measurement,coordinateMapping: mapping,
                    appliedRotationDegrees: baseline.appliedRotationDegrees,detectedSkewDegrees: baseline.detectedSkewDegrees,
                    nativeSourceData: baseline.nativeSourceData)
            }
            guard !Task.isCancelled, let mapping = baseline.coordinateMapping, let pool = try? candidateScan()
            else { return baseline }
            var seeds: [Side: Line] = [:]
            var tiedSeeds: [Side: [Line]] = [:]
            var eligibleSeeds: [Side: [Line]] = [:]
            for side in Side.allCases {
                let target = edge(region, side)
                let ranked = pool.filter { $0.side == side && $0.frame == .inner }.map { candidate in
                    (
                        candidate.nativeLine,
                        (distance(candidate.nativeLine.start, target) + distance(candidate.nativeLine.end, target)) / 2
                    )
                }.sorted { $0.1 < $1.1 }
                diagnosticSink?("print-seed \(side.rawValue) candidates=\(ranked.count) distance=\(ranked.first?.1 ?? -1)")
                if let diagnosticSink,
                    let data = try? JSONSerialization.data(withJSONObject: [
                        "side": side.rawValue,
                        "target": [[target.start.x, target.start.y], [target.end.x, target.end.y]],
                        "candidates": ranked.map { ["start": [$0.0.start.x, $0.0.start.y],
                            "end": [$0.0.end.x, $0.0.end.y], "distance": $0.1] as [String: Any] },
                    ], options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) {
                    diagnosticSink("print-seed-candidates " + json)
                }
                guard let best = ranked.first, best.1 < 24 else {
                    return baseline
                }
                eligibleSeeds[side] = ranked.filter { $0.1 < 24 }.map { $0.0 }
                if ranked.count > 1, ranked[1].1 - best.1 < 1 {
                    // Both reference kinds can yield duplicate proposals for
                    // one observed rule. Resolve only through photo-fit agreement;
                    // artwork keeps its signed inward-contrast fitter below.
                    tiedSeeds[side] = ranked.filter { $0.1 < 24 && $0.1 - best.1 < 1 }.map { $0.0 }
                }
                seeds[side] = best.0
            }
            guard let seed = quad(seeds) else { return baseline }
            func refined(_ side: Side, seed: CardCenteringQuad) -> CardCenteringBoundaryCandidate? {
                if let ordinary = fit(side, seed: seed, source: source, printedBorder: reference.isPrintedBorder) {
                    return ordinary
                }
                guard reference.isPrintedBorder else { return nil }
                // Suppress foil texture only on rejected sides. At least two
                // widths must satisfy all original support limits. Every fully
                // supported fit must agree; an incomplete scale supplies no vote.
                let trials = [4.0, 8.0, 16.0].compactMap { width -> (Double, CardCenteringBoundaryCandidate)? in
                    guard let result = fit(side, seed: seed, source: source, printedBorder: true, stripHalfWidth: width)
                    else { return nil }
                    return (width, result)
                }
                diagnosticSink?("print-strip \(side.rawValue) supportedWidths=\(trials.map { $0.0 })")
                guard trials.count >= 2 else { return nil }
                let selected = trials.min { abs($0.0 - 8) < abs($1.0 - 8) }!.1
                guard supportedLinesAgree(trials.map { $0.1.nativeLine }) else { return nil }
                return selected
            }
            let fits = Side.allCases.compactMap { side -> CardCenteringBoundaryCandidate? in
                let initial = tiedSeeds[side] ?? [seeds[side]!]
                func fitLine(_ line: Line) -> CardCenteringBoundaryCandidate? {
                    guard !Task.isCancelled else { return nil }
                    var variant = seeds; variant[side] = line
                    guard let quad = quad(variant) else { return nil }
                    return refined(side, seed: quad)
                }
                // Template distance alone cannot distinguish observations of the
                // same edge. Resolve a tie only through supported photo geometry.
                let candidates = initial.count == 1
                    ? [refined(side, seed: seed)].compactMap { $0 }
                    : initial.compactMap(fitLine)
                if !candidates.isEmpty {
                    diagnosticSink?("print-initial \(side.rawValue) seeds=\(initial.count) supported=\(candidates.count)")
                    guard supportedLinesAgree(candidates.map(\.nativeLine)) else { return nil }
                    return candidates.first
                }
                // Reacquire only after the nearer proposals lack photo support.
                // Keep the original design-distance/search limits and require
                // every supported alternative to agree, independently of order.
                let alternatives = (eligibleSeeds[side] ?? []).filter { !initial.contains($0) }.compactMap(fitLine)
                diagnosticSink?("print-alternate \(side.rawValue) supported=\(alternatives.count)")
                guard supportedLinesAgree(alternatives.map(\.nativeLine)) else { return nil }
                return alternatives.first
            }
            diagnosticSink?("print-fit sides=\(fits.map { $0.side.rawValue })")
            guard fits.count == 4,
                let native = quad(Dictionary(uniqueKeysWithValues: fits.map { ($0.side, $0.nativeLine) })),
                !Task.isCancelled
            else { return baseline }
            let old = baseline.measurement
            // First validated on artwork references with a separate physical
            // perimeter. Printed/foil reference transfer retains its prior cut.
            let outerFits = physicalRefinementEnabled && !reference.isPrintedBorder ? Side.allCases.compactMap {
                physicalSide($0, seed: mapping.nativeQuad(fromWorking: old.geometryOuterQuad), source: source)
            } : []
            let oldNativeOuter = mapping.nativeQuad(fromWorking: old.geometryOuterQuad)
            let needsPhysicalCorrection = outerFits.contains {
                !supportedLinesAgree([$0.nativeLine,edge(oldNativeOuter,$0.side)])
            }
            let outerNative = outerFits.count == 4 && needsPhysicalCorrection
                ? quad(Dictionary(uniqueKeysWithValues: outerFits.map { ($0.side,$0.nativeLine) })) : nil
            let repairedOuter = outerNative.flatMap { candidate -> CardCenteringQuad? in
                let working = mapping.workingQuad(fromNative: candidate)
                let check = CardCenteringMeasurement(imageWidth: old.imageWidth, imageHeight: old.imageHeight,
                    outerQuad: working, innerQuad: mapping.workingQuad(fromNative: native), warnings: [],
                    coordinateMapping: mapping)
                return check.hasValidFrameGeometry ? working : nil
            }
            guard !Task.isCancelled else { return baseline }
            let priorOuter = old.boundaryCandidates.filter { $0.frame == .outer }
            let alternatives = (pool + (repairedOuter == nil ? [] : priorOuter)).map { candidate in
                CardCenteringBoundaryCandidate(
                    id: "print-probe-" + candidate.id, frame: candidate.frame, side: candidate.side,
                    nativeLine: candidate.nativeLine, source: candidate.source, proposedRole: candidate.proposedRole,
                    competingRoles: candidate.competingRoles, signal: candidate.signal, strength: candidate.strength,
                    polarity: candidate.polarity, coverage: candidate.coverage,
                    fitResidualNativePixels: candidate.fitResidualNativePixels,
                    sampleBands: candidate.sampleBands, exclusions: candidate.exclusions,
                    selectionReason: .competingCandidate,
                    reason: candidate.reason, observedPoints: candidate.observedPoints,
                    observedPointStations: candidate.observedPointStations)
            }
            var measurement = CardCenteringMeasurement(
                imageWidth: old.imageWidth, imageHeight: old.imageHeight,
                outerQuad: repairedOuter ?? old.geometryOuterQuad, innerQuad: mapping.workingQuad(fromNative: native),
                warnings: old.warnings,
                detectionNotes: old.detectionNotes,
                coordinateMapping: mapping, innerReference: reference.isPrintedBorder ? .printedBorder : .artWindow,
                confidence: .declined(reason: reference.isPrintedBorder ? "Printed border placement requires review." : "Artwork placement requires review."),
                inputRecord: old.inputRecord,
                boundaryCandidates: fits + (repairedOuter == nil ? priorOuter : outerFits) + alternatives,
                referenceDefinition: reference.isPrintedBorder ? .matchedPrintedBorder : .matchedArtwork)
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
    extension CardCenteringPrintMatcher {
        private struct PrintedStrip {
            let a, b: Point
            let tx, ty, nx, ny: Double
            let crop: CardCenteringNativeRefiner.Crop

            init?(_ side: Side, seed: CardCenteringQuad, source: UIImage) {
                let line = CardCenteringPrintMatcher.edge(seed,side)
                let reverse = side == .left || side == .bottom
                a = reverse ? line.end : line.start; b = reverse ? line.start : line.end
                let length = hypot(b.x-a.x,b.y-a.y)
                guard length > 24 else { return nil }
                tx = (b.x-a.x)/length; ty = (b.y-a.y)/length
                nx = (reverse ? -1 : 1)*ty; ny = (reverse ? 1 : -1)*tx
                guard let value = CardCenteringNativeRefiner.crop(source:source,orientedRect:CGRect(
                    x:min(a.x,b.x)-200,y:min(a.y,b.y)-200,
                    width:abs(b.x-a.x)+400,height:abs(b.y-a.y)+400)) else { return nil }
                crop = value
            }
            func base(_ index: Int) -> Point {
                let t = 0.1+0.8*Double(index)/60
                return .init(x:a.x+t*(b.x-a.x),y:a.y+t*(b.y-a.y))
            }
            func point(_ base: Point, _ depth: Double) -> Point {
                .init(x:base.x+depth*nx,y:base.y+depth*ny)
            }
            func profile(_ base: Point, offsets: [Double], width: Int) -> [SIMD3<Double>]? {
                var result: [SIMD3<Double>] = []
                for offset in offsets {
                    var total = SIMD3<Double>(repeating:0)
                    for shift in -width...width {
                        let p = Point(x:base.x+offset*nx+Double(shift)*tx,
                                      y:base.y+offset*ny+Double(shift)*ty)
                        guard let c = crop.color(at:p) else { return nil }
                        total += SIMD3(c.0,c.1,c.2)
                    }
                    result.append(total/Double(2*width+1))
                }
                return result
            }
        }

        private static func regionGradient(_ values: [SIMD3<Double>], sigma: Double) -> [Double] {
            let radius = Int(4*sigma+0.5)
            let weights = (-radius...radius).map { exp(-Double($0*$0)/(2*sigma*sigma)) }
            let total = weights.reduce(0,+)
            return values.indices.map { index in
                var sum = SIMD3<Double>(repeating:0)
                for offset in -radius...radius {
                    let j = max(0,min(values.count-1,index+offset))
                    sum += values[j]*(Double(offset)*weights[offset+radius]/(sigma*sigma*total))
                }
                return (abs(sum.x)+abs(sum.y)+abs(sum.z))/3
            }
        }

        /// Refines an existing frame proposal; supplies no new design identity.
        static func observedPrintedSeedPath(_ side: Side, seed: CardCenteringQuad, source: UIImage) -> ObservedPath? {
            guard let strip = PrintedStrip(side,seed:seed,source:source) else { return nil }
            var points: [Point?] = []
            for i in 0..<61 {
                guard !Task.isCancelled else { return nil }
                let base = strip.base(i)
                var positions: [Double] = []
                for width in [4,8,16] {
                    guard let raw = strip.profile(base,offsets:(-28...28).map(Double.init),width:width) else { continue }
                    for sigma in [1.0,2.0] {
                        let g = regionGradient(raw,sigma:sigma)
                        guard let best = (22...34).max(by:{ g[$0]<g[$1] }),best != 22,best != 34,g[best]>=2.5 else { continue }
                        let curvature = g[best-1]-2*g[best]+g[best+1]
                        let fraction = curvature < -1e-9 ? max(-0.5,min(0.5,0.5*(g[best-1]-g[best+1])/curvature)) : 0
                        positions.append(Double(best-28)+fraction)
                    }
                }
                guard positions.count == 6,positions.max()!-positions.min()! <= 4 else { points.append(nil);continue }
                let sorted = positions.sorted()
                points.append(strip.point(base,(sorted[2]+sorted[3])/2))
            }
            diagnosticSink?("seed-path \(side.rawValue) supported=\(points.compactMap { $0 }.count)")
            return .init(side:side.rawValue,observations:points)
        }

        private static func physicalDepth(_ base: Point, nx: Double, ny: Double, path: ObservedPath) -> Double? {
            let supported = path.observations.enumerated().compactMap { index,p in p.map { (index,$0) } }
            var hits: [Double] = []
            for (a,b) in zip(supported,supported.dropFirst()) where b.0-a.0 <= 7 {
                let dx = a.1.x-b.1.x, dy = a.1.y-b.1.y
                let vx = a.1.x-base.x, vy = a.1.y-base.y
                let determinant = nx*dy-ny*dx
                guard abs(determinant)>1e-8 else { continue }
                let depth = (vx*dy-vy*dx)/determinant
                let fraction = (nx*vy-ny*vx)/determinant
                if depth>0 && fraction>=0 && fraction<=1 && !hits.contains(where:{ abs($0-depth)<1e-6 }) { hits.append(depth) }
            }
            return hits.count == 1 ? hits[0] : nil
        }

        /// Candidate identity only. A stronger interior rule fails when its
        /// exterior still contains printed material instead of the observed border.
        static func uniformBorderProposal(_ raw: [SIMD3<Double>], exterior: [SIMD3<Double>]) -> Double? {
            guard raw.count == 161,!exterior.isEmpty else { return nil }
            let level = exterior.reduce(SIMD3<Double>(repeating:0),+)/Double(exterior.count)
            let noise = sqrt(exterior.reduce(0) { $0+simd_length_squared($1-level) }/Double(3*exterior.count))
            let tolerance = max(1,3*noise), g = regionGradient(raw,sigma:2)
            let peaks = (1..<160).filter { g[$0]>g[$0-1] && g[$0]>=g[$0+1] }.sorted { g[$0]>g[$1] }
            var separated: [Int] = []
            for peak in peaks where !separated.contains(where:{ abs($0-peak)<8 }) { separated.append(peak) }
            var eligible: [Double] = []
            for peak in separated where peak>=12 && peak+40<161 {
                var lo = g[peak],hi = g[peak],i = peak-1
                while i>=0 && g[i]<=g[peak] { lo = min(lo,g[i]);i -= 1 }
                i = peak+1
                while i<g.count && g[i]<=g[peak] { hi = min(hi,g[i]);i += 1 }
                guard g[peak]-max(lo,hi)>=0.5 else { continue }
                let outside = raw[(peak+12)..<(peak+40)]
                let rms = sqrt(outside.reduce(0) { $0+simd_length_squared($1-level) }/Double(3*outside.count))
                let inside = raw[(peak-12)..<(peak-4)].reduce(SIMD3<Double>(repeating:0),+)/8
                guard rms<=tolerance,sqrt(simd_length_squared(inside-level)/3)>=5 else { continue }
                eligible.append(Double(peak-80))
            }
            return eligible.count == 1 ? eligible[0] : nil
        }

        struct BorderRegionFit {
            let center, width, amplitude, relativeRMS, cost: Double
            var converged = false
            var accepted: Bool {
                converged && abs(center)<11.999 && width<7.999 && amplitude>=5 && relativeRMS<=0.15
            }
        }

        /// Variable projection: solve channel baselines/slopes/amplitudes exactly,
        /// then minimize the same soft-L1 residual over shared position and blur.
        /// Bounded coarse search plus refinement avoids relying on a single start.
        static func fitBorderRegion(_ raw: [SIMD3<Double>], logistic: Bool) -> BorderRegionFit? {
            guard raw.count == 57 else { return nil }
            let mean = raw.reduce(SIMD3<Double>(repeating:0),+)/57
            let xx = (-28...28).reduce(0.0) { $0+Double($1*$1) }
            var xy = SIMD3<Double>(repeating:0)
            for i in 0..<57 { xy += raw[i]*Double(i-28) }
            func evaluate(_ center: Double, _ width: Double) -> BorderRegionFit? {
                let step = (-28...28).map { x -> Double in
                    let z = (Double(x)-center)/width
                    return logistic ? 1/(1+exp(-1.7*z)) : 0.5*(1+erf(z/sqrt(2)))
                }
                let sm = step.reduce(0,+)/57
                var xs = 0.0
                for i in 0..<57 { xs += Double(i-28)*step[i] }
                let alpha = xs/xx
                var hh = 0.0,hy = SIMD3<Double>(repeating:0)
                for i in 0..<57 {
                    let h = step[i]-sm-alpha*Double(i-28)
                    hh += h*h;hy += raw[i]*h
                }
                guard hh>1e-9 else { return nil }
                let amplitude = hy/hh, slope = (xy-amplitude*xs)/xx, intercept = mean-amplitude*sm
                var error = 0.0,cost = 0.0
                for i in 0..<57 {
                    let residual = intercept+slope*Double(i-28)+amplitude*step[i]-raw[i]
                    error += simd_length_squared(residual)
                    for channel in 0..<3 { cost += 16*(sqrt(1+residual[channel]*residual[channel]/16)-1) }
                }
                let size = sqrt(simd_length_squared(amplitude)/3)
                return .init(center:center,width:width,amplitude:size,relativeRMS:sqrt(error/171)/max(size,1e-9),cost:cost)
            }
            var best: BorderRegionFit?
            for center in stride(from:-12.0,through:12.0,by:2) {
                for width in [0.5,1,2,4,8] {
                    if let trial = evaluate(center,width),trial.cost < (best?.cost ?? .infinity) { best = trial }
                }
            }
            guard var current = best else { return nil }
            var positionStep = 1.0,blurStep = 0.5
            for _ in 0..<150 {
                if Task.isCancelled { return nil }
                var next = current
                for x in -1...1 {
                    for y in -1...1 where x != 0 || y != 0 {
                        let center = max(-12,min(12,current.center+Double(x)*positionStep))
                        let width = max(0.5,min(8,current.width+Double(y)*blurStep))
                        if let trial = evaluate(center,width),trial.cost < next.cost-1e-12 { next = trial }
                    }
                }
                if next.cost < current.cost-1e-12 { current = next }
                else { positionStep /= 2;blurStep /= 2 }
                if positionStep<0.0005 { current.converged = true;return current }
            }
            return current
        }

        static func observedUniformBorderPath(_ side: Side, seed: CardCenteringQuad,
                                               physical: ObservedPath, source: UIImage) -> ObservedPath? {
            guard physical.side == side.rawValue,let strip = PrintedStrip(side,seed:seed,source:source) else { return nil }
            var points: [Point?] = []
            for i in 0..<61 {
                guard !Task.isCancelled else { return nil }
                let base = strip.base(i)
                guard let cut = physicalDepth(base,nx:strip.nx,ny:strip.ny,path:physical) else { points.append(nil);continue }
                var proposals: [Double] = []
                for width in [16,32,64] {
                    guard let raw = strip.profile(base,offsets:(-80...80).map(Double.init),width:width),
                          let exterior = strip.profile(base,offsets:(24...48).reversed().map { cut-Double($0) },width:width),
                          let proposal = uniformBorderProposal(raw,exterior:exterior),proposal+12<cut-48 else { continue }
                    proposals.append(proposal)
                }
                guard proposals.count == 3,proposals.max()!-proposals.min()!<=4 else { points.append(nil);continue }
                let seedDepth = proposals.sorted()[1]
                var positions: [Double] = []
                for width in [16,32,64] {
                    guard let raw = strip.profile(base,offsets:(-28...28).map { seedDepth+Double($0) },width:width) else { continue }
                    for logistic in [false,true] {
                        guard let fit = fitBorderRegion(raw,logistic:logistic),fit.accepted else { continue }
                        positions.append(seedDepth+fit.center)
                    }
                }
                guard positions.count == 6,positions.max()!-positions.min()!<=4 else { points.append(nil);continue }
                let sorted = positions.sorted()
                points.append(strip.point(base,(sorted[2]+sorted[3])/2))
            }
            diagnosticSink?("uniform-border \(side.rawValue) supported=\(points.compactMap { $0 }.count)")
            return .init(side:side.rawValue,observations:points)
        }

        /// Explicit research invocation; preserves existing proposal identity and
        /// report state. The weak bottom uses independent physical-border evidence.
        static func observedSelectiveBorderMeasurement(analysis: CardCenteringAnalysis, source: UIImage) -> ObservedMeasurement? {
            guard let mapping = analysis.coordinateMapping,let working = analysis.measurement.geometryInnerQuad else { return nil }
            let outerSeed = mapping.nativeQuad(fromWorking:analysis.measurement.geometryOuterQuad)
            let innerSeed = mapping.nativeQuad(fromWorking:working)
            let outer = Side.allCases.compactMap { observedPhysicalPath($0,seed:outerSeed,source:source) }
            guard let physicalBottom = outer.first(where:{ $0.side == Side.bottom.rawValue }) else { return nil }
            let inner = Side.allCases.compactMap { side in
                side == .bottom ? observedUniformBorderPath(side,seed:innerSeed,physical:physicalBottom,source:source)
                    : observedPrintedSeedPath(side,seed:innerSeed,source:source)
            }
            return measureObservedPaths(outer:outer,inner:inner,outerSeed:outerSeed,innerSeed:innerSeed)
        }

        /// Opt-in repair of an existing recognized back. Supported bottom paths
        /// keep the ordinary result; weak paths need complete independent support.
        /// Does not turn back recognition into publisher-design certainty.
        static func applySelectiveMagicRepair(baseline: CardCenteringAnalysis, source: UIImage) -> CardCenteringAnalysis {
            let old = baseline.measurement
            guard old.referenceDefinition == .magicClassicBack,!old.hasObservedPaths,
                  let mapping = baseline.coordinateMapping,let workingInner = old.geometryInnerQuad,
                  let direct = observedPrintedSeedPath(.bottom,seed:mapping.nativeQuad(fromWorking:workingInner),source:source)
            else { return baseline }
            let indices = direct.observations.indices.filter { direct.observations[$0] != nil }
            if indices.count>=30,let first = indices.lastIndex(where:{ $0<=7 }),
               let last = indices.firstIndex(where:{ $0>=53 }) {
                let measured = indices[first...last]
                if zip(measured,measured.dropFirst()).allSatisfy({ $1-$0<=7 }) { return baseline }
            }
            guard let observed = observedSelectiveBorderMeasurement(analysis:baseline,source:source),
                  let outer = guideQuad(observed.outerPaths),let inner = guideQuad(observed.innerPaths),!Task.isCancelled
            else { return baseline }
            var measurement = CardCenteringMeasurement(imageWidth:old.imageWidth,imageHeight:old.imageHeight,
                outerQuad:mapping.workingQuad(fromNative:outer),innerQuad:mapping.workingQuad(fromNative:inner),
                warnings:old.warnings,detectionNotes:old.detectionNotes,coordinateMapping:mapping,innerReference:old.innerReference,
                confidence:.declined(reason:"Review the detected card and printed border edges."),
                inputRecord:old.inputRecord,referenceDefinition:old.referenceDefinition)
            measurement.observedPrintMeasurement = observed
            guard measurement.hasValidFrameGeometry else { return baseline }
            return .init(image:baseline.image,measurement:measurement,coordinateMapping:mapping,
                appliedRotationDegrees:baseline.appliedRotationDegrees,detectedSkewDegrees:baseline.detectedSkewDegrees,
                nativeSourceData:baseline.nativeSourceData)
        }
    }
#endif
