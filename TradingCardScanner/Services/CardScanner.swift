import Combine
import AVFoundation
import Foundation
import ImageIO
import Vision

/// The scan region is defined once in Vision's normalized coordinates after the
/// camera frame is oriented `.right`: portrait, bottom-left origin.
///
/// AVFoundation preview conversion expects a metadata-output rect in the native
/// unrotated landscape frame with a top-left origin, so derive that rectangle
/// explicitly instead of sharing raw numbers between incompatible spaces.
enum CardFramingRegion {
    /// A 2.5:3.5 card fitted inside the portrait-oriented 16:9 camera image.
    /// Normalized Vision coordinates are not square: one unit of Y spans 16/9
    /// as many source pixels as one unit of X. Applying the card ratio directly
    /// to normalized values produces a visibly incorrect ~0.40 aspect ratio.
    static let sourceImageAspectRatio: CGFloat = 9.0 / 16.0
    static let physicalCardAspectRatio: CGFloat = 2.5 / 3.5
    private static let normalizedCardWidth: CGFloat = 0.72
    private static let normalizedCardHeight = normalizedCardWidth
        * sourceImageAspectRatio / physicalCardAspectRatio

    static let cardVisionRect = CGRect(
        x: (1 - normalizedCardWidth) / 2,
        y: (1 - normalizedCardHeight) / 2,
        width: normalizedCardWidth,
        height: normalizedCardHeight
    )

    /// Insets are card-relative so every overlay stays aligned when the guide is
    /// resized. Vision uses a bottom-left origin: footer is low Y, title high Y.
    static let visionRect = cardRelativeRect(x: 0.025, y: 0.015, width: 0.95, height: 0.15)
    static let titleVisionRect = cardRelativeRect(x: 0.035, y: 0.79, width: 0.93, height: 0.16)

