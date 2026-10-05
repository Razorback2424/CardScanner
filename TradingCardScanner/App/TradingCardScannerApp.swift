import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let runtimes: CardGameRuntimeContainer
    @StateObject private var scanSummaryStore = ScanSessionSummaryStore()
    @StateObject private var cardFinishMotion = CardFinishMotionSource()
    @StateObject private var storageBootstrap = CollectionStorageBootstrap()

    init() {
        CollectionWriteSerializer.enforcesOwnershipRule =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        let runtimes = CardGameRuntimeContainer.appDefaults()
        self.runtimes = runtimes
    }

    // Compatibility name for existing portfolio/status call sites. The
    // actual state is owned by CollectionStorageBootstrap.
    typealias StorageMode = CollectionStorageMode
    @MainActor static var activeStorageMode: CollectionStorageMode = .onDevice
    @MainActor static var storageIsReady = false
    @MainActor static var activeStoreID: UUID?
    @MainActor static var activeCloudAccountStatusRaw = "unknown"
    @MainActor static var activeAttachmentStateRaw = "neverAttached"
    @MainActor static var lastBootstrapErrorCategory: String?

    var body: some Scene {
        WindowGroup {
            Group {
                switch storageBootstrap.state {
                case .ready(let session):
                    CollectionSessionContent(runtimes: runtimes, container: session.container)
                        .id(ObjectIdentifier(session.container))
                        .modelContainer(session.container)
                        .environmentObject(scanSummaryStore)
                        .environment(\.cardFinishMotionSource, cardFinishMotion)
                default:
                    CollectionStorageBootstrapView(bootstrap: storageBootstrap)
                }
            }
            .task {
                await storageBootstrap.start()
                await runtimes.refreshCatalogsAtLaunch()
            }
        }
    }

    /// Legacy synchronous callers may only borrow the process-authoritative
    /// session. Fresh/background launches must use the async headless
    /// preflight, which owns the single-container creation decision.
    @MainActor
    static func makeBackgroundContainer() throws -> ModelContainer {
        guard let session = CollectionStorageGeneration.shared.activeSession(),
              session.isAuthoritative else {
            throw CollectionStorageBootstrapError.storageSessionUnavailable
        }
        return session.container
    }
}

/// Runtime consumers are created only after their actual storage session exists.
@MainActor
private struct CollectionSessionContent: View {
    let runtimes: CardGameRuntimeContainer
    let container: ModelContainer
    private struct Services {
        let id = UUID()
        let runtimes: CardGameRuntimeContainer
        let scanner: ScannerViewModel
    }
    @State private var services: Services?
    @State private var failed = false
    @State private var attempt = 0
    @State private var preparing = false

    var body: some View {
        Group {
            if let services {
                VStack(spacing: 0) {
                    if !services.runtimes.unavailableGames.isEmpty {
                        catalogUnavailableBanner(services.runtimes)
                    }
                    ContentView(runtimes: services.runtimes)
                        .environmentObject(services.scanner)
                        .id(services.id)
                }
            } else if failed {
                ContentUnavailableView {
                    Label("Couldn't prepare catalog", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Your collection is safe. Try preparing the catalog again.")
                } actions: {
                    Button("Retry") { failed = false; attempt += 1 }
                }
            } else { ProgressView("Preparing catalog") }
        }
        .task(id: attempt) {
            preparing = true
            defer { preparing = false }
            do {
                // A packaged configuration failure has no source to observe;
                // an explicit retry re-reads configuration and the bundled seed.
                let candidate = runtimes.unavailableGames.isEmpty ? runtimes : CardGameRuntimeContainer.appDefaults()
                let bound = try await candidate.bound(to: container, isCurrent: {
                    CollectionStorageGeneration.shared.activeSession()?.container === container
                })
                try Task.checkCancellation()
                if services == nil || services?.runtimes.registry.games(supporting: []) != bound.registry.games(supporting: [])
                    || services?.runtimes.unavailableGames.map(\.game) != bound.unavailableGames.map(\.game) {
                    services?.scanner.viewDisappeared()
                    services = .init(runtimes: bound, scanner: bound.makeScannerModel())
                }
            } catch is CancellationError {
                return
            } catch { if services == nil { failed = true } }
        }
        .task(id: services?.runtimes.unavailableGames.map(\.game)) {
            guard let services, !services.runtimes.unavailableGames.isEmpty else { return }
            let games = Set(services.runtimes.unavailableGames.map(\.game))
            for await _ in runtimes.optionalCatalogRecoveryEvents(for: games) {
                guard !Task.isCancelled else { break }
                attempt += 1
            }
        }
        .onDisappear { services?.scanner.viewDisappeared() }
    }

    private func unavailableNames(_ bound: CardGameRuntimeContainer) -> String {
        bound.unavailableGames.map(\.displayName).joined(separator: ", ")
    }

    private func catalogUnavailableBanner(_ bound: CardGameRuntimeContainer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(unavailableNames(bound)) catalog unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("Your collection is safe. Other games are available while we try to restore this catalog.")
                .font(.subheadline)
            Button(preparing ? "Retrying…" : "Retry catalog") { attempt += 1 }
                .disabled(preparing)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}
