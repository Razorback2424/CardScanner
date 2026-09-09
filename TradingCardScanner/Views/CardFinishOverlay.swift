import CoreMotion
import SwiftUI
import UIKit

/// One device-motion source shared by the collection grid and card detail.
///
/// The grid asks for a 30 Hz feed while it is visible. A detail overlay can
/// temporarily promote the same source to 60 Hz. Keeping the motion manager
/// here means a grid of visible cards never creates one manager per tile.
final class CardFinishMotionSource: ObservableObject {
    /// Roll and pitch as −1…1, where ±1 is a comfortable wrist tilt.
    @Published private(set) var tilt: CGSize = .zero

    private let motionManager = CMMotionManager()
    private var gridIsActive = false
    private var detailIsActive = false
    private var currentFrequency: Double?
    private var reference: (roll: Double, pitch: Double)?
    private var reduceMotionObserver: NSObjectProtocol?

    /// Full travel at roughly 25°, which is a wrist movement rather than a
    /// shoulder one.
    private static let fullTravel = 0.44

    init() {
        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMotion()
        }
    }

    deinit {
        if let reduceMotionObserver {
            NotificationCenter.default.removeObserver(reduceMotionObserver)
        }
    }

    func startGrid() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            gridIsActive = false
            updateMotion()
            return
        }
        gridIsActive = true
        updateMotion()
    }

    func stopGrid() {
        gridIsActive = false
        updateMotion()
    }

    func startDetail() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            detailIsActive = false
            updateMotion()
            return
        }
        detailIsActive = true
        updateMotion()
    }

    func stopDetail() {
        detailIsActive = false
        updateMotion()
    }

    private func updateMotion() {
        guard !UIAccessibility.isReduceMotionEnabled,
              gridIsActive || detailIsActive,
              motionManager.isDeviceMotionAvailable else {
            stopDeviceMotion()
            return
        }

        let frequency = detailIsActive ? 60.0 : 30.0
        guard currentFrequency != frequency else { return }

        motionManager.stopDeviceMotionUpdates()
        reference = nil
        tilt = .zero
        currentFrequency = frequency
        motionManager.deviceMotionUpdateInterval = 1 / frequency
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            if self.reference == nil {
                self.reference = (attitude.roll, attitude.pitch)
            }
            guard let reference = self.reference else { return }

            let target = CGSize(
                width: Self.normalised(attitude.roll - reference.roll),
                height: Self.normalised(attitude.pitch - reference.pitch)
            )
            // Tracks the hand rather than trailing it. A heavy damping
            // coefficient makes the sheen look stationary during the quick
            // tilt people actually use to look for foil.
            self.tilt = CGSize(
                width: self.tilt.width * 0.55 + target.width * 0.45,
                height: self.tilt.height * 0.55 + target.height * 0.45
            )
        }
    }

    private func stopDeviceMotion() {
        guard currentFrequency != nil || motionManager.isDeviceMotionActive else { return }
        motionManager.stopDeviceMotionUpdates()
        currentFrequency = nil
        reference = nil
        tilt = .zero
    }

    private static func normalised(_ radians: Double) -> Double {
        max(-1, min(1, radians / fullTravel))
    }
}

private struct CardFinishMotionSourceKey: EnvironmentKey {
    static let defaultValue = CardFinishMotionSource()
}

extension EnvironmentValues {
    /// A reference-valued environment entry deliberately does not observe the
    /// source at the collection-screen level. Only the small sheen overlays
    /// subscribe to its published tilt values.
    var cardFinishMotionSource: CardFinishMotionSource {
        get { self[CardFinishMotionSourceKey.self] }
        set { self[CardFinishMotionSourceKey.self] = newValue }
    }
}

enum CardFinishMotionUsage: Equatable {
    case passive
    case detail
}

/// The card's finish, rendered rather than captioned.
struct CardFinishOverlay: View {
    let variant: PhysicalVariant?
    let resolution: VariantResolution?
    let treatments: [MagicTreatment]
    let cornerRadius: CGFloat
    let motionUsage: CardFinishMotionUsage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var motionSource: CardFinishMotionSource

    /// How far the sweep travels at full tilt, as a fraction of the gradient's
    /// own length. Chosen to preserve the travel distance used by the detail
    /// hero while remaining visible at collection-tile scale.
    private static let driveSpan = 0.275

    private struct SheenBand {
        /// Where the band rests when the card is held still.
        var phase: Double
        /// Chromatic offset from the band's centre, which opens as the card is
        /// tilted.
        var fringe: Double = 0
        /// How the band answers tilt. Negative counter-moves against the main
        /// band so the highlight reads as a surface instead of a rigid wash.
        var travelScale: Double = 1
        var width: Double
        var tint: Color
        var intensity: Double
        /// Carries the additive specular core. Exactly one band should.
        var isPrimary: Bool = false
    }

    init(
        variant: PhysicalVariant?,
        resolution: VariantResolution?,
        treatments: [MagicTreatment],
        cornerRadius: CGFloat,
        motionSource: CardFinishMotionSource,
        motionUsage: CardFinishMotionUsage = .passive
    ) {
        self.variant = variant
        self.resolution = resolution
        self.treatments = treatments
        self.cornerRadius = cornerRadius
        self.motionUsage = motionUsage
        self._motionSource = ObservedObject(wrappedValue: motionSource)
    }

