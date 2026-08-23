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
enum ScanRegion {
    static let visionRect = CGRect(x: 0.08, y: 0.17, width: 0.72, height: 0.16)

    static let fullFrameRect = CGRect(x: 0, y: 0, width: 1, height: 1)

#if DEBUG
    /// Calibration switch for the first on-device run.
    ///
    /// Set this to `true` to widen Vision's ROI to the whole frame for one build.
    /// That matters because if `metadataRect(fromVisionRect:)` has the rotation
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

    static var metadataRect: CGRect {
        return metadataRect(fromVisionRect: visionRect)
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

    static func metadataRect(fromVisionRect rect: CGRect) -> CGRect {
        // Current `.right` transform assumption:
        // metadataX = 1 - visionY
        // metadataY = 1 - visionX
        // Rect bounds must use max values because both axes reverse direction.
        //
        // IMPORTANT FIELD-TEST CHECK:
        // Apple's orientation wording is easy to interpret in either rotation direction.
        // If the on-device yellow band/recognized-text boxes are mirrored to the wrong
        // vertical end of the card, the alternate transform is:
        // CGRect(x: rect.minY, y: rect.minX,
        //        width: rect.height, height: rect.width)
        CGRect(
            x: 1 - rect.maxY,
            y: 1 - rect.maxX,
            width: rect.height,
            height: rect.width
        )
    }
}

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

    var hint: String {
        switch self {
        case .standard: return "Hold about 20cm away"
        case .macro: return "Hold about 5cm away"
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
#if DEBUG
    @Published private(set) var debugVisionBoxes: [CGRect] = []
#endif

    var onConfirmedCandidate: ((ScanCandidate) -> Void)?

    private let sessionQueue = DispatchQueue(label: "cards.camera.session")
    private let visionQueue = DispatchQueue(label: "cards.camera.vision", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let request = VNRecognizeTextRequest()

    private var isConfigured = false
    private var isPaused = false
    private var videoInput: AVCaptureDeviceInput?
    /// Written on `sessionQueue`; `lens` is the main-thread mirror for the UI.
    private var currentLens: CameraLens = .standard
    private var lastVisionTime: CFAbsoluteTime = 0
    private var confirmationWindow = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)

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

    private func configureTextRequest() {
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]

        // Vision only applies customWords while language correction is enabled.
        // Field testing should decide whether this wins over correction-off for the
        // numeric-heavy identifier strip; keep the custom set vocabulary for MVP.
        request.usesLanguageCorrection = true
        request.customWords = SetCodeMap.codes
        request.regionOfInterest = ScanRegion.activeVisionROI
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

            self.visionQueue.async { self.confirmationWindow.reset() }
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
        let focusPoint = CGPoint(x: ScanRegion.metadataRect.midX, y: ScanRegion.metadataRect.midY)
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

    private func handleRecognizedText(_ lines: [String]) {
        // Preserve Vision's line grouping first. That helps keep a set code paired
        // with its own collector number when more than one card/text line is visible.
        let parsed = ScanParser.parse(lines)
        guard let confirmed = confirmationWindow.observe(parsed) else { return }

        isPaused = true

        DispatchQueue.main.async { [weak self] in
            self?.onConfirmedCandidate?(confirmed)
        }
    }

    private func setCameraIssue(_ issue: CameraIssue?) {
        DispatchQueue.main.async { [weak self] in
            self?.cameraIssue = issue
        }
    }
}

extension CardScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isPaused else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastVisionTime >= minimumVisionInterval else { return }
        lastVisionTime = now

        do {
            let handler = VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: .right,
                options: [:]
            )
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }

#if DEBUG
            let boxes = observations.map(\.boundingBox)
            DispatchQueue.main.async { [weak self] in
                self?.debugVisionBoxes = boxes
            }
#endif

            handleRecognizedText(lines)
        } catch {
#if DEBUG
            DispatchQueue.main.async { [weak self] in
                self?.debugVisionBoxes = []
            }
#endif
            // A bad frame is expected occasionally. Record a miss in the rolling
            // confirmation window, then allow the next frame to try again.
            _ = confirmationWindow.observe(nil)
        }
    }
}
