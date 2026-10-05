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
        let runtimes: CardGameRuntimeContainer
        let scanner: ScannerViewModel
    }
    @State private var services: Services?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let services {
                ContentView(runtimes: services.runtimes).environmentObject(services.scanner)
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
            guard services == nil else { return }
            do {
                let bound = try await runtimes.bound(to: container, isCurrent: {
                    CollectionStorageGeneration.shared.activeSession()?.container === container
                })
                services = .init(runtimes: bound, scanner: bound.makeScannerModel())
            } catch { failed = true }
        }
        .onDisappear { services?.scanner.viewDisappeared() }
    }
}
