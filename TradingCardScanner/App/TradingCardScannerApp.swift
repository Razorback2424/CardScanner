import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var runtimes: CardGameRuntimeContainer?
    @StateObject private var scanSummaryStore = ScanSessionSummaryStore()
    @StateObject private var cardFinishMotion = CardFinishMotionSource()
    @StateObject private var storageBootstrap = PerformanceSignpost.measureLaunch("Launch.storageDependencies") {
        CollectionStorageBootstrap()
    }
    @StateObject private var opening = AppOpeningModel()
    @StateObject private var collectorTools = CollectorToolsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CollectionWriteSerializer.enforcesOwnershipRule =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        // Catalog registration is the slower half of launch preparation; start
        // it now rather than when the first frame schedules the launch task.
        PerformanceSignpost.measureLaunch("Launch.startCatalogPreparation") {
            CardGameRuntimeContainer.startPreparingAppDefaults()
        }
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
    @State private var retryStillUnavailable = false
    @AppStorage("catalogRecoveryAcknowledgedGames") private var acknowledgedCatalogGames = ""

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
                    if !visibleUnavailableGames.isEmpty {
                        CatalogRecoveryBanner(
                            names: visibleUnavailableGames.map(\.displayName).joined(separator: ", "),
                            scanner: services.scanner,
                            preparing: preparing,
                            recoveryReady: recoveryReady,
                            retryStillUnavailable: retryStillUnavailable,
                            dismiss: dismissCatalogWarning,
                            reload: retryCatalogs
                        )
                    }
                    PerformanceSignpost.measureLaunch("Launch.contentViewInit") {
                        ContentView(runtimes: services.runtimes)
                    }
                        .environmentObject(services.scanner)
                        .environment(\.catalogRecoveryContext, CatalogRecoveryContext(
                            unavailableGames: services.runtimes.unavailableGames,
                            preparing: preparing,
                            recoveryReady: recoveryReady,
                            retryStillUnavailable: retryStillUnavailable,
                            retry: retryCatalogs
                        ))
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
                func bindDefault() async throws -> CardGameRuntimeContainer {
                    // The first binding defers static price withdrawal to ContentView's
                    // launch task, so opening the collection does not wait on it.
                    return try await candidate.bound(to: container, recovering: services?.runtimes,
                                                      deferringPriceAuthorityInstall: services == nil, isCurrent: {
                        CollectionStorageGeneration.shared.activeSession()?.container === container
                    })
                }
                let bound: CardGameRuntimeContainer
#if DEBUG && LOCAL_ONLY_SIGNING
                if LorcanaReviewLaunch.isEnabled() {
                    let kit = try LorcanaReviewLaunch.makeKit()
                    bound = try await kit.bound(to: container, isCurrent: {
                        CollectionStorageGeneration.shared.activeSession()?.container === container
                    })
                } else {
                    bound = try await bindDefault()
                }
#else
                bound = try await bindDefault()
#endif
                try Task.checkCancellation()
                guard CollectionStorageGeneration.shared.activeSession()?.container === container,
                      services?.scanner.canReloadCatalogs != false else { return }
                // A recovered game is no longer acknowledged; a later failure
                // must be visible again, even if the warning was once dismissed.
                acknowledgedCatalogGames = CatalogRecoveryAcknowledgements.retaining(
                    acknowledgedCatalogGames, unavailable: bound.unavailableGames
                )
                retryStillUnavailable = services != nil && !bound.unavailableGames.isEmpty
                if services == nil || services?.runtimes.registry.games(supporting: []) != bound.registry.games(supporting: [])
                    || services?.runtimes.unavailableGames.map(\.game) != bound.unavailableGames.map(\.game) {
                    services?.scanner.viewDisappeared()
                    services = .init(runtimes: bound, scanner: bound.makeScannerModel())
                    recoveryReady = false
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      CollectionStorageGeneration.shared.activeSession()?.container === container else { return }
                if services == nil {
                    failed = true
                    opening.blocked = true
                } else {
                    retryStillUnavailable = true
                }
            }
        }
        .task(id: services?.runtimes.unavailableGames.map(\.game)) {
            guard let services, !services.runtimes.unavailableGames.isEmpty else { return }
            let games = Set(services.runtimes.unavailableGames.map(\.game))
            for await _ in runtimes.optionalCatalogRecoveryEvents(for: games) {
                guard !Task.isCancelled else { break }
                recoveryReady = true
                retryStillUnavailable = false
            }
        }
        .onDisappear { services?.scanner.viewDisappeared() }
    }

    private var visibleUnavailableGames: [CardGameDescriptor] {
        CatalogRecoveryAcknowledgements.visible(
            services?.runtimes.unavailableGames ?? [], acknowledged: acknowledgedCatalogGames
        )
    }

    private func dismissCatalogWarning() {
        acknowledgedCatalogGames = CatalogRecoveryAcknowledgements.acknowledging(
            acknowledgedCatalogGames, unavailable: visibleUnavailableGames
        )
    }

    private func retryCatalogs() {
        guard !preparing, services?.scanner.canReloadCatalogs == true else { return }
        retryStillUnavailable = false
        recoveryReady = false
        attempt += 1
    }
}

