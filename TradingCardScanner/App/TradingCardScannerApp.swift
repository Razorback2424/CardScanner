import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @StateObject private var scannerModel = ScannerViewModel()
    private let container = TradingCardScannerApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scannerModel)
        }
        .modelContainer(container)
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
        PriceObservation.self,
        PriceCheckDay.self,
        PortfolioDailyClose.self
    ])

    private static let fullSchema = Schema([
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self,
        InventoryEvent.self,
        PriceObservation.self,
        PriceCheckDay.self,
        PortfolioDailyClose.self
    ])

    /// CloudKit sync is opt-in, decided once per launch from whether the
    /// person is signed in with Apple (`AppleAccountCredentials`) — not from
    /// whatever iCloud account happens to be signed into the device. Signing
    /// in or out again takes effect on the *next* launch rather than
    /// mid-session: SwiftData does not support moving a live store between a
    /// local-only and a CloudKit-mirrored configuration, so
    /// `AccountSettingsSection` says "restart to finish" instead of quietly
    /// doing nothing.
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
                return container
            }
        }
#endif

        let localConfiguration = ModelConfiguration(schema: syncedSchema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(
            for: fullSchema,
            configurations: [localConfiguration, localOnlyConfiguration]
        ) {
            return container
        }

        // Only reachable if even a local store can't be created (disk full,
        // corrupt store) — matches what SwiftData's own `.modelContainer(for:)`
        // convenience modifier does in the same situation.
        fatalError("Could not create a local ModelContainer.")
    }
}
