import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    private enum Tab: Hashable {
        case collection
        case browse
        case scan
        case centering
    }

    @State private var selectedTab: Tab
#if DEBUG
    private let debugRoute: String?
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        debugRoute = route
        _selectedTab = State(initialValue: route == "Browse" ? .browse : .collection)
#else
        _selectedTab = State(initialValue: .collection)
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "rectangle.stack")
                }
                .tag(Tab.collection)

            BrowseView()
                .tabItem {
                    Label("Browse", systemImage: "square.grid.2x2")
                }
                .tag(Tab.browse)

            ScannerView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }
                .tag(Tab.scan)

            CardCenteringView()
                .tabItem {
                    Label("Centering", systemImage: "square.dashed.inset.filled")
                }
                .tag(Tab.centering)
        }
#if DEBUG
        .task {
            guard debugRoute == "SealedArtwork" else { return }
            seedSealedArtworkQA()
        }
#endif
    }

#if DEBUG
    @MainActor
    private func seedSealedArtworkQA() {
        let store = CollectionStore(context: modelContext)
        let artworkURL = URL(
            string: "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        )
        _ = store.addSealed(
            SealedProductSummary(
                id: "ui-artwork-product",
                name: "Legendary Treasures Booster Box",
                setName: "Legendary Treasures",
                variantID: "ui-artwork-variant",
                marketPriceUSD: 18_750,
                updatedAt: .now,
                imageURL: artworkURL
            ),
            game: .pokemon
        )

        let unavailable = store.addSealed(
            SealedProductSummary(
                id: "ui-no-artwork-product",
                name: "Provider Artwork Missing",
                setName: "Artwork Diagnostics",
                variantID: "ui-no-artwork-variant",
                marketPriceUSD: 25,
                updatedAt: .now,
                imageURL: nil
            ),
            game: .pokemon
        )
        if let row = store.card(forKey: unavailable.collectionKey) {
            row.catalogMetadataCheckedAt = .now
            row.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion
        }
        try? modelContext.save()
    }
#endif
}