    static let fullFrameRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    private static func cardRelativeRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: cardVisionRect.minX + x * cardVisionRect.width,
            y: cardVisionRect.minY + y * cardVisionRect.height,
            width: width * cardVisionRect.width,
            height: height * cardVisionRect.height
        )
    }

    static func metadataRect(rotationAngle: CGFloat) -> CGRect {
        metadataRect(fromVisionRect: visionRect, rotationAngle: rotationAngle)
    }

    /// Vision normalizes observation bounding boxes against the request's
    /// `regionOfInterest`, so a box must be scaled and offset back into full-frame
    /// coordinates before any metadata/preview conversion. With a full-frame ROI this
    /// is the identity; with the real scan band it is not remotely close.
    static func fullFrameVisionRect(fromObservationBoundingBox box: CGRect, in roi: CGRect) -> CGRect {
        CGRect(
            x: roi.minX + box.minX * roi.width,
            y: roi.minY + box.minY * roi.height,
            width: box.width * roi.width,
            height: box.height * roi.height
        )
    }

    /// Converts a Vision rect (bottom-left origin, in the *upright* image the
    /// camera frame becomes once rotated) into an AVFoundation metadata-output
    /// rect (top-left origin, in the sensor's native unrotated landscape frame).
    ///
    /// `rotationAngle` is the `AVCaptureConnection.videoRotationAngle` currently
    /// applied — the clockwise rotation that turns the sensor image upright. The
    /// transform is genuinely angle-dependent: metadata space stays sensor-relative
    /// no matter how the window is oriented, so this cannot be collapsed into one
    /// formula. Anything other than a quarter turn is treated as 0.
    ///
    /// Derivation, for a point in the upright top-left space `(ux, uy)` where
    /// `ux = visionX` and `uy = 1 - visionY`: `upright = rotate(sensor, angle)`,
    /// so `sensor = rotate(upright, -angle)`. The four cases below are that
    /// inverse rotation written out, with rect bounds taken from whichever corner
    /// becomes the minimum once the axes reverse.
    static func metadataRect(fromVisionRect rect: CGRect, rotationAngle: CGFloat) -> CGRect {
        switch normalizedRotationAngle(rotationAngle) {
        case 90:
            // The portrait case, and the only one an iPhone ever takes. This is the
            // transform the scanner shipped with, unchanged:
            //   metadataX = 1 - visionY, metadataY = 1 - visionX
            // Rect bounds use max values because both axes reverse direction.
            //
            // IMPORTANT FIELD-TEST CHECK:
            // Apple's orientation wording is easy to interpret in either rotation
            // direction. If the on-device green band/recognized-text boxes are
            // mirrored to the wrong vertical end of the card, the alternate
            // transform is the 270 case below.
            return CGRect(
                x: 1 - rect.maxY,
                y: 1 - rect.maxX,
                width: rect.height,
                height: rect.width
            )
        case 180:
            return CGRect(
                x: 1 - rect.maxX,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
        case 270:
            return CGRect(
                x: rect.minY,
                y: rect.minX,
                width: rect.height,
                height: rect.width
            )
        default:
            return CGRect(
                x: rect.minX,
                y: 1 - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
    }

    /// Snaps to the nearest quarter turn in `[0, 360)`. Only quarter turns are ever
    /// reported, but the value arrives as a `CGFloat` and exact equality on a float
    /// is a bad thing to build a coordinate transform on.
    static func normalizedRotationAngle(_ angle: CGFloat) -> Int {
        let quarters = Int((angle / 90).rounded())
        return ((quarters % 4) + 4) % 4 * 90
    }

    /// The Vision orientation that turns a sensor-space frame upright for the
    /// same rotation `rotationAngle` describes. `CGImagePropertyOrientation` names
    /// where the original first row sits in the displayed image, so a 90° clockwise
    /// rotation is `.right`.
    static func imageOrientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch normalizedRotationAngle(angle) {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Vision reports sizes in the upright image, so the sensor's landscape
    /// dimensions are swapped for the quarter turns and kept for the half turns.
    static func visionSourceSize(
        forRotationAngle angle: CGFloat,
        sensorWidth: Int,
        sensorHeight: Int
    ) -> CGSize {
        switch normalizedRotationAngle(angle) {
        case 90, 270:
            return CGSize(width: sensorHeight, height: sensorWidth)
        default:
            return CGSize(width: sensorWidth, height: sensorHeight)
        }
    }
}

/// Experimental calibration values for the one piece of scanner evidence that
/// may authorize a duplicate question. These values are deliberately kept in
/// one place so device tuning cannot accidentally change the trust boundary:
/// only positively observed motion can produce a reset proof.
struct SpatialTrackingConfiguration: Equatable, Sendable {
    let trackingRate: Double
    let seedInsetFraction: CGFloat
    let minimumConfidence: Float
    let requiredExitObservations: Int
    let maximumGuideOverlap: CGFloat

    static let experimental = SpatialTrackingConfiguration(
        trackingRate: 8,
        seedInsetFraction: 0.06,
        minimumConfidence: 0.50,
        requiredExitObservations: 2,
        maximumGuideOverlap: 0.25
    )

    init(
        trackingRate: Double = 8,
        seedInsetFraction: CGFloat = 0.06,
        minimumConfidence: Float = 0.50,
        requiredExitObservations: Int = 2,
        maximumGuideOverlap: CGFloat = 0.25
    ) {
        self.trackingRate = max(1, trackingRate)
        self.seedInsetFraction = min(max(0, seedInsetFraction), 0.49)
        self.minimumConfidence = min(max(0, minimumConfidence), 1)
        self.requiredExitObservations = max(1, requiredExitObservations)
        self.maximumGuideOverlap = min(max(0, maximumGuideOverlap), 1)
    }

    var seedRect: CGRect {
        let guide = CardFramingRegion.cardVisionRect
        return guide.insetBy(
            dx: guide.width * seedInsetFraction,
            dy: guide.height * seedInsetFraction
        )
    }

    func isQualifyingExit(box: CGRect, confidence: Float) -> Bool {
        guard confidence >= minimumConfidence, box.width > 0, box.height > 0 else {
            return false
        }

        let center = CGPoint(x: box.midX, y: box.midY)
        guard !CardFramingRegion.cardVisionRect.contains(center) else { return false }

        let intersection = box.intersection(CardFramingRegion.cardVisionRect)
        let intersectionArea = intersection.isNull
            ? 0
            : intersection.width * intersection.height
        let trackedArea = box.width * box.height
        return intersectionArea / trackedArea <= maximumGuideOverlap
    }
}

/// Strict spatial evidence accumulator. OCR loss, tracker loss, timeouts, and
/// empty-footer observations never call this type, so they cannot become a
/// `SpatialResetProof` by accident.
struct SpatialExitObservationAccumulator: Equatable, Sendable {
    let configuration: SpatialTrackingConfiguration
    private(set) var consecutiveQualifiedObservations = 0

    init(configuration: SpatialTrackingConfiguration = .experimental) {
        self.configuration = configuration
    }

    /// Returns true exactly when the configured run is completed. A
    /// non-qualifying observation breaks the run, and observations after the
    /// completion do not create another event if a caller has not yet torn down
    /// its tracker.
    mutating func observe(box: CGRect, confidence: Float) -> Bool {
        guard configuration.isQualifyingExit(box: box, confidence: confidence) else {
            consecutiveQualifiedObservations = 0
            return false
        }
        consecutiveQualifiedObservations += 1
        return consecutiveQualifiedObservations == configuration.requiredExitObservations
    }

    mutating func reset() {
        consecutiveQualifiedObservations = 0
    }
}

/// A lost tracker is a hard lineage boundary. OCR may continue to identify the
/// same canonical card, but it cannot recreate the presentation that was lost.
/// A different suppression key is allowed to begin a new encounter and clears
/// the old marker.
struct SpatialTrackerSeedGate: Equatable, Sendable {
    private(set) var lostIdentity: ScanSuppressionKey?

    mutating func markLost(_ subject: ScanSubject?) {
        guard let subject else { return }
        lostIdentity = subject.suppressionKey
    }

    mutating func canSeed(_ subject: ScanSubject) -> Bool {
        guard lostIdentity != subject.suppressionKey else { return false }
        lostIdentity = nil
        return true
    }

    /// A held-card tap is an explicit authorization for one fresh presentation.
    /// It does not claim that the old tracker exited; it only clears the lost
    /// marker for the expected next seed.
    mutating func allowAuthorizedReseed(for key: ScanSuppressionKey) {
        guard lostIdentity == key else { return }
        lostIdentity = nil
    }
}

/// The camera output may arrive faster or slower than either Vision workload.
/// Keeping the last-run timestamps here makes the 8 Hz tracker and 0.24 s OCR
/// independently fake-clockable. Slab-label cadence is decided by
/// `SlabLabelSchedule` on OCR frames.
enum ScanCadenceKind: Equatable, Sendable {
    case tracking
    case ocr
    case label
}

struct ScanCadenceScheduler: Equatable, Sendable {
    let trackingInterval: CFAbsoluteTime
    let ocrInterval: CFAbsoluteTime
    let labelInterval: CFAbsoluteTime
    private(set) var lastTrackingAt: CFAbsoluteTime?
    private(set) var lastOCRAt: CFAbsoluteTime?
    private(set) var lastLabelAt: CFAbsoluteTime?

    init(
        trackingRate: Double = 8,
        ocrInterval: CFAbsoluteTime = 0.24,
        labelInterval: CFAbsoluteTime = 0.5
    ) {
        trackingInterval = 1.0 / max(1, trackingRate)
        self.ocrInterval = max(0, ocrInterval)
        self.labelInterval = max(0, labelInterval)
    }

    mutating func shouldRun(_ kind: ScanCadenceKind, at now: CFAbsoluteTime) -> Bool {
        guard isDue(kind, at: now) else { return false }
        markRan(kind, at: now)
        return true
    }

    /// Chooses the one Vision workload allowed to start for this frame.
    ///
    /// Tracking is intentionally not run immediately before a due footer OCR
    /// pass. That ordering used to let a tracker pass consume the frame queue
    /// first and turn the nominal 240 ms OCR cadence into a longer, device-
    /// dependent delay. If OCR is paused by a user choice, tracking may still
    /// run so the existing spatial continuity proof remains alive.
    mutating func nextVisionWork(
        at now: CFAbsoluteTime,
        ocrAllowed: Bool
    ) -> ScanCadenceKind? {
        if ocrAllowed, isDue(.ocr, at: now) {
            markRan(.ocr, at: now)
            return .ocr
        }
        guard isDue(.tracking, at: now) else { return nil }
        markRan(.tracking, at: now)
        return .tracking
    }

    /// Pulls the next footer pass forward after the first plausible reading.
    /// The current pass has already been marked as run; this makes the next
    /// eligible pass happen after `delay`, without changing the steady-state
    /// cadence once confirmation succeeds or the candidate disappears.
    mutating func prioritizeOCR(
        at now: CFAbsoluteTime,
        after delay: CFAbsoluteTime
    ) {
        guard ocrInterval > 0 else { return }
        lastOCRAt = now - ocrInterval + max(0, delay)
    }

    private func isDue(_ kind: ScanCadenceKind, at now: CFAbsoluteTime) -> Bool {
        switch kind {
        case .tracking:
            return lastTrackingAt == nil || now - lastTrackingAt! >= trackingInterval
        case .ocr:
            return lastOCRAt == nil || now - lastOCRAt! >= ocrInterval
        case .label:
            return lastLabelAt == nil || now - lastLabelAt! >= labelInterval
        }
    }

    mutating func markRan(_ kind: ScanCadenceKind, at now: CFAbsoluteTime) {
        switch kind {
        case .tracking:
            lastTrackingAt = now
        case .ocr:
            lastOCRAt = now
        case .label:
            lastLabelAt = now
        }
    }
}

enum SlabLabelSchedule {
    static let labelInterval: CFAbsoluteTime = 0.5
    static let certifiedCopyCheckInterval: CFAbsoluteTime = 2.0

    static func shouldReadLabel(
        mode: ScanSubjectMode,
        footerHasText: Bool,
        hasStableFooterIdentity: Bool,
        hasEvidence: Bool,
        certKnown: Bool,
        lastLabelAt: CFAbsoluteTime?,
        now: CFAbsoluteTime,
        needsFastFollowUp: Bool = false,
        certlessBackoff: Bool = false
    ) -> Bool {
        guard mode == .slab, footerHasText, hasStableFooterIdentity else { return false }
        guard let lastLabelAt else { return true }
        let interval = hasEvidence && (certKnown || certlessBackoff) && !needsFastFollowUp
            ? certifiedCopyCheckInterval
            : labelInterval
        return now - lastLabelAt >= interval
    }
}

struct SpatialResetProof: Identifiable, Equatable, Sendable {
    let id: UUID
    let encounterID: UUID
    /// Present when the tracker had already been accepted before it exited.
    /// A provisional proof is matched to history by `encounterID` after the
    /// asynchronous collection commit succeeds.
    let presentationToken: UUID?

    init(
        id: UUID = UUID(),
        encounterID: UUID,
        presentationToken: UUID? = nil
    ) {
        self.id = id
        self.encounterID = encounterID
        self.presentationToken = presentationToken
    }
}

struct HeldRepeatAuthorization: Equatable, Sendable {
    let id: UUID
    let expectedSuppressionKey: ScanSuppressionKey
    let expiresAt: CFAbsoluteTime

    init(
        id: UUID = UUID(),
        expectedSuppressionKey: ScanSuppressionKey,
        expiresAt: CFAbsoluteTime
    ) {
        self.id = id
        self.expectedSuppressionKey = expectedSuppressionKey
        self.expiresAt = expiresAt
    }

    func isExpired(at now: CFAbsoluteTime) -> Bool {
        now >= expiresAt
    }
}

enum HeldRepeatAuthorizationRejection: Equatable, Sendable {
    case cardChanged
    case expired
    case recognitionPaused
}

enum HeldRepeatAuthorizationResult: Equatable, Sendable {
    case accepted
    case rejected(HeldRepeatAuthorizationRejection)
}

enum HeldRepeatAuthorizationTerminalOutcome: Equatable, Sendable {
    case consumed
    case expired
    case rejected
    case cancelled
}

enum SpatialTrackerLifecycle: Equatable, Sendable {
    case idle
    case provisional(encounterID: UUID)
    case accepted(presentationToken: UUID, encounterID: UUID)
    case exited(proof: SpatialResetProof)
    case continuityLost
}

// Visual tracking follows image appearance, not physical identity. With a
// stack of identical cards it can stay attached to, or jump to, the lower copy;
// unless the strict exit rule is positively satisfied, that ambiguity remains
// continuity loss and cannot authorize a duplicate question.

/// Compatibility name for parser/debug code written before the whole-card guide.
typealias ScanRegion = CardFramingRegion

enum CameraIssue: Equatable {
    case permissionDenied
    case unavailable
    case configurationFailed

    var message: String {
        switch self {
        case .permissionDenied:
            return "Camera access is required. Enable Camera access in Settings, then reopen the scanner."
        case .unavailable:
            return "The back camera is unavailable on this device."
        case .configurationFailed:
            return "The camera could not be started. Try closing and reopening the scanner."
        }
    }
}

private enum CameraScannerError: Error {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
}

struct HistoricalEvidenceRequest: Equatable {
    let id: UUID
    let number: PokemonPrintedNumberEvidence
    let startedAt: CFAbsoluteTime
    var lastObservedAt: CFAbsoluteTime
    var retryCount: Int
    var titleCandidates: Set<String>
}

enum HistoricalTitleRequestPolicy {
    static func number(
        for outcome: RecognitionOutcome,
        footerLines: [RecognizedLine]
    ) -> PokemonPrintedNumberEvidence? {
        guard case .nothing = outcome else { return nil }
        return PokemonHistoricalScanParser.numberEvidence(in: footerLines.map(\.text))
    }
}

struct CaptureAssessment: Equatable {
    let detailSharpness: Float?
    let horizontalMotion: Float?
    let verticalMotion: Float?
    let textPixelHeight: Float?
    let localContrast: Float?
    let clippedHighlightArea: Float?
    let meanOCRConfidence: Float?
    let isAdjustingFocus: Bool
    let isAdjustingExposure: Bool
    let exposureDuration: Double
    let iso: Float
    let lensPosition: Float?
    let minimumFocusDistance: Int?
}

enum OpticalIssue: Equatable {
    case none
    case cameraSettling
    case insufficientDetail
    case likelyTooClose
    case lowLight
    case glare
    case motion
}

enum PresentationState: Equatable {
    case unknown
    case cardEntering
    case cardStable
    case cardChanging
}

struct ScanAssistance: Equatable {
    let issue: OpticalIssue
    let presentation: PresentationState

    static let none = ScanAssistance(issue: .none, presentation: .unknown)

    var message: String? {
        switch issue {
        case .insufficientDetail: return "Move closer"
        case .likelyTooClose: return "Back up slightly"
        case .lowLight: return "Add light"
        case .glare: return "Tilt card slightly"
        case .motion: return "Hold steady"
        case .none, .cameraSettling: return nil
        }
    }
}

/// Conservative evidence counter. Uncalibrated or absent measurements never
/// become a user-facing diagnosis.
struct CaptureAssistanceMonitor {
    /// How many consecutive frames without footer text an already-stable
    /// presentation survives before it is released.
    ///
    /// OCR loses the identifier strip for a frame or two constantly — a hand
    /// tremor, a glare band crossing it, the lens hunting focus. Collapsing to
    /// `.unknown` on the first such frame restarted the confirmation sequence
    /// every time and made a card that never actually moved look like it kept
    /// arriving.
    ///
    /// Fixed, and deliberately not proportional to how long the card has been
    /// stable: a card that sat still for a minute must be released as promptly
    /// as one that arrived a second ago, or the scanner would keep describing a
    /// card that has already left the frame.
    private static let blankFrameGrace = 2

    private(set) var presentation: PresentationState = .unknown
    private var stableObservationCount = 0
    private var blankObservationCount = 0
    private var candidateIssue: OpticalIssue = .none
    private var candidateCount = 0

    mutating func observe(_ assessment: CaptureAssessment, hasFooterText: Bool) -> ScanAssistance {
        if hasFooterText {
            blankObservationCount = 0
            stableObservationCount += 1
            presentation = stableObservationCount >= 2 ? .cardStable : .cardEntering
        } else if presentation == .cardStable, blankObservationCount < Self.blankFrameGrace {
            // Hold the established presentation. The grace applies only once a
            // card is actually stable — a presentation still entering has not
            // earned the benefit of the doubt.
            blankObservationCount += 1
        } else {
            blankObservationCount = 0
            stableObservationCount = 0
            presentation = .unknown
        }

        let next: OpticalIssue
        if assessment.isAdjustingFocus || assessment.isAdjustingExposure {
            next = .cameraSettling
        } else if presentation == .cardStable,
                  let height = assessment.textPixelHeight,
                  height < 7 {
            next = .insufficientDetail
        } else if presentation == .cardStable,
                  assessment.exposureDuration > 1.0 / 20.0,
                  assessment.iso > 800,
                  (assessment.meanOCRConfidence ?? 1) < 0.45 {
            next = .lowLight
        } else {
            next = .none
        }

        if next == candidateIssue {
            candidateCount += 1
        } else {
            candidateIssue = next
            candidateCount = 1
        }
        let emitted = candidateCount >= 3 ? next : .none
        return ScanAssistance(issue: emitted, presentation: presentation)
    }
}

/// Which back camera the session runs on.
///
/// The wide-angle lens on recent iPhones cannot focus closer than roughly 12cm.
/// A card's set code / collector number strip is ~4mm tall, so at the closest
/// distance the wide lens can actually focus, the strip lands on too few pixels
/// for `.accurate` OCR — the frame looks sharp but the text is mush. The ultra
/// wide focuses to ~2cm, which is what iOS itself switches to for macro, so it
/// is the correct lens for this app's whole job.
enum CameraLens: String, CaseIterable, Identifiable {
    /// The standard back camera. Frames a whole card from a comfortable distance.
    case standard
    /// The ultra wide back camera, used the way iOS uses it for macro: get close.
    case macro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .macro: return "Macro"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: return "camera"
        case .macro: return "camera.macro"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .standard: return .builtInWideAngleCamera
        case .macro: return .builtInUltraWideCamera
        }
    }

}

#if DEBUG
/// Debug-only Vision geometry belongs to the preview, not to the scanner's
/// shared publication stream. Keeping it in its own observable object prevents
/// every OCR pass from invalidating unrelated scanner chrome.
@MainActor
final class ScannerDebugVisionOverlay: ObservableObject {
    @Published private(set) var boxes: [CGRect] = []

    func update(_ boxes: [CGRect]) {
        guard self.boxes != boxes else { return }
        self.boxes = boxes
    }
}
#endif

/// Main-actor-owned values that the scanner publishes to SwiftUI.
///
/// The scanner itself deliberately remains queue-oriented: AVFoundation owns a
/// session queue and Vision owns a frame queue. Keeping the publication surface
/// in this small object makes the boundary explicit instead of relying on every
/// producer to remember that `@Published` is main-thread-only.
@MainActor
final class CardScannerUIState: ObservableObject {
    @Published private(set) var cameraIssue: CameraIssue?
    @Published private(set) var lens: CameraLens = .standard
    @Published private(set) var subjectMode: ScanSubjectMode = .raw
    /// Only the lenses this particular device actually has. An iPhone SE has no
    /// ultra wide, so the toggle must not offer one.
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var scanAssistance: ScanAssistance = .none
    /// Non-nil only after the label has earned its own confirmation window.
    @Published private(set) var slabFraming: GradedSlabEvidence?
    @Published private(set) var slabLabelReadPrompt: SlabLabelReadPrompt?
    /// The footer band Vision is currently reading. Published because the
    /// preview draws this rectangle and the debug overlay denormalizes
    /// observation boxes against it; re-deriving either from the guide geometry
    /// pointed both at a different strip than the one being recognized.
    @Published private(set) var footerRegionOfInterest: CGRect =
        CardFramingRegion.visionRect

    func setSubjectMode(_ mode: ScanSubjectMode) {
        guard subjectMode != mode else { return }
        subjectMode = mode
    }

    func setCameraIssue(_ issue: CameraIssue?) {
        cameraIssue = issue
    }

    func setLens(_ lens: CameraLens) {
        self.lens = lens
    }

    func setAvailableLenses(_ lenses: [CameraLens]) {
        availableLenses = lenses
    }

    func setScanAssistance(_ assistance: ScanAssistance) {
        guard scanAssistance != assistance else { return }
        scanAssistance = assistance
    }

    func showSlab(_ evidence: GradedSlabEvidence) {
        guard slabFraming != evidence else { return }
        slabFraming = evidence
    }

    func setFooterRegionOfInterest(_ rect: CGRect) {
        guard footerRegionOfInterest != rect else { return }
        footerRegionOfInterest = rect
    }

    func clearSlabPresentation() {
        slabFraming = nil
        slabLabelReadPrompt = nil
    }

    func setSlabLabelReadPrompt(_ prompt: SlabLabelReadPrompt?) {
        guard slabLabelReadPrompt != prompt else { return }
        slabLabelReadPrompt = prompt
    }
}

enum SlabLabelReadPromptStage: Equatable, Sendable {
    case findingCardNumber
    case readingLabel
    case labelNotFound

    var title: String {
        switch self {
        case .findingCardNumber: return "Fit the whole slab in the outline"
        case .readingLabel: return "Card found — reading slab label…"
        case .labelNotFound: return "No slab label found yet"
        }
    }

    var message: String {
        switch self {
        case .findingCardNumber:
            return "Tilt slightly to reduce glare so the card number is easier to read."
        case .readingLabel:
            return "Keep the whole label visible and tilt slightly to cut glare."
        case .labelNotFound:
            return "Keep the whole label in the outline, tilt slightly to cut glare, or scan as raw."
        }
    }

    var offersRawSwitch: Bool {
        self == .labelNotFound
    }
}

struct SlabLabelReadPrompt: Equatable, Identifiable, Sendable {
    let id: UUID
    let stage: SlabLabelReadPromptStage
}

final class CardScanner: NSObject, ObservableObject {
    let session = AVCaptureSession()

#if DEBUG
    let debugVisionOverlay: ScannerDebugVisionOverlay
#endif

    /// The rotation tracker publishes on the main actor while exposing a
    /// lock-backed queue-agnostic angle to the capture and Vision queues.
    let rotation: CameraRotationTracker

    /// The UI observes this object directly. The compatibility accessors below
    /// keep the test seams readable while asserting that reads happen on main.
    let uiState: CardScannerUIState

    /// A plausible identifier or historical evidence key has been read once.
    /// Not yet trusted, and never
    /// allowed to touch the collection — this exists so a catalog request can be
    /// in flight while Vision is still looking for its second matching pass.
    var onPlausibleCandidate: ((ScanSubject) -> Void)?
    var onSlabFooterRecognized: (() -> Void)?
    /// Parsed frames matching the identity currently under catalog-miss
    /// verification, including frames suppressed by the latch. The gate is
    /// checked against the vision-queue mirror so local evidence policies can
    /// count fresh observations without starting another catalog request.
    var onObservedCandidate: ((ScanSubject) -> Void)?
    /// Identity is established: confirmed across OCR passes and admitted by the
    /// latch as a new physical presentation.
    /// The encounter id is created at the exact frame that confirms the OCR
    /// encounter, before the event crosses to the view model.
    /// Subject-aware callback used by the scanner UI. The optional lifecycle
    /// fence is nil for deterministic callers that do not model a session, but
    /// production always supplies the token captured on the Vision queue at the
    /// exact confirmation frame.
    var onConfirmedSubjectCandidate: ((ScannerConfirmationToken?, UUID, ScanSubject, UUID?) -> Void)?
    /// A certificate first recognized after this encounter was committed is a
    /// refinement of its physical slab, not a second scan event.
    var onGradedSlabCertificationRefined: ((UUID, ScanSubject, ScanSubject) -> Void)?
    /// A bounded label read after a raw collection scan may offer conversion to
    /// a graded collection row. It never changes the already committed card.
    var onPostCommitSlabEvidence: ((UUID, GradedSlabEvidence) -> Void)?
    /// Positive spatial exit evidence. This is intentionally separate from OCR
    /// and from the latch's weak timeout/absence signals.
    var onSpatialResetProof: ((SpatialResetProof) -> Void)?
    /// Camera lifecycle is a scanner-session boundary. The view model dismisses
    /// pending candidates/proofs, but keeps committed session history.
    var onCameraInterruption: (() -> Void)?
    var onCameraInterruptionEnded: (() -> Void)?
    /// The same printing has been sitting in the band since it was consumed.
    /// Fires once per latch so the UI can explain the one case the latch cannot
    /// tell apart: a second identical copy dropped in without a gap.
    var onLatchHolding: ((ScanSubject, UUID?) -> Void)?
    /// The latch released a consumed presentation. The encounter id is kept
    /// when the scanner still owns that continuity; the suppression key is
    /// always present so the view model can clear a stale offer safely.
    var onLatchReleased: ((UUID?, ScanSuppressionKey) -> Void)?
    /// Terminal state for the scanner-owned held-repeat permit. In particular,
    /// expiry is emitted by the Vision queue's clock rather than inferred by a
    /// frame arriving late.
    var onHeldRepeatAuthorizationTerminated: ((UUID, HeldRepeatAuthorizationTerminalOutcome) -> Void)?

    private let sessionQueue = DispatchQueue(label: "cards.camera.session")
    private let visionQueue = DispatchQueue(label: "cards.camera.vision", qos: .userInitiated)
    private let profileQueue = DispatchQueue(
        label: "cards.camera.profile",
        qos: .userInitiated
    )
    private let videoOutput = AVCaptureVideoDataOutput()
    private let footerRequest = VNRecognizeTextRequest()
    private let titleRequest = VNRecognizeTextRequest()
    private let labelRequest = VNRecognizeTextRequest()
    private let trackingSequenceHandler = VNSequenceRequestHandler()

    private var isConfigured = false
    private var isPaused = false
    /// All capture-session starts are tied to the latest lifecycle request.
    /// Permission callbacks can arrive after the scanner has disappeared; a
    /// stale callback must not resurrect the camera off-screen.
    private var wantsRunning = false
    private var startRequestID = UUID()
    /// Wall-clock time at which recognition was paused. The latch's absence
    /// clock is compensated on resume because no OCR observations were produced
    /// during this interval.
    private var recognitionPausedAt: CFAbsoluteTime?
    private var videoInput: AVCaptureDeviceInput?
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndedObserver: NSObjectProtocol?
    /// Written on `sessionQueue`; `uiState.lens` is the main-thread mirror for
    /// the UI.
    private var currentLens: CameraLens = .standard
    private var confirmationWindow = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)
    /// A catalog miss verification suppresses speculative work for its exact
    /// physical identity. It is mirrored from the main actor before the frame
    /// reaches `announcePlausible`.
    private var catalogMissSuppressionKey: ScanSuppressionKey?
    /// Main-actor lifecycle state is mirrored here before a Vision frame can
    /// publish a confirmation. A callback carrying an older token is ignored
    /// by the view model instead of being reinterpreted by the current screen.
    private var confirmationContext: ScannerConfirmationToken?
    private var latch = CardLatch()
    /// A Price Check result needs a short breather before the same stationary
    /// card can be confirmed again. The confirmation window adds roughly half
    /// a second after this delay before its sheet can return.
    private static let priceCheckRecheckDelay: TimeInterval = 1.25
    private var didAnnounceLatchHold = false
    private var activeHeldRepeatAuthorization: HeldRepeatAuthorization?
    private var heldRepeatExpiryWorkItem: DispatchWorkItem?
    private var latchEncounterID: UUID?
    private var lastAnnouncedPlausible: ScanSubject?
    private var profile: RecognitionProfile = .pokemonOnly
    private var subjectMode: ScanSubjectMode = .raw
    private var historicalAttempt: HistoricalEvidenceRequest?
    private struct ActiveSlab: Equatable {
        let evidence: GradedSlabEvidence
    }

    private struct PostCommitLabelWatch {
        let encounterID: UUID
        let startedAt: CFAbsoluteTime
        let purpose: ScanPurpose
        var labelReads = 0
        var lastLabelAt: CFAbsoluteTime?
        var evidenceWindow = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
    }

    private enum SlabClearCause {
        case footerAbsence
        case latchRelease
        case identityChanged
        case spatialExit
        case lifecycle
    }
    private var activeSlab: ActiveSlab?
    private var activeSlabBaseIdentifier: ScanSuppressionKey?
    private var activeSlabEmptyFrames = 0
    private var slabAwaitingFooterKey: ScanSuppressionKey?
    private var slabFooterIdentityConfirmationWindow = CandidateConfirmationWindow(
        matchesRequired: 2,
        windowSize: 4
    )
    private var slabFooterRecognitionWindow = CandidateConfirmationWindow(
        matchesRequired: 2,
        windowSize: 4
    )
    private var slabFooterRecognizedKey: ScanSuppressionKey?
    private var slabAwaitingLabelSince: CFAbsoluteTime?
    private var slabFooterTextSince: CFAbsoluteTime?
    private var slabFooterTextPromptID: UUID?
    private var slabRecognitionID: UUID?
    private var slabAwaitingEmptyFrames = 0
    private var slabLabelPromptID: UUID?
    private var slabLabelReadSequence = 0
    private var slabEvidenceWindow = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
    private var certifiedCopyWindow = SlabEvidenceConfirmationWindow(matchesRequired: 3, windowSize: 5)
    private var certifiedCopyCandidate: String?
    private var certlessLabelMisses = 0
    private var postCommitLabelWatch: PostCommitLabelWatch?
    private var assistanceMonitor = CaptureAssistanceMonitor()
    private let spatialTrackingConfiguration: SpatialTrackingConfiguration
    private var trackerRequest: VNTrackObjectRequest?
    private var trackerEncounterID: UUID?
    private var trackerPresentationToken: UUID?
    private var trackerLifecycle: SpatialTrackerLifecycle = .idle
    /// A lost chain cannot be reconstructed by later OCR for the same identity.
    /// A different identity may start a fresh chain and clears this marker.
    private var trackerSeedGate = SpatialTrackerSeedGate()
    private var spatialExitAccumulator: SpatialExitObservationAccumulator
    private var cadence: ScanCadenceScheduler
    private static let historicalAttemptTTL: CFAbsoluteTime = 1.5
    private static let slabBandEmptyFramesBeforeClear = 4
    /// Keep the initial hold quiet. If the label still has not confirmed, show a
    /// framing hint while the scanner continues gathering evidence.
    private static let slabLabelOfferDelay: CFAbsoluteTime = 3.0
    private static let postCommitFirstLabelDelay: CFAbsoluteTime = 0.5
    private static let postCommitLabelInterval: CFAbsoluteTime = 0.75
    private static let postCommitMaximumLabelReads = 4
    private static let historicalAttemptLimit = 6

#if DEBUG
    private var labelOCRReadCount = 0
#endif


    /// Consecutive readings of an already-consumed card before the UI mentions it.
    /// Long enough that simply finishing a movement never triggers it.
    private static let latchHoldHintMatches = 8

    private struct AssistanceTextMetrics: Sendable {
        let textPixelHeight: Float?
        let meanOCRConfidence: Float?
        let hasFooterText: Bool
    }

    private struct AssistanceDeviceState: Sendable {
        let isAdjustingFocus: Bool
        let isAdjustingExposure: Bool
        let exposureDuration: Double
        let iso: Float
        let lensPosition: Float?
        let minimumFocusDistance: Int?

        init(device: AVCaptureDevice) {
            isAdjustingFocus = device.isAdjustingFocus
            isAdjustingExposure = device.isAdjustingExposure
            exposureDuration = CMTimeGetSeconds(device.exposureDuration)
            iso = device.iso
            lensPosition = device.isFocusModeSupported(.continuousAutoFocus)
                ? device.lensPosition
                : nil
            minimumFocusDistance = device.minimumFocusDistance >= 0
                ? device.minimumFocusDistance
                : nil
        }
    }

#if DEBUG
    private var diagnosticEvents: [String] = []
#endif

    @MainActor
    override convenience init() {
        self.init(spatialTrackingConfiguration: .experimental)
    }

    @MainActor
    init(spatialTrackingConfiguration: SpatialTrackingConfiguration) {
#if DEBUG
        debugVisionOverlay = ScannerDebugVisionOverlay()
#endif
        rotation = CameraRotationTracker()
        uiState = CardScannerUIState()
        self.spatialTrackingConfiguration = spatialTrackingConfiguration
        spatialExitAccumulator = SpatialExitObservationAccumulator(
            configuration: spatialTrackingConfiguration
        )
        cadence = ScanCadenceScheduler(
            trackingRate: spatialTrackingConfiguration.trackingRate,
            ocrInterval: 0.24,
            labelInterval: 0.5
        )
        super.init()
        configureTextRequest()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            // iOS reports the ordinary app-background transition through the
            // same interruption notification as real camera contention. It is
            // expected lifecycle, not a camera fault worth showing to the user.
            let notify = {
                DispatchQueue.main.async { [weak self] in
                    self?.onCameraInterruption?()
                }
            }
            guard let reasonNumber = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
                  let reason = AVCaptureSession.InterruptionReason(rawValue: reasonNumber.intValue) else {
                // Missing or future interruption reasons are not known-benign.
                // Reset pending scan state rather than letting an interruption
                // silently leave a stale latch and confirmation window alive.
                notify()
                return
            }
            guard reason != .videoDeviceNotAvailableInBackground else { return }
            notify()
        }
        interruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.onCameraInterruptionEnded?()
            }
        }

        // Resolved from the cached hardware probe rather than queried per launch.
        let lenses: [CameraLens] = CameraCapabilities.hasMacroLens() ? [.standard, .macro] : [.standard]

        // Macro is the default whenever the hardware has it. The standard lens
        // cannot focus close enough to resolve the identifier strip at all, so
        // starting there would mean every session opens on a blurry frame.
        let preferred = lenses.contains(.macro) ? CameraLens.macro : .standard
        uiState.setAvailableLenses(lenses)
        uiState.setLens(preferred)
        currentLens = preferred
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let interruptionEndedObserver {
            NotificationCenter.default.removeObserver(interruptionEndedObserver)
        }
    }

    // MARK: - Main-actor publication boundary

    /// Queue producers use one funnel for all SwiftUI-facing mutations. The
    /// state object, rather than this queue-oriented scanner, owns `@Published`.
    private func updateUI(_ update: @escaping @MainActor (CardScannerUIState) -> Void) {
        let state = uiState
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                update(state)
            }
        }
    }

