import CoreGraphics
import UIKit
import Vision

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
    let coordinateMapping: CardCenteringCoordinateMapping?
    /// The skew estimated from the fitted card quad before any automatic
    /// presentation correction. Keeping this separate from the applied
    /// rotation lets tests and evidence compare the detector's estimate with
    /// the transform it chose to apply.
    let detectedSkewDegrees: Double?
    /// The rotation the measurement was taken at. Non-zero when the analyzer
    /// straightened the card itself, so the screen's rotation control can show
    /// what was applied instead of claiming zero.
    var appliedRotationDegrees: Double = 0

    init(
        image: UIImage,
        measurement: CardCenteringMeasurement,
        coordinateMapping: CardCenteringCoordinateMapping? = nil,
        appliedRotationDegrees: Double = 0,
        detectedSkewDegrees: Double? = nil
    ) {
        self.image = image
        self.measurement = measurement
        self.coordinateMapping = coordinateMapping
        self.appliedRotationDegrees = appliedRotationDegrees
        self.detectedSkewDegrees = detectedSkewDegrees
    }
}

#if DEBUG
/// Test-only observability for the profile detector. This deliberately carries
/// measurements out of the existing scoring path without changing a decision,
/// so metamorphic diagnostics can identify where a result diverges before an
/// algorithm experiment is attempted.
struct CardCenteringProfileCandidateDiagnostic: Codable, Equatable {
    let normalizedDepth: Double
    let score: Double
    let support: Double
}

struct CardCenteringProfileDiagnostic: Codable, Equatable {
    let side: String
    let workingWidth: Int
    let workingHeight: Int
    let cardWidthWorkingPx: Double
    let cardHeightWorkingPx: Double
    let sampleRadiusPixels: Double
    let sampleRadiusNormalized: Double
    let normalizedDepthStart: Double
    let normalizedDepthEnd: Double
    let samplesAlongEdge: Int
    let maxIndex: Int
    let normalizedDepths: [Double]
    let scores: [Double]
    let supports: [Double]
    let baseline: Double
    let mad: Double
    let threshold: Double
    let thresholdCandidates: [CardCenteringProfileCandidateDiagnostic]
    let shallowCandidates: [CardCenteringProfileCandidateDiagnostic]
    let selectedIndex: Int
    let selectedNormalizedDepthBeforeRefinement: Double
    let selectedNormalizedDepthAfterRefinement: Double
    let outerQuadWorking: CardCenteringQuad
    let distanceScale: Double
}

struct CardCenteringStageTimingDiagnostic: Codable, Equatable {
    let decodeOrientationDownscale: Double
    let colorPreparation: Double
    let visionRequests: Double
    let scalarFields: Double
    let outerCandidateRefinement: Double
    let innerCandidateGeneration: Double
    let jointSelection: Double
    let rectification: Double
    let resultConstruction: Double

    var total: Double {
        decodeOrientationDownscale
            + colorPreparation
            + visionRequests
            + scalarFields
            + outerCandidateRefinement
            + innerCandidateGeneration
            + jointSelection
            + rectification
            + resultConstruction
    }
}

enum CardCenteringInnerSource: String, Codable, Equatable {
    case scalarInner
    case visionPrintedInner
    case visionArtWindow
    case profile
    case none
}

struct CardCenteringAnalysisDiagnostic: Codable, Equatable {
    let stageTimings: CardCenteringStageTimingDiagnostic
    let scalarOuterAgreesWithVision: Bool
    let scalarPinned: Bool?
    let outlineHasInner: Bool
    let innerSource: CardCenteringInnerSource
    let visionOuterQuad: CardCenteringQuad?
    let scalarOuter: CardCenteringEdges?
    let scalarInner: CardCenteringEdges?
    let scalarOutlineQuad: CardCenteringQuad?
    let selectedOuterSource: String
    let selectedSleeveAmbiguity: Double
    let proposedOuterQuad: CardCenteringQuad?
    let refinedOuterQuad: CardCenteringQuad?
    let outerRefinementAccepted: Bool
}

struct CardCenteringProfileFailureDiagnostic: Codable, Equatable {
    let side: String?
    let reason: String
    let workingWidth: Int
    let workingHeight: Int
    let cardWidthWorkingPx: Double
    let cardHeightWorkingPx: Double
    let innerWidthWorkingPx: Double?
    let innerHeightWorkingPx: Double?
    let innerAspect: Double?
    let profileSupport: Double?
}

struct CardCenteringOuterRefinementDiagnostic: Codable, Equatable {
    let side: String
    let acceptedOffsets: [Double]
    let acceptedStrengths: [Double]
    let acceptedTransitionWidths: [Double]
    let acceptedContrastDeltas: [Double]
    let minimumAccepted: Int
    let maximumLocalOffset: Double
    let maximumTransitionWidth: Double
    let offsetMedian: Double?
    let offsetMAD: Double?
    let rejectionDistance: Double?
    let accepted: Bool
    let reason: String?
}

/// Candidate-level evidence for the revision-E perception spike. The analyzer
/// never reads this data when making a decision; it exists so the evaluation
/// harness can distinguish missing semantic candidates from a bad selector.
struct CardCenteringCandidateDiagnostic: Codable, Equatable {
    let family: String
    let side: String
    let source: String
    /// Pixel coordinates in the prepared detector image. These are the exact
    /// coordinates used by the proposing stage before the harness maps them
    /// back to oriented source pixels.
    let workingGeometry: [CardCenteringPoint]
    /// Oriented source-pixel coordinates derived from the exposed coordinate
    /// mapping. This is intentionally carried separately from working pixels:
    /// candidate recall must not depend on an evaluator guessing a scale.
    let nativeGeometry: [CardCenteringPoint]
    let normalizedGeometry: [CardCenteringPoint]
    let support: Double
    let transitionStrength: Double
    let transitionWidth: Double?
    let baseline: Double?
    let mad: Double?
    let threshold: Double?
    let proposedSemanticRole: String
    let selected: Bool
    let rejectionReason: String?
}

struct CardCenteringCandidateLedgerDiagnostic: Codable, Equatable {
    let workingWidth: Int
    let workingHeight: Int
    let selectedOuterSource: String
    let selectedInnerSource: CardCenteringInnerSource
    let candidates: [CardCenteringCandidateDiagnostic]
}
#endif

/// Native port of the tuned Python centering detector. It scores long color
/// transitions instead of isolated details, separates the physical card from
/// a scanner background, then uses the top border as the reference when
/// choosing plausible left, right, and bottom frame edges.
enum CardCenteringAnalyzer {
#if DEBUG
    /// Installed only by temporary diagnostic tests. The hook is observational
    /// and is never consulted by production decisions.
    nonisolated(unsafe) static var profileDiagnosticSink: ((CardCenteringProfileDiagnostic) -> Void)?
    /// Installed only by temporary diagnostic tests. This reports which branch
    /// supplied the final inner reference and the evidence-arbitration inputs.
    nonisolated(unsafe) static var analysisDiagnosticSink: ((CardCenteringAnalysisDiagnostic) -> Void)?
    /// Installed only by temporary diagnostic tests. This reports why a
    /// profile-based inner reference could not be assembled.
    nonisolated(unsafe) static var profileFailureDiagnosticSink: ((CardCenteringProfileFailureDiagnostic) -> Void)?
    /// Installed only by temporary diagnostic tests. This reports whether the
    /// deterministic outer-edge pass found a coherent transition but rejected
    /// it as too far from the Vision proposal.
    nonisolated(unsafe) static var outerRefinementDiagnosticSink: ((CardCenteringOuterRefinementDiagnostic) -> Void)?
    /// Installed only by the REQ-042 candidate-recall harness. Candidate
    /// telemetry is observational and is never consulted by production logic.
    nonisolated(unsafe) static var candidateLedgerDiagnosticSink: ((CardCenteringCandidateLedgerDiagnostic) -> Void)?
    /// The active DEBUG-only ledger is a reference context so the production
    /// method signatures stay identical in Release builds. Tests run analyses
    /// serially while this temporary sink is installed.
    nonisolated(unsafe) private static var activeCandidateLedger: CandidateLedger?
#endif

    private struct Pixel {
        let l: Float
        let a: Float
        let b: Float
    }

    private struct Candidate {
        let position: Int
        let strength: Float
        let support: Float
    }

    private struct CandidateSet {
        let candidates: [Candidate]
        let baseline: Float
        let mad: Float
        let threshold: Float
    }

#if DEBUG
    private struct CandidateLedgerEntry {
        let family: String
        let side: String
        let source: String
        let workingGeometry: [CardCenteringPoint]
        let support: Double
        let transitionStrength: Double
        let transitionWidth: Double?
        let baseline: Double?
        let mad: Double?
        let threshold: Double?
        let proposedSemanticRole: String
        let selected: Bool
        let rejectionReason: String?
    }

    private final class CandidateLedger {
        let workingWidth: Int
        let workingHeight: Int
        var entries: [CandidateLedgerEntry] = []

        init(workingWidth: Int, workingHeight: Int) {
            self.workingWidth = workingWidth
            self.workingHeight = workingHeight
        }

        func append(
            family: String,
            side: String,
            source: String,
            workingGeometry: [CardCenteringPoint],
            support: Double,
            transitionStrength: Double,
            transitionWidth: Double? = nil,
            baseline: Double? = nil,
            mad: Double? = nil,
            threshold: Double? = nil,
            proposedSemanticRole: String,
            selected: Bool,
            rejectionReason: String? = nil
        ) {
            entries.append(CandidateLedgerEntry(
                family: family,
                side: side,
                source: source,
                workingGeometry: workingGeometry,
                support: support,
                transitionStrength: transitionStrength,
                transitionWidth: transitionWidth,
                baseline: baseline,
                mad: mad,
                threshold: threshold,
                proposedSemanticRole: proposedSemanticRole,
                selected: selected,
                rejectionReason: rejectionReason
            ))
        }

        func diagnostic(
            nativeMapping: CardCenteringCoordinateMapping,
            selectedOuterSource: String,
            selectedInnerSource: CardCenteringInnerSource
        ) -> CardCenteringCandidateLedgerDiagnostic {
            func normalized(_ point: CardCenteringPoint) -> CardCenteringPoint {
                CardCenteringPoint(
                    x: point.x / Double(max(workingWidth, 1)),
                    y: point.y / Double(max(workingHeight, 1))
                )
            }

            return CardCenteringCandidateLedgerDiagnostic(
                workingWidth: workingWidth,
                workingHeight: workingHeight,
                selectedOuterSource: selectedOuterSource,
                selectedInnerSource: selectedInnerSource,
                candidates: entries.map { entry in
                    CardCenteringCandidateDiagnostic(
                        family: entry.family,
                        side: entry.side,
                        source: entry.source,
                        workingGeometry: entry.workingGeometry,
                        nativeGeometry: entry.workingGeometry.map(nativeMapping.nativePoint(fromWorking:)),
                        normalizedGeometry: entry.workingGeometry.map(normalized),
                        support: entry.support,
                        transitionStrength: entry.transitionStrength,
                        transitionWidth: entry.transitionWidth,
                        baseline: entry.baseline,
                        mad: entry.mad,
                        threshold: entry.threshold,
                        proposedSemanticRole: entry.proposedSemanticRole,
                        selected: entry.selected,
                        rejectionReason: entry.rejectionReason
                    )
                }
            )
        }
    }

    private struct StageTimingAccumulator {
        var decodeOrientationDownscale = 0.0
        var colorPreparation = 0.0
        var visionRequests = 0.0
        var scalarFields = 0.0
        var outerCandidateRefinement = 0.0
        var innerCandidateGeneration = 0.0
        var jointSelection = 0.0
        var rectification = 0.0
        var resultConstruction = 0.0

        func snapshot() -> CardCenteringStageTimingDiagnostic {
            CardCenteringStageTimingDiagnostic(
                decodeOrientationDownscale: decodeOrientationDownscale,
                colorPreparation: colorPreparation,
                visionRequests: visionRequests,
                scalarFields: scalarFields,
                outerCandidateRefinement: outerCandidateRefinement,
                innerCandidateGeneration: innerCandidateGeneration,
                jointSelection: jointSelection,
                rectification: rectification,
                resultConstruction: resultConstruction
            )
        }
    }
#endif

    private struct CardOutline {
        let edges: CardCenteringEdges
        let quad: CardCenteringQuad
        let innerQuad: CardCenteringQuad?
        let innerReference: CardCenteringInnerReference
        let innerSupport: Double
        /// Positive means the card's top edge slopes down from left to right.
        let skewDegrees: Double
        /// Whether opposite sides support a trustworthy rectification.
        let edgesAreParallel: Bool
        /// A normalized measure of how much long-edge support the outline has.
        let edgeSupport: Double
        /// Evidence that another rectangle surrounds the selected card.
        let sleeveAmbiguity: Double
        let usesVision: Bool
    }

    private struct ScalarDetection {
        let lab: [Pixel]
        let evidenceWidth: Int
        let evidenceHeight: Int
        let outputScaleX: Double
        let outputScaleY: Double
        let borderColor: UIColor
        let outline: CardOutline?
        let outer: CardCenteringEdges
        let inner: CardCenteringEdges
        let pinned: Bool
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

#if DEBUG
    /// Benchmark-only entry point for the resolution/latency curve. Keeping
    /// this separate from the product API prevents a test setting from
    /// changing the normal 1,200-pixel production path.
    static func analyzeForBenchmark(
        _ data: Data,
        workingMaxDimension: CGFloat,
        detectionMaxDimension: CGFloat? = nil
    ) throws -> CardCenteringAnalysis {
        guard workingMaxDimension > 20 else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        if let detectionMaxDimension,
           detectionMaxDimension <= 20 || detectionMaxDimension > workingMaxDimension {
            throw CardCenteringAnalyzerError.renderFailed
        }
        return try analyze(
            data,
            rotationDegrees: 0,
            correctingSkew: true,
            workingMaxDimension: workingMaxDimension,
            detectionMaxDimension: detectionMaxDimension
        )
    }
#endif

