import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Ownership and pricing are separate entities on purpose: a price is a
        // mutable observation about a printing-and-variant, shared by every copy
        // owned, with its own freshness lifecycle.
        .modelContainer(for: [CollectedCard.self, PriceRecord.self, ProductIdentity.self])
    }
}
