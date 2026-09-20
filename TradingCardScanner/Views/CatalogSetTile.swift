import SwiftUI
import UIKit

enum CatalogSetTileLayout: Equatable {
    case grid
    case rail

    var artworkHeight: CGFloat {
        switch self {
        case .grid: return 104
        case .rail: return 112
        }
    }

    var artworkPadding: CGFloat {
        switch self {
        case .grid: return 10
        case .rail: return 8
        }
    }

    var nameLineLimit: Int {
        switch self {
        case .grid: return 2
        case .rail: return 3
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
    @State private var artworkPhase: CatalogImageLoadPhase = .idle
    @State private var artworkRetryCount = 0
    @State private var retriedArtworkOnCurrentAppearance = false

    private var artworkSource: PokemonArtworkFallbacks.SetSource {
        PokemonArtworkFallbacks.setSource(for: set, kind: .logo)
    }

    private var isMissingArtwork: Bool {
        guard set.game == .pokemon else { return false }
        guard !artworkSource.candidates.isEmpty else {
            return true
        }
        let hasBundledArtwork = artworkSource.candidates.contains { candidate in
            guard case let .bundled(name) = candidate else { return false }
            return UIImage(named: name) != nil
        }
        if hasBundledArtwork { return false }
        let hasRemoteArtwork = artworkSource.candidates.contains { candidate in
            if case .remote = candidate { return true }
            return false
        }
        return hasRemoteArtwork ? artworkPhase == .failed : true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            artworkBox

            if !isMissingArtwork {
                Text(set.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(layout.nameLineLimit)
                    .multilineTextAlignment(.leading)
            }

            if isMissingArtwork, layout == .grid, let cardCount = set.cardCount {
                Text(countLabel(cardCount, singular: "card", plural: "cards"))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !isMissingArtwork {
                Text(metadata)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            completionFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            accessibilityLabel
        )
    }

    private var metadata: String {
        [
            (layout == .rail && set.game == .magic) ? nil : set.code,
            set.cardCount.map { countLabel($0, singular: "card", plural: "cards") }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let unitSingular = completion.unit == "variations" ? "variation" : "card"
        let unitPlural = completion.unit == "variations" ? "variations" : "cards"
        let owned = countLabel(completion.owned, singular: unitSingular, plural: unitPlural)
        let progress = completion.total.map { "\(owned) of \($0) \(unitPlural) collected" }
            ?? "\(owned) collected"
        let art = isMissingArtwork ? ", artwork unavailable" : ""
        return "\(set.name), \(progress), set code \(set.code)\(art)"
    }

    private var artworkBox: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(tileTintName))

            Group {
                artwork
                    .opacity(isMissingArtwork ? 0 : 1)
                    .accessibilityHidden(isMissingArtwork)
                if isMissingArtwork { missingArtwork }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(layout.artworkPadding)

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

            if layout == .rail {
                Text(set.game.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.background.opacity(0.84), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .onAppear {
            guard isMissingArtwork,
                  artworkSource.candidates.contains(where: { candidate in
                      if case .remote = candidate { return true }
                      return false
                  }),
                  !retriedArtworkOnCurrentAppearance else { return }
            retriedArtworkOnCurrentAppearance = true
            artworkRetryCount &+= 1
        }
        .onDisappear {
            retriedArtworkOnCurrentAppearance = false
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
                candidates: artworkSource.candidates,
                targetPixelSize: 416,
                reloadToken: artworkRetryCount,
                placeholderSymbol: "square.stack.3d.up",
                placeholderText: set.code,
                onPhaseChange: { phase in
                    artworkPhase = phase
                }
            )
        }
    }

    private var missingArtwork: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(set.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(set.code)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
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

                Text(completionFooterLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color("BrowseSetProgress"))
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 16)
        }
    }

    private var completionFooterLabel: String {
        if let total = completion.total {
            return "\(completion.owned) of \(total) \(completion.unit)"
        }
        return "\(completion.owned) owned"
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