    private static func analyze(
        _ data: Data,
        rotationDegrees: Double,
        correctingSkew: Bool,
        padding: UIColor? = nil,
        workingMaxDimension: CGFloat = 1_200,
        detectionMaxDimension: CGFloat? = nil
    ) throws -> CardCenteringAnalysis {
        // Auto-correction is a presentation transform applied after this one
        // detector pass. The old implementation rendered and re-analyzed the
        // image, which doubled both cost and the chance of measuring its padded
        // rotation wedges as card evidence.
#if DEBUG
        var stageTimings = StageTimingAccumulator()
        let decodeStart = CFAbsoluteTimeGetCurrent()
#endif
        let detectionRotationDegrees = correctingSkew ? 0 : rotationDegrees
        guard let source = UIImage(data: data),
              let prepared = prepare(
                  source,
                  rotationDegrees: detectionRotationDegrees,
                  padding: padding ?? .white,
                  maxDimension: workingMaxDimension
              ) else {
            throw CardCenteringAnalyzerError.unreadableImage
        }
        guard let preparedCGImage = prepared.cgImage else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        let width = preparedCGImage.width
        let height = preparedCGImage.height
        guard width > 20, height > 20 else { throw CardCenteringAnalyzerError.renderFailed }
#if DEBUG
        let candidateLedger = CandidateLedger(workingWidth: width, workingHeight: height)
        Self.activeCandidateLedger = candidateLedger
        defer { Self.activeCandidateLedger = nil }
        let detectorSourceScale = min(1, workingMaxDimension / max(source.size.width, source.size.height))
        let detectorMapping = CardCenteringCoordinateMapping(
            orientedSourceSize: CardCenteringSize(
                width: source.size.width * source.scale,
                height: source.size.height * source.scale
            ),
            workingSize: CardCenteringSize(width: Double(width), height: Double(height)),
            appliedRotationDegrees: detectionRotationDegrees,
            unrotatedWorkingSize: CardCenteringSize(
                width: source.size.width * detectorSourceScale,
                height: source.size.height * detectorSourceScale
            )
        )
#endif

        // The benchmark can deliberately detect on a smaller image and refine
        // the selected edge on the full working image. The normal production
        // path leaves both values equal, so this is an explicit experiment,
        // not an accidental resolution change.
        let detectionImage: UIImage
        if let detectionMaxDimension,
           detectionMaxDimension < workingMaxDimension {
            guard let reduced = prepare(
                source,
                rotationDegrees: detectionRotationDegrees,
                padding: padding ?? .white,
                maxDimension: detectionMaxDimension
            ) else {
                throw CardCenteringAnalyzerError.renderFailed
            }
            detectionImage = reduced
        } else {
            detectionImage = prepared
        }
        guard let detectionCGImage = detectionImage.cgImage else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        let detectionWidth = detectionCGImage.width
        let detectionHeight = detectionCGImage.height
        let detectionToWorkingX = Double(width) / Double(max(detectionWidth, 1))
        let detectionToWorkingY = Double(height) / Double(max(detectionHeight, 1))
#if DEBUG
        stageTimings.decodeOrientationDownscale += CFAbsoluteTimeGetCurrent() - decodeStart
        let visionStart = CFAbsoluteTimeGetCurrent()
#endif
        let visionOutline = visionCardOutline(
            image: detectionImage,
            width: detectionWidth,
            height: detectionHeight,
            ledgerScaleX: detectionToWorkingX,
            ledgerScaleY: detectionToWorkingY
        ).map {
            scaled($0, x: detectionToWorkingX, y: detectionToWorkingY)
        }
#if DEBUG
        stageTimings.visionRequests += CFAbsoluteTimeGetCurrent() - visionStart
        let scalarStart = CFAbsoluteTimeGetCurrent()
#endif
        // The scalar path is deliberately lazy. Vision supplies both physical
        // and printed quads for the common case; only a missing proposal or a
        // missing inner reference needs the older Lab/profile evidence. A
        // second, deliberately narrow escape hatch handles a Vision proposal
        // whose shape is not credible or whose outer edge nearly fills the
        // frame: those are the scanner-bed cases where the colour silhouette
        // has better physical-edge evidence. The scalar pass is never used to
        // replace a credible, nested sleeve/card proposal.
        let scalarNeeded = visionOutline == nil
            || visionOutline?.innerQuad == nil
            || visionOutline.map({ scalarValidationNeeded($0, width: width, height: height) }) == true
        let scalar = scalarNeeded
            ? try scalarDetection(
                from: detectionImage,
                outputWidth: width,
                outputHeight: height,
                evidenceMaxDimension: detectionMaxDimension ?? workingMaxDimension
            )
            : nil
#if DEBUG
        stageTimings.scalarFields += CFAbsoluteTimeGetCurrent() - scalarStart
#endif
#if DEBUG
        let outerStart = CFAbsoluteTimeGetCurrent()
#endif
        var outline = preferredOutline(vision: visionOutline, scalar: scalar)
        let proposedOuterQuad = outline?.quad ?? .axisAligned(CardCenteringEdges(
            left: 0,
            top: 0,
            right: width - 1,
            bottom: height - 1
        ))
        var refinedOuterQuad: CardCenteringQuad? = nil
        var workingRGBPixels: [Pixel]? = nil
        if let proposedOutline = outline, proposedOutline.usesVision {
            let rgbPixels = try pixels(from: prepared)
            workingRGBPixels = rgbPixels
            let refined = refineOuterQuad(
                pixels: rgbPixels,
                width: width,
                height: height,
                outer: proposedOutline.quad
            )
            if let refined {
                refinedOuterQuad = refined
                outline = replacingOuterQuad(of: proposedOutline, with: refined)
            }
        }
#if DEBUG
        stageTimings.outerCandidateRefinement += CFAbsoluteTimeGetCurrent() - outerStart
#endif
        let outerRefinementAccepted = refinedOuterQuad != nil
        let outlineHasInner = outline.map { $0.innerQuad != nil } ?? false
        let selectedOuterSource: String
        if outline?.usesVision == true {
            selectedOuterSource = "vision"
        } else if outline != nil {
            selectedOuterSource = "scalar"
        } else if scalar != nil {
            selectedOuterSource = "scalar_fallback"
        } else {
            selectedOuterSource = "frame_fallback"
        }
        var notes: [String] = []
        if outline == nil {
            // The gradient scan below is a guess in exactly the conditions that
            // defeat the outline: a card that does not stand out from what it is
            // lying on, or one bled to the edges of the frame. Say so, rather
            // than letting a guess wear the same face as a measurement.
            notes.append("The card outline could not be found automatically — check the outer guides before reading the result.")
        }
        if let outline, !outline.edgesAreParallel {
            notes.append("The card's side edges are not parallel or could not be compared reliably — the photo may be angled, so the centering reading may not be reliable.")
        }

        // Past the correctable range this is no longer a lean to be taken out;
        // it is a photo taken at an angle, and rotating by a fitted number would
        // be a guess. Rotation on this screen is a display adjustment and does
        // not re-run detection, so the person has to straighten the source.
        if let skew = outline?.skewDegrees, abs(skew) > maximumCorrectableSkew {
            notes.append("The card looks strongly rotated. Straighten the photo and load it again for an accurate reading.")
        }

        let outer = outline?.edges ?? scalar?.outer ?? CardCenteringEdges(
            left: 0,
            top: 0,
            right: width - 1,
            bottom: height - 1
        )
        if outline?.usesVision == false || outline == nil,
           scalar?.pinned == true,
           notes.isEmpty {
            notes.append("The border edges could not be followed confidently — check all four guides before reading the result.")
        }

        let automaticRotation = correctingSkew
            ? ((outline?.skewDegrees).map { abs($0) >= minimumCorrectableSkew && abs($0) <= maximumCorrectableSkew ? -$0 : 0 } ?? 0)
            : rotationDegrees
        let presentationRotationDegrees = correctingSkew ? automaticRotation : rotationDegrees
#if DEBUG
        let presentationStart = CFAbsoluteTimeGetCurrent()
#endif
        let presentationImage: UIImage
        if correctingSkew, abs(presentationRotationDegrees) >= 0.000_1 {
            presentationImage = prepare(
                prepared,
                rotationDegrees: presentationRotationDegrees,
                padding: scalar?.borderColor ?? .white,
                maxDimension: workingMaxDimension
            ) ?? prepared
        } else {
            presentationImage = prepared
        }
#if DEBUG
        stageTimings.decodeOrientationDownscale += CFAbsoluteTimeGetCurrent() - presentationStart
#endif
        guard let presentationCGImage = presentationImage.cgImage else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        let rotationMapping: CardCenteringCoordinateMapping?
        if correctingSkew, abs(presentationRotationDegrees) >= 0.000_1 {
            rotationMapping = CardCenteringCoordinateMapping(
                orientedSourceSize: CardCenteringSize(width: Double(width), height: Double(height)),
                workingSize: CardCenteringSize(
                    width: Double(presentationCGImage.width),
                    height: Double(presentationCGImage.height)
                ),
                appliedRotationDegrees: presentationRotationDegrees,
                unrotatedWorkingSize: CardCenteringSize(width: Double(width), height: Double(height))
            )
        } else {
            rotationMapping = nil
        }

        let sourceScale = min(1, workingMaxDimension / max(source.size.width, source.size.height))
        let unrotatedWorkingSize = CardCenteringSize(
            width: source.size.width * sourceScale,
            height: source.size.height * sourceScale
        )
        let coordinateMapping = CardCenteringCoordinateMapping(
            orientedSourceSize: CardCenteringSize(
                width: source.size.width * source.scale,
                height: source.size.height * source.scale
            ),
            workingSize: CardCenteringSize(
                width: Double(presentationCGImage.width),
                height: Double(presentationCGImage.height)
            ),
            appliedRotationDegrees: presentationRotationDegrees,
            unrotatedWorkingSize: unrotatedWorkingSize
        )

        let detectedOuterQuad = outline?.quad ?? .axisAligned(outer)
        let usesFullResolutionRefinement = detectionMaxDimension.map {
            $0 < workingMaxDimension
        } == true
        let shouldUseWorkingProfile = usesFullResolutionRefinement
            || (outline?.usesVision == true && (scalar == nil || scalar?.pinned == true))
        let pinnedScalarHasCardShapedOutline = scalar?.pinned == true
            && scalar?.outline.map { scalarOutline in
                let measuredAspect = scalarOutline.quad.rectifiedAspectRatio
                let shortToLongAspect = measuredAspect > 1 ? 1 / measuredAspect : measuredAspect
                // A sleeve silhouette can be a few percent short or wide
                // after the scalar mask fit. Keep this broader than the
                // confidence aspect guard while excluding malformed shapes
                // such as a malformed half-height candidate.
                return abs(shortToLongAspect - (5.0 / 7.0)) / (5.0 / 7.0) <= 0.08
            } == true
        let profileWidthCoverage = pinnedScalarHasCardShapedOutline ? 0.80 : 0.85
        let profileHeightCoverage = pinnedScalarHasCardShapedOutline ? 0.80 : 0.88
        let profilePixels: [Pixel]?
#if DEBUG
        let profileColorStart = CFAbsoluteTimeGetCurrent()
#endif
        if shouldUseWorkingProfile {
            let rgbPixels = try workingRGBPixels ?? pixels(from: prepared)
            profilePixels = rgbPixels.map(rgbToLab)
        } else {
            profilePixels = nil
        }
#if DEBUG
        stageTimings.colorPreparation += CFAbsoluteTimeGetCurrent() - profileColorStart
        let innerStart = CFAbsoluteTimeGetCurrent()
#endif
        let profileInnerResult: InnerProfileResult?
        if let profilePixels {
            // A pinned scalar search means its fixed-depth evidence reached a
            // limit; it does not mean the selected physical outer quad lacks
            // an inner reference. Evaluate the profile from that selected quad
            // in working pixels instead of throwing the evidence away because
            // the scalar and Vision estimators disagreed.
            profileInnerResult = innerQuadFromProfiles(
                pixels: profilePixels,
                width: width,
                height: height,
                outer: detectedOuterQuad,
                distanceScale: 1,
                minimumPortraitWidthCoverage: profileWidthCoverage,
                minimumPortraitHeightCoverage: profileHeightCoverage,
                ledgerScaleX: 1,
                ledgerScaleY: 1
            )
        } else if let scalar, !scalar.pinned {
            let evidenceOuter = scaled(
                detectedOuterQuad,
                x: 1 / scalar.outputScaleX,
                y: 1 / scalar.outputScaleY
            )
            profileInnerResult = innerQuadFromProfiles(
                pixels: scalar.lab,
                width: scalar.evidenceWidth,
                height: scalar.evidenceHeight,
                outer: evidenceOuter,
                distanceScale: 1,
                minimumPortraitWidthCoverage: profileWidthCoverage,
                minimumPortraitHeightCoverage: profileHeightCoverage,
                ledgerScaleX: scalar.outputScaleX,
                ledgerScaleY: scalar.outputScaleY
            ).map {
                InnerProfileResult(
                    quad: scaled($0.quad, x: scalar.outputScaleX, y: scalar.outputScaleY),
                    support: $0.support
                )
            }
        } else {
            profileInnerResult = nil
        }
#if DEBUG
        stageTimings.innerCandidateGeneration += CFAbsoluteTimeGetCurrent() - innerStart
        let selectionStart = CFAbsoluteTimeGetCurrent()
#endif
        let detectedInnerQuad: CardCenteringQuad?
        let detectedInnerReference: CardCenteringInnerReference
        let detectedInnerSupport: Double
        let innerSource: CardCenteringInnerSource
        let fittedOuterEdges = detectedOuterQuad.projectedEdges
        let fittedOuterWidth = Double(max(fittedOuterEdges.right - fittedOuterEdges.left, 1))
        let fittedOuterHeight = Double(max(fittedOuterEdges.bottom - fittedOuterEdges.top, 1))
        let scalarOuterAgreesWithVision: Bool
        if let scalar {
            let edgeErrors = [
                abs(scalar.outer.left - fittedOuterEdges.left),
                abs(scalar.outer.right - fittedOuterEdges.right),
                abs(scalar.outer.top - fittedOuterEdges.top),
                abs(scalar.outer.bottom - fittedOuterEdges.bottom)
            ]
            scalarOuterAgreesWithVision = Double(edgeErrors[0]) / fittedOuterWidth <= 0.02
                && Double(edgeErrors[1]) / fittedOuterWidth <= 0.02
                && Double(edgeErrors[2]) / fittedOuterHeight <= 0.02
                && Double(edgeErrors[3]) / fittedOuterHeight <= 0.02
        } else {
            scalarOuterAgreesWithVision = false
        }
        if let scalar, !scalar.pinned, outlineHasInner, scalarOuterAgreesWithVision {
            // A complete scalar pass has an independently fitted colour edge
            // for every side. Prefer that evidence over a Vision rectangle
            // when the latter is merely a printed box or an artwork detail.
            // This is also the legacy recovery path for low-contrast synthetic
            // cards, where Vision's proposal is consistently a few pixels
            // inside the physical border.
            detectedInnerQuad = innerQuad(
                from: scalar.inner,
                relativeTo: scalar.outer,
                in: detectedOuterQuad
            )
            detectedInnerReference = .artWindow
            detectedInnerSupport = 0.5
            innerSource = .scalarInner
        } else if let profileInnerResult {
            detectedInnerQuad = profileInnerResult.quad
            detectedInnerReference = .artWindow
            detectedInnerSupport = profileInnerResult.support
            innerSource = .profile
        } else if let innerQuad = outline?.innerQuad {
            detectedInnerQuad = innerQuad
            detectedInnerReference = outline?.innerReference ?? .printedBorder
            detectedInnerSupport = outline?.innerSupport ?? 0.8
            switch outline?.innerReference {
            case .some(.printedBorder):
                innerSource = .visionPrintedInner
            case .some(.artWindow):
                innerSource = .visionArtWindow
            case .some(.none), nil:
                innerSource = .none
            }
        } else if let scalar,
                  scalarInnerFallbackIsUsable(scalar) {
            // Preserve the scalar path's independently measured inner edge when
            // it also won the physical-edge arbitration. A profile fit can be
            // unavailable on a flat or low-resolution card even though the
            // four per-side gradient candidates are valid.
            detectedInnerQuad = .axisAligned(scalar.inner)
            detectedInnerReference = .artWindow
            detectedInnerSupport = 0.5
            innerSource = .scalarInner
        } else {
            detectedInnerQuad = nil
            detectedInnerReference = .none
            detectedInnerSupport = 0
            innerSource = .none
        }
        if detectedInnerQuad == nil, !notes.contains(where: { $0.contains("inner reference") }) {
            notes.append("No gradeable inner reference was found — adjust the inner guides manually before reading the result.")
        }
        let finalOuterQuad: CardCenteringQuad
        let finalInnerQuad: CardCenteringQuad?
        // Outer and inner geometry are selected in one detector pass. After
        // automatic presentation correction, transform that same pair instead
        // of re-running the profile search on resampled pixels; a second search
        // can select a nearby artwork transition and change the ratio.
        let presentationProfileResult: InnerProfileResult? = nil
        let finalInnerSupport: Double
        if let rotationMapping {
            finalOuterQuad = rotationMapping.workingQuad(fromNative: detectedOuterQuad)
            if let presentationProfileResult {
                finalInnerQuad = presentationProfileResult.quad
                finalInnerSupport = presentationProfileResult.support
            } else {
                finalInnerQuad = detectedInnerQuad.map(rotationMapping.workingQuad(fromNative:))
                finalInnerSupport = detectedInnerSupport
            }
        } else {
            finalOuterQuad = detectedOuterQuad
            finalInnerQuad = detectedInnerQuad
            finalInnerSupport = detectedInnerSupport
        }
#if DEBUG
        stageTimings.jointSelection += CFAbsoluteTimeGetCurrent() - selectionStart
        let rectificationStart = CFAbsoluteTimeGetCurrent()
#endif
        let finalRectification = CardCenteringRectification(outerQuad: finalOuterQuad)
#if DEBUG
        stageTimings.rectification += CFAbsoluteTimeGetCurrent() - rectificationStart
        let resultStart = CFAbsoluteTimeGetCurrent()
#endif

        var measurement = CardCenteringMeasurement(
            imageWidth: presentationCGImage.width,
            imageHeight: presentationCGImage.height,
            outerQuad: finalOuterQuad,
            innerQuad: finalInnerQuad,
            warnings: [],
            detectionNotes: notes,
            coordinateMapping: coordinateMapping,
            innerReference: detectedInnerReference,
            confidence: confidence(
                outline: outline,
                outer: finalOuterQuad,
                inner: finalInnerQuad,
                innerSupport: finalInnerSupport,
                notes: notes,
                rectification: finalRectification
            ),
            rectification: finalRectification
        )
        measurement.refreshWarnings()
#if DEBUG
        stageTimings.resultConstruction += CFAbsoluteTimeGetCurrent() - resultStart
#endif
#if DEBUG
        analysisDiagnosticSink?(CardCenteringAnalysisDiagnostic(
            stageTimings: stageTimings.snapshot(),
            scalarOuterAgreesWithVision: scalarOuterAgreesWithVision,
            scalarPinned: scalar?.pinned,
            outlineHasInner: outlineHasInner,
            innerSource: innerSource,
            visionOuterQuad: visionOutline?.quad,
            scalarOuter: scalar?.outer,
            scalarInner: scalar?.inner,
            scalarOutlineQuad: scalar?.outline?.quad,
            selectedOuterSource: selectedOuterSource,
            selectedSleeveAmbiguity: outline?.sleeveAmbiguity ?? 0,
            proposedOuterQuad: proposedOuterQuad,
            refinedOuterQuad: refinedOuterQuad,
            outerRefinementAccepted: outerRefinementAccepted
        ))
        candidateLedgerDiagnosticSink?(candidateLedger.diagnostic(
            nativeMapping: detectorMapping,
            selectedOuterSource: selectedOuterSource,
            selectedInnerSource: innerSource
        ))
#endif
        return CardCenteringAnalysis(
            image: presentationImage,
            measurement: measurement,
            coordinateMapping: coordinateMapping,
            appliedRotationDegrees: presentationRotationDegrees,
            detectedSkewDegrees: outline?.skewDegrees
        )
    }

