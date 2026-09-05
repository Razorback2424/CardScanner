import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var scannerModel = ScannerViewModel()
    enum StorageMode: Equatable {
        case cloudKit
        case localOnly

        var label: String {
            switch self {
            case .cloudKit: return "iCloud sync enabled"
            case .localOnly: return "On this device only"
            }
        }

        var detail: String {
            switch self {
            case .cloudKit:
                return "The collection uses this device's iCloud account."
            case .localOnly:
                return "The collection is stored locally; this launch is not using a CloudKit-backed container."
            }
        }

        var isCloudSyncing: Bool {
            self == .cloudKit
        }
    }

    /// The actual SwiftData configuration selected during this launch. This is
    /// intentionally separate from Sign in with Apple: that credential gates
    /// whether the cloud configuration is attempted, while CloudKit uses the
    /// device's iCloud account for its private database.
    private(set) static var activeStorageMode: StorageMode = .localOnly

    static let container: ModelContainer = {
        let container = TradingCardScannerApp.makeContainer()
        CollectionArtworkStore.migrateLegacyMappings(in: ModelContext(container))
        return container
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scannerModel)
        }
        .modelContainer(Self.container)
    }

    // Ownership and pricing are separate entities on purpose: a price is a
    // mutable observation about a printing-and-variant, shared by every copy
    // owned, with its own freshness lifecycle.
    private static let syncedSchema = Schema([
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self,
        InventoryEvent.self
    ])

    /// The portfolio's knowledge history, which never leaves the device.
    ///
    /// Not a storage optimisation. These tables record *when this phone learned
    /// what* — every price observation it received and every day it
    /// successfully checked. Two devices with different refresh schedules
    /// legitimately have different knowledge histories, and merging them would
    /// produce a history neither device actually observed. Closes converge once
    /// there is a shared, instrument-keyed pricing service to derive them from;
    /// until then, honest and device-local beats synced and invented.
    private static let localOnlySchema = Schema([
        ReferenceQuote.self,
        PriceObservation.self,
        PriceCheckDay.self,
        PortfolioDailyClose.self,
        LocalArtworkOverride.self
    ])

    private static let fullSchema = Schema([
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self,
        InventoryEvent.self,
        ReferenceQuote.self,
        PriceObservation.self,
        PriceCheckDay.self,
        PortfolioDailyClose.self,
        LocalArtworkOverride.self
    ])

    /// CloudKit sync is attempted once per launch when the app's sign-in gate
    /// is present. The private database itself belongs to the device's iCloud
    /// account, not the Sign in with Apple credential. Signing in or out again
    /// takes effect on the next launch rather than mid-session: SwiftData does
    /// not support moving a live store between a local-only and a CloudKit-
    /// mirrored configuration, so `AccountSettingsSection` says "restart to
    /// finish" instead of quietly doing nothing.
    ///
    /// If a CloudKit-backed container can't actually be created — the
    /// expected case during development without a paid Apple Developer
    /// Program membership provisioning the iCloud capability — this falls
    /// back to a local-only container instead of crashing. Local persistence
    /// is the fallback in both the literal and the design sense: sync is
    /// additive, never a requirement to use the app.
    private static func makeContainer() -> ModelContainer {
        // A separate store for the local-only models, so CloudKit mirroring is
        // decided per configuration rather than per container.
        let localOnlyConfiguration = ModelConfiguration(
            "PortfolioLocal",
            schema: localOnlySchema,
            cloudKitDatabase: .none
        )

        // A build signed by a personal Apple Developer team cannot carry the
        // iCloud entitlement at all, so there is nothing to attempt. The
        // fallback below is the same one used when CloudKit is unavailable for
        // any other reason — this just skips a request that is known to fail.
#if !LOCAL_ONLY_SIGNING
        if AppleAccountCredentials.isSignedIn {
            let cloudConfiguration = ModelConfiguration(schema: syncedSchema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(
                for: fullSchema,
                configurations: [cloudConfiguration, localOnlyConfiguration]
            ) {
                activeStorageMode = .cloudKit
                return container
            }
        }
#endif

        let localConfiguration = ModelConfiguration(schema: syncedSchema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(
            for: fullSchema,
            configurations: [localConfiguration, localOnlyConfiguration]
        ) {
            activeStorageMode = .localOnly
            return container
        }

        // Only reachable if even a local store can't be created (disk full,
        // corrupt store) — matches what SwiftData's own `.modelContainer(for:)`
        // convenience modifier does in the same situation.
        fatalError("Could not create a local ModelContainer.")
    }
}
