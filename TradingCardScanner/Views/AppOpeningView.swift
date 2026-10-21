import SwiftUI

/// Presentation time starts only after the local result exists. Keep the
/// lock readable, then release it without imposing a minimum loading screen.
private enum OpeningMotion {
    static let lockResponse = 0.34
    static let captionDelay: Duration = .milliseconds(180)
    static let readyHold: Duration = .milliseconds(720)
    static let quickReadyHold: Duration = .milliseconds(420)
    static let revealDuration = 0.48
    static let settleDuration: Duration = .milliseconds(620)
    /// The opening zooms past the viewer as the collection fades in.
    static let handoffScale: CGFloat = 1.06
    static let beamPeriod = 2.4
}

/// Brand colors drawn from the app icon. The static launch screen
/// (`LaunchBackground` + `LaunchMark`) is this view's first frame, so keep
/// both in step when changing the card, guides, or backdrop; regenerate the
/// mark with `scripts/render_launch_mark.py`.
private enum OpeningPalette {
    static let backdrop = Color("LaunchBackground")
    static let halo = Color(red: 0.04, green: 0.20, blue: 0.66)
    static let cardTop = Color(red: 0.33, green: 0.58, blue: 1.00)
    static let cardBottom = Color(red: 0.02, green: 0.30, blue: 0.94)
    static let beam = Color(red: 0.31, green: 0.78, blue: 1.00)
    static let spark = Color(red: 0.62, green: 0.86, blue: 1.00)
    static let seeking = Color.white.opacity(0.7)
    static let locked = Color("OpeningReadyGreen")
}

private enum OpeningGeometry {
    static let card = CGSize(width: 132, height: 185)
    static let cardRadius: CGFloat = 12
    static let guideInset: CGFloat = 12
    /// Back cards fan out from behind the front card, echoing the app icon.
    static let fan: [(angle: Double, x: CGFloat, y: CGFloat, opacity: Double)] = [
        (-16, -30, 12, 0.5),
        (-8, -15, 6, 0.75)
    ]
}

enum AppOpeningPhase: Equatable {
    case opening
    case restoringFromCloud
    case ready(copies: Int?)

