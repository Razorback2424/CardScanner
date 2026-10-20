import SwiftUI

struct ProView: View {
    private enum Module: Hashable {
        case centering
        case ebayPhotos

        var title: String {
            switch self {
            case .centering: return "Card Centering"
            case .ebayPhotos: return "eBay Listing Photos"
            }
        }

        var subtitle: String {
            switch self {
            case .centering:
                return "Collector Tools: guided centering and annotated output."
            case .ebayPhotos:
                return "Single-card photos free. Unlimited batches with Collector Tools."
            }
        }

        var systemImage: String {
            switch self {
            case .centering: return "square.dashed.inset.filled"
            case .ebayPhotos: return "photo.stack"
            }
        }
    }

    private static let modules: [Module] = [.centering, .ebayPhotos]
    @State private var path: [Module]
    @State private var isShowingCollectorTools = false

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
        _path = State(
            initialValue: route?.hasPrefix("Centering") == true
                ? [.centering]
                : []
        )
#else
        _path = State(initialValue: [])
#endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(Self.modules, id: \.self) { module in
                NavigationLink(value: module) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(module.title, systemImage: module.systemImage)
                        Text(module.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            .contentWidthLimit(.standard)
            .navigationTitle("Pro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Collector Tools") { isShowingCollectorTools = true }
                }
            }
            .sheet(isPresented: $isShowingCollectorTools) { CollectorToolsOfferView() }
            .navigationDestination(for: Module.self) { module in
                switch module {
                case .centering:
                    CardCenteringView()
                case .ebayPhotos:
                    EbayListingPhotosView()
                }
            }
        }
    }
}
