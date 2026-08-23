import SwiftUI
import SwiftData

@main
struct TradingCardScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: CollectedCard.self)
    }
}