    private static func confidence(
        outline: CardOutline?,
        outer: CardCenteringQuad,
        inner: CardCenteringQuad?,
        innerSupport: Double,
        notes: [String],
        rectification: CardCenteringRectification
    ) -> CardCenteringConfidence {
        let nominalAspect = 5.0 / 7.0
        let measuredAspect = outer.rectifiedAspectRatio
        let shortToLongAspect = measuredAspect > 1 ? 1 / measuredAspect : measuredAspect
        let aspectResidual = abs(shortToLongAspect - nominalAspect) / nominalAspect
        let rectificationResidual = rectification.residualDegrees
        let edgeSupport = min(1, max(0, outline?.edgeSupport ?? 0.5))
        let sleeveAmbiguity = min(1, max(0, outline?.sleeveAmbiguity ?? 0))
        let hasOuterEvidence = outline != nil
        let hasInner = inner != nil
        let sourceEdgesAreParallel = outline?.edgesAreParallel ?? true
        let parallelismPasses = sourceEdgesAreParallel
            && rectification.isValid
            && rectificationResidual <= 0.30
        let aspectPasses = aspectResidual <= 0.04
        let innerSupportPasses = innerSupport >= 0.30
        let sleeveAmbiguityPasses = sleeveAmbiguity < 0.25
        let rotationPasses = !notes.contains(where: { $0.contains("strongly rotated") })
        let state: CardCenteringConfidenceState = hasOuterEvidence
            && hasInner
            && innerSupportPasses
            && aspectPasses
            && parallelismPasses
            && sleeveAmbiguityPasses
            && rotationPasses
            ? .confident
            : .declined
        let aspectScore = max(0, 1 - aspectResidual / 0.08)
        let rectificationScore = max(0, 1 - rectificationResidual / 0.60)
        let score = min(
            1,
            max(
                0,
                0.30 * edgeSupport
                    + 0.25 * aspectScore
                    + 0.20 * rectificationScore
                    + 0.20 * min(1, max(0, innerSupport))
                    + 0.05 * (1 - sleeveAmbiguity)
            )
        )
        var reason: String?
        if !hasOuterEvidence {
            reason = "The card outline could not be established reliably. Adjust the outer guides manually before reading centering."
        } else if !hasInner {
            reason = "The image does not contain a stable gradeable inner reference. Adjust the inner guides manually before reading centering."
        } else if !innerSupportPasses {
            reason = "The inner reference is not supported consistently around the card. Adjust the inner guides manually before reading centering."
        } else if !aspectPasses {
            reason = "The detected object has card geometry outside the safe aspect tolerance."
        } else if !parallelismPasses {
            reason = "The detected edges cannot be rectified reliably."
        } else if !sleeveAmbiguityPasses {
            reason = "More than one nested card boundary was found. Adjust the outer guides manually before reading centering."
        } else if notes.contains(where: { $0.contains("strongly rotated") }) {
            reason = "The card is too strongly rotated for an automatic centering reading."
        }
        return CardCenteringConfidence(
            score: state == .declined ? min(score, 0.49) : score,
            state: state,
            edgeSupport: edgeSupport,
            aspectResidual: aspectResidual,
            rectificationResidual: rectificationResidual,
            sleeveAmbiguity: sleeveAmbiguity,
            innerReferencePresent: hasInner,
            reason: reason
        )
    }

    /// Vision is intentionally the fast primary detector, but its rectangle
    /// proposal can lock onto a strong printed box instead of a pale physical
    /// silhouette. Only ask the more expensive scalar evidence pass to arbitrate
    /// when the proposal itself supplies a general geometric reason for doubt.
    private static func scalarValidationNeeded(
        _ vision: CardOutline,
        width: Int,
        height: Int
    ) -> Bool {
        let nominalAspect = 5.0 / 7.0
        let measuredAspect = vision.quad.rectifiedAspectRatio
        let shortToLongAspect = measuredAspect > 1 ? 1 / measuredAspect : measuredAspect
        let aspectResidual = abs(shortToLongAspect - nominalAspect) / nominalAspect
        let coverage = abs(polygonArea(vision.quad.points)) / max(Double(width * height), 1)

        // A full-frame rectangle with no nested sleeve is the characteristic
        // scanner-bed situation in which Vision often sees the high-contrast
        // printed region first. This is a validation trigger, not a minimum
        // framing requirement: smaller or cropped cards still use Vision.
        let silhouetteRisk = coverage >= 0.70 && vision.sleeveAmbiguity <= 0.01
        return aspectResidual > 0.04 || silhouetteRisk
    }

    private static func preferredOutline(
        vision: CardOutline?,
        scalar: ScalarDetection?
    ) -> CardOutline? {
        guard let vision else { return scalar?.outline }
        guard let scalarOutline = scalar?.outline else { return vision }
        // Outer and inner geometry are one hypothesis. Once Vision has found
        // both, replacing only its outer with a scalar silhouette would pair
        // unrelated coordinate systems and make a good inner reference look
        // wrong. Scalar validation may still arbitrate an incomplete Vision
        // proposal below.
        // Once Vision has supplied both the physical and gradeable inner quad,
        // keep that complete hypothesis intact. The scalar silhouette is
        // intentionally axis-aligned and cannot carry a fitted rotation or
        // perspective through the presentation transform; it may arbitrate
        // only when Vision is incomplete or geometrically malformed.
        if vision.innerQuad != nil {
            return vision
        }

        let nominalAspect = 5.0 / 7.0
        func aspectResidual(_ quad: CardCenteringQuad) -> Double {
            let measured = quad.rectifiedAspectRatio
            let shortToLong = measured > 1 ? 1 / measured : measured
            return abs(shortToLong - nominalAspect) / nominalAspect
        }

        let visionResidual = aspectResidual(vision.quad)
        let scalarResidual = aspectResidual(scalarOutline.quad)
        let scalarHasCardShape = scalarResidual <= 0.04
        let scalarRepairsShape = scalarHasCardShape && scalarResidual + 0.02 < visionResidual
        if visionResidual <= 0.04 {
            // A complete-aspect Vision outer remains the best coordinate frame
            // even when its inner-reference search needs scalar evidence. The
            // scalar outline is axis-aligned and can otherwise erase the
            // fitted roll that the presentation transform must preserve.
            return vision
        }
        // A scalar silhouette can be a useful validation of a malformed Vision
        // proposal, but coverage alone is not enough to replace it. On a
        // photographed card the Lab silhouette often stops at the printed
        // texture rather than the physical cut edge, which biases every inner
        // border while still preserving a plausible 5:7 aspect ratio.
        if vision.sleeveAmbiguity == 0, scalarHasCardShape {
            // Vision can find a strong printed rectangle without exposing a
            // gradeable inner reference. Keep the scalar physical-edge and
            // inner-border evidence together instead of pairing unrelated
            // hypotheses. This also covers sideways cards, whose broad Vision
            // request is intentionally portrait-biased.
            return scalarOutline
        }
        if scalarRepairsShape {
            return scalarOutline
        }
        return vision
    }

    /// A pinned scalar candidate has reached one of its search limits and is
    /// not a gradeable inner reference. The one retained legacy exception is a
    /// card whose printed region genuinely reaches both horizontal cut edges;
    /// that still provides useful vertical guides for the existing manual
    /// recovery path, while an asymmetric near-limit candidate is rejected.
    private static func scalarInnerFallbackIsUsable(_ scalar: ScalarDetection) -> Bool {
        guard scalar.pinned else { return true }
        let outer = scalar.outer
        let width = max(1, outer.right - outer.left)
        let height = max(1, outer.bottom - outer.top)
        let aspect = Double(width) / Double(height)
        let shortToLongAspect = aspect > 1 ? 1 / aspect : aspect
        let looksLikeCard = abs(shortToLongAspect - (5.0 / 7.0)) / (5.0 / 7.0) <= 0.04
        let minimumX = max(4, Int((Double(width) * 0.01).rounded()))
        let minimumY = max(4, Int((Double(height) * 0.01).rounded()))
        let left = scalar.inner.left - outer.left
        let right = outer.right - scalar.inner.right
        let top = scalar.inner.top - outer.top
        return looksLikeCard
            && left > minimumX
            && right > minimumX
            && top <= minimumY + 1
    }

    /// Replaces a Vision region proposal with edge lines measured from the
    /// working raster. Vision is good at proposing a card-shaped region, but it
    /// is not the definition of the physical cut edge: its rectangle can settle
    /// on a printed border, sleeve boundary, or a nearby high-contrast detail.
    /// Each normal profile is searched around the proposal for the nearest
    /// coherent 10--90% luminance transition. The accepted points are then fit
    /// as four independent total-least-squares lines and intersected into a
    /// quad. No image resampling or ground-truth information is used here.
    private static func refineOuterQuad(
        pixels: [Pixel],
        width: Int,
        height: Int,
        outer: CardCenteringQuad
    ) -> CardCenteringQuad? {
        guard pixels.count == width * height,
              width > 20,
              height > 20,
              outer.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }

        let center = midpoint(outer.points)
        let shortEdge: Double = min(outer.rectifiedWidth, outer.rectifiedHeight)
        guard shortEdge.isFinite, shortEdge > 12 else { return nil }
        // This pass is a local refinement of a credible Vision region, not a
        // second unconstrained rectangle detector. A profile can legitimately
        // find a nearby sub-pixel correction, but a large move is more likely
        // to be an artwork/banner transition than the physical cut edge. Keep
        // the replacement conservative and leave the original proposal in
        // place when the evidence is not local to it.
        let maximumLocalOffset = max(8.0, shortEdge * 0.02)
        // A physical cut edge should be a localized transition. Broad
        // transitions are commonly caused by a sleeve, glare, or artwork
        // region and do not provide a safe sub-pixel edge replacement.
        let maximumTransitionWidth = max(12.0, shortEdge * 0.02)

