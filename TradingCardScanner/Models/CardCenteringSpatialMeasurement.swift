import Foundation

/// Identity for derived geometry, separate from immutable detector evidence.
/// Recomputed values cannot masquerade as a cached result after an edit.
struct CardCenteringGeometryRevision: Codable, Equatable {
    let inputSHA256: String?
    let outer: CardCenteringQuad
    let inner: CardCenteringQuad?
    let mapping: CardCenteringCoordinateMapping?
    let reference: CardCenteringReferenceDefinition
    let reviewState: CardCenteringReviewState
    var observedPoints: [[CardCenteringPoint?]]? = nil
}

struct CardCenteringSpatialSample: Codable, Equatable {
    let normalizedPosition: Double
    let firstMargin: Double
    let secondMargin: Double
    let ratio: CardCenteringRatioPair
}

struct CardCenteringSpatialAxis: Codable, Equatable {
    let samples: [CardCenteringSpatialSample]
    let unavailablePositions: [Double]
    let ratioRange: CardCenteringRatioRange?
    let firstMarginMinimum: Double?
    let firstMarginMaximum: Double?
    let secondMarginMinimum: Double?
    let secondMarginMaximum: Double?
    let medianFirstPercentage: Double?
    var midpoint: CardCenteringRatioPair? { samples.first { $0.normalizedPosition == 0.5 }?.ratio }
    /// Geometric intersection coverage, never image support or certainty.
    var geometricCoverage: Double { Double(samples.count) / 5 }

    init(samples: [CardCenteringSpatialSample]) {
        self.samples = samples
        unavailablePositions = CardCenteringSpatialMeasurement.positions.filter { position in
            !samples.contains { $0.normalizedPosition == position }
        }
        ratioRange = CardCenteringRatioRange(samples: samples.map(\.ratio))
        firstMarginMinimum = samples.map(\.firstMargin).min()
        firstMarginMaximum = samples.map(\.firstMargin).max()
        secondMarginMinimum = samples.map(\.secondMargin).min()
        secondMarginMaximum = samples.map(\.secondMargin).max()
        let sorted = samples.map { $0.ratio.firstPercentage }.sorted()
        if sorted.isEmpty { medianFirstPercentage = nil }
        else if sorted.count.isMultiple(of: 2) {
            medianFirstPercentage = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else { medianFirstPercentage = sorted[sorted.count / 2] }
    }
}

struct CardCenteringSpatialSide: Codable, Equatable {
    let side: CardCenteringPrecisionSide
    let rectifiedTiltDegrees: Double
    /// Present only when retained observations still belong to this exact line.
    let observedImageCoverage: Double?
    let observedFitResidualNativePixels: Double?
    let evidenceCandidateID: String?
}

struct CardCenteringTransformRoundTrip: Codable, Equatable {
    let sampleCount: Int
    let sourceRMS: Double
    let sourceMaximum: Double
    let rectifiedRMS: Double
    let rectifiedMaximum: Double
}

extension CardCenteringRectification {
    /// Composition of the actual forward matrix and its actual inverse at an
    /// interior grid. This tests numerical consistency, not physical identity.
    func interiorRoundTrip(outer: CardCenteringQuad) -> CardCenteringTransformRoundTrip? {
        var sourceErrors: [Double] = [], rectifiedErrors: [Double] = []
        for y in CardCenteringSpatialMeasurement.positions {
            for x in CardCenteringSpatialMeasurement.positions {
                let top = CardCenteringPoint(x: outer.topLeft.x + x * (outer.topRight.x - outer.topLeft.x),
                    y: outer.topLeft.y + x * (outer.topRight.y - outer.topLeft.y))
                let bottom = CardCenteringPoint(x: outer.bottomLeft.x + x * (outer.bottomRight.x - outer.bottomLeft.x),
                    y: outer.bottomLeft.y + x * (outer.bottomRight.y - outer.bottomLeft.y))
                let source = CardCenteringPoint(x: top.x + y * (bottom.x - top.x), y: top.y + y * (bottom.y - top.y))
                let recovered = sourcePoint(fromRectified: rectifiedPoint(from: source))
                let target = CardCenteringPoint(x: x * targetSize.width, y: y * targetSize.height)
                let returned = rectifiedPoint(from: sourcePoint(fromRectified: target))
                let a = hypot(recovered.x - source.x, recovered.y - source.y)
                let b = hypot(returned.x - target.x, returned.y - target.y)
                guard a.isFinite, b.isFinite else { return nil }
                sourceErrors.append(a); rectifiedErrors.append(b)
            }
        }
        func rms(_ values: [Double]) -> Double {
            let sum = values.reduce(0.0) { $0 + $1 * $1 }
            return sqrt(sum / Double(values.count))
        }
        return CardCenteringTransformRoundTrip(sampleCount: sourceErrors.count,
            sourceRMS: rms(sourceErrors), sourceMaximum: sourceErrors.max()!,
            rectifiedRMS: rms(rectifiedErrors), rectifiedMaximum: rectifiedErrors.max()!)
    }
}

struct CardCenteringSpatialMeasurement: Codable, Equatable {
    static let method = "common_axis_samples_v1"
    static let positions = [0.1, 0.3, 0.5, 0.7, 0.9]
    private(set) var methodVersion = CardCenteringSpatialMeasurement.method
    let revision: CardCenteringGeometryRevision
    let rectification: CardCenteringRectification
    let rectifiedInner: CardCenteringQuad
    let leftRight: CardCenteringSpatialAxis
    let topBottom: CardCenteringSpatialAxis
    let sides: [CardCenteringSpatialSide]
    let numericalRoundTrip: CardCenteringTransformRoundTrip

