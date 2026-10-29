import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtimes: CardGameRuntimeContainer?
    @StateObject private var scanSummaryStore = ScanSessionSummaryStore()
    @StateObject private var cardFinishMotion = CardFinishMotionSource()
    @StateObject private var storageBootstrap = CollectionStorageBootstrap()
    @StateObject private var opening = AppOpeningModel()
    @StateObject private var collectorTools = CollectorToolsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CollectionWriteSerializer.enforcesOwnershipRule =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        // Catalog registration is the slower half of launch preparation; start
        // it now rather than when the first frame schedules the launch task.
        CardGameRuntimeContainer.startPreparingAppDefaults()
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
        // Register these scene dependencies before building the overlay host.
        // Storage can finish before catalog preparation; that later runtime
        // publication must rebuild the session branch as well.
        let storageState = storageBootstrap.state
        let preparedRuntimes = runtimes
        return WindowGroup {
            AppOpeningContainer(bootstrap: storageBootstrap, opening: opening) {
                switch storageState {
                case .ready(let session):
                    if let runtimes = preparedRuntimes {
                        CollectionSessionContent(runtimes: runtimes, container: session.container)
                            .id(ObjectIdentifier(session.container))
                            .modelContainer(session.container)
                            .environmentObject(scanSummaryStore)
                            .environment(\.cardFinishMotionSource, cardFinishMotion)
                    }
                default:
                    CollectionStorageBootstrapView(bootstrap: storageBootstrap)
                }
            }
            .environmentObject(opening)
            .task { collectorTools.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await collectorTools.reconcile() } }
            }
            .task {
                guard runtimes == nil else { return }
#if DEBUG && LOCAL_ONLY_SIGNING
                if LorcanaReviewLaunch.isEnabled() {
                    await storageBootstrap.start()
                    guard !Task.isCancelled else { return }
                    // Actual review authority is installed below, only after
                    // checking the process-authoritative isolated container.
                    self.runtimes = try? CardGameRuntimeContainer(runtimes: [])
                    return
                }
#endif
                async let prepared = CardGameRuntimeContainer.takePreparedAppDefaults()
                let storageInterval = PerformanceSignpost.beginInterval("Launch.storageStart", id: PerformanceSignpost.makeID(), "")
                await storageBootstrap.start()
                PerformanceSignpost.endInterval("Launch.storageStart", storageInterval, "")
                let runtimes = await prepared
                guard !Task.isCancelled else { return }
                self.runtimes = runtimes
                await runtimes.refreshCatalogsAtLaunch()
            }
        }
    }
}

/// Runtime consumers are created only after their actual storage session exists.
@MainActor
private struct CollectionSessionContent: View {
    @EnvironmentObject private var opening: AppOpeningModel
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
#if DEBUG && LOCAL_ONLY_SIGNING
                    if LorcanaReviewLaunch.isEnabled() {
                        Label(LorcanaReviewLaunch.banner, systemImage: "testtube.2")
                            .font(.caption2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.regularMaterial)
                            .accessibilityIdentifier("lorcana-review-banner")
                    }
#endif
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
                    Button("Retry") { opening.reset(); failed = false; attempt += 1 }
                }
            } else {
                // The overlay covers this wait, but the Group needs a child
                // or its preparation task below never runs.
                Color.clear
            }
        }
        .task(id: attempt) {
            preparing = true
            defer { preparing = false }
            do {
                // A packaged configuration failure has no source to observe;
                // an explicit retry re-reads configuration and the bundled seed.
                guard services?.scanner.canReloadCatalogs != false else { return }
                let candidate = runtimes.unavailableGames.isEmpty ? runtimes : await CardGameRuntimeContainer.preparedAppDefaults()
                let bound: CardGameRuntimeContainer
#if DEBUG && LOCAL_ONLY_SIGNING
                if LorcanaReviewLaunch.isEnabled() {
                    let kit = try LorcanaReviewLaunch.makeKit()
                    bound = try await kit.bound(to: container, isCurrent: {
                        CollectionStorageGeneration.shared.activeSession()?.container === container
                    })
                } else {
                    // The first binding defers static price withdrawal to ContentView's
                    // launch task, so opening the collection does not wait on it.
                    bound = try await candidate.bound(to: container, recovering: services?.runtimes,
                                                      deferringPriceAuthorityInstall: services == nil, isCurrent: {
                        CollectionStorageGeneration.shared.activeSession()?.container === container
                    })
                }
#else
                // The first binding defers static price withdrawal to ContentView's
                // launch task, so opening the collection does not wait on it.
                bound = try await candidate.bound(to: container, recovering: services?.runtimes,
                                                  deferringPriceAuthorityInstall: services == nil, isCurrent: {
                    CollectionStorageGeneration.shared.activeSession()?.container === container
                })
#endif
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
            } catch {
                if services == nil {
                    failed = true
                    opening.blocked = true
                }
            }
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
