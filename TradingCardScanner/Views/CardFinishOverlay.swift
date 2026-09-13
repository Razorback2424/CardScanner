import CoreMotion
import Foundation
import SwiftUI
import UIKit

/// Cheap counters for the opt-in finish performance route. These are plain
/// counters rather than an observable model: publishing every sensor/body
/// event would change the workload being measured. The HUD samples them on a
/// slow timeline instead.
final class CardFinishPerformanceDiagnostics {
    static let shared = CardFinishPerformanceDiagnostics()

#if DEBUG || CARD_FINISH_PERF_HARNESS
    private(set) var scenario = "-"
    private(set) var rowCount = 0
    private(set) var sensorCallbackCount = 0
    private(set) var collectionDeliveryCount = 0
    private(set) var detailDeliveryCount = 0
    private(set) var overlayBodyEvaluationCount = 0

    private final class WeakRendererOwner {
        weak var value: AnyObject?

        init(_ value: AnyObject) {
            self.value = value
        }
    }

    private var rendererOwners: [ObjectIdentifier: WeakRendererOwner] = [:]

    var activeRendererCount: Int {
        pruneDeadRendererOwners()
        return rendererOwners.count
    }
#endif

    func reset(scenario: String, rowCount: Int) {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        self.scenario = scenario
        self.rowCount = rowCount
        rendererOwners.removeAll()
        sensorCallbackCount = 0
        collectionDeliveryCount = 0
        detailDeliveryCount = 0
        overlayBodyEvaluationCount = 0
#endif
    }

    func rendererAppeared(owner: AnyObject) {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        pruneDeadRendererOwners()
        rendererOwners[ObjectIdentifier(owner)] = WeakRendererOwner(owner)
#endif
    }

    func rendererDisappeared(owner: AnyObject) {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        rendererOwners.removeValue(forKey: ObjectIdentifier(owner))
#endif
    }

#if DEBUG || CARD_FINISH_PERF_HARNESS
    private func pruneDeadRendererOwners() {
        rendererOwners = rendererOwners.filter { $0.value.value != nil }
    }
#endif

    func sensorCallback() {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        sensorCallbackCount += 1
#endif
    }

    func motionDelivered(to usage: CardFinishMotionUsage) {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        switch usage {
        case .passive:
            collectionDeliveryCount += 1
        case .detail:
            detailDeliveryCount += 1
        }
#endif
    }

    func overlayBodyEvaluated() {
#if DEBUG || CARD_FINISH_PERF_HARNESS
        overlayBodyEvaluationCount += 1
#endif
    }
}

/// The only runtime modes the foil renderer needs to distinguish. Keeping the
/// decision separate from the view makes accessibility and evidence policy
/// testable without constructing SwiftUI views.
enum CardFinishPerformancePolicy: Equatable, Sendable {
    case live
    case staticCollection
    case staticAll
    case disabled
}

struct CardFinishRenderPlan: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case disabled
        case staticSurface
        case live
    }

    let family: SheenFamily?
    let isReverse: Bool
    let mode: Mode

    static func make(
        variant: PhysicalVariant?,
        resolution: VariantResolution?,
        treatments: [MagicTreatment],
        motionUsage: CardFinishMotionUsage,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        policy: CardFinishPerformancePolicy
    ) -> CardFinishRenderPlan {
        guard let variant,
              let resolution,
              resolution != .catalogSilent,
              resolution != .imported,
              isSupportedSurface(variant),
              !reduceTransparency,
              policy != .disabled else {
            return CardFinishRenderPlan(family: nil, isReverse: false, mode: .disabled)
        }

        let family = treatments.first?.sheenFamily ?? .dispersed
        let isStatic = reduceMotion
            || policy == .staticAll
            || (policy == .staticCollection && motionUsage == .passive)
        let mode: Mode = isStatic
            ? .staticSurface
            : .live

        return CardFinishRenderPlan(
            family: family,
            isReverse: variant.id == PhysicalVariant.reverse.id,
            mode: mode
        )
    }

    private static func isSupportedSurface(_ variant: PhysicalVariant) -> Bool {
        let id = variant.id
        return id == PhysicalVariant.foil.id
            || id == PhysicalVariant.holo.id
            || id == PhysicalVariant.reverse.id
    }
}

struct CardFinishMotionAttitude: Sendable {
    let roll: Double
    let pitch: Double
}

@preconcurrency @MainActor
protocol CardFinishMotionSampler: AnyObject {
    var isDeviceMotionAvailable: Bool { get }
    func start(
        interval: TimeInterval,
        handler: @escaping (CardFinishMotionAttitude) -> Void
    )
    func stop()
}

@preconcurrency @MainActor
private final class CardFinishCoreMotionSampler: CardFinishMotionSampler {
    private let motionManager = CMMotionManager()

