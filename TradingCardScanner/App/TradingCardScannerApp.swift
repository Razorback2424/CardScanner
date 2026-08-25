import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    @StateObject private var scannerModel = ScannerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scannerModel)
        }
        // Ownership and pricing are separate entities on purpose: a price is a
        // mutable observation about a printing-and-variant, shared by every copy
        // owned, with its own freshness lifecycle.
        .modelContainer(for: [
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self
        ])
    }
}