#if DEBUG
    private func updateDebugVisionOverlay(_ boxes: [CGRect]) {
        let overlay = debugVisionOverlay
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                overlay.update(boxes)
            }
        }
    }
#endif

    // These synchronous accessors are retained for the existing debug seams.
    // Production SwiftUI views observe `uiState` directly, so state changes do
    // not depend on forwarding nested-object publications through the scanner.
    var cameraIssue: CameraIssue? {
        MainActor.assumeIsolated { uiState.cameraIssue }
    }

    var lens: CameraLens {
        MainActor.assumeIsolated { uiState.lens }
    }

    var availableLenses: [CameraLens] {
        MainActor.assumeIsolated { uiState.availableLenses }
    }

    var scanAssistance: ScanAssistance {
        MainActor.assumeIsolated { uiState.scanAssistance }
    }

    var slabFraming: GradedSlabEvidence? {
        MainActor.assumeIsolated { uiState.slabFraming }
    }

    var slabLabelReadPrompt: SlabLabelReadPrompt? {
        MainActor.assumeIsolated { uiState.slabLabelReadPrompt }
    }

    var footerRegionOfInterest: CGRect {
        MainActor.assumeIsolated { uiState.footerRegionOfInterest }
    }

    func start() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_route"),
           arguments.indices.contains(index + 1),
           arguments[index + 1] == "WholeCardScanner" {
            return
        }
#endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setCameraIssue(nil)
            let requestID = UUID()
            sessionQueue.async { [weak self] in
                self?.wantsRunning = true
                self?.startRequestID = requestID
            }
            configureAndStartIfNeeded(for: requestID)
        case .notDetermined:
            let requestID = UUID()
            sessionQueue.async { [weak self] in
                self?.wantsRunning = true
                self?.startRequestID = requestID
            }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.setCameraIssue(nil)
                    self.configureAndStartIfNeeded(for: requestID)
                } else {
                    self.sessionQueue.async {
                        self.wantsRunning = false
                        self.startRequestID = UUID()
                    }
                    self.setCameraIssue(.permissionDenied)
                }
            }
        default:
            sessionQueue.async { [weak self] in
                self?.wantsRunning = false
                self?.startRequestID = UUID()
            }
            setCameraIssue(.permissionDenied)
        }
    }

    func stop() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.cancelHeldRepeatAuthorizationOnVisionQueue()
            self.clearActiveSlab(cause: .lifecycle)
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = false
            self.startRequestID = UUID()
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Updates the lifecycle fence used by the confirmation callback. This is
    /// intentionally queued with Vision work so the token belongs to the same
    /// serial stream as the frame that may emit it.
    func updateConfirmationContext(_ context: ScannerConfirmationToken?) {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.confirmationContext = context
            if let context,
               let watch = self.postCommitLabelWatch,
               context.purpose != watch.purpose {
                self.postCommitLabelWatch = nil
            }
        }
    }

    /// A mode change invalidates every in-flight observation on the serial
    /// Vision queue before installing that mode's framing ROIs.
    func setSubjectMode(_ mode: ScanSubjectMode) {
        visionQueue.async { [weak self] in
            guard let self, self.subjectMode != mode else { return }
            self.subjectMode = mode
            self.postCommitLabelWatch = nil
            self.resetObservationState()
            self.installModeROIs()
            self.updateUI { $0.setSubjectMode(mode) }
        }
    }

    /// Mirrors the catalog-miss suppression key onto the same queue that decides
    /// whether a plausible reading should start speculative work or emit an
    /// observed-candidate callback. This keeps both hot-path decisions
    /// independent of the main actor.
    func updateCatalogMissSuppressionKey(_ key: ScanSuppressionKey?) {
        visionQueue.async { [weak self] in
            self?.catalogMissSuppressionKey = key
        }
    }

    /// Stops the camera and clears all presentation-scoped recognition state.
    /// The view model calls this at a real scanner-session boundary, not for an
    /// ordinary recognition pause.
    func endSession() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.recognitionPausedAt = nil
            self.isPaused = false
            self.resetObservationState()
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = false
            self.startRequestID = UUID()
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func pauseRecognition(at pausedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        visionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isPaused {
                self.recognitionPausedAt = pausedAt
            }
            self.isPaused = true
            self.cancelHeldRepeatAuthorizationOnVisionQueue()
        }
    }

    func resumeRecognition(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        visionQueue.async { [weak self] in
            guard let self else { return }
            let wasPaused = self.isPaused || self.recognitionPausedAt != nil
            if let pausedAt = self.recognitionPausedAt {
                self.latch.advanceObservedClock(
                    by: max(0, now - pausedAt)
                )
                self.recognitionPausedAt = nil
            }
            if wasPaused {
                self.resetConfirmationWindow()
            }
            self.isPaused = false
        }
    }

    /// Verifies a held-card offer against the latch on the vision queue. A
    /// successful tap is an explicit permit for one next confirmation, not a
    /// claim that the old presentation physically exited.
    func authorizeHeldRepeat(
        _ authorization: HeldRepeatAuthorization,
        completion: @escaping (HeldRepeatAuthorizationResult) -> Void
    ) {
        visionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    completion(.rejected(.cardChanged))
                }
                return
            }

            let result: HeldRepeatAuthorizationResult
            if authorization.isExpired(at: CFAbsoluteTimeGetCurrent()) {
                if self.activeHeldRepeatAuthorization?.id == authorization.id {
                    self.terminateHeldRepeatAuthorization(outcome: .expired)
                }
                self.recordDiagnostic("heldRepeatAuthorizationExpired")
                result = .rejected(.expired)
            } else if self.isPaused {
                self.recordDiagnostic("heldRepeatAuthorizationRejectedWhilePaused")
                result = .rejected(.recognitionPaused)
            } else if self.activeHeldRepeatAuthorization != nil ||
                        self.latch.latched?.suppressionKey != authorization.expectedSuppressionKey {
                self.recordDiagnostic("heldRepeatAuthorizationRejected")
                result = .rejected(.cardChanged)
            } else {
                // A lost tracker is not converted into exit evidence. The
                // authorization only opens the gate for this user's next
                // presentation, which may receive a fresh tracker seed.
                self.terminateTrackerWithoutSpatialProof()
                self.trackerSeedGate.allowAuthorizedReseed(
                    for: authorization.expectedSuppressionKey
                )
                self.latch.authorizeHeldRepeat(for: authorization.expectedSuppressionKey)
                self.resetConfirmationWindow()
                self.historicalAttempt = nil
                self.didAnnounceLatchHold = false
                self.activeHeldRepeatAuthorization = authorization
                self.recordDiagnostic("heldRepeatAuthorizationAccepted")
                self.scheduleHeldRepeatExpiryOnVisionQueue(for: authorization)
                result = .accepted
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Invalidates a pending held-repeat tap at a lifecycle boundary.
    func cancelHeldRepeatAuthorization() {
        visionQueue.async { [weak self] in
            self?.cancelHeldRepeatAuthorizationOnVisionQueue()
        }
    }

    /// Persistence failure leaves the visible card consumed but not added. Keep
    /// that latch state and reset only OCR confirmation so the offer can be
    /// restored by the ViewModel without inventing a new tracker lineage.
    func restoreHeldRepeatAfterFailure() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.activeHeldRepeatAuthorization = nil
            self.heldRepeatExpiryWorkItem?.cancel()
            self.heldRepeatExpiryWorkItem = nil
            self.latch.cancelHeldRepeatAuthorization()
            self.resetConfirmationWindow()
            self.didAnnounceLatchHold = false
        }
    }

    /// Recognition invalidation is allowed to clear OCR evidence, but it must
    /// not turn an active tracker into an exit proof. Used for mode changes,
    /// backgrounding, and camera interruptions.
    func invalidateSpatialContinuity() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.cancelHeldRepeatAuthorizationOnVisionQueue()
            self.markTrackerContinuityLost()
            self.clearActiveSlab(cause: .spatialExit)
            self.resetConfirmationWindow()
            self.historicalAttempt = nil
        }
    }

    /// Promotes the tracker that was seeded by this exact encounter. If it has
    /// already exited or been lost, no new tracker is created.
    func acceptedPresentation(encounterID: UUID, presentationToken: UUID) {
        visionQueue.async { [weak self] in
            guard let self,
                  self.trackerEncounterID == encounterID,
                  case .provisional = self.trackerLifecycle,
                  self.trackerRequest != nil else { return }
            self.trackerPresentationToken = presentationToken
            self.trackerLifecycle = .accepted(
                presentationToken: presentationToken,
                encounterID: encounterID
            )
        }
    }

    /// Keeps a suppressed candidate from becoming a new continuity chain. The
    /// latch remains engaged, so repeated OCR for the same visible card stays
    /// suppressed without any persistence knowledge in `CardScanner`.
    func keepPresentationSuppressed(encounterID: UUID) {
        visionQueue.async { [weak self] in
            guard let self,
                  self.trackerEncounterID == encounterID,
                  case .provisional = self.trackerLifecycle else { return }
            self.markTrackerContinuityLost()
        }
    }

    /// Rebinds an already continuous provisional candidate to the committed
    /// presentation when the user answers "Same card". This never reseeds.
    func rebindProvisionalPresentation(encounterID: UUID, presentationToken: UUID) {
        visionQueue.async { [weak self] in
            guard let self,
                  self.trackerEncounterID == encounterID,
                  self.trackerRequest != nil,
                  case .provisional = self.trackerLifecycle else { return }
            self.trackerPresentationToken = presentationToken
            self.trackerLifecycle = .accepted(
                presentationToken: presentationToken,
                encounterID: encounterID
            )
        }
    }

    /// Undo/delete can restore a prior committed record, but its old visual
    /// continuity is not recoverable. Mark the currently matching tracker lost;
    /// do not fabricate a new seed from the restored record.
    func restoreAcceptedPresentation(presentationToken: UUID) {
        visionQueue.async { [weak self] in
            guard let self,
                  case let .accepted(token, _) = self.trackerLifecycle,
                  token == presentationToken else { return }
            self.markTrackerContinuityLost()
        }
    }

    /// Allow the very next confirmation of the card currently in the band.
    ///
    /// Only for failures that wrote nothing and say nothing about the card — a
    /// dropped request should cost a re-read, never a collection entry. A lookup
    /// that failed because the record genuinely disagrees keeps its latch, so a
    /// card the app cannot resolve is asked about once instead of retried in a
    /// loop for as long as it sits there.
    func allowImmediateRetry() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.latch.releaseAndForget()
            self.resetConfirmationWindow()
            self.didAnnounceLatchHold = false
        }
    }

    /// Lets a dismissed Price Check result be read again after its brief
    /// confirmation-safe delay. This is intentionally narrower than
    /// `allowImmediateRetry()`: the latter forgets every consumed printing and
    /// is only safe when no card mutation or price-check history was written.
    func allowRecheck(of subject: ScanSubject) {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.latch.armRecheck(
                for: subject,
                at: CFAbsoluteTimeGetCurrent(),
                after: Self.priceCheckRecheckDelay
            )
            self.resetConfirmationWindow()
            self.didAnnounceLatchHold = false
        }
    }

    /// Installs the Magic set directory. One atomic update of the parser and the
    /// OCR vocabulary together, so no frame is ever recognised against a
    /// vocabulary that does not match the parser about to read it.
    ///
    /// Partial observations are cleared only when the vocabulary materially
    /// changes. The bundled snapshot is replaced by a live directory a moment
    /// after launch, and throwing away a half-confirmed card for a refresh that
    /// changed nothing the user is looking at would be a stutter for no reason.
    func useMagicDefinitions(_ definitions: [MagicSetDefinition]) {
        // Compiling the vocabulary regex is the expensive half. Keep it off
        // both the main actor and the frame queue, while preserving call order
        // so a live refresh cannot be followed by a stale bundled snapshot.
        profileQueue.async { [weak self] in
            let magic = MagicScanProfile(definitions: definitions)
            self?.useMagicDefinitions(magic)
        }
    }

    private func useMagicDefinitions(_ magic: MagicScanProfile) {
        visionQueue.async { [weak self] in
            guard let self, self.profile.magic?.definitions != magic.definitions else { return }
            self.profile = RecognitionProfile(pokemon: self.profile.pokemon, magic: magic)
            self.footerRequest.customWords = self.profile.customWords
            self.resetObservationState()
        }
    }

    /// Installs the Pokémon registry used by the frame parser and Vision's OCR
    /// vocabulary. The profile owns an immutable registry snapshot, so a
    /// candidate parsed before an activation keeps the `PokemonSetDefinition`
    /// that gave it meaning even after this method installs a newer profile.
    ///
    /// Regex compilation happens on the shared profile queue. Installation is
    /// serialized on the vision queue with frame parsing, and the confirmation
    /// window is cleared only when the vocabulary itself changes. Metadata-only
    /// release updates still replace the profile for future identifiers without
    /// throwing away a half-confirmed card.
    func usePokemonRegistry(_ registry: PokemonCatalogRegistry) {
        profileQueue.async { [weak self] in
            let pokemon = PokemonScanProfile(registry: registry)
            self?.usePokemonProfile(pokemon)
        }
    }

    private func usePokemonProfile(_ pokemon: PokemonScanProfile) {
        visionQueue.async { [weak self] in
            guard let self else { return }
            let vocabularyChanged = self.profile.pokemon.vocabulary != pokemon.vocabulary
            self.profile = RecognitionProfile(pokemon: pokemon, magic: self.profile.magic)
            self.footerRequest.customWords = self.profile.customWords
            if vocabularyChanged {
                self.resetObservationState()
            }
        }
    }

    private func configureTextRequest() {
        footerRequest.recognitionLevel = .accurate
        footerRequest.recognitionLanguages = ["en-US"]

        // Vision only applies customWords while language correction is enabled.
        // Field testing should decide whether this wins over correction-off for the
        // numeric-heavy identifier strip; keep the custom set vocabulary for MVP.
        footerRequest.usesLanguageCorrection = true
        footerRequest.customWords = profile.customWords

        titleRequest.recognitionLevel = .accurate
        titleRequest.recognitionLanguages = ["en-US"]
        titleRequest.usesLanguageCorrection = true

        labelRequest.recognitionLevel = .accurate
        labelRequest.recognitionLanguages = ["en-US"]
        labelRequest.usesLanguageCorrection = true
        labelRequest.customWords = GradedLabelParser.visionCustomWords
        installModeROIs()
    }

    private func configureAndStartIfNeeded(for requestID: UUID) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.wantsRunning, self.startRequestID == requestID else { return }

            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch CameraScannerError.cameraUnavailable {
                    self.setCameraIssue(.unavailable)
                    return
                } catch {
                    self.setCameraIssue(.configurationFailed)
                    return
                }
            }

            guard self.wantsRunning, self.startRequestID == requestID else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// Switches lenses without tearing down the session. Safe to call while running.
    func setLens(_ newLens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, newLens != self.currentLens else { return }
            guard CardScanner.device(for: newLens) != nil else { return }

            let previousLens = self.currentLens
            do {
                try self.attachInput(for: newLens)
            } catch {
                // Put the working lens back rather than leaving the session with no
                // input, which would freeze the preview on the last frame.
                try? self.attachInput(for: previousLens)
                return
            }

            self.visionQueue.async {
                self.markTrackerContinuityLost()
                self.resetObservationState()
            }
        }
    }

    /// Whether a lens is *usable* is `CameraCapabilities`' decision; this only
    /// resolves the device once that decision has been made.
    private static func device(for lens: CameraLens) -> AVCaptureDevice? {
        AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try attachInput(for: currentLens)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            // Vision consumes the camera's native biplanar YUV format. Keeping
            // capture in that format avoids a full 4K BGRA conversion and cuts
            // the continuously allocated frame bandwidth roughly in half.
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)

        guard session.canAddOutput(videoOutput) else { throw CameraScannerError.cannotAddOutput }
        session.addOutput(videoOutput)
    }

    /// Swaps the session's video input to `lens`. Callers must be on `sessionQueue`.
    ///
    /// `beginConfiguration` nests, so this works both inside `configureSession`'s
    /// batch and as a standalone switch on a running session.
    private func attachInput(for lens: CameraLens) throws {
        guard let device = CardScanner.device(for: lens) else {
            throw CameraScannerError.cameraUnavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let existing = videoInput {
            session.removeInput(existing)
            videoInput = nil
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraScannerError.cannotAddInput }
        session.addInput(input)
        videoInput = input

        applyBestPreset()
        try configureCamera(device)

        currentLens = lens
        updateUI { $0.setLens(lens) }
    }

    /// Picks the highest preset the *current* input can satisfy.
    ///
    /// This must run before `configureCamera`. Changing the preset reselects the
    /// device's `activeFormat`, and that resets per-device state including
    /// `videoZoomFactor` and focus configuration — so setting the preset afterwards
    /// silently discarded every macro setting applied to the device.
    ///
    /// The identifier strip is roughly 4mm of printed text, so pixels on that strip
    /// are the limiting factor for OCR accuracy. Take 4K where the device offers it;
    /// Vision's ROI crops before recognition, so the extra pixels cost buffer
    /// bandwidth rather than proportionally more recognition time.
    private func applyBestPreset() {
        let preferred: [AVCaptureSession.Preset] = [.hd4K3840x2160, .hd1920x1080, .high]
        guard let preset = preferred.first(where: { session.canSetSessionPreset($0) }) else { return }
        session.sessionPreset = preset
    }

    private func configureCamera(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        // A card is always within arm's reach. Without this the lens hunts through
        // the far half of its range every time the card moves, and each hunt costs
        // several frames of blur — which reads to the user as "it won't focus".
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        // Smooth AF ramps focus slowly to keep recorded video watchable. Nothing is
        // being recorded here and a slow ramp is just a longer stretch of unreadable
        // frames, so leave it off and let the lens snap.
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = false
        }

        // Focus and meter on the scan band rather than the frame centre, so a busy
        // card illustration cannot pull focus away from the text being read.
        // Focus/exposure points are in metadata (sensor) space, so the scan band's
        // location there depends on how the device is held. Set from the rotation
        // known at configure time; a later rotation moves the point by less than the
        // depth of field at card distance, so it is not re-applied per rotation.
        let focusRect = ScanRegion.metadataRect(rotationAngle: rotation.currentAngle)
        let focusPoint = CGPoint(x: focusRect.midX, y: focusRect.midY)
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = focusPoint
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = focusPoint
        }

        // The ultra wide runs at its native field of view: no digital zoom, because
        // cropping would throw away exactly the pixels the OCR needs. The user closes
        // the distance instead — that is what the lens is for.
        let zoom = device.minAvailableVideoZoomFactor
        if device.videoZoomFactor != zoom {
            device.videoZoomFactor = zoom
        }
    }

    // MARK: - Spatial continuity

    /// Creates the only tracker for a confirmed encounter. The seed is the
    /// exact frame that produced the OCR confirmation, not a later frame or a
    /// later OCR result.
    private func seedTracker(
        encounterID: UUID,
        subject: ScanSubject,
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        at now: CFAbsoluteTime
    ) {
        if trackerRequest != nil {
            // OCR confirmation of a different identity is enough to start a
            // new lineage, but it is never proof that the old presentation
            // physically exited. Drop the old tracker without publishing an
            // exit event, then seed this confirmed encounter.
            terminateTrackerWithoutSpatialProof()
        }
        guard trackerSeedGate.canSeed(subject) else {
            // Later OCR is not a spatial reset. Keep the identity consumed and
            // let the view model suppress it without creating a new lineage.
            return
        }

        let seedObservation = VNDetectedObjectObservation(
            boundingBox: spatialTrackingConfiguration.seedRect
        )
        let request = VNTrackObjectRequest(detectedObjectObservation: seedObservation)
        request.trackingLevel = .fast

        trackerEncounterID = encounterID
        trackerSeedSubject = subject
        trackerPresentationToken = nil
        trackerRequest = request
        trackerLifecycle = .provisional(encounterID: encounterID)
        spatialExitAccumulator.reset()
        cadence.markRan(.tracking, at: now)
        recordDiagnostic("trackerSeeded")

        // Establish the sequence on the same pixel buffer that confirmed the
        // encounter. If Vision does not return a result for this seed, retain
        // the known presentation box and let the next frame prove continuity.
        do {
            try trackingSequenceHandler.perform(
                [request],
                on: pixelBuffer,
                orientation: orientation
            )
            if let observation = request.results?.first as? VNDetectedObjectObservation {
                feedForwardTrackerObservation(observation, into: request)
            }
        } catch {
            markTrackerContinuityLost()
        }
    }

    /// Runs on a frame selected by `ScanCadenceScheduler`. The scheduler has
    /// already marked tracking as run, which prevents a tracker pass from being
    /// selected again ahead of the next footer OCR pass.
    private func trackCurrentFrame(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        at now: CFAbsoluteTime
    ) {
        guard let request = trackerRequest else { return }

        do {
            try trackingSequenceHandler.perform(
                [request],
                on: pixelBuffer,
                orientation: orientation
            )
            guard let observation = request.results?.first as? VNDetectedObjectObservation else {
                markTrackerContinuityLost()
                return
            }

            feedForwardTrackerObservation(observation, into: request)
            guard observation.confidence >= spatialTrackingConfiguration.minimumConfidence else {
                markTrackerContinuityLost()
                return
            }
            guard !spatialExitAccumulator.observe(
                box: observation.boundingBox,
                confidence: observation.confidence
            ) else {
                guard let encounterID = trackerEncounterID else {
                    markTrackerContinuityLost()
                    return
                }
                let proof = SpatialResetProof(
                    encounterID: encounterID,
                    presentationToken: trackerPresentationToken
                )
                let subject = trackerSubjectForExit
                request.isLastFrame = true
                trackerRequest = nil
                trackerEncounterID = nil
                trackerSeedSubject = nil
                trackerPresentationToken = nil
                trackerLifecycle = .exited(proof: proof)
                spatialExitAccumulator.reset()

                // Make the latch's consumed identity eligible again, but only
                // because the independent tracker produced positive exit proof.
                if let subject {
                    let latchWasEngaged = latch.latched
                    let latchEncounterID = self.latchEncounterID
                    latch.confirmSpatialExit(for: subject)
                    if let latchWasEngaged, latch.latched == nil {
                        self.latchEncounterID = nil
                        if self.activeHeldRepeatAuthorization != nil {
                            self.terminateHeldRepeatAuthorization(outcome: .cancelled)
                        }
                        self.emitLatchRelease(
                            encounterID: latchEncounterID,
                            suppressionKey: latchWasEngaged.suppressionKey
                        )
                    }
                }
                // A slab label is presentation state, not a two-second hint.
                // Positive spatial exit is the authoritative boundary that
                // lets the next raw card start with a clean subject.
                clearActiveSlab(cause: .spatialExit)
                recordDiagnostic("spatialProof")
                DispatchQueue.main.async { [weak self] in
                    self?.onSpatialResetProof?(proof)
                }
                return
            }
        } catch {
            markTrackerContinuityLost()
        }
    }

    /// The identifier is retained only to authorize the local latch release;
    /// persistence and duplicate decisions remain in the view model.
    private var trackerSubjectForExit: ScanSubject? {
        switch trackerLifecycle {
        case .provisional, .accepted:
            return trackerSeedSubject
        case .idle, .exited, .continuityLost:
            return nil
        }
    }

    private var trackerSeedSubject: ScanSubject?

    /// Vision tracking is sequential: the observation returned for this frame
    /// must become the request's input for the next frame. Keep this assignment
    /// beside the cached observation update so a future lifecycle change cannot
    /// accidentally preserve only the stale seed.
    static func feedForwardTrackerObservation(
        _ observation: VNDetectedObjectObservation,
        into request: VNTrackObjectRequest
    ) {
        request.inputObservation = observation
    }

    private func feedForwardTrackerObservation(
        _ observation: VNDetectedObjectObservation,
        into request: VNTrackObjectRequest
    ) {
        Self.feedForwardTrackerObservation(observation, into: request)
    }

    /// Tracker loss is never exit evidence. It only releases the Vision
    /// request and records that this presentation can no longer authorize a
    /// duplicate prompt. Slab evidence is cleared by its own footer, spatial,
    /// latch, or lifecycle presence rules.
    private func markTrackerContinuityLost() {
        let hadTracker = trackerRequest != nil || trackerSeedSubject != nil
        // Preserve an earlier lost marker when a later lifecycle invalidation
        // arrives after the request has already been released. Passing nil to
        // the gate would accidentally reopen same-identity reseeding.
        if let trackerSeedSubject {
            trackerSeedGate.markLost(trackerSeedSubject)
        }
        trackerRequest?.isLastFrame = true
        trackerRequest = nil
        trackerEncounterID = nil
        trackerSeedSubject = nil
        trackerPresentationToken = nil
        spatialExitAccumulator.reset()
        trackerLifecycle = .continuityLost
        if hadTracker {
            recordDiagnostic("trackerLost")
        }
    }

    /// Ends a tracker because the user explicitly authorized a new physical
    /// presentation. Unlike `markTrackerContinuityLost`, this does not set the
    /// same-identity lost gate and cannot emit a spatial proof.
    private func terminateTrackerWithoutSpatialProof() {
        trackerRequest?.isLastFrame = true
        trackerRequest = nil
        trackerEncounterID = nil
        trackerSeedSubject = nil
        trackerPresentationToken = nil
        spatialExitAccumulator.reset()
        trackerLifecycle = .idle
    }

    /// Must be called on `visionQueue`. The work item is the authoritative
    /// deadline for a held-repeat permit; frame processing only handles the
    /// other terminal races (consumption, rejection, or lifecycle cancel).
    private func scheduleHeldRepeatExpiryOnVisionQueue(
        for authorization: HeldRepeatAuthorization
    ) {
        heldRepeatExpiryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeHeldRepeatAuthorization?.id == authorization.id else { return }

            self.activeHeldRepeatAuthorization = nil
            self.heldRepeatExpiryWorkItem = nil
            self.latch.cancelHeldRepeatAuthorization()
            self.resetConfirmationWindow()
            self.didAnnounceLatchHold = false
            self.recordDiagnostic("heldRepeatAuthorizationExpired")
            self.emitHeldRepeatAuthorizationTermination(
                id: authorization.id,
                outcome: .expired
            )
        }
        heldRepeatExpiryWorkItem = workItem
        let remaining = max(0, authorization.expiresAt - CFAbsoluteTimeGetCurrent())
        visionQueue.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    /// Must be called on `visionQueue`. Every path clears the deadline before
    /// publishing its terminal outcome, making later queued work harmless.
    private func terminateHeldRepeatAuthorization(
        outcome: HeldRepeatAuthorizationTerminalOutcome
    ) {
        guard let authorization = activeHeldRepeatAuthorization else {
            heldRepeatExpiryWorkItem?.cancel()
            heldRepeatExpiryWorkItem = nil
            latch.cancelHeldRepeatAuthorization()
            return
        }

        activeHeldRepeatAuthorization = nil
        heldRepeatExpiryWorkItem?.cancel()
        heldRepeatExpiryWorkItem = nil
        latch.cancelHeldRepeatAuthorization()
        emitHeldRepeatAuthorizationTermination(id: authorization.id, outcome: outcome)
    }

    private func emitHeldRepeatAuthorizationTermination(
        id: UUID,
        outcome: HeldRepeatAuthorizationTerminalOutcome
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onHeldRepeatAuthorizationTerminated?(id, outcome)
        }
    }

    private func cancelHeldRepeatAuthorizationOnVisionQueue() {
        if activeHeldRepeatAuthorization != nil {
            recordDiagnostic("heldRepeatAuthorizationCancelled")
            terminateHeldRepeatAuthorization(outcome: .cancelled)
        } else {
            heldRepeatExpiryWorkItem?.cancel()
            heldRepeatExpiryWorkItem = nil
            latch.cancelHeldRepeatAuthorization()
        }
    }

    /// The whole acceptance pipeline, in order. Everything above this line is
    /// evidence gathering; nothing below it is allowed to guess.
    ///
    ///     OCR observation -> latch -> rolling confirmation -> latch admission -> identity
    ///
    /// Recognition is never paused on success. The camera is the product surface,
    /// so card two is already being read while card one's receipt is still on
    /// screen — the latch, not a pause, is what stops one card being counted
    /// twice.
    private func handleFooterOutcome(
        _ outcome: RecognitionOutcome,
        footerLines: [RecognizedLine],
        historicalSubject: ScanSubject?,
        at now: CFAbsoluteTime,
        pixelBuffer: CVPixelBuffer?,
        didUpdateSlabPresence: Bool = false
    ) {
        if !didUpdateSlabPresence {
            updateActiveSlabPresence(
                outcome: outcome,
                historicalSubject: historicalSubject,
                footerLines: footerLines,
                at: now
            )
        }

        // Vision's line grouping is preserved into the parsers, which is what
        // keeps a set code paired with its own collector number when more than
        // one card is visible.
        //
        // An ambiguous frame is treated exactly like a frame that read nothing:
        // it confirms nothing, and it ages the confirmation window so a later
        // pass gets a clean run at the card.
        // Ordinary identification runs on every frame, whatever else is
        // pending. Historical title capture is additional evidence gathering,
        // never a replacement for the scanner's normal ability to recognise a
        // card — the invariant being that no card is ever unrecognisable
        // because of what happened while looking at a previous one.
        let parsed: ScanSubject?
        switch outcome {
        case let .identified(subject):
            historicalAttempt = nil
            parsed = activeSlabEvidence(matching: subject.identifier).map {
                ScanSubject(identifier: subject.identifier, slab: $0)
            } ?? subject
        case .nothing:
            parsed = historicalSubject
        case .ambiguous, .spatiallyRejectedMagicCollector:
            historicalAttempt = nil
            parsed = nil
        }

        // Whether the band is occupied, which is not the same question as
        // whether this frame produced an identifier. A card being moved is
        // legible-but-unparseable for most of the movement, and the latch must
        // not read that as the card having left.
        let latchedBeforeObservation = latch.latched
        let decision = latch.observeSubject(parsed, cardPresent: !footerLines.isEmpty, at: now)
        let isLateSlabCertificationRefinement = parsed.map { observation in
            guard let latched = latch.latched,
                  latched.identifier == observation.identifier,
                  let previous = latched.slab,
                  let updated = observation.slab else { return false }
            return SlabEvidenceConfirmationWindow.isCertificateRefinement(
                from: previous,
                to: updated
            )
        } ?? false
        if let parsed,
           parsed.suppressionKey == catalogMissSuppressionKey {
            DispatchQueue.main.async { [weak self] in
                self?.onObservedCandidate?(parsed)
            }
        }
        if let latchedBeforeObservation, latch.latched == nil {
            postCommitLabelWatch = nil
            let encounterID = latchEncounterID
            latchEncounterID = nil
            if activeHeldRepeatAuthorization != nil {
                terminateHeldRepeatAuthorization(outcome: .cancelled)
            }
            emitLatchRelease(
                encounterID: encounterID,
                suppressionKey: latchedBeforeObservation.suppressionKey
            )
            if latchedBeforeObservation.slab != nil || activeSlab != nil {
                clearActiveSlab(cause: .latchRelease, at: now)
            }
        }

        switch decision {
        case .holdingLatch:
            announceLatchHoldIfNeeded()

        case let .forwardSubject(observation):
            if isLateSlabCertificationRefinement {
                // A late label confirmation can add the slab axis after the
                // graded subject has already been admitted. It is still the
                // same physical presentation, so it must not become a second
                // event.
                resetConfirmationWindow()
                return
            }

            if subjectMode == .slab, observation?.slab == nil {
                if let observation {
                    announcePlausible(
                        ScanSubject(identifier: observation.identifier),
                        at: now
                    )
                }
                updateSlabLabelPromptIfDue(at: now)
                _ = confirmationWindow.observeSubject(nil)
                announceLatchHoldIfNeeded()
                return
            }

            announcePlausible(observation, at: now)

            guard let confirmed = confirmationWindow.observeSubject(observation) else { return }
            PerformanceSignpost.emitEvent("twoFrameConfirmation", "ordinary")

            if let replaced = latch.replaceHeldCertifiedSlab(with: confirmed) {
                postCommitLabelWatch = nil
                let replacedEncounterID = latchEncounterID
                latchEncounterID = nil
                emitLatchRelease(
                    encounterID: replacedEncounterID,
                    suppressionKey: replaced.suppressionKey
                )
            }

            if let authorization = activeHeldRepeatAuthorization {
                if authorization.isExpired(at: now) {
                    terminateHeldRepeatAuthorization(outcome: .expired)
                    recordDiagnostic("heldRepeatAuthorizationExpired")
                } else {
                    // A different identity became authoritative before the
                    // held repeat did. Reject the permit, then let this new
                    // identity take the ordinary path.
                    terminateHeldRepeatAuthorization(outcome: .rejected)
                    recordDiagnostic("heldRepeatAuthorizationRejected")
                }
            }

            // Confirmed, but the same physical card may simply never have left.
            guard latch.admits(confirmed) else {
                // This is suppression, not a new scanning boundary. Preserve
                // the plausible marker so a held duplicate does not keep
                // restarting speculative catalog work.
                confirmationWindow.reset()
                return
            }

            latch.engage(on: confirmed, at: now)
            latchEncounterID = nil
            didAnnounceLatchHold = false
            historicalAttempt = nil
            let encounterID = UUID()
            latchEncounterID = encounterID
            if subjectMode == .slab {
                PerformanceSignpost.emitEvent(
                    "slabEncounterAdmitted",
                    "observation=\(slabRecognitionID?.uuidString ?? "none") encounter=\(encounterID.uuidString)"
                )
            }
            armPostCommitLabelWatchIfNeeded(encounterID: encounterID, at: now)
            if let pixelBuffer {
                seedTracker(
                    encounterID: encounterID,
                    subject: confirmed,
                    pixelBuffer: pixelBuffer,
                    orientation: CardFramingRegion.imageOrientation(forRotationAngle: rotation.currentAngle),
                    at: now
                )
            }
            let context = confirmationContext
            DispatchQueue.main.async { [weak self] in
                self?.onConfirmedSubjectCandidate?(
                    context,
                    encounterID,
                    confirmed,
                    nil
                )
            }

        case let .forwardAuthorizedSubject(observation):
            if subjectMode == .slab, observation.slab == nil {
                updateSlabLabelPromptIfDue(at: now)
                _ = confirmationWindow.observeSubject(nil)
                announceLatchHoldIfNeeded()
                return
            }

            announcePlausible(observation, at: now)

            guard let confirmed = confirmationWindow.observeSubject(observation) else { return }
            PerformanceSignpost.emitEvent("twoFrameConfirmation", "held-repeat")
            guard let authorization = activeHeldRepeatAuthorization,
                  confirmed.suppressionKey == authorization.expectedSuppressionKey,
                  latch.consumeHeldRepeatAuthorization(for: authorization.expectedSuppressionKey) else {
                // A dedicated decision is never allowed to fall through into
                // ordinary admission if its one-shot token disappeared.
                resetConfirmationWindow()
                return
            }

            let authorizationID = authorization.id
            terminateHeldRepeatAuthorization(outcome: .consumed)
            recordDiagnostic("heldRepeatAuthorizationConsumed")
            latch.engage(on: confirmed, at: now)
            didAnnounceLatchHold = false
            historicalAttempt = nil
            let encounterID = UUID()
            latchEncounterID = encounterID
            armPostCommitLabelWatchIfNeeded(encounterID: encounterID, at: now)
            if let pixelBuffer {
                seedTracker(
                    encounterID: encounterID,
                    subject: confirmed,
                    pixelBuffer: pixelBuffer,
                    orientation: CardFramingRegion.imageOrientation(forRotationAngle: rotation.currentAngle),
                    at: now
                )
            }
            let context = confirmationContext
            DispatchQueue.main.async { [weak self] in
                self?.onConfirmedSubjectCandidate?(
                    context,
                    encounterID,
                    confirmed,
                    authorizationID
                )
            }

        }
    }

    private func activateSlab(
        _ evidence: GradedSlabEvidence,
        baseIdentifier: ScanSuppressionKey? = nil
    ) {
        guard activeSlab == nil else { return }
        PerformanceSignpost.emitEvent(
            "slabLabelConfirmed",
            "observation=\(slabRecognitionID?.uuidString ?? "none") grader=\(evidence.company.rawValue) certificate=\(evidence.certificationNumber == nil ? "missing" : "read")"
        )
        activeSlab = ActiveSlab(evidence: evidence)
        activeSlabEmptyFrames = 0
        if activeSlabBaseIdentifier == nil {
            activeSlabBaseIdentifier = baseIdentifier
        }
        slabAwaitingFooterKey = nil
        slabFooterIdentityConfirmationWindow.reset()
        slabAwaitingLabelSince = nil
        slabFooterTextSince = nil
        slabFooterTextPromptID = nil
        slabAwaitingEmptyFrames = 0
        slabLabelPromptID = nil
        slabEvidenceWindow.reset()
        certifiedCopyWindow.reset()
        certifiedCopyCandidate = nil
        certlessLabelMisses = 0
        installModeROIs()
        updateUI { $0.setSlabLabelReadPrompt(nil) }
        updateUI { $0.showSlab(evidence) }
    }

    private func refineActiveSlabCertificate(_ evidence: GradedSlabEvidence) {
        guard let previousEvidence = activeSlab?.evidence,
              SlabEvidenceConfirmationWindow.isCertificateRefinement(
                  from: previousEvidence,
                  to: evidence
              ) else { return }
        activeSlab = ActiveSlab(evidence: evidence)
        certlessLabelMisses = 0
        updateUI { $0.showSlab(evidence) }

        if let encounterID = latchEncounterID,
           let latched = latch.latched {
            let updated = ScanSubject(identifier: latched.identifier, slab: evidence)
            guard latch.refineLatchedSlab(to: updated) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onGradedSlabCertificationRefined?(encounterID, latched, updated)
            }
        }
    }

    private func replaceActiveSlabWithCertifiedCopy(_ evidence: GradedSlabEvidence) {
        guard let previousEvidence = activeSlab?.evidence,
              SlabEvidenceConfirmationWindow.isDistinctCertifiedCopy(
                  from: previousEvidence,
                  to: evidence
              ) else { return }
        activeSlab = ActiveSlab(evidence: evidence)
        slabEvidenceWindow.reset()
        certifiedCopyWindow.reset()
        certifiedCopyCandidate = nil
        updateUI { $0.showSlab(evidence) }
    }

    private func activeSlabEvidence(matching identifier: ScanIdentifier) -> GradedSlabEvidence? {
        guard activeSlabBaseIdentifier == identifier.suppressionKey else { return nil }
        return activeSlab?.evidence
    }

    /// Installs the footer ROI and mirrors it for the preview. Callers must be
    /// on `visionQueue`.
    private func setFooterRegionOfInterest(_ rect: CGRect) {
        footerRequest.regionOfInterest = rect
        updateUI { $0.setFooterRegionOfInterest(rect) }
    }

    private func installModeROIs() {
        switch subjectMode {
        case .raw:
            setFooterRegionOfInterest(CardFramingRegion.visionRect)
            titleRequest.regionOfInterest = CardFramingRegion.titleVisionRect
            labelRequest.regionOfInterest = SlabFramingRegion.bootstrapLabelVisionRect
        case .slab:
            setFooterRegionOfInterest(SlabFramingRegion.slabModeFooterVisionRect)
            titleRequest.regionOfInterest = SlabFramingRegion.slabModeTitleVisionRect
            labelRequest.regionOfInterest = SlabFramingRegion.slabModeLabelVisionRect
        }
    }

    private func clearActiveSlab(
        cause: SlabClearCause,
        at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) {
        activeSlab = nil
        activeSlabBaseIdentifier = nil
        activeSlabEmptyFrames = 0
        slabAwaitingFooterKey = nil
        slabFooterIdentityConfirmationWindow.reset()
        slabFooterRecognitionWindow.reset()
        slabFooterRecognizedKey = nil
        slabAwaitingLabelSince = nil
        slabFooterTextSince = nil
        slabFooterTextPromptID = nil
        slabRecognitionID = nil
        slabAwaitingEmptyFrames = 0
        slabLabelPromptID = nil
        slabEvidenceWindow.reset()
        certifiedCopyWindow.reset()
        certifiedCopyCandidate = nil
        certlessLabelMisses = 0
        switch cause {
        case .footerAbsence:
            recordDiagnostic("slabClearAbsence")
        case .latchRelease:
            postCommitLabelWatch = nil
            recordDiagnostic("slabClearLatchRelease")
        case .identityChanged:
            recordDiagnostic("slabClearIdentityChanged")
        case .spatialExit:
            postCommitLabelWatch = nil
            recordDiagnostic("slabClearSpatialExit")
        case .lifecycle:
            postCommitLabelWatch = nil
            recordDiagnostic("slabClearLifecycle")
        }
        installModeROIs()
        updateUI { $0.clearSlabPresentation() }
        updateUI { $0.setSlabLabelReadPrompt(nil) }
    }

    /// In slab mode, label evidence stays bound to the first stable footer key
    /// seen with it. A replacement key must confirm in 2 of 4 footer reads so a
    /// single OCR misread cannot reset label progress or the no-label timer.
    private func updateActiveSlabPresence(
        outcome: RecognitionOutcome,
        historicalSubject: ScanSubject?,
        footerLines: [RecognizedLine],
        at now: CFAbsoluteTime
    ) {
        guard subjectMode == .slab else { return }
        let footerIdentifier: ScanIdentifier? = switch outcome {
        case let .identified(subject): subject.identifier
        case .nothing, .ambiguous, .spatiallyRejectedMagicCollector:
            historicalSubject?.identifier
        }
        let footerKey = footerIdentifier?.suppressionKey

        guard !footerLines.isEmpty else {
            _ = slabFooterIdentityConfirmationWindow.observeSubject(nil)
            _ = slabFooterRecognitionWindow.observeSubject(nil)
            slabFooterTextSince = nil
            slabFooterTextPromptID = nil
            if activeSlab == nil, activeSlabBaseIdentifier == nil {
                updateUI { $0.setSlabLabelReadPrompt(nil) }
            }
            activeSlabEmptyFrames += 1
            slabAwaitingEmptyFrames += 1
            if activeSlabEmptyFrames >= Self.slabBandEmptyFramesBeforeClear
                || slabAwaitingEmptyFrames >= Self.slabBandEmptyFramesBeforeClear {
                clearActiveSlab(cause: .footerAbsence, at: now)
            }
            return
        }

        activeSlabEmptyFrames = 0
        slabAwaitingEmptyFrames = 0
        if slabFooterTextSince == nil {
            slabFooterTextSince = now
            slabFooterTextPromptID = UUID()
            if slabRecognitionID == nil {
                let recognitionID = UUID()
                slabRecognitionID = recognitionID
                PerformanceSignpost.emitEvent(
                    "slabFooterTextVisible",
                    "observation=\(recognitionID.uuidString)"
                )
            }
        }
        guard let footerIdentifier, let footerKey else {
            _ = slabFooterIdentityConfirmationWindow.observeSubject(nil)
            _ = slabFooterRecognitionWindow.observeSubject(nil)
            updateSlabLabelPromptIfDue(at: now)
            return
        }

        slabFooterTextSince = nil
        slabFooterTextPromptID = nil
        if let confirmed = slabFooterRecognitionWindow.observeSubject(
            ScanSubject(identifier: footerIdentifier)
        ), confirmed.identifier.suppressionKey == footerKey,
           slabFooterRecognizedKey != footerKey {
            slabFooterRecognizedKey = footerKey
            PerformanceSignpost.emitEvent(
                "slabFooterRecognitionConfirmed",
                "observation=\(slabRecognitionID?.uuidString ?? "none") footer=two-of-four"
            )
            DispatchQueue.main.async { [weak self] in
                self?.onSlabFooterRecognized?()
            }
        }

        let stableFooterKey = activeSlabBaseIdentifier ?? slabAwaitingFooterKey
        if let stableFooterKey {
            guard stableFooterKey != footerKey else {
                slabFooterIdentityConfirmationWindow.reset()
                return
            }
            guard let confirmedFooter = slabFooterIdentityConfirmationWindow.observeSubject(
                ScanSubject(identifier: footerIdentifier)
            ), confirmedFooter.identifier.suppressionKey == footerKey else { return }

            clearActiveSlab(cause: .identityChanged, at: now)
            slabLabelPromptID = UUID()
            updateUI { $0.setSlabLabelReadPrompt(nil) }
            slabAwaitingFooterKey = footerKey
            slabFooterRecognizedKey = footerKey
            let recognitionID = UUID()
            slabRecognitionID = recognitionID
            PerformanceSignpost.emitEvent(
                "slabFooterIdentityChanged",
                "observation=\(recognitionID.uuidString) footer=confirmed"
            )
            return
        }

        if slabAwaitingFooterKey == nil {
            slabLabelPromptID = UUID()
            PerformanceSignpost.emitEvent(
                "slabFooterIdentityEstablished",
                "observation=\(slabRecognitionID?.uuidString ?? "none") footer=initial"
            )
        }
        slabAwaitingFooterKey = footerKey
    }

    private func detectSlabLabelIfDue(
        handler: VNImageRequestHandler,
        sourceSize: CGSize,
        footerHasText: Bool,
        at now: CFAbsoluteTime
    ) {
        guard shouldReadSlabLabel(at: now, footerHasText: footerHasText) else {
            updateSlabLabelPromptIfDue(at: now)
            return
        }
        cadence.markRan(.label, at: now)
        beginSlabLabelReadPromptIfNeeded(at: now)
        slabLabelReadSequence += 1
        do {
#if DEBUG
            labelOCRReadCount += 1
#endif
            let labelID = PerformanceSignpost.makeID()
            let labelState = PerformanceSignpost.beginInterval(
                "labelOCR",
                id: labelID,
                "encounter=\(latchEncounterID?.uuidString ?? "none")"
            )
            defer {
                PerformanceSignpost.endInterval(
                    "labelOCR",
                    labelState,
                    "encounter=\(latchEncounterID?.uuidString ?? "none")"
                )
            }
            try handler.perform([labelRequest])
            let lines = recognizedLines(
                from: labelRequest,
                roi: labelRequest.regionOfInterest,
                sourceSize: sourceSize
            )
#if DEBUG
            if Self.isGradedLabelCaptureDebugRoute {
                let raw = lines.map(\.text).joined(separator: " | ")
                let output = raw.isEmpty ? "<no text>" : raw
                print("[GradedLabelCapture] \(output)")
            }
#endif
            let evidence = GradedLabelParser.parse(lines)
            PerformanceSignpost.emitEvent(
                "slabLabelRead",
                "observation=\(slabRecognitionID?.uuidString ?? "none") attempt=\(slabLabelReadSequence) result=\(evidence == nil ? "miss" : "parsed")"
            )
            _ = applySlabLabelEvidence(
                evidence,
                baseIdentifier: activeSlabBaseIdentifier ?? slabAwaitingFooterKey,
                at: now
            )
            updateSlabLabelPromptIfDue(at: now)
        } catch {
            PerformanceSignpost.emitEvent(
                "slabLabelRead",
                "observation=\(slabRecognitionID?.uuidString ?? "none") attempt=\(slabLabelReadSequence) result=error"
            )
            _ = slabEvidenceWindow.observe(nil)
            certifiedCopyWindow.reset()
            certifiedCopyCandidate = nil
            if let activeSlab, activeSlab.evidence.certificationNumber == nil {
                certlessLabelMisses += 1
            }
            updateSlabLabelPromptIfDue(at: now)
        }
    }

    private func shouldReadSlabLabel(
        at now: CFAbsoluteTime,
        footerHasText: Bool
    ) -> Bool {
        let currentFooterKey = activeSlabBaseIdentifier ?? slabAwaitingFooterKey
        return SlabLabelSchedule.shouldReadLabel(
            mode: subjectMode,
            footerHasText: footerHasText,
            hasStableFooterIdentity: currentFooterKey != nil,
            hasEvidence: activeSlab != nil,
            certKnown: activeSlab?.evidence.certificationNumber != nil,
            lastLabelAt: cadence.lastLabelAt,
            now: now,
            needsFastFollowUp: certifiedCopyCandidate != nil,
            certlessBackoff: certlessLabelMisses >= 3
        )
    }

    private func beginSlabLabelReadPromptIfNeeded(at now: CFAbsoluteTime) {
        guard activeSlab == nil,
              slabAwaitingFooterKey != nil,
              slabAwaitingLabelSince == nil else { return }
        slabAwaitingLabelSince = now
        let id = slabLabelPromptID ?? UUID()
        slabLabelPromptID = id
        updateUI {
            $0.setSlabLabelReadPrompt(
                SlabLabelReadPrompt(id: id, stage: .readingLabel)
            )
        }
    }

    @discardableResult
    private func applySlabLabelEvidence(
        _ evidence: GradedSlabEvidence?,
        baseIdentifier: ScanSuppressionKey? = nil,
        at now: CFAbsoluteTime
    ) -> GradedSlabEvidence? {
        guard subjectMode == .slab else { return nil }
        guard let baseIdentifier else {
            _ = slabEvidenceWindow.observe(nil)
            return nil
        }
        guard (activeSlabBaseIdentifier ?? slabAwaitingFooterKey) == baseIdentifier else {
            return nil
        }
        if let activeEvidence = activeSlab?.evidence {
            guard let evidence else {
                slabEvidenceWindow.reset()
                certifiedCopyWindow.reset()
                certifiedCopyCandidate = nil
                if activeEvidence.certificationNumber == nil { certlessLabelMisses += 1 }
                return nil
            }

            if SlabEvidenceConfirmationWindow.isDistinctCertifiedCopy(
                from: activeEvidence,
                to: evidence
            ) {
                if certifiedCopyCandidate != evidence.certificationNumber {
                    certifiedCopyWindow.reset()
                    certifiedCopyCandidate = evidence.certificationNumber
                }
                guard let confirmed = certifiedCopyWindow.observe(evidence) else { return nil }
                replaceActiveSlabWithCertifiedCopy(confirmed)
                return confirmed
            }
            certifiedCopyWindow.reset()
            certifiedCopyCandidate = nil

            // Once admitted, two visually identical certless slabs cannot be
            // distinguished by a later label read. Preserve the saved row and
            // require a deliberate new-copy action instead of assigning the
            // other copy's certificate to it.
            guard latch.latched == nil,
                  SlabEvidenceConfirmationWindow.isCertificateRefinement(
                      from: activeEvidence,
                      to: evidence
                  ) else {
                slabEvidenceWindow.reset()
                if activeEvidence.certificationNumber == nil { certlessLabelMisses += 1 }
                return nil
            }
            guard let confirmed = slabEvidenceWindow.observe(evidence) else { return nil }
            if SlabEvidenceConfirmationWindow.isCertificateRefinement(
                from: activeEvidence,
                to: confirmed
            ) {
                refineActiveSlabCertificate(confirmed)
            }
            return confirmed
        }

        guard let confirmed = slabEvidenceWindow.observe(evidence) else { return nil }
        activateSlab(confirmed, baseIdentifier: baseIdentifier)
        return confirmed
    }

    private func updateSlabLabelPromptIfDue(at now: CFAbsoluteTime) {
        guard subjectMode == .slab, activeSlab == nil else { return }

        if slabAwaitingFooterKey != nil,
           let startedAt = slabAwaitingLabelSince,
           let id = slabLabelPromptID,
           now - startedAt >= Self.slabLabelOfferDelay {
            updateUI {
                $0.setSlabLabelReadPrompt(
                    SlabLabelReadPrompt(id: id, stage: .labelNotFound)
                )
            }
            return
        }

        guard slabAwaitingFooterKey == nil,
              let startedAt = slabFooterTextSince,
              let id = slabFooterTextPromptID,
              now - startedAt >= Self.slabLabelOfferDelay else { return }
        updateUI {
            $0.setSlabLabelReadPrompt(
                SlabLabelReadPrompt(id: id, stage: .findingCardNumber)
            )
        }
    }

    private func armPostCommitLabelWatchIfNeeded(encounterID: UUID, at now: CFAbsoluteTime) {
        guard subjectMode == .raw,
              confirmationContext?.purpose == .collection,
              confirmationContext?.subjectMode == .raw else {
            postCommitLabelWatch = nil
            return
        }
        postCommitLabelWatch = PostCommitLabelWatch(
            encounterID: encounterID,
            startedAt: now,
            purpose: .collection
        )
    }

    private func shouldReadPostCommitLabel(
        at now: CFAbsoluteTime,
        footerIdentifier: ScanIdentifier?
    ) -> Bool {
        guard let watch = postCommitLabelWatch,
              let footerIdentifier,
              subjectMode == .raw,
              latchEncounterID == watch.encounterID,
              latch.latched?.identifier.suppressionKey == footerIdentifier.suppressionKey,
              watch.labelReads < Self.postCommitMaximumLabelReads,
              now - watch.startedAt >= Self.postCommitFirstLabelDelay,
              watch.lastLabelAt.map({ now - $0 >= Self.postCommitLabelInterval }) ?? true else {
            return false
        }
        return true
    }

    private func acceptPostCommitLabelEvidence(
        _ evidence: GradedSlabEvidence?,
        footerIdentifier: ScanIdentifier?,
        at now: CFAbsoluteTime
    ) {
        guard shouldReadPostCommitLabel(at: now, footerIdentifier: footerIdentifier),
              var watch = postCommitLabelWatch else { return }
        watch.labelReads += 1
        watch.lastLabelAt = now
#if DEBUG
        labelOCRReadCount += 1
#endif
        if let confirmed = watch.evidenceWindow.observe(evidence) {
            postCommitLabelWatch = nil
            DispatchQueue.main.async { [weak self] in
                self?.onPostCommitSlabEvidence?(watch.encounterID, confirmed)
            }
            return
        }
        if watch.labelReads >= Self.postCommitMaximumLabelReads {
            postCommitLabelWatch = nil
        } else {
            postCommitLabelWatch = watch
        }
    }

    private func detectPostCommitLabelIfDue(
        handler: VNImageRequestHandler,
        sourceSize: CGSize,
        footerIdentifier: ScanIdentifier?,
        at now: CFAbsoluteTime
    ) {
        guard shouldReadPostCommitLabel(at: now, footerIdentifier: footerIdentifier) else {
            return
        }
        labelRequest.regionOfInterest = SlabFramingRegion.bootstrapLabelVisionRect
        do {
            let labelID = PerformanceSignpost.makeID()
            let labelState = PerformanceSignpost.beginInterval(
                "labelOCR",
                id: labelID,
                "encounter=\(latchEncounterID?.uuidString ?? "none")"
            )
            defer {
                PerformanceSignpost.endInterval(
                    "labelOCR",
                    labelState,
                    "encounter=\(latchEncounterID?.uuidString ?? "none")"
                )
            }
            try handler.perform([labelRequest])
            let lines = recognizedLines(
                from: labelRequest,
                roi: labelRequest.regionOfInterest,
                sourceSize: sourceSize
            )
#if DEBUG
            if Self.isGradedLabelCaptureDebugRoute {
                let raw = lines.map(\.text).joined(separator: " | ")
                print("[GradedLabelCapture] \(raw.isEmpty ? "<no text>" : raw)")
            }
#endif
            acceptPostCommitLabelEvidence(
                GradedLabelParser.parse(lines),
                footerIdentifier: footerIdentifier,
                at: now
            )
        } catch {
            acceptPostCommitLabelEvidence(nil, footerIdentifier: footerIdentifier, at: now)
        }
    }

