import SwiftUI
import UIKit

// Sharing a card as an image instead of a screenshot.
//
// Two images, chosen by where Share was tapped rather than by the user:
// - `CollectionShareImage` for a card or product the user owns (a pull or a
//   trade). The only choice is whether to include the price.
// - `BuyCheckShareImage` for a price check ("should I buy this?"): market
//   price, an optional asking price, and the 3-month trend when there is
//   enough history to state one.
//
// Both images follow one portrait composition: artwork, identity, rarity,
// value below a hairline, then quieter printing details and attribution.

enum CardShareStyle {
    /// The image is drawn at this size in points and rendered at 3x, giving a
    /// 1080 x 1920 portrait image, with room for the artwork and its identity.
    static let canvas = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3
    /// How long the price-check bitmap waits for asking-price typing to pause.
    static let askRenderPause: Duration = .milliseconds(200)
    static let cardAspect: CGFloat = 0.716

    static let ground = Color(red: 13 / 255, green: 13 / 255, blue: 20 / 255)
    static let primaryText = Color(red: 244 / 255, green: 242 / 255, blue: 255 / 255)
    static let secondaryText = Color(red: 226 / 255, green: 223 / 255, blue: 239 / 255)
    static let tertiaryText = Color(red: 201 / 255, green: 198 / 255, blue: 217 / 255)
    static let mutedText = Color(red: 156 / 255, green: 153 / 255, blue: 179 / 255)
    static let hairline = Color.white.opacity(0.10)
    static let sheetBackground = Color(red: 23 / 255, green: 23 / 255, blue: 27 / 255)
    static let rowBackground = Color(red: 34 / 255, green: 34 / 255, blue: 39 / 255)
    static var mint: Color { AppPalette.foil[0] }
    static var iris: Color { AppPalette.foil[2] }
    static var rose: Color { AppPalette.foil[3] }
}

// MARK: - Artwork

struct CardShareArtwork {
    enum Kind: Equatable {
        case catalog
        /// The user's own photo of their copy. Used whenever one exists, so a
        /// trade partner sees the actual card rather than stock art.
        case userPhoto
    }

    let image: UIImage
    let kind: Kind
}

enum CardShareArtworkLoader {
    typealias Load = @MainActor (String?, [URL]) async -> CardShareArtwork?
    static let pixelSize = 1_200

    @MainActor
    static func load(localFilename: String?, remoteURLs: [URL]) async -> CardShareArtwork? {
        if let localFilename, !localFilename.isEmpty {
            let dimension = pixelSize
            let image = await Task.detached(priority: .userInitiated) {
                CollectionArtworkStore.image(filename: localFilename, maximumPixelDimension: dimension)
            }.value
            if let image { return CardShareArtwork(image: image, kind: .userPhoto) }
        }
        for url in remoteURLs {
            if let image = try? await CatalogImageCache.shared.image(for: url, targetPixelSize: pixelSize) {
                return CardShareArtwork(image: image, kind: .catalog)
            }
        }
        return nil
    }
}

/// Artwork enriches a share; loading or failing to load it never blocks the
/// identity and price. A newer attempt owns the result if an old request lingers.
@MainActor
final class CardShareArtworkState: ObservableObject {
    @Published private(set) var artwork: CardShareArtwork?
    @Published private(set) var isLoading = false
    @Published private(set) var revision = 0
    private var generation = 0

    func load(localFilename: String?, remoteURLs: [URL],
              using loader: CardShareArtworkLoader.Load = CardShareArtworkLoader.load) async {
        generation += 1
        let attempt = generation
        isLoading = true
        let loaded = await loader(localFilename, remoteURLs)
        guard attempt == generation else { return }
        isLoading = false
        guard !Task.isCancelled else { return }
        artwork = loaded
        revision += 1
    }
}

enum CardShareArtworkLayout {
    static func aspect(for artwork: CardShareArtwork?) -> CGFloat {
        guard let artwork, artwork.image.size.height > 0 else { return CardShareStyle.cardAspect }
        let aspect = artwork.image.size.width / artwork.image.size.height
        // Ordinary photos remain whole. Extreme personal photos get a bounded,
        // centered crop rather than reducing the share's artwork to a sliver.
        return artwork.kind == .userPhoto ? min(max(aspect, 1 / 3), 3) : aspect
    }

    static func cornerRadius(for size: CGSize, kind: CardShareArtwork.Kind?) -> CGFloat {
        let preferred: CGFloat = kind == .userPhoto ? 16 : max(6, size.width * 0.045)
        return min(preferred, min(size.width, size.height) * 0.08)
    }
}

// MARK: - Identity from app models

extension CardShareIdentity {
    init(collectedCard card: CollectedCard) {
        let badge: Badge?
        switch card.itemKind {
        case .gradedCard:
            badge = Self.gradeText(for: card).map(Badge.grade)
        case .rawCard:
            badge = Self.finishBadge(for: card.variant)
        case .sealedProduct:
            badge = nil
        }
        let isSealed = card.itemKind == .sealedProduct
        let labels = isSealed ? nil : Self.onePiecePrintingLabels(for: card)
        self.init(
            name: card.name,
            setCode: isSealed ? nil : card.setCode,
            setName: card.setName,
            number: isSealed ? nil : CardShareNumber(card.displayCardNumber),
            badge: badge,
            rarity: isSealed ? nil : CardShareRarity(raw: labels?.rarity ?? card.rarity, game: card.cardGame,
                pokemonSetID: card.catalogProviderID ?? card.providerID),
            artworkTreatment: labels?.artworkTreatment,
            finish: isSealed ? nil : Self.finishBadge(for: card.variant)?.text,
            edition: !isSealed && card.cardGame == .pokemon ? card.pokemonPrintRun?.label : nil
        )
    }

    private static func onePiecePrintingLabels(for card: CollectedCard)
        -> (rarity: String?, artworkTreatment: String?)? {
        guard card.cardGame == .onePiece,
              let id = card.underlyingPrintingID.flatMap(UUID.init(uuidString:)),
              let container = card.modelContext?.container,
              let adapter = CollectionStore.activeCatalogAdapter(for: card.cardGame, in: container) as? OnePieceCatalogAdapter else {
            return nil
        }
        return adapter.printingLabels(for: id)
    }

    init(priceCheck result: PriceCheckResult) {
        let badge: Badge?
        if let slab = result.resolvedScan.request.subject.slab {
            badge = .grade(slab.grade.display(company: slab.company))
        } else {
            badge = Self.finishBadge(for: result.resolved.variant)
        }
        self.init(
            name: result.card.name,
            setCode: result.card.setCode,
            setName: result.card.setName,
            number: CardShareNumber(result.card.displayCardNumber),
            badge: badge,
            rarity: CardShareRarity(raw: result.card.rarity, game: result.card.game,
                pokemonSetID: result.card.setID),
            artworkTreatment: result.card.artworkTreatment,
            finish: Self.finishBadge(for: result.resolved.variant)?.text,
            edition: result.card.game == .pokemon ? result.resolvedScan.pokemonPrintRun?.label : nil
        )
    }

