import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case collection
        case browse
        case scan
        case centering
    }

    @State private var selectedTab: Tab

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
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
    }
}
