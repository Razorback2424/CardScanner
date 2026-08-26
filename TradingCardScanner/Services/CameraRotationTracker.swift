import AVFoundation
import Combine
import Foundation
import UIKit

/// The app's single answer to "which way is up?" for the camera.
///
/// **iPhone is left exactly as it was.** It ships portrait-locked, its scanner
/// geometry was correct, and every part of that geometry — the preview rotation,
/// the Vision orientation, the ROI transform, the focus point — resolves from a
/// fixed 90°, which is the constant the code hardcoded before any of this existed.
/// Nothing on that path is derived, observed or recomputed.
///
/// iPad is the separate path, and the only one that asks a question, because it is
/// the only place the interface can actually rotate. There the angle comes from the
/// **interface orientation of the preview itself** — how the preview is turned on
/// screen — and not from how the device is held relative to gravity. Those are
/// different questions and only the first is the right one: the scan band, the card
/// guide and the Vision ROI are drawn on top of the preview, so the image must stay
/// fixed with respect to the screen. An angle that tracks gravity swings the picture
/// inside its frame while the guides stay put.
///
/// The idiom check in `UIView.cameraRotationAngle` is deliberate, and is the one
/// place in the app that makes one. Layout everywhere else derives from available
/// space, as it should. This is not layout: it is which physical geometry the
/// capture pipeline is wired for, and on a screen that cannot rotate the honest
/// answer is a constant.
final class CameraRotationTracker: NSObject, ObservableObject {
    @Published private(set) var previewAngle: CGFloat = CameraRotationTracker.defaultAngle

    /// Portrait. The value every portrait-locked screen holds forever, and the
    /// value to show before a preview has reported anything.
    static let defaultAngle: CGFloat = 90

    /// Whether the capture pipeline should follow the interface at all. False on
    /// iPhone, where the interface is portrait-locked and the scanner's existing
    /// geometry is correct — the code there does what it did, including leaving
    /// connections alone that it never used to write to.
    static var tracksInterfaceRotation: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// A queue-agnostic mirror of `previewAngle`. `CardScanner` reads this from its
    /// Vision queue on every frame, which must not hop to the main thread, and
    /// `@Published` is only safe to read there.
    private let lock = NSLock()
    private var lockedPreviewAngle = CameraRotationTracker.defaultAngle

    /// The rotation to hand the preview connection, the photo connection and
    /// Vision. One value for all three: what the user framed is what gets captured
    /// and what gets read.
    var currentAngle: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return lockedPreviewAngle
    }

    /// Called by a preview view when it lays out, which is also when it rotates.
    func report(_ angle: CGFloat) {
        lock.lock()
        let changed = lockedPreviewAngle != angle
        lockedPreviewAngle = angle
        lock.unlock()

        guard changed else { return }
        if Thread.isMainThread {
            previewAngle = angle
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.previewAngle = angle
            }
        }
    }

    /// The rotation that makes the sensor image upright for a screen turned this
    /// way. `landscapeRight` is the sensor's own native orientation, hence 0°.
    static func angle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        default: return defaultAngle
        }
    }
}

extension UIView {
    /// The camera rotation for the screen this view is on.
    ///
    /// Portrait on iPhone, always — see the note on `CameraRotationTracker`. Also
    /// portrait before an iPad view has a window, which is the only orientation an
    /// unattached view could sensibly be assumed to be in.
    var cameraRotationAngle: CGFloat {
        guard CameraRotationTracker.tracksInterfaceRotation,
              let orientation = window?.windowScene?.interfaceOrientation else {
            return CameraRotationTracker.defaultAngle
        }
        return CameraRotationTracker.angle(for: orientation)
    }
}