#if DEBUG
    /// Drains the serial Vision queue after a lifecycle fence. Test code uses
    /// this instead of sleeping, so assertions observe the same ordering as a
    /// real frame callback.
    func drainVisionQueueForTesting() {
        visionQueue.sync {}
    }

    /// Drains the profile compiler and its ordered installation hop. This lets
    /// tests assert the same queue ordering as a live catalog activation without
    /// sleeping or putting regex construction on the Vision queue.
    func drainProfileQueuesForTesting() {
        profileQueue.sync {}
        visionQueue.sync {}
    }

    /// Test-only view of the OCR vocabulary installed on the active Vision
    /// request.
    var customWordsForTesting: [String] {
        visionQueue.sync { footerRequest.customWords }
    }

    /// Test-only parser boundary using the profile installed on the Vision
    /// queue. Production frame handling calls the same profile value.
    func recognitionOutcomeForTesting(_ lines: [String]) -> RecognitionOutcome {
        visionQueue.sync { profile.identify(lines) }
    }

    /// Feeds one parsed observation through the production confirmation window.
    /// It intentionally omits latch and camera side effects so the test can focus
    /// on whether an activation joins or separates the four-frame window.
    @discardableResult
    func observeConfirmationForTesting(_ lines: [String]) -> ScanSubject? {
        visionQueue.sync {
            guard case let .identified(subject) = profile.identify(lines) else {
                return confirmationWindow.observeSubject(nil)
            }
            return confirmationWindow.observeSubject(subject)
        }
    }

    /// Test-only visibility for the non-blocking graded correction contract.
    /// Production UI never needs to know whether recognition is paused; tests do
    /// need to prove that this path never entered the pause state.
    var isRecognitionPausedForTesting: Bool {
        visionQueue.sync { isPaused }
    }

    var subjectModeForTesting: ScanSubjectMode {
        visionQueue.sync { subjectMode }
    }

    var labelOCRReadCountForTesting: Int {
        visionQueue.sync { labelOCRReadCount }
    }

    var isPostCommitLabelWatchArmedForTesting: Bool {
        visionQueue.sync { postCommitLabelWatch != nil }
    }

    /// Test/support seam for the state transition after Vision has produced a
    /// parsed label. The capture path above uses the same cadence gate and
    /// evidence application helpers; this avoids manufacturing a camera frame
    /// just to exercise the bootstrap that a simulator cannot reach naturally.
    @discardableResult
    func receiveSlabLabelEvidenceForTesting(
        _ evidence: GradedSlabEvidence?,
        footerHasText: Bool,
        for identifier: ScanIdentifier? = nil,
        at now: CFAbsoluteTime
    ) -> GradedSlabEvidence? {
        let outcome: RecognitionOutcome = identifier.map {
            .identified(ScanSubject(identifier: $0))
        } ?? .nothing
        updateActiveSlabPresence(
            outcome: outcome,
            historicalSubject: nil,
            footerLines: footerHasText ? [RecognizedLine(text: "footer")] : [],
            at: now
        )
        guard shouldReadSlabLabel(at: now, footerHasText: footerHasText) else {
            updateSlabLabelPromptIfDue(at: now)
            return nil
        }
        cadence.markRan(.label, at: now)
        beginSlabLabelReadPromptIfNeeded(at: now)
#if DEBUG
        labelOCRReadCount += 1
#endif
        let confirmed = applySlabLabelEvidence(
            evidence,
            baseIdentifier: activeSlabBaseIdentifier ?? slabAwaitingFooterKey,
            at: now
        )
        updateSlabLabelPromptIfDue(at: now)
        return confirmed
    }

    /// Debug-only seam for the production label-parser boundary.
    @discardableResult
    func receiveSlabLabelLinesForTesting(
        _ lines: [RecognizedLine],
        footerHasText: Bool,
        for identifier: ScanIdentifier? = nil,
        at now: CFAbsoluteTime
    ) -> GradedSlabEvidence? {
        let outcome: RecognitionOutcome = identifier.map {
            .identified(ScanSubject(identifier: $0))
        } ?? .nothing
        updateActiveSlabPresence(
            outcome: outcome,
            historicalSubject: nil,
            footerLines: footerHasText ? [RecognizedLine(text: "footer")] : [],
            at: now
        )
        guard shouldReadSlabLabel(at: now, footerHasText: footerHasText) else {
            updateSlabLabelPromptIfDue(at: now)
            return nil
        }
        cadence.markRan(.label, at: now)
        beginSlabLabelReadPromptIfNeeded(at: now)
#if DEBUG
        labelOCRReadCount += 1
#endif
        let confirmed = applySlabLabelEvidence(
            GradedLabelParser.parse(lines),
            baseIdentifier: activeSlabBaseIdentifier ?? slabAwaitingFooterKey,
            at: now
        )
        updateSlabLabelPromptIfDue(at: now)
        return confirmed
    }

    /// Debug-only seam for the sticky footer identity rule. It mirrors the
    /// production update with a tiny value input so tests can prove that a
    /// routine label re-confirmation does not erase the baseline.
    func receiveSlabFooterPresenceForTesting(
        identifier: ScanIdentifier?,
        hasText: Bool,
        at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) {
        let outcome: RecognitionOutcome = identifier.map {
            .identified(ScanSubject(identifier: $0))
        } ?? .nothing
        updateActiveSlabPresence(
            outcome: outcome,
            historicalSubject: nil,
            footerLines: hasText ? [RecognizedLine(text: "footer")] : [],
            at: now
        )
    }

    /// Debug-only seam for the shared production transition reached when a
    /// frame-level tracker pass has no observation or falls below confidence.
    /// It deliberately calls the same loss handler used by `trackCurrentFrame`.
    func receiveTrackerContinuityLossForTesting() {
        markTrackerContinuityLost()
    }

    /// Debug-only seam for the footer confirmation gate. It runs the real
    /// frame outcome path without manufacturing a camera pixel buffer.
    func receiveFooterOutcomeForTesting(
        _ outcome: RecognitionOutcome,
        footerHasText: Bool = true,
        at now: CFAbsoluteTime
    ) {
        handleFooterOutcome(
            outcome,
            footerLines: footerHasText ? [RecognizedLine(text: "footer")] : [],
            historicalSubject: nil,
            at: now,
            pixelBuffer: nil
        )
    }

    @discardableResult
    func receivePostCommitSlabEvidenceForTesting(
        _ evidence: GradedSlabEvidence?,
        footerIdentifier: ScanIdentifier?,
        at now: CFAbsoluteTime
    ) -> Bool {
        guard shouldReadPostCommitLabel(at: now, footerIdentifier: footerIdentifier) else { return false }
        acceptPostCommitLabelEvidence(evidence, footerIdentifier: footerIdentifier, at: now)
        return true
    }

    /// Debug-only seam for the historical-attempt bound. It calls the same
    /// bookkeeping the frame path uses, without manufacturing a camera frame.
    @discardableResult
    func advanceHistoricalAttemptForTesting(
        _ number: PokemonPrintedNumberEvidence,
        at now: CFAbsoluteTime
    ) -> Bool {
        visionQueue.sync { advanceHistoricalAttempt(for: number, at: now) }
    }

    var latchedSubjectForTesting: ScanSubject? {
        latch.latched
    }

    var activeSlabEvidenceForTesting: GradedSlabEvidence? {
        activeSlab?.evidence
    }

    var lastSlabLabelReadAtForTesting: CFAbsoluteTime? {
        cadence.lastLabelAt
    }

    var footerRegionOfInterestForTesting: CGRect {
        footerRequest.regionOfInterest
    }

    var titleRegionOfInterestForTesting: CGRect {
        titleRequest.regionOfInterest
    }
