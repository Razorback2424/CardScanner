import SwiftUI

enum AppPalette {
    static let mark = Color(red: 23 / 255, green: 151 / 255, blue: 159 / 255)
}

/// Presentation time starts only after the local result exists. Keep the
/// lock readable, then release it without imposing a minimum loading screen.
private enum OpeningMotion {
    static let lockResponse = 0.34
    static let captionDelay: Duration = .milliseconds(180)
    static let readyHold: Duration = .milliseconds(720)
    static let quickReadyHold: Duration = .milliseconds(420)
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
                    .scaleEffect(opening.handoff && !reduceMotion && !opening.fastHandoff ? 1.02 : 1)
                    .animation(reduceMotion || opening.fastHandoff ? nil : .smooth(duration: 0.60), value: opening.handoff)
                    .allowsHitTesting(false)
                    .accessibilityHidden(opening.handoff)
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
    @State private var textAppeared = false
    @State private var guidesLocked = false
    @State private var captionReady = false

    private var captionPhase: AppOpeningPhase { captionReady ? phase : phase.isReady ? .opening : phase }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .overlay {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(AppPalette.mark)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color("OpeningReadyGreen").opacity(guidesLocked ? 0.20 : 0), lineWidth: 1)
                            .animation(.easeOut(duration: 0.30), value: guidesLocked)
                    }
                    .overlay {
                        CornerGuides()
                            .stroke(guidesLocked ? Color(uiColor: .systemGreen) : Color(uiColor: .secondaryLabel),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .animation(.easeOut(duration: 0.28), value: guidesLocked)
                            .padding(guidesLocked && !reduceMotion ? 0 : -12)
                            .animation(reduceMotion ? nil : .spring(response: OpeningMotion.lockResponse, dampingFraction: 0.92), value: guidesLocked)
                    }
                    .frame(width: 132, height: 185)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                VStack(spacing: 6) {
                    Text("CardScanner")
                        .font(.title2.weight(.semibold))
                    Text(captionPhase.caption)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(captionReady ? Color("OpeningReadyGreen") : .secondary)
                        .frame(height: 96, alignment: .top)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: captionPhase)
                }
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared || reduceMotion ? 0 : 5)
                .padding(.top, geometry.size.height / 2 + 92.5 + 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.caption.replacingOccurrences(of: "…", with: ""))
        .onAppear { withAnimation(.easeOut(duration: 0.32)) { textAppeared = true } }
        .task(id: phase) {
            guidesLocked = phase.isReady
            captionReady = false
            guard phase.isReady else { return }
            do {
                if !reduceMotion { try await Task.sleep(for: OpeningMotion.captionDelay) }
                try Task.checkCancellation()
                captionReady = true
            } catch { /* Superseded readiness never publishes a delayed caption. */ }
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
