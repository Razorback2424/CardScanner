import XCTest
@testable import TradingCardScanner

final class CenteringSpatialMeasurementTests: XCTestCase {
    private func candidate(_ id: String, frame: CardCenteringPrecisionFrame = .outer,
                           side: CardCenteringPrecisionSide = .bottom,
                           start: CardCenteringPoint, end: CardCenteringPoint) -> CardCenteringBoundaryCandidate {
        .init(id: id, frame: frame, side: side, nativeLine: .init(start: start, end: end), source: "analytic_fixture",
            proposedRole: frame == .outer ? .shadow : .printedBorder,
            competingRoles: frame == .outer ? [.physicalCut] : [.artwork], signal: "analytic_line",
            strength: nil, polarity: nil, coverage: 0.76, fitResidualNativePixels: 0.2,
            sampleBands: [.init(start: start, end: end, sampleCount: 25)], exclusions: [],
            selectionReason: .competingCandidate, reason: "Known alternative in synthetic fixture")
    }
    private func fixture(inner: CardCenteringQuad? = nil, candidates: [CardCenteringBoundaryCandidate] = []) -> CardCenteringMeasurement {
        .init(imageWidth: 600, imageHeight: 840,
            outerQuad: .axisAligned(.init(left: 20, top: 20, right: 580, bottom: 820)),
            innerQuad: inner ?? .axisAligned(.init(left: 50, top: 50, right: 550, bottom: 790)), warnings: [],
            boundaryCandidates: candidates)
    }
    private func skewedInner() -> CardCenteringQuad {
        .init(topLeft: .init(x: 45, y: 60), topRight: .init(x: 550, y: 45),
            bottomRight: .init(x: 540, y: 780), bottomLeft: .init(x: 65, y: 790))
    }
    func testCenteredGeometryHasFiveCommonSamplesWithoutInventingImageSupport() throws {
        let value = fixture(), spatial = try XCTUnwrap(value.spatialMeasurement)
        XCTAssertFalse(value.canReportRatios)
        XCTAssertEqual(spatial.methodVersion, "common_axis_samples_v1")
        for axis in [spatial.leftRight, spatial.topBottom] {
            XCTAssertEqual(axis.samples.map(\.normalizedPosition), [0.1, 0.3, 0.5, 0.7, 0.9])
            XCTAssertEqual(axis.geometricCoverage, 1)
            XCTAssertEqual(axis.medianFirstPercentage, 50)
            XCTAssertEqual(axis.midpoint?.firstPercentage, 50)
            XCTAssertTrue(axis.samples.allSatisfy { abs($0.firstMargin - 30) < 1e-8 && abs($0.secondMargin - 30) < 1e-8 })
        }
        XCTAssertTrue(spatial.sides.allSatisfy { $0.observedImageCoverage == nil && $0.evidenceCandidateID == nil })
        XCTAssertEqual(try JSONDecoder().decode(CardCenteringSpatialMeasurement.self,
            from: JSONEncoder().encode(spatial)), spatial)
    }
    func testUnequalSlopesUseSameRowAndColumnWithoutChangingHeadlineConvention() throws {
        var value = fixture(inner: skewedInner())
        XCTAssertTrue(value.confirmFrames(reference: .userPrintedBorder))
        let spatial = try XCTUnwrap(value.spatialMeasurement)
        let expectedLeft: Double = 25 + 360.0 / 730 * 20
        let expectedRight: Double = 30 + 375.0 / 735 * 10
        let lr = try XCTUnwrap(spatial.leftRight.samples.first { $0.normalizedPosition == 0.5 })
        XCTAssertEqual(lr.firstMargin, expectedLeft, accuracy: 1e-9)
        XCTAssertEqual(lr.secondMargin, expectedRight, accuracy: 1e-9)
        XCTAssertEqual(lr.ratio.firstPercentage, 100 * expectedLeft / (expectedLeft + expectedRight), accuracy: 1e-9)
        let expectedTop: Double = 40 - 255.0 / 505 * 15
        let expectedBottom: Double = 30 + 235.0 / 475 * 10
        let tb = try XCTUnwrap(spatial.topBottom.samples.first { $0.normalizedPosition == 0.5 })
        XCTAssertEqual(tb.firstMargin, expectedTop, accuracy: 1e-9)
        XCTAssertEqual(tb.secondMargin, expectedBottom, accuracy: 1e-9)
        XCTAssertEqual(value.leftRightCentering, "50.0 / 50.0")
        XCTAssertGreaterThan(abs(lr.ratio.firstPercentage - 50), 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(spatial.leftRight.ratioRange).firstSpread, 5)
        XCTAssertNotEqual(spatial.sides.first { $0.side == .left }?.rectifiedTiltDegrees,
                          spatial.sides.first { $0.side == .right }?.rectifiedTiltDegrees)
    }
    func testSamplesOutsideInnerSegmentsAreUnavailableRatherThanExtrapolated() throws {
        let value = fixture(inner: .axisAligned(.init(left: 200, top: 300, right: 400, bottom: 600)))
        let spatial = try XCTUnwrap(value.spatialMeasurement)
        XCTAssertEqual(spatial.leftRight.samples.map(\.normalizedPosition), [0.5, 0.7])
        XCTAssertEqual(spatial.topBottom.samples.map(\.normalizedPosition), [0.5])
        XCTAssertEqual(spatial.leftRight.geometricCoverage, 0.4)
        XCTAssertEqual(spatial.topBottom.geometricCoverage, 0.2)
        XCTAssertEqual(spatial.topBottom.unavailablePositions, [0.1, 0.3, 0.7, 0.9])
    }
    func testAbsentCrossedAndNonpositiveMarginsHaveNoSpatialReading() {
        var value = fixture()
        value.innerQuad = nil
        XCTAssertNil(value.spatialMeasurement)
        value.innerQuad = .axisAligned(.init(left: 20, top: 50, right: 550, bottom: 790))
        XCTAssertNil(value.spatialMeasurement)
        value.innerQuad = .axisAligned(.init(left: 590, top: 50, right: 550, bottom: 790))
        XCTAssertNil(value.spatialMeasurement)
        XCTAssertNil(value.boundarySensitivity(comparing: []).boundaryChoices)
    }
    func testOuterOnlyHomographyPreservesSpatialRatiosAcrossPerspectiveRotationAndUnequalScale() throws {
        let value = fixture(inner: skewedInner()), original = try XCTUnwrap(value.spatialMeasurement)
        let transforms: [(CardCenteringPoint) -> CardCenteringPoint] = [
            { .init(x: 0.7 * $0.x + 50, y: 1.3 * $0.y + 70) },
            { p in let a = 7.0 * Double.pi / 180
                return .init(x: cos(a) * p.x - sin(a) * p.y + 150, y: sin(a) * p.x + cos(a) * p.y + 50) },
            { p in let d = 1 + 0.00015 * p.x + 0.00008 * p.y
                return .init(x: (1.1 * p.x + 0.03 * p.y + 100) / d, y: (0.02 * p.x + 1.05 * p.y + 80) / d) }
        ]
        func mapped(_ quad: CardCenteringQuad, _ transform: (CardCenteringPoint) -> CardCenteringPoint) -> CardCenteringQuad {
            let p = quad.points.map(transform)
            return .init(topLeft: p[0], topRight: p[1], bottomRight: p[2], bottomLeft: p[3])
        }
        for transform in transforms {
            let changed = CardCenteringMeasurement(imageWidth: 1400, imageHeight: 1500,
                outerQuad: mapped(value.outerQuad, transform), innerQuad: mapped(value.innerQuad!, transform), warnings: [])
            let spatial = try XCTUnwrap(changed.spatialMeasurement)
            XCTAssertEqual(spatial.leftRight.samples.count, original.leftRight.samples.count)
            XCTAssertEqual(spatial.topBottom.samples.count, original.topBottom.samples.count)
            for (a, b) in zip(original.leftRight.samples + original.topBottom.samples, spatial.leftRight.samples + spatial.topBottom.samples) {
                XCTAssertEqual(a.normalizedPosition, b.normalizedPosition)
                XCTAssertEqual(a.ratio.firstPercentage, b.ratio.firstPercentage, accuracy: 1e-7)
            }
            XCTAssertEqual(spatial.numericalRoundTrip.sampleCount, 25)
            XCTAssertLessThan(spatial.numericalRoundTrip.sourceMaximum, 1e-7)
            XCTAssertLessThan(spatial.numericalRoundTrip.rectifiedMaximum, 1e-7)
        }
    }
    func testAllEXIFMirrorsAndQuarterTurnsPreserveDirectionalMeaning() throws {
        let value = fixture(inner: .axisAligned(.init(left: 40, top: 60, right: 540, bottom: 770)))
        let lr = 100.0 * 20 / 60, tb = 100.0 * 40 / 90
        let expected = [(lr,tb),(100-lr,tb),(100-lr,100-tb),(lr,100-tb),(tb,lr),(100-tb,lr),(100-tb,100-lr),(tb,100-lr)]
        for exif in 1...8 {
            let mapping = CardCenteringRasterOrientation(rawSize: .init(width: 600, height: 840), exif: exif)
            func oriented(_ q: CardCenteringQuad) -> CardCenteringQuad {
                let byY = q.points.map(mapping.orientedPoint(fromRaw:)).sorted { $0.y < $1.y }
                let top = byY.prefix(2).sorted { $0.x < $1.x }, bottom = byY.suffix(2).sorted { $0.x < $1.x }
                return .init(topLeft: top[0], topRight: top[1], bottomRight: bottom[1], bottomLeft: bottom[0])
            }
            let changed = CardCenteringMeasurement(imageWidth: Int(mapping.orientedSize.width), imageHeight: Int(mapping.orientedSize.height),
                outerQuad: oriented(value.outerQuad), innerQuad: oriented(value.innerQuad!), warnings: [])
            let spatial = try XCTUnwrap(changed.spatialMeasurement)
            XCTAssertEqual(try XCTUnwrap(spatial.leftRight.midpoint).firstPercentage, expected[exif - 1].0, accuracy: 1e-8)
            XCTAssertEqual(try XCTUnwrap(spatial.topBottom.midpoint).firstPercentage, expected[exif - 1].1, accuracy: 1e-8)
        }
    }
    func testInteriorGridRejectsSingularTransformWithoutClaimingPhysicalAccuracy() throws {
        let value = fixture()
        let numerical = try XCTUnwrap(value.spatialMeasurement).numericalRoundTrip
        XCTAssertEqual(numerical.sampleCount, 25)
        XCTAssertLessThan(numerical.sourceRMS, 1e-8)
        let singular = CardCenteringRectification(targetSize: .init(width: 560, height: 800), coefficients: Array(repeating: 0, count: 8), residualDegrees: 0)
        XCTAssertNil(singular.interiorRoundTrip(outer: value.outerQuad))
    }
    func testThinBordersRetainSubpixelRatiosAndPositiveMargins() throws {
        let inner = CardCenteringQuad(topLeft: .init(x: 20.25, y: 20.5), topRight: .init(x: 579.25, y: 20.5),
            bottomRight: .init(x: 579.25, y: 818.5), bottomLeft: .init(x: 20.25, y: 818.5))
        let spatial = try XCTUnwrap(fixture(inner: inner).spatialMeasurement)
        XCTAssertEqual(spatial.leftRight.geometricCoverage, 1)
        XCTAssertEqual(spatial.topBottom.geometricCoverage, 1)
        for sample in spatial.leftRight.samples + spatial.topBottom.samples {
            XCTAssertEqual(sample.ratio.firstPercentage, 25, accuracy: 1e-8)
            XCTAssertGreaterThan(sample.firstMargin, 0)
            XCTAssertGreaterThan(sample.secondMargin, 0)
        }
    }
    func testCutShadowAlternativeRecomputesHomographyAndBothAxesWithoutCombiningEdges() throws {
        let shadow = candidate("shadow", start: .init(x: 580, y: 825), end: .init(x: 20, y: 824))
        var value = fixture(candidates: [shadow])
        XCTAssertTrue(value.confirmFrames(reference: .userPrintedBorder))
        let before = value
        let result = value.boundarySensitivity(comparing: ["shadow"])
        XCTAssertEqual(result.scenarios.count, 2)
        let current = result.scenarios[0], changed = result.scenarios[1]
        XCTAssertEqual(changed.proposedRole, .shadow)
        XCTAssertNil(changed.rejectionReason)
        XCTAssertNotEqual(current.spatial?.rectification.coefficients, changed.spatial?.rectification.coefficients)
        XCTAssertGreaterThan(abs(try XCTUnwrap(changed.headlineLeftRight).firstPercentage - 50), 0.00001)
        XCTAssertGreaterThan(abs(try XCTUnwrap(changed.headlineTopBottom).firstPercentage - 50), 3)
        var independentlyChanged = value
        XCTAssertTrue(independentlyChanged.selectBoundaryCandidate(id: "shadow", as: .physicalCut))
        XCTAssertEqual(changed.spatial, independentlyChanged.spatialMeasurement)
        XCTAssertEqual(changed.revision?.inner, value.innerQuad)
        for line in independentlyChanged.selectedLines where !(line.frame == .outer && line.side == .bottom) {
            let previous = try XCTUnwrap(value.selectedLines.first { $0.frame == line.frame && $0.side == line.side })
            XCTAssertTrue(previous.nativeLine.coincides(with: line.nativeLine))
        }
        XCTAssertEqual(value, before)
        XCTAssertEqual(try XCTUnwrap(result.boundaryChoices).scenarioIDs, ["current", "candidate_shadow"])
        XCTAssertNil(result.localPerturbations)
        XCTAssertEqual(try JSONDecoder().decode(CardCenteringBoundarySensitivity.self, from: JSONEncoder().encode(result)), result)
    }
    func testInvalidAndMissingAlternativesRemainExplicitWithoutAnInventedRange() throws {
        let crossed = candidate("crossed", start: .init(x: 580, y: 30), end: .init(x: 20, y: 30))
        let value = fixture(candidates: [crossed])
        let result = value.boundarySensitivity(comparing: ["crossed", "missing", "crossed"])
        XCTAssertEqual(result.scenarios.count, 3)
        XCTAssertTrue(result.scenarios.dropFirst().allSatisfy { $0.rejectionReason != nil && $0.headlineLeftRight == nil })
        XCTAssertNil(result.boundaryChoices)
        XCTAssertNil(result.localPerturbations)
        XCTAssertTrue(result.limitation.contains("unknown"))
    }
    func testLocalAssumptionsStaySeparateFromSemanticChoicesAndSpatialVariation() throws {
        let shadow = candidate("shadow", start: .init(x: 580, y: 825), end: .init(x: 20, y: 825))
        let value = fixture(candidates: [shadow])
        let result = value.boundarySensitivity(comparing: ["shadow"], perturbations: [
            .init(frame: .inner, side: .left, normalOffsetNativePixels: -1),
            .init(frame: .inner, side: .left, normalOffsetNativePixels: 1),
            .init(frame: .inner, side: .left, normalOffsetNativePixels: .infinity)
        ])
        let local = try XCTUnwrap(result.localPerturbations), semantic = try XCTUnwrap(result.boundaryChoices)
        XCTAssertEqual(local.leftRight.firstMinimum, 100.0 * 29 / 59, accuracy: 1e-8)
        XCTAssertEqual(local.leftRight.firstMaximum, 100.0 * 31 / 61, accuracy: 1e-8)
        XCTAssertEqual(local.topBottom.firstSpread, 0, accuracy: 1e-8)
        XCTAssertGreaterThan(semantic.topBottom.firstSpread, 3)
        XCTAssertEqual(semantic.leftRight.firstSpread, 0, accuracy: 1e-8)
        XCTAssertEqual(value.spatialMeasurement?.leftRight.ratioRange?.firstSpread, 0)
        XCTAssertNotNil(result.scenarios.last?.rejectionReason)
        XCTAssertEqual(local.scenarioIDs.count, 3)
    }
    func testManualEditsRecomputeDerivedValuesAndRetireOldLineEvidence() throws {
        let left = candidate("left", frame: .inner, side: .left, start: .init(x: 50, y: 790), end: .init(x: 50, y: 50))
        var value = fixture(candidates: [left])
        let originalProposal = value.proposedInnerQuad
        XCTAssertTrue(value.selectBoundaryCandidate(id: "left", as: .printedBorder))
        let before = try XCTUnwrap(value.spatialMeasurement)
        XCTAssertEqual(before.sides.first { $0.side == .left }?.observedImageCoverage, 0.76)
        XCTAssertTrue(value.setPrecisionInnerSide(.left, positionNativePixels: 51))
        let after = try XCTUnwrap(value.spatialMeasurement)
        XCTAssertNotEqual(before.revision, after.revision)
        XCTAssertNil(after.sides.first { $0.side == .left }?.observedImageCoverage)
        XCTAssertNil(after.sides.first { $0.side == .left }?.evidenceCandidateID)
        XCTAssertNotEqual(before.leftRight, after.leftRight)
        XCTAssertEqual(value.boundaryCandidates, [left])
        XCTAssertEqual(value.proposedInnerQuad, originalProposal)
    }
    @MainActor func testUndoRotationAndReplacementKeepDerivedResultsBoundToCurrentInput() async throws {
        let model = CardCenteringViewModel()
        model.measurement = fixture()
        XCTAssertTrue(model.measurement!.confirmFrames(reference: .userPrintedBorder))
        let initial = try XCTUnwrap(model.precisionMeasurement?.spatialMeasurement)
        model.updatePrecisionSide(.left, position: 51)
        XCTAssertNotEqual(model.precisionMeasurement?.spatialMeasurement, initial)
        model.undo()
        XCTAssertEqual(model.precisionMeasurement?.spatialMeasurement, initial)
        model.adjustRotation(by: 1)
        XCTAssertFalse(model.measurement?.canReportRatios ?? true)
        XCTAssertNotEqual(model.precisionMeasurement?.geometryRevision, initial.revision)
        await model.loadImageData { throw CocoaError(.fileReadCorruptFile) }
        XCTAssertNil(model.measurement)
        XCTAssertNil(model.precisionMeasurement?.spatialMeasurement)
    }
}