    /// A catalog printing nobody owns yet, at the finish being looked at.
    init(catalogCard card: IdentifiedCard, setName: String?, finish: String?, edition: String?) {
        self.init(
            name: card.name,
            setCode: card.setCode,
            setName: setName ?? card.setName,
            number: CardShareNumber(card.displayCardNumber),
            badge: nil,
            rarity: CardShareRarity(raw: card.rarity, game: card.game, pokemonSetID: card.setID),
            artworkTreatment: card.artworkTreatment,
            finish: finish,
            edition: edition
        )
    }

    static func gradeText(for card: CollectedCard) -> String? {
        guard let company = card.gradingCompany else { return nil }
        return card.cardGrade?.display(company: company)
            ?? [company.label, card.gradeRaw].compactMap { $0 }.joined(separator: " ")
    }
}

/// One owned copy the collection share can show: its facts without a finish,
/// plus the finish the holder recorded, so the sheet can state or hide it.
/// A raw finish and each graded slab are separate options.
struct CollectionShareOption: Identifiable {
    let id: String
    let identity: CardShareIdentity
    /// What the copy picker calls it: `Foil`, `PSA 10 · Holo`.
    let choiceLabel: String
    /// A slab is shared on its own; it never joins the finish comparison.
    let isGraded: Bool
    /// Nil when nothing trustworthy is known, such as sealed product or a
    /// finish the catalog never specified.
    let finishLabel: String?
    let price: CardSharePrice?
    let showsFinishSheen: Bool
    let localArtworkFilename: String?
    let remoteArtworkURLs: [URL]

    init(id: String, identity: CardShareIdentity, finishLabel: String?, price: CardSharePrice?,
         showsFinishSheen: Bool, localArtworkFilename: String?, remoteArtworkURLs: [URL], isGraded: Bool? = nil) {
        self.id = id
        self.isGraded = isGraded ?? (identity.gradeBadge != nil)
        self.identity = identity.replacingFinish(nil)
        let finish = finishLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? finishLabel : nil
        self.finishLabel = finish
        let parts = [identity.gradeBadge?.text, finish].compactMap { $0 }
        self.choiceLabel = parts.isEmpty ? "Your copy" : parts.joined(separator: " · ")
        self.price = price
        self.showsFinishSheen = showsFinishSheen
        self.localArtworkFilename = localArtworkFilename
        self.remoteArtworkURLs = remoteArtworkURLs
    }

    @MainActor
    init(collectedCard card: CollectedCard, price: PriceDisplay, localArtworkFilename: String?) {
        let source = CatalogCardArtworkSource(collectedCard: card, prefersFullSize: true)
        self.init(
            id: card.collectionKey,
            identity: CardShareIdentity(collectedCard: card),
            finishLabel: Self.finishLabel(for: card),
            price: CardSharePrice(collectedCard: card, display: price),
            showsFinishSheen: CollectionShareSheet.showsFinishSheen(for: card),
            localArtworkFilename: localArtworkFilename,
            remoteArtworkURLs: [source.primaryURL].compactMap { $0 } + source.fallbacks,
            isGraded: card.itemKind == .gradedCard
        )
    }

    /// Owned copies state their finish even when it is the standard one: a
    /// friend wants to know a pull was the nonfoil, not just that it wasn't foil.
    static func finishLabel(for card: CollectedCard) -> String? {
        guard card.itemKind != .sealedProduct,
              let variant = card.variant,
              variant.id != PhysicalVariant.firstEdition.id,
              // Imported and catalog-silent finishes are not established
              // enough to tell someone else.
              card.variantResolution.map({ $0.certainty != .unresolved }) ?? false else { return nil }
        return variant.label
    }
}

extension CardSharePrice {
    init?(collectedCard card: CollectedCard, display: PriceDisplay) {
        self.init(
            display: display,
            basis: Self.basis(
                itemKind: card.itemKind,
                gradeLabel: CardShareIdentity.gradeText(for: card),
                source: display.source
            )
        )
    }

    init?(priceCheck result: PriceCheckResult) {
        let display = result.display
        let slab = result.resolvedScan.request.subject.slab
        self.init(
            display: display,
            basis: Self.basis(
                itemKind: slab == nil ? .rawCard : .gradedCard,
                gradeLabel: slab.map { $0.grade.display(company: $0.company) },
                source: display.source
            )
        )
    }
}

// MARK: - Collection image (pulls and trades)

struct CollectionShareImage: View {
    let identity: CardShareIdentity
    /// Nil when the price is switched off or unavailable.
    let price: CardSharePrice?
    let artwork: CardShareArtwork?
    let showsFinishSheen: Bool
    /// Every owned finish, shared together. Empty for a single copy, whose
    /// finish (if stated) rides in `identity`.
    var finishes: [CardShareFinishLine] = []
    /// The artwork's own colour, as the card detail page uses it.
    var accent: ArtworkAccent? = nil
    var now: Date = .now

    private var footerSource: String? {
        (price ?? finishes.lazy.compactMap(\.price).first)?.sourceLine(now: now)
    }

    private func priceAmount(_ price: CardSharePrice) -> some View {
        Text(price.formattedAmount())
            .font(.system(size: 27, weight: .heavy))
            .tracking(-0.5)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func priceBasis(_ price: CardSharePrice) -> some View {
        Text(price.basis)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CardShareStyle.tertiaryText)
            .lineLimit(1)
    }