        let outwardDistance = max(12, shortEdge * 0.08)
        let inwardDistance = max(16, shortEdge * 0.12)
        let depthSamples = 81
        let alongProgress: [Double] = stride(from: 0.12, through: 0.88, by: 0.03).map { value in
            value
        }
        let edgeSpecifications: [(Side, CardCenteringPoint, CardCenteringPoint)] = [
            (.left, outer.topLeft, outer.bottomLeft),
            (.top, outer.topLeft, outer.topRight),
            (.right, outer.topRight, outer.bottomRight),
            (.bottom, outer.bottomLeft, outer.bottomRight)
        ]
        var lines: [Side: GeometryLine] = [:]
        var acceptedSideCount = 0

        for (side, start, end) in edgeSpecifications {
            let tangentX = end.x - start.x
            let tangentY = end.y - start.y
            let edgeLength = hypot(tangentX, tangentY)
            guard edgeLength > 8 else { return nil }
            let edgeMidpoint = interpolate(start, end, amount: 0.5)
            var normalX = -tangentY / edgeLength
            var normalY = tangentX / edgeLength
            let towardCenterX = center.x - edgeMidpoint.x
            let towardCenterY = center.y - edgeMidpoint.y
            if normalX * towardCenterX + normalY * towardCenterY < 0 {
                normalX = -normalX
                normalY = -normalY
            }

            let offsets = (0..<depthSamples).map { index in
                -outwardDistance
                    + (outwardDistance + inwardDistance)
                    * Double(index) / Double(depthSamples - 1)
            }
            var acceptedOffsets: [Double] = []
            var acceptedStrengths: [Double] = []
            var acceptedTransitionWidths: [Double] = []
            var acceptedContrastDeltas: [Double] = []
            var acceptedPoints: [CardCenteringPoint] = []
#if DEBUG
            let candidateLedger = Self.activeCandidateLedger
                ?? CandidateLedger(workingWidth: width, workingHeight: height)
            func appendRefinementCandidate(
                points: [CardCenteringPoint],
                selected: Bool,
                rejectionReason: String?
            ) {
                guard !points.isEmpty else { return }
                let geometry = points.count > 1
                    ? [points.first!, points.last!]
                    : points
                candidateLedger.append(
                    family: "outer",
                    side: String(describing: side),
                    source: "outer_refinement.normal_profile",
                    workingGeometry: geometry,
                    support: Double(points.count) / Double(max(alongProgress.count, 1)),
                    transitionStrength: median(acceptedStrengths),
                    transitionWidth: acceptedTransitionWidths.isEmpty
                        ? nil
                        : median(acceptedTransitionWidths),
                    proposedSemanticRole: "physical_outer_candidate",
                    selected: selected,
                    rejectionReason: rejectionReason
                )
            }
#endif

            for progress in alongProgress {
                let edgePoint = interpolate(start, end, amount: progress)
                let values = offsets.map { offset in
                    luminance(samplePixel(
                        pixels,
                        width: width,
                        height: height,
                        at: CardCenteringPoint(
                            x: edgePoint.x + normalX * offset,
                            y: edgePoint.y + normalY * offset
                        )
                    ))
                }
                let smoothed = values.indices.map { index in
                    let lower = max(0, index - 1)
                    let upper = min(values.count - 1, index + 1)
                    return values[lower...upper].reduce(0, +) / Double(upper - lower + 1)
                }
                let outside = median(Array(smoothed.prefix(10)))
                let inside = median(Array(smoothed.suffix(10)))
                let delta = inside - outside
                guard abs(delta) >= 0.015 else { continue }

                let lowerTarget = outside + delta * 0.10
                let upperTarget = outside + delta * 0.90
                var candidates: [(offset: Double, strength: Double, width: Double, contrast: Double)] = []
                for index in 1..<(smoothed.count - 1) {
                    let previous = smoothed[index - 1]
                    let current = smoothed[index]
                    let next = smoothed[index + 1]
                    let gradientValue: Double = abs(next - previous)
                    let leftGradient: Double = abs(current - previous)
                    let rightGradient: Double = abs(next - current)
                    guard gradientValue >= leftGradient,
                          gradientValue >= rightGradient,
                          let lowerCrossing = crossing(
                              values: smoothed,
                              positions: offsets,
                              target: lowerTarget,
                              near: index,
                              radius: 12
                          ),
                          let upperCrossing = crossing(
                              values: smoothed,
                              positions: offsets,
                              target: upperTarget,
                              near: index,
                              radius: 12
                          ) else {
                        continue
                    }
                    let transitionOffset: Double = (lowerCrossing + upperCrossing) / 2
                    let transitionWidth: Double = abs(upperCrossing - lowerCrossing)
                    guard transitionOffset >= offsets.first!, transitionOffset <= offsets.last!,
                          transitionWidth <= maximumTransitionWidth else {
                        continue
                    }
                    candidates.append((transitionOffset, gradientValue, transitionWidth, abs(delta)))
                }
                guard let selected = candidates.min(by: { lhs, rhs in
                    if abs(lhs.offset - rhs.offset) > 0.5 {
                        return abs(lhs.offset) < abs(rhs.offset)
                    }
                    return lhs.strength > rhs.strength
                }) else {
                    continue
                }
                acceptedOffsets.append(selected.offset)
                acceptedStrengths.append(selected.strength)
                acceptedTransitionWidths.append(selected.width)
                acceptedContrastDeltas.append(selected.contrast)
                acceptedPoints.append(CardCenteringPoint(
                    x: edgePoint.x + normalX * selected.offset,
                    y: edgePoint.y + normalY * selected.offset
                ))
            }

            let minimumAccepted = max(8, Int(Double(alongProgress.count) * 0.45))
            guard acceptedOffsets.count >= minimumAccepted else {
#if DEBUG
                appendRefinementCandidate(
                    points: acceptedPoints,
                    selected: false,
                    rejectionReason: "too_few_accepted_offsets"
                )
                outerRefinementDiagnosticSink?(CardCenteringOuterRefinementDiagnostic(
                    side: String(describing: side),
                    acceptedOffsets: acceptedOffsets,
                    acceptedStrengths: acceptedStrengths,
                    acceptedTransitionWidths: acceptedTransitionWidths,
                    acceptedContrastDeltas: acceptedContrastDeltas,
                    minimumAccepted: minimumAccepted,
                    maximumLocalOffset: maximumLocalOffset,
                    maximumTransitionWidth: maximumTransitionWidth,
                    offsetMedian: nil,
                    offsetMAD: nil,
                    rejectionDistance: nil,
                    accepted: false,
                    reason: "too_few_accepted_offsets"
                ))
#endif
                lines[side] = fitGeometryLine([start, end])
                continue
            }
            let offsetMedian = median(acceptedOffsets)
            let offsetMAD = median(acceptedOffsets.map { abs($0 - offsetMedian) })
            let rejectionDistance = max(3, offsetMAD * 3)
            // A sleeve edge is a soft, broad transition; a synthetic artwork
            // edge is a sharp, high-gradient transition. Keep the accepted
            // transition localized before allowing it to replace the Vision
            // proposal.
            guard abs(offsetMedian) <= maximumLocalOffset else {
#if DEBUG
                appendRefinementCandidate(
                    points: acceptedPoints,
                    selected: false,
                    rejectionReason: "median_offset_outside_local_guard"
                )
                outerRefinementDiagnosticSink?(CardCenteringOuterRefinementDiagnostic(
                    side: String(describing: side),
                    acceptedOffsets: acceptedOffsets,
                    acceptedStrengths: acceptedStrengths,
                    acceptedTransitionWidths: acceptedTransitionWidths,
                    acceptedContrastDeltas: acceptedContrastDeltas,
                    minimumAccepted: minimumAccepted,
                    maximumLocalOffset: maximumLocalOffset,
                    maximumTransitionWidth: maximumTransitionWidth,
                    offsetMedian: offsetMedian,
                    offsetMAD: offsetMAD,
                    rejectionDistance: rejectionDistance,
                    accepted: false,
                    reason: "median_offset_outside_local_guard"
                ))
#endif
                lines[side] = fitGeometryLine([start, end])
                continue
            }
            let filteredPoints = zip(acceptedOffsets, acceptedPoints).compactMap { offset, point in
                abs(offset - offsetMedian) <= rejectionDistance ? point : nil
            }
            guard filteredPoints.count >= minimumAccepted else {
#if DEBUG
                appendRefinementCandidate(
                    points: filteredPoints,
                    selected: false,
                    rejectionReason: "too_few_offsets_after_mad_filter"
                )
                outerRefinementDiagnosticSink?(CardCenteringOuterRefinementDiagnostic(
                    side: String(describing: side),
                    acceptedOffsets: acceptedOffsets,
                    acceptedStrengths: acceptedStrengths,
                    acceptedTransitionWidths: acceptedTransitionWidths,
                    acceptedContrastDeltas: acceptedContrastDeltas,
                    minimumAccepted: minimumAccepted,
                    maximumLocalOffset: maximumLocalOffset,
                    maximumTransitionWidth: maximumTransitionWidth,
                    offsetMedian: offsetMedian,
                    offsetMAD: offsetMAD,
                    rejectionDistance: rejectionDistance,
                    accepted: false,
                    reason: "too_few_offsets_after_mad_filter"
                ))
#endif
                lines[side] = fitGeometryLine([start, end])
                continue
            }
#if DEBUG
            outerRefinementDiagnosticSink?(CardCenteringOuterRefinementDiagnostic(
                side: String(describing: side),
                acceptedOffsets: acceptedOffsets,
                acceptedStrengths: acceptedStrengths,
                acceptedTransitionWidths: acceptedTransitionWidths,
                acceptedContrastDeltas: acceptedContrastDeltas,
                minimumAccepted: minimumAccepted,
                maximumLocalOffset: maximumLocalOffset,
                maximumTransitionWidth: maximumTransitionWidth,
                offsetMedian: offsetMedian,
                offsetMAD: offsetMAD,
                rejectionDistance: rejectionDistance,
                accepted: true,
                reason: nil
            ))
            appendRefinementCandidate(
                points: filteredPoints,
                selected: true,
                rejectionReason: nil
            )
#endif
            lines[side] = fitGeometryLine(filteredPoints)
            acceptedSideCount += 1
        }

        guard acceptedSideCount > 0 else { return nil }
        guard let top = lines[.top],
              let left = lines[.left],
              let right = lines[.right],
              let bottom = lines[.bottom],
              let topLeft = intersection(top, left),
              let topRight = intersection(top, right),
              let bottomRight = intersection(bottom, right),
              let bottomLeft = intersection(bottom, left) else {
            return nil
        }
        let refined = CardCenteringQuad(
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        )
        guard refined.points.allSatisfy({ point in
            point.x.isFinite && point.y.isFinite
                && point.x >= -Double(width) * 0.08
                && point.x <= Double(width) * 1.08
                && point.y >= -Double(height) * 0.08
                && point.y <= Double(height) * 1.08
        }) else {
            return nil
        }
        let area = abs(polygonArea(refined.points))
        let originalArea = abs(polygonArea(outer.points))
        let aspect = refined.rectifiedAspectRatio
        let shortToLongAspect = aspect > 1 ? 1 / aspect : aspect
        let aspectResidual = abs(shortToLongAspect - (5.0 / 7.0)) / (5.0 / 7.0)
        guard area >= originalArea * 0.70,
              area <= originalArea * 1.30,
              aspectResidual <= 0.10,
              parallelismResidual(for: refined) <= 4.0 else {
            return nil
        }
        return refined
    }

    private static func crossing(
        values: [Double],
        positions: [Double],
        target: Double,
        near index: Int,
        radius: Int
    ) -> Double? {
        guard values.count == positions.count, values.count >= 2 else { return nil }
        let lower = max(0, index - radius)
        let upper = min(values.count - 2, index + radius)
        var best: (distance: Int, position: Double)?
        for segment in lower...upper {
            let first = values[segment] - target
            let second = values[segment + 1] - target
            guard first == 0 || second == 0 || first * second < 0 else { continue }
            let amount: Double
            if abs(second - first) <= .ulpOfOne {
                amount = 0
            } else {
                amount = min(max(-first / (second - first), 0), 1)
            }
            let position = positions[segment]
                + (positions[segment + 1] - positions[segment]) * amount
            let distance = min(abs(segment - index), abs(segment + 1 - index))
            if best == nil || distance < best!.distance {
                best = (distance, position)
            }
        }
        return best?.position
    }

    private static func luminance(_ pixel: Pixel) -> Double {
        0.2126 * Double(pixel.l)
            + 0.7152 * Double(pixel.a)
            + 0.0722 * Double(pixel.b)
    }

    private static func replacingOuterQuad(
        of outline: CardOutline,
        with outer: CardCenteringQuad
    ) -> CardOutline {
        let inner = outline.innerQuad.map {
            mappedQuad($0, from: outline.quad, to: outer)
        }
        return CardOutline(
            edges: outer.projectedEdges,
            quad: outer,
            innerQuad: inner,
            innerReference: outline.innerReference,
            innerSupport: outline.innerSupport,
            // Keep the proposal's roll estimate as the presentation-control
            // signal. The refinement is intentionally allowed to move an edge
            // by a few pixels, but using that independently fitted line pair
            // for auto-rotation would turn sub-pixel edge noise into a visible
            // 0.3--0.6 degree change. The refined quad still supplies the
            // measurement and rectification geometry below.
            skewDegrees: outline.skewDegrees,
            edgesAreParallel: outline.edgesAreParallel,
            edgeSupport: outline.edgeSupport,
            sleeveAmbiguity: outline.sleeveAmbiguity,
            usesVision: outline.usesVision
        )
    }

    private static func mappedQuad(
        _ quad: CardCenteringQuad,
        from source: CardCenteringQuad,
        to destination: CardCenteringQuad
    ) -> CardCenteringQuad {
        func map(_ point: CardCenteringPoint) -> CardCenteringPoint {
            guard let coordinates = bilinearCoordinates(of: point, in: source) else {
                return point
            }
            return bilinearPoint(in: destination, u: coordinates.u, v: coordinates.v)
        }
        return CardCenteringQuad(
            topLeft: map(quad.topLeft),
            topRight: map(quad.topRight),
            bottomRight: map(quad.bottomRight),
            bottomLeft: map(quad.bottomLeft)
        )
    }

