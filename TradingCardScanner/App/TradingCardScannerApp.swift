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
    private static let schema = Schema([
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self
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
        if AppleAccountCredentials.isSignedIn {
            let cloudConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
                return container
            }
        }

        let localConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }

        // Only reachable if even a local store can't be created (disk full,
        // corrupt store) — matches what SwiftData's own `.modelContainer(for:)`
        // convenience modifier does in the same situation.
        fatalError("Could not create a local ModelContainer.")
    }
}