#endif

#if DEBUG
    private static var isGradedLabelCaptureDebugRoute: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_route"),
              arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "GradedLabelCapture"
    }
#endif

    /// Whether this frame may run the title pass, and the attempt bookkeeping
    /// that decides it. Callers must be on `visionQueue`.
    ///
    /// An exhausted attempt is deliberately kept rather than cleared. Clearing
    /// it let the very next frame build a fresh attempt with `retryCount` 0 and
    /// `startedAt` set to that frame, which put both the retry cap and the TTL
    /// permanently out of reach: the cap skipped one frame in seven and the TTL
    /// never elapsed. The TTL is now the only thing that starts a new attempt.
    private func advanceHistoricalAttempt(
        for number: PokemonPrintedNumberEvidence,
        at now: CFAbsoluteTime
    ) -> Bool {
        var retainedTitleCandidates: Set<String> = []
        if let attempt = historicalAttempt,
           attempt.number != number || now - attempt.startedAt > Self.historicalAttemptTTL {
            let sameNumberInSlabMode = subjectMode == .slab && attempt.number == number
            if sameNumberInSlabMode {
                // A slab takes longer to resolve than a raw card. Renew the
                // bounded title-read budget for the same printed number, but
                // preserve any useful title evidence and the confirmation
                // progress already earned by the slab footer.
                retainedTitleCandidates = attempt.titleCandidates
            }
            historicalAttempt = nil
            if !sameNumberInSlabMode {
                resetConfirmationWindow()
            }
        }

        if historicalAttempt == nil {
            historicalAttempt = HistoricalEvidenceRequest(
                id: UUID(),
                number: number,
                startedAt: now,
                lastObservedAt: now,
                retryCount: 0,
                titleCandidates: retainedTitleCandidates
            )
        }

        guard var attempt = historicalAttempt,
              attempt.retryCount < Self.historicalAttemptLimit else { return false }

        attempt.retryCount += 1
        attempt.lastObservedAt = now
        historicalAttempt = attempt
        return true
    }

    /// Creates or advances a short-lived historical attempt and reads the title
    /// from the same pixel buffer. A number must be visible again on every retry,
    /// which prevents a stale footer from being joined to the next physical card.
    private func historicalIdentifier(
        for number: PokemonPrintedNumberEvidence,
        footerLines: [RecognizedLine],
        handler: VNImageRequestHandler,
        sourceSize: CGSize,
        at now: CFAbsoluteTime
    ) -> ScanIdentifier? {
        guard PokemonHistoricalIdentityResolver.canAttempt(number) else {
            historicalAttempt = nil
            return nil
        }
        if subjectMode == .slab,
           let attempt = historicalAttempt,
           attempt.number == number,
           !attempt.titleCandidates.isEmpty {
            // One successful title read is enough to begin catalog prefetch.
            // Re-running title OCR on every footer frame added cost without
            // changing the historical identity for a held slab.
            return .pokemonHistorical(
                PokemonHistoricalScanEvidence(
                    number: number,
                    titleCandidates: attempt.titleCandidates.sorted()
                )
            )
        }
        guard advanceHistoricalAttempt(for: number, at: now) else { return nil }

        do {
            let titleID = PerformanceSignpost.makeID()
            let titleState = PerformanceSignpost.beginInterval(
                "titleOCR",
                id: titleID,
                "encounter=\(latchEncounterID?.uuidString ?? "none")"
            )
            defer {
                PerformanceSignpost.endInterval(
                    "titleOCR",
                    titleState,
                    "encounter=\(latchEncounterID?.uuidString ?? "none")"
                )
            }
            try handler.perform([titleRequest])
            let titleLines = recognizedLines(
                from: titleRequest,
                roi: titleRequest.regionOfInterest,
                sourceSize: sourceSize
            )
            if case let .pokemonHistorical(evidence)? = PokemonHistoricalScanParser.parse(
                number: number,
                titleLines: titleLines.map(\.text),
                excludingFooter: PokemonHistoricalScanParser.footerSignature(from: footerLines.map(\.text))
            ) {
                historicalAttempt?.titleCandidates.formUnion(evidence.titleCandidates)
            }
        } catch {
            // A failed secondary request is a miss. Footer recognition remains
            // authoritative and the next matching frame may retry.
        }
        guard let attempt = historicalAttempt,
              !attempt.titleCandidates.isEmpty else { return nil }
        return .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: number,
                titleCandidates: attempt.titleCandidates.sorted()
            )
        )
    }

    /// Speculation, and only speculation. The catalog de-duplicates, so an
    /// identifier that flickers in and out costs at most one request.
    private func announcePlausible(_ observation: ScanSubject?, at now: CFAbsoluteTime) {
        guard let observation,
              observation.suppressionKey != catalogMissSuppressionKey,
              observation != lastAnnouncedPlausible else { return }
        lastAnnouncedPlausible = observation
        cadence.prioritizeOCR(at: now, after: 0.08)
        PerformanceSignpost.signposter.emitEvent("firstPlausibleReading")
        DispatchQueue.main.async { [weak self] in
            self?.onPlausibleCandidate?(observation)
        }
    }

    private func announceLatchHoldIfNeeded() {
        guard !didAnnounceLatchHold,
              latch.heldMatchCount >= Self.latchHoldHintMatches,
              let latched = latch.latched else { return }

        didAnnounceLatchHold = true
        recordDiagnostic("heldDuplicateOffer")
        let encounterID = latchEncounterID
        DispatchQueue.main.async { [weak self] in
            self?.onLatchHolding?(latched, encounterID)
        }
    }

    private func emitLatchRelease(
        encounterID: UUID?,
        suppressionKey: ScanSuppressionKey
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onLatchReleased?(encounterID, suppressionKey)
        }
    }

    /// Callers must be on `visionQueue`.
    private func resetConfirmationWindow() {
        confirmationWindow.reset()
        lastAnnouncedPlausible = nil
    }

    /// Callers must be on `visionQueue`.
    private func resetObservationState() {
        resetConfirmationWindow()
        latch.releaseAndForget()
        cancelHeldRepeatAuthorizationOnVisionQueue()
        clearActiveSlab(cause: .lifecycle)
        latchEncounterID = nil
        didAnnounceLatchHold = false
        historicalAttempt = nil
    }

    private func recordDiagnostic(_ event: String) {
#if DEBUG
        diagnosticEvents.append(event)
        if diagnosticEvents.count > 64 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 64)
        }