    var isDeviceMotionAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func start(
        interval: TimeInterval,
        handler: @escaping (CardFinishMotionAttitude) -> Void
    ) {
        motionManager.deviceMotionUpdateInterval = interval
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let attitude = motion?.attitude else { return }
            handler(
                CardFinishMotionAttitude(
                    roll: attitude.roll,
                    pitch: attitude.pitch
                )
            )
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

/// A separately observable delivery channel for one motion consumer class.
/// Collection tiles share the passive channel; the detail hero gets its own
/// cadence and can therefore move to 60 Hz without forcing every tile to
/// invalidate at that rate.
@preconcurrency @MainActor
final class CardFinishMotionChannel: ObservableObject {
    let usage: CardFinishMotionUsage
    let rateHz: Int
    @Published private(set) var tilt: CGSize = .zero
    private(set) var deliveredSampleCount = 0
    private var lastDeliveryTime: TimeInterval?
    private var lastDeliveredTilt: CGSize?

    fileprivate init(usage: CardFinishMotionUsage) {
        self.usage = usage
        self.rateHz = usage.rateHz
    }

    fileprivate func reset() {
        lastDeliveryTime = nil
        lastDeliveredTilt = nil
        if tilt != .zero {
            tilt = .zero
        }
    }

    fileprivate func deliver(
        _ nextTilt: CGSize,
        at time: TimeInterval,
        minimumDelta: CGFloat
    ) -> Bool {
        let minimumInterval = 1.0 / Double(rateHz)
        if let lastDeliveryTime,
           time - lastDeliveryTime < minimumInterval - 0.000_001 {
            return false
        }
        if let lastDeliveredTilt,
           max(abs(nextTilt.width - lastDeliveredTilt.width), abs(nextTilt.height - lastDeliveredTilt.height)) < minimumDelta {
            return false
        }

        self.lastDeliveryTime = time
        self.lastDeliveredTilt = nextTilt
        self.tilt = nextTilt
        deliveredSampleCount += 1
        CardFinishPerformanceDiagnostics.shared.motionDelivered(to: usage)
        return true
    }
}

/// One device-motion source shared by the collection grid and card detail.
///
/// Registration is reference-counted rather than screen-scoped. This avoids a
/// manager per tile and, importantly, stops Core Motion when the last eligible
/// overlay leaves the hierarchy.
@preconcurrency @MainActor
final class CardFinishMotionSource: ObservableObject {
    private final class Registration {
        let usage: CardFinishMotionUsage
        weak var owner: AnyObject?

        init(usage: CardFinishMotionUsage, owner: AnyObject) {
            self.usage = usage
            self.owner = owner
        }
    }

    private let sampler: CardFinishMotionSampler
    private let now: () -> TimeInterval
    private let collectionChannel = CardFinishMotionChannel(usage: .passive)
    private let detailChannel = CardFinishMotionChannel(usage: .detail)
    private var registrations: [UUID: Registration] = [:]
    private var passiveRegistrationCount = 0
    private var detailRegistrationCount = 0
    private var currentFrequency: Double?
    private var reference: (roll: Double, pitch: Double)?
    private var currentTilt: CGSize = .zero
    private var reduceMotionObserver: NSObjectProtocol?

    /// Full travel at roughly 25°, which is a wrist movement rather than a
    /// shoulder one.
    private static let fullTravel = 0.44
    private static let minimumDeliveredTiltDelta: CGFloat = 0.005

    init(
        sampler: CardFinishMotionSampler? = nil,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        self.sampler = sampler ?? CardFinishCoreMotionSampler()
        self.now = now
        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMotion()
            }
        }
    }

    deinit {
        if let reduceMotionObserver {
            NotificationCenter.default.removeObserver(reduceMotionObserver)
        }
    }

    var activeRegistrationCount: Int {
        if pruneDeadRegistrations() {
            updateMotion()
        }
        return registrations.count
    }

    func channel(for usage: CardFinishMotionUsage) -> CardFinishMotionChannel {
        usage == .detail ? detailChannel : collectionChannel
    }

    @discardableResult
    func register(_ usage: CardFinishMotionUsage, owner: AnyObject) -> UUID {
        _ = pruneDeadRegistrations()
        let token = UUID()
        registrations[token] = Registration(usage: usage, owner: owner)
        incrementRegistrationCount(for: usage)
        PerformanceSignpost.emitEvent(
            "cardFinishMotion",
            "event=register usage=\(usage == .detail ? "detail" : "collection") active=\(registrations.count)"
        )
        updateMotion()
        return token
    }

    func unregister(_ token: UUID) {
        guard let registration = registrations.removeValue(forKey: token) else { return }
        decrementRegistrationCount(for: registration.usage)
        if registrationCount(for: registration.usage) == 0 {
            channel(for: registration.usage).reset()
        }
        PerformanceSignpost.emitEvent(
            "cardFinishMotion",
            "event=unregister active=\(registrations.count)"
        )
        updateMotion()
    }

