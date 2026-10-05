import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtimes: CardGameRuntimeContainer?
    @StateObject private var scanSummaryStore = ScanSessionSummaryStore()
    @StateObject private var cardFinishMotion = CardFinishMotionSource()
    @StateObject private var storageBootstrap = CollectionStorageBootstrap()

    init() {
        CollectionWriteSerializer.enforcesOwnershipRule =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
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
                    if let runtimes {
                        CollectionSessionContent(runtimes: runtimes, container: session.container)
                            .id(ObjectIdentifier(session.container))
                            .modelContainer(session.container)
                            .environmentObject(scanSummaryStore)
                            .environment(\.cardFinishMotionSource, cardFinishMotion)
                    } else { ProgressView("Preparing catalog") }
                default:
                    CollectionStorageBootstrapView(bootstrap: storageBootstrap)
                }
            }
            .task {
                guard runtimes == nil else { return }
                async let prepared = CardGameRuntimeContainer.preparedAppDefaults()
                await storageBootstrap.start()
                let runtimes = await prepared
                guard !Task.isCancelled else { return }
                self.runtimes = runtimes
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
    @State private var recoveryReady = false

    var body: some View {
        Group {
            if let services {
                VStack(spacing: 0) {
                    if !services.runtimes.unavailableGames.isEmpty {
                        CatalogRecoveryBanner(names: unavailableNames(services.runtimes),
                            scanner: services.scanner, preparing: preparing, recoveryReady: recoveryReady) { attempt += 1 }
                    }
                    ContentView(runtimes: services.runtimes)
                        .environmentObject(services.scanner)
                        .id(services.id)
                        .disabled(preparing)
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
                guard services?.scanner.canReloadCatalogs != false else { return }
                let candidate = runtimes.unavailableGames.isEmpty ? runtimes : await CardGameRuntimeContainer.preparedAppDefaults()
                let bound = try await candidate.bound(to: container, recovering: services?.runtimes, isCurrent: {
                    CollectionStorageGeneration.shared.activeSession()?.container === container
                })
                try Task.checkCancellation()
                guard services?.scanner.canReloadCatalogs != false else { return }
                if services == nil || services?.runtimes.registry.games(supporting: []) != bound.registry.games(supporting: [])
                    || services?.runtimes.unavailableGames.map(\.game) != bound.unavailableGames.map(\.game) {
                    services?.scanner.viewDisappeared()
                    services = .init(runtimes: bound, scanner: bound.makeScannerModel())
                    recoveryReady = false
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
                recoveryReady = true
            }
        }
        .onDisappear { services?.scanner.viewDisappeared() }
    }

    private func unavailableNames(_ bound: CardGameRuntimeContainer) -> String {
        bound.unavailableGames.map(\.displayName).joined(separator: ", ")
    }

}

@MainActor
private struct CatalogRecoveryBanner: View {
    let names: String
    @ObservedObject var scanner: ScannerViewModel
    let preparing: Bool
    let recoveryReady: Bool
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(names) catalog unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(recoveryReady
                 ? "A catalog update is available. Reload when you’re ready; this returns you to the main screen. Finish scanning first."
                 : "Your collection is safe. Other games are available. Finish scanning before retrying this catalog.")
                .font(.subheadline)
            Button(preparing ? "Retrying…" : recoveryReady ? "Reload catalog" : "Retry catalog", action: reload)
                .disabled(preparing || !scanner.canReloadCatalogs)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}