#endif
    }

    private func setCameraIssue(_ issue: CameraIssue?) {
        updateUI { $0.setCameraIssue(issue) }
    }

    private func updateAssistance(from lines: [RecognizedLine]) {
        let metrics = AssistanceTextMetrics(
            textPixelHeight: lines.compactMap { $0.sourcePixelRect.map { Float($0.height) } }.max(),
            meanOCRConfidence: {
                let confidences = lines.compactMap(\.confidence)
                return confidences.isEmpty
                    ? nil
                    : confidences.reduce(0, +) / Float(confidences.count)
            }(),
            hasFooterText: !lines.isEmpty
        )

        // `videoInput` belongs to sessionQueue. Sample the mutable device on
        // that queue, then hand immutable values back to visionQueue in the
        // same order as the OCR updates. This keeps focus/exposure guidance
        // fresh without synchronously blocking frame processing.
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let deviceState = AssistanceDeviceState(device: device)
            self.visionQueue.async { [weak self] in
                self?.applyAssistance(metrics: metrics, device: deviceState)
            }
        }
    }

    private func applyAssistance(
        metrics: AssistanceTextMetrics,
        device: AssistanceDeviceState
    ) {
        let assessment = CaptureAssessment(
            detailSharpness: nil,
            horizontalMotion: nil,
            verticalMotion: nil,
            textPixelHeight: metrics.textPixelHeight,
            localContrast: nil,
            clippedHighlightArea: nil,
            meanOCRConfidence: metrics.meanOCRConfidence,
            isAdjustingFocus: device.isAdjustingFocus,
            isAdjustingExposure: device.isAdjustingExposure,
            exposureDuration: device.exposureDuration,
            iso: device.iso,
            lensPosition: device.lensPosition,
            minimumFocusDistance: device.minimumFocusDistance
        )
        let assistance = assistanceMonitor.observe(
            assessment,
            hasFooterText: metrics.hasFooterText
        )
        updateUI { $0.setScanAssistance(assistance) }
    }
}