@MainActor
private struct CatalogRecoveryBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let names: String
    @ObservedObject var scanner: ScannerViewModel
    let preparing: Bool
    let recoveryReady: Bool
    let retryStillUnavailable: Bool
    let dismiss: () -> Void
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(names)
                    } else {
                        Label("\(names) catalog unavailable", systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss catalog warning")
                .accessibilityHint("Catalog status and retry remain available in Settings")
            }
            message
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: reload) {
                Text(actionTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(preparing || !scanner.canReloadCatalogs)
            .buttonStyle(.bordered)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }

    private var actionTitle: LocalizedStringKey {
        if preparing { return "Retrying…" }
        if recoveryReady { return dynamicTypeSize.isAccessibilitySize ? "Reload" : "Reload catalog" }
        return dynamicTypeSize.isAccessibilitySize ? "Retry" : "Retry catalog"
    }

    private var message: Text {
        if dynamicTypeSize.isAccessibilitySize {
            if recoveryReady { return Text("Update ready. Finish scanning first.") }
            if retryStillUnavailable { return Text("Still unavailable. Retry here or in Settings.") }
            return Text("Catalog unavailable. Retry here or in Settings.")
        }
        if retryStillUnavailable {
            return Text("The catalog is still unavailable. You can try again here or in Settings.")
        } else if recoveryReady {
            return Text("A catalog update is available. Reloading returns you to the main screen. Finish scanning first.")
        } else {
            return Text("Your collection is safe. Other games are available. You can also retry in Settings.")
        }
    }
}

/// Dismissal is a presentation preference only. It never changes the registry,
/// available capabilities, catalog loading, or the safety gate on retry.
enum CatalogRecoveryAcknowledgements {
    private static func identifiers(in encoded: String) -> Set<String> {
        Set(encoded.split(separator: ",").map(String.init))
    }

    static func visible(_ unavailable: [CardGameDescriptor], acknowledged: String) -> [CardGameDescriptor] {
        let hidden = identifiers(in: acknowledged)
        return unavailable.filter { !hidden.contains($0.game.rawValue) }
    }

    static func acknowledging(_ existing: String, unavailable: [CardGameDescriptor]) -> String {
        identifiers(in: existing)
            .union(unavailable.map { $0.game.rawValue })
            .sorted().joined(separator: ",")
    }

    static func retaining(_ existing: String, unavailable: [CardGameDescriptor]) -> String {
        identifiers(in: existing)
            .intersection(unavailable.map { $0.game.rawValue })
            .sorted().joined(separator: ",")
    }
}

/// The same live recovery action is available from Settings after a banner is
/// dismissed. Keeping this separate from acknowledgment avoids false success.
struct CatalogRecoveryContext {
    let unavailableGames: [CardGameDescriptor]
    let preparing: Bool
    let recoveryReady: Bool
    let retryStillUnavailable: Bool
    let retry: () -> Void
}

private struct CatalogRecoveryContextKey: EnvironmentKey {
    static let defaultValue: CatalogRecoveryContext? = nil
}

extension EnvironmentValues {
    var catalogRecoveryContext: CatalogRecoveryContext? {
        get { self[CatalogRecoveryContextKey.self] }
        set { self[CatalogRecoveryContextKey.self] = newValue }
    }
}
