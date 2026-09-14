import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var scannerModel = ScannerViewModel()
    @StateObject private var scanSummaryStore = ScanSessionSummaryStore()
    @StateObject private var cardFinishMotion = CardFinishMotionSource()
    @StateObject private var storageBootstrap = CollectionStorageBootstrap()

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
                    ContentView()
                        .modelContainer(session.container)
                        .environmentObject(scannerModel)
                        .environmentObject(scanSummaryStore)
                        .environment(\.cardFinishMotionSource, cardFinishMotion)
                default:
                    CollectionStorageBootstrapView(bootstrap: storageBootstrap)
                }
            }
            .task {
                await storageBootstrap.start()
            }
        }
    }

    /// Background Tasks runs in a fresh process. It may create a new
    /// explicitly identified container only after the app-level bootstrap has
    /// established that storage is ready; it never shares a global container.
    @MainActor
    static func makeBackgroundContainer() throws -> ModelContainer {
        try CollectionStorageBootstrapDependencies.makeContainer(
            paths: CollectionStoragePaths.production(),
            mode: activeStorageMode
        )
    }
}
