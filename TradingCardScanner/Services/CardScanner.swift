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

#if DEBUG
    /// Calibration switch for the first on-device run.
    ///
    /// Set this to `true` to widen Vision's ROI to the whole frame for one build.
    /// That matters because if `metadataRect(fromVisionRect:rotationAngle:)` has the rotation
    /// backwards, the normal ROI points at the wrong end of the card, Vision finds
    /// no text there, and the debug overlay draws nothing — no signal in exactly the
    /// case the overlay exists to diagnose. With the full frame, Vision reports text
    /// everywhere and the green boxes reveal the true mapping immediately.
    ///
    /// Set it back to `false` once the transform is confirmed.
    static let calibrationUsesFullFrameROI = false
#endif

    /// The ROI actually handed to Vision. Observation bounding boxes are normalized
    /// against *this* rect, not the full frame.
    static var activeVisionROI: CGRect {
#if DEBUG
        return calibrationUsesFullFrameROI ? fullFrameRect : visionRect
#else
        return visionRect
#endif
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
    private(set) var presentation: PresentationState = .unknown
    private var stableObservationCount = 0
    private var candidateIssue: OpticalIssue = .none
    private var candidateCount = 0

    mutating func observe(_ assessment: CaptureAssessment, hasFooterText: Bool) -> ScanAssistance {
        if hasFooterText {
            stableObservationCount += 1
            presentation = stableObservationCount >= 2 ? .cardStable : .cardEntering
        } else {
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

final class CardScanner: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var cameraIssue: CameraIssue?
    @Published private(set) var lens: CameraLens = .standard
    /// Only the lenses this particular device actually has. An iPhone SE has no
    /// ultra wide, so the toggle must not offer one.
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var scanAssistance: ScanAssistance = .none
#if DEBUG
    @Published private(set) var debugVisionBoxes: [CGRect] = []
#endif

    /// A plausible identifier or historical evidence key has been read once.
    /// Not yet trusted, and never
    /// allowed to touch the collection — this exists so a catalog request can be
    /// in flight while Vision is still looking for its second matching pass.
    var onPlausibleCandidate: ((ScanIdentifier) -> Void)?
    /// Identity is established: confirmed across OCR passes and admitted by the
    /// latch as a new physical presentation.
    var onConfirmedCandidate: ((ScanIdentifier) -> Void)?
    /// The same printing has been sitting in the band since it was consumed.
    /// Fires once per latch so the UI can explain the one case the latch cannot
    /// tell apart: a second identical copy dropped in without a gap.
    var onLatchHolding: ((ScanIdentifier) -> Void)?

    /// Which way the sensor is currently held. Read by the preview layer and by
    /// every Vision pass, so overlays and recognition share one answer.
    let rotation = CameraRotationTracker()

    private let sessionQueue = DispatchQueue(label: "cards.camera.session")
    private let visionQueue = DispatchQueue(label: "cards.camera.vision", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let footerRequest = VNRecognizeTextRequest()
    private let titleRequest = VNRecognizeTextRequest()

    private var isConfigured = false
    private var isPaused = false
    private var videoInput: AVCaptureDeviceInput?
    /// Written on `sessionQueue`; `lens` is the main-thread mirror for the UI.
    private var currentLens: CameraLens = .standard
    private var lastVisionTime: CFAbsoluteTime = 0
    private var confirmationWindow = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)
    private var latch = CardLatch()
    private var didAnnounceLatchHold = false
    private var lastAnnouncedPlausible: ScanIdentifier?
    private var profile: RecognitionProfile = .pokemonOnly
    private var historicalAttempt: HistoricalEvidenceRequest?
    private var assistanceMonitor = CaptureAssistanceMonitor()
    private static let historicalAttemptTTL: CFAbsoluteTime = 1.5
    private static let historicalAttemptLimit = 6


    /// Consecutive readings of an already-consumed card before the UI mentions it.
    /// Long enough that simply finishing a movement never triggers it.
    private static let latchHoldHintMatches = 8

    // This is a ceiling of about 4 OCR starts/sec. Actual throughput is whichever
    // is slower: this interval or Vision's synchronous .accurate processing time.
    private let minimumVisionInterval: CFAbsoluteTime = 0.24

    override init() {
        super.init()
        configureTextRequest()

        // Resolved from the cached hardware probe rather than queried per launch.
        let lenses: [CameraLens] = CameraCapabilities.hasMacroLens() ? [.standard, .macro] : [.standard]
        availableLenses = lenses

        // Macro is the default whenever the hardware has it. The standard lens
        // cannot focus close enough to resolve the identifier strip at all, so
        // starting there would mean every session opens on a blurry frame.
        let preferred = lenses.contains(.macro) ? CameraLens.macro : .standard
        lens = preferred
        currentLens = preferred
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
            configureAndStartIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.setCameraIssue(nil)
                    self.configureAndStartIfNeeded()
                } else {
                    self.setCameraIssue(.permissionDenied)
                }
            }
        default:
            setCameraIssue(.permissionDenied)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func pauseRecognition() {
        visionQueue.async { [weak self] in
            self?.isPaused = true
        }
    }

    func resumeRecognition() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.confirmationWindow.reset()
            self.isPaused = false
        }
    }

    /// Discards only evidence for the card currently being considered.
    ///
    /// Mode changes must require a fresh observation, but they must not erase
    /// the duplicate suppression memory for a card that was already consumed.
    func discardCurrentObservation() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.confirmationWindow.reset()
            self.historicalAttempt = nil
            self.lastAnnouncedPlausible = nil
            self.didAnnounceLatchHold = false
            self.isPaused = false
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
            self.confirmationWindow.reset()
            self.didAnnounceLatchHold = false
            self.lastAnnouncedPlausible = nil
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
        // Compiling the vocabulary regex is the expensive half; do it off the
        // frame queue.
        let magic = MagicScanProfile(definitions: definitions)

        visionQueue.async { [weak self] in
            guard let self, self.profile.magic?.definitions != magic.definitions else { return }
            self.profile = RecognitionProfile(magic: magic)
            self.footerRequest.customWords = self.profile.customWords
            self.resetObservationState()
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
        footerRequest.regionOfInterest = CardFramingRegion.visionRect

        titleRequest.recognitionLevel = .accurate
        titleRequest.recognitionLanguages = ["en-US"]
        titleRequest.usesLanguageCorrection = true
        titleRequest.regionOfInterest = CardFramingRegion.titleVisionRect
    }

    private func configureAndStartIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

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

            self.visionQueue.async { self.resetObservationState() }
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
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
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
        DispatchQueue.main.async { [weak self] in
            self?.lens = lens
        }
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
        historicalIdentifier: ScanIdentifier?,
        at now: CFAbsoluteTime
    ) {
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
        let parsed: ScanIdentifier?
        switch outcome {
        case let .identified(identifier):
            historicalAttempt = nil
            parsed = identifier
        case .nothing:
            parsed = historicalIdentifier
        case .ambiguous, .spatiallyRejectedMagicCollector:
            historicalAttempt = nil
            parsed = nil
        }

        // Whether the band is occupied, which is not the same question as
        // whether this frame produced an identifier. A card being moved is
        // legible-but-unparseable for most of the movement, and the latch must
        // not read that as the card having left.
        switch latch.observe(parsed, cardPresent: !footerLines.isEmpty, at: now) {
        case .holdingLatch:
            announceLatchHoldIfNeeded()

        case let .forward(observation):
            announcePlausible(observation)

            guard let confirmed = confirmationWindow.observe(observation) else { return }

            // Confirmed, but the same physical card may simply never have left.
            guard latch.admits(confirmed) else {
                confirmationWindow.reset()
                return
            }

            latch.engage(on: confirmed, at: now)
            didAnnounceLatchHold = false
            historicalAttempt = nil
            DispatchQueue.main.async { [weak self] in
                self?.onConfirmedCandidate?(confirmed)
            }
        }
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

        if let attempt = historicalAttempt,
           attempt.number != number || now - attempt.startedAt > Self.historicalAttemptTTL {
            historicalAttempt = nil
            confirmationWindow.reset()
        }

        if historicalAttempt == nil {
            historicalAttempt = HistoricalEvidenceRequest(
                id: UUID(),
                number: number,
                startedAt: now,
                lastObservedAt: now,
                retryCount: 0,
                titleCandidates: []
            )
        }
        guard var attempt = historicalAttempt,
              attempt.retryCount < Self.historicalAttemptLimit else {
            historicalAttempt = nil
            return nil
        }

        attempt.retryCount += 1
        attempt.lastObservedAt = now
        do {
            try handler.perform([titleRequest])
            let titleLines = recognizedLines(
                from: titleRequest,
                roi: CardFramingRegion.titleVisionRect,
                sourceSize: sourceSize
            )
            if case let .pokemonHistorical(evidence)? = PokemonHistoricalScanParser.parse(
                number: number,
                titleLines: titleLines.map(\.text),
                excludingFooter: PokemonHistoricalScanParser.footerSignature(from: footerLines.map(\.text))
            ) {
                attempt.titleCandidates.formUnion(evidence.titleCandidates)
            }
        } catch {
            // A failed secondary request is a miss. Footer recognition remains
            // authoritative and the next matching frame may retry.
        }
        historicalAttempt = attempt
        guard !attempt.titleCandidates.isEmpty else { return nil }
        return .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: number,
                titleCandidates: attempt.titleCandidates.sorted()
            )
        )
    }

    /// Speculation, and only speculation. The catalog de-duplicates, so an
    /// identifier that flickers in and out costs at most one request.
    private func announcePlausible(_ observation: ScanIdentifier?) {
        guard let observation, observation != lastAnnouncedPlausible else { return }
        lastAnnouncedPlausible = observation
        DispatchQueue.main.async { [weak self] in
            self?.onPlausibleCandidate?(observation)
        }
    }

    private func announceLatchHoldIfNeeded() {
        guard !didAnnounceLatchHold,
              latch.heldMatchCount >= Self.latchHoldHintMatches,
              let latched = latch.latched else { return }

        didAnnounceLatchHold = true
        DispatchQueue.main.async { [weak self] in
            self?.onLatchHolding?(latched)
        }
    }

    /// Callers must be on `visionQueue`.
    private func resetObservationState() {
        confirmationWindow.reset()
        latch.releaseAndForget()
        didAnnounceLatchHold = false
        lastAnnouncedPlausible = nil
        historicalAttempt = nil
    }

    private func setCameraIssue(_ issue: CameraIssue?) {
        DispatchQueue.main.async { [weak self] in
            self?.cameraIssue = issue
        }
    }

    private func updateAssistance(from lines: [RecognizedLine]) {
        guard let device = videoInput?.device else { return }
        let heights = lines.compactMap { $0.sourcePixelRect.map { Float($0.height) } }
        let confidences = lines.compactMap(\.confidence)
        let assessment = CaptureAssessment(
            detailSharpness: nil,
            horizontalMotion: nil,
            verticalMotion: nil,
            textPixelHeight: heights.max(),
            localContrast: nil,
            clippedHighlightArea: nil,
            meanOCRConfidence: confidences.isEmpty
                ? nil
                : confidences.reduce(0, +) / Float(confidences.count),
            isAdjustingFocus: device.isAdjustingFocus,
            isAdjustingExposure: device.isAdjustingExposure,
            exposureDuration: CMTimeGetSeconds(device.exposureDuration),
            iso: device.iso,
            lensPosition: device.isFocusModeSupported(.continuousAutoFocus) ? device.lensPosition : nil,
            minimumFocusDistance: device.minimumFocusDistance >= 0 ? device.minimumFocusDistance : nil
        )
        let assistance = assistanceMonitor.observe(assessment, hasFooterText: !lines.isEmpty)
        DispatchQueue.main.async { [weak self] in
            guard self?.scanAssistance != assistance else { return }
            self?.scanAssistance = assistance
        }
    }
}