    var body: some View {
        VStack(spacing: 0) {
            if artwork != nil {
                ShareArtworkView(artwork: artwork, showsFinishSheen: showsFinishSheen, shadowRadius: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 24)
            } else {
                Spacer(minLength: 24)
            }

            // Artwork gives up room first; the facts never do.
            ShareIdentityBlock(identity: finishes.isEmpty ? identity : identity.replacingFinish(nil), accent: accent)
                .layoutPriority(1)

            if artwork == nil {
                Spacer(minLength: 24)
            }

            if !finishes.isEmpty {
                ShareFinishList(finishes: finishes)
                    .layoutPriority(1)
                    .padding(.top, 14)
                    .overlay(alignment: .top) { ShareHairline() }
                    .padding(.top, 14)
            } else if let price {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        priceAmount(price)
                        Spacer(minLength: 0)
                        priceBasis(price)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        priceAmount(price)
                        priceBasis(price)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .layoutPriority(1)
                .padding(.top, 14)
                .overlay(alignment: .top) { ShareHairline() }
                .padding(.top, 14)
            }

            ShareFooter(printing: identity.edition, source: footerSource)
                .padding(.top, 22)
        }
        .padding(EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
        .frame(width: CardShareStyle.canvas.width, height: CardShareStyle.canvas.height)
        .background { ShareGround(glow: true, accent: accent) }
        .foregroundStyle(CardShareStyle.primaryText)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Buy check image (should I buy this?)

struct BuyCheckShareImage: View {
    let identity: CardShareIdentity
    let price: CardSharePrice
    let ask: CardShareAsk?
    let trend: CardShareTrend?
    let artwork: CardShareArtwork?
    var now: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            if trend != nil {
                historyIdentityRow
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if artwork != nil {
                    ShareArtworkView(artwork: artwork, showsFinishSheen: false, shadowRadius: 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 24)
                } else {
                    Spacer(minLength: 24)
                }
                ShareIdentityBlock(identity: identity, accent: nil)
                if artwork == nil { Spacer(minLength: 24) }
            }
            stats.padding(.top, 18).layoutPriority(1)
            if let trend {
                trendBlock(trend).padding(.top, 18)
            }

            ShareFooter(printing: identity.edition, source: footerSource)
                .padding(.top, 22)
        }
        .padding(EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
        .frame(width: CardShareStyle.canvas.width, height: CardShareStyle.canvas.height)
        .background { ShareGround(glow: false) }
        .foregroundStyle(CardShareStyle.primaryText)
        .environment(\.colorScheme, .dark)
    }

    /// History needs room of its own. Keep the artwork beside the identity
    /// here, instead of compressing it to a tiny sliver above the chart.
    @ViewBuilder
    private var historyIdentityRow: some View {
        if let artwork {
            HStack(spacing: 16) {
                ShareArtworkView(artwork: artwork, showsFinishSheen: false, shadowRadius: 12)
                    .frame(width: 110, height: 110 / CardShareStyle.cardAspect)
                VStack(alignment: .leading, spacing: 8) {
                    Text(identity.name)
                        .font(.system(size: 20, weight: .bold))
                        .fontWidth(.expanded)
                        .tracking(-0.4)
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                    // Same order and voice as the card page: set, then code
                    // and number.
                    if let name = identity.displaySetName {
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .fontWidth(.expanded)
                            .foregroundStyle(ShareIdentityBlock.fallbackSetTint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let designation = ShareIdentityBlock.designation(for: identity) {
                        designation
                            .font(.system(size: 14, weight: .bold))
                            .fontWidth(.expanded)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if let label = identity.shareRarityLabel {
                        ShareRarityLabel(label: label, rarity: identity.rarity)
                    }
                    if let grade = identity.gradeBadge {
                        ShareBadge(badge: grade, size: 12)
                    }
                    if let finish = identity.finish {
                        ShareBadge(badge: .finish(finish), size: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ShareIdentityBlock(identity: identity, accent: nil)
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 14) {
            stat(label: "Market", value: price.formattedAmount(), detail: nil, tint: nil)
            if let ask {
                stat(
                    label: "Asking",
                    value: askAmountText(ask),
                    detail: ask.comparisonText,
                    tint: askTint(ask)
                )
            }
        }
        .padding(.top, 17)
        .overlay(alignment: .top) { ShareHairline() }
    }

    private func stat(label: String, value: String, detail: String?, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(CardShareStyle.mutedText)
            Text(value)
                .font(.system(size: 36, weight: .heavy))
                .tracking(-1)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint ?? CardShareStyle.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendBlock(_ trend: CardShareTrend) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: trendSymbol(trend))
                        .font(.system(size: 11, weight: .heavy))
                    Text(trend.headline(now: now))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(trendTint(trend))
                .lineLimit(1)
                Spacer(minLength: 6)
                if let position = trend.positionText(now: now) {
                    Text(position)
                        .font(.system(size: 14))
                        .foregroundStyle(CardShareStyle.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            ShareTrendChart(
                trend: trend,
                ask: ask?.amount,
                askLabel: ask.map { "Asking \(askAmountText($0))" },
                tint: trendTint(trend)
            )
            .frame(height: 84)
            HStack {
                Text(CardShareFormat.shortDate(trend.start, now: now))
                Spacer()
                Text(CardShareFormat.shortDate(trend.end, now: now))
            }
            .font(.system(size: 12))
            .foregroundStyle(CardShareStyle.mutedText)
        }
    }

    /// `Near Mint · TCGplayer · Oct 31`. The stat above already says Market,
    /// so the footer keeps only the condition the price describes.
    private var footerSource: String? {
        let basis = price.basis.replacingOccurrences(of: " market", with: "")
        return [basis, price.sourceLine(now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    private func askAmountText(_ ask: CardShareAsk) -> String {
        CardSharePrice(amount: ask.amount, currencyCode: price.currencyCode, basis: "", source: nil, asOf: nil)
            .formattedAmount()
    }

    private func askTint(_ ask: CardShareAsk) -> Color {
        switch ask.comparison {
        case .under: return CardShareStyle.mint
        case .over: return CardShareStyle.rose
        case .atMarket: return CardShareStyle.tertiaryText
        }
    }

    private func trendTint(_ trend: CardShareTrend) -> Color {
        switch trend.direction {
        case .up: return CardShareStyle.mint
        case .down: return CardShareStyle.rose
        case .flat: return CardShareStyle.tertiaryText
        }
    }

    private func trendSymbol(_ trend: CardShareTrend) -> String {
        switch trend.direction {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .flat: return "minus"
        }
    }
}

// MARK: - Image parts

private struct ShareGround: View {
    let glow: Bool
    var accent: ArtworkAccent? = nil

    var body: some View {
        ZStack {
            CardShareStyle.ground
            if glow, let accent, !accent.isNeutral {
                // The card detail page's wash, so the image looks like the
                // page it was shared from.
                LinearGradient(
                    stops: [
                        .init(color: accent.deep.opacity(0.75), location: 0),
                        .init(color: accent.deep.opacity(0.35), location: 0.45),
                        .init(color: CardShareStyle.ground, location: 0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if glow {
                RadialGradient(
                    colors: [CardShareStyle.iris.opacity(0.18), CardShareStyle.iris.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: 300
                )
            }
        }
    }
}

private struct ShareHairline: View {
    var body: some View {
        Rectangle()
            .fill(CardShareStyle.hairline)
            .frame(height: 1)
    }
}

private struct ShareArtworkView: View {
    let artwork: CardShareArtwork?
    let showsFinishSheen: Bool
    let shadowRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = fittedSize(in: proxy.size)
            framed(size: size)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var aspect: CGFloat {
        CardShareArtworkLayout.aspect(for: artwork)
    }

    private func fittedSize(in bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        var width = bounds.width
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    private func framed(size: CGSize) -> some View {
        let radius = CardShareArtworkLayout.cornerRadius(for: size, kind: artwork?.kind)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if let artwork {
                Image(uiImage: artwork.image)
                    .resizable()
                    .scaledToFill()
            } else {
                shape.fill(Color.white.opacity(0.06))
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(CardShareStyle.mutedText)
            }
            if showsFinishSheen, artwork?.kind == .catalog {
                ShareFinishSheen()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.55), radius: shadowRadius, y: shadowRadius * 0.65)
    }
}

/// A still capture of the foil sheen, at a flattering angle. A shared image
/// cannot follow the recipient's tilt, so it carries one considered pose.
private struct ShareFinishSheen: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: AppPalette.foil.map { $0.opacity(0.22) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0.30),
                    .init(color: .white.opacity(0.38), location: 0.44),
                    .init(color: .white.opacity(0), location: 0.56)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.overlay)
        }
        .allowsHitTesting(false)
    }
}

/// The card detail page's identity header, at share scale: expanded bold
/// name, the set name in the artwork's colour beside its code and number,
/// then rarity, grade and finish.
private struct ShareIdentityBlock: View {
    let identity: CardShareIdentity
    let accent: ArtworkAccent?

    /// `CardDetailIdentityHeader`'s dark-mode set link, before artwork colour.
    static let fallbackSetTint = Color(red: 0.30, green: 0.75, blue: 0.79)

    private var setTint: Color {
        if let accent, !accent.isNeutral { return accent.ink }
        return Self.fallbackSetTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(identity.name)
                .font(.system(size: 27, weight: .bold))
                .fontWidth(.expanded)
                .tracking(-0.6)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                // Never squeezed to a line by the artwork; three at most.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            if identity.displaySetName != nil || designation != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        setName
                        if identity.displaySetName != nil, designation != nil {
                            Circle()
                                .fill(CardShareStyle.mutedText)
                                .frame(width: 4, height: 4)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 5 }
                        }
                        designation
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: 3) {
                        setName
                        designation
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .fontWidth(.expanded)
            }
            if identity.shareRarityLabel != nil || identity.gradeBadge != nil || identity.finish != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        rarityLabel
                        badges
                    }
                    .fixedSize()
                    // Rarity names run long; the grade and finish stay paired
                    // while they fit, and stack when a finish name is long.
                    VStack(alignment: .leading, spacing: 8) {
                        rarityLabel
                        HStack(spacing: 8) { badges }.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        rarityLabel
                        badges
                    }
                }
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var setName: some View {
        if let name = identity.displaySetName {
            Text(name)
                .foregroundStyle(setTint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var designation: Text? { Self.designation(for: identity) }

    /// `FIN 159`, or `TST 087/165` with the set total quieter.
    static func designation(for identity: CardShareIdentity) -> Text? {
        let code = identity.designationSetCode.map { Text($0.uppercased()) }
        let number = identity.number.map { number in
            Text(number.primary) + Text(number.total ?? "").foregroundStyle(CardShareStyle.mutedText)
        }
        switch (code, number) {
        case let (code?, number?): return code + Text(" ") + number
        case let (code?, nil): return code
        case let (nil, number?): return number
        case (nil, nil): return nil
        }
    }

    @ViewBuilder
    private var rarityLabel: some View {
        if let label = identity.shareRarityLabel {
            ShareRarityLabel(label: label, rarity: identity.rarity)
        }
    }

    @ViewBuilder
    private var badges: some View {
        if let grade = identity.gradeBadge {
            ShareBadge(badge: grade, size: 12)
        }
        if let finish = identity.finish {
            ShareBadge(badge: .finish(finish), size: 12)
        }
    }
}

/// Every owned finish of one card: what was pulled, and, with prices on, how
/// the finishes compare.
private struct ShareFinishList: View {
    static let visibleLimit = 5
    let finishes: [CardShareFinishLine]

    private var visible: ArraySlice<CardShareFinishLine> { finishes.prefix(Self.visibleLimit) }
    private var hiddenCount: Int { max(0, finishes.count - Self.visibleLimit) }
    private var basis: String? { finishes.lazy.compactMap(\.price).first?.basis }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("FINISHES OWNED")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CardShareStyle.mutedText)
                Spacer(minLength: 8)
                if let basis {
                    Text(basis)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CardShareStyle.tertiaryText)
                        .lineLimit(1)
                }
            }
            if basis == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { badges }.fixedSize()
                    VStack(alignment: .leading, spacing: 6) { badges }
                }
            } else {
                ForEach(visible) { finish in
                    HStack(alignment: .center, spacing: 12) {
                        ShareBadge(badge: .finish(finish.label), size: 12)
                        Spacer(minLength: 0)
                        // The amount is the point of the comparison: it keeps
                        // its full width and a long finish name shortens.
                        Text(finish.price?.formattedAmount() ?? "—")
                            .font(.system(size: 19, weight: .heavy))
                            .tracking(-0.3)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(finish.price == nil ? CardShareStyle.mutedText : CardShareStyle.primaryText)
                    }
                }
            }
            if hiddenCount > 0 {
                Text("+\(hiddenCount) more")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CardShareStyle.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var badges: some View {
        ForEach(visible) { finish in
            ShareBadge(badge: .finish(finish.label), size: 12)
        }
    }
}

/// Familiar rarity marks, adapted for a dark ground. The complete name stays
/// readable independently of color; a star count is never used as a rating.
private struct ShareRarityLabel: View {
    let label: String
    let rarity: CardShareRarity?

    private var tint: Color {
        switch rarity?.tone ?? .neutral {
        case .neutral: return CardShareStyle.secondaryText
        case .silver: return Color(red: 216 / 255, green: 228 / 255, blue: 246 / 255)
        case .gold: return Color(red: 244 / 255, green: 213 / 255, blue: 140 / 255)
        case .iris: return Color(red: 198 / 255, green: 191 / 255, blue: 255 / 255)
        case .rose: return CardShareStyle.rose
        case .ember: return Color(red: 255 / 255, green: 181 / 255, blue: 133 / 255)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            mark
                .fixedSize()
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .fontWidth(.expanded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var mark: some View {
        switch rarity?.mark ?? .none {
        case .circle:
            Circle().frame(width: 8, height: 8)
        case .diamond:
            Image(systemName: "diamond.fill").font(.system(size: 11))
        case let .stars(count):
            stars(count: count, symbol: "star.fill")
        case let .shinyStars(count):
            stars(count: count, symbol: "sparkle")
        case .megaStar:
            Image(systemName: "star.fill")
                .font(.system(size: 17))
                .overlay {
                    Image(systemName: "star")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CardShareStyle.ground)
                }
        case .attackStars:
            HStack(spacing: 2) {
                Image(systemName: "star.fill").foregroundStyle(CardShareStyle.rose)
                Image(systemName: "star.fill").foregroundStyle(CardShareStyle.mint)
            }
            .font(.system(size: 13))
        case let .code(code):
            Text(code).font(.system(size: 14, weight: .heavy))
        case .none:
            EmptyView()
        }
    }

    private func stars(count: Int, symbol: String) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                Image(systemName: symbol)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.85), tint],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

private struct ShareBadge: View {
    let badge: CardShareIdentity.Badge
    let size: CGFloat

    var body: some View {
        // Ideal width is the whole label; when the canvas is narrower it
        // shortens rather than running off the image.
        let label = Text(badge.text)
            .font(.system(size: size, weight: .bold))
            .fontWidth(.expanded)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .frame(height: size + 11)
        switch badge {
        case .grade:
            label
                .foregroundStyle(CardShareStyle.ground)
                .background(CardShareStyle.primaryText, in: Capsule())
        case .finish:
            label
                .foregroundStyle(CardShareStyle.mint)
                .overlay { Capsule().strokeBorder(CardShareStyle.mint.opacity(0.55), lineWidth: 1) }
        }
    }
}

private struct ShareBrandMark: View {
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(colors: AppPalette.foil, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 8, height: 12)
            Text("ScanStash")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.1)
                .foregroundStyle(CardShareStyle.primaryText.opacity(0.65))
        }
        .fixedSize()
    }
}

/// Physical printing and market attribution stay below rarity and value.
private struct ShareFooter: View {
    let printing: String?
    let source: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let printing {
                    Text(printing).fontWeight(.medium)
                }
                if let source {
                    Text(source)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(CardShareStyle.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            ShareBrandMark()
        }
    }
}

private struct ShareTrendChart: View {
    let trend: CardShareTrend
    let ask: Double?
    let askLabel: String?
    let tint: Color

    private static let inset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = plotted(in: size)
            ZStack(alignment: .topLeading) {
                areaPath(points, height: size.height)
                    .fill(LinearGradient(colors: [tint.opacity(0.24), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                linePath(points)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let ask, let askLabel {
                    let y = yPosition(for: ask, height: size.height)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(CardShareStyle.secondaryText.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    Text(askLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CardShareStyle.secondaryText)
                        .frame(width: size.width, alignment: .trailing)
                        .offset(y: y > size.height / 2 ? y - 19 : y + 5)
                }
                if let last = points.last {
                    Circle()
                        .fill(tint)
                        .overlay { Circle().stroke(CardShareStyle.ground, lineWidth: 2) }
                        .frame(width: 11, height: 11)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The asking price is part of the domain, so its line is always drawn
    /// where it truly sits against the history.
    private var domain: (low: Double, high: Double) {
        let low = min(trend.low, ask ?? trend.low)
        let high = max(trend.high, ask ?? trend.high)
        let pad = max((high - low) * 0.08, high * 0.01)
        return (low - pad, high + pad)
    }

    private func yPosition(for value: Double, height: CGFloat) -> CGFloat {
        let (low, high) = domain
        guard high > low else { return height / 2 }
        let fraction = (high - value) / (high - low)
        return Self.inset + CGFloat(fraction) * (height - Self.inset * 2)
    }

    private func plotted(in size: CGSize) -> [CGPoint] {
        let start = trend.start.timeIntervalSince1970
        let span = max(trend.end.timeIntervalSince1970 - start, 1)
        return trend.samples.map { sample in
            let fraction = (sample.date.timeIntervalSince1970 - start) / span
            return CGPoint(
                x: Self.inset + CGFloat(fraction) * (size.width - Self.inset * 2),
                y: yPosition(for: sample.amount, height: size.height)
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func areaPath(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.closeSubpath()
        }
    }
}

// MARK: - Sheets

/// Shared from a card or product in the collection.
///
/// Several options mean the holder owns several finishes of one card; they can
/// share one copy, or every finish at once to compare them.
struct CollectionShareSheet: View {
    /// What a trade price check needs: offered beside a plain card share for
    /// a card the user does not own.
    struct PriceCheck {
        let identity: CardShareIdentity
        let price: CardSharePrice
        let artworkURLs: [URL]
        let historyRequest: CardMarketHistoryRequest?
    }

    let options: [CollectionShareOption]
    var priceCheck: PriceCheck?
    var artworkLoader: CardShareArtworkLoader.Load = CardShareArtworkLoader.load

    @Environment(\.dismiss) private var dismiss
    /// Remembers the last choice: someone who shares prices usually keeps
    /// sharing them, and someone who does not should never be surprised.
    @AppStorage("cardShare.includesPrice") private var includesPrice = false
    /// On by default: telling a friend it was the foil is usually the point.
    @AppStorage("cardShare.includesFinish") private var includesFinish = true
    @State private var selectedID: String
    @State private var sharesAllFinishes = false
    @StateObject private var artwork = CardShareArtworkState()
    @State private var artworkAttempt = 0
    /// The source `artwork` was loaded from, so a newly chosen copy never goes
    /// out wearing the previous copy's photo.
    @State private var loadedArtworkSource: ArtworkSource?
    @State private var accent: ArtworkAccent?
    @State private var rendered: UIImage?
    @State private var showsPriceCheck = false

    init(options: [CollectionShareOption], initialOptionID: String? = nil, priceCheck: PriceCheck? = nil,
         artworkLoader: @escaping CardShareArtworkLoader.Load = CardShareArtworkLoader.load) {
        self.options = options
        self.priceCheck = priceCheck
        self.artworkLoader = artworkLoader
        let initial = options.first { $0.id == initialOptionID } ?? options.first
        _selectedID = State(initialValue: initial?.id ?? "")
    }

    init(identity: CardShareIdentity, price: CardSharePrice?, showsFinishSheen: Bool,
         localArtworkFilename: String?, remoteArtworkURLs: [URL],
         artworkLoader: @escaping CardShareArtworkLoader.Load = CardShareArtworkLoader.load) {
        self.init(options: [CollectionShareOption(id: "share", identity: identity, finishLabel: identity.finish,
            price: price, showsFinishSheen: showsFinishSheen, localArtworkFilename: localArtworkFilename,
            remoteArtworkURLs: remoteArtworkURLs)], artworkLoader: artworkLoader)
    }

    private struct ArtworkSource: Hashable {
        let localFilename: String?
        let remoteURLs: [URL]
    }

    private struct ArtworkRequest: Hashable {
        let source: ArtworkSource
        let attempt: Int
    }

    private struct RenderKey: Equatable {
        let includesPrice: Bool
        let includesFinish: Bool
        let selectedID: String
        let showsAllFinishes: Bool
        let artworkRevision: Int
        let artworkIsCurrent: Bool
        let accent: ArtworkAccent?
    }

    private var current: CollectionShareOption? {
        options.first { $0.id == selectedID } ?? options.first
    }

    /// One raw copy per finish, in the order the card page lists them: what
    /// "All finishes" compares. Slabs are shared one at a time.
    private var finishOptions: [CollectionShareOption] {
        var seen: Set<String> = []
        return options.filter { option in
            guard !option.isGraded, let label = option.finishLabel else { return false }
            return seen.insert(label.lowercased()).inserted
        }
    }

    /// Picker labels, numbered only where two copies would otherwise read the
    /// same (two PSA 10 Holo slabs).
    private var choiceLabels: [String: String] {
        let totals = Dictionary(grouping: options, by: \.choiceLabel).mapValues(\.count)
        var seen: [String: Int] = [:]
        var labels: [String: String] = [:]
        for option in options {
            let label = option.choiceLabel
            guard totals[label, default: 0] > 1 else { labels[option.id] = label; continue }
            seen[label, default: 0] += 1
            labels[option.id] = "\(label) (\(seen[label]!))"
        }
        return labels
    }

    private var showsAllFinishes: Bool {
        sharesAllFinishes && includesFinish && finishOptions.count > 1
    }

    private var currentSource: ArtworkSource? {
        current.map { ArtworkSource(localFilename: $0.localArtworkFilename, remoteURLs: $0.remoteArtworkURLs) }
    }

    private var displayedArtwork: CardShareArtwork? {
        loadedArtworkSource == currentSource ? artwork.artwork : nil
    }

    private var identity: CardShareIdentity? {
        guard let current else { return nil }
        return includesFinish && !showsAllFinishes ? current.identity.replacingFinish(current.finishLabel) : current.identity
    }

    private var sharedPrice: CardSharePrice? {
        includesPrice && !showsAllFinishes ? current?.price : nil
    }

    private var finishLines: [CardShareFinishLine] {
        guard showsAllFinishes else { return [] }
        return finishOptions.map {
            CardShareFinishLine(id: $0.id, label: $0.finishLabel ?? "", price: includesPrice ? $0.price : nil)
        }
    }

    private var availablePrice: CardSharePrice? {
        showsAllFinishes ? finishOptions.lazy.compactMap(\.price).first : current?.price
    }

    private var image: CollectionShareImage? {
        guard let identity, let current else { return nil }
        return CollectionShareImage(identity: identity, price: sharedPrice, artwork: displayedArtwork,
            showsFinishSheen: includesFinish && !showsAllFinishes && current.showsFinishSheen,
            finishes: finishLines, accent: accent)
    }

    private var summary: String {
        guard let identity else { return "" }
        return CardShareSummary.text(identity: identity, price: sharedPrice, finishes: finishLines)
    }

    private var renderKey: RenderKey {
        RenderKey(includesPrice: includesPrice, includesFinish: includesFinish, selectedID: selectedID,
            showsAllFinishes: showsAllFinishes, artworkRevision: artwork.revision,
            artworkIsCurrent: loadedArtworkSource == currentSource, accent: accent)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    CardSharePreview(content: image, summary: summary)
                }
                optionsCard
                if displayedArtwork == nil, let current {
                    CardShareArtworkStatus(isLoading: artwork.isLoading,
                        canRetry: artwork.revision > 0
                            && (current.localArtworkFilename?.isEmpty == false || !current.remoteArtworkURLs.isEmpty)) {
                        artworkAttempt += 1
                    }
                }
                CardShareButton(rendered: rendered, title: identity?.name ?? "", message: summary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CardShareCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(CardShareStyle.sheetBackground)
        .preferredColorScheme(.dark)
        .task(id: currentSource.map { ArtworkRequest(source: $0, attempt: artworkAttempt) }) {
            guard let source = currentSource else { return }
            await artwork.load(localFilename: source.localFilename, remoteURLs: source.remoteURLs, using: artworkLoader)
            guard !Task.isCancelled else { return }
            loadedArtworkSource = source
        }
        .task(id: currentSource) {
            guard let source = currentSource else { return }
            let sampled = await ArtworkAccentStore.accent(localFilename: source.localFilename,
                remoteURL: source.remoteURLs.first, fallbackRemoteURL: source.remoteURLs.dropFirst().first)
            guard !Task.isCancelled else { return }
            accent = sampled
        }
        .task(id: renderKey) {
            rendered = image.flatMap { CardShareRenderer.render($0) }
        }
        .sheet(isPresented: $showsPriceCheck) {
            if let priceCheck {
                BuyCheckShareSheet(identity: priceCheck.identity, price: priceCheck.price,
                                   artworkURLs: priceCheck.artworkURLs, historyRequest: priceCheck.historyRequest,
                                   title: "Trade price check", artworkLoader: artworkLoader)
            }
        }
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            if options.count > 1 {
                copyPicker
                Divider().padding(.leading, 16)
            }
            if options.contains(where: { $0.finishLabel != nil }) {
                finishSection
                Divider().padding(.leading, 16)
            }
            priceRow
            if priceCheck != nil {
                Divider().padding(.leading, 16)
                priceCheckRow
            }
        }
        // The preview scales down to make room; the controls keep their text.
        .fixedSize(horizontal: false, vertical: true)
        .background(CardShareStyle.rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Which owned copy goes out: each raw finish, each slab, or every finish
    /// together for comparison.
    private var copyPicker: some View {
        let labels = choiceLabels
        return ScrollViewReader { proxy in ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    CardShareChoiceChip(title: labels[option.id] ?? option.choiceLabel,
                                        systemImage: option.isGraded ? "checkmark.seal.fill" : nil,
                                        isSelected: !showsAllFinishes && option.id == current?.id) {
                        selectedID = option.id
                        sharesAllFinishes = false
                    }
                    .id(option.id)
                }
                if includesFinish && finishOptions.count > 1 {
                    CardShareChoiceChip(title: "All finishes", systemImage: "square.stack",
                                        isSelected: showsAllFinishes) {
                        sharesAllFinishes = true
                    }
                    .id("all-finishes")
                }
            }
        }
        // The copy the sheet opened on may sit past the edge.
        .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
        }
        // Scroll edge to edge within the card, aligned with the text.
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.vertical, 6)
        // Several choices stay visible at once even at the largest sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Copy to share")
    }

    private var finishSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includesFinish) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish")
                        .font(.body.weight(.semibold))
                    Text(finishRowDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(CardShareStyle.mint)
            .disabled(current?.finishLabel == nil && !showsAllFinishes)

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    private var finishRowDetail: String {
        guard includesFinish else { return "Card details, without the finish" }
        if showsAllFinishes { return "All \(finishOptions.count) finishes you own" }
        return current?.finishLabel ?? "Not recorded for this copy"
    }

    private var priceRow: some View {
        Toggle(isOn: $includesPrice) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Price")
                    .font(.body.weight(.semibold))
                Text(priceRowDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(CardShareStyle.mint)
        .disabled(availablePrice == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    /// A secondary path for trades: asking price against market, with trend.
    private var priceCheckRow: some View {
        Button { showsPriceCheck = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Price check for a trade")
                        .font(.body.weight(.semibold))
                    Text("Compare an asking price to market")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var priceRowDetail: String {
        guard let price = availablePrice else { return "No market price available yet" }
        guard includesPrice else { return "Card details, without the price" }
        let basis = showsAllFinishes ? "\(price.basis) per finish" : price.basis
        if let source = price.source { return "\(basis) from \(source)" }
        return basis
    }
}

/// A one-tap choice among a few short options.
private struct CardShareChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.footnote.weight(.semibold))
                }
                Text(title)
            }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(isSelected ? AppPalette.ink : Color.primary)
                .background(isSelected ? AnyShapeStyle(CardShareStyle.mint) : AnyShapeStyle(Color.white.opacity(0.10)),
                            in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Shared from a price check: is this a good price, and is now a good time?
struct BuyCheckShareSheet: View {
    let identity: CardShareIdentity
    let price: CardSharePrice
    let artworkURLs: [URL]
    /// Nil where market history is not available for this item, such as a
    /// graded price check. The image then goes out without a chart.
    let historyRequest: CardMarketHistoryRequest?
    /// A scan result is a price check; a card page shares a card.
    var title = "Share price check"
    var artworkLoader: CardShareArtworkLoader.Load = CardShareArtworkLoader.load
#if DEBUG
    var reviewTrend: CardShareTrend? = nil
#endif

    @Environment(\.cardGameRuntimes) private var runtimes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var askText = ""
    @State private var trend: CardShareTrend?
    @StateObject private var artwork = CardShareArtworkState()
    @State private var artworkAttempt = 0
    @State private var rendered: UIImage?
    /// The inputs `rendered` was drawn from.
    @State private var renderedKey: RenderKey?
    @State private var now = Date.now
    @FocusState private var isAskFocused: Bool

    private struct RenderKey: Equatable {
        let ask: CardShareAsk?
        let trend: CardShareTrend?
        let artworkRevision: Int
    }

    private var renderKey: RenderKey {
        RenderKey(ask: ask, trend: trend, artworkRevision: artwork.revision)
    }

    private var ask: CardShareAsk? {
        CardShareAsk(text: askText, market: price.amount, currencyCode: price.currencyCode)
    }

    private var image: BuyCheckShareImage {
        BuyCheckShareImage(identity: identity, price: price, ask: ask, trend: trend, artwork: artwork.artwork, now: now)
    }

    private var summary: String {
        CardShareSummary.text(identity: identity, price: price, trend: trend, ask: ask, now: now)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CardSharePreview(content: image, summary: summary)
                    .onTapGesture { isAskFocused = false }
                askRow
                if artwork.artwork == nil {
                    CardShareArtworkStatus(isLoading: artwork.isLoading,
                        canRetry: artwork.revision > 0 && !artworkURLs.isEmpty) {
                        artworkAttempt += 1
                    }
                }
                CardShareButton(rendered: rendered, title: identity.name, message: summary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CardShareCloseButton { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isAskFocused = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(CardShareStyle.sheetBackground)
        .preferredColorScheme(.dark)
        .task(id: artworkAttempt) {
            await artwork.load(localFilename: nil, remoteURLs: artworkURLs, using: artworkLoader)
        }
        .task {
#if DEBUG
            if let reviewTrend {
                trend = reviewTrend
                return
            }
#endif
            await loadHistory()
        }
        .task(id: renderKey) {
            let key = renderKey
            if let renderedKey, renderedKey.ask != key.ask {
                // Typing an asking price: the preview above already follows
                // every keystroke; only the share bitmap waits for a pause.
                // Drop the old bitmap first so Share can never send a
                // superseded price.
                rendered = nil
                try? await Task.sleep(for: CardShareStyle.askRenderPause)
                guard !Task.isCancelled else { return }
            }
            rendered = CardShareRenderer.render(image)
            renderedKey = key
        }
    }

    private var askRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Asking price")
                    .font(.body.weight(.semibold))
                Text(ask?.comparisonText ?? "Optional. Compares it to market.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            HStack(spacing: 3) {
                Text(CardShareFormat.currencySymbol(for: price.currencyCode))
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("0.00", text: $askText)
                    .keyboardType(.decimalPad)
                    .font(.body.weight(.bold))
                    .monospacedDigit()
                    .focused($isAskFocused)
                    .accessibilityLabel("Asking price")
            }
            .padding(.horizontal, 12)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 116)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { isAskFocused = true }
        }
        .padding(.leading, 16)
        .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 16 : 8)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .fixedSize(horizontal: false, vertical: true)
        .background(CardShareStyle.rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Cached history first so the chart appears at once; a fresh fetch then
    /// replaces it. If neither arrives, the image simply has no chart.
    @MainActor
    private func loadHistory() async {
        guard let historyRequest else { return }
        let cached = await CardMarketHistoryService.shared.cached(historyRequest, runtimes: runtimes)
        guard !Task.isCancelled else { return }
        if let cachedTrend = CardShareTrend.make(points: cached, now: now) {
            trend = cachedTrend
        }
        do {
            let points = try await CardMarketHistoryService.shared.history(for: historyRequest, runtimes: runtimes)
            guard !Task.isCancelled else { return }
            trend = CardShareTrend.make(points: points, now: now)
        } catch {
            // Keep whatever the cache could say; a failed refresh is not a
            // reason to hold the share.
        }
    }
}

// MARK: - Sheet parts

enum CardShareRenderer {
    @MainActor
    static func render<Content: View>(_ content: Content) -> UIImage? {
        let state = PerformanceSignpost.beginInterval("CardShare.render", id: PerformanceSignpost.makeID(), "\(Content.self)")
        defer { PerformanceSignpost.endInterval("CardShare.render", state, "") }
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark))
        renderer.scale = CardShareStyle.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

extension CardShareFormat {
    static func currencySymbol(for currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }
}

/// Shows exactly what will be sent, scaled to the room the sheet has.
private struct CardSharePreview<Content: View>: View {
    let content: Content
    let summary: String

    var body: some View {
        GeometryReader { proxy in
            let canvas = CardShareStyle.canvas
            let scale = max(0.1, min(proxy.size.width / canvas.width, proxy.size.height / canvas.height, 1))
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            content
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1) }
                .scaleEffect(scale)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image to share")
        .accessibilityValue(summary)
    }
}

private struct CardShareButton: View {
    let rendered: UIImage?
    let title: String
    let message: String

    var body: some View {
        if let rendered {
            let image = Image(uiImage: rendered)
            ShareLink(item: image, message: Text(message), preview: SharePreview(title, image: image)) {
                label(text: "Share")
            }
            .buttonStyle(.plain)
        } else {
            Button {} label: {
                label(text: "Preparing…")
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.6)
        }
    }

    private func label(text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Label(text, systemImage: "square.and.arrow.up")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(AppPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(LinearGradient(colors: AppPalette.foil, startPoint: .leading, endPoint: .trailing), in: shape)
            .contentShape(shape)
    }
}

private struct CardShareArtworkStatus: View {
    let isLoading: Bool
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Sharing without artwork")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isLoading {
                ProgressView().accessibilityLabel("Loading artwork")
            } else if canRetry {
                Button("Retry", action: retry)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Retry artwork")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(minHeight: 24)
    }
}

private struct CardShareCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.12), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

#if DEBUG
/// Deterministic visual QA of the actual sheets, without scanning or saved data.
private struct CardShareReviewState {
    static var value: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(index + 1) else { return "holo" }
        return arguments[index + 1]
    }
}

private extension CardShareIdentity {
    func withGrade(_ grade: String) -> CardShareIdentity {
        CardShareIdentity(name: name, setCode: setCode, setName: setName, number: number,
                          badge: .grade(grade), rarity: rarity, artworkTreatment: artworkTreatment,
                          finish: finish, edition: edition)
    }
}

struct CardShareReviewView: View {
    @State private var isPresented = true
    @State private var loadAttempts = 0
    private let state = CardShareReviewState.value
    private let artworkURL = URL(string: "https://card-share-review.invalid/artwork")!

    private var identity: CardShareIdentity {
        if state == "buy-one-piece" {
            return CardShareIdentity(
                name: "Nami", setCode: "EB05", setName: "Extra Booster: One Piece Heroines Edition Vol. 2 · EB05",
                number: CardShareNumber("EB05-061"), badge: .finish("Foil"),
                rarity: CardShareRarity(raw: "Secret Rare", game: .onePiece), artworkTreatment: "Alt Art"
            )
        }
        return CardShareIdentity(
            name: state.contains("long") ? "A Very Long Legendary Trading Card Name With Extra Words" : (state == "sealed" ? "Booster Bundle" : "Share test card"),
            setCode: state == "sealed" ? nil : "TST",
            setName: state.contains("long") ? "A Very Long Set Name With Extra Words" : "Test Set",
            number: state == "sealed" ? nil : CardShareNumber("087/165"),
            badge: state == "graded" ? .grade("PSA 10") : (["normal", "sealed"].contains(state) ? nil : .finish("Reverse")),
            rarity: state == "sealed" ? nil : CardShareRarity(
                raw: state == "normal" ? "Common" : "Special illustration rare",
                game: .pokemon, pokemonSetID: "sv08.5"),
            edition: state == "first-edition" ? "1st Edition" : nil
        )
    }

    private var reviewTrend: CardShareTrend? {
        guard state == "buy-one-piece" else { return nil }
        let now = Date.now.timeIntervalSince1970
        let points = [200.0, 150, 40, 25, 24, 23.5].enumerated().map { index, price in
            JustTCGHistoryPoint(p: price, t: now - Double(5 - index) * 4 * 86_400)
        }
        return CardShareTrend.make(points: points)
    }

    private var price: CardSharePrice {
        if state == "buy-one-piece" {
            return CardSharePrice(amount: 23.5, currencyCode: "USD", basis: "Market price", source: "TCGplayer", asOf: .now)
        }
        return CardSharePrice(amount: 64.2, currencyCode: "USD",
            basis: state == "graded" ? "PSA 10 market" : (state == "sealed" ? "Market price" : "Near Mint market"),
            source: state == "graded" ? "JustTCG" : "TCGplayer", asOf: .now)
    }

    /// Several owned finishes of one card, as the card page offers them.
    private var finishOptions: [CollectionShareOption] {
        [("normal", "Normal", 0.25), ("holo", "Holo", 1.8), ("reverse", "Reverse Holo", 0.9)].map { id, label, amount in
            CollectionShareOption(id: id, identity: identity, finishLabel: label,
                price: CardSharePrice(amount: amount, currencyCode: "USD", basis: "Near Mint market",
                    source: "TCGplayer", asOf: .now),
                showsFinishSheen: id != "normal", localArtworkFilename: nil, remoteArtworkURLs: [artworkURL])
        } + [CollectionShareOption(id: "psa10", identity: identity.replacingFinish(nil).withGrade("PSA 10"),
            finishLabel: "Holo",
            price: CardSharePrice(amount: 42, currencyCode: "USD", basis: "PSA 10 market", source: "JustTCG", asOf: .now),
            showsFinishSheen: false, localArtworkFilename: nil, remoteArtworkURLs: [artworkURL])]
    }

    var body: some View {
        Button("Open share sheet") { isPresented = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .sheet(isPresented: $isPresented) {
                Group {
                    if state.hasPrefix("buy") {
                        BuyCheckShareSheet(identity: identity, price: price, artworkURLs: [artworkURL], historyRequest: nil,
                            title: state == "buy-one-piece" ? "Share card" : "Share price check",
                            artworkLoader: loadArtwork, reviewTrend: reviewTrend)
                    } else if state == "unowned" {
                        CollectionShareSheet(options: [CollectionShareOption(id: "catalog", identity: identity,
                                finishLabel: identity.finish, price: price, showsFinishSheen: false,
                                localArtworkFilename: nil, remoteArtworkURLs: [artworkURL])],
                            priceCheck: .init(identity: identity, price: price, artworkURLs: [artworkURL],
                                              historyRequest: nil),
                            artworkLoader: loadArtwork)
                    } else if state.hasPrefix("finishes") {
                        CollectionShareSheet(options: finishOptions,
                            initialOptionID: state.contains("graded") ? "psa10" : "holo", artworkLoader: loadArtwork)
                    } else {
                        CollectionShareSheet(identity: identity, price: state == "no-price" ? nil : price,
                            showsFinishSheen: !["normal", "graded", "sealed"].contains(state), localArtworkFilename: nil,
                            remoteArtworkURLs: state == "missing-art" ? [] : [artworkURL], artworkLoader: loadArtwork)
                    }
                }
                .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("large-text") ? .accessibility3 : .large)
            }
    }

    /// Generated locally so screenshot states never depend on a provider or
    /// warmed image cache. The injected loader is used only by this DEBUG host.
    private func loadArtwork(_ filename: String?, _ urls: [URL]) async -> CardShareArtwork? {
        loadAttempts += 1
        if state.contains("missing-art") || state.contains("failed-art") { return nil }
        if state.contains("retry"), loadAttempts == 1 { return nil }
        if state.contains("slow") {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return nil }
        }
        let size: CGSize
        switch state {
        case "photo-tall": size = CGSize(width: 120, height: 360)
        case "photo-wide": size = CGSize(width: 360, height: 120)
        case "photo-extreme-tall": size = CGSize(width: 24, height: 480)
        case "photo-extreme-wide": size = CGSize(width: 480, height: 24)
        default: size = CGSize(width: 215, height: 300)
        }
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemMint.setFill()
            context.fill(CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8))
            ("TEST ART" as NSString).draw(at: CGPoint(x: 8, y: 8),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.black])
        }
        return CardShareArtwork(image: image, kind: state.hasPrefix("photo-") ? .userPhoto : .catalog)
    }
}
#endif