    var caption: String {
        switch self {
        case .opening: return "Opening your collection…"
        case .restoringFromCloud: return "Restoring collection from iCloud…"
        case .ready(let copies):
            guard let copies, copies > 0 else { return "Collection ready" }
            return copies == 1 ? "1 copy ready" : "\(copies.formatted()) copies ready"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

@MainActor
final class AppOpeningModel: ObservableObject {
    // Outer nil means not loaded; inner nil means a ready result without a count.
    @Published private(set) var portfolioReady: Int??
    @Published var blocked = false
    @Published private(set) var showsOpening = true
    @Published private(set) var handoff = false
    @Published private(set) var fastHandoff = false
    private var appearedAt: ContinuousClock.Instant?
    private var sessionID: ObjectIdentifier?

    func portfolioDidLoad(copies: Int?) {
        guard portfolioReady == nil else { return }
        portfolioReady = .some(copies)
    }

    func reset() {
        portfolioReady = nil
        blocked = false
        handoff = false
        fastHandoff = false
        showsOpening = true
        appearedAt = nil
    }

    func bindSession(_ id: ObjectIdentifier?) {
        guard let id else { return }
        if let sessionID, sessionID != id { reset() }
        sessionID = id
    }

    func markAppeared() {
        if appearedAt == nil { appearedAt = .now }
    }

    var usesFastPath: Bool {
        guard let appearedAt else { return true }
        return appearedAt.duration(to: .now) < .milliseconds(150)
    }

    func beginHandoff(fast: Bool) {
        fastHandoff = fast
        handoff = true
    }

    func finishHandoff() { showsOpening = false }

    func revealProblem() {
        portfolioReady = nil
        fastHandoff = true
        handoff = true
        showsOpening = false
    }
}

extension CollectionStorageBootstrap.State {
    func openingPhase(portfolioReady: Int??) -> AppOpeningPhase? {
        switch self {
        case .loading: return .opening
        case .ready:
            if let copies = portfolioReady { return .ready(copies: copies) }
            return .opening
        case .restoringFromCloud(let readiness):
            switch readiness {
            case .checkingRemoteCollection, .importingRemoteCollection: return .restoringFromCloud
            case .readyEmpty, .readyPopulated: return .opening
            case .failed, .notApplicable: return nil
            }
        case .confirmationRequired, .accountConflict, .temporarilyUnavailable, .recoveryRequired:
            return nil
        }
    }

    var openingSessionID: ObjectIdentifier? {
        if case .ready(let session) = self { return ObjectIdentifier(session.container) }
        return nil
    }
}

/// Owns the overlay above all bootstrap stages without unmounting launch work.
struct AppOpeningContainer<Content: View>: View {
    @ObservedObject var bootstrap: CollectionStorageBootstrap
    @ObservedObject var opening: AppOpeningModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content

    init(bootstrap: CollectionStorageBootstrap, opening: AppOpeningModel,
         @ViewBuilder content: () -> Content) {
        self.bootstrap = bootstrap
        self.opening = opening
        // Build in the parent's update so changes to its prepared runtimes
        // invalidate the session content even after storage is already ready.
        self.content = content()
    }

    private var phase: AppOpeningPhase? {
        opening.blocked ? nil : bootstrap.state.openingPhase(portfolioReady: opening.portfolioReady)
    }

    var body: some View {
        ZStack {
            content
                .opacity(opening.handoff || phase == nil ? 1 : 0)
                .animation(.easeInOut(duration: phase == nil ? 0.18 : reduceMotion ? 0.24 : OpeningMotion.revealDuration), value: opening.handoff)
                .scaleEffect(opening.handoff || reduceMotion || opening.fastHandoff ? 1 : 0.985)
                .animation(reduceMotion || opening.fastHandoff ? nil : .smooth(duration: 0.60), value: opening.handoff)
                .allowsHitTesting(opening.handoff || phase == nil)
                .accessibilityHidden(!opening.handoff && phase != nil)

            if opening.showsOpening, let phase {
                AppOpeningView(phase: phase)
                    .opacity(opening.handoff ? 0 : 1)
                    .animation(.easeInOut(duration: reduceMotion ? 0.24 : OpeningMotion.revealDuration), value: opening.handoff)
                    .scaleEffect(opening.handoff && !reduceMotion && !opening.fastHandoff ? OpeningMotion.handoffScale : 1)
                    .animation(reduceMotion || opening.fastHandoff ? nil : .smooth(duration: 0.60), value: opening.handoff)
                    .allowsHitTesting(false)
                    .accessibilityHidden(opening.handoff)
                    // The dark stage stays full-bleed; status text returns with the collection.
                    .statusBarHidden(!opening.handoff)
                    .transition(.opacity)
                    .onAppear { opening.markAppeared() }
            }
        }
        .animation(.easeOut(duration: 0.18), value: phase == nil)
        .onChange(of: bootstrap.state.openingSessionID, initial: true) { _, id in
            opening.bindSession(id)
        }
        .task(id: phase) {
            guard let phase else {
                opening.revealProblem()
                return
            }
            guard phase.isReady else {
                if opening.handoff { opening.reset() }
                return
            }
            guard !opening.handoff else { return }
            let fast = opening.usesFastPath
            do {
                try await Task.sleep(for: reduceMotion ? .milliseconds(120)
                                     : fast ? OpeningMotion.quickReadyHold : OpeningMotion.readyHold)
                try Task.checkCancellation()
                opening.beginHandoff(fast: fast)
                try await Task.sleep(for: reduceMotion ? .milliseconds(300) : OpeningMotion.settleDuration)
                opening.finishHandoff()
            } catch { /* A new phase cancels the old handoff. */ }
        }
    }
}

struct CornerGuides: Shape {
    var length: CGFloat = 22
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bounds = rect.insetBy(dx: 1.5, dy: 1.5)
        for (x, y, dx, dy) in [
            (bounds.minX, bounds.minY, CGFloat(1), CGFloat(1)),
            (bounds.maxX, bounds.minY, -1, 1),
            (bounds.maxX, bounds.maxY, -1, -1),
            (bounds.minX, bounds.maxY, 1, -1)
        ] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        return path
    }
}

struct AppOpeningView: View {
    let phase: AppOpeningPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var introduced = false
    @State private var fanned = false
    @State private var textAppeared = false
    @State private var guidesLocked = false
    @State private var captionReady = false
    @State private var glint = false
    @State private var locks = 0

    private var captionPhase: AppOpeningPhase { captionReady ? phase : phase.isReady ? .opening : phase }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OpeningBackdrop(animated: !reduceMotion)
                    .opacity(introduced ? 1 : 0)

                OpeningCardStack(introduced: introduced, fanned: fanned || reduceMotion,
                                 locked: guidesLocked, glint: glint, locks: locks)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                VStack(spacing: 14) {
                    Text("CardScanner")
                        .font(.title2.weight(.bold))
                        .fontWidth(.expanded)
                        .tracking(0.4)
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.74, green: 0.87, blue: 1)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: OpeningPalette.beam.opacity(0.45), radius: 14)
                    OpeningProgressTrack(ready: captionReady, animated: !reduceMotion)
                    Text(captionPhase.caption)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(captionReady ? OpeningPalette.locked : .white.opacity(0.62))
                        .frame(height: 96, alignment: .top)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: captionPhase)
                }
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared || reduceMotion ? 0 : 8)
                .padding(.top, geometry.size.height / 2 + OpeningGeometry.card.height / 2 + 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(OpeningPalette.backdrop)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: locks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.caption.replacingOccurrences(of: "…", with: ""))
        .onAppear {
            // The first frame matches the static launch image; everything else builds from it.
            withAnimation(.easeOut(duration: 0.7)) { introduced = true }
            withAnimation(reduceMotion ? nil : .spring(response: 0.62, dampingFraction: 0.74).delay(0.05)) { fanned = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.12)) { textAppeared = true }
        }
        .task(id: phase) {
            if phase.isReady && !guidesLocked { locks += 1 }
            guidesLocked = phase.isReady
            captionReady = false
            guard phase.isReady else {
                glint = false
                return
            }
            if !reduceMotion { withAnimation(.easeInOut(duration: 0.7).delay(0.12)) { glint = true } }
            do {
                if !reduceMotion { try await Task.sleep(for: OpeningMotion.captionDelay) }
                try Task.checkCancellation()
                captionReady = true
            } catch { /* Superseded readiness never publishes a delayed caption. */ }
        }
    }
}

