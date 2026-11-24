import SwiftUI

enum TradeSide: CaseIterable, Hashable, Sendable {
    case give
    case receive

    var title: String { self == .give ? "You give" : "You receive" }
    /// For the one-line scanner controls at large text sizes.
    var shortTitle: String { self == .give ? "Give" : "Receive" }
    var opposite: Self { self == .give ? .receive : .give }
    var cashTitle: String { self == .give ? "Cash you give" : "Cash you receive" }
    /// Give is always mint and receive always indigo, so the ledger, the guide
    /// brackets and the receipt agree about where a card went.
    var tint: Color { self == .give ? .mint : Color(red: 0.49, green: 0.48, blue: 1) }
}

struct TradeScanDestination: Equatable, Sendable {
    let draftID: UUID
    let side: TradeSide
}

struct TradeEntry: Identifiable {
    var id: UUID { result.resolvedScan.request.encounterID }
    var side: TradeSide
    var quantity = 1
    var result: PriceCheckResult
    let refreshKey: PriceCheckCoordinator.TradeRefreshKey

    var identityText: String {
        let scan = result.resolvedScan
        let finish = scan.request.subject.slab.map { $0.grade.display(company: $0.company) }
            ?? result.card.finishAndTreatmentDisplayLabel(for: scan.resolved.variant)
        return [
            scan.request.identifier.scannerDisplayIdentifier(for: result.card),
            scan.pokemonPrintRun?.label,
            finish
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var artwork: CatalogCardArtworkSource {
        CatalogCardArtworkSource(identifiedCard: result.card, thumbnailURL: result.card.thumbnailImageURL,
                                 imageURL: result.card.displayImageURL, prefersFullSize: false)
    }

    var unitPrice: Money? {
        guard case let .price(price) = result.quote else { return nil }
        return PortfolioPriceEligibility.eligibleUnitPrice(
            amount: price.unitMarketPriceUSD, currencyCode: price.currencyCode
        )
    }

    var isLastKnown: Bool {
        guard unitPrice != nil else { return false }
        if case .lastKnown = result.quoteState { return true }
        return result.successfulQuoteState == .stale
    }

    var refreshState: PriceCheckQuoteState {
        if case let .lastKnown(issue) = result.quoteState { return ScannerViewModel.quoteState(for: issue) }
        return result.quoteState
    }

    var priceIssue: LocalizedStringResource? {
        guard !result.shouldAutoRefresh else { return nil }
        switch refreshState {
        case .providerUnavailable: return "Couldn’t reach the price provider."
        case .fallbackDisabled: return "Backup prices are off in Settings → Pricing."
        case .fallbackUnconfigured: return "Set up JustTCG in Settings → Pricing."
        case let .rateLimited(retryAt): return "Too many checks. Try again at \(Self.timeText(retryAt))."
        case let .budgetLimited(resetAt): return "Price checks used up. Resets \(Self.timeText(resetAt))."
        case .unsupportedGame: return "Prices are unavailable for this game."
        case .unsupportedFinish, .unsupportedTreatment, .gradedFinishUnresolved, .gradedIdentityUnresolved:
            return "The provider can’t identify this version for pricing."
        case .gradedSearchIncomplete: return "The provider’s graded price search couldn’t finish."
        case .notMatched, .mappingUnavailable, .gradedProductNotMatched, .gradedCardNotTracked, .gradedGradeNotTracked:
            return "This version couldn’t be matched to a price listing."
        case .noExactPrice, .gradedGradeNotPriced, .gradedCardHasNoPrices:
            return "No market price found for this version."
        case .checking, .current, .stale, .lastKnown: return nil
        }
    }

    /// Today's limits read as a time; only a later reset needs its date.
    private static func timeText(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    var canRetryPrice: Bool {
        guard !result.shouldAutoRefresh, unitPrice == nil || isLastKnown else { return false }
        switch refreshState {
        case .unsupportedGame, .unsupportedFinish, .unsupportedTreatment, .gradedFinishUnresolved, .gradedIdentityUnresolved:
            return false
        case let .rateLimited(retryAt), let .budgetLimited(retryAt):
            return Date.now >= retryAt
        default:
            return true
        }
    }
}

struct TradeSideTotal {
    var count = 0
    var checking = 0
    var unavailable = 0
    var hasLastKnown = false
    /// Card value used for the comparison: market, or the vendor rate's share
    /// of it on the give side.
    var cards: Money = .zero
    /// Card value at market, before any vendor rate.
    var marketCards: Money = .zero
    /// The vendor rate applied to this side's cards, if any.
    var vendorRate: Int?
    var cash: Money = .zero
    var missing: Int { checking + unavailable }
    var total: Money { cards + cash }
    var isPresent: Bool { count > 0 || !cash.isZero }
}

struct TradeDraft {
    let id = UUID()
    var scanSide: TradeSide = .receive
    var entries: [TradeEntry] = []
    /// A dealer's trade-in rate for your cards, as a whole percent below 100.
    /// Nil is market value. It never scales cash or the cards you receive.
    var vendorRate: Int?
    var cash: [TradeSide: Money] = [:]
    var latestScanID: TradeEntry.ID?
    private var removed: (entry: TradeEntry, index: Int)?

    var destination: TradeScanDestination { .init(draftID: id, side: scanSide) }
    var latest: TradeEntry? { entries.first { $0.id == latestScanID } }
    var isEmpty: Bool { entries.isEmpty && cash.values.allSatisfy(\.isZero) }
    var removedName: String? { removed?.entry.result.card.name }

    func count(on side: TradeSide) -> Int {
        entries.lazy.filter { $0.side == side }.reduce(0) { $0 + $1.quantity }
    }

    func total(on side: TradeSide) -> TradeSideTotal {
        var total = entries.lazy.filter { $0.side == side }.reduce(into: TradeSideTotal(cash: cash[side] ?? .zero)) { total, entry in
            total.count += entry.quantity
            if let unitPrice = entry.unitPrice {
                total.cards += unitPrice * entry.quantity
                total.hasLastKnown = total.hasLastKnown || entry.isLastKnown
            } else if entry.result.shouldAutoRefresh {
                total.checking += entry.quantity
            } else {
                total.unavailable += entry.quantity
            }
        }
        // Keep provider precision through quantity and subtotal arithmetic.
        // Round each side once to the cent so cash can exactly balance it.
        if total.cards.isValid {
            let remainder = total.cards.tenThousandths % 100
            total.cards += Money(tenThousandths: (remainder >= 50 ? 100 : 0) - remainder)
        }
        total.marketCards = total.cards
        if side == .give, let vendorRate, Self.vendorRates.contains(vendorRate) {
            total.cards = Self.scaled(total.cards, percent: vendorRate)
            total.vendorRate = vendorRate
        }
        return total
    }

    static let vendorRates = 1...99

    /// A whole-cent amount scaled by a whole percent, rounded half away from
    /// zero to the cent. Integer only, so the result is exact and repeatable.
    static func scaled(_ amount: Money, percent: Int) -> Money {
        let product = Money(tenThousandths: amount.tenThousandths / 100, isOverflowed: !amount.isValid) * percent
        guard product.isValid else { return product }
        let hundredthsOfCents = product.tenThousandths
        let cents = hundredthsOfCents >= 0 ? (hundredthsOfCents + 50) / 100 : -((-hundredthsOfCents + 50) / 100)
        return Money(tenThousandths: cents * 100)
    }

    static func difference(give: TradeSideTotal, receive: TradeSideTotal) -> Money? {
        guard give.isPresent, receive.isPresent, give.missing == 0, receive.missing == 0 else { return nil }
        let value = receive.total - give.total
        return value.isValid ? value : nil
    }

    mutating func balance() {
        guard let difference = Self.difference(give: total(on: .give), receive: total(on: .receive)),
              !difference.isZero else { return }
        let side: TradeSide = difference < .zero ? .receive : .give
        cash[side, default: .zero] += difference.magnitude
    }

    mutating func undoLatestScan() {
        guard let index = entries.firstIndex(where: { $0.id == latestScanID }) else { return }
        if entries[index].quantity > 1 {
            entries[index].quantity -= 1
        } else {
            entries.remove(at: index)
        }
        latestScanID = nil
    }

    mutating func remove(_ id: TradeEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removed = (entries.remove(at: index), index)
    }

    mutating func restore() {
        guard let removed else { return }
        entries.insert(removed.entry, at: min(removed.index, entries.count))
        self.removed = nil
        alignQuotes(for: removed.entry.refreshKey)
    }

    /// Rows of one exact instrument (same printing, finish and slab evidence)
    /// carry its newest usable quote, so identical cards on either side are
    /// valued alike regardless of when each was priced. Rows still awaiting
    /// their own check are left to it; side and quantity never change.
    mutating func alignQuotes(for key: PriceCheckCoordinator.TradeRefreshKey) {
        let matching = entries.indices.filter { entries[$0].refreshKey == key }
        guard matching.count > 1 else { return }
        var newest: PriceCheckResult?
        for index in matching {
            let result = entries[index].result
            guard let price = result.quote.usablePrice else { continue }
            if let current = newest?.quote.usablePrice,
               !QuoteEvidenceOrdering.isNewer(price, than: current, game: result.card.game) { continue }
            newest = result
        }
        guard let newest, let newestPrice = newest.quote.usablePrice else { return }
        for index in matching where !entries[index].result.shouldAutoRefresh {
            guard let price = entries[index].result.quote.usablePrice,
                  QuoteEvidenceOrdering.isNewer(newestPrice, than: price, game: newest.card.game) else { continue }
            entries[index].result.adoptEvidence(from: newest)
        }
    }

    mutating func forgetRemoval() { removed = nil }
}


struct TradeScannerControls: View {
    @ObservedObject var model: ScannerViewModel
    let openReview: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            // Chosen by text size rather than measured width: the ledger's
            // labels shrink a little to fit, while measuring would drop to the
            // pills as soon as a label (like a vendor rate) got a few points
            // longer. Above this size the three columns can't hold their text.
            if dynamicTypeSize > .xxLarge {
                pillControls
            } else {
                ledger
            }
        }
        // The band above the guide holds one 44-pt row; beyond this size the
        // one-line controls would be cut off. VoiceOver labels stay complete.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ledger

    /// The whole trade in one glance: each side's latest cards and value, and
    /// the gap between them in the middle. A side is also the switch that sends
    /// the next scan there; the middle opens review.
    private var ledger: some View {
        let draft = model.tradeDraft
        let give = draft.total(on: .give)
        let receive = draft.total(on: .receive)
        let difference = TradeDraft.difference(give: give, receive: receive)
        return HStack(spacing: 2) {
            ledgerSide(.give, total: give, entries: draft.entries)
            balance(difference: difference, give: give, receive: receive)
            ledgerSide(.receive, total: receive, entries: draft.entries)
        }
        .padding(3)
        .appGlass(cornerRadius: 22)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: draft.scanSide)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8), value: draft.entries.count)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8), value: difference)
        .sensoryFeedback(.success, trigger: difference?.isZero == true) { wasEven, isEven in !wasEven && isEven }
    }

    private func ledgerSide(_ side: TradeSide, total: TradeSideTotal, entries: [TradeEntry]) -> some View {
        let selected = model.tradeDraft.scanSide == side
        let leading = side == .give
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        // Entries are appended as they are scanned, so the newest is last.
        let stack = TradeSideStack(
            entries: Array(entries.filter { $0.side == side }.suffix(3)),
            count: total.count,
            tint: side.tint
        )
        let labels = VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
            // A vendor rate must stay readable, so the side's name shortens
            // before the rate is ever truncated.
            Group {
                if let rate = total.vendorRate {
                    ViewThatFits(in: .horizontal) {
                        Text("\(side.title) · \(rate)%")
                        Text("\(side.shortTitle) · \(rate)%")
                    }
                } else {
                    Text(side.title)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(side.tint)
            ledgerValue(total)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        return Button {
            model.setTradeScanSide(side)
        } label: {
            HStack(spacing: 9) {
                if leading {
                    stack
                    labels
                } else {
                    labels
                    stack
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 55, alignment: leading ? .leading : .trailing)
            .background {
                if selected {
                    shape.fill(side.tint.opacity(0.2))
                        .overlay(shape.strokeBorder(side.tint.opacity(0.45), lineWidth: 1))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("\(side.title), \(detail(side))")
        .accessibilityHint(selected ? "" : String(localized: "Scans go to this side."))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trade-side-\(side)")
    }

    /// A side's value shows only once every card on it is priced, so it is
    /// never a partial sum.
    @ViewBuilder
    private func ledgerValue(_ total: TradeSideTotal) -> some View {
        if total.isPresent, total.missing == 0, total.total.isValid {
            Text(total.total.formatted(locale: locale))
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
        } else {
            let status: LocalizedStringKey = !total.isPresent ? "None yet"
                : total.checking > 0 ? "Pricing…" : "Price missing"
            Text(status)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func balance(difference: Money?, give: TradeSideTotal, receive: TradeSideTotal) -> some View {
        let state = TradeBalanceState(difference: difference, give: give, receive: receive, locale: locale)
        return Button(action: openReview) {
            VStack(spacing: 2) {
                Text(state.caption)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Text(state.amount)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(state.color)
                    .contentTransition(.numericText())
                TradeBalanceGauge(lean: state.lean, tint: state.color)
                    .padding(.top, 2)
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: 64, minHeight: 55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Review trade")
        .accessibilityValue(Text(state.accessibilityValue))
        .accessibilityIdentifier("trade-review")
        .disabled(!model.canOpenTradeReview)
    }

    // MARK: Large-text pills

    private var pillControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                side(.give)
                side(.receive)
                review()
            }
            HStack(spacing: 6) {
                side(.give)
                side(.receive)
                review(compact: true)
            }
            // Large text: one line per control keeps both sides and Review in
            // the short band above the guide instead of a hidden scroll.
            HStack(spacing: 6) {
                side(.give, compact: true)
                side(.receive, compact: true)
                review(compact: true)
            }
            HStack(spacing: 6) {
                side(.give, compact: true, showsCount: false)
                side(.receive, compact: true, showsCount: false)
                review(compact: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                side(.give)
                side(.receive)
                review()
            }
        }
    }

    /// The count confirms the stack was fully scanned; the value appears only
    /// once every card on that side is priced, so it is never a partial sum.
    private func detail(_ side: TradeSide) -> String {
        let total = model.tradeDraft.total(on: side)
        let cards = total.count == 1 ? String(localized: "1 card") : String(localized: "\(total.count) cards")
        guard total.isPresent, total.missing == 0, total.total.isValid else { return cards }
        return "\(cards) · \(total.total.formatted(locale: locale))"
    }

    private func side(_ side: TradeSide, compact: Bool = false, showsCount: Bool = true) -> some View {
        let selected = model.tradeDraft.scanSide == side
        let detail = detail(side)
        return Button {
            model.setTradeScanSide(side)
        } label: {
            HStack(spacing: 5) {
                if compact {
                    HStack(spacing: 4) {
                        Text(side.shortTitle).font(.footnote.weight(.semibold))
                        if showsCount {
                            Text(model.tradeDraft.count(on: side), format: .number)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                    .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(side.title).font(.footnote.weight(.semibold))
                        Text(detail)
                            .font((dynamicTypeSize.isAccessibilitySize ? Font.caption2 : .caption).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.mint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .appPillGlass(tint: selected ? Color.mint.opacity(0.24) : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("\(side.title), \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trade-side-\(side)")
    }

    private func review(compact: Bool = false) -> some View {
        Button(action: openReview) {
            Group {
                if compact {
                    Image(systemName: "list.bullet").frame(width: 44)
                } else {
                    Label("Review", systemImage: "list.bullet")
                        .padding(.horizontal, 12)
                }
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .appPillGlass(interactive: true)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Review trade")
        .accessibilityIdentifier("trade-review")
        .disabled(!model.canOpenTradeReview)
    }
}

/// What the middle of the ledger says. It agrees with the review sheet's
/// verdict: only an exact match is "Even".
private struct TradeBalanceState {
    let caption: LocalizedStringKey
    let amount: String
    let color: Color
    /// -1 leans fully toward give, 1 fully toward receive.
    let lean: Double
    let accessibilityValue: LocalizedStringKey

    init(difference: Money?, give: TradeSideTotal, receive: TradeSideTotal, locale: Locale) {
        guard let difference else {
            let pricing = give.checking + receive.checking > 0
            caption = "Balance"
            amount = pricing ? String(localized: "Pricing…") : "–"
            color = .white.opacity(0.6)
            lean = 0
            accessibilityValue = pricing ? "Getting prices" : "Not enough to compare yet"
            return
        }
        let formatted = difference.magnitude.formatted(locale: locale)
        let larger = max(give.total, receive.total)
        let ratio = larger.isZero ? 0 : Double(difference.tenThousandths) / Double(larger.tenThousandths)
        lean = min(1, max(-1, ratio))
        if difference.isZero {
            caption = "Balance"
            amount = String(localized: "Even")
            color = .green
            accessibilityValue = "Even trade"
        } else if difference < .zero {
            caption = "You're over"
            amount = formatted
            color = .orange
            accessibilityValue = "You give \(formatted) more"
        } else {
            caption = "You're up"
            amount = formatted
            color = .green
            accessibilityValue = "You receive \(formatted) more"
        }
    }
}

/// A short track with a center mark; the dot leans toward the side giving more.
private struct TradeBalanceGauge: View {
    let lean: Double
    let tint: Color

    var body: some View {
        ZStack {
            Capsule().fill(.white.opacity(0.16)).frame(width: 46, height: 4)
            Capsule().fill(.white.opacity(0.5)).frame(width: 2, height: 8)
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.7), radius: 3)
                .offset(x: lean * 19)
        }
        .frame(width: 46, height: 8)
        .accessibilityHidden(true)
    }
}

/// The latest cards on one side, fanned with the newest on top, and the side's
/// card count as a badge. Same footprint as the collection session stack.
private struct TradeSideStack: View {
    /// Oldest first; the last entry is the newest.
    let entries: [TradeEntry]
    let count: Int
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            if entries.isEmpty {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 20, height: 28)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let depth = entries.count - 1 - index
                CardThumbnail(artwork: entry.artwork, width: 20)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .rotationEffect(.degrees(Double(depth) * -9), anchor: .bottom)
                    .offset(x: CGFloat(depth) * -4)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 30, height: 32)
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(count, format: .number)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(tint, in: Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                    .offset(x: 7, y: -6)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityHidden(true)
    }
}

struct TradeScannerReceipt: View {
    let entry: TradeEntry
    let undo: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    private var priceText: String? { entry.unitPrice?.formatted(locale: locale) }

    var body: some View {
        HStack(spacing: 9) {
            // The card itself leads, so the receipt is recognizable without
            // reading; the green check still says it was added.
            CardThumbnail(artwork: entry.artwork, width: 28)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 16, height: 16)
                        .background(.green, in: Circle())
                        .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1.5))
                        .offset(x: 5, y: 1)
                }
                .padding(.trailing, 2)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.result.card.name).font(.subheadline.weight(.semibold))
                        if let priceText {
                            Text(priceText).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        Text(entry.side.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(entry.side.tint)
                        Text(entry.identityText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .fixedSize()
                }
                .frame(height: 44)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    // The price shares the name's line so the identifier below
                    // gets the full width and the finish is not cut off.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.result.card.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let priceText {
                            Text("+\(priceText)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        } else if entry.result.shouldAutoRefresh {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    // The side leads so a long identifier truncates instead of
                    // hiding where the card went.
                    Text("\(Text(entry.side.title).foregroundStyle(entry.side.tint)) · \(entry.identityText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
            }
            if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo scan of \(entry.result.card.name)")
        }
        .foregroundStyle(.white)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : 2)
        .appGlass(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [entry.result.card.name, priceText, entry.identityText, entry.side.title].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityIdentifier("trade-receipt")
    }
}

/// The whole trade on one screen: the verdict first, then each side's cards
/// with that side's cash directly beneath them.
struct TradeReviewSheet: View {
    @ObservedObject var model: ScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var cashInputs: [TradeSide: String] = [:]
    @State private var invalidCash: Set<TradeSide> = []
    @State private var confirmsClear = false
    @State private var confirmsDiscard = false
    @State private var editsCustomRate = false
    @State private var customRateInput = ""
    @FocusState private var focusedCash: TradeSide?

    private static let presetVendorRates = [90, 80, 75, 70, 60]

    var body: some View {
        let draft = model.tradeDraft
        let give = draft.total(on: .give)
        let receive = draft.total(on: .receive)
        let difference = TradeDraft.difference(give: give, receive: receive)
        NavigationStack {
            List {
                Section {
                    TradeReviewHero(
                        entries: draft.entries, give: give, receive: receive,
                        difference: invalidCash.isEmpty ? difference : nil,
                        verdict: verdict(give: give, receive: receive, difference: difference),
                        problems: TradeProblems.list(for: draft.entries),
                        sharedSource: Self.sharedSource(draft.entries)
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                }
                ForEach(TradeSide.allCases, id: \.self) { side in
                    sideSection(side, total: side == .give ? give : receive, entries: draft.entries.filter { $0.side == side })
                }
                if !draft.isEmpty {
                    Section {
                        Button("Clear trade", role: .destructive) { confirmsClear = true }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { TradeReviewBackdrop() }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let removed = draft.removedName, focusedCash == nil {
                    RemovalUndoBanner(name: removed, onUndo: model.restoreTradeEntry, onDismiss: model.forgetTradeRemoval)
                } else if focusedCash == nil, invalidCash.isEmpty, let difference, !difference.isZero {
                    evenOutBar(difference)
                }
            }
            .contentWidthLimit(.standard)
            .navigationTitle("Review trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !draft.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: shareText(draft: draft, give: give, receive: receive, difference: difference)) {
                            Label("Share trade", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finishReview)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedCash != nil {
                        Spacer()
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
                            focusedCash = nil
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .alert("Discard cash edit?", isPresented: $confirmsDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("The last valid amount will be kept.")
            }
            .alert("Vendor rate", isPresented: $editsCustomRate) {
                TextField("Percent", text: $customRateInput)
                    .keyboardType(.numberPad)
                Button("Apply") { model.setTradeVendorRate(customRate) }
                    .disabled(customRate == nil)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The percent of market value the vendor gives for your cards, from 1 to 99.")
            }
            .onChange(of: focusedCash) { oldSide, _ in
                if let oldSide, !invalidCash.contains(oldSide) {
                    reloadCashInput(for: oldSide)
                }
            }
            .confirmationDialog("Clear this trade?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear trade", role: .destructive) {
                    focusedCash = nil
                    model.clearTrade()
                    // A cleared trade means the next one starts at the camera.
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(!invalidCash.isEmpty)
        .onAppear(perform: reloadCashInputs)
        // Undo belongs to this review visit; a later one starts clean.
        .onDisappear(perform: model.forgetTradeRemoval)
    }

    // MARK: Summary

    private func verdict(give: TradeSideTotal, receive: TradeSideTotal, difference: Money?) -> LocalizedStringResource {
        if !invalidCash.isEmpty { return "Check the cash amount" }
        if give.checking + receive.checking > 0 { return "Getting prices…" }
        if give.unavailable + receive.unavailable > 0 { return "Some prices are missing" }
        switch (give.isPresent, receive.isPresent) {
        case (false, false): return "Scan cards to compare"
        case (false, true): return "Add what you give"
        case (true, false): return "Add what you receive"
        case (true, true): break
        }
        guard let difference else { return "Can’t compare this trade" }
        if difference.isZero { return "Even trade" }
        let amount = difference.magnitude.formatted(locale: locale)
        return difference < .zero ? "You give \(amount) more" : "You receive \(amount) more"
    }

    /// Pinned below the list so evening out never needs a scroll. It uses the
    /// same amounts as the verdict, including any vendor rate.
    private func evenOutBar(_ difference: Money) -> some View {
        let amount = difference.magnitude.formatted(locale: locale)
        return Button {
            focusedCash = nil
            model.balanceTrade()
            reloadCashInputs()
        } label: {
            Label(
                difference < .zero ? "Get \(amount) cash to even it out" : "Pay \(amount) cash to even it out",
                systemImage: "banknote"
            )
            .font(.system(.headline, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
        .accessibilityIdentifier("trade-balance-cash")
    }

    // MARK: Vendor rate

    private var customRate: Int? {
        guard let value = Int(customRateInput.trimmingCharacters(in: .whitespaces)),
              TradeDraft.vendorRates.contains(value) else { return nil }
        return value
    }

    /// Deliberately quiet: one secondary row under your cards, not a control
    /// that competes with the verdict.
    private var vendorRateRow: some View {
        let rate = model.tradeDraft.vendorRate
        return Menu {
            Picker("Vendor rate", selection: Binding(
                get: { rate ?? 100 },
                set: { model.setTradeVendorRate($0) }
            )) {
                Text("Market value").tag(100)
                ForEach(Self.presetVendorRates, id: \.self) { Text("\($0)%").tag($0) }
                if let rate, !Self.presetVendorRates.contains(rate) {
                    Text("\(rate)%").tag(rate)
                }
            }
            Button("Other rate…") {
                customRateInput = rate.map(String.init) ?? ""
                editsCustomRate = true
            }
        } label: {
            HStack {
                Text("Vendor rate")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(rate.map { "\($0)%" } ?? String(localized: "Market"))
                    .foregroundStyle(rate == nil ? .secondary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        // A menu label takes the app tint; this row should read as a quiet
        // setting, not an action.
        .tint(.secondary)
        .accessibilityLabel("Vendor rate for your cards")
        .accessibilityValue(rate.map { "\($0)% of market" } ?? String(localized: "Market value"))
        .accessibilityIdentifier("trade-vendor-rate")
    }

    // MARK: Share

    /// Every card with its price, source, time and listing, so both people can
    /// check the same numbers.
    private func shareText(draft: TradeDraft, give: TradeSideTotal, receive: TradeSideTotal, difference: Money?) -> String {
        var lines: [String] = []
        for side in TradeSide.allCases {
            let total = side == .give ? give : receive
            var heading = "\(side.title) (\(total.count == 1 ? String(localized: "1 card") : String(localized: "\(total.count) cards")))"
            if total.isPresent, total.missing == 0, total.total.isValid {
                heading += ": \(total.total.formatted(locale: locale))"
                if let rate = total.vendorRate {
                    heading += " " + String(localized: "at \(rate)% vendor rate (\((total.marketCards + total.cash).formatted(locale: locale)) market)")
                }
            }
            lines.append(heading)
            for entry in draft.entries where entry.side == side {
                var line = "• \(entry.result.card.name) — \(entry.identityText)"
                if entry.quantity > 1 { line += " ×\(entry.quantity)" }
                if let unit = entry.unitPrice {
                    line += " — \((unit * entry.quantity).formatted(locale: locale))"
                    if let source = Self.sourceLine(entry) { line += " (\(source))" }
                } else {
                    line += " — " + String(localized: "no price")
                }
                if let link = TCGplayerLinkBuilder.destination(for: entry.result.resolvedScan) {
                    line += " \(link.url.absoluteString)"
                }
                lines.append(line)
            }
            if let cash = draft.cash[side], !cash.isZero {
                lines.append("• " + String(localized: "Cash: \(cash.formatted(locale: locale))"))
            }
            lines.append("")
        }
        lines.append(String(localized: verdict(give: give, receive: receive, difference: difference)))
        return lines.joined(separator: "\n")
    }

    /// "TCGplayer · Today 4:12 PM" or "TCGplayer · Nov 20".
    fileprivate static func sourceLine(_ entry: TradeEntry) -> String? {
        guard case let .price(price) = entry.result.quote, entry.unitPrice != nil else { return nil }
        let date = price.effectiveAsOf
        let when = Calendar.current.isDateInToday(date)
            ? String(localized: "Today \(date.formatted(date: .omitted, time: .shortened))")
            : date.formatted(.dateTime.month(.abbreviated).day())
        return "\(price.source.label) · \(when)"
    }

    /// "TCGplayer prices · Today 4:12 PM" when every card is priced from one
    /// source today, so the rows don't each repeat it. The time is the oldest
    /// quote's, so the line never overstates freshness.
    fileprivate static func sharedSource(_ entries: [TradeEntry]) -> String? {
        var source: String?
        var oldest: Date?
        for entry in entries {
            guard isCurrent(entry), case let .price(price) = entry.result.quote else { return nil }
            if let source, source != price.source.label { return nil }
            source = price.source.label
            oldest = min(oldest ?? price.effectiveAsOf, price.effectiveAsOf)
        }
        guard let source, let oldest else { return nil }
        return String(localized: "\(source) prices · Today \(oldest.formatted(date: .omitted, time: .shortened))")
    }

    fileprivate static func isCurrent(_ entry: TradeEntry) -> Bool {
        guard case let .price(price) = entry.result.quote, entry.unitPrice != nil else { return false }
        return !entry.isLastKnown && Calendar.current.isDateInToday(price.effectiveAsOf)
    }

    // MARK: Sides

    private func sideSection(_ side: TradeSide, total: TradeSideTotal, entries: [TradeEntry]) -> some View {
        Section {
            if entries.isEmpty {
                Text("No cards")
                    .foregroundStyle(.secondary)
                    .listRowBackground(TradeRowBackground(side: side))
            }
            ForEach(entries) { entry in
                entryRow(entry)
                    .listRowBackground(TradeRowBackground(side: side))
            }
            cashRow(side)
                .listRowBackground(TradeRowBackground(side: side))
            if side == .give {
                vendorRateRow
                    .listRowBackground(TradeRowBackground(side: side))
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(side.tint).frame(width: 8, height: 8).accessibilityHidden(true)
                switch total.count {
                case 0: Text(side.title)
                case 1: Text("\(side.title) · 1 card")
                default: Text("\(side.title) · \(total.count) cards")
                }
            }
        }
    }

    private func cashRow(_ side: TradeSide) -> some View {
        let isInvalid = invalidCash.contains(side)
        let field = TextField(side.cashTitle, text: cashBinding(side), prompt: Text(cashText(.zero)))
            .font(.body.monospacedDigit())
            .keyboardType(.decimalPad)
            .focused($focusedCash, equals: side)
            .foregroundStyle(isInvalid ? Color.red : Color.primary)
            .accessibilityLabel(side.cashTitle)
            .accessibilityIdentifier("trade-cash-\(side)")
        return VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                Label("Cash", systemImage: "banknote")
                    .accessibilityHidden(true)
                field
            } else {
                HStack {
                    Label("Cash", systemImage: "banknote")
                        .accessibilityHidden(true)
                    Spacer(minLength: 12)
                    field
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160)
                }
            }
            if isInvalid {
                Text("Enter an amount like 5.00")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { focusedCash = side }
    }

    private func entryRow(_ entry: TradeEntry) -> some View {
        let moveTitle: LocalizedStringResource = "Switch side"
        return DisclosureGroup {
            quantityControl(entry)
            if let details = priceDetails(entry) {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let issue = entry.priceIssue {
                Text(issue).font(.footnote).foregroundStyle(.secondary)
            }
            if entry.canRetryPrice {
                Button("Retry price", systemImage: "arrow.clockwise") { model.retryTradeQuote(entry.id) }
                    .buttonStyle(.borderless)
            }
            Button(moveTitle, systemImage: "arrow.left.arrow.right") { model.moveTradeEntry(entry.id) }
                .buttonStyle(.borderless)
            Button("Remove", systemImage: "trash", role: .destructive) { model.removeTradeEntry(entry.id) }
                .buttonStyle(.borderless)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                let card = entry.result.card
                CardThumbnail(artwork: entry.artwork, width: 44)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottomTrailing) {
                        if entry.quantity > 1 {
                            Text("×\(entry.quantity)")
                                .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.thickMaterial, in: Capsule())
                                .offset(x: 7, y: 5)
                                .accessibilityLabel("Quantity \(entry.quantity)")
                        }
                    }
                    .padding(.trailing, 4)
                let stacked = dynamicTypeSize >= .xxxLarge
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                layout {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name).font(.subheadline.weight(.semibold))
                        Text(entry.identityText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Where the price came from and how old it is, without
                        // opening the row: the first thing to check in a dispute.
                        if let source = Self.sourceLine(entry),
                           Self.sharedSource(model.tradeDraft.entries) == nil || !Self.isCurrent(entry) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Self.isCurrent(entry) ? Color.green : .orange)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                                Text(source)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    entryPrice(entry, alignment: stacked ? .leading : .trailing)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityActions {
                if let link = TCGplayerLinkBuilder.destination(for: entry.result.resolvedScan) {
                    Button(link.accessibilityLabel) { openURL(link.url) }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", systemImage: "trash", role: .destructive) { model.removeTradeEntry(entry.id) }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(moveTitle, systemImage: "arrow.left.arrow.right") { model.moveTradeEntry(entry.id) }
                .tint(.indigo)
        }
    }

    /// The per-card price when the row shows a quantity total. Source and time
    /// are already on the row itself.
    private func priceDetails(_ entry: TradeEntry) -> String? {
        guard entry.quantity > 1, let unitPrice = entry.unitPrice else { return nil }
        let amount = unitPrice.doubleValue.formatted(
            .currency(code: "USD").precision(.fractionLength(2...4)).locale(locale)
        )
        return String(localized: "\(amount) each")
    }

    @ViewBuilder
    private func quantityControl(_ entry: TradeEntry) -> some View {
        let label = Text("Quantity \(entry.quantity)")
        let stepper = Stepper(value: Binding(
            get: { model.tradeDraft.entries.first { $0.id == entry.id }?.quantity ?? entry.quantity },
            set: { model.setTradeQuantity($0, for: entry.id) }
        ), in: 1...CollectionQuantityLimits.maximum) { label }

        if dynamicTypeSize >= .xxxLarge {
            VStack(alignment: .leading, spacing: 4) {
                label.accessibilityHidden(true)
                stepper.labelsHidden()
            }
        } else {
            stepper
        }
    }

    private func entryPrice(_ entry: TradeEntry, alignment: HorizontalAlignment) -> some View {
        let unitPrice = entry.unitPrice
        return VStack(alignment: alignment, spacing: 3) {
            if let price = unitPrice {
                let amount = Text((price * entry.quantity).formatted(locale: locale))
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                // Only an exact product page; a search could show the wrong
                // card. Tapping the price is how you check the price.
                if let link = TCGplayerLinkBuilder.destination(for: entry.result.resolvedScan) {
                    Button { openURL(link.url) } label: {
                        HStack(spacing: 3) {
                            amount
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(link.accessibilityLabel)
                } else {
                    amount
                }
            }
            if entry.result.shouldAutoRefresh {
                if unitPrice == nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Getting price")
                } else {
                    Text("Updating").font(.caption).foregroundStyle(.secondary)
                }
            } else if unitPrice == nil {
                // Matches the summary's note so the row holding up the
                // comparison is easy to find.
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("No price").foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
            } else if entry.isLastKnown {
                Text("Last known")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Cash input

    private func finishReview() {
        focusedCash = nil
        if invalidCash.isEmpty {
            dismiss()
        } else {
            confirmsDiscard = true
        }
    }

    private func cashBinding(_ side: TradeSide) -> Binding<String> {
        Binding {
            cashInputs[side, default: ""]
        } set: { text in
            cashInputs[side] = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invalidCash.remove(side)
                model.setTradeCash(.zero, on: side)
            } else if let amount = LocalizedNumberInput.parse(text, locale: locale),
                      amount >= 0,
                      let money = Money(rounding: amount), money.tenThousandths % 100 == 0,
                      abs(amount * 100 - (amount * 100).rounded()) <= max((amount * 100).ulp, 0.000000001) {
                invalidCash.remove(side)
                model.setTradeCash(money, on: side)
            } else {
                invalidCash.insert(side)
            }
        }
    }

    private func reloadCashInputs() {
        invalidCash.removeAll()
        for side in TradeSide.allCases {
            reloadCashInput(for: side)
        }
    }

    private func reloadCashInput(for side: TradeSide) {
        let amount = model.tradeDraft.cash[side] ?? .zero
        cashInputs[side] = amount.isZero ? "" : cashText(amount)
    }

    private func cashText(_ amount: Money) -> String {
        amount.doubleValue.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }
}

/// Give and receive as one bar, in the scanner's side colors.
private struct TradeValueBar: View {
    let give: Money
    let receive: Money

    var body: some View {
        GeometryReader { geometry in
            let total = max(1, give.doubleValue + receive.doubleValue)
            let gap: CGFloat = 3
            let available = max(0, geometry.size.width - gap)
            let giveWidth = available * give.doubleValue / total
            HStack(spacing: gap) {
                Capsule().fill(TradeSide.give.tint).frame(width: max(giveWidth, 4))
                Capsule().fill(TradeSide.receive.tint)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Only what needs a second look before trading: cards without a price and
/// prices that are not from today. An empty list means nothing to flag.
private enum TradeProblems {
    static func list(for entries: [TradeEntry]) -> [String] {
        var problems: [String] = []
        let unpriced = entries.filter { $0.unitPrice == nil && !$0.result.shouldAutoRefresh }
        if unpriced.count == 1, let entry = unpriced.first {
            problems.append(String(localized: "\(entry.result.card.name) has no price"))
        } else if !unpriced.isEmpty {
            problems.append(String(localized: "\(unpriced.count) cards have no price"))
        }
        let older = entries.filter { $0.unitPrice != nil && !TradeReviewSheet.isCurrent($0) }
        if older.count == 1, let entry = older.first {
            problems.append(entry.isLastKnown
                ? String(localized: "\(entry.result.card.name) uses a last-known price")
                : String(localized: "\(entry.result.card.name)’s price is older than today"))
        } else if !older.isEmpty {
            problems.append(String(localized: "\(older.count) prices are older than today"))
        }
        return problems
    }
}

/// The trade as a table: your cards facing theirs, and the one number that
/// decides it. Everything else on the screen is supporting detail.
private struct TradeReviewHero: View {
    let entries: [TradeEntry]
    let give: TradeSideTotal
    let receive: TradeSideTotal
    /// Nil when the two sides can't be compared yet.
    let difference: Money?
    let verdict: LocalizedStringResource
    let problems: [String]
    let sharedSource: String?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 54.0
    @ScaledMetric(relativeTo: .title) private var centsSize = 32.0

    var body: some View {
        VStack(spacing: 20) {
            if !problems.isEmpty {
                problemList
            }
            table
            verdictView
            if difference != nil {
                TradeValueBar(give: give.total, receive: receive.total)
                    .padding(.horizontal, 8)
            }
            if let sharedSource {
                Label(sharedSource, systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(TradeSourceLabelStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: difference)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: entries.count)
    }

    // MARK: Table

    private var table: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return layout {
            sideColumn(.give, total: give)
            medallion
                .padding(.top, 28)
            sideColumn(.receive, total: receive)
        }
    }

    private func sideColumn(_ side: TradeSide, total: TradeSideTotal) -> some View {
        VStack(spacing: 12) {
            TradeHeroStack(
                entries: Array(entries.filter { $0.side == side }.suffix(3)),
                count: total.count,
                tint: side.tint
            )
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(side.tint).frame(width: 7, height: 7)
                    Text(side.title)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                Text(value(total))
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(total.isPresent && total.missing == 0 ? .primary : .secondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                if let rate = total.vendorRate, total.missing == 0, total.marketCards.isValid {
                    // The market value stays visible so the adjustment is never hidden.
                    Text("\(Text((total.marketCards + total.cash).formatted(locale: locale)).strikethrough()) · \(rate)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if total.missing > 0, total.isPresent {
                    Text(total.count == total.missing && total.cash.isZero ? "No prices yet" : "Priced so far")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func value(_ total: TradeSideTotal) -> String {
        guard total.isPresent, total.total.isValid,
              !(total.count > 0 && total.count == total.missing && total.cash.isZero) else { return "—" }
        return total.total.formatted(locale: locale)
    }

    private var medallion: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LinearGradient(colors: AppPalette.foil, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    // MARK: Verdict

    @ViewBuilder
    private var verdictView: some View {
        Group {
            if let difference, difference.isValid {
                if difference.isZero {
                    Text("Even trade")
                        .font(.system(size: centsSize + 6, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: AppPalette.foil, startPoint: .leading, endPoint: .trailing))
                } else {
                    VStack(spacing: 2) {
                        amount(difference.magnitude)
                            .foregroundStyle(difference < .zero ? Color.orange : .green)
                        Text(difference < .zero ? "You give more" : "You receive more")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(verdict)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verdict))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("trade-comparison")
    }

    /// Whole dollars large, cents quieter: the same treatment as card detail.
    private func amount(_ money: Money) -> some View {
        let formatted = money.formatted(locale: locale)
        let separator = locale.decimalSeparator ?? "."
        let split = formatted.range(of: separator, options: .backwards)
        let lead = split.map { String(formatted[..<$0.lowerBound]) } ?? formatted
        let cents = split.map { String(formatted[$0.lowerBound...]) }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(lead)
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .tracking(-1)
            if let cents {
                Text(cents)
                    .font(.system(size: centsSize, weight: .bold, design: .rounded))
                    .opacity(0.55)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
    }

    private var problemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

/// One side's cards, fanned like a hand with the newest on top, over a soft
/// glow in the side's color.
private struct TradeHeroStack: View {
    /// Oldest first; the last entry is the newest.
    let entries: [TradeEntry]
    let count: Int
    let tint: Color

    var body: some View {
        ZStack {
            Ellipse()
                .fill(tint.opacity(entries.isEmpty ? 0.12 : 0.38))
                .frame(width: 92, height: 70)
                .blur(radius: 22)
            if entries.isEmpty {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 54, height: 75)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let depth = entries.count - 1 - index
                // Older cards splay out to alternate sides behind the newest.
                let direction: Double = depth == 1 ? -1 : 1
                CardThumbnail(artwork: entry.artwork, width: 54)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
                    .rotationEffect(.degrees(depth == 0 ? 0 : direction * 10), anchor: .bottom)
                    .offset(x: depth == 0 ? 0 : CGFloat(direction) * 16, y: depth == 0 ? 0 : 3)
                    .zIndex(Double(-depth))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(width: 110, height: 92)
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text(count, format: .number)
                    .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(tint, in: Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                    .offset(x: -6, y: -2)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Grouped background lit from the top by both sides' colors, so the sheet
/// reads as the trade's own space rather than a settings list.
private struct TradeReviewBackdrop: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(
                colors: [TradeSide.give.tint.opacity(0.22), .clear],
                center: UnitPoint(x: 0.12, y: 0.1), startRadius: 0, endRadius: 280
            )
            RadialGradient(
                colors: [TradeSide.receive.tint.opacity(0.26), .clear],
                center: UnitPoint(x: 0.88, y: 0.1), startRadius: 0, endRadius: 280
            )
        }
        .ignoresSafeArea()
    }
}

/// A row in one side's section, washed faintly in that side's color from the
/// leading edge so the two lists can't be confused at a glance.
private struct TradeRowBackground: View {
    let side: TradeSide

    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            LinearGradient(
                colors: [side.tint.opacity(0.11), side.tint.opacity(0.02)],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }
}

private struct TradeSourceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.green)
            configuration.title
        }
    }
}