/// What the scanner recognises, as one value.
///
/// There is no game mode. A printed identifier is specific enough to say which
/// game it came from — `OBF 223/197` cannot be a Magic footer and `ECL • 0218 •
/// EN` cannot be a Pokémon one — so asking the user to pick first was asking for
/// information the card already carries.
struct RecognitionProfile: Sendable {
    /// The active Pokémon vocabulary and its immutable catalog snapshot.
    let pokemon: PokemonScanProfile
    /// `nil` only before the Magic set directory is installed. Pokémon needs no
    /// counterpart because the bundled seed is always available.
    let magic: MagicScanProfile?

    init(
        pokemon: PokemonScanProfile = .bundledSeed,
        magic: MagicScanProfile? = nil
    ) {
        self.pokemon = pokemon
        self.magic = magic
    }

    static let pokemonOnly = RecognitionProfile(pokemon: .bundledSeed, magic: nil)

    /// Vision biases recognition toward these, so it carries both games'
    /// vocabularies at once. Deduplicated because a three-character code can
    /// legitimately belong to both directories.
    var customWords: [String] {
        ScanText.unique(pokemon.customWords + (magic?.customWords ?? []))
    }

    /// Both parsers, every frame.
    ///
    /// Exactly one result is an identification. Two is a frame claiming to be two
    /// different cards, which is rejected rather than ranked — the same rule that
    /// already governs two Pokémon identifiers in one frame. A later pass will
    /// almost always resolve it, and a wrong entry costs far more than a wait.
    func identify(_ lines: [String]) -> RecognitionOutcome {
        identify(lines.map { RecognizedLine(text: $0) })
    }

    func identify(_ lines: [RecognizedLine]) -> RecognitionOutcome {
        let text = lines.map(\.text)
        let pokemonResult = self.pokemon.parse(text)
        let magicOutcome = magic?.parseOutcome(lines) ?? .nothing

        switch (pokemonResult, magicOutcome) {
        case (nil, .nothing):
            return .nothing
        case let (identifier?, .nothing):
            return .identified(ScanSubject(identifier: identifier))
        case let (nil, .identified(identifier)):
            return .identified(ScanSubject(identifier: identifier))
        case (_?, .identified(_)):
            return .ambiguous
        case (nil, .spatiallyRejectedCollector):
            return .spatiallyRejectedMagicCollector
        case let (identifier?, .spatiallyRejectedCollector):
            // Preserve modern Pokemon recognition if it independently earned an
            // identity; the rejected Magic-shaped reading is then irrelevant.
            return .identified(ScanSubject(identifier: identifier))
        }
    }
}

enum RecognitionOutcome: Equatable {
    case nothing
    case identified(ScanSubject)
    case spatiallyRejectedMagicCollector
    /// Both games produced a valid identifier from one frame.
    case ambiguous
}

extension CardScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    private func recognizedLines(
        from request: VNRecognizeTextRequest,
        roi: CGRect,
        sourceSize: CGSize
    ) -> [RecognizedLine] {
        (request.results ?? []).compactMap { observation in
            let candidates = observation.topCandidates(3)
            guard let candidate = candidates.first else { return nil }
            let fullFrame = CardFramingRegion.fullFrameVisionRect(
                fromObservationBoundingBox: observation.boundingBox,
                in: roi
            )
            return RecognizedLine(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence,
                alternatives: candidates.dropFirst().map(\.string),
                sourcePixelRect: CGRect(
                    x: fullFrame.minX * sourceSize.width,
                    y: fullFrame.minY * sourceSize.height,
                    width: fullFrame.width * sourceSize.width,
                    height: fullFrame.height * sourceSize.height
                )
            )
        }
    }

    /// A frame that cannot be described. Routed through the existing catch so a
    /// malformed buffer counts as absence evidence for the latch and the
    /// confirmation window, exactly like a failed Vision pass.
    private enum CameraFrameError: Error {
        case missingFormatDescription
        case missingImageBuffer
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        PerformanceSignpost.emitEvent(
            "frameReceived",
            latchEncounterID?.uuidString ?? "none"
        )
        let rotationAngle = rotation.currentAngle
        let orientation = CardFramingRegion.imageOrientation(forRotationAngle: rotationAngle)

        // OCR owns a simultaneous due frame. Tracking is still allowed on
        // non-OCR frames, including while OCR is paused for a user choice.
        guard let work = cadence.nextVisionWork(at: now, ocrAllowed: !isPaused) else {
            return
        }

        do {
            // A frame with no image buffer is a bad frame, not a non-event. It
            // has already consumed its cadence slot, so returning here silently
            // skipped the absence evidence every other failed frame produces.
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw CameraFrameError.missingImageBuffer
            }

            if work == .tracking {
                let trackingState = PerformanceSignpost.signposter.beginInterval("tracking")
                defer { PerformanceSignpost.signposter.endInterval("tracking", trackingState) }
                trackCurrentFrame(
                    pixelBuffer: pixelBuffer,
                    orientation: orientation,
                    at: now
                )
                return
            }

            let handler = VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: orientation,
                options: [:]
            )
            let footerState = PerformanceSignpost.beginInterval(
                "footerOCR",
                id: PerformanceSignpost.makeID(),
                "encounter=\(latchEncounterID?.uuidString ?? "none")"
            )
            do {
                defer {
                    PerformanceSignpost.endInterval(
                        "footerOCR",
                        footerState,
                        "encounter=\(latchEncounterID?.uuidString ?? "none")"
                    )
                }
                try handler.perform([footerRequest])
            }

            // Guarded like every other optional on this path. A buffer that
            // already yielded an image buffer will essentially always carry a
            // format description, but this is a nullable C API on the frame
            // path and a trap here is not catchable by the enclosing `do`.
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw CameraFrameError.missingFormatDescription
            }
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            // Vision measures the upright image, so the sensor's landscape
            // width/height swap for a quarter turn and stay put for a half turn.
            let sourceSize = CardFramingRegion.visionSourceSize(
                forRotationAngle: rotationAngle,
                sensorWidth: Int(dimensions.width),
                sensorHeight: Int(dimensions.height)
            )
            let parseID = PerformanceSignpost.makeID()
            let parseState = PerformanceSignpost.beginInterval(
                "footerParse",
                id: parseID,
                "encounter=\(latchEncounterID?.uuidString ?? "none")"
            )
            let lines: [RecognizedLine]
            let outcome: RecognitionOutcome
            do {
                defer {
                    PerformanceSignpost.endInterval(
                        "footerParse",
                        parseState,
                        "encounter=\(latchEncounterID?.uuidString ?? "none")"
                    )
                }
                lines = recognizedLines(
                    from: footerRequest,
                    roi: footerRequest.regionOfInterest,
                    sourceSize: sourceSize
                )
                updateAssistance(from: lines)
                outcome = profile.identify(lines)
            }
            var historical: ScanIdentifier?
            if let number = HistoricalTitleRequestPolicy.number(for: outcome, footerLines: lines) {
                historical = historicalIdentifier(
                    for: number,
                    footerLines: lines,
                    handler: handler,
                    sourceSize: sourceSize,
                    at: now
                )
            } else if case .nothing = outcome {
                historicalAttempt = nil
            }

#if DEBUG
            let boxes = footerRequest.results?.map(\.boundingBox) ?? []
            updateDebugVisionOverlay(boxes)
#endif

            let footerIdentifier: ScanIdentifier? = switch outcome {
            case let .identified(subject): subject.identifier
            case .nothing, .ambiguous, .spatiallyRejectedMagicCollector:
                historical
            }

            let historicalSubject = historical.map {
                ScanSubject(identifier: $0, slab: activeSlabEvidence(matching: $0))
            }
            // Slab mode establishes footer-key ownership before parsing label
            // evidence. In Raw mode this remains a no-op and no label OCR runs
            // until a raw encounter has committed.
            updateActiveSlabPresence(
                outcome: outcome,
                historicalSubject: historicalSubject,
                footerLines: lines,
                at: now
            )
            handleFooterOutcome(
                outcome,
                footerLines: lines,
                historicalSubject: historical.map {
                    ScanSubject(identifier: $0, slab: activeSlabEvidence(matching: $0))
                },
                at: now,
                pixelBuffer: pixelBuffer,
                didUpdateSlabPresence: true
            )
            // Keep footer confirmation and latch transitions ahead of the
            // larger label pass. Slab evidence becomes eligible on the next
            // footer frame after the label has earned confirmation.
            detectSlabLabelIfDue(
                handler: handler,
                sourceSize: sourceSize,
                footerHasText: !lines.isEmpty,
                at: now
            )
            detectPostCommitLabelIfDue(
                handler: handler,
                sourceSize: sourceSize,
                footerIdentifier: footerIdentifier,
                at: now
            )
        } catch {
#if DEBUG
            updateDebugVisionOverlay([])
#endif
            // A bad frame is expected occasionally. Run it through the normal
            // pipeline as a miss so it counts as absence evidence for the latch
            // as well as the confirmation window, then let the next frame try.
            historicalAttempt = nil
            handleFooterOutcome(
                .nothing,
                footerLines: [],
                historicalSubject: nil,
                at: now,
                pixelBuffer: nil
            )
        }
    }
}