    init?(_ value: CardCenteringMeasurement) {
        guard value.hasValidFrameGeometry, let inner = value.geometryInnerQuad else { return nil }
        // Always derive the one transform from the current cut. The printed
        // reference never receives an independently fitted normalization.
        let transform = CardCenteringRectification(outerQuad: value.geometryOuterQuad)
        guard transform.isNumericallyValid,
              let roundTrip = transform.interiorRoundTrip(outer: value.geometryOuterQuad) else { return nil }
        revision = value.geometryRevision
        rectification = transform
        rectifiedInner = transform.rectifiedQuad(from: inner)
        numericalRoundTrip = roundTrip
        let points = rectifiedInner.points
        func intersection(_ side: CardCenteringPrecisionSide, at position: Double) -> Double? {
            let p = points[side.index], q = points[(side.index + 1) % 4]
            let start = side.isVertical ? p.y : p.x, end = side.isVertical ? q.y : q.x
            guard abs(end - start) > 1e-10 else { return nil }
            let t = (position - start) / (end - start)
            guard t.isFinite, t >= -1e-9, t <= 1 + 1e-9 else { return nil }
            return side.isVertical ? p.x + t * (q.x - p.x) : p.y + t * (q.y - p.y)
        }
        func samples(horizontal: Bool) -> [CardCenteringSpatialSample] {
            Self.positions.compactMap { progress in
                let position = progress * (horizontal ? transform.targetSize.height : transform.targetSize.width)
                let span = horizontal ? transform.targetSize.width : transform.targetSize.height
                guard let first = intersection(horizontal ? .left : .top, at: position),
                      let last = intersection(horizontal ? .right : .bottom, at: position), first < last,
                      let ratio = CardCenteringRatioPair(firstDistance: first, secondDistance: span - last) else { return nil }
                return .init(normalizedPosition: progress, firstMargin: first, secondMargin: span - last, ratio: ratio)
            }
        }
        leftRight = .init(samples: samples(horizontal: true))
        topBottom = .init(samples: samples(horizontal: false))
        sides = CardCenteringPrecisionSide.allCases.map { side in
            let p = points[side.index], q = points[(side.index + 1) % 4]
            var angle = atan2(q.y - p.y, q.x - p.x) * 180 / .pi - (side.isVertical ? 90 : 0)
            while angle > 90 { angle -= 180 }; while angle < -90 { angle += 180 }
            let selected = value.selectedLines.first { $0.frame == .inner && $0.side == side }
            let observed = selected.flatMap { selected in
                value.boundaryCandidates.first { $0.id == selected.candidateID && $0.nativeLine.coincides(with: selected.nativeLine) }
            }
            return .init(side: side, rectifiedTiltDegrees: angle, observedImageCoverage: observed?.coverage,
                observedFitResidualNativePixels: observed?.fitResidualNativePixels, evidenceCandidateID: observed?.id)
        }
    }
}

enum CardCenteringSensitivityKind: String, Codable { case current, boundaryChoice, localPerturbation }

struct CardCenteringBoundaryPerturbation: Codable, Equatable {
    let frame: CardCenteringPrecisionFrame
    let side: CardCenteringPrecisionSide
    /// Positive moves toward the frame interior along the native line normal.
    /// This is a caller-specified assumption, not an inferred error bound.
    let normalOffsetNativePixels: Double
}

struct CardCenteringSensitivityScenario: Codable, Equatable, Identifiable {
    let id: String
    let kind: CardCenteringSensitivityKind
    let candidateID: String?
    let proposedRole: CardCenteringBoundaryRole?
    let assumption: String
    let rejectionReason: String?
    let revision: CardCenteringGeometryRevision?
    let spatial: CardCenteringSpatialMeasurement?
    let headlineLeftRight: CardCenteringRatioPair?
    let headlineTopBottom: CardCenteringRatioPair?
}

struct CardCenteringSensitivityRange: Codable, Equatable {
    let leftRight: CardCenteringRatioRange
    let topBottom: CardCenteringRatioRange
    let scenarioIDs: [String]
}

struct CardCenteringBoundarySensitivity: Codable, Equatable {
    let revision: CardCenteringGeometryRevision
    let scenarios: [CardCenteringSensitivityScenario]
    let boundaryChoices: CardCenteringSensitivityRange?
    let localPerturbations: CardCenteringSensitivityRange?
    let limitation: String
}

extension CardCenteringMeasurement {
    var geometryRevision: CardCenteringGeometryRevision {
        .init(inputSHA256: inputRecord?.sha256, outer: geometryOuterQuad, inner: geometryInnerQuad,
            mapping: coordinateMapping, reference: referenceDefinition, reviewState: reviewState,
            observedPoints: hasObservedPaths ? observedGuidePaths(outer:true)+observedGuidePaths(outer:false) : nil)
    }
    var spatialMeasurement: CardCenteringSpatialMeasurement? { hasObservedPaths ? nil : .init(self) }