    private func incrementRegistrationCount(for usage: CardFinishMotionUsage) {
        switch usage {
        case .passive:
            passiveRegistrationCount += 1
        case .detail:
            detailRegistrationCount += 1
        }
    }

    private func decrementRegistrationCount(for usage: CardFinishMotionUsage) {
        switch usage {
        case .passive:
            passiveRegistrationCount = max(0, passiveRegistrationCount - 1)
        case .detail:
            detailRegistrationCount = max(0, detailRegistrationCount - 1)
        }
    }

    private func registrationCount(for usage: CardFinishMotionUsage) -> Int {
        switch usage {
        case .passive: passiveRegistrationCount
        case .detail: detailRegistrationCount
        }
    }

    /// The view owns the registration lifetime. The source keeps only a weak
    /// owner so a lazy-grid view that leaves the hierarchy cannot keep motion
    /// active forever if SwiftUI skips a disappearance callback.
    @discardableResult
    private func pruneDeadRegistrations() -> Bool {
        let deadTokens = registrations.compactMap { token, registration in
            registration.owner == nil ? token : nil
        }
        guard !deadTokens.isEmpty else { return false }

        for token in deadTokens {
            guard let registration = registrations.removeValue(forKey: token) else { continue }
            decrementRegistrationCount(for: registration.usage)
        }
        if passiveRegistrationCount == 0 {
            collectionChannel.reset()
        }
        if detailRegistrationCount == 0 {
            detailChannel.reset()
        }
        return true
    }

    private var hasDetailRegistration: Bool {
        detailRegistrationCount > 0
    }

    private func updateMotion() {
        _ = pruneDeadRegistrations()
        guard !UIAccessibility.isReduceMotionEnabled,
              !registrations.isEmpty,
              sampler.isDeviceMotionAvailable else {
            stopDeviceMotion()
            return
        }

        let frequency = hasDetailRegistration
            ? Double(CardFinishMotionUsage.detail.rateHz)
            : Double(CardFinishMotionUsage.passive.rateHz)
        guard currentFrequency != frequency else { return }

        sampler.stop()
        reference = nil
        currentTilt = .zero
        collectionChannel.reset()
        detailChannel.reset()
        currentFrequency = frequency
        PerformanceSignpost.emitEvent(
            "cardFinishMotion",
            "event=start rateHz=\(Int(frequency)) active=\(registrations.count)"
        )
        sampler.start(interval: 1.0 / frequency) { [weak self] attitude in
            guard let self else { return }
            self.receive(attitude)
        }
    }

    private func receive(_ attitude: CardFinishMotionAttitude) {
        if pruneDeadRegistrations() {
            updateMotion()
            guard !registrations.isEmpty else { return }
        }
        CardFinishPerformanceDiagnostics.shared.sensorCallback()
        if reference == nil {
            reference = (attitude.roll, attitude.pitch)
        }
        guard let reference else { return }

        let target = CGSize(
            width: Self.normalised(attitude.roll - reference.roll),
            height: Self.normalised(attitude.pitch - reference.pitch)
        )
        // Tracks the hand rather than trailing it. A heavy damping
        // coefficient makes the sheen look stationary during the quick
        // tilt people actually use to look for foil.
        currentTilt = CGSize(
            width: currentTilt.width * 0.55 + target.width * 0.45,
            height: currentTilt.height * 0.55 + target.height * 0.45
        )
        let timestamp = now()
        if passiveRegistrationCount > 0 {
            _ = collectionChannel.deliver(
                currentTilt,
                at: timestamp,
                minimumDelta: Self.minimumDeliveredTiltDelta
            )
        }
        if detailRegistrationCount > 0 {
            _ = detailChannel.deliver(
                currentTilt,
                at: timestamp,
                minimumDelta: Self.minimumDeliveredTiltDelta
            )
        }
    }

    private func stopDeviceMotion() {
        guard currentFrequency != nil || !registrations.isEmpty else { return }
        sampler.stop()
        currentFrequency = nil
        reference = nil
        currentTilt = .zero
        collectionChannel.reset()
        detailChannel.reset()
        PerformanceSignpost.emitEvent("cardFinishMotion", "event=stop")
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

    var cardFinishPerformancePolicy: CardFinishPerformancePolicy {
        get { self[CardFinishPerformancePolicyKey.self] }
        set { self[CardFinishPerformancePolicyKey.self] = newValue }
    }
}

private struct CardFinishPerformancePolicyKey: EnvironmentKey {
    static let defaultValue: CardFinishPerformancePolicy = .live
}

enum CardFinishMotionUsage: Equatable {
    case passive
    case detail

