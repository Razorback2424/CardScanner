import AVFoundation
import CoreMotion
import SwiftUI
import UIKit

enum CenteringCameraLens: String, Codable, Equatable {
    case macro
    case wide
}

struct CenteringCameraOpticsConfiguration: Equatable {
    let lens: CenteringCameraLens
    let geometricDistortionCorrectionSupported: Bool

    var requestsGeometricDistortionCorrection: Bool {
        geometricDistortionCorrectionSupported
    }
}

enum CenteringCameraConfiguration: Equatable {
    case centering
    case listingPhotos
}

@MainActor
final class CenteringCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    nonisolated let session = AVCaptureSession()
    /// Which way the sensor is held. The photo connection and the preview layer
    /// both follow it, so a capture taken on an iPad in landscape is upright.
    nonisolated let rotation: CameraRotationTracker

    @Published private(set) var cameraIssue: CameraIssue?
    @Published private(set) var levelOffset: CGSize = .zero
    @Published private(set) var isLevel = false
    @Published private(set) var capturedData: Data?
    /// The lens that produced the current camera capture. The image data still
    /// carries its own EXIF metadata; this field makes the capture path
    /// explicit for the centering evidence and device checks.
    @Published private(set) var captureLens: CenteringCameraLens?

    nonisolated private let sessionQueue = DispatchQueue(label: "cards.centering.camera")
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let motionManager = CMMotionManager()
    nonisolated private let configuration: CenteringCameraConfiguration
    nonisolated(unsafe) private var isConfigured = false
    /// Set once the session has committed, because `activeFormat` is not
    /// settled until then. Only the listing-photo configuration raises it; the
    /// centering path keeps AVFoundation's default photo dimensions.
    nonisolated(unsafe) private var configuredCamera: AVCaptureDevice?
    /// A centering capture is a one-shot interaction. Keep the request marked
    /// active until the view stops so rapid taps cannot queue multiple photos
    /// before the first result dismisses the camera.
    nonisolated(unsafe) private var isCaptureInFlight = false
    /// All start/stop decisions are serialized with capture-session work. This
    /// prevents a delayed permission callback from starting the camera after the
    /// full-screen camera has already disappeared.
    nonisolated(unsafe) private var requestedStartID: UUID?

    init(configuration: CenteringCameraConfiguration = .centering) {
        rotation = CameraRotationTracker()
        self.configuration = configuration
        super.init()
    }

    func start() {
        let requestID = UUID()
        sessionQueue.async { [weak self] in
            self?.requestedStartID = requestID
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(requestID: requestID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStart(requestID: requestID)
                } else {
                    self?.setIssue(.permissionDenied)
                }
            }
        default:
            setIssue(.permissionDenied)
        }
        startLevelUpdates()
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestedStartID = nil
            self.isCaptureInFlight = false
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning, !self.isCaptureInFlight else { return }
            self.isCaptureInFlight = true
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            if self.configuration == .listingPhotos {
                // Read back from the output rather than from a cached format
                // value: `maxPhotoDimensions` is the only value guaranteed to
                // be accepted here, and exceeding it raises an uncatchable
                // ObjC exception.
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
            let angle = self.rotation.currentAngle
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        sessionQueue.async { [weak self] in
            guard let self, self.isCaptureInFlight else { return }
            guard let data else {
                self.isCaptureInFlight = false
                self.setIssue(.configurationFailed)
                return
            }
            // Keep the one-shot occupied until stop() runs. The SwiftUI
            // observer dismisses the view from the main queue, and this closes
            // the small window in which a second tap could otherwise enqueue.
            DispatchQueue.main.async { [weak self] in
                self?.capturedData = data
            }
        }
    }

    nonisolated private func configureAndStart(requestID: UUID) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.requestedStartID == requestID else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.applyMaximumPhotoDimensionsIfNeeded()
                    self.isConfigured = true
                }
                guard !self.session.isRunning else { return }
                guard self.requestedStartID == requestID else { return }
                self.session.startRunning()
                self.setIssue(nil)
            } catch {
                self.setIssue(.configurationFailed)
            }
        }
    }

    nonisolated private func configureSession() throws {
        let lens: CenteringCameraLens
        switch configuration {
        case .centering:
            lens = CameraCapabilities.hasMacroLens() ? .macro : .wide
        case .listingPhotos:
            // The ultra-wide macro lens has a much lower maximum still-image
            // size on high-resolution devices. Listing photos must use the
            // main wide camera so the export can preserve native pixels.
            lens = .wide
        }
        let cameraType: AVCaptureDevice.DeviceType = lens == .macro
            ? .builtInUltraWideCamera
            : .builtInWideAngleCamera
        guard let camera = AVCaptureDevice.default(cameraType, for: .video, position: .back) else {
            throw CameraConfigurationError.unavailable
        }
        let optics = CenteringCameraOpticsConfiguration(
            lens: lens,
            geometricDistortionCorrectionSupported: camera.isGeometricDistortionCorrectionSupported
        )
        DispatchQueue.main.async { [weak self] in
            self?.captureLens = optics.lens
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraConfigurationError.unavailable
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        configuredCamera = camera

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isSmoothAutoFocusSupported {
                camera.isSmoothAutoFocusEnabled = false
            }
            if optics.requestsGeometricDistortionCorrection {
                camera.isGeometricDistortionCorrectionEnabled = true
            }
            let focusRect = ScanRegion.metadataRect(rotationAngle: rotation.currentAngle)
            let focusPoint = CGPoint(x: focusRect.midX, y: focusRect.midY)
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = focusPoint
            }
            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = focusPoint
            }
            camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
        } catch {
            // Capture can still proceed with the device's existing focus and exposure.
        }
    }

    /// Raises the still-image size to the sensor maximum for listing photos.
    /// This must run after `configureSession` returns, because the session's
    /// `commitConfiguration` is deferred to that point and `activeFormat` is
    /// not settled before it.
    nonisolated private func applyMaximumPhotoDimensionsIfNeeded() {
        guard configuration == .listingPhotos, let camera = configuredCamera else { return }
        guard let dimensions = camera.activeFormat.supportedMaxPhotoDimensions.max(
            by: { lhs, rhs in
                Int64(lhs.width) * Int64(lhs.height)
                    < Int64(rhs.width) * Int64(rhs.height)
            }
        ) else { return }
        photoOutput.maxPhotoDimensions = dimensions
    }

    private func startLevelUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1 / 30
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // When the phone is parallel to a card lying flat, gravity points almost
            // entirely through the screen. The remaining x/y components show the
            // direction and amount the phone needs to move to become parallel.
            let x = max(-1, min(1, gravity.x))
            let y = max(-1, min(1, gravity.y))
            self.levelOffset = CGSize(width: x * 90, height: -y * 90)
            self.isLevel = hypot(x, y) < 0.025
        }
    }

    nonisolated private func setIssue(_ issue: CameraIssue?) {
        Task { @MainActor [weak self] in
            self?.cameraIssue = issue
        }
    }

    private enum CameraConfigurationError: Error {
        case unavailable
    }
}

