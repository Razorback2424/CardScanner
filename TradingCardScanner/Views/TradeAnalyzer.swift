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

    private func side(_ side: TradeSide) -> some View {
        let selected = model.tradeDraft.scanSide == side
        let count = model.tradeDraft.count(on: side)
        return Button {
            model.setTradeScanSide(side)
        } label: {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(side.title).font(.footnote.weight(.semibold))
                    Text(count == 1 ? "1 card" : "\(count) cards")
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
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("trade-side-\(side)")
    }

    private func review(compact: Bool = false) -> some View {
        Button(action: openReview) {
            Group {
                if compact {
                    Image(systemName: "list.bullet").frame(width: 44)
                } else {
                    Label("Review trade", systemImage: "list.bullet")
                        .padding(.horizontal, 10)
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

    var body: some View {
        HStack(spacing: 8) {
            ScannerStatusBadge(tone: .added, systemName: "checkmark")
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.result.card.name).font(.subheadline.weight(.semibold))
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.result.card.name), \(entry.identityText), \(entry.side.title)")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.result.card.name).font(.subheadline.weight(.semibold))
                    Text("\(entry.identityText) · \(entry.side.title)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
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
        .accessibilityIdentifier("trade-receipt")
    }
}

struct TradeReviewSheet: View {
    @ObservedObject var model: ScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var side: TradeSide
    @State private var cashInputs: [TradeSide: String] = [:]
    @State private var invalidCash: Set<TradeSide> = []
    @State private var confirmsClear = false
    @State private var confirmsDiscard = false
    @FocusState private var focusedCash: TradeSide?

    init(model: ScannerViewModel) {
        self.model = model
        _side = State(initialValue: model.tradeDraft.scanSide)
    }

    var body: some View {
        let draft = model.tradeDraft
        let give = draft.total(on: .give)
        let receive = draft.total(on: .receive)
        NavigationStack {
            List {
                Section { summary(give: give, receive: receive) }
                Section {
                    sideSelector(give: give.count, receive: receive.count)
                    let entries = draft.entries.filter { $0.side == side }
                    if entries.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No cards on this side")
                                .font(.subheadline.weight(.semibold))
                            Text("Scan cards to add them here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
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
            .alert("Discard invalid cash edits?", isPresented: $confirmsDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard and close", role: .destructive) { dismiss() }
            } message: {
                Text("Your last valid cash amounts will be kept.")
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
                    reloadCashInputs()
                    side = model.tradeDraft.scanSide
                }
            }
        }
        .interactiveDismissDisabled(!invalidCash.isEmpty)
        .onAppear(perform: reloadCashInputs)
    }

    private func summary(give: TradeSideTotal, receive: TradeSideTotal) -> some View {
        let difference = TradeDraft.difference(give: give, receive: receive)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Market estimate · USD")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(comparisonText(give: give, receive: receive, difference: difference))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("trade-comparison")
                if give.hasLastKnown || receive.hasLastKnown {
                    Label("Includes last-known prices", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
                .accessibilityHidden(true)
            sideTotals(give: give, receive: receive)
            if invalidCash.isEmpty, let difference, !difference.isZero {
                Button {
                    focusedCash = nil
                    model.balanceTrade()
                    reloadCashInputs()
                } label: {
                    let amount = difference.magnitude.formatted(locale: locale)
                    Label(
                        difference < .zero ? "Receive \(amount) more cash" : "Give \(amount) more cash",
                        systemImage: "plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Adds cash to balance the trade.")
                .accessibilityIdentifier("trade-balance-cash")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sideTotals(give: TradeSideTotal, receive: TradeSideTotal) -> some View {
        if dynamicTypeSize >= .xxxLarge {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    sideValue(.give, give)
                    cashField(.give)
                }
                VStack(alignment: .leading, spacing: 8) {
                    sideValue(.receive, receive)
                    cashField(.receive)
                }
            }
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    sideValue(.give, give)
                    sideValue(.receive, receive)
                }
                GridRow {
                    cashField(.give)
                    cashField(.receive)
                }
            }
        }
    }

    private func sideValue(_ side: TradeSide, _ total: TradeSideTotal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(side.title)
                .font(.subheadline.weight(.semibold))
            if invalidCash.contains(side) {
                Text("Check cash amount")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if total.count > 0, total.count == total.missing, total.cash.isZero {
                Text(total.checking > 0 ? "Awaiting prices" : "Price unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(total.total.formatted(locale: locale))
                    .font(.title2.weight(.semibold).monospacedDigit())
                if total.missing > 0, total.total.isValid {
                    Text("Known subtotal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !total.cash.isZero, total.count > total.missing, total.cards.isValid {
                let amount = total.cards.formatted(locale: locale)
                Text(total.missing > 0 ? "Priced cards \(amount)" : "Cards \(amount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cashField(_ side: TradeSide) -> some View {
        let isInvalid = invalidCash.contains(side)
        return VStack(alignment: .leading, spacing: 4) {
            Text(dynamicTypeSize >= .xxxLarge ? String(localized: "Cash") : side.cashTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            TextField(side.cashTitle, text: cashBinding(side), prompt: Text(cashText(.zero)))
                .font(.body.monospacedDigit())
                .keyboardType(.decimalPad)
                .focused($focusedCash, equals: side)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if isInvalid || focusedCash == side {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isInvalid ? Color.red : Color.accentColor, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(side.cashTitle)
                .accessibilityIdentifier("trade-cash-\(side)")
            if isInvalid {
                Text("Use zero or a positive amount with up to two decimal places.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonText(give: TradeSideTotal, receive: TradeSideTotal, difference: Money?) -> LocalizedStringResource {
        if !invalidCash.isEmpty { return "Check the cash amounts" }
        let checking = give.checking + receive.checking
        let unavailable = give.unavailable + receive.unavailable
        if checking > 0 && unavailable > 0 { return "Checking \(checking) · \(unavailable) unavailable" }
        if checking > 0 { return checking == 1 ? "Checking 1 price" : "Checking \(checking) prices" }
        if unavailable > 0 { return unavailable == 1 ? "1 card needs a price" : "\(unavailable) cards need prices" }
        if !give.isPresent, !receive.isPresent { return "Add cards or cash to compare" }
        guard give.isPresent, receive.isPresent else { return "Add both sides to compare" }
        guard let difference else { return "Trade total unavailable" }
        if difference.isZero { return "Even at estimated value" }
        let amount = difference.magnitude.formatted(locale: locale)
        return difference < .zero ? "You give \(amount) more" : "You receive \(amount) more"
    }

    @ViewBuilder
    private func sideSelector(give: Int, receive: Int) -> some View {
        let stacked = dynamicTypeSize >= .xxxLarge
        let picker = Picker("Cards to review", selection: $side) {
            Text(stacked ? "Give \(give)" : "You give · \(give)")
                .accessibilityLabel(give == 1 ? "You give 1 card" : "You give \(give) cards")
                .tag(TradeSide.give)
            Text(stacked ? "Receive \(receive)" : "You receive · \(receive)")
                .accessibilityLabel(receive == 1 ? "You receive 1 card" : "You receive \(receive) cards")
                .tag(TradeSide.receive)
        }
        .accessibilityIdentifier("trade-review-side")

        if stacked {
            picker.pickerStyle(.inline).labelsHidden()
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private func entryRow(_ entry: TradeEntry) -> some View {
        DisclosureGroup {
            quantityControl(entry)
            if case let .price(price) = entry.result.quote, let unitPrice = entry.unitPrice {
                VStack(alignment: .leading, spacing: 4) {
                    if entry.quantity > 1 {
                        let amount = unitPrice.doubleValue.formatted(
                            .currency(code: "USD").precision(.fractionLength(2...4)).locale(locale)
                        )
                        Text("\(amount) per card")
                    }
                    Text(price.source.label)
                    Text("As of \(price.effectiveAsOf.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            if let issue = entry.priceIssue {
                Text(issue).font(.footnote).foregroundStyle(.secondary)
            }
            if entry.canRetryPrice {
                Button("Retry price", systemImage: "arrow.clockwise") { model.retryTradeQuote(entry.id) }
                    .buttonStyle(.borderless)
            }
            Button(
                entry.side == .give ? "Move to cards you receive" : "Move to cards you give",
                systemImage: "arrow.left.arrow.right"
            ) {
                model.moveTradeEntry(entry.id)
            }
            .buttonStyle(.borderless)
            Button("Remove card", systemImage: "trash", role: .destructive) { model.removeTradeEntry(entry.id) }
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
                        Text(entry.identityText).font(.caption).foregroundStyle(.secondary)
                        if entry.quantity > 1 {
                            Text("\(entry.quantity) copies").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    entryPrice(entry, alignment: stacked ? .leading : .trailing)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("Remove", role: .destructive) { model.removeTradeEntry(entry.id) }
        }
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
                Text(unitPrice == nil ? "Checking price" : "Updating price")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if unitPrice == nil || entry.isLastKnown {
                Text(unitPrice == nil ? "Price unavailable" : "Last known")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

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