/// Fanned card stack with the scanner guides that hunt, then lock on.
private struct OpeningCardStack: View {
    let introduced: Bool
    let fanned: Bool
    let locked: Bool
    let glint: Bool
    let locks: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var card: CGSize { OpeningGeometry.card }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OpeningGeometry.cardRadius, style: .continuous)
    }
    private var glowColor: Color { locked ? OpeningPalette.locked : OpeningPalette.beam }

    var body: some View {
        ZStack {
            ForEach(OpeningGeometry.fan.indices, id: \.self) { index in
                let layer = OpeningGeometry.fan[index]
                backCard
                    .opacity(introduced || !reduceMotion ? layer.opacity : 0)
                    .rotationEffect(.degrees(fanned ? layer.angle : 0))
                    .offset(x: fanned ? layer.x : 0, y: fanned ? layer.y : 0)
            }

            frontCard

            if !reduceMotion {
                cardShape
                    .stroke(OpeningPalette.locked, lineWidth: 2)
                    .frame(width: card.width, height: card.height)
                    .keyframeAnimator(initialValue: LockPulse(), trigger: locks) { ring, pulse in
                        ring.scaleEffect(pulse.scale).opacity(pulse.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: 0.16)
                            CubicKeyframe(1.3, duration: 0.6)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: 0.15)
                            LinearKeyframe(0.85, duration: 0.03)
                            CubicKeyframe(0, duration: 0.58)
                        }
                    }
            }

            TimelineView(.animation(paused: reduceMotion || locked)) { timeline in
                OpeningScanBeam()
                    .frame(width: card.width + 72)
                    .offset(y: reduceMotion ? 0 : beamOffset(at: timeline.date))
            }
            .opacity(introduced && !locked ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: locked)

            CornerGuides()
                .stroke(locked ? OpeningPalette.locked : OpeningPalette.seeking,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: glowColor.opacity(introduced ? 0.9 : 0), radius: locked ? 8 : 5)
                .animation(.easeOut(duration: 0.28), value: locked)
                .padding(locked && !reduceMotion ? 0 : -OpeningGeometry.guideInset)
                .frame(width: card.width, height: card.height)
                .phaseAnimator([false, true]) { guides, widened in
                    // Seeking guides breathe until the collection is ready.
                    guides.scaleEffect(widened && !locked && !reduceMotion ? 1.035 : 1)
                } animation: { _ in .easeInOut(duration: 1.1) }
                .animation(reduceMotion ? nil : .spring(response: OpeningMotion.lockResponse, dampingFraction: 0.92), value: locked)
        }
    }

    private var backCard: some View {
        cardShape
            .fill(LinearGradient(colors: [OpeningPalette.cardTop, OpeningPalette.cardBottom],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { cardShape.strokeBorder(.white.opacity(0.4), lineWidth: 1) }
            .frame(width: card.width, height: card.height)
            .compositingGroup()
    }

    private var frontCard: some View {
        cardShape
            .fill(LinearGradient(colors: [OpeningPalette.cardTop, OpeningPalette.cardBottom],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: card.width, height: card.height)
            .overlay {
                cardShape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0),
                                                      .init(color: .white.opacity(0), location: 0.5)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    .padding(9)
            }
            .overlay {
                // A foil glint crosses the card as the guides lock.
                LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 54, height: 280)
                    .rotationEffect(.degrees(18))
                    .offset(x: glint ? 190 : -190)
                    .blendMode(.plusLighter)
            }
            .clipShape(cardShape)
            .overlay { cardShape.strokeBorder(.white.opacity(0.9), lineWidth: 2) }
            // Scoped so the glow's color change never retimes the glint above.
            .animation(.easeOut(duration: 0.4)) { card in
                card.shadow(color: glowColor.opacity(introduced ? 0.55 : 0), radius: 28)
            }
    }

    private func beamOffset(at date: Date) -> CGFloat {
        let period = OpeningMotion.beamPeriod
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return CGFloat(sin(progress * 2 * .pi)) * card.height * 0.42
    }
}

