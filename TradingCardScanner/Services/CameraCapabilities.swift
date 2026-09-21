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
        // Suffixed when the probe started testing focus distance as well as
        // autofocus. A value cached by the older, weaker probe is not an answer
        // to the question this one asks.
        static let hasMacroLens = "camera.hasMacroLens.v2"
        static let probedModelIdentifier = "camera.probedModelIdentifier.v2"
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

    /// The closest a lens may focus and still be the right lens for this app.
    /// A macro-capable ultra wide focuses to roughly 20mm; the standard wide
    /// bottoms out around 120mm, which is where the identifier strip stops
    /// resolving. 80mm sits clear of both.
    private static let macroFocusDistanceLimitMillimeters = 80

    private static func probeForMacroLens() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else {
            return false
        }
        guard device.isFocusModeSupported(.continuousAutoFocus) else { return false }

        // `minimumFocusDistance` reports -1 when the device does not publish
        // one. Unknown is not evidence against the lens, so it keeps the old
        // autofocus-only answer; only a positively reported long throw is
        // treated as disqualifying.
        let minimumFocusDistance = device.minimumFocusDistance
        guard minimumFocusDistance >= 0 else { return true }
        return minimumFocusDistance <= macroFocusDistanceLimitMillimeters
    }

    /// Hardware model identifier, e.g. `iPhone17,1`. Deliberately not the marketing
    /// name: this only has to be stable and distinct per camera configuration.
    static let modelIdentifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)

        // The capacity is the size of the machine buffer being rebound. It used to
        // be the size of the pointer itself, which is eight bytes regardless of
        // how long the model string actually is. Read outside the inout access,
        // because measuring it inside overlaps with the exclusive borrow.
        let machineSize = MemoryLayout.size(ofValue: systemInfo.machine)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: machineSize) {
                String(validatingUTF8: $0)
            }
        }

        return identifier ?? "unknown"
    }()
}
