import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ScannerView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "rectangle.stack")
                }
        }
    }
}
