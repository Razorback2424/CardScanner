import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let catalogCoordinator: PokemonCatalogCoordinator
    private let magicCatalogCoordinator: MagicCatalogCoordinator
    @StateObject private var scannerModel: ScannerViewModel
    @StateObject private var scanSummaryStore = ScanSessionSummaryStore()
    @StateObject private var cardFinishMotion = CardFinishMotionSource()
    @StateObject private var storageBootstrap = CollectionStorageBootstrap()

    init() {
        let catalogCoordinator = PokemonCatalogCoordinator()
        let magicCatalogCoordinator = MagicCatalogCoordinator()
        self.catalogCoordinator = catalogCoordinator
        self.magicCatalogCoordinator = magicCatalogCoordinator
        _scannerModel = StateObject(
            wrappedValue: ScannerViewModel(
                catalog: CardCatalog(magicCatalogCoordinator: magicCatalogCoordinator),
                catalogCoordinator: catalogCoordinator,
                magicCatalogCoordinator: magicCatalogCoordinator
            )
        )
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
                    ContentView(
                        catalogCoordinator: catalogCoordinator,
                        magicCatalogCoordinator: magicCatalogCoordinator
                    )
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
