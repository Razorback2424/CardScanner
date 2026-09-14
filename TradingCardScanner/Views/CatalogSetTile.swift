import SwiftUI
import UIKit

enum CatalogSetTileLayout {
    case grid
    case rail

    var artworkHeight: CGFloat {
        switch self {
        case .grid: return 104
        case .rail: return 134
        }
    }

    var nameLineLimit: Int {
        switch self {
        case .grid: return 2
        case .rail: return 2
        }
    }
}

/// A reusable set tile for both the two-column directory and the root
/// "Just released" rail. Navigation belongs to the caller so the same tile
/// can be used by more than one route without nesting links.
struct CatalogSetTile: View {
    let set: CatalogSet
    let completion: SetCompletion
    var layout: CatalogSetTileLayout = .grid
    var showsNewBadge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            artworkBox

            Text(set.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(layout.nameLineLimit)
                .multilineTextAlignment(.leading)

            Text(metadata)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            completionFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // Keep this wording in sync with the previous set-list row. The
        // denominator remains available to VoiceOver even though the compact
        // visual tile shows only the owned numerator.
        .accessibilityLabel(
            "\(set.name), \(completion.owned) of \(completion.total.map { String($0) } ?? "unknown") \(completion.unit) collected, set code \(set.code)"
        )
    }

    private var metadata: String {
        [
            set.code,
            set.cardCount.map { "\($0) cards" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var artworkBox: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(tileTintName))

            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)

            if showsNewBadge {
                Text("NEW")
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color("BrowseSetBadgeFill"), in: Capsule())
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if set.game == .magic {
            // Scryfall's set symbols are SVG. ImageIO does not decode SVG on
            // iOS, so the first shippable fallback is deliberately textual and
            // never leaves a Magic tile looking like a failed image request.
            Text(set.code)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            CatalogCachedImage(
                url: set.symbolURL ?? set.logoURL,
                fallbackURL: set.symbolURL == nil ? nil : set.logoURL,
                targetPixelSize: 416,
                placeholderSymbol: "square.stack.3d.up",
                placeholderText: set.code
            )
        }
    }

    @ViewBuilder
    private var completionFooter: some View {
        if completion.owned > 0 {
            HStack(alignment: .center, spacing: 8) {
                if let fraction = completion.fraction {
                    GeometryReader { proxy in
                        let width = proxy.size.width * min(max(fraction, 0), 1)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color(uiColor: .label).opacity(0.12))
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color("BrowseSetProgress"))
                                .frame(width: width)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }

                Text("\(completion.owned)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color("BrowseSetProgress"))
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 16)
        }
    }

    /// A stable palette assignment preserves the varied pastel treatment from
    /// the design while the asset catalog supplies a dark appearance for every
    /// swatch. It is keyed by set identity, not process-randomized `hashValue`.
    private var tileTintName: String {
        let names = [
            "BrowseTileLavender",
            "BrowseTileSand",
            "BrowseTileBlue",
            "BrowseTileRose",
            "BrowseTileStone",
            "BrowseTilePeach"
        ]
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in set.id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return names[Int(hash % UInt64(names.count))]
    }
}