private struct LockPulse {
    var scale: CGFloat = 1
    var opacity: Double = 0
}

/// The icon's scan line: a hot core inside a soft glow that fades at both ends.
private struct OpeningScanBeam: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(OpeningPalette.beam)
                .frame(height: 10)
                .blur(radius: 8)
                .opacity(0.75)
            Capsule()
                .fill(OpeningPalette.beam)
                .frame(height: 3)
                .blur(radius: 1.5)
            Capsule()
                .fill(.white)
                .frame(height: 1.5)
        }
        .frame(height: 28)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                                   .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .blendMode(.plusLighter)
    }
}

/// Slim indeterminate track that fills once the collection is ready. It never
/// fakes a percentage: loading has no honest one.
private struct OpeningProgressTrack: View {
    let ready: Bool
    let animated: Bool

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.12))
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: !animated || ready)) { timeline in
                    GeometryReader { proxy in
                        let width = proxy.size.width * 0.34
                        let sweep: CGFloat = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 3_600) * 2.4)
                        Capsule()
                            .fill(LinearGradient(colors: [OpeningPalette.beam.opacity(0), OpeningPalette.beam,
                                                          OpeningPalette.beam.opacity(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: width)
                            .offset(x: sweep * (proxy.size.width - width))
                    }
                }
                .opacity(ready || !animated ? 0 : 1)
            }
            .overlay {
                Capsule()
                    .fill(OpeningPalette.locked)
                    .scaleEffect(x: ready ? 1 : 0.001, anchor: .leading)
                    .shadow(color: OpeningPalette.locked.opacity(0.8), radius: 4)
            }
            .frame(width: OpeningGeometry.card.width, height: 3)
            .animation(.easeOut(duration: 0.35), value: ready)
            .accessibilityHidden(true)
    }
}

