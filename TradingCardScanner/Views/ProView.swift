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
                return "Measure borders and export a centering report."
            case .ebayPhotos:
                return "Prepare ten numbered photos for a card listing."
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

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let routeIndex = arguments.firstIndex(of: "-ui_debug_route")
        let route = routeIndex.flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
        _path = State(
            initialValue: route == "Centering" || route == "CenteringExpanded"
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
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .contentWidthLimit(.standard)
            .navigationTitle("Pro")
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
