import SwiftUI

/// ScanStash brand tokens shared by the app icon, LaunchMark, and opening.
enum AppPalette {
    /// Foil stops, top-leading to bottom-trailing: mint, sky, iris, rose.
    static let foil: [Color] = [
        Color(red: 124 / 255, green: 247 / 255, blue: 218 / 255),
        Color(red: 92 / 255, green: 200 / 255, blue: 255 / 255),
        Color(red: 154 / 255, green: 140 / 255, blue: 255 / 255),
        Color(red: 255 / 255, green: 150 / 255, blue: 214 / 255)
    ]
    static let ink = Color(red: 43 / 255, green: 37 / 255, blue: 133 / 255)
}

/// Reveal content as soon as the local result exists; settle the opening
/// artwork afterward without delaying interaction.
private enum OpeningMotion {
    static let lockResponse = 0.34
    static let captionDelay: Duration = .milliseconds(180)
    static let revealDuration = 0.48
    static let settleDuration: Duration = .milliseconds(620)
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

    /// How long a mounted collection waits for its first portfolio summary
    /// before the opening reveals it anyway. A fast replay keeps the copy-count
    /// caption; a slow one reveals Portfolio's own calculating state.
    static let portfolioRevealBudget: Duration = .milliseconds(350)

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
                    .scaleEffect(opening.handoff && !reduceMotion && !opening.fastHandoff ? 1.06 : 1)
                    .animation(reduceMotion || opening.fastHandoff ? nil : .smooth(duration: 0.60), value: opening.handoff)
                    .allowsHitTesting(false)
                    .accessibilityHidden(opening.handoff)
                    // Keep system status chrome out of the full-bleed opening stage.
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
                try Task.checkCancellation()
                PerformanceSignpost.emitEvent("Launch.handoff", fast ? "fast" : "settled")
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

/// The ScanStash mark: a foil card on top of a fanned stash. Its unfanned,
/// unlocked, unswept state is drawn into LaunchMark, so keep the two in step.
struct ScanStashMark: View {
    static let cardSize = CGSize(width: 112, height: 156)
    static let openGuideInset: CGFloat = 14
    static let lockedGuideInset: CGFloat = 5

    var fanned: Bool
    var locked: Bool
    var sheenSwept: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { colorScheme == .dark }
    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        ZStack {
            stashCard(depth: 2)
            stashCard(depth: 1)
            faceCard
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .overlay {
            CornerGuides()
                .stroke(locked ? Color("OpeningReadyGreen") : Color(uiColor: .secondaryLabel),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .animation(.easeOut(duration: 0.28), value: locked)
                .padding(-(locked && !reduceMotion ? Self.lockedGuideInset : Self.openGuideInset))
                .animation(reduceMotion ? nil : .spring(response: OpeningMotion.lockResponse, dampingFraction: 0.86), value: locked)
        }
    }

    /// Stash cards pivot below the deck like a hand of cards.
    private func stashCard(depth: Int) -> some View {
        card
            .fill(isDark ? Color.white.opacity(depth == 1 ? 0.20 : 0.11)
                         : AppPalette.ink.opacity(depth == 1 ? 0.16 : 0.09))
            .overlay { card.strokeBorder(isDark ? Color.white.opacity(0.22) : AppPalette.ink.opacity(0.16), lineWidth: 1) }
            .rotationEffect(.degrees(fanned || reduceMotion ? Double(depth) * -8 : 0),
                            anchor: UnitPoint(x: 0.5, y: 1.4))
            .opacity(fanned ? 1 : 0)
    }

    private var faceCard: some View {
        card
            .fill(LinearGradient(colors: AppPalette.foil, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.26))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                        }
                        .frame(height: 84)
                    Capsule().fill(.white.opacity(0.75)).frame(width: 52, height: 7).padding(.top, 6)
                    Capsule().fill(.white.opacity(0.45)).frame(width: 34, height: 7)
                }
                .padding(9)
            }
            .overlay {
                LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0.30),
                    .init(color: .white.opacity(0.45), location: 0.42),
                    .init(color: .white.opacity(0), location: 0.50)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .offset(x: sheenSwept ? Self.cardSize.width * 1.3 : 0)
                .clipShape(card)
            }
            .overlay { card.strokeBorder(isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1) }
            .shadow(color: isDark ? Color.black.opacity(0.55) : AppPalette.ink.opacity(0.22), radius: 14, y: 8)
    }
}

