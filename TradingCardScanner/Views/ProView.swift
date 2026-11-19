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

        /// What this tool costs, shown on the tile so nobody has to open it to
        /// find out. Nil once Collector Tools is owned.
        func accessBadge(isOwned: Bool) -> ProToolBadge? {
            guard !isOwned else { return nil }
            switch self {
            case .centering:
                return ProToolBadge(text: nil, systemImage: "lock.fill", accessibilityLabel: "Requires Collector Tools")
            case .ebayPhotos:
                return ProToolBadge(text: "1 free", systemImage: nil, accessibilityLabel: "One card free")
            }
        }
    }

    private static let modules: [Module] = [.centering, .ebayPhotos]
    @ObservedObject private var collectorTools = CollectorToolsStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            initialValue: route == "ListingPhotos" ? [.ebayPhotos]
                : route?.hasPrefix("Centering") == true ? [.centering] : []
        )
#else
        _path = State(initialValue: [])
#endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    CollectorToolsBanner(store: collectorTools) { isShowingCollectorTools = true }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tools")
                            .font(.title3.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(
                            // Side by side until accessibility sizes, where a half-width
                            // tile would truncate the tool's name.
                            columns: [GridItem(
                                .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 160),
                                spacing: 14,
                                alignment: .top
                            )],
                            spacing: 14
                        ) {
                            ForEach(Self.modules, id: \.self) { module in
                                NavigationLink(value: module) {
                                    ProToolTile(
                                        title: module.title,
                                        badge: collectorTools.ownership == .loading
                                            ? nil : module.accessBadge(isOwned: collectorTools.isOwned)
                                    ) {
                                        switch module {
                                        case .centering: CenteringGuideArt(cardWidth: 70, showsReadout: false)
                                        case .ebayPhotos: ListingPhotosArt(cardWidth: 58)
                                        }
                                    }
                                }
                                .buttonStyle(ProPressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 32)
                .contentWidthLimit(.wide)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pro")
            .sheet(isPresented: $isShowingCollectorTools) { CollectorToolsOfferView() }
            .task {
                if !collectorTools.isOwned, collectorTools.displayPrice == nil {
                    await collectorTools.loadProduct()
                }
            }
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

/// The Collector Tools purchase, stated once at the top of Pro: a foil card
/// while it is an offer, a quiet confirmation once it is owned. Either way the
/// purchase itself happens in the offer sheet, never from this surface.
private struct CollectorToolsBanner: View {
    @ObservedObject var store: CollectorToolsStore
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            if store.isOwned {
                statusRow(title: "Collector Tools", detail: "Unlocked", isLoading: false)
            } else if store.ownership == .loading {
                statusRow(title: "Collector Tools", detail: "Checking purchases…", isLoading: true)
            } else {
                offer
            }
        }
        .buttonStyle(ProPressableStyle())
        .accessibilityHint(store.isOwned ? "Shows purchase details." : "Shows what's included.")
    }

    private var offer: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Collector Tools", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.ink.opacity(0.8))
            Text("Unlimited centering and batch listing photos")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(store.displayPrice.map { "Unlock for \($0)" } ?? "Unlock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AppPalette.ink, in: Capsule())
                .padding(.top, 2)
        }
        .padding(20)
        // At accessibility sizes the text needs the width the watermark keeps.
        .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: AppPalette.foil, startPoint: .topLeading, endPoint: .bottomTrailing)
                if !dynamicTypeSize.isAccessibilitySize {
                    fannedCards
                        .offset(x: 34, y: 18)
                }
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.35), lineWidth: 1) }
        .shadow(color: AppPalette.ink.opacity(0.18), radius: 18, y: 10)
        .contentShape(shape)
    }

    /// The opening mark's fanned hand, turned into a watermark.
    private var fannedCards: some View {
        ZStack {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(index == 2 ? 0.42 : 0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                    }
                    .frame(width: 84, height: 117)
                    .rotationEffect(.degrees(Double(index - 1) * 12 + 8), anchor: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    private func statusRow(title: String, detail: String, isLoading: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: AppPalette.foil, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(AppPalette.ink)
                    .opacity(isLoading ? 0 : 1)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ProToolBadge {
    let text: String?
    let systemImage: String?
    let accessibilityLabel: String
}

/// One tool: an illustration of what it makes, and its name.
private struct ProToolTile<Art: View>: View {
    let title: String
    let badge: ProToolBadge?
    @ViewBuilder let art: () -> Art
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Sits below the badge row, so a badge never covers the art.
                art()
                    .padding(.top, 28)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 164)
            .overlay(alignment: .topTrailing) {
                if let badge {
                    HStack(spacing: 4) {
                        if let systemImage = badge.systemImage { Image(systemName: systemImage) }
                        if let text = badge.text { Text(text) }
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, badge.text == nil ? 7 : 9)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(badge.accessibilityLabel)
                }
            }
            .clipped()

            HStack(spacing: 8) {
                // Two lines reserved, so side-by-side tiles stay the same height.
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2, reservesSpace: !dynamicTypeSize.isAccessibilitySize)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
        .contentShape(shape)
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
    }
}