    private static func bilinearPoint(
        in quad: CardCenteringQuad,
        u: Double,
        v: Double
    ) -> CardCenteringPoint {
        let top = interpolate(quad.topLeft, quad.topRight, amount: u)
        let bottom = interpolate(quad.bottomLeft, quad.bottomRight, amount: u)
        return interpolate(top, bottom, amount: v)
    }

    private static func bilinearCoordinates(
        of point: CardCenteringPoint,
        in quad: CardCenteringQuad
    ) -> (u: Double, v: Double)? {
        let a = quad.topLeft
        let b = CardCenteringPoint(x: quad.topRight.x - a.x, y: quad.topRight.y - a.y)
        let c = CardCenteringPoint(x: quad.bottomLeft.x - a.x, y: quad.bottomLeft.y - a.y)
        let d = CardCenteringPoint(
            x: a.x - quad.topRight.x - quad.bottomLeft.x + quad.bottomRight.x,
            y: a.y - quad.topRight.y - quad.bottomLeft.y + quad.bottomRight.y
        )
        var u = 0.5
        var v = 0.5
        for _ in 0..<12 {
            let predicted = CardCenteringPoint(
                x: a.x + b.x * u + c.x * v + d.x * u * v,
                y: a.y + b.y * u + c.y * v + d.y * u * v
            )
            let errorX = predicted.x - point.x
            let errorY = predicted.y - point.y
            if hypot(errorX, errorY) <= 1e-6 { break }
            let derivativeU = CardCenteringPoint(x: b.x + d.x * v, y: b.y + d.y * v)
            let derivativeV = CardCenteringPoint(x: c.x + d.x * u, y: c.y + d.y * u)
            let determinant = derivativeU.x * derivativeV.y - derivativeV.x * derivativeU.y
            guard abs(determinant) > 1e-10 else { return nil }
            let deltaU = (errorX * derivativeV.y - derivativeV.x * errorY) / determinant
            let deltaV = (derivativeU.x * errorY - errorX * derivativeU.y) / determinant
            u -= deltaU
            v -= deltaV
            guard u.isFinite, v.isFinite else { return nil }
        }
        guard u >= -0.10, u <= 1.10, v >= -0.10, v <= 1.10 else { return nil }
        return (min(max(u, 0), 1), min(max(v, 0), 1))
    }

    private static func scaled(
        _ edges: CardCenteringEdges,
        x xScale: Double,
        y yScale: Double
    ) -> CardCenteringEdges {
        CardCenteringEdges(
            left: Int((Double(edges.left) * xScale).rounded()),
            top: Int((Double(edges.top) * yScale).rounded()),
            right: Int((Double(edges.right) * xScale).rounded()),
            bottom: Int((Double(edges.bottom) * yScale).rounded())
        )
    }

    private static func scaled(
        _ point: CardCenteringPoint,
        x xScale: Double,
        y yScale: Double
    ) -> CardCenteringPoint {
        CardCenteringPoint(x: point.x * xScale, y: point.y * yScale)
    }

    private static func scaled(
        _ quad: CardCenteringQuad,
        x xScale: Double,
        y yScale: Double
    ) -> CardCenteringQuad {
        CardCenteringQuad(
            topLeft: scaled(quad.topLeft, x: xScale, y: yScale),
            topRight: scaled(quad.topRight, x: xScale, y: yScale),
            bottomRight: scaled(quad.bottomRight, x: xScale, y: yScale),
            bottomLeft: scaled(quad.bottomLeft, x: xScale, y: yScale)
        )
    }

    /// Transfers an axis-aligned scalar measurement into the fitted Vision
    /// frame without pairing its pixel coordinates with a different outer
    /// rectangle. Scalar evidence is measured in its own resized image; the
    /// four fractional edge positions are the part that survives that resize
    /// and can be applied to a perspective quad safely.
    private static func innerQuad(
        from inner: CardCenteringEdges,
        relativeTo outer: CardCenteringEdges,
        in fittedOuter: CardCenteringQuad
    ) -> CardCenteringQuad {
        let width = Double(max(outer.right - outer.left, 1))
        let height = Double(max(outer.bottom - outer.top, 1))
        let left = min(max(Double(inner.left - outer.left) / width, 0), 1)
        let right = min(max(Double(inner.right - outer.left) / width, 0), 1)
        let top = min(max(Double(inner.top - outer.top) / height, 0), 1)
        let bottom = min(max(Double(inner.bottom - outer.top) / height, 0), 1)

        func point(u: Double, v: Double) -> CardCenteringPoint {
            let topEdge = interpolate(fittedOuter.topLeft, fittedOuter.topRight, amount: u)
            let bottomEdge = interpolate(fittedOuter.bottomLeft, fittedOuter.bottomRight, amount: u)
            return interpolate(topEdge, bottomEdge, amount: v)
        }

        return CardCenteringQuad(
            topLeft: point(u: left, v: top),
            topRight: point(u: right, v: top),
            bottomRight: point(u: right, v: bottom),
            bottomLeft: point(u: left, v: bottom)
        )
    }

    private static func scaled(
        _ outline: CardOutline,
        x xScale: Double,
        y yScale: Double
    ) -> CardOutline {
        CardOutline(
            edges: scaled(outline.edges, x: xScale, y: yScale),
            quad: scaled(outline.quad, x: xScale, y: yScale),
            innerQuad: outline.innerQuad.map { scaled($0, x: xScale, y: yScale) },
            innerReference: outline.innerReference,
            innerSupport: outline.innerSupport,
            skewDegrees: outline.skewDegrees,
            edgesAreParallel: outline.edgesAreParallel,
            edgeSupport: outline.edgeSupport,
            sleeveAmbiguity: outline.sleeveAmbiguity,
            usesVision: outline.usesVision
        )
    }

    private static func parallelismResidual(for quad: CardCenteringQuad) -> Double {
        let top = atan2(quad.topRight.y - quad.topLeft.y, quad.topRight.x - quad.topLeft.x)
        let bottom = atan2(quad.bottomRight.y - quad.bottomLeft.y, quad.bottomRight.x - quad.bottomLeft.x)
        let left = atan2(quad.bottomLeft.y - quad.topLeft.y, quad.bottomLeft.x - quad.topLeft.x)
        let right = atan2(quad.bottomRight.y - quad.topRight.y, quad.bottomRight.x - quad.topRight.x)
        let radians = max(angleDifference180(top, bottom), angleDifference180(left, right))
        return radians * 180 / .pi
    }

    private enum Side: CaseIterable, Hashable {
        case left, right, top, bottom
    }