    var rateHz: Int {
        switch self {
        case .passive: 30
        case .detail: 60
        }
    }
}

private final class CardFinishMotionRegistrationOwner {}

/// The card's finish, rendered rather than captioned.
struct CardFinishOverlay: View {
    let variant: PhysicalVariant?
    let resolution: VariantResolution?
    let treatments: [MagicTreatment]
    let cornerRadius: CGFloat
    let motionUsage: CardFinishMotionUsage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.cardFinishPerformancePolicy) private var performancePolicy
    private let motionSource: CardFinishMotionSource
    @ObservedObject private var motionChannel: CardFinishMotionChannel
    @State private var registrationOwner = CardFinishMotionRegistrationOwner()
    @State private var motionRegistration: UUID?
    @State private var isRendererCounted = false

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
        self.motionSource = motionSource
        self._motionChannel = ObservedObject(
            wrappedValue: motionSource.channel(for: motionUsage)
        )
    }

    private var counterBand: SheenBand {
        SheenBand(
            phase: -0.20,
            travelScale: -0.55,
            width: 0.09,
            tint: renderPlan.family == .neon ? .purple : .white,
            intensity: 0.42
        )
    }

    private var renderPlan: CardFinishRenderPlan {
        CardFinishRenderPlan.make(
            variant: variant,
            resolution: resolution,
            treatments: treatments,
            motionUsage: motionUsage,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            policy: performancePolicy
        )
    }

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
        switch renderPlan.family {
        case .neon:
            return [
                SheenBand(phase: 0, fringe: -0.04, width: 0.10, tint: .orange, intensity: 0.85),
                SheenBand(phase: 0, width: 0.10, tint: .green, intensity: 1, isPrimary: true),
                SheenBand(phase: 0, fringe: 0.04, width: 0.10, tint: .purple, intensity: 0.85),
                counterBand
            ]
        case .dispersed, .none:
            return dispersedFoil
        }
    }

    var body: some View {
        let _ = CardFinishPerformanceDiagnostics.shared.overlayBodyEvaluated()
        Group {
            if renderPlan.mode != .disabled {
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
                        if renderPlan.isReverse {
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
        .onAppear {
            updateRendererDiagnostics()
            updateMotionRegistration()
        }
        .onDisappear {
            if isRendererCounted {
                CardFinishPerformanceDiagnostics.shared.rendererDisappeared(owner: registrationOwner)
                isRendererCounted = false
            }
            unregisterMotion()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateRendererDiagnostics()
            updateMotionRegistration()
        }
        .onChange(of: reduceTransparency) { _, _ in
            updateRendererDiagnostics()
            updateMotionRegistration()
        }
        .onChange(of: renderPlan.mode) { _, _ in
            updateRendererDiagnostics()
            updateMotionRegistration()
        }
    }

    private func sheen(_ band: SheenBand, in size: CGSize, specular: Bool) -> some View {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        // Roll dominates: turning the phone in the hand is how anyone looks
        // for foil. Pitch contributes so the band still answers a nod.
        let tilt: CGSize
        if case .live = renderPlan.mode {
            tilt = motionChannel.tilt
        } else {
            tilt = .zero
        }
        let drive = max(
            -1,
            min(1, tilt.width * 0.85 + tilt.height * 0.45)
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

    private func updateMotionRegistration() {
        guard case .live = renderPlan.mode else {
            unregisterMotion()
            return
        }
        guard motionRegistration == nil else { return }
        motionRegistration = motionSource.register(motionUsage, owner: registrationOwner)
    }

    private func updateRendererDiagnostics() {
        let shouldCount = renderPlan.mode != .disabled
        guard shouldCount != isRendererCounted else { return }
        isRendererCounted = shouldCount
        if shouldCount {
            CardFinishPerformanceDiagnostics.shared.rendererAppeared(owner: registrationOwner)
        } else {
            CardFinishPerformanceDiagnostics.shared.rendererDisappeared(owner: registrationOwner)
        }
    }

    private func unregisterMotion() {
        guard let motionRegistration else { return }
        motionSource.unregister(motionRegistration)
        self.motionRegistration = nil
    }
}

#if DEBUG || CARD_FINISH_PERF_HARNESS
struct CardFinishPerformanceHUD: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let diagnostics = CardFinishPerformanceDiagnostics.shared
            VStack(alignment: .leading, spacing: 3) {
                Text("Finish perf · \(diagnostics.scenario) · \(diagnostics.rowCount) rows")
                    .font(.caption.weight(.semibold))
                Text("renderers \(diagnostics.activeRendererCount) · bodies \(diagnostics.overlayBodyEvaluationCount)")
                Text("sensor \(diagnostics.sensorCallbackCount) · collection \(diagnostics.collectionDeliveryCount) · detail \(diagnostics.detailDeliveryCount)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            .padding(8)
        }
        .allowsHitTesting(false)
    }
}
#endif