struct CenteringCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera: CenteringCameraController

    let onCapture: (Data) -> Void

    init(
        configuration: CenteringCameraConfiguration = .centering,
        onCapture: @escaping (Data) -> Void
    ) {
        self.onCapture = onCapture
        _camera = StateObject(
            wrappedValue: CenteringCameraController(configuration: configuration)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CenteringCameraPreview(session: camera.session, rotation: camera.rotation)
                .ignoresSafeArea()

            CameraGrid()
                .stroke(.white.opacity(0.45), lineWidth: 0.75)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            CameraLevelIndicator(offset: camera.levelOffset, isLevel: camera.isLevel)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .accessibilityLabel("Close camera")
                    Spacer()
                }
                .padding()

                Spacer()

                Text(camera.isLevel ? "Level" : "Align the two markers")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(camera.isLevel ? .yellow : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())

                Button(action: camera.capture) {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle().stroke(.black.opacity(0.75), lineWidth: 2).padding(5)
                        }
                }
                .accessibilityLabel("Take photo")
                .padding(.top, 12)
                .padding(.bottom, 28)
            }

            if let issue = camera.cameraIssue {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Camera Unavailable",
                        systemImage: "camera.fill",
                        description: Text(issue.message)
                    )
                    if issue == .permissionDenied {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding()
            }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Returning from Settings can grant camera access while this
                // full-screen view remains mounted; retry without requiring a
                // dismiss/reopen cycle.
                camera.start()
            } else {
                camera.stop()
            }
        }
        .onChange(of: camera.capturedData) { _, data in
            guard let data else { return }
            onCapture(data)
            dismiss()
        }
    }
}

private struct CenteringCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    let rotation: CameraRotationTracker

    func makeUIView(context: Context) -> CameraPreviewSurface {
        let view = CameraPreviewSurface()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.rotation = rotation
        return view
    }

    func updateUIView(_ uiView: CameraPreviewSurface, context: Context) {
        uiView.previewLayer.session = session
        uiView.rotation = rotation
    }
}

private final class CameraPreviewSurface: UIView {
    var rotation: CameraRotationTracker?

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout runs on rotation, so the angle is re-read from this view's own
        // window here rather than through a separate orientation observer.
        let angle = cameraRotationAngle
        rotation?.report(angle)
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle),
              connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }
}

private struct CameraGrid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                let x = rect.minX + rect.width * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))

                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }
}

private struct CameraLevelIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let offset: CGSize
    let isLevel: Bool

    var body: some View {
        ZStack {
            reticle(color: .white.opacity(0.85))
            reticle(color: isLevel ? .yellow : .white)
                .offset(isLevel ? .zero : offset)
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: offset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLevel ? "Camera level" : "Camera not level")
    }

    private func reticle(color: Color) -> some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 34, height: 34)
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: 17, y: 7))
                    path.addLine(to: CGPoint(x: 17, y: 27))
                    path.move(to: CGPoint(x: 7, y: 17))
                    path.addLine(to: CGPoint(x: 27, y: 17))
                }
                .stroke(color, lineWidth: 2)
            }
    }
}