    private static func prepare(
        _ image: UIImage,
        rotationDegrees: Double,
        padding: UIColor,
        maxDimension: CGFloat = 1_200
    ) -> UIImage? {
        guard image.cgImage != nil else { return nil }
        // Camera photos commonly carry their portrait rotation in
        // `imageOrientation` while the CGImage remains landscape. Using the raw
        // CGImage dimensions here and then drawing the oriented UIImage stretches
        // the card before edge detection. Work from UIImage's display size so the
        // pixels and the orientation describe the same rectangle.
        let originalWidth = image.size.width
        let originalHeight = image.size.height
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

    private static func pixels(from image: UIImage) throws -> [Pixel] {
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
        var result: [Pixel] = []
        result.reserveCapacity(width * height)
        var index = 0
        while index < bytes.count {
            let red = Float(bytes[index]) / 255
            let green = Float(bytes[index + 1]) / 255
            let blue = Float(bytes[index + 2]) / 255
            result.append(Pixel(l: red, a: green, b: blue))
            index += 4
        }
        return result
    }

    private static func scalarDetection(
        from image: UIImage,
        outputWidth: Int,
        outputHeight: Int,
        evidenceMaxDimension: CGFloat
    ) throws -> ScalarDetection {
        // The scalar detector is evidence arbitration, not the reported
        // working image. Keep the required 1,200px working image for Vision
        // and final coordinates, but run the expensive Lab/gradient fallback
        // on a smaller evidence image and scale its fitted geometry back into
        // that working space. Synthetic images below this cap are unchanged.
        guard let evidenceImage = prepare(
            image,
            rotationDegrees: 0,
            padding: .white,
            maxDimension: evidenceMaxDimension
        ), let evidenceCGImage = evidenceImage.cgImage else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        let width = evidenceCGImage.width
        let height = evidenceCGImage.height
        let pixels = try pixels(from: evidenceImage)
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
        let topOuterSet = candidates(
            horizontalScores(gy, width: width, height: height, yRange: 0..<outerY, xRange: xRange),
            offset: 0
        )
        let bottomStart = max(0, height - outerY - 1)
        let bottomOuterSet = candidates(
            horizontalScores(gy, width: width, height: height, yRange: bottomStart..<(height - 1), xRange: xRange),
            offset: bottomStart
        )
        let outerTop = topOuterSet.candidates.first!.position
        let outerBottom = bottomOuterSet.candidates.last!.position

        // Measure vertical evidence only along the straight body of the card,
        // keeping rounded corners and scanner-bed marks out of the side fit.
        let detectedHeight = max(1, outerBottom - outerTop)
        let verticalInset = max(2, Int((Double(detectedHeight) * 0.08).rounded()))
        let yStart = clamped(outerTop + verticalInset, 0, height - 1)
        let yEnd = clamped(outerBottom - verticalInset, yStart + 1, height)
        let yRange = yStart..<yEnd
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

        let outline = cardOutline(lab: lab, width: width, height: height)
        let outer = outline?.edges ?? CardCenteringEdges(
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
            .left: candidates(
                verticalScores(gx, width: width, height: height, xRange: leftStart..<leftEnd, yRange: yRange),
                offset: leftStart,
                madMultiplier: 1.1
            ),
            .right: candidates(
                verticalScores(gx, width: width, height: height, xRange: rightStartInner..<rightEndInner, yRange: yRange),
                offset: rightStartInner,
                madMultiplier: 1.1
            ),
            .top: candidates(
                horizontalScores(gy, width: width, height: height, yRange: topStart..<topEnd, xRange: xRange),
                offset: topStart,
                madMultiplier: 1.1
            ),
            .bottom: candidates(
                horizontalScores(gy, width: width, height: height, yRange: bottomStartInner..<bottomEndInner, xRange: xRange),
                offset: bottomStartInner,
                madMultiplier: 1.1
            )
        ]

        let searchDepths: [Side: Int] = [.left: maxX, .right: maxX, .top: maxY, .bottom: maxY]
        var chosen: [Side: Int] = [:]
        var borderWalk: [Side: Int] = [:]
        for side in Side.allCases {
            let depth = searchDepths[side] ?? maxX
            let minimum = side == .left || side == .right ? minX : minY
            if let border = borderEnd(
                side: side,
                lab: lab,
                width: width,
                height: height,
                outer: outer,
                minimum: minimum,
                maximum: depth
            ) {
                chosen[side] = border
                borderWalk[side] = border
            } else {
                chosen[side] = chooseInner(side: side, set: innerSets[side]!, outer: outer).position
            }
        }
        let inner = CardCenteringEdges(
            left: chosen[.left]!,
            top: chosen[.top]!,
            right: chosen[.right]!,
            bottom: chosen[.bottom]!
        )
        let pinned = [
            (inner.left - outer.left, minX, maxX),
            (outer.right - inner.right, minX, maxX),
            (inner.top - outer.top, minY, maxY),
            (outer.bottom - inner.bottom, minY, maxY)
        ].contains { border, lower, upper in border <= lower || border >= upper }

        let scaleX = Double(outputWidth) / Double(width)
        let scaleY = Double(outputHeight) / Double(height)
#if DEBUG
        let candidateLedger = Self.activeCandidateLedger
            ?? CandidateLedger(workingWidth: outputWidth, workingHeight: outputHeight)
        func ledgerPoint(x: Double, y: Double) -> CardCenteringPoint {
            CardCenteringPoint(x: x * scaleX, y: y * scaleY)
        }

        func ledgerLine(side: Side, position: Int) -> [CardCenteringPoint] {
            switch side {
            case .left, .right:
                return [
                    ledgerPoint(x: Double(position), y: Double(yRange.lowerBound)),
                    ledgerPoint(x: Double(position), y: Double(max(yRange.lowerBound, yRange.upperBound - 1)))
                ]
            case .top, .bottom:
                return [
                    ledgerPoint(x: Double(xRange.lowerBound), y: Double(position)),
                    ledgerPoint(x: Double(max(xRange.lowerBound, xRange.upperBound - 1)), y: Double(position))
                ]
            }
        }

        func ledgerQuadEdge(_ quad: CardCenteringQuad, side: Side) -> [CardCenteringPoint] {
            switch side {
            case .left: [quad.topLeft, quad.bottomLeft]
            case .right: [quad.topRight, quad.bottomRight]
            case .top: [quad.topLeft, quad.topRight]
            case .bottom: [quad.bottomLeft, quad.bottomRight]
            }
        }

        func appendGradientCandidates(
            _ set: CandidateSet,
            family: String,
            side: Side,
            source: String,
            selectedPosition: Int?,
            selectedReason: String,
            role: String
        ) {
            for candidate in set.candidates {
                let selected = selectedPosition == candidate.position
                candidateLedger.append(
                    family: family,
                    side: String(describing: side),
                    source: source,
                    workingGeometry: ledgerLine(side: side, position: candidate.position),
                    support: Double(candidate.support),
                    transitionStrength: Double(candidate.strength),
                    baseline: Double(set.baseline),
                    mad: Double(set.mad),
                    threshold: Double(set.threshold),
                    proposedSemanticRole: role,
                    selected: selected,
                    rejectionReason: selected ? nil : selectedReason
                )
            }
        }

        let scalarOuterPositions: [Side: Int] = [
            .left: outer.left,
            .right: outer.right,
            .top: outer.top,
            .bottom: outer.bottom
        ]
        let scalarInnerPositions: [Side: Int] = [
            .left: inner.left,
            .right: inner.right,
            .top: inner.top,
            .bottom: inner.bottom
        ]
        let outerSets: [Side: CandidateSet] = [
            .left: leftOuterSet,
            .right: rightOuterSet,
            .top: topOuterSet,
            .bottom: bottomOuterSet
        ]
        for side in Side.allCases {
            let outerReason: String
            let outerSelectedPosition: Int?
            if outline != nil {
                outerReason = "scalar_mask_outline_won"
                outerSelectedPosition = nil
            } else if (side == .left || side == .right), silhouette != nil {
                outerReason = "scalar_silhouette_won"
                outerSelectedPosition = nil
            } else {
                outerReason = "not_selected_by_scalar_selector"
                outerSelectedPosition = scalarOuterPositions[side]
            }
            appendGradientCandidates(
                outerSets[side]!,
                family: "outer",
                side: side,
                source: "scalar.gradient.outer",
                selectedPosition: outerSelectedPosition,
                selectedReason: outerReason,
                role: "physical_outer_candidate"
            )
            appendGradientCandidates(
                innerSets[side]!,
                family: "inner",
                side: side,
                source: "scalar.gradient.inner",
                selectedPosition: borderWalk[side] == nil ? scalarInnerPositions[side] : nil,
                selectedReason: borderWalk[side] == nil
                    ? "not_selected_by_scalar_selector"
                    : "scalar_border_walk_won",
                role: "untyped_inner_reference"
            )
        }

        if let silhouette {
            for (side, position) in [(Side.left, silhouette.left), (Side.right, silhouette.right)] {
                let selected = outline == nil && scalarOuterPositions[side] == position
                candidateLedger.append(
                    family: "outer",
                    side: String(describing: side),
                    source: "scalar.silhouette",
                    workingGeometry: ledgerLine(side: side, position: position),
                    support: 1,
                    transitionStrength: 1,
                    proposedSemanticRole: "physical_outer_candidate",
                    selected: selected,
                    rejectionReason: selected ? nil : "not_selected_by_scalar_selector"
                )
            }
        }

        if let outline {
            for side in Side.allCases {
                let geometry = ledgerQuadEdge(outline.quad, side: side).map {
                    ledgerPoint(x: $0.x, y: $0.y)
                }
                candidateLedger.append(
                    family: "outer",
                    side: String(describing: side),
                    source: "scalar.mask_outline",
                    workingGeometry: geometry,
                    support: outline.edgeSupport,
                    transitionStrength: outline.edgeSupport,
                    proposedSemanticRole: "physical_outer_candidate",
                    selected: true
                )
            }
        }

        for (side, position) in borderWalk {
            candidateLedger.append(
                family: "inner",
                side: String(describing: side),
                source: "scalar.border_walk",
                workingGeometry: ledgerLine(side: side, position: position),
                support: 1,
                transitionStrength: 0,
                proposedSemanticRole: "untyped_inner_reference",
                selected: true
            )
        }
#endif
        return ScalarDetection(
            lab: lab,
            evidenceWidth: width,
            evidenceHeight: height,
            outputScaleX: scaleX,
            outputScaleY: scaleY,
            borderColor: borderColor(pixels: pixels, width: width, height: height),
            outline: outline.map { scaled($0, x: scaleX, y: scaleY) },
            outer: scaled(outer, x: scaleX, y: scaleY),
            inner: scaled(inner, x: scaleX, y: scaleY),
            pinned: pinned
        )
    }

    private static func rgbToLab(_ rgb: Pixel) -> Pixel {
        func linear(_ value: Float) -> Float {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(rgb.l), g = linear(rgb.a), b = linear(rgb.b)
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
        guard !scores.isEmpty else {
            return CandidateSet(
                candidates: [Candidate(position: offset, strength: 0, support: 0)],
                baseline: 0,
                mad: 0,
                threshold: 0
            )
        }
        let smoothed = scores.indices.map { index -> Float in
            let range = max(0, index - 2)...min(scores.count - 1, index + 2)
            return range.reduce(0) { $0 + scores[$1] } / Float(range.count)
        }
        let baseline = median(smoothed)
        let mad = median(smoothed.map { abs($0 - baseline) })
        let maximum = smoothed.max() ?? 0
        let threshold = max(baseline + madMultiplier * max(mad, 0.000_001), 0.12 * maximum)
        var found: [Int: Candidate] = [:]

        for index in smoothed.indices {
            let left = index == 0 ? -Float.infinity : smoothed[index - 1]
            let right = index == smoothed.count - 1 ? -Float.infinity : smoothed[index + 1]
            guard smoothed[index] >= left, smoothed[index] >= right, smoothed[index] >= threshold else { continue }
            let refinement = max(0, index - 2)...min(scores.count - 1, index + 2)
            let rawIndex = refinement.max(by: { scores[$0] < scores[$1] }) ?? index
            let position = offset + rawIndex
            let supportRange = max(0, rawIndex - 2)...min(scores.count - 1, rawIndex + 2)
            let support = Float(supportRange.filter { smoothed[$0] >= threshold }.count)
                / Float(max(1, supportRange.count))
            let candidate = Candidate(
                position: position,
                strength: scores[rawIndex],
                support: support
            )
            if let existing = found[position], existing.strength >= candidate.strength {
                continue
            }
            found[position] = candidate
        }
        if found.isEmpty, let strongest = scores.indices.max(by: { scores[$0] < scores[$1] }) {
            let supportRange = max(0, strongest - 2)...min(scores.count - 1, strongest + 2)
            found[offset + strongest] = Candidate(
                position: offset + strongest,
                strength: scores[strongest],
                support: Float(supportRange.filter { smoothed[$0] >= threshold }.count)
                    / Float(max(1, supportRange.count))
            )
        }
        return CandidateSet(
            candidates: found.values.sorted { $0.position < $1.position },
            baseline: baseline,
            mad: mad,
            threshold: threshold
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
        pixels: [Pixel],
        width: Int,
        height: Int
    ) -> UIColor {
        let ring = ringWidth(width: width, height: height)
        var red: [Float] = [], green: [Float] = [], blue: [Float] = []
        for index in ringIndices(width: width, height: height, ring: ring) {
            let pixel = pixels[index]
            red.append(pixel.l); green.append(pixel.a); blue.append(pixel.b)
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

    /// Vision supplies a rectangle proposal without making the centering
    /// decision for us. It is only used to establish the physical card quad;
    /// inner geometry is still scored independently below. Working on the
    /// already orientation-normalized image keeps EXIF and detector coordinates
    /// in the same space.
    private static func visionCardOutline(
        image: UIImage,
        width: Int,
        height: Int,
        ledgerScaleX: Double = 1,
        ledgerScaleY: Double = 1
    ) -> CardOutline? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.45
        // Admit both portrait and landscape cards. The post-filter below keeps
        // the product's 0.45...2.0 policy, but it cannot recover an observation
        // that this request rejected before Vision emitted it.
        request.maximumAspectRatio = 2.0
        // This is a quality floor, not a framing assumption. The same image
        // may arrive cropped or with a card farther from the camera, so the
        // detector must not require a fixed fraction of the source canvas.
        request.minimumSize = 0.01
        request.quadratureTolerance = 30
        request.maximumObservations = 12
        request.minimumConfidence = 0.20

        // A card's front artwork window is not constrained to the card's
        // portrait aspect ratio. Keep this second proposal set separate from
        // the physical-card detector: a broad request is useful for finding a
        // landscape art panel, but its smaller text boxes must never be allowed
        // to replace the outer card quad.
        let broadRequest = VNDetectRectanglesRequest()
        broadRequest.minimumAspectRatio = 0.12
        broadRequest.maximumAspectRatio = 1.50
        broadRequest.minimumSize = 0.01
        broadRequest.quadratureTolerance = 30
        broadRequest.maximumObservations = 20
        broadRequest.minimumConfidence = 0.10

        do {
            try VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]).perform([request, broadRequest])
        } catch {
            return nil
        }

        func makeQuads(
            from results: [VNRectangleObservation]?,
            minimumConfidence: Float
        ) -> [CardCenteringQuad] {
            (results ?? [])
            .filter { $0.confidence >= minimumConfidence }
            .map { observation in
                CardCenteringQuad(
                    topLeft: visionPoint(
                        observation.topLeft,
                        targetWidth: width,
                        targetHeight: height
                    ),
                    topRight: visionPoint(
                        observation.topRight,
                        targetWidth: width,
                        targetHeight: height
                    ),
                    bottomRight: visionPoint(
                        observation.bottomRight,
                        targetWidth: width,
                        targetHeight: height
                    ),
                    bottomLeft: visionPoint(
                        observation.bottomLeft,
                        targetWidth: width,
                        targetHeight: height
                    )
                )
            }
            .filter { quad in
                let area = abs(polygonArea(quad.points))
                let aspect = quad.rectifiedAspectRatio
                return area >= 100
                    && (0.45...2.0).contains(aspect)
                    && quad.points.allSatisfy { point in
                        point.x >= -Double(width) * 0.08
                            && point.x <= Double(width) * 1.08
                            && point.y >= -Double(height) * 0.08
                            && point.y <= Double(height) * 1.08
                    }
            }
            .sorted { abs(polygonArea($0.points)) > abs(polygonArea($1.points)) }
        }

        let quads = makeQuads(from: request.results, minimumConfidence: 0.20)

        guard !quads.isEmpty else { return nil }
        let nestedPairs: [(outerIndex: Int, innerIndex: Int)] = quads.indices.flatMap { outerIndex in
            quads.indices.compactMap { innerIndex in
                guard outerIndex != innerIndex else { return nil }
                let enclosing = quads[outerIndex]
                let candidate = quads[innerIndex]
                let enclosingArea = abs(polygonArea(enclosing.points))
                let candidateArea = abs(polygonArea(candidate.points))
                guard enclosingArea > candidateArea,
                      candidateArea / max(enclosingArea, .ulpOfOne) >= 0.90,
                      candidateArea / max(enclosingArea, .ulpOfOne) <= 0.985,
                      candidate.rectifiedAspectRatio / max(enclosing.rectifiedAspectRatio, .ulpOfOne) >= 0.96,
                      candidate.rectifiedAspectRatio / max(enclosing.rectifiedAspectRatio, .ulpOfOne) <= 1.04,
                      contains(enclosing, candidate.points) else { return nil }
                let enclosingCenter = midpoint(enclosing.points)
                let candidateCenter = midpoint(candidate.points)
                let candidateWidth = max(enclosing.topLength, enclosing.bottomLength)
                let candidateHeight = max(enclosing.leftLength, enclosing.rightLength)
                guard abs(candidateCenter.x - enclosingCenter.x) <= candidateWidth * 0.04,
                      abs(candidateCenter.y - enclosingCenter.y) <= candidateHeight * 0.04 else { return nil }
                let border = enclosing.borderDistances(to: candidate)
                guard [border.left, border.top, border.right, border.bottom].allSatisfy({ $0 >= 2 }) else {
                    return nil
                }
                return (outerIndex, innerIndex)
            }
        }
        let selectedPair = nestedPairs.max { lhs, rhs in
            let lhsArea = abs(polygonArea(quads[lhs.innerIndex].points))
            let rhsArea = abs(polygonArea(quads[rhs.innerIndex].points))
            return lhsArea < rhsArea
        }
        let nominalAspect = 5.0 / 7.0
        func aspectResidual(_ quad: CardCenteringQuad) -> Double {
            let measured = quad.rectifiedAspectRatio
            let shortToLong = measured > 1 ? 1 / measured : measured
            return abs(shortToLong - nominalAspect) / nominalAspect
        }
        let largestArea = abs(polygonArea(quads[0].points))
        let largestIsCardShaped = aspectResidual(quads[0]) <= 0.04
        let cardShapedFallback = quads.indices.first { index in
            index != 0
                && abs(polygonArea(quads[index].points)) >= largestArea * 0.55
                && aspectResidual(quads[index]) <= 0.04
        }
        // A crop can leave the crop boundary as the largest card-shaped
        // rectangle. If that boundary encloses a second, similarly shaped
        // proposal with a substantial (but not sleeve-sized) inset, use the
        // contained proposal as the physical card. This is deliberately gated
        // on the enclosing quad touching the image frame; an inner printed
        // border inside a normally framed card must not win this arbitration.
        let frameEnclosedCard = quads.indices.dropFirst().filter { candidateIndex in
            let frame = quads[0]
            let candidate = quads[candidateIndex]
            let frameMargin = frame.points.map { point in
                let horizontal = min(point.x, Double(width) - point.x) / Double(max(width, 1))
                let vertical = min(point.y, Double(height) - point.y) / Double(max(height, 1))
                return min(horizontal, vertical)
            }.min() ?? 1
            let areaRatio = abs(polygonArea(candidate.points)) / max(largestArea, .ulpOfOne)
            let candidateAspectResidual = aspectResidual(candidate)
            let candidateCenter = midpoint(candidate.points)
            let frameCenter = midpoint(frame.points)
            let candidateWidth = max(candidate.topLength, candidate.bottomLength)
            let candidateHeight = max(candidate.leftLength, candidate.rightLength)
            let frameMinX = frame.points.map(\.x).min() ?? 0
            let frameMaxX = frame.points.map(\.x).max() ?? 0
            let frameMinY = frame.points.map(\.y).min() ?? 0
            let frameMaxY = frame.points.map(\.y).max() ?? 0
            let candidateWithinFrame = candidate.points.allSatisfy { point in
                point.x >= frameMinX
                    && point.x <= frameMaxX
                    && point.y >= frameMinY
                    && point.y <= frameMaxY
            }
            // A real crop boundary is expected to touch the image frame, not
            // merely sit inside the ordinary photo margin around a card. The
            // previous 4% allowance promoted the printed image rectangle on
            // several normally framed card backs to the physical outer.
            return frameMargin <= 0.02
                && (0.75...0.90).contains(areaRatio)
                && candidateAspectResidual <= 0.04
                && abs(candidateCenter.x - frameCenter.x) <= candidateWidth * 0.06
                && abs(candidateCenter.y - frameCenter.y) <= candidateHeight * 0.06
                && candidateWithinFrame
        }.max { lhs, rhs in
            abs(polygonArea(quads[lhs].points)) < abs(polygonArea(quads[rhs].points))
        }
        // A sleeve or glare boundary can be the largest rectangle without
        // satisfying the card's own aspect guard. In that case, prefer the
        // largest nearby card-shaped proposal instead of treating the sleeve
        // as the physical card. The stricter nested-pair path remains the
        // primary sleeve/card disambiguation when it has enough evidence.
        let outerIndex = selectedPair?.innerIndex
            ?? frameEnclosedCard
            ?? (!largestIsCardShaped ? cardShapedFallback : nil)
            ?? 0
        let outer = quads[outerIndex]
        let outerArea = abs(polygonArea(outer.points))
        let outerWidth = (outer.topLength + outer.bottomLength) / 2
        let outerHeight = (outer.leftLength + outer.rightLength) / 2
        let sleeveAmbiguity = nestedPairs.count > 1 ? 0.25 : (selectedPair == nil ? 0 : 0.05)
        func hasBalancedOppositeEdges(_ candidate: CardCenteringQuad) -> Bool {
            let horizontalBalance = min(candidate.topLength, candidate.bottomLength)
                / max(candidate.topLength, candidate.bottomLength, .ulpOfOne)
            let verticalBalance = min(candidate.leftLength, candidate.rightLength)
                / max(candidate.leftLength, candidate.rightLength, .ulpOfOne)
            return horizontalBalance >= 0.80 && verticalBalance >= 0.80
        }
        let printedInner = quads.indices.first(where: { index in
            guard index != outerIndex else { return false }
            let candidate = quads[index]
            let candidateArea = abs(polygonArea(candidate.points))
            let candidateWidth = (candidate.topLength + candidate.bottomLength) / 2
            let candidateHeight = (candidate.leftLength + candidate.rightLength) / 2
            let printedBorderShape = (0.55...0.85).contains(candidate.rectifiedAspectRatio)
                && candidateWidth >= outerWidth * 0.65
                && candidateHeight >= outerHeight * 0.65
            return candidateArea < outerArea * 0.985
                && candidateArea > outerArea * 0.15
                && printedBorderShape
                && hasBalancedOppositeEdges(candidate)
                && contains(outer, candidate.points)
        }).map { quads[$0] }

        let broadQuads = makeQuads(from: broadRequest.results, minimumConfidence: 0.08)
        let artWindow = broadQuads.first { candidate in
            let candidateArea = abs(polygonArea(candidate.points))
            let candidateAspect = candidate.rectifiedAspectRatio
            let outerCenter = midpoint(outer.points)
            let candidateCenter = midpoint(candidate.points)
            let cardWidth = max(outer.topLength, outer.bottomLength)
            let cardHeight = max(outer.leftLength, outer.rightLength)
            let candidateWidth = (candidate.topLength + candidate.bottomLength) / 2
            let candidateHeight = (candidate.leftLength + candidate.rightLength) / 2
            let portraitArtWindow = (0.58...0.85).contains(candidateAspect)
            let landscapeArtWindow = (0.90...1.30).contains(candidateAspect)
            let heightIsGradeable = portraitArtWindow
                ? (cardHeight * 0.88...cardHeight * 0.98).contains(candidateHeight)
                : candidateHeight <= cardHeight * 0.75
            return candidateArea < outerArea * 0.96
                && candidateArea > outerArea * 0.12
                // A gradeable art window may be landscape, but an unusually
                // shallow interior field is more often a content region than
                // a stable printed frame. Staying conservative here makes the
                // result decline instead of reporting a precise-looking ratio
                // from a light region with no reliable border reference.
                && (portraitArtWindow || landscapeArtWindow)
                && candidateWidth >= cardWidth * 0.55
                && candidateHeight >= cardHeight * 0.25
                && heightIsGradeable
                && abs(candidateCenter.x - outerCenter.x) <= cardWidth * 0.10
                && candidateCenter.y <= outerCenter.y + cardHeight * 0.05
                && hasBalancedOppositeEdges(candidate)
                // A text box or a diagonal artwork detail can be rectangle-
                // shaped without being a frame. A real printed frame remains
                // close to a pair of parallel long/short edges in this macro
                // corpus; reject proposals whose opposite sides visibly fan.
                && parallelismResidual(for: candidate) <= 2.5
                && contains(outer, candidate.points)
        }
        let inner = artWindow ?? printedInner
        let innerReference: CardCenteringInnerReference = artWindow != nil
            ? .artWindow
            : (printedInner != nil ? .printedBorder : .none)
        let innerSupport = inner == nil ? 0 : 0.80
#if DEBUG
        let candidateLedger = Self.activeCandidateLedger
            ?? CandidateLedger(workingWidth: Int(Double(width) * ledgerScaleX), workingHeight: Int(Double(height) * ledgerScaleY))
        func scaledLedgerPoint(_ point: CardCenteringPoint) -> CardCenteringPoint {
            CardCenteringPoint(
                x: point.x * ledgerScaleX,
                y: point.y * ledgerScaleY
            )
        }

        func ledgerVisionEdge(_ quad: CardCenteringQuad, side: Side) -> [CardCenteringPoint] {
            switch side {
            case .left:
                return [scaledLedgerPoint(quad.topLeft), scaledLedgerPoint(quad.bottomLeft)]
            case .right:
                return [scaledLedgerPoint(quad.topRight), scaledLedgerPoint(quad.bottomRight)]
            case .top:
                return [scaledLedgerPoint(quad.topLeft), scaledLedgerPoint(quad.topRight)]
            case .bottom:
                return [scaledLedgerPoint(quad.bottomLeft), scaledLedgerPoint(quad.bottomRight)]
            }
        }

        func appendVisionCandidate(
            _ quad: CardCenteringQuad,
            family: String,
            source: String,
            role: String,
            selected: Bool,
            rejectionReason: String?
        ) {
            for side in Side.allCases {
                candidateLedger.append(
                    family: family,
                    side: String(describing: side),
                    source: source,
                    workingGeometry: ledgerVisionEdge(quad, side: side),
                    support: 1,
                    transitionStrength: 1,
                    proposedSemanticRole: role,
                    selected: selected,
                    rejectionReason: rejectionReason
                )
            }
        }

        for (index, quad) in quads.enumerated() {
            let selected = index == outerIndex
            let role: String
            if selected {
                role = "physical_outer_candidate"
            } else if selectedPair?.outerIndex == index {
                role = "sleeve_outer_candidate"
            } else {
                role = "unknown_outer_candidate"
            }
            appendVisionCandidate(
                quad,
                family: "outer",
                source: "vision.card_rectangle",
                role: role,
                selected: selected,
                rejectionReason: selected ? nil : "not_selected_by_current_outer_selector"
            )
            guard index != outerIndex else { continue }
            let isPrintedInner = printedInner == quad
            appendVisionCandidate(
                quad,
                family: "inner",
                source: "vision.card_rectangle",
                role: isPrintedInner ? "printed_border" : "unknown_inner_candidate",
                selected: isPrintedInner,
                rejectionReason: isPrintedInner ? nil : "not_selected_by_current_printed_inner_selector"
            )
        }

        for quad in broadQuads {
            let selected = artWindow == quad
            appendVisionCandidate(
                quad,
                family: "inner",
                source: "vision.broad_rectangle",
                role: selected ? "art_window" : "unknown_inner_candidate",
                selected: selected,
                rejectionReason: selected ? nil : "not_selected_by_current_art_window_selector"
            )
        }
#endif

        func skew(for quad: CardCenteringQuad) -> Double {
            let topAngle = atan2(quad.topRight.y - quad.topLeft.y, quad.topRight.x - quad.topLeft.x)
            let bottomAngle = atan2(quad.bottomRight.y - quad.bottomLeft.y, quad.bottomRight.x - quad.bottomLeft.x)
            return lineOrientationAverage([topAngle, bottomAngle]) * 180 / .pi
        }
        let topAngle = atan2(outer.topRight.y - outer.topLeft.y, outer.topRight.x - outer.topLeft.x)
        let bottomAngle = atan2(outer.bottomRight.y - outer.bottomLeft.y, outer.bottomRight.x - outer.bottomLeft.x)
        let leftAngle = atan2(outer.bottomLeft.y - outer.topLeft.y, outer.bottomLeft.x - outer.topLeft.x)
        let rightAngle = atan2(outer.bottomRight.y - outer.topRight.y, outer.bottomRight.x - outer.topRight.x)
        // Treat edge directions as unoriented lines and average all four. The
        // side directions are shifted by 90° before averaging, so roll is not
        // inferred from only the two least-shadowed edges.
        // Roll is the common direction of the two long card edges. The side
        // edges may legitimately converge under perspective; averaging their
        // directions into roll would attenuate or exaggerate the correction.
        // If nested observations caused the selected physical quad to be an
        // inner printed rectangle, its top edge can be partially obscured and
        // its roll estimate can be biased. The largest rectangle from the
        // card-focused request is the enclosing physical silhouette (or its
        // sleeve); both share the same in-plane roll, so use that stable
        // long-edge estimate for automatic presentation correction.
        let skew = skew(for: quads[0])
        // A photographed card may have mild perspective: the side edges can
        // converge by a few degrees even though the homography is stable. Keep
        // the strict top/bottom agreement for roll, while allowing that normal
        // perspective before declaring the outline unusable. A much larger
        // convergence is still surfaced by the perspective synthetic case.
        let topParallelTolerance = 1.0 * .pi / 180
        let sideParallelTolerance = 4.0 * .pi / 180
        let edgesAreParallel = angleDifference180(topAngle, bottomAngle) <= topParallelTolerance
            && angleDifference180(leftAngle, rightAngle) <= sideParallelTolerance

        return CardOutline(
            edges: outer.projectedEdges,
            quad: outer,
            innerQuad: inner,
            innerReference: innerReference,
            innerSupport: innerSupport,
            skewDegrees: skew,
            edgesAreParallel: edgesAreParallel,
            edgeSupport: selectedPair == nil ? 1 : 0.95,
            sleeveAmbiguity: sleeveAmbiguity,
            usesVision: true
        )
    }

    private static func midpoint(_ points: [CardCenteringPoint]) -> CardCenteringPoint {
        let count = Double(max(points.count, 1))
        return CardCenteringPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }

    private static func visionPoint(
        _ point: CGPoint,
        targetWidth: Int,
        targetHeight: Int
    ) -> CardCenteringPoint {
        CardCenteringPoint(
            x: Double(point.x) * Double(targetWidth),
            y: (1 - Double(point.y)) * Double(targetHeight)
        )
    }

    private static func polygonArea(_ points: [CardCenteringPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        return points.indices.reduce(0) { result, index in
            let next = points[(index + 1) % points.count]
            return result + points[index].x * next.y - next.x * points[index].y
        } / 2
    }

    private static func contains(_ outer: CardCenteringQuad, _ points: [CardCenteringPoint]) -> Bool {
        let outerPoints = outer.points
        let signs = outerPoints.indices.map { index -> Double in
            let next = outerPoints[(index + 1) % outerPoints.count]
            return cross(outerPoints[index], next, points[0])
        }
        guard let first = signs.first, abs(first) > .ulpOfOne else { return false }
        return points.allSatisfy { point in
            outerPoints.indices.allSatisfy { index in
                let next = outerPoints[(index + 1) % outerPoints.count]
                let value = cross(outerPoints[index], next, point)
                return value * first >= -1
            }
        }
    }

    private static func cross(_ first: CardCenteringPoint, _ second: CardCenteringPoint, _ point: CardCenteringPoint) -> Double {
        (second.x - first.x) * (point.y - first.y)
            - (second.y - first.y) * (point.x - first.x)
    }

    private static func angleDifference180(_ first: Double, _ second: Double) -> Double {
        var difference = (first - second).truncatingRemainder(dividingBy: .pi)
        if difference > .pi / 2 { difference -= .pi }
        if difference < -.pi / 2 { difference += .pi }
        return abs(difference)
    }

    private static func lineOrientationAverage(_ angles: [Double]) -> Double {
        guard !angles.isEmpty else { return 0 }
        let doubled = angles.reduce(into: (sine: 0.0, cosine: 0.0)) { result, angle in
            result.sine += sin(2 * angle)
            result.cosine += cos(2 * angle)
        }
        var average = 0.5 * atan2(doubled.sine, doubled.cosine)
        if average > .pi / 2 { average -= .pi }
        if average < -.pi / 2 { average += .pi }
        return average
    }

    private enum ProfileSide: CaseIterable {
        case left, top, right, bottom
    }

    private struct GeometryLine {
        let a: Double
        let b: Double
        let c: Double
    }

    private struct InnerProfileResult {
        let quad: CardCenteringQuad
        let support: Double
    }

    /// Finds a printed reference by following a coherent transition inward
    /// from each already-fitted card edge. The long-edge median rejects foil
    /// highlights and text, while the quad interpolation keeps a perspective
    /// edge aligned during sampling.
    private static func innerQuadFromProfiles(
        pixels: [Pixel],
        width: Int,
        height: Int,
        outer: CardCenteringQuad,
        distanceScale: Double,
        minimumPortraitWidthCoverage: Double = 0.85,
        minimumPortraitHeightCoverage: Double = 0.88,
        ledgerScaleX: Double = 1,
        ledgerScaleY: Double = 1
    ) -> InnerProfileResult? {
        let cardWidth = max(outer.topLength + outer.bottomLength, 2) / 2
        let cardHeight = max(outer.leftLength + outer.rightLength, 2) / 2
        func recordFailure(
            _ side: ProfileSide?,
            _ reason: String,
            innerWidthWorkingPx: Double? = nil,
            innerHeightWorkingPx: Double? = nil,
            innerAspect: Double? = nil,
            profileSupport: Double? = nil
        ) {
#if DEBUG
            profileFailureDiagnosticSink?(CardCenteringProfileFailureDiagnostic(
                side: side.map { String(describing: $0) },
                reason: reason,
                workingWidth: width,
                workingHeight: height,
                cardWidthWorkingPx: cardWidth,
                cardHeightWorkingPx: cardHeight,
                innerWidthWorkingPx: innerWidthWorkingPx,
                innerHeightWorkingPx: innerHeightWorkingPx,
                innerAspect: innerAspect,
                profileSupport: profileSupport
            ))
#endif
        }
        guard cardWidth > 20, cardHeight > 20 else {
            recordFailure(nil, "card_geometry_too_small")
            return nil
        }

        // All four sides use the same card-normalized grid. This removes the
        // width-vs-height sampling pitch change that a quarter-turn used to
        // introduce, while keeping the original image pixels untouched.
        let normalizedDepthStart = 0.004
        let normalizedDepthEnd = 0.20
        let depthSampleCount = 320
        let normalizedDepths = (0..<depthSampleCount).map { index in
            normalizedDepthStart
                + (normalizedDepthEnd - normalizedDepthStart)
                * Double(index) / Double(max(depthSampleCount - 1, 1))
        }
        let radiusNormalized = 0.0015

        func edgeEndpoints(_ side: ProfileSide) -> (CardCenteringPoint, CardCenteringPoint) {
            switch side {
            case .left: (outer.topLeft, outer.bottomLeft)
            case .top: (outer.topLeft, outer.topRight)
            case .right: (outer.topRight, outer.bottomRight)
            case .bottom: (outer.bottomLeft, outer.bottomRight)
            }
        }

        func edgePoint(_ side: ProfileSide, progress: Double) -> CardCenteringPoint {
            let endpoints = edgeEndpoints(side)
            return interpolate(endpoints.0, endpoints.1, amount: progress)
        }

        func inwardNormal(_ side: ProfileSide) -> (x: Double, y: Double) {
            let endpoints = edgeEndpoints(side)
            let tangentX = endpoints.1.x - endpoints.0.x
            let tangentY = endpoints.1.y - endpoints.0.y
            let length = max(hypot(tangentX, tangentY), .ulpOfOne)
            var normalX = -tangentY / length
            var normalY = tangentX / length
            let centre = outer.points.reduce(into: CardCenteringPoint(x: 0, y: 0)) { result, point in
                result.x += point.x / 4
                result.y += point.y / 4
            }
            let midpoint = edgePoint(side, progress: 0.5)
            if (centre.x - midpoint.x) * normalX + (centre.y - midpoint.y) * normalY < 0 {
                normalX = -normalX
                normalY = -normalY
            }
            return (normalX, normalY)
        }

        func point(side: ProfileSide, progress: Double, normalizedDepth: Double) -> CardCenteringPoint {
            let origin = edgePoint(side, progress: progress)
            let normal = inwardNormal(side)
            let axisLength = side == .left || side == .right ? cardWidth : cardHeight
            let distance = normalizedDepth * axisLength
            return CardCenteringPoint(
                x: origin.x + normal.x * distance,
                y: origin.y + normal.y * distance
            )
        }

        func profile(for side: ProfileSide) -> (depth: Double, score: Double, support: Double)? {
            let samples = 240
            let maxIndex = depthSampleCount - 1
            let progressValues = (0..<samples).map {
                0.12 + 0.76 * Double($0) / Double(max(samples - 1, 1))
            }

            // The derivative width is expressed in card-normalized units, so
            // there is no absolute-pixel radius switch at a scale boundary.
            let radiusPixels = radiusNormalized
                * (side == .left || side == .right ? cardWidth : cardHeight)
            var scores = [Double](repeating: 0, count: depthSampleCount)
            var supports = [Double](repeating: 0, count: depthSampleCount)
            for index in normalizedDepths.indices {
                let depth = normalizedDepths[index]
                let previousDepth = max(normalizedDepthStart, depth - radiusNormalized)
                let currentDepth = min(normalizedDepthEnd, depth + radiusNormalized)
                var values: [Double] = []
                values.reserveCapacity(samples)
                for sampleIndex in 0..<samples {
                    let progress = progressValues[sampleIndex]
                    let previous = samplePixel(
                        pixels,
                        width: width,
                        height: height,
                        at: point(side: side, progress: progress, normalizedDepth: previousDepth)
                    )
                    let current = samplePixel(
                        pixels,
                        width: width,
                        height: height,
                        at: point(side: side, progress: progress, normalizedDepth: currentDepth)
                    )
                    values.append(Double(distance(previous, current)) * distanceScale)
                }
                let score = values.isEmpty ? 0 : median(values)
                scores[index] = score
                let supportThreshold = max(1.5, score * 0.75)
                supports[index] = Double(values.filter { $0 >= supportThreshold }.count) / Double(samples)
            }

            let valid = scores.indices.filter { normalizedDepths[$0] >= 0.02 }
            guard !valid.isEmpty else {
                recordFailure(side, "no_valid_depths")
                return nil
            }
            let baseline = median(valid.map { scores[$0] })
            let mad = median(valid.map { abs(scores[$0] - baseline) })
            // The loudest transition is often a banner or a text row deeper
            // inside the card. Keep a permissive set of local maxima, then
            // prefer the earliest member of the strongest shallow cluster.
            let threshold = max(baseline + max(0.75, mad), 2.5)
            let candidates = valid.filter { index in
                scores[index] >= threshold
                    && scores[index] >= scores[max(valid.first ?? index, index - 1)]
                    && scores[index] >= scores[min(valid.last ?? index, index + 1)]
                    && supports[index] >= 0.24
            }
            let shallow = candidates.filter {
                normalizedDepths[$0] >= 0.02 && normalizedDepths[$0] <= 0.12
            }
            guard let maximumScore = shallow.map({ scores[$0] }).max(), maximumScore > 0 else {
                recordFailure(side, "no_shallow_candidate")
                return nil
            }
            let strongEnough = shallow.filter { scores[$0] >= maximumScore * 0.72 }
            guard let selected = strongEnough.min() else {
                recordFailure(side, "no_strong_candidate")
                return nil
            }

            // A local quadratic fit gives a small sub-sample correction without
            // changing which evidence peak won. Convert its bounded index offset
            // back through the fixed normalized grid.
            let refinedIndex: Double
            if selected > valid.first!, selected < valid.last! {
                let previousScore = scores[selected - 1]
                let currentScore = scores[selected]
                let nextScore = scores[selected + 1]
                let curvature = previousScore - 2 * currentScore + nextScore
                if abs(curvature) > 1e-9 {
                    let rawOffset = 0.5 * (previousScore - nextScore) / curvature
                    refinedIndex = Double(selected)
                        + Swift.min(0.5, Swift.max(-0.5, rawOffset))
                } else {
                    refinedIndex = Double(selected)
                }
            } else {
                refinedIndex = Double(selected)
            }
            let gridStep = (normalizedDepthEnd - normalizedDepthStart)
                / Double(max(depthSampleCount - 1, 1))
            let refinedDepth = normalizedDepthStart + refinedIndex * gridStep
#if DEBUG
            func diagnosticCandidate(_ index: Int) -> CardCenteringProfileCandidateDiagnostic {
                CardCenteringProfileCandidateDiagnostic(
                    normalizedDepth: normalizedDepths[index],
                    score: scores[index],
                    support: supports[index]
                )
            }
            let diagnostic = CardCenteringProfileDiagnostic(
                side: String(describing: side),
                workingWidth: width,
                workingHeight: height,
                cardWidthWorkingPx: cardWidth,
                cardHeightWorkingPx: cardHeight,
                sampleRadiusPixels: radiusPixels,
                sampleRadiusNormalized: radiusNormalized,
                normalizedDepthStart: normalizedDepthStart,
                normalizedDepthEnd: normalizedDepthEnd,
                samplesAlongEdge: samples,
                maxIndex: maxIndex,
                normalizedDepths: normalizedDepths,
                scores: scores,
                supports: supports,
                baseline: baseline,
                mad: mad,
                threshold: threshold,
                thresholdCandidates: candidates.map(diagnosticCandidate),
                shallowCandidates: shallow.map(diagnosticCandidate),
                selectedIndex: selected,
                selectedNormalizedDepthBeforeRefinement: normalizedDepths[selected],
                selectedNormalizedDepthAfterRefinement: refinedDepth,
                outerQuadWorking: outer,
                distanceScale: distanceScale
            )
            profileDiagnosticSink?(diagnostic)
            let candidateLedger = Self.activeCandidateLedger
                ?? CandidateLedger(
                    workingWidth: Int(Double(width) * ledgerScaleX),
                    workingHeight: Int(Double(height) * ledgerScaleY)
                )
            for index in candidates {
                let selectedCandidate = index == selected
                let rejectionReason: String?
                if selectedCandidate {
                    rejectionReason = nil
                } else if !shallow.contains(index) {
                    rejectionReason = "outside_gradeable_shallow_band"
                } else if scores[index] < maximumScore * 0.72 {
                    rejectionReason = "below_strongest_shallow_margin"
                } else {
                    rejectionReason = "not_selected_by_current_profile_selector"
                }
                let geometry = [
                    point(side: side, progress: 0.15, normalizedDepth: normalizedDepths[index]),
                    point(side: side, progress: 0.85, normalizedDepth: normalizedDepths[index])
                ].map {
                    CardCenteringPoint(
                        x: $0.x * ledgerScaleX,
                        y: $0.y * ledgerScaleY
                    )
                }
                candidateLedger.append(
                    family: "inner",
                    side: String(describing: side),
                    source: "profile.normalized_gradient",
                    workingGeometry: geometry,
                    support: supports[index],
                    transitionStrength: scores[index],
                    baseline: baseline,
                    mad: mad,
                    threshold: threshold,
                    proposedSemanticRole: "untyped_inner_reference",
                    selected: selectedCandidate,
                    rejectionReason: rejectionReason
                )
            }
#endif
            return (refinedDepth, scores[selected], supports[selected])
        }

        var depths: [ProfileSide: Double] = [:]
        var supports: [ProfileSide: Double] = [:]
        for side in ProfileSide.allCases {
            guard let result = profile(for: side) else { return nil }
            depths[side] = result.depth
            supports[side] = result.support
        }

        let edgeProgress = stride(from: 0.15, through: 0.85, by: 0.05).map { Double($0) }
        func line(for side: ProfileSide) -> GeometryLine {
            let normalizedDepth = depths[side]!
            let points = edgeProgress.map { progress in
                point(side: side, progress: progress, normalizedDepth: normalizedDepth)
            }
            return fitGeometryLine(points)
        }
        let lines = ProfileSide.allCases.reduce(into: [ProfileSide: GeometryLine]()) { result, side in
            result[side] = line(for: side)
        }
        guard let top = lines[.top], let left = lines[.left],
              let right = lines[.right], let bottom = lines[.bottom],
              let topLeft = intersection(top, left),
              let topRight = intersection(top, right),
              let bottomRight = intersection(bottom, right),
              let bottomLeft = intersection(bottom, left) else {
            recordFailure(nil, "line_intersection")
            return nil
        }

        let inner = CardCenteringQuad(
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        )
        let border = outer.borderDistances(to: inner)
        guard [border.left, border.top, border.right, border.bottom].allSatisfy({ $0 > 0 }) else {
            recordFailure(nil, "inner_outside_outer")
            return nil
        }
        let aspect = inner.rectifiedAspectRatio
        // A quarter-turn makes the standard 5:7 card landscape (7:5 ≈ 1.40).
        // The previous upper bound admitted shallow landscape artwork windows
        // but rejected the same full-frame printed reference after a 90° turn,
        // forcing the scalar axis-aligned fallback and breaking INV-5.
        let portraitReference = (0.60...0.85).contains(aspect)
        let landscapeReference = (1.00...1.55).contains(aspect)
        guard portraitReference || landscapeReference else {
            recordFailure(nil, "inner_aspect_out_of_range")
            return nil
        }
        let innerWidth = (inner.topLength + inner.bottomLength) / 2
        let innerHeight = (inner.leftLength + inner.rightLength) / 2
        let hasGradeableCoverage: Bool
        if portraitReference {
            // A portrait art/printed reference should track the card's long
            // frame almost to the bottom. A shorter light field is a content
            // mask, not a stable centering reference.
            hasGradeableCoverage = innerWidth >= cardWidth * minimumPortraitWidthCoverage
                && innerHeight >= cardHeight * minimumPortraitHeightCoverage
        } else {
            hasGradeableCoverage = innerWidth >= cardWidth * 0.55
                && innerHeight >= cardHeight * 0.25
        }
        guard hasGradeableCoverage else {
            recordFailure(
                nil,
                "inner_coverage_too_small",
                innerWidthWorkingPx: innerWidth,
                innerHeightWorkingPx: innerHeight,
                innerAspect: aspect
            )
            return nil
        }
        let support = ProfileSide.allCases.compactMap { supports[$0] }.reduce(0, +) / 4
        guard support >= 0.30,
              ProfileSide.allCases.allSatisfy({ supports[$0, default: 0] >= 0.24 }) else {
            recordFailure(nil, "profile_support_too_low", profileSupport: support)
            return nil
        }
        return InnerProfileResult(quad: inner, support: support)
    }

    private static func interpolate(
        _ first: CardCenteringPoint,
        _ second: CardCenteringPoint,
        amount: Double
    ) -> CardCenteringPoint {
        CardCenteringPoint(
            x: first.x + (second.x - first.x) * amount,
            y: first.y + (second.y - first.y) * amount
        )
    }

    private static func samplePixel(
        _ pixels: [Pixel],
        width: Int,
        height: Int,
        at point: CardCenteringPoint
    ) -> Pixel {
        let x = min(max(point.x, 0), Double(width - 1))
        let y = min(max(point.y, 0), Double(height - 1))
        let lowerX = min(max(Int(x.rounded(.down)), 0), width - 1)
        let lowerY = min(max(Int(y.rounded(.down)), 0), height - 1)
        let upperX = min(lowerX + 1, width - 1)
        let upperY = min(lowerY + 1, height - 1)
        let xAmount = Float(x - Double(lowerX))
        let yAmount = Float(y - Double(lowerY))
        func mix(_ first: Pixel, _ second: Pixel, _ amount: Float) -> Pixel {
            Pixel(
                l: first.l + (second.l - first.l) * amount,
                a: first.a + (second.a - first.a) * amount,
                b: first.b + (second.b - first.b) * amount
            )
        }
        let top = mix(pixels[lowerY * width + lowerX], pixels[lowerY * width + upperX], xAmount)
        let bottom = mix(pixels[upperY * width + lowerX], pixels[upperY * width + upperX], xAmount)
        return mix(top, bottom, yAmount)
    }

    private static func fitGeometryLine(_ points: [CardCenteringPoint]) -> GeometryLine {
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)
        let xx = points.reduce(0) { $0 + pow($1.x - meanX, 2) }
        let yy = points.reduce(0) { $0 + pow($1.y - meanY, 2) }
        let xy = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        var a = -sin(angle)
        var b = cos(angle)
        if a < -1e-12 || (abs(a) <= 1e-12 && b < 0) {
            a = -a
            b = -b
        }
        return GeometryLine(a: a, b: b, c: a * meanX + b * meanY)
    }

    private static func intersection(_ first: GeometryLine, _ second: GeometryLine) -> CardCenteringPoint? {
        let determinant = first.a * second.b - second.a * first.b
        guard abs(determinant) > 1e-10 else { return nil }
        return CardCenteringPoint(
            x: (first.c * second.b - second.c * first.b) / determinant,
            y: (first.a * second.c - second.a * first.c) / determinant
        )
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
        guard (0.50...2.00).contains(aspect) else { return nil }

        // Both vertical edges are fitted and averaged. One alone can be dragged
        // by a shadow down one side; when the two disagree, neither supports a
        // trustworthy corrective rotation. Keep the outline for measurement,
        // but carry that evidence to the result instead of inferring skew.
        let inset = Swift.max(2, Int((Double(boxHeight) * 0.1).rounded()))
        let fitRows = (rows.lower + inset)...(rows.upper - inset)
        guard fitRows.lowerBound < fitRows.upperBound else { return nil }

        let leftSlope = slope(of: firstForeground, over: fitRows)
        let rightSlope = slope(of: lastForeground, over: fitRows)
        let edgesAreParallel: Bool
        if let leftSlope, let rightSlope {
            edgesAreParallel = abs(leftSlope - rightSlope) <= 0.08
        } else {
            edgesAreParallel = false
        }
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
            quad: .axisAligned(CardCenteringEdges(
                left: columns.lower,
                top: rows.lower,
                right: columns.upper,
                bottom: rows.upper
            )),
            innerQuad: nil,
            innerReference: .none,
            innerSupport: 0,
            skewDegrees: skew,
            edgesAreParallel: edgesAreParallel,
            edgeSupport: 0.5,
            sleeveAmbiguity: 0,
            usesVision: false
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