/// What the scanner recognises, as one value.
///
/// There is no game mode. A printed identifier is specific enough to say which
/// game it came from — `OBF 223/197` cannot be a Magic footer and `ECL • 0218 •
/// EN` cannot be a Pokémon one — so asking the user to pick first was asking for
/// information the card already carries.
struct RecognitionProfile {
    /// `nil` only before the Magic set directory is installed. Pokémon needs no
    /// counterpart because its set table is compiled in.
    let magic: MagicScanProfile?

    static let pokemonOnly = RecognitionProfile(magic: nil)

    /// Vision biases recognition toward these, so it carries both games'
    /// vocabularies at once. Deduplicated because a three-character code can
    /// legitimately belong to both directories.
    var customWords: [String] {
        ScanText.unique(SetCodeMap.codes + PokemonPromoCodeMap.codes + (magic?.customWords ?? []))
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
        let pokemon = ScanParser.parsePokemon(text)
        let magicOutcome = magic?.parseOutcome(lines) ?? .nothing

        switch (pokemon, magicOutcome) {
        case (nil, .nothing):
            return .nothing
        case let (identifier?, .nothing), let (nil, .identified(identifier)):
            return .identified(identifier)
        case (_?, .identified(_)):
            return .ambiguous
        case (nil, .spatiallyRejectedCollector):
            return .spatiallyRejectedMagicCollector
        case let (identifier?, .spatiallyRejectedCollector):
            // Preserve modern Pokemon recognition if it independently earned an
            // identity; the rejected Magic-shaped reading is then irrelevant.
            return .identified(identifier)
        }
    }
}