    private var counterBand: SheenBand {
        SheenBand(
            phase: -0.20,
            travelScale: -0.55,
            width: 0.09,
            tint: activeTreatment == .neonInk ? .purple : .white,
            intensity: 0.42
        )
    }

    private var isCatalogConfirmed: Bool {
        guard variant != nil, let resolution else { return false }
        return resolution != .catalogSilent && resolution != .imported
    }

    private var activeTreatment: MagicTreatment? { treatments.first }

    private var isFoilSurface: Bool {
        guard let variant else { return false }
        return variant.id == PhysicalVariant.holo.id || variant.id == PhysicalVariant.foil.id
    }

    private var isReverseSurface: Bool {
        variant?.id == PhysicalVariant.reverse.id
    }

    private var hasSurface: Bool { isFoilSurface || isReverseSurface }

    /// One dispersed band, and for now the finish every foil surface uses.
    /// The close colour components fringe one highlight rather than producing
    /// artificial stripes.
    private var dispersedFoil: [SheenBand] {
        [
            SheenBand(
                phase: 0,
                fringe: -0.035,
                width: 0.095,
                tint: .pink,
                intensity: 0.7
            ),
            SheenBand(
                phase: 0,
                width: 0.105,
                tint: .cyan,
                intensity: 1,
                isPrimary: true
            ),
            SheenBand(
                phase: 0,
                fringe: 0.035,
                width: 0.095,
                tint: .blue,
                intensity: 0.7
            ),
            counterBand
        ]
    }

    private var bands: [SheenBand] {
        switch activeTreatment {
        case .neonInk:
            return [
                SheenBand(phase: 0, fringe: -0.04, width: 0.10, tint: .orange, intensity: 0.85),
                SheenBand(phase: 0, width: 0.10, tint: .green, intensity: 1, isPrimary: true),
                SheenBand(phase: 0, fringe: 0.04, width: 0.10, tint: .purple, intensity: 0.85),
                counterBand
            ]
        case .surgeFoil, .unclassified, .none:
            return dispersedFoil
        }
    }

    var body: some View {
        Group {
            if isCatalogConfirmed, !reduceTransparency, hasSurface {
                GeometryReader { proxy in
                    ZStack {
                        ForEach(bands.indices, id: \.self) { index in
                            sheen(bands[index], in: proxy.size, specular: false)
                        }
                        // A single narrow additive core, on the band that rests
                        // at centre. Everything else is soft-light.
                        if let primary = bands.first(where: \.isPrimary) {
                            sheen(primary, in: proxy.size, specular: true)
                        }
                    }
                    .mask {
                        if isReverseSurface {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(.white, lineWidth: proxy.size.width * 0.10)
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear { updateMotionUsage() }
        .onDisappear {
            if motionUsage == .detail {
                motionSource.stopDetail()
            }
        }
        .onChange(of: reduceMotion) { _, _ in updateMotionUsage() }
        .onChange(of: reduceTransparency) { _, _ in updateMotionUsage() }
    }

    private func sheen(_ band: SheenBand, in size: CGSize, specular: Bool) -> some View {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        // Roll dominates: turning the phone in the hand is how anyone looks
        // for foil. Pitch contributes so the band still answers a nod.
        let drive = max(
            -1,
            min(1, motionSource.tilt.width * 0.85 + motionSource.tilt.height * 0.45)
        )
        let spread = 0.32 + 0.68 * abs(drive)
        let travel = (
            drive * band.travelScale * Self.driveSpan
                + band.phase
                + band.fringe * spread
        ) * diagonal * 2

        return LinearGradient(
            stops: stops(for: band, specular: specular),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: diagonal * 2, height: diagonal * 2)
        .offset(y: travel)
        .rotationEffect(.degrees(-24))
        .position(x: size.width / 2, y: size.height / 2)
        .blendMode(specular ? .plusLighter : .softLight)
    }

    private func stops(for band: SheenBand, specular: Bool) -> [Gradient.Stop] {
        let half = (specular ? band.width * 0.34 : band.width) / 2
        let core = specular ? 0.13 * band.intensity : 0.5 * band.intensity
        let shoulder = specular ? 0 : 0.13 * band.intensity
        let outer = min(0.5, half * 2.2)
        return [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.5 - outer),
            .init(color: band.tint.opacity(shoulder), location: 0.5 - half),
            .init(color: .white.opacity(core), location: 0.5),
            .init(color: band.tint.opacity(shoulder), location: 0.5 + half),
            .init(color: .clear, location: 0.5 + outer),
            .init(color: .clear, location: 1)
        ]
    }

    private func updateMotionUsage() {
        guard motionUsage == .detail else { return }
        let shouldRun = isCatalogConfirmed && !reduceMotion && !reduceTransparency && hasSurface
        if shouldRun {
            motionSource.startDetail()
        } else {
            motionSource.stopDetail()
        }
    }
}
