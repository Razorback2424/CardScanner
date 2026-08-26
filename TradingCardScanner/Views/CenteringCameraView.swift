import AVFoundation
import CoreMotion
import SwiftUI
import UIKit

final class CenteringCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    @Published private(set) var cameraIssue: CameraIssue?
    @Published private(set) var levelOffset: CGSize = .zero
    @Published private(set) var isLevel = false
    @Published private(set) var capturedData: Data?

    private let sessionQueue = DispatchQueue(label: "cards.centering.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let motionManager = CMMotionManager()
    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStart()
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
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            setIssue(.configurationFailed)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.capturedData = data
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                self.setIssue(nil)
            } catch {
                self.setIssue(.configurationFailed)
            }
        }
    }

    private func configureSession() throws {
        let cameraType: AVCaptureDevice.DeviceType = CameraCapabilities.hasMacroLens()
            ? .builtInUltraWideCamera
            : .builtInWideAngleCamera
        guard let camera = AVCaptureDevice.default(cameraType, for: .video, position: .back) else {
            throw CameraConfigurationError.unavailable
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
            let focusPoint = CGPoint(x: ScanRegion.metadataRect.midX, y: ScanRegion.metadataRect.midY)
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

    private func setIssue(_ issue: CameraIssue?) {
        DispatchQueue.main.async { [weak self] in
            self?.cameraIssue = issue
        }
    }

    private enum CameraConfigurationError: Error {
        case unavailable
    }
}

struct CenteringCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CenteringCameraController()

    let onCapture: (Data) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CenteringCameraPreview(session: camera.session)
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
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera.fill",
                    description: Text(issue.message)
                )
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding()
            }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedData) { _, data in
            guard let data else { return }
            onCapture(data)
            dismiss()
        }
    }
}

private struct CenteringCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewSurface {
        let view = CameraPreviewSurface()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewSurface, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class CameraPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
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
