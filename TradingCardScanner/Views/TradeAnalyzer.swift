import SwiftUI

enum TradeSide: CaseIterable, Hashable, Sendable {
    case give
    case receive

    var title: String { self == .give ? "You give" : "You receive" }
    var opposite: Self { self == .give ? .receive : .give }
    var cashTitle: String { self == .give ? "Cash you give" : "Cash you receive" }
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
        case let .rateLimited(retryAt): return "Too many checks. Try again \(retryAt.formatted())."
        case let .budgetLimited(resetAt): return "Price checks used up. Resets \(resetAt.formatted())."
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
    var cards: Money = .zero
    var cash: Money = .zero
    var missing: Int { checking + unavailable }
    var total: Money { cards + cash }
    var isPresent: Bool { count > 0 || !cash.isZero }
}

struct TradeDraft {
    let id = UUID()
    var scanSide: TradeSide = .receive
    var entries: [TradeEntry] = []
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
        return total
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
    }
}


struct TradeScannerControls: View {
    @ObservedObject var model: ScannerViewModel
    let openReview: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    side(.give)
                    side(.receive)
                }
                review()
            }
            VStack(alignment: .leading, spacing: 4) {
                side(.give)
                side(.receive)
                review()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The count confirms the stack was fully scanned; the value appears only
    /// once every card on that side is priced, so it is never a partial sum.
    private func detail(_ side: TradeSide) -> String {
        let total = model.tradeDraft.total(on: side)
        let cards = total.count == 1 ? String(localized: "1 card") : String(localized: "\(total.count) cards")
        guard total.isPresent, total.missing == 0, total.total.isValid else { return cards }
        return "\(cards) · \(total.total.formatted(locale: locale))"
    }

    private func side(_ side: TradeSide) -> some View {
        let selected = model.tradeDraft.scanSide == side
        let detail = detail(side)
        return Button {
            model.setTradeScanSide(side)
        } label: {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(side.title).font(.footnote.weight(.semibold))
                    Text(detail)
                        .font((dynamicTypeSize.isAccessibilitySize ? Font.caption2 : .caption).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
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

struct TradeScannerReceipt: View {
    let entry: TradeEntry
    let undo: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    private var priceText: String? { entry.unitPrice?.formatted(locale: locale) }

    var body: some View {
        HStack(spacing: 8) {
            ScannerStatusBadge(tone: .added, systemName: "checkmark")
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.result.card.name).font(.subheadline.weight(.semibold))
                        if let priceText {
                            Text(priceText).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        Text(entry.side.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.mint)
                        Text(entry.identityText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .fixedSize()
                }
                .frame(height: 44)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.result.card.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    // The side leads so a long identifier truncates instead of
                    // hiding where the card went.
                    Text("\(Text(entry.side.title).foregroundStyle(.mint)) · \(entry.identityText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let priceText {
                    Text(priceText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                } else if entry.result.shouldAutoRefresh {
                    ProgressView().controlSize(.small).tint(.white)
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
        .padding(.leading, 10)
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
    @State private var cashInputs: [TradeSide: String] = [:]
    @State private var invalidCash: Set<TradeSide> = []
    @State private var confirmsClear = false
    @State private var confirmsDiscard = false
    @FocusState private var focusedCash: TradeSide?

    var body: some View {
        let draft = model.tradeDraft
        let give = draft.total(on: .give)
        let receive = draft.total(on: .receive)
        NavigationStack {
            List {
                Section { summary(give: give, receive: receive) }
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
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let removed = draft.removedName, focusedCash == nil {
                    RemovalUndoBanner(name: removed, onUndo: model.restoreTradeEntry)
                }
            }
            .contentWidthLimit(.standard)
            .navigationTitle("Review trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
    }

    // MARK: Summary

    private func summary(give: TradeSideTotal, receive: TradeSideTotal) -> some View {
        let difference = TradeDraft.difference(give: give, receive: receive)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Market value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verdict(give: give, receive: receive, difference: difference))
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("trade-comparison")
                statusNotes(give: give, receive: receive)
            }
            let totals = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            totals {
                sideValue(.give, give)
                sideValue(.receive, receive)
            }
            if invalidCash.isEmpty, let difference, !difference.isZero {
                Button {
                    focusedCash = nil
                    model.balanceTrade()
                    reloadCashInputs()
                } label: {
                    let amount = difference.magnitude.formatted(locale: locale)
                    Text(difference < .zero ? "Get \(amount) cash to even it out" : "Pay \(amount) cash to even it out")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("trade-balance-cash")
            }
        }
        .padding(.vertical, 6)
    }

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

    @ViewBuilder
    private func statusNotes(give: TradeSideTotal, receive: TradeSideTotal) -> some View {
        let unavailable = give.unavailable + receive.unavailable
        if unavailable > 0 {
            note(
                unavailable == 1 ? "1 card has no price. Retry or remove it." : "\(unavailable) cards have no price. Retry or remove them.",
                systemImage: "exclamationmark.circle"
            )
        }
        if give.hasLastKnown || receive.hasLastKnown {
            note("Includes last-known prices", systemImage: "clock")
        }
    }

    private func note(_ text: LocalizedStringResource, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func sideValue(_ side: TradeSide, _ total: TradeSideTotal) -> some View {
        let isUnpriced = total.count > 0 && total.count == total.missing && total.cash.isZero
        return VStack(alignment: .leading, spacing: 2) {
            Text(side.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(isUnpriced || !total.isPresent || !total.total.isValid ? "—" : total.total.formatted(locale: locale))
                .font(.title3.weight(.semibold).monospacedDigit())
            if total.missing > 0 {
                Text(isUnpriced ? "No prices yet" : "Priced so far")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sides

    private func sideSection(_ side: TradeSide, total: TradeSideTotal, entries: [TradeEntry]) -> some View {
        Section {
            if entries.isEmpty {
                Text("No cards")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                entryRow(entry)
            }
            cashRow(side)
        } header: {
            Text(total.count == 1 ? "\(side.title) · 1 card" : "\(side.title) · \(total.count) cards")
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
                CardThumbnail(artwork: CatalogCardArtworkSource(
                    identifiedCard: card, thumbnailURL: card.thumbnailImageURL, imageURL: card.displayImageURL,
                    prefersFullSize: false
                ), width: 34)
                .accessibilityHidden(true)
                let stacked = dynamicTypeSize >= .xxxLarge
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                layout {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name).font(.subheadline.weight(.semibold))
                        Text(entry.quantity > 1 ? "\(entry.identityText) · ×\(entry.quantity)" : entry.identityText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    entryPrice(entry, alignment: stacked ? .leading : .trailing)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", systemImage: "trash", role: .destructive) { model.removeTradeEntry(entry.id) }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(moveTitle, systemImage: "arrow.left.arrow.right") { model.moveTradeEntry(entry.id) }
                .tint(.indigo)
        }
    }

    /// Source and age of the quote, with the per-card price when the row
    /// shows a quantity total.
    private func priceDetails(_ entry: TradeEntry) -> String? {
        guard case let .price(price) = entry.result.quote, let unitPrice = entry.unitPrice else { return nil }
        var parts: [String] = []
        if entry.quantity > 1 {
            let amount = unitPrice.doubleValue.formatted(
                .currency(code: "USD").precision(.fractionLength(2...4)).locale(locale)
            )
            parts.append(String(localized: "\(amount) each"))
        }
        parts.append(price.source.label)
        parts.append(price.effectiveAsOf.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
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
                Text((price * entry.quantity).formatted(locale: locale))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            if entry.result.shouldAutoRefresh {
                if unitPrice == nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Getting price")
                } else {
                    Text("Updating").font(.caption).foregroundStyle(.secondary)
                }
            } else if unitPrice == nil || entry.isLastKnown {
                Text(unitPrice == nil ? "No price" : "Last known")
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