/// Deep-navy stage: a breathing halo, a fading dot grid, and drifting sparks.
private struct OpeningBackdrop: View {
    let animated: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [OpeningPalette.halo.opacity(0.7), OpeningPalette.halo.opacity(0)],
                           center: .center, startRadius: 0, endRadius: 360)
            OpeningDotGrid()
            TimelineView(.animation(paused: !animated)) { timeline in
                Canvas { context, size in
                    Self.draw(in: &context, size: size,
                              time: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center, startRadius: 180, endRadius: 620)
        }
        .allowsHitTesting(false)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let width = Double(size.width)
        let height = Double(size.height)
        guard width > 0, height > 0 else { return }
        // Two slow aurora lobes keep the halo alive behind the card.
        for (index, color) in [OpeningPalette.halo, OpeningPalette.beam].enumerated() {
            let angle = time * 0.3 + Double(index) * Double.pi
            let lobe = CGPoint(x: width / 2 + cos(angle) * 48, y: height / 2 + sin(angle * 0.8) * 64)
            let radius: Double = index == 0 ? 230 : 150
            context.fill(Path(ellipseIn: CGRect(x: lobe.x - radius, y: lobe.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [color.opacity(index == 0 ? 0.5 : 0.16), color.opacity(0)]),
                                               center: lobe, startRadius: 0, endRadius: radius))
        }
        for index in 0..<28 {
            let seed = Double(index)
            let speed = 10 + unit(seed, 2) * 22
            let travel = (unit(seed, 3) * height + time * speed).truncatingRemainder(dividingBy: height)
            let x = unit(seed, 1) * width
            let y = height - travel
            let twinkle = 0.5 + 0.5 * sin(time * (1.2 + unit(seed, 4) * 2.4) + seed)
            let alpha = sin(Double.pi * travel / height) * (0.2 + 0.6 * twinkle)
            let radius = 0.8 + unit(seed, 5) * 1.6
            for (scale, strength) in [(3.2, 0.18), (1.0, 1.0)] {
                let r = radius * scale
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(OpeningPalette.spark.opacity(alpha * strength)))
            }
        }
    }

    /// Stable pseudo-random value in 0..<1 so sparks keep their lanes between frames.
    private static func unit(_ seed: Double, _ salt: Double) -> Double {
        let value = sin(seed * 12.9898 + salt * 78.233) * 43_758.5453
        return value - value.rounded(.down)
    }
}

private struct OpeningDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = max(size.width, size.height) * 0.55
            var y = center.y.truncatingRemainder(dividingBy: spacing)
            while y < size.height {
                var x = center.x.truncatingRemainder(dividingBy: spacing)
                while x < size.width {
                    let falloff = max(0, 1 - hypot(x - center.x, y - center.y) / reach)
                    if falloff > 0 {
                        context.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                                     with: .color(.white.opacity(0.09 * falloff * falloff)))
                    }
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

/// Only this small observer subscribes to portfolio changes at the root.
struct AppOpeningReadinessReporter: View {
    @ObservedObject var portfolio: PortfolioEngine
    @EnvironmentObject private var opening: AppOpeningModel
    let skipsPortfolio: Bool
    let holdsOpening: Bool

    private var ready: Bool {
        !holdsOpening && (skipsPortfolio || portfolio.summary != nil || !portfolio.integrityDefects.isEmpty)
    }

    var body: some View {
        Color.clear
            .onChange(of: ready, initial: true) { _, ready in
                if ready { opening.portfolioDidLoad(copies: skipsPortfolio ? nil : portfolio.summary?.copyCount) }
            }
    }
}