    func includingPhotoRotation(_ degrees: Double) -> Self {
        var value = self
        let size = CardCenteringSize(width: Double(imageWidth), height: Double(imageHeight))
        var mapping = coordinateMapping ?? .init(orientedSourceSize: size, workingSize: size)
        mapping.appliedRotationDegrees += degrees
        value.coordinateMapping = mapping
        return value
    }

    func spatialRatioDetail(horizontal: Bool) -> String? {
#if DEBUG
        if let observedPrintMeasurement, canReportRatios {
            let values = horizontal ? observedPrintMeasurement.localLeftShares : observedPrintMeasurement.localTopShares
            guard let lo = values.min(), let hi = values.max(), hi-lo >= 0.1 else { return nil }
            return String(format: "Across measured span: %.1f–%.1f%% %@",lo,hi,horizontal ? "left" : "top")
        }
#endif
        guard canReportRatios, let spatial = spatialMeasurement else { return nil }
        let axis = horizontal ? spatial.leftRight : spatial.topBottom
        guard let range = axis.ratioRange, range.firstSpread >= 0.1 else { return nil }
        return String(format: "Across card: %.1f–%.1f%% %@", range.firstMinimum, range.firstMaximum,
            horizontal ? "left" : "top")
    }

    /// Explicit, independent one-side scenarios. No automatic plausibility
    /// assertion, Cartesian product of edges, or invented localization bound.
    func boundarySensitivity(comparing candidateIDs: [String],
                             perturbations: [CardCenteringBoundaryPerturbation] = []) -> CardCenteringBoundarySensitivity {
        func scenario(_ value: Self?, id: String, kind: CardCenteringSensitivityKind,
                      candidate: CardCenteringBoundaryCandidate? = nil, assumption: String,
                      rejection: String? = nil) -> CardCenteringSensitivityScenario {
            let spatial = value?.spatialMeasurement
            // Rebuild both-axis headline measurements from that same fresh cut
            // transform, including when only one outer line was replaced.
            let fresh = value.flatMap { value -> Self? in
                guard spatial != nil else { return nil }
                return Self(imageWidth: value.imageWidth, imageHeight: value.imageHeight,
                    outerQuad: value.geometryOuterQuad, innerQuad: value.geometryInnerQuad, warnings: [])
            }
            return .init(id: id, kind: kind, candidateID: candidate?.id, proposedRole: candidate?.proposedRole,
                assumption: assumption, rejectionReason: rejection ?? (spatial == nil ? "Invalid frame geometry" : nil),
                revision: value?.geometryRevision, spatial: spatial,
                headlineLeftRight: fresh.flatMap { .init(firstDistance: $0.leftBorderDistance, secondDistance: $0.rightBorderDistance) },
                headlineTopBottom: fresh.flatMap { .init(firstDistance: $0.topBorderDistance, secondDistance: $0.bottomBorderDistance) })
        }
        var scenarios = [scenario(self, id: "current", kind: .current, assumption: "Current selected guides")]
        var visited = Set<String>()
        for id in candidateIDs where visited.insert(id).inserted {
            guard let candidate = boundaryCandidates.first(where: { $0.id == id }) else {
                scenarios.append(scenario(nil, id: "candidate_\(id)", kind: .boundaryChoice,
                    assumption: "Requested boundary alternative", rejection: "Candidate is unavailable for this input"))
                continue
            }
            var alternative = self
            let role: CardCenteringBoundaryRole = candidate.frame == .outer ? .physicalCut : referenceDefinition.role
            let valid = alternative.selectBoundaryCandidate(id: id, as: role)
            scenarios.append(scenario(valid ? alternative : nil, id: "candidate_\(id)", kind: .boundaryChoice, candidate: candidate,
                assumption: "Treat the \(candidate.side.rawValue) \(candidate.frame.label.lowercased()) alternative as the selected boundary; other seven lines fixed",
                rejection: valid ? nil : "Alternative crosses or collapses the selected frames"))
        }
        for (index, perturbation) in perturbations.enumerated() {
            var alternative = self
            let selected = selectedLines.first { $0.frame == perturbation.frame && $0.side == perturbation.side }
            var valid = false
            if let selected, let current = precisionLine(perturbation.side, frame: perturbation.frame),
               perturbation.normalOffsetNativePixels.isFinite {
                let dx = selected.nativeLine.end.x - selected.nativeLine.start.x
                let dy = selected.nativeLine.end.y - selected.nativeLine.start.y
                let length = hypot(dx, dy)
                let denominator = perturbation.side.isVertical ? -dy : dx
                if abs(denominator) > 1e-10 {
                    valid = alternative.setPrecisionSide(perturbation.side, frame: perturbation.frame,
                        positionNativePixels: current.position + perturbation.normalOffsetNativePixels * length / denominator)
                }
            }
            scenarios.append(scenario(valid ? alternative : nil, id: "perturbation_\(index)", kind: .localPerturbation,
                assumption: "Assume a \(perturbation.normalOffsetNativePixels) native-pixel inward-normal shift of the \(perturbation.side.rawValue) \(perturbation.frame.label.lowercased()); other seven lines fixed",
                rejection: valid ? nil : "Perturbation is nonfinite or produces invalid geometry"))
        }
        func range(_ kind: CardCenteringSensitivityKind) -> CardCenteringSensitivityRange? {
            let accepted = scenarios.filter { ($0.kind == .current || $0.kind == kind) && $0.rejectionReason == nil }
            guard accepted.contains(where: { $0.kind == kind }),
                  let lr = CardCenteringRatioRange(samples: accepted.compactMap(\.headlineLeftRight)),
                  let tb = CardCenteringRatioRange(samples: accepted.compactMap(\.headlineTopBottom)) else { return nil }
            return .init(leftRight: lr, topBottom: tb, scenarioIDs: accepted.map(\.id))
        }
        return .init(revision: geometryRevision, scenarios: scenarios, boundaryChoices: range(.boundaryChoice),
            localPerturbations: range(.localPerturbation),
            limitation: "Only the listed one-edge scenarios are compared. These ranges are not confidence intervals; uncertainty beyond these assumptions is unknown.")
    }
}
