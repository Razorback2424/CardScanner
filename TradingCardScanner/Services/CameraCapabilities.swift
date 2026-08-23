import AVFoundation
import Foundation

/// Resolves — once — whether this phone has an ultra wide camera that can actually
/// focus close enough to read a card's identifier strip, and remembers the answer.
///
/// The result is a fixed property of the hardware, so probing it on every launch is
/// wasted work. It is cached in `UserDefaults` alongside the hardware model it was
/// measured on: `UserDefaults` travels with an iCloud restore onto a new phone, and a
/// `true` cached from a device with a macro-capable ultra wide must not be trusted on
/// a device without one. A model mismatch re-probes and overwrites.
enum CameraCapabilities {
    private enum Key {
        static let hasMacroLens = "camera.hasMacroLens"
        static let probedModelIdentifier = "camera.probedModelIdentifier"
    }

    /// A macro-capable ultra wide must exist *and* autofocus. Several iPhones ship a
    /// fixed-focus ultra wide that sits near its hyperfocal distance and only gets
    /// softer as you approach — present, but useless for this app.
    static func hasMacroLens(defaults: UserDefaults = .standard) -> Bool {
        if defaults.string(forKey: Key.probedModelIdentifier) == modelIdentifier,
           let cached = defaults.object(forKey: Key.hasMacroLens) as? Bool {
            return cached
        }

        let probed = probeForMacroLens()
        defaults.set(probed, forKey: Key.hasMacroLens)
        defaults.set(modelIdentifier, forKey: Key.probedModelIdentifier)
        return probed
    }

    /// Forces the next `hasMacroLens` call to re-probe the hardware.
    static func invalidateCache(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Key.hasMacroLens)
        defaults.removeObject(forKey: Key.probedModelIdentifier)
    }

    private static func probeForMacroLens() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else {
            return false
        }
        return device.isFocusModeSupported(.continuousAutoFocus)
    }

    /// Hardware model identifier, e.g. `iPhone17,1`. Deliberately not the marketing
    /// name: this only has to be stable and distinct per camera configuration.
    static let modelIdentifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)

        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pointer)) {
                String(validatingUTF8: $0)
            }
        }

        return identifier ?? "unknown"
    }()
}
