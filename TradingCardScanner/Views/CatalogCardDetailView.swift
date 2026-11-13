import SwiftData
import SwiftUI

typealias CatalogCardSelection = @MainActor (CatalogCardDetails, CatalogCardSummary) -> Void

private struct CatalogCardSelectionKey: EnvironmentKey {
    static var defaultValue: CatalogCardSelection? { nil }
}

extension EnvironmentValues {
    var catalogCardSelection: CatalogCardSelection? {
        get { self[CatalogCardSelectionKey.self] }
        set { self[CatalogCardSelectionKey.self] = newValue }
    }
}

struct CatalogCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @Environment(\.catalogCardSelection) private var catalogCardSelection
    @Environment(\.cardGameRuntimes) private var runtimes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: CatalogCardSummary
    let catalog: any BrowseCatalogProviding

    @State private var details: CatalogCardDetails?
    @State private var error: CatalogFailurePresentation?
    @State private var isLoading = false
    @State private var finishOptions: [PhysicalVariant] = []
    @State private var showsFinishChoice = false
    @State private var pendingMutation: CollectionMutation?
    @State private var isWritePending = false
    @State private var undoTask: Task<Void, Never>?
    /// Kept separate from `error`, which replaces the whole page with a load
    /// failure. A failed add must not blank the card the user is looking at.
    @State private var addFailure: String?
    @State private var addAlertTitle = "Couldn't add card"
    /// Keyed by instrument, not a single slot. Cancelling the previous card's
    /// quote on each add meant adding two cards quickly left the first one
    /// unpriced until the next refresh — the request was already in flight and
    /// its answer was thrown away. Same rule the scanner already uses.
    @State private var fallbackQuoteTasks: [String: Task<Void, Never>] = [:]
    @State private var showsGradedPicker = false
    @State private var historyVariantID: String?
    @State private var mappedPrices: [String: PriceLookup] = [:]
    @State private var mappedPriceCheckFinished = false
    @State private var failedPriceVariantIDs: Set<String> = []
    @State private var priceRetryID = 0
    @State private var ownedPriceChecks: [String: OwnedPriceRetentionReason] = [:]
    /// The exact raw entry a − tap targets; the dialog chooses plain removal or
    /// a recorded sale/trade. Quantity is the value the user saw, so a write
    /// against a changed collection fails as stale instead of guessing.
    @State private var decrementTarget: CatalogOwnedEntryTarget?
    @State private var dispositionTarget: CollectionDispositionTarget?
    @State private var ownershipChange: CatalogOwnershipChange?
    @State private var ownershipChangeTask: Task<Void, Never>?
    /// Projection revision observed when a quantity write started. Controls
    /// stay locked until ownership republishes, so a quick second tap never
    /// computes its expected quantity from the pre-write snapshot.
    @State private var awaitingProjectionRevision: UInt?
    @State private var showsPriceSources = false
    /// One transport per presentation, so the graded picker shares the app's
    /// pacing and request ledger rather than keeping its own.
    private let marketTransport = JustTCGTransport.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let details { content(details) }
                else if isLoading {
                    initialOwnedPriceSection
                    ProgressView().padding(.top, 40)
                }
                else if let error {
                    initialOwnedPriceSection
                    ContentUnavailableView("Couldn't load this card", systemImage: error.icon, description: Text(error.message))
                    if let action = error.action {
                        Button(action) {
                            Task {
                                if error == .catalog { await catalog.refreshCatalogNow() }
                                await load()
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .onChange(of: details?.card.id) { _, _ in
#if DEBUG
                if OwnedPriceReviewView.isActive { proxy.scrollTo("catalog-market-prices", anchor: .top) }
#endif
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            addAlertTitle,
            isPresented: Binding(
                get: { addFailure != nil },
                set: { if !$0 { addFailure = nil } }
            ),
            presenting: addFailure
        ) { _ in
            Button("OK", role: .cancel) { addFailure = nil }
        } message: { detail in
            Text(detail)
        }
        .task { if details == nil { await load() } }
        .task(id: "\(details?.card.id ?? ""):\(priceRetryID)") { await loadMappedPrices() }
        .sheet(isPresented: $showsGradedPicker) {
            if let details {
                GradedVariantPickerView(
                    card: details.card,
                    setReleaseOrder: details.set.releaseOrder,
                    pokemonPrintRun: summary.pokemonPrintRun,
                    transport: marketTransport
                )
            }
        }
        .safeAreaInset(edge: .top) {
            if let change = ownershipChange {
                ownershipChangeBanner(change).contentWidthLimit(.standard)
            } else if let mutation = pendingMutation {
                addedBanner(mutation).contentWidthLimit(.standard)
            }
        }
        .sheet(item: $dispositionTarget) { target in
            // The existing sale/trade record: it reduces quantity through the
            // store and keeps the transaction in Collection Activity.
            CollectionDispositionSheet(target: target) { snapshot in
                lockQuantityUntilProjectionUpdates()
                let noun = snapshot.quantity == 1 ? "copy" : "copies"
                present(CatalogOwnershipChange(
                    message: "Recorded \(snapshot.quantity) \(noun) as \(target.kind == .traded ? "traded" : "sold")",
                    undo: nil))
            }
        }
        .onChange(of: projectionStore.revision) { _, _ in
            awaitingProjectionRevision = nil
        }
    }

    private func content(_ details: CatalogCardDetails) -> some View {
        let reviewedPrinting = PokemonDeltaReignCatalog.printing(for: summary)
        return VStack(spacing: 20) {
            CatalogArtworkView(
                thumbnailURL: summary.thumbnailURL,
                imageURL: reviewedPrinting == nil ? details.card.displayImageURL ?? summary.imageURL : reviewedPrinting?.imageURL,
                prefersFullSize: true,
                game: summary.game,
                setCode: summary.setCode,
                collectorNumber: summary.collectorNumber,
                limitlessArtworkAuthorized: summary.limitlessArtworkAuthorized,
                providerID: summary.providerID,
                providerSetID: summary.setID.providerID
            )
                .frame(maxHeight: 470)

            VStack(spacing: 14) {
                Text(details.card.name)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                CatalogCardFactChips(chips: factChips(details))
                NavigationLink {
                    CatalogSetCardsView(set: details.set, catalog: catalog)
                } label: {
                    CatalogCardSetRow(set: details.set, setName: details.card.setName)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View cards in this set")
                .accessibilityIdentifier("card-set-link")
            }

            treatmentSection(details.card)
            if let notice = details.catalogNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            if catalog.gameRegistry.supports(summary.game, .pricing),
               details.collectionWriteUnavailableReason == nil {
                priceSection(details.card)
            } else {
                Text(details.collectionWriteUnavailableReason == nil
                     ? "Pricing unavailable" : "Pricing unavailable for this printing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ownedSection(details.card)
            if catalog.gameRegistry.supports(summary.game, .pricing),
               details.collectionWriteUnavailableReason == nil {
                browsePriceHistorySection()
            }

            if let reason = details.collectionWriteUnavailableReason {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
            if let catalogCardSelection {
                Button {
                    catalogCardSelection(details, summary)
                } label: {
                    Label("Use This Card", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Resolve the saved scan using this catalog printing")
                .disabled(details.collectionWriteUnavailableReason != nil)
            } else {
                VStack(spacing: 12) {
                    // Raw copies are added from their price rows. This button
                    // remains only where no row can carry a quantity control.
                    if !showsInlineQuantityControls(details) {
                        Button { prepareAdd(details.card) } label: {
                            HStack(spacing: 10) {
                                if isWritePending { ProgressView().accessibilityLabel("Saving collection change") }
                                Label(
                                    summary.masterSetVariant.map { "Add \($0.label) Copy" } ?? "Add to Collection",
                                    systemImage: "plus.circle.fill"
                                )
                            }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .disabled(isWritePending || !catalog.gameRegistry.supports(summary.game, .collectionWrite)
                            || !PokemonVariantPolicy.allowsAcquisition(of: details.card, finish: summary.masterSetVariant,
                                printRun: summary.pokemonPrintRun)
                            || details.collectionWriteUnavailableReason != nil)
                    }

                    if catalog.gameRegistry.supports(summary.game, [.collectionWrite, .gradedPricing]) {
                        // A slab is a distinct object with a grade the user chooses.
                        Button { showsGradedPicker = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.primary)
                                Text("Add Graded Copy")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .appPillGlass(tint: Color.accentColor.opacity(0.22), fallbackTintOpacity: 1, interactive: true)
                        .disabled(isWritePending || details.collectionWriteUnavailableReason != nil)
                        .opacity(isWritePending || details.collectionWriteUnavailableReason != nil ? 0.5 : 1)
                    }
                }
                .confirmationDialog(
                    "Choose a finish",
                    isPresented: $showsFinishChoice,
                    titleVisibility: .visible
                ) {
                    ForEach(finishOptions) { variant in
                        Button(variant.label) { commit(ResolvedVariant(variant: variant, resolution: .userConfirmed)) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Add the physical version you own.")
                }
            }

            let marketplaceDestinations = TCGplayerLinkBuilder.destinations(for: details.card, summary: summary)
            if !marketplaceDestinations.isEmpty {
                VStack(spacing: 8) {
                    ForEach(marketplaceDestinations, id: \.url) { destination in
                        CardDetailMarketplaceButton(destination: destination)
                    }
                }
            }
        }
        .padding(20)
        .contentWidthLimit(.standard)
    }

    private func showsInlineQuantityControls(_ details: CatalogCardDetails) -> Bool {
        catalogCardSelection == nil
            && catalog.gameRegistry.supports(summary.game, [.pricing, .collectionWrite])
            && details.collectionWriteUnavailableReason == nil
            && !Self.priceVariants(for: details.card, summary: summary,
                ownedRows: ownership.matchingRows(for: summary)).isEmpty
    }

    private func factChips(_ details: CatalogCardDetails) -> [CatalogCardFactChip] {
        var chips: [CatalogCardFactChip] = [
            .init(id: "number", text: details.card.identifier, systemImage: "number",
                  tint: .secondary, accessibilityLabel: "Card number \(details.card.identifier)", monospaced: true)
        ]
        if let rarity = details.card.rarity, !rarity.isEmpty {
            let style = CatalogCardRarityStyle(rarity: rarity)
            chips.append(.init(id: "rarity", text: rarity.capitalized, systemImage: style.symbol,
                               tint: style.tint, accessibilityLabel: "Rarity \(rarity.capitalized)"))
        }
        if let printRun = summary.pokemonPrintRun {
            chips.append(.init(id: "print-run", text: printRun.label, systemImage: "rosette",
                               tint: .accentColor, accessibilityLabel: printRun.label))
        }
        if let variant = summary.masterSetVariant {
            chips.append(.init(id: "variant", text: variant.label, systemImage: "square.stack.3d.up.fill",
                               tint: .accentColor, accessibilityLabel: "Finish \(variant.label)"))
        }
        if let treatment = details.card.magicTreatmentDisplayLabel {
            chips.append(.init(id: "treatment", text: treatment, systemImage: "sparkles",
                               tint: .purple, accessibilityLabel: "Treatment: \(treatment)"))
        }
        return chips
    }

    /// The treatment itself is a header chip. Only diagnostics that need the
    /// user's attention keep a panel here.
    @ViewBuilder
    private func treatmentSection(_ card: IdentifiedCard) -> some View {
        if !card.magicTreatmentDiagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.magicTreatmentDiagnostics) { diagnostic in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(diagnostic.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(diagnostic.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// Raw copies are counted on their price rows. This lists only owned items
    /// no row accounts for: graded slabs, and any raw entry whose finish does
    /// not match a priced variant. Nothing owned may silently disappear.
    @ViewBuilder private func ownedSection(_ card: IdentifiedCard) -> some View {
        let rows = otherOwnedRows(card)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(rows.allSatisfy { $0.itemKind != .rawCard } ? "Graded copies" : "Other copies")
                    .font(.headline)
                ForEach(rows) { row in
                    HStack {
                        Label(row.ownedDisplayLabel,
                              systemImage: row.itemKind == .rawCard ? "rectangle.portrait" : "checkmark.seal.fill")
                            .symbolRenderingMode(.hierarchical)
                        Spacer()
                        Text("×\(row.quantity)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func otherOwnedRows(_ card: IdentifiedCard) -> [CatalogOwnershipCardSnapshot] {
        let rows = ownedRows(card)
        guard catalog.gameRegistry.supports(summary.game, .pricing),
              details?.collectionWriteUnavailableReason == nil else { return rows }
        let shown = Set(Self.priceVariants(for: card, summary: summary, ownedRows: ownership.matchingRows(for: summary))
            .flatMap { ownedPrice(for: $0).entries.map(\.collectionKey) })
        return rows.filter { !shown.contains($0.collectionKey) }
    }

    private var ownership: CatalogOwnershipIndex {
        projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
    }

    private func ownedPrice(for variant: PhysicalVariant) -> OwnedCatalogPrice {
        var slot = summary
        slot.masterSetVariant = variant
        return OwnedCatalogPrice(rows: ownership.matchingRows(for: slot))
    }

    static func priceVariants(for card: IdentifiedCard, summary: CatalogCardSummary,
                              ownedRows: [CatalogOwnershipCardSnapshot] = []) -> [PhysicalVariant] {
        var variants = summary.pokemonPrintRun == nil ? card.variantEvidence.catalogVariants
            : card.variantEvidence.excludingFirstEditionPseudoFinish().catalogVariants
        // Edition is already carried by the summary. Preserve the physical
        // finish when selecting owned records and requesting exact quotes.
        if summary.pokemonPrintRun == .firstEdition, variants.isEmpty {
            for row in ownedRows where row.itemKind == .rawCard {
                if let variant = row.variant, variant.id != PhysicalVariant.firstEdition.id,
                   !variants.contains(where: { $0.id == variant.id }) { variants.append(variant) }
            }
        }
        if let required = summary.masterSetVariant, !variants.contains(where: { $0.id == required.id }) {
            variants.append(required)
        }
        // An edition-only quote remains context when no physical finish is
        // known. It is never substituted for a known Holo or Normal slot.
        if variants.isEmpty, summary.pokemonPrintRun == .firstEdition { return [.firstEdition] }
        return variants
    }

    @ViewBuilder private var initialOwnedPriceSection: some View {
        let owned = OwnedCatalogPrice(rows: ownership.matchingRows(for: summary))
        if !owned.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved market price").font(.headline)
                priceValue(owned.display)
                if error != nil { Text("Couldn't check for a newer price just now").font(.caption) }
            }
            .padding(20)
        }
    }

    private func priceSection(_ card: IdentifiedCard) -> some View {
        let variants = Self.priceVariants(for: card, summary: summary,
            ownedRows: ownership.matchingRows(for: summary))
        let showsControls = details.map(showsInlineQuantityControls) ?? false
        let sources = priceSourceLabels(variants)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(showsControls ? "Prices & copies" : "Market prices").font(.headline)
                Spacer()
                Button {
                    showsPriceSources = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Price sources")
                .accessibilityIdentifier("catalog-price-sources")
                .popover(isPresented: $showsPriceSources) {
                    priceSourcesPopover(variants)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.bottom, 4)
            ForEach(Array(variants.enumerated()), id: \.element.id) { index, variant in
                if index > 0 { Divider().opacity(0.6) }
                variantPriceRow(variant, card: card, showsControls: showsControls)
            }
            if !sources.isEmpty {
                Text("Prices from \(sources.formatted(.list(type: .and)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            priceRetryButton.padding(.top, 8)
        }
        .id("catalog-market-prices")
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .confirmationDialog(
            decrementTarget.map { "Remove a \($0.variantLabel) copy?" } ?? "",
            isPresented: Binding(get: { decrementTarget != nil }, set: { if !$0 { decrementTarget = nil } }),
            titleVisibility: .visible,
            presenting: decrementTarget
        ) { target in
            Button(target.quantity == 1 ? "Remove from Collection" : "Remove 1 Copy", role: .destructive) {
                decrement(target)
            }
            Button("Record Sale or Trade…") {
                dispositionTarget = CollectionDispositionTarget(
                    collectionKey: target.collectionKey, treatments: target.treatments,
                    cardName: target.cardName, quantity: target.quantity, kind: .sold)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(target.quantity == 1
                 ? "This is your only \(target.variantLabel) copy."
                 : "You own \(target.quantity) \(target.variantLabel) copies.")
        }
    }

    private func priceDisplay(for variant: PhysicalVariant) -> PriceDisplay? {
        let owned = ownedPrice(for: variant)
        if !owned.entries.isEmpty { return owned.display }
        if case let .price(quote) = mappedPrices[variant.id] { return PriceDisplay(quote) }
        return nil
    }

    private func priceSourceLabels(_ variants: [PhysicalVariant]) -> [String] {
        var labels: [String] = []
        for variant in variants {
            if let label = priceDisplay(for: variant)?.source?.label, !labels.contains(label) { labels.append(label) }
        }
        return labels
    }

    /// Provenance stays one tap away for anyone who wants it, without putting
    /// check timestamps in front of every price.
    private func priceSourcesPopover(_ variants: [PhysicalVariant]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Price sources").font(.headline)
                ForEach(variants) { variant in
                    let display = priceDisplay(for: variant)
                    let checks = Array(Set(ownedPrice(for: variant).entries
                        .compactMap { ownedPriceChecks[$0.collectionKey]?.caption })).sorted()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(variant.label).font(.subheadline.weight(.semibold))
                        if let display, !display.detailAttribution.isEmpty {
                            priceAttribution(display)
                        } else {
                            Text("No price details yet").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(checks, id: \.self) {
                            Text($0).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .frame(minWidth: 280, maxWidth: 360, alignment: .leading)
        }
        .frame(maxHeight: 420)
    }

    private func variantPriceRow(_ variant: PhysicalVariant, card: IdentifiedCard, showsControls: Bool) -> some View {
        let owned = ownedPrice(for: variant)
        let quantity = owned.entries.reduce(0) { $0 + $1.quantity }
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                rowPrice(variant, owned: owned)
                if showsControls, owned.entries.count > 1 {
                    Text("Saved as \(owned.entries.count) entries · edit them in Collection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if showsControls {
                CatalogQuantityStepper(
                    quantity: quantity,
                    variantLabel: variant.label,
                    canIncrease: canAdd(variant, card: card) && quantity < CollectionQuantityLimits.maximum,
                    canDecrease: owned.entries.count == 1,
                    isUpdating: isQuantityLocked,
                    onIncrease: { add(variant, card: card) },
                    onDecrease: {
                        guard owned.entries.count == 1, let entry = owned.entries.first else { return }
                        decrementTarget = CatalogOwnedEntryTarget(
                            collectionKey: entry.collectionKey, treatments: entry.magicTreatmentIDsRaw,
                            quantity: entry.quantity, cardName: card.name, variantLabel: variant.label)
                    }
                )
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog-price-row-\(variant.id)")
    }

    @ViewBuilder
    private func rowPrice(_ variant: PhysicalVariant, owned: OwnedCatalogPrice) -> some View {
        if !owned.entries.isEmpty {
            priceValue(owned.display)
            if failedPriceVariantIDs.contains(variant.id) {
                Text("Couldn't check for a newer price").font(.caption).foregroundStyle(.secondary)
            }
        } else if case let .price(quote) = mappedPrices[variant.id] {
            priceValue(PriceDisplay(quote))
        } else if !mappedPriceCheckFinished {
            ProgressView().frame(height: 28)
        } else {
            Text(failedPriceVariantIDs.contains(variant.id) ? "Couldn't check price"
                : (mappedPrices[variant.id] == .unavailable(nil) ? "No price yet" : "No USD price"))
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minHeight: 28, alignment: .leading)
        }
    }

    @ViewBuilder private func priceValue(_ display: PriceDisplay) -> some View {
        if let amount = display.amount {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(amount.formatted(.currency(code: "USD")))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PortfolioPalette.value)
                if display.state() == .stale {
                    Label("Stale", systemImage: "clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Stale price")
                }
            }
        } else {
            Text(display.state() == .unavailable ? "No USD price" : "Not priced yet").foregroundStyle(.secondary)
        }
    }

    private func priceAttribution(_ display: PriceDisplay) -> some View {
        ForEach(display.detailAttribution, id: \.self) {
            Text($0).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Inline quantity

    private var isQuantityLocked: Bool { isWritePending || awaitingProjectionRevision != nil }

    /// A row names its finish, so a + on a finish the catalog lists is the
    /// user's explicit choice. Any other row (an edition-only slot) falls back
    /// to the resolver, which asks when the finish is ambiguous.
    private func directFinish(_ variant: PhysicalVariant, card: IdentifiedCard) -> Bool {
        if variant.id == summary.masterSetVariant?.id { return true }
        var evidence = card.variantEvidence
        if summary.pokemonPrintRun != nil { evidence = evidence.excludingFirstEditionPseudoFinish() }
        return evidence.catalogVariants.contains { $0.id == variant.id }
    }

    private func canAdd(_ variant: PhysicalVariant, card: IdentifiedCard) -> Bool {
        catalog.gameRegistry.supports(card.game, .collectionWrite)
            && PokemonVariantPolicy.allowsAcquisition(of: card,
                finish: directFinish(variant, card: card) ? variant : summary.masterSetVariant,
                printRun: summary.pokemonPrintRun)
    }

    private func add(_ variant: PhysicalVariant, card: IdentifiedCard) {
        guard !isQuantityLocked else { return }
        guard directFinish(variant, card: card) else {
            prepareAdd(card)
            return
        }
        guard catalog.gameRegistry.supports(card.game, .collectionWrite) else {
            addFailure = "Collection saving is not available for this game yet."
            return
        }
        guard PokemonVariantPolicy.allowsAcquisition(of: card, finish: variant, printRun: summary.pokemonPrintRun) else {
            addFailure = "Scan Stash couldn't verify this printing."
            return
        }
        commit(ResolvedVariant(variant: variant, resolution: .userConfirmed))
    }

    private func lockQuantityUntilProjectionUpdates() {
        let revision = projectionStore.revision
        awaitingProjectionRevision = revision
        // A write that changes nothing visible never republishes; don't leave
        // the controls locked forever waiting for it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if awaitingProjectionRevision == revision { awaitingProjectionRevision = nil }
        }
    }

    private func decrement(_ target: CatalogOwnedEntryTarget) {
        guard !isQuantityLocked else { return }
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isWritePending = true
        lockQuantityUntilProjectionUpdates()
        Task { @MainActor in
            defer { isWritePending = false }
            do {
                let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                let change: CatalogOwnershipChange
                if target.quantity <= 1 {
                    // The last copy goes through the store's removal, so history
                    // records it and the snapshot can restore it.
                    let snapshot = try await CollectionExclusiveWrites.retryingIfRequired {
                        try await writer.remove(collectionKey: target.collectionKey, treatments: target.treatments,
                            expectedCurrent: target.quantity, shouldContinue: shouldContinue)
                    }
                    change = CatalogOwnershipChange(message: "Removed from Collection", undo: .restore(snapshot))
                } else {
                    let saved = try await CollectionExclusiveWrites.retryingIfRequired {
                        try await writer.setQuantity(target.quantity - 1, collectionKey: target.collectionKey,
                            treatments: target.treatments, expectedCurrent: target.quantity,
                            shouldContinue: shouldContinue)
                    }
                    change = CatalogOwnershipChange(message: "Removed 1 \(target.variantLabel) copy",
                        undo: .setQuantity(collectionKey: target.collectionKey, treatments: target.treatments,
                                           restoreTo: target.quantity, expectedCurrent: saved))
                }
                guard generation.isCurrent(token) else { return }
                present(change)
            } catch is CancellationError {
                awaitingProjectionRevision = nil
            } catch {
                awaitingProjectionRevision = nil
                guard generation.isCurrent(token) else { return }
                addAlertTitle = "Couldn't update collection"
                if case CollectionStoreError.staleQuantity = error {
                    addFailure = "Your collection changed while this was saving. Check the quantity and try again."
                } else {
                    addFailure = error.localizedDescription
                }
            }
        }
    }

    private func present(_ change: CatalogOwnershipChange) {
        undoTask?.cancel()
        pendingMutation = nil
        ownershipChange = change
        ownershipChangeTask?.cancel()
        ownershipChangeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, ownershipChange?.id == change.id { ownershipChange = nil }
        }
    }

    private func undoOwnershipChange(_ change: CatalogOwnershipChange) {
        guard !isWritePending, ownershipChange?.id == change.id, let undo = change.undo else { return }
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        ownershipChangeTask?.cancel()
        isWritePending = true
        lockQuantityUntilProjectionUpdates()
        Task { @MainActor in
            defer { isWritePending = false }
            do {
                switch undo {
                case let .restore(snapshot):
                    let writer = await CollectionActivityWriter.makeBackground(modelContainer: container)
                    try await CollectionExclusiveWrites.retryingIfRequired {
                        try await writer.restore(snapshot: snapshot, shouldContinue: shouldContinue)
                    }
                case let .setQuantity(collectionKey, treatments, restoreTo, expectedCurrent):
                    let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                    _ = try await CollectionExclusiveWrites.retryingIfRequired {
                        try await writer.setQuantity(restoreTo, collectionKey: collectionKey, treatments: treatments,
                            expectedCurrent: expectedCurrent, shouldContinue: shouldContinue)
                    }
                }
                guard generation.isCurrent(token), ownershipChange?.id == change.id else { return }
                ownershipChange = nil
            } catch is CancellationError {
                awaitingProjectionRevision = nil
            } catch {
                awaitingProjectionRevision = nil
                guard generation.isCurrent(token), ownershipChange?.id == change.id else { return }
                addAlertTitle = "Couldn't undo change"
                addFailure = "The collection change could not be undone. \(error.localizedDescription)"
            }
        }
    }

    private func ownershipChangeBanner(_ change: CatalogOwnershipChange) -> some View {
        HStack {
            Label(change.message, systemImage: "checkmark.circle.fill")
                .font(dynamicTypeSize.isAccessibilitySize ? .subheadline : .body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if change.undo != nil {
                Button("Undo") { undoOwnershipChange(change) }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(isWritePending)
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func loadMappedPrices() async {
        guard let loadedDetails = details,
              catalog.gameRegistry.supports(loadedDetails.card.game, .pricing) else { return }
        let card = loadedDetails.card
        mappedPriceCheckFinished = false
        failedPriceVariantIDs = []
        let retryID = priceRetryID
        let generation = CollectionStorageGeneration.shared
        let token = generation.currentToken()
        let writer = await ScannerCollectionWriter.makeBackground(modelContainer: modelContext.container)
        for variant in Self.priceVariants(for: card, summary: summary,
            ownedRows: ownership.matchingRows(for: summary)) {
            do {
                let quote = try await catalog.price(for: summary, variant: variant)
                guard !Task.isCancelled, details?.card.id == card.id, priceRetryID == retryID else { return }
                mappedPrices[variant.id] = quote
                let treatments = MagicTreatmentKeyCodec.storedIDs(from: card.magicTreatments(for: variant))
                if let token {
                    let entries = ownedPrice(for: variant).reconcilableEntries(variant: variant, treatmentIDs: treatments)
                    for entry in entries {
                        let result = try await CollectionExclusiveWrites.retryingIfRequired {
                            try await writer.reconcileOwnedPrice(quote, collectionKey: entry.collectionKey,
                                shouldContinue: generation.continuation(for: token))
                        }
                        guard !Task.isCancelled, generation.isCurrent(token), priceRetryID == retryID else { return }
                        ownedPriceChecks[entry.collectionKey] = result.retainedReason
                    }
                    if !entries.isEmpty {
                        await projectionStore.rebuild(container: modelContext.container)
                    }
                }
            } catch PriceQuoteError.mappingUnavailable {
                guard !Task.isCancelled, details?.card.id == card.id, priceRetryID == retryID else { return }
                mappedPrices[variant.id] = .unavailable(nil)
                for entry in ownedPrice(for: variant).entries { ownedPriceChecks[entry.collectionKey] = .unavailable }
            } catch {
                guard !Task.isCancelled, details?.card.id == card.id, priceRetryID == retryID else { return }
                failedPriceVariantIDs.insert(variant.id)
            }
        }
        mappedPriceCheckFinished = true
    }

    @ViewBuilder private var priceRetryButton: some View {
        if mappedPriceCheckFinished && (!failedPriceVariantIDs.isEmpty || !ownedPriceChecks.isEmpty
            || mappedPrices.values.contains(where: { if case let .unavailable(source) = $0 { return source != nil }; return false })) {
            Button("Retry prices") {
                mappedPriceCheckFinished = false
                Task {
                    await catalog.resetPriceResolution(for: [summary.id])
                    priceRetryID += 1
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func browsePriceHistorySection() -> some View {
        if let details {
            let variants = details.card.variantEvidence.catalogVariants
            let variant = summary.masterSetVariant
                ?? variants.first(where: { $0.id == historyVariantID }) ?? variants.first
            let currentPrice = variant.map { variant in
                let owned = ownedPrice(for: variant)
                if !owned.entries.isEmpty { return owned.display }
                if case let .price(quote) = mappedPrices[variant.id] { return PriceDisplay(quote) }
                return PriceDisplay.unknown
            } ?? .unknown
            let picker: AnyView? = summary.masterSetVariant == nil && variants.count > 1
                ? AnyView(CatalogHistoryVariantPicker(
                    title: summary.game == .yuGiOh ? "History edition" : "History finish",
                    variants: variants,
                    selection: Binding(get: { variant?.id ?? "" }, set: { historyVariantID = $0 })))
                : nil
            CardMarketHistoryPanel(request: .init(card: details.card,
                variant: variant,
                printRun: summary.pokemonPrintRun), currentPrice: currentPrice, variantPicker: picker)
                .id(variant?.id ?? "unknown")
        }
    }

    private func prepareAdd(_ card: IdentifiedCard) {
        guard !isWritePending else { return }
        guard catalog.gameRegistry.supports(card.game, .collectionWrite) else {
            addFailure = "Collection saving is not available for this game yet."
            return
        }
        guard PokemonVariantPolicy.allowsAcquisition(of: card, finish: summary.masterSetVariant,
            printRun: summary.pokemonPrintRun) else {
            addFailure = "Scan Stash couldn't verify this printing."
            return
        }
        if let required = summary.masterSetVariant {
            commit(ResolvedVariant(variant: required, resolution: .userConfirmed))
            return
        }
        // Edition is carried by the virtual Browse set, so the finish question
        // must not ask about it again.
        var evidence = card.variantEvidence
        if summary.pokemonPrintRun != nil {
            evidence = evidence.excludingFirstEditionPseudoFinish()
        }
        switch VariantResolver.resolve(evidence) {
        case let .resolved(resolved): commit(resolved)
        case let .needsChoice(options, _):
            guard !options.isEmpty else {
                addFailure = "Scan Stash couldn't verify the finish for this card."
                return
            }
            finishOptions = options
            showsFinishChoice = true
        }
    }

    private func commit(_ resolved: ResolvedVariant) {
        guard !isWritePending else { return }
        guard catalog.gameRegistry.supports(summary.game, .collectionWrite) else {
            addFailure = "Collection saving is not available for this game yet."
            return
        }
        guard let details else { return }
        let container = modelContext.container
        let printRun = summary.pokemonPrintRun
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isWritePending = true
        lockQuantityUntilProjectionUpdates()
        Task { @MainActor in
            defer { isWritePending = false }
            do {
                let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
                let receipt = try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.addCatalog(details, resolved: resolved, pokemonPrintRun: printRun,
                        shouldContinue: shouldContinue)
                }
                guard generation.isCurrent(token) else { return }
                if !receipt.priceSaved {
                    addAlertTitle = "Added with price warning"
                    addFailure = "The card was added, but its price could not be saved. It will remain available for a later refresh."
                }
                queueFallbackPrice(for: details.card, variant: resolved.variant, pokemonPrintRun: printRun,
                    printingID: receipt.storageID, catalogLookup: receipt.catalogLookup,
                    collectionKey: receipt.mutation.collectionKey,
                    writer: writer, shouldContinue: shouldContinue)
                ownershipChangeTask?.cancel()
                ownershipChange = nil
                pendingMutation = receipt.mutation
                undoTask?.cancel()
                undoTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(6))
                    if !Task.isCancelled, pendingMutation == receipt.mutation { pendingMutation = nil }
                }
            } catch is CancellationError {
                awaitingProjectionRevision = nil
            } catch CatalogLookupError.staleCatalog where summary.game == .pokemon {
                awaitingProjectionRevision = nil
                guard generation.isCurrent(token) else { return }
                self.details = nil
                addAlertTitle = "Catalog updated"
                addFailure = "Choose the printing again to add it to your collection."
                await load()
            } catch {
                awaitingProjectionRevision = nil
                guard generation.isCurrent(token) else { return }
                addAlertTitle = "Couldn't add card"
                addFailure = error.localizedDescription
            }
        }
    }

    private func queueFallbackPrice(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?,
        printingID: String,
        catalogLookup: PriceLookup,
        collectionKey: String,
        writer: ScannerCollectionWriter,
        shouldContinue: @escaping StorageGenerationContinuation
    ) {
        if let service = runtimes?.makePriceQuoteService(), service.supportsStoredPrintingRefresh(for: card.game) {
            let key = PriceRecord.key(game: card.game, printingID: printingID, variantID: variant?.id)
            guard fallbackQuoteTasks[key] == nil else { return }
            fallbackQuoteTasks[key] = Task { @MainActor in
                defer { fallbackQuoteTasks[key] = nil }
                guard let quote = try? await service.refresh(card: card, variant: variant, pokemonPrintRun: nil),
                      !Task.isCancelled else { return }
                _ = try? await writer.storeCatalogPrice(quote, game: card.game, printingID: printingID,
                    variantID: variant?.id, collectionKey: collectionKey, shouldContinue: shouldContinue)
            }
            return
        }
        guard PriceFallbackQuoteResolver.needsFallback(
                  catalogLookup,
                  identifiedCatalogCard: true
              ),
              (PokemonTCGCSVMapping.byCardID[card.providerID] != nil
                  || PokemonReviewedMarketProduct.entry(cardID: card.providerID, variantID: variant?.id) != nil
                  || PriceVendorCredentials.hasKey) else { return }

        let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: card.magicTreatments(for: variant)
        )
        let key = PriceRecord.key(
            game: card.game,
            printingID: printingID,
            variantID: variant?.id,
            treatmentIDs: treatmentIDs
        )
        guard fallbackQuoteTasks[key] == nil else { return }

        let fallbackContext = ModelContext(writer.modelContainer)
        let resolver = PriceFallbackQuoteResolver(context: fallbackContext)
        fallbackQuoteTasks[key] = Task { @MainActor in
            defer { fallbackQuoteTasks[key] = nil }
            switch await resolver.resolve(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            ) {
            case let .lookup(quote):
                guard !Task.isCancelled else { return }
                let identityKey = ProductIdentity.key(
                    game: card.game,
                    printingID: printingID,
                    variantID: variant?.id,
                    treatmentIDs: treatmentIDs
                )
                let marketVariantID = ProductIdentityStore(context: fallbackContext)
                    .cachedVariantID(forKey: identityKey)
                _ = try? await writer.storeCatalogPrice(
                    quote,
                    game: card.game,
                    printingID: printingID,
                    variantID: variant?.id,
                    treatments: treatmentIDs,
                    marketVariantID: marketVariantID,
                    collectionKey: collectionKey,
                    shouldContinue: shouldContinue
                )
            case .failed:
                break
            }
        }
    }

    private func ownedRows(_ card: IdentifiedCard) -> [CatalogOwnershipCardSnapshot] {
        let ownership = projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
        return ownership.matchingRows(for: summary)
            .sorted { ($0.variantLabel ?? "") < ($1.variantLabel ?? "") }
    }

    private func addedBanner(_ mutation: CollectionMutation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Label("Added to Collection", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    undoButton(mutation)
                }
            } else {
                HStack {
                    Label("Added to Collection", systemImage: "checkmark.circle.fill")
                    Spacer()
                    undoButton(mutation)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func undoButton(_ mutation: CollectionMutation) -> some View {
        HStack {
            if isWritePending { ProgressView().accessibilityLabel("Saving collection change") }
            Button("Undo") { undoCatalogMutation(mutation) }
                .fontWeight(.semibold)
                .frame(minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(isWritePending)
        }
    }

    private func undoCatalogMutation(_ mutation: CollectionMutation) {
        guard !isWritePending, pendingMutation == mutation else { return }
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        undoTask?.cancel()
        isWritePending = true
        Task { @MainActor in
            defer { isWritePending = false }
            do {
                let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
                try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.undoCatalog(mutation, shouldContinue: shouldContinue)
                }
                guard generation.isCurrent(token), pendingMutation == mutation else { return }
                pendingMutation = nil
            } catch is CancellationError {
            } catch {
                guard generation.isCurrent(token), pendingMutation == mutation else { return }
                addAlertTitle = "Couldn't undo card"
                addFailure = "The local collection change could not be undone. \(error.localizedDescription)"
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        if details == nil, let installed = await catalog.installedDetails(for: summary) {
            guard !Task.isCancelled else { return }
            details = installed
        }
        do {
            let needsRefresh = OwnedCatalogPrice(rows: ownership.matchingRows(for: summary)).entries
                .contains { $0.selectedPrice.state() == .stale }
            let refreshed = try await catalog.details(for: summary, refreshingPrices: needsRefresh || priceRetryID > 0)
            guard !Task.isCancelled else { return }
            details = refreshed
        }
        catch is CancellationError { return }
        catch { self.error = CatalogFailurePresentation(error: error) }
    }
}

// MARK: - Catalog detail components

/// The single raw entry a − tap acts on, captured as the user saw it.
struct CatalogOwnedEntryTarget: Identifiable, Equatable {
    var id: String { collectionKey }
    let collectionKey: String
    let treatments: [String]
    let quantity: Int
    let cardName: String
    let variantLabel: String
}

/// A completed quantity change from this screen, with what Undo must invert.
struct CatalogOwnershipChange: Identifiable {
    enum Undo {
        /// The last copy was removed; restore the exact removed snapshot.
        case restore(RemovedCardSnapshot)
        /// A copy was removed from a stack; set it back if nothing else moved it.
        case setQuantity(collectionKey: String, treatments: [String], restoreTo: Int, expectedCurrent: Int)
    }

    let id = UUID()
    let message: String
    let undo: Undo?
}

struct CatalogCardFactChip: Identifiable {
    let id: String
    let text: String
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String
    var monospaced = false
}

/// Number, rarity, edition, finish and treatment as one row of capsules.
/// Wraps to a column when a long treatment or large text cannot fit.
struct CatalogCardFactChips: View {
    let chips: [CatalogCardFactChip]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipViews }
            VStack(spacing: 8) { chipViews }
        }
    }

    private var chipViews: some View {
        ForEach(chips) { chip in
            Label {
                Text(chip.text)
                    .monospacedDigit()
                    .fontDesign(chip.monospaced ? .rounded : nil)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: chip.systemImage)
                    .imageScale(.small)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(chip.tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(chip.tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(chip.tint.opacity(0.28), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chip.accessibilityLabel)
        }
    }
}

/// Rarity names differ by game, so this matches on words rather than an
/// exhaustive table. Unknown rarities fall back to a neutral chip.
struct CatalogCardRarityStyle {
    let symbol: String
    let tint: Color

    init(rarity: String) {
        let value = rarity.lowercased()
        func has(_ words: String...) -> Bool { words.contains { value.contains($0) } }
        if has("mythic", "secret", "hyper", "special illustration", "starlight", "enchanted", "manga", "gold") {
            symbol = "sparkles"; tint = Color(red: 0.96, green: 0.52, blue: 0.24)
        } else if has("ultra", "illustration", "legendary", "double rare", "super", "epic", "ace") {
            symbol = "star.circle.fill"; tint = Color(red: 0.70, green: 0.55, blue: 0.98)
        } else if has("uncommon") {
            symbol = "diamond.fill"; tint = Color(red: 0.55, green: 0.70, blue: 0.82)
        } else if has("common") {
            symbol = "circle.fill"; tint = .secondary
        } else if has("rare", "holo") {
            symbol = "star.fill"; tint = Color(red: 0.90, green: 0.70, blue: 0.28)
        } else {
            symbol = "seal.fill"; tint = .secondary
        }
    }
}

/// The set is a destination, so it is drawn as one: a full-width row with the
/// set's symbol, a "browse" affordance, and a chevron.
struct CatalogCardSetRow: View {
    let set: CatalogSet
    let setName: String

    var body: some View {
        HStack(spacing: 14) {
            symbol
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(setName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(set.cardCount.map { $0 == 1 ? "Browse 1 card" : "Browse all \($0) cards" } ?? "Browse this set")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Set, \(setName)")
    }

    private var placeholder: some View {
        Image(systemName: "square.stack.3d.up.fill")
            .font(.title3)
            .foregroundStyle(Color.accentColor)
    }

    /// Scryfall symbols are SVG, which the raster loader cannot draw; Magic
    /// keeps the placeholder rather than a broken image.
    @ViewBuilder private var symbol: some View {
        if set.game != .magic, let url = set.symbolURL ?? set.logoURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().padding(7)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }
}

/// Owned quantity for one finish. With none owned it is a single + button;
/// with copies it becomes − n +.
struct CatalogQuantityStepper: View {
    let quantity: Int
    let variantLabel: String
    let canIncrease: Bool
    let canDecrease: Bool
    let isUpdating: Bool
    let onIncrease: () -> Void
    let onDecrease: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if quantity > 0 {
                Button(action: onDecrease) {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canDecrease || isUpdating)
                .accessibilityLabel("Remove a \(variantLabel) copy")

                Text("\(quantity)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 20)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(quantity) \(variantLabel) owned")
            }
            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canIncrease || isUpdating)
            .accessibilityLabel(quantity == 0 ? "Add a \(variantLabel) copy" : "Add another \(variantLabel) copy")
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.borderless)
        .foregroundStyle(quantity > 0 ? Color.primary : Color.accentColor)
        .background(quantity > 0 ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(quantity > 0 ? 0.5 : 0.25), lineWidth: 1))
        .opacity(isUpdating ? 0.6 : 1)
        .animation(.snappy(duration: 0.2), value: quantity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog-quantity-\(variantLabel)")
    }
}

/// Segmented when the finishes fit; a scrolling row of capsules for long
/// lists or accessibility text sizes, where segments would truncate.
struct CatalogHistoryVariantPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let variants: [PhysicalVariant]
    @Binding var selection: String

    var body: some View {
        if variants.count <= 4, !dynamicTypeSize.isAccessibilitySize {
            Picker(title, selection: $selection) {
                ForEach(variants) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("catalog-history-variant-picker")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(variants) { variant in
                        let isSelected = variant.id == selection
                        Button { selection = variant.id } label: {
                            Text(variant.label)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityIdentifier("catalog-history-variant-picker")
        }
    }
}

#if DEBUG
/// In-memory fixtures for repeatable screenshots of the production surfaces.
/// The catalog quote intentionally disagrees with the initial saved valuation.
struct OwnedPriceReviewView: View {
    @StateObject private var projection = CollectionProjectionStore()
    @StateObject private var completions = CatalogSetCompletionStore()
    @StateObject private var history = PortfolioHistoryStore()
    @State private var fixture: OwnedPriceReviewFixture?
    @State private var failure: String?

    static var isActive: Bool { argument("-ui_debug_route") == "OwnedPriceReview" }
    private static func argument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    var body: some View {
        NavigationStack {
            if let fixture, let snapshot = projection.snapshot {
                if fixture.state.contains("collection") {
                    CollectionCardDetailView(card: fixture.row, price: snapshot.rows.first?.price ?? .unknown,
                        history: history, unpricedReason: nil, artworkReason: nil,
                        instrumentKey: snapshot.rows.first?.priceStorageKey,
                        onRemoved: { _ in })
                        .modelContainer(fixture.container)
                } else if fixture.state.contains("grid") {
                    CatalogSetCardsView(set: fixture.details.set, catalog: fixture.catalog)
                        .modelContainer(fixture.container)
                } else {
                    CatalogCardDetailView(summary: fixture.summary, catalog: fixture.catalog)
                        .modelContainer(fixture.container)
                }
            } else if let failure { Text(failure) }
            else { ProgressView() }
        }
        .environmentObject(projection)
        .environmentObject(completions)
        .environment(\.cardGameRuntimes, nil)
        .environment(\.sharedBrowseCatalog, nil)
        .task {
            guard fixture == nil else { return }
            do {
                let loaded = try OwnedPriceReviewFixture(state: Self.argument("-ui_debug_state") ?? "native-newer-catalog")
                if !loaded.state.contains("catalog") {
                    let writer = await ScannerCollectionWriter.makeBackground(modelContainer: loaded.container)
                    _ = try await writer.reconcileOwnedPrice(loaded.quote, collectionKey: loaded.row.collectionKey, shouldContinue: { true })
                }
                await projection.rebuild(container: loaded.container)
                fixture = loaded
            } catch { failure = error.localizedDescription }
        }
    }
}

@MainActor
private struct OwnedPriceReviewFixture {
    let state: String
    let container: ModelContainer
    let row: CollectedCard
    let summary: CatalogCardSummary
    let details: CatalogCardDetails
    let quote: PriceLookup
    let catalog: OwnedPriceReviewCatalog

    init(state: String) throws {
        self.state = state
        container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"""
        {"id":"fixture-001","localId":"001","name":"Price consistency fixture",
         "set":{"id":"fixture","name":"Pricing review","cardCount":{"total":1,"official":1}},
         "variants":{"firstEdition":false,"normal":false,"holo":true,"reverse":false}}
        """#.utf8))
        let identified = IdentifiedCard.pokemon(card, setCode: "FIX")
        let printRun: PokemonPrintRun? = state.contains("first-edition") ? .firstEdition : nil
        let set = CatalogSet(catalogID: CatalogSetID(game: .pokemon, providerID: "fixture", pokemonPrintRun: printRun),
            name: "Pricing review", code: "FIX", logoURL: nil, symbolURL: nil,
            cardCount: 1, releaseDate: nil, sortRank: 0)
        summary = CatalogCardSummary(game: .pokemon, providerID: card.id, setID: set.catalogID,
            setName: set.name, setCode: "FIX", name: card.name, collectorNumber: "001", thumbnailURL: nil,
            imageURL: nil, masterSetVariant: .holo, isSoleSlotForCard: true)
        details = CatalogCardDetails(card: identified, set: set)
        let legacy = state.contains("legacy")
        row = CollectedCard(collectionKey: legacy ? "pokemon:csv:fixture:holo" : "pokemon:fixture-001:holo",
            game: .pokemon, providerID: legacy ? "csv:fixture" : card.id, name: card.name, setName: set.name,
            setCode: "FIX", cardNumber: "001", rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: .holo, variantResolution: .userConfirmed)
        row.catalogProviderID = card.id
        row.pokemonPrintRunRaw = printRun?.rawValue
        container.mainContext.insert(row)
        let date = Date(timeIntervalSince1970: 1_793_469_600) // 2026-10-31 18:00 UTC
        let prices = PriceStore(context: container.mainContext)
        _ = prices.store(.price(.init(unitMarketPriceUSD: 713.30, currencyCode: "USD", source: .justTCG,
            sourceVariantID: "saved", sourceUpdatedAt: date, fetchedAt: date)), game: .pokemon,
            printingID: printRun.map { "\(card.id)@\($0.rawValue)" } ?? card.id, variantID: "holo", at: date)
        guard prices.save() else { throw PriceStore.CheckpointWriteError() }
        quote = state.contains("unavailable") ? .unavailable(.tcgplayer) : .price(.init(unitMarketPriceUSD: 816.38,
            currencyCode: "USD", source: .tcgplayer, sourceVariantID: "holofoil",
            sourceUpdatedAt: state.contains("undated") ? nil : date.addingTimeInterval(state.contains("newer") ? -86400 : 169200),
            fetchedAt: .now))
        catalog = OwnedPriceReviewCatalog(summary: summary, details: details, quote: quote, fails: state.contains("failure"))
    }
}

private struct OwnedPriceReviewCatalog: BrowseCatalogProviding {
    let summary: CatalogCardSummary
    let details: CatalogCardDetails
    let quote: PriceLookup
    let fails: Bool
    func sets(for game: CardGame) async throws -> [CatalogSet] { [details.set] }
    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [summary], nextCursor: nil)
    }
    func searchCards(named query: String, game: CardGame, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [summary], nextCursor: nil)
    }
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails { details }
    func price(for summary: CatalogCardSummary, variant: PhysicalVariant) async throws -> PriceLookup {
        if fails { throw URLError(.notConnectedToInternet) }
        return quote
    }
    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        AsyncStream { $0.yield([summary.id: 816.38]); $0.finish() }
    }
}

private enum MagicTreatmentSlice4Fixture {
    static let card: ScryfallCard = {
        let json = """
        {
          "id": "cb82d614-13d8-40ec-9213-8e6852d37c9c",
          "name": "Auron, Venerated Guardian",
          "set": "fic",
          "set_name": "Final Fantasy Commander",
          "collector_number": "10",
          "lang": "en",
          "digital": false,
          "layout": "normal",
          "rarity": "rare",
          "released_at": "2025-06-13",
          "finishes": ["foil", "nonfoil"],
          "frame_effects": ["legendary"],
          "promo_types": ["ffx", "surgefoil", "universesbeyond"]
        }
        """
        return try! JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
    }()

    static let set = CatalogSet(
        catalogID: CatalogSetID(game: .magic, providerID: "fic"),
        name: card.setName,
        code: card.setCode.uppercased(),
        logoURL: nil,
        symbolURL: nil,
        cardCount: 106,
        releaseDate: Date(timeIntervalSince1970: 1_749_772_800),
        sortRank: 0
    )

    static let summary = CatalogCardSummary(
        game: .magic,
        providerID: card.id,
        setID: set.catalogID,
        setName: card.setName,
        setCode: card.setCode.uppercased(),
        name: card.name,
        collectorNumber: card.collectorNumber,
        thumbnailURL: nil,
        imageURL: nil
    )

    static let receipt = ScanReceipt(
        scanID: UUID(),
        name: card.name,
        identifier: "FIC 10",
        variantLabel: IdentifiedCard.magic(card)
            .finishAndTreatmentDisplayLabel(for: .foil),
        treatmentDiagnostics: [],
        thumbnailURL: nil
    )
}

private actor MagicTreatmentSlice4DebugCatalog: BrowseCatalogProviding {
    static let shared = MagicTreatmentSlice4DebugCatalog()

    func sets(for game: CardGame) async throws -> [CatalogSet] {
        game == .magic ? [MagicTreatmentSlice4Fixture.set] : []
    }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [MagicTreatmentSlice4Fixture.summary], nextCursor: nil)
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [MagicTreatmentSlice4Fixture.summary], nextCursor: nil)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        CatalogCardDetails(
            card: .magic(MagicTreatmentSlice4Fixture.card),
            set: MagicTreatmentSlice4Fixture.set
        )
    }

    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        AsyncStream { continuation in continuation.finish() }
    }
}

/// DEBUG-only deterministic surface for Slice 4 visual QA. It reuses the
/// production receipt and catalog-detail views with a local exact-printing
/// dual-finish fixture, so the screenshot proves that a selected foil can show
/// the composed label while browse detail does not silently choose foil.
struct MagicTreatmentSlice4DebugView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Magic treatment")
                        .font(.largeTitle.bold())

                    Text("Scan receipt")
                        .font(.headline)
                    ScanReceiptCard(
                        receipt: MagicTreatmentSlice4Fixture.receipt,
                        onUndo: {},
                        onOpen: {}
                    )

                    Text("Catalog card detail")
                        .font(.headline)
                    CatalogCardDetailView(
                        summary: MagicTreatmentSlice4Fixture.summary,
                        catalog: MagicTreatmentSlice4DebugCatalog.shared
                    )
                        .frame(height: 680)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                }
                .padding(20)
                .contentWidthLimit(.standard)
            }
            .navigationTitle("Treatment QA")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