enum RecognitionOutcome: Equatable {
    case nothing
    case identified(ScanIdentifier)
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

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isPaused else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastVisionTime >= minimumVisionInterval else { return }
        lastVisionTime = now

        let rotationAngle = rotation.currentAngle

        do {
            let handler = VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: CardFramingRegion.imageOrientation(forRotationAngle: rotationAngle),
                options: [:]
            )
            try handler.perform([footerRequest])

            let dimensions = CMVideoFormatDescriptionGetDimensions(
                CMSampleBufferGetFormatDescription(sampleBuffer)!
            )
            // Vision measures the upright image, so the sensor's landscape
            // width/height swap for a quarter turn and stay put for a half turn.
            let sourceSize = CardFramingRegion.visionSourceSize(
                forRotationAngle: rotationAngle,
                sensorWidth: Int(dimensions.width),
                sensorHeight: Int(dimensions.height)
            )
            let lines = recognizedLines(
                from: footerRequest,
                roi: CardFramingRegion.visionRect,
                sourceSize: sourceSize
            )
            updateAssistance(from: lines)
            let outcome = profile.identify(lines)
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
            DispatchQueue.main.async { [weak self] in
                self?.debugVisionBoxes = boxes
            }
#endif

            handleFooterOutcome(
                outcome,
                footerLines: lines,
                historicalIdentifier: historical,
                at: now
            )
        } catch {
#if DEBUG
            DispatchQueue.main.async { [weak self] in
                self?.debugVisionBoxes = []
            }
#endif
            // A bad frame is expected occasionally. Run it through the normal
            // pipeline as a miss so it counts as absence evidence for the latch
            // as well as the confirmation window, then let the next frame try.
            historicalAttempt = nil
            handleFooterOutcome(
                .nothing,
                footerLines: [],
                historicalIdentifier: nil,
                at: now
            )
        }
    }
}