struct AppOpeningView: View {
    let phase: AppOpeningPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var textAppeared = false
    @State private var stashFanned = false
    @State private var guidesLocked = false
    @State private var sheenSwept = false
    @State private var captionReady = false

    private var captionPhase: AppOpeningPhase { captionReady ? phase : phase.isReady ? .opening : phase }
    private var markHalfHeight: CGFloat { ScanStashMark.cardSize.height / 2 + ScanStashMark.openGuideInset }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Color("LaunchBackground")
                aurora
                    .position(center)
                    .opacity(stashFanned ? 1 : 0)
                    .animation(.easeOut(duration: 0.7), value: stashFanned)

                ScanStashMark(fanned: stashFanned, locked: guidesLocked, sheenSwept: sheenSwept)
                    .position(center)

                VStack(spacing: 10) {
                    Text("ScanStash")
                        .font(.system(.title, design: .default, weight: .bold))
                        .fontWidth(.expanded)
                        .tracking(-0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        ZStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(AppPalette.foil[2])
                                .symbolEffect(.pulse, options: .repeating, isActive: !captionReady && !reduceMotion)
                                .opacity(captionReady ? 0 : 1)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color("OpeningReadyGreen"))
                                .symbolEffect(.bounce, value: reduceMotion ? false : captionReady)
                                .opacity(captionReady ? 1 : 0)
                        }
                        .font(.subheadline.weight(.semibold))
                        Text(captionPhase.caption)
                            .monospacedDigit()
                            .foregroundStyle(captionReady ? Color("OpeningReadyGreen") : .secondary)
                            .contentTransition(.opacity)
                    }
                    .font(.subheadline.weight(.medium))
                    .animation(.easeInOut(duration: 0.25), value: captionPhase)
                    .frame(height: 96, alignment: .top)
                }
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared || reduceMotion ? 0 : 6)
                .padding(.top, geometry.size.height / 2 + markHalfHeight + 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.caption.replacingOccurrences(of: "…", with: ""))
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) { textAppeared = true }
            withAnimation(reduceMotion ? .easeOut(duration: 0.24) : .spring(response: 0.55, dampingFraction: 0.78)) {
                stashFanned = true
            }
        }
        .task(id: phase) {
            guidesLocked = phase.isReady
            captionReady = false
            sheenSwept = false
            guard phase.isReady else { return }
            if !reduceMotion { withAnimation(.easeInOut(duration: 0.8)) { sheenSwept = true } }
            do {
                if !reduceMotion { try await Task.sleep(for: OpeningMotion.captionDelay) }
                try Task.checkCancellation()
                captionReady = true
            } catch { /* Superseded readiness never publishes a delayed caption. */ }
        }
    }

    /// Two soft foil blooms behind the mark; launch shows none, so it fades in.
    private var aurora: some View {
        let strength = colorScheme == .dark ? 0.20 : 0.26
        return ZStack {
            RadialGradient(colors: [AppPalette.foil[0].opacity(strength), .clear],
                           center: .center, startRadius: 0, endRadius: 170)
                .offset(x: -48, y: -40)
            RadialGradient(colors: [AppPalette.foil[2].opacity(strength), .clear],
                           center: .center, startRadius: 0, endRadius: 190)
                .offset(x: 44, y: 46)
        }
        .frame(width: 460, height: 460)
    }
}

/// Only this small observer subscribes to portfolio changes at the root.
struct AppOpeningReadinessReporter: View {
    @ObservedObject var portfolio: PortfolioEngine
    @EnvironmentObject private var opening: AppOpeningModel
    let skipsPortfolio: Bool
    let holdsOpening: Bool
    var revealBudget: Duration = AppOpeningModel.portfolioRevealBudget
    @State private var budgetElapsed = false

    private var ready: Bool {
        !holdsOpening && (skipsPortfolio || portfolio.summary != nil || !portfolio.integrityDefects.isEmpty
            || budgetElapsed)
    }

    var body: some View {
        Color.clear
            .onChange(of: ready, initial: true) { _, ready in
                guard ready else { return }
                // Past the budget without a summary, the caption has no count.
                opening.portfolioDidLoad(copies: skipsPortfolio ? nil : portfolio.summary?.copyCount)
            }
            .task {
                PerformanceSignpost.emitEvent("Launch.contentMounted", "")
                try? await Task.sleep(for: revealBudget)
                guard !Task.isCancelled else { return }
                budgetElapsed = true
            }
    }
}
