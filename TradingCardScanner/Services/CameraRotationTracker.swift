import AVFoundation
import Combine
import Foundation

/// Owns an `AVCaptureDevice.RotationCoordinator` for the active capture device and
/// publishes the rotation the preview layer and the capture path should apply.
///
/// This is the app's single answer to "which way is up?". It deliberately asks the
/// physical device rather than the interface orientation or the device idiom:
/// on an iPad in a freely resized window neither of those describes how the sensor
/// is held, and the camera overlays are drawn in sensor-relative coordinates.
///
/// The angles start at 90° — portrait — so the first frames match what the app did
/// before rotation was tracked at all, and the coordinator corrects them as soon as
/// it reports.
final class CameraRotationTracker: NSObject, ObservableObject {
    @Published private(set) var previewAngle: CGFloat = CameraRotationTracker.defaultAngle
    @Published private(set) var captureAngle: CGFloat = CameraRotationTracker.defaultAngle

    static let defaultAngle: CGFloat = 90

    /// Queue-agnostic mirrors of the published values. `CardScanner` reads the
    /// preview angle from its Vision queue on every frame, which must not hop to
    /// the main thread, and `@Published` is only safe to read there.
    private let lock = NSLock()
    private var lockedPreviewAngle = CameraRotationTracker.defaultAngle
    private var lockedCaptureAngle = CameraRotationTracker.defaultAngle

    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []

    /// The rotation to hand the preview layer and Vision, readable from any queue.
    var currentPreviewAngle: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return lockedPreviewAngle
    }

    /// The rotation to apply to a photo-output connection, readable from any queue.
    var currentCaptureAngle: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return lockedCaptureAngle
    }

    /// Starts tracking `device`. Safe to call again when the session swaps lenses —
    /// the previous coordinator and its observations are torn down first.
    func track(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer? = nil) {
        stop()

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        self.coordinator = coordinator

        observations = [
            coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                self?.updatePreview(coordinator.videoRotationAngleForHorizonLevelPreview)
            },
            coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                self?.updateCapture(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
        ]
    }

    func stop() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        coordinator = nil
    }

    private func updatePreview(_ angle: CGFloat) {
        lock.lock()
        lockedPreviewAngle = angle
        lock.unlock()

        publish { $0.previewAngle = angle }
    }

    private func updateCapture(_ angle: CGFloat) {
        lock.lock()
        lockedCaptureAngle = angle
        lock.unlock()

        publish { $0.captureAngle = angle }
    }

    /// KVO fires on whichever thread mutated the coordinator, but `@Published`
    /// drives SwiftUI, so the observable half is always republished on main.
    private func publish(_ mutate: @escaping (CameraRotationTracker) -> Void) {
        if Thread.isMainThread {
            mutate(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                mutate(self)
            }
        }
    }
}
