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
// Both images follow one layout: artwork, identity in fixed places, value
// below a hairline, and every piece of small print in a single footer line.

enum CardShareStyle {
    /// The image is drawn at this size in points and rendered at 3x, giving a
    /// 1080 x 1350 portrait image that suits Messages, social posts and Discord.
    static let canvas = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3
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
    static let pixelSize = 1_200

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
        self.init(
            name: card.name,
            setCode: isSealed ? nil : card.setCode,
            setName: card.setName,
            number: isSealed ? nil : CardShareNumber(card.cardNumber),
            badge: badge
        )
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
            badge: badge
        )
    }

    static func gradeText(for card: CollectedCard) -> String? {
        guard let company = card.gradingCompany else { return nil }
        return card.cardGrade?.display(company: company)
            ?? [company.label, card.gradeRaw].compactMap { $0 }.joined(separator: " ")
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
    var now: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            ShareArtworkView(artwork: artwork, showsFinishSheen: showsFinishSheen, shadowRadius: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 17)

            ShareIdentityBlock(identity: identity)

            if let price {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(price.formattedAmount())
                        .font(.system(size: 27, weight: .heavy))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(price.basis)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CardShareStyle.tertiaryText)
                        .lineLimit(1)
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { ShareHairline() }
                .padding(.top, 14)
            }

            ShareFooter(source: price?.sourceLine(now: now))
                .padding(.top, 17)
        }
        .padding(EdgeInsets(top: 26, leading: 24, bottom: 19, trailing: 24))
        .frame(width: CardShareStyle.canvas.width, height: CardShareStyle.canvas.height)
        .background { ShareGround(glow: true) }
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
            VStack(alignment: .leading, spacing: 17) {
                identityRow
                stats
                if let trend {
                    trendBlock(trend)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trend == nil ? .leading : .topLeading)

            ShareFooter(source: footerSource)
                .padding(.top, 17)
        }
        .padding(EdgeInsets(top: 24, leading: 22, bottom: 19, trailing: 22))
        .frame(width: CardShareStyle.canvas.width, height: CardShareStyle.canvas.height)
        .background { ShareGround(glow: false) }
        .foregroundStyle(CardShareStyle.primaryText)
        .environment(\.colorScheme, .dark)
    }

    /// With no chart, the card picture grows to fill the space the chart
    /// would have used.
    private var thumbnailWidth: CGFloat { trend == nil ? 115 : 75 }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 17) {
            ShareArtworkView(artwork: artwork, showsFinishSheen: false, shadowRadius: 10)
                .frame(width: thumbnailWidth, height: thumbnailWidth / CardShareStyle.cardAspect)

            VStack(alignment: .leading, spacing: 7) {
                Text(identity.name)
                    .font(.system(size: 23, weight: .heavy))
                    .tracking(-0.3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if identity.setCode != nil || identity.number != nil {
                    HStack(spacing: 8) {
                        if let code = identity.setCode {
                            ShareSetCodeChip(code: code, size: 11)
                        }
                        if let number = identity.number {
                            ShareNumberText(number: number, size: 18)
                        }
                    }
                }
                if let setName = identity.setName {
                    Text(setName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CardShareStyle.secondaryText)
                        .lineLimit(1)
                }
                if let badge = identity.badge {
                    ShareBadge(badge: badge, size: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        ZStack {
            CardShareStyle.ground
            if glow {
                RadialGradient(
                    colors: [CardShareStyle.iris.opacity(0.24), CardShareStyle.iris.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: 230
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
        guard let image = artwork?.image, image.size.height > 0 else { return CardShareStyle.cardAspect }
        return min(max(image.size.width / image.size.height, 0.5), 1.6)
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
        let radius: CGFloat = artwork?.kind == .userPhoto ? 16 : max(6, size.width * 0.045)
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

private struct ShareIdentityBlock: View {
    let identity: CardShareIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(identity.name)
                    .font(.system(size: 25, weight: .heavy))
                    .tracking(-0.3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let number = identity.number {
                    ShareNumberText(number: number, size: 20)
                        .layoutPriority(1)
                }
            }
            if identity.setCode != nil || identity.setName != nil || identity.badge != nil {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        if let code = identity.setCode {
                            ShareSetCodeChip(code: code, size: 12)
                        }
                        if let setName = identity.setName {
                            Text(setName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CardShareStyle.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let badge = identity.badge {
                        ShareBadge(badge: badge, size: 13)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }
}

/// `087` bright and `/165` quiet: the card's own number is what a collector
/// looks for.
private struct ShareNumberText: View {
    let number: CardShareNumber
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(number.primary)
                .foregroundStyle(CardShareStyle.primaryText)
            if let total = number.total {
                Text(total)
                    .fontWeight(.bold)
                    .foregroundStyle(CardShareStyle.mutedText)
            }
        }
        .font(.system(size: size, weight: .heavy))
        .monospacedDigit()
        .tracking(-0.2)
        .lineLimit(1)
        .fixedSize()
    }
}

private struct ShareSetCodeChip: View {
    let code: String
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(code.uppercased())
            .font(.system(size: size, weight: .heavy))
            .tracking(0.7)
            .foregroundStyle(CardShareStyle.primaryText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: size + 10)
            .background(Color.white.opacity(0.10), in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
    }
}

private struct ShareBadge: View {
    let badge: CardShareIdentity.Badge
    let size: CGFloat

    var body: some View {
        let label = Text(badge.text)
            .font(.system(size: size, weight: .bold))
            .lineLimit(1)
            .fixedSize()
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
                .font(.system(size: 11, weight: .heavy))
                .fontWidth(.expanded)
                .foregroundStyle(CardShareStyle.primaryText.opacity(0.6))
        }
        .fixedSize()
    }
}

/// Every piece of small print lives here: source and date on the left, the
/// mark on the right.
private struct ShareFooter: View {
    let source: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(source ?? "")
                .font(.system(size: 12))
                .foregroundStyle(CardShareStyle.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
struct CollectionShareSheet: View {
    let identity: CardShareIdentity
    let price: CardSharePrice?
    let showsFinishSheen: Bool
    let localArtworkFilename: String?
    let remoteArtworkURLs: [URL]

    @Environment(\.dismiss) private var dismiss
    /// Remembers the last choice: someone who shares prices usually keeps
    /// sharing them, and someone who does not should never be surprised.
    @AppStorage("cardShare.includesPrice") private var includesPrice = false
    @State private var artwork: CardShareArtwork?
    @State private var isLoadingArtwork = true
    @State private var rendered: UIImage?

    private struct RenderKey: Equatable {
        let includesPrice: Bool
        let isLoadingArtwork: Bool
    }

    private var sharedPrice: CardSharePrice? { includesPrice ? price : nil }

    private var image: CollectionShareImage {
        CollectionShareImage(identity: identity, price: sharedPrice, artwork: artwork, showsFinishSheen: showsFinishSheen)
    }

    private var summary: String {
        CardShareSummary.text(identity: identity, price: sharedPrice)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CardSharePreview(content: image, summary: summary)
                priceRow
                CardShareButton(rendered: isLoadingArtwork ? nil : rendered, title: identity.name, message: summary)
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
        .task {
            artwork = await CardShareArtworkLoader.load(localFilename: localArtworkFilename, remoteURLs: remoteArtworkURLs)
            isLoadingArtwork = false
        }
        .task(id: RenderKey(includesPrice: includesPrice, isLoadingArtwork: isLoadingArtwork)) {
            rendered = CardShareRenderer.render(image)
        }
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
        .disabled(price == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(CardShareStyle.rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var priceRowDetail: String {
        guard let price else { return "No market price available yet" }
        guard includesPrice else { return "Just the card, its name and finish" }
        if let source = price.source { return "\(price.basis) from \(source)" }
        return price.basis
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

    @Environment(\.cardGameRuntimes) private var runtimes
    @Environment(\.dismiss) private var dismiss
    @State private var askText = ""
    @State private var trend: CardShareTrend?
    @State private var artwork: CardShareArtwork?
    @State private var isLoadingArtwork = true
    @State private var rendered: UIImage?
    @State private var now = Date.now
    @FocusState private var isAskFocused: Bool

    private struct RenderKey: Equatable {
        let ask: CardShareAsk?
        let trend: CardShareTrend?
        let isLoadingArtwork: Bool
    }

    private var ask: CardShareAsk? { CardShareAsk(text: askText, market: price.amount) }

    private var image: BuyCheckShareImage {
        BuyCheckShareImage(identity: identity, price: price, ask: ask, trend: trend, artwork: artwork, now: now)
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
                CardShareButton(rendered: isLoadingArtwork ? nil : rendered, title: identity.name, message: summary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .navigationTitle("Share price check")
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
        .task {
            artwork = await CardShareArtworkLoader.load(localFilename: nil, remoteURLs: artworkURLs)
            isLoadingArtwork = false
        }
        .task { await loadHistory() }
        .task(id: RenderKey(ask: ask, trend: trend, isLoadingArtwork: isLoadingArtwork)) {
            rendered = CardShareRenderer.render(image)
        }
    }

    private var askRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Asking price")
                    .font(.body.weight(.semibold))
                Text(ask?.comparisonText ?? "Optional. Compares it to market.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
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
            .frame(width: 116, height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { isAskFocused = true }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 60)
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
