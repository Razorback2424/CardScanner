import SwiftData
import SwiftUI

typealias CatalogCardSelection = @MainActor (CatalogCardDetails, CatalogCardSummary) -> Void

private struct CatalogCardSelectionKey: EnvironmentKey {
    static var defaultValue: CatalogCardSelection? { nil }
}

extension EnvironmentValues {
    @Entry var catalogCopyHistory: PortfolioHistoryStore? = nil

    var catalogCardSelection: CatalogCardSelection? {
        get { self[CatalogCardSelectionKey.self] }
        set { self[CatalogCardSelectionKey.self] = newValue }
    }
}

/// Search discovers catalog-issued summaries. Only exact printing and edition
/// identity can choose a result. The saved name is just a retrieval hint.
struct CatalogDetailLookup: Hashable {
    let game: CardGame
    let providerID: String
    let printRun: PokemonPrintRun?
    let name: String
    let setCode: String

    func summary(in catalog: any BrowseCatalogProviding, setIDs: Set<CatalogSetID> = []) async throws -> CatalogCardSummary? {
        let directory = try await catalog.sets(for: game)
        let candidateSets = directory.filter { set in
            set.pokemonPrintRun == printRun && (setIDs.isEmpty
                ? set.code.caseInsensitiveCompare(setCode) == .orderedSame
                    || set.physicalPrintingIDs?.contains(providerID) == true
                : setIDs.contains(set.catalogID))
        }
        let scope = candidateSets.isEmpty ? setIDs : Set(candidateSets.map(\.catalogID))
        for set in candidateSets {
            if let local = try await catalog.completeLocalCards(in: set),
               let exact = exactSummary(in: local) { return exact }
        }
        var cursor: String?
        var visited: Set<String> = []
        repeat {
            let page = try await catalog.searchCards(named: name, game: game, setIDs: scope, cursor: cursor)
            try Task.checkCancellation()
            if let exact = exactSummary(in: page.items) { return exact }
            cursor = page.nextCursor
        } while cursor.map({ visited.insert($0).inserted }) == true
        return nil
    }

    func exactSummary(in summaries: [CatalogCardSummary]) -> CatalogCardSummary? {
        let matches = summaries.filter {
            $0.game == game && $0.pokemonPrintRun == printRun
                && $0.providerID.caseInsensitiveCompare(providerID) == .orderedSame
        }
        guard let first = matches.first, matches.allSatisfy({ $0.setID == first.setID }) else { return nil }
        return first
    }

    func matches(_ details: CatalogCardDetails, summary: CatalogCardSummary) -> Bool {
        details.card.game == game && details.set.catalogID == summary.setID
            && details.card.providerID.caseInsensitiveCompare(providerID) == .orderedSame
    }
}

struct CollectionCatalogDestination<Fallback: View>: View {
    let lookup: CatalogDetailLookup
    let openingFinishID: String?
    let catalog: any BrowseCatalogProviding
    @ViewBuilder let fallback: () -> Fallback
    @State private var resolvedSummary: CatalogCardSummary?
    @State private var resolvedDetails: CatalogCardDetails?
    @State private var didResolve = false

    var body: some View {
        Group {
            if let resolvedSummary, let resolvedDetails {
                CatalogCardDetailView(summary: resolvedSummary, catalog: catalog,
                    openingFinishID: openingFinishID, initialDetails: resolvedDetails)
            } else if didResolve {
                fallback()
            } else {
                ProgressView("Loading card…")
            }
        }
        .task {
            guard !didResolve else { return }
            defer { if !Task.isCancelled { didResolve = true } }
            do {
                guard let summary = try await lookup.summary(in: catalog) else { return }
                let installed = await catalog.installedDetails(for: summary)
                let details: CatalogCardDetails
                if let installed, installed.collectionWriteUnavailableReason == nil {
                    details = installed
                } else {
                    details = try await catalog.details(for: summary)
                }
                try Task.checkCancellation()
                guard lookup.matches(details, summary: summary),
                      details.collectionWriteUnavailableReason == nil else { return }
                resolvedDetails = details
                resolvedSummary = summary
            } catch {
                // A saved copy remains usable while its catalog is unavailable.
            }
        }
    }
}

struct CatalogCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var projectionStore: CollectionProjectionStore
    @Environment(\.catalogCardSelection) private var catalogCardSelection
    @Environment(\.cardGameRuntimes) private var runtimes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.catalogCopyHistory) private var copyHistory
    private let originalSummary: CatalogCardSummary
    let catalog: any BrowseCatalogProviding
    private let openingFinishID: String?
    @State private var updatedSummary: CatalogCardSummary?
    private var summary: CatalogCardSummary { updatedSummary ?? originalSummary }

    @State private var details: CatalogCardDetails?
    @State private var loadedFullDetails = false
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
    @State private var needsCatalogResolution = false
    /// One transport per presentation, so the graded picker shares the app's
    /// pacing and request ledger rather than keeping its own.
    private let marketTransport = JustTCGTransport.shared

    init(summary: CatalogCardSummary, catalog: any BrowseCatalogProviding,
         openingFinishID: String? = nil, initialDetails: CatalogCardDetails? = nil) {
        originalSummary = summary
        self.catalog = catalog
        self.openingFinishID = openingFinishID ?? summary.masterSetVariant?.id
        _details = State(initialValue: initialDetails)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let details { content(details) }
                else if isLoading {
                    ProgressView().padding(.top, 40)
                }
                else if let error {
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
        .toolbar(.hidden, for: .tabBar)
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
        .task {
            let updates = await catalog.catalogUpdates()
            if needsCatalogResolution { await reloadCatalogIdentity() }
            else if !loadedFullDetails { await load() }
            for await update in updates {
                guard !Task.isCancelled else { return }
                guard update.affects(game: summary.game, providerSetID: summary.setID.providerID) else { continue }
                await reloadCatalogIdentity()
            }
        }
        .task(id: selectedQuoteRequest) {
            if let request = selectedQuoteRequest { await loadSelectedQuote(request) }
        }
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
            CollectionDispositionSheet(target: target) { snapshot, kind in
                isWritePending = true
                Task { @MainActor in
                    await projectionStore.rebuild(container: modelContext.container)
                    isWritePending = false
                }
                let noun = snapshot.quantity == 1 ? "copy" : "copies"
                present(CatalogOwnershipChange(
                    message: "Recorded \(snapshot.quantity) \(noun) as \(kind == .traded ? "traded" : "sold")",
                    undo: nil))
            }
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

            identityHeader(details)

            if !finishVariants(details.card).isEmpty {
                priceSection(details.card)
            }

            treatmentSection(details.card)
            if let notice = details.catalogNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            if needsCatalogResolution {
                Button("Retry catalog lookup") { Task { await reloadCatalogIdentity() } }
                    .disabled(isLoading)
            }
            if projectionStore.loadFailed, catalogCardSelection == nil {
                Button("Reload owned quantities") {
                    Task { await projectionStore.rebuild(container: modelContext.container) }
                }
                .disabled(isWritePending)
            }
            if catalog.gameRegistry.supports(summary.game, .pricing), !needsCatalogResolution,
               selectedVariant(details.card) != nil {
                browsePriceHistorySection()
            }
            if catalogCardSelection == nil {
                if let variant = selectedVariant(details.card) {
                    ForEach(ownedSlot(for: variant, card: details.card).targets) { target in
                        savedCopyLink(target.collectionKey, personalOnly: true)
                    }
                }
                ownedSection(details.card)
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
                        .disabled(isQuantityLocked || !catalog.gameRegistry.supports(summary.game, .collectionWrite)
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
                        .disabled(isQuantityLocked || details.collectionWriteUnavailableReason != nil)
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

            if !needsCatalogResolution,
               let destination = TCGplayerLinkBuilder.destination(for: details.card,
                    variant: selectedVariant(details.card), pokemonPrintRun: summary.pokemonPrintRun) {
                CardDetailMarketplaceButton(destination: destination)
            }
            DisclosureGroup("Printing details") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Set", value: details.set.name)
                    LabeledContent("Card number", value: summary.printedCollectorNumber ?? "Unnumbered")
                    if let rarity = CardRarityToken(raw: details.card.rarity) {
                        LabeledContent("Rarity", value: rarity.label)
                    }
                    if let run = summary.pokemonPrintRun {
                        LabeledContent("Print run", value: run.label)
                    }
                    let treatments = details.card.magicTreatments(for: selectedVariant(details.card))
                    if !treatments.isEmpty {
                        LabeledContent("Treatment", value: treatments.map(\.label).formatted(.list(type: .and)))
                    }
                }
                .font(.subheadline)
                .padding(.top, 8)
            }
        }
        .padding(20)
        .contentWidthLimit(.standard)
    }

    private func showsInlineQuantityControls(_ details: CatalogCardDetails) -> Bool {
        catalogCardSelection == nil
            && details.collectionWriteUnavailableReason == nil
            && !finishVariants(details.card).isEmpty
    }

    private func identityHeader(_ details: CatalogCardDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(details.card.name)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    setLink(details)
                    Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(summary.setAndCollectorLabel)
                }
                VStack(alignment: .leading, spacing: 0) {
                    setLink(details)
                    Text(summary.setAndCollectorLabel)
                }
            }
            .font(.subheadline.weight(.semibold))
            if let rarity = CardRarityToken(raw: details.card.rarity) {
                Text(rarity.label).font(.subheadline.weight(.semibold))
            }
            if let run = summary.pokemonPrintRun {
                Text(run.label).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setLink(_ details: CatalogCardDetails) -> some View {
        NavigationLink {
            CatalogSetCardsView(set: details.set, catalog: catalog)
        } label: {
            Text(details.set.name)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityHint("View cards in this set")
        .accessibilityIdentifier("card-set-link")
    }

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
                        Text("×\(projectionStore.snapshot?.rowsByCollectionKey[row.collectionKey]?.quantity ?? row.quantity)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    savedCopyLink(row.collectionKey, personalOnly: false)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func savedCopyLink(_ key: String, personalOnly: Bool) -> some View {
        if let copyHistory, let row = projectionStore.snapshot?.rowsByCollectionKey[key] {
            NavigationLink {
                CollectionCardDestination(row: row, unpricedReason: nil, artworkReason: nil,
                    isLogicalConflict: (projectionStore.snapshot?.physicalRowCountsByKey[key] ?? 0) > 1,
                    history: copyHistory, personalOnly: personalOnly,
                    onRemoved: { snapshot in
                        present(.init(message: "Removed from Collection", undo: .restore(snapshot)))
                    })
            } label: {
                Text("Saved copy details").frame(minHeight: 44)
            }
        }
    }

    private func otherOwnedRows(_ card: IdentifiedCard) -> [CatalogOwnershipCardSnapshot] {
        let rows = ownedRows
        let shown = Set(finishVariants(card).flatMap { ownedSlot(for: $0, card: card).price.entries.map(\.collectionKey) })
        return rows.filter { !shown.contains($0.collectionKey) }
    }

    private var ownership: CatalogOwnershipIndex {
        projectionStore.snapshot?.ownership ?? CatalogOwnershipIndex(rows: [])
    }

    private func finishVariants(_ card: IdentifiedCard) -> [PhysicalVariant] {
        // An edition-only price context is never an editable physical finish.
        Self.priceVariants(for: card, summary: summary).filter { $0.id != PhysicalVariant.firstEdition.id }
    }

    private func selectedVariant(_ card: IdentifiedCard) -> PhysicalVariant? {
        let variants = finishVariants(card)
        let preferred = historyVariantID ?? openingFinishID
        return variants.first { $0.id == preferred } ?? variants.first
    }

    private func ownedSlot(for variant: PhysicalVariant, card: IdentifiedCard) -> CatalogFinishOwnership {
        CatalogFinishOwnership(
            rows: ownership.exactPrintingRows(for: summary),
            variant: variant,
            treatments: MagicTreatmentKeyCodec.storedIDs(from: card.magicTreatments(for: variant)),
            qualifiers: card.magicTreatmentQualifiers(for: variant),
            name: card.name,
            projection: projectionStore.snapshot
        )
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

    private func priceSection(_ card: IdentifiedCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finishes").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(finishVariants(card)) { variant in
                variantPriceRow(variant, card: card)
            }
        }
        .id("catalog-market-prices")
        .confirmationDialog(
            decrementTarget.map { "Remove a \($0.variantLabel) copy?" } ?? "",
            isPresented: Binding(get: { decrementTarget != nil }, set: { if !$0 { decrementTarget = nil } }),
            titleVisibility: .visible,
            presenting: decrementTarget
        ) { target in
            Button(target.quantity == 1 ? "Remove from Collection" : "Remove 1 Copy", role: .destructive) {
                decrement(target)
            }
            .disabled(isQuantityLocked)
            Button("Record Sale or Trade…") {
                dispositionTarget = CollectionDispositionTarget(
                    collectionKey: target.collectionKey, treatments: target.treatments,
                    cardName: target.cardName, quantity: target.quantity, kind: .sold)
            }
            .disabled(isQuantityLocked)
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(target.quantity == 1
                 ? "This is your only \(target.variantLabel) copy."
                 : "You own \(target.quantity) \(target.variantLabel) copies.")
        }
    }

    private func variantPriceRow(_ variant: PhysicalVariant, card: IdentifiedCard) -> some View {
        let slot = ownedSlot(for: variant, card: card)
        let selected = selectedVariant(card)?.id == variant.id
        let showControls = details.map(showsInlineQuantityControls) ?? false
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        let shape = RoundedRectangle(cornerRadius: 14)
        return layout {
            Button { historyVariantID = variant.id } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(variant.label).font(.body.weight(.semibold))
                        if catalog.gameRegistry.supports(summary.game, .pricing), !needsCatalogResolution {
                            priceValue(priceDisplay(for: variant, card: card, slot: slot))
                        }
                        if slot.hasConflict {
                            Text("Saved copies need review").font(.caption).foregroundStyle(.secondary)
                        } else if slot.price.entriesDisagree {
                            Text("Saved prices differ").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if showControls, projectionStore.isLoaded, !projectionStore.loadFailed {
                VStack(alignment: .trailing, spacing: 0) {
                    CatalogQuantityStepper(
                        quantity: slot.quantity, variantLabel: variant.label,
                        canIncrease: canAdd(variant, card: card) && !slot.hasConflict
                            && slot.quantity < CollectionQuantityLimits.maximum,
                        canDecrease: slot.targets.count == 1 && !slot.hasConflict,
                        isUpdating: isQuantityLocked,
                        onIncrease: { add(variant, card: card) },
                        onDecrease: { decrementTarget = slot.targets.first }
                    )
                    if slot.targets.count > 1, !slot.hasConflict {
                        Menu("Manage copies") {
                            ForEach(slot.targets) { target in
                                Button("\(target.dateAdded.formatted(date: .abbreviated, time: .shortened)) · \(target.quantity) owned") {
                                    decrementTarget = target
                                }
                            }
                        }
                        .font(.caption)
                        .frame(minHeight: 44)
                        .disabled(isQuantityLocked)
                    }
                }
            } else if catalogCardSelection == nil, projectionStore.isLoaded, !projectionStore.loadFailed {
                Text("\(slot.quantity) owned").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06), in: shape)
        .overlay { shape.strokeBorder(selected ? Color.accentColor : .clear) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog-price-row-\(variant.id)")
    }

    private func priceDisplay(for variant: PhysicalVariant, card: IdentifiedCard, slot: CatalogFinishOwnership) -> PriceDisplay {
        if !slot.hasConflict, !slot.price.entriesDisagree,
           Set(slot.price.entries.map(\.selectedPriceKey)).count == 1 {
            return slot.price.display
        }
        let lookup = mappedPrices[variant.id] ?? CardPricing.price(for: card, variant: variant,
            magicTreatments: card.magicTreatments(for: variant), pokemonPrintRun: summary.pokemonPrintRun,
            at: details?.retrievedAt ?? .distantPast)
        if case let .price(quote) = lookup { return PriceDisplay(quote) }
        return .unknown
    }

    @ViewBuilder private func priceValue(_ display: PriceDisplay) -> some View {
        if let amount = display.amount {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(amount.formatted(.currency(code: display.currencyCode)))
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

    // MARK: - Inline quantity

    private var isQuantityLocked: Bool {
        isWritePending || needsCatalogResolution || !projectionStore.isLoaded || projectionStore.loadFailed
    }

    private func canAdd(_ variant: PhysicalVariant, card: IdentifiedCard) -> Bool {
        catalog.gameRegistry.supports(card.game, .collectionWrite)
            && (card.variantEvidence.physicalCoverageVerified || card.variantEvidence.explicitMembershipSupported
                || variant.id == summary.masterSetVariant?.id)
            && PokemonVariantPolicy.allowsAcquisition(of: card,
                finish: variant,
                printRun: summary.pokemonPrintRun)
    }

    private func add(_ variant: PhysicalVariant, card: IdentifiedCard) {
        guard !isQuantityLocked, canAdd(variant, card: card),
              !ownedSlot(for: variant, card: card).hasConflict else { return }
        commit(ResolvedVariant(variant: variant, resolution: .userConfirmed))
    }

    private func decrement(_ target: CatalogOwnedEntryTarget) {
        guard !isQuantityLocked else { return }
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isWritePending = true
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
                await projectionStore.rebuild(container: container)
                guard generation.isCurrent(token) else { return }
                present(change)
            } catch is CancellationError {
            } catch {
                guard generation.isCurrent(token) else { return }
                await projectionStore.rebuild(container: container)
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
                await projectionStore.rebuild(container: container)
                guard generation.isCurrent(token), ownershipChange?.id == change.id else { return }
                ownershipChange = nil
            } catch is CancellationError {
            } catch {
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

    private struct QuoteRequest: Hashable {
        let summary: CatalogCardSummary
        let variant: PhysicalVariant
        let retrievedAt: Date
        let retry: Int
    }

    private var selectedQuoteRequest: QuoteRequest? {
        guard !needsCatalogResolution, catalogCardSelection == nil,
              catalog.gameRegistry.supports(summary.game, .pricing), let details,
              let variant = selectedVariant(details.card) else { return nil }
        return QuoteRequest(summary: summary, variant: variant, retrievedAt: details.retrievedAt, retry: priceRetryID)
    }

    private func loadSelectedQuote(_ request: QuoteRequest) async {
        guard let card = details?.card, selectedQuoteRequest == request else { return }
        let generation = CollectionStorageGeneration.shared
        let token = generation.currentToken()
        let variant = request.variant
        failedPriceVariantIDs.remove(variant.id)
        do {
            let quote = try await catalog.price(for: request.summary, variant: variant)
            guard !Task.isCancelled, selectedQuoteRequest == request else { return }
            mappedPrices[variant.id] = quote
            guard let token, generation.isCurrent(token), !isWritePending else { return }
            let slot = ownedSlot(for: variant, card: card)
            guard !slot.hasConflict, !slot.targets.isEmpty else { return }
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: modelContext.container)
            for target in slot.targets {
                guard !Task.isCancelled, generation.isCurrent(token), selectedQuoteRequest == request else { return }
                let result = try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.reconcileOwnedPrice(quote, collectionKey: target.collectionKey,
                        shouldContinue: generation.continuation(for: token))
                }
                guard !Task.isCancelled, generation.isCurrent(token), selectedQuoteRequest == request else { return }
                ownedPriceChecks[target.collectionKey] = result.retainedReason
            }
            await projectionStore.rebuild(container: modelContext.container)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, selectedQuoteRequest == request else { return }
            failedPriceVariantIDs.insert(variant.id)
        }
    }

    @ViewBuilder
    private func browsePriceHistorySection() -> some View {
        if let details {
            let variant = selectedVariant(details.card)
            let slot = variant.map { ownedSlot(for: $0, card: details.card) }
            let currentPrice = variant.flatMap { finish in
                slot.map { priceDisplay(for: finish, card: details.card, slot: $0) }
            } ?? .unknown
            VStack(alignment: .leading, spacing: 6) {
                Text(variant.map { "\($0.label) market price" } ?? "Market price").font(.headline)
                priceValue(currentPrice)
                if let slot, projectionStore.isLoaded, !projectionStore.loadFailed, catalogCardSelection == nil {
                    let unit = PortfolioPriceEligibility.eligibleUnitPrice(
                        amount: currentPrice.amount, currencyCode: currentPrice.currencyCode)
                    let value: Money? = slot.hasConflict ? nil
                        : (slot.quantity == 0 ? .zero : unit?.multiplied(by: slot.quantity))
                    LabeledContent("Owned value", value: value?.formatted() ?? "Unavailable")
                        .font(.subheadline)
                }
                if let variant {
                    let notes = Set((slot?.targets ?? []).compactMap { ownedPriceChecks[$0.collectionKey]?.caption })
                    ForEach(notes.sorted(), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    if failedPriceVariantIDs.contains(variant.id) {
                        Button("Retry price check") { priceRetryID += 1 }.font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let request = CardMarketHistoryRequest(card: details.card, variant: variant, printRun: summary.pokemonPrintRun)
            CardMarketHistoryPanel(request: request, currentPrice: currentPrice.amount == nil ? nil : currentPrice)
                .id(request)
        }
    }

    private func prepareAdd(_ card: IdentifiedCard) {
        guard !isQuantityLocked else { return }
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
        guard !isQuantityLocked else { return }
        guard catalog.gameRegistry.supports(summary.game, .collectionWrite) else {
            addFailure = "Collection saving is not available for this game yet."
            return
        }
        guard let details, details.collectionWriteUnavailableReason == nil else { return }
        let container = modelContext.container
        let printRun = summary.pokemonPrintRun
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isWritePending = true
        Task { @MainActor in
            defer { isWritePending = false }
            do {
                let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
                let receipt = try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.addCatalog(details, resolved: resolved, pokemonPrintRun: printRun,
                        shouldContinue: shouldContinue)
                }
                guard generation.isCurrent(token) else { return }
                await projectionStore.rebuild(container: container)
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
            } catch CatalogLookupError.staleCatalog {
                guard generation.isCurrent(token) else { return }
                addAlertTitle = "Catalog updated"
                addFailure = "Choose the printing again to add it to your collection."
                await reloadCatalogIdentity()
            } catch {
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

    private var ownedRows: [CatalogOwnershipCardSnapshot] {
        let rows = ownership.exactPrintingRows(for: summary)
        var seen: Set<String> = []
        return rows.filter { seen.insert($0.collectionKey).inserted }
            .sorted { ($0.ownedDisplayLabel, $0.collectionKey) < ($1.ownedDisplayLabel, $1.collectionKey) }
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
                await projectionStore.rebuild(container: container)
                guard generation.isCurrent(token) else { return }
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
        guard !isLoading else { return }
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
            loadedFullDetails = true
        }
        catch is CancellationError { return }
        catch { self.error = CatalogFailurePresentation(error: error) }
    }

    private func reloadCatalogIdentity() async {
        guard !isLoading else { return }
        isLoading = true
        needsCatalogResolution = true
        decrementTarget = nil
        showsFinishChoice = false
        mappedPrices = [:]
        failedPriceVariantIDs = []
        ownedPriceChecks = [:]
        defer { isLoading = false }
        let lookup = CatalogDetailLookup(game: summary.game, providerID: summary.providerID,
            printRun: summary.pokemonPrintRun, name: summary.name, setCode: summary.setCode)
        do {
            guard let current = try await lookup.summary(in: catalog, setIDs: [summary.setID]) else { return }
            let refreshed = try await catalog.details(for: current)
            try Task.checkCancellation()
            guard lookup.matches(refreshed, summary: current) else { return }
            updatedSummary = current
            details = refreshed
            loadedFullDetails = true
            historyVariantID = selectedVariant(refreshed.card)?.id
            needsCatalogResolution = false
            priceRetryID += 1
        } catch {
            // Retain the last identity for display until it can be reverified.
        }
    }
}

// MARK: - Catalog detail components

struct CatalogFinishOwnership {
    let price: OwnedCatalogPrice
    let targets: [CatalogOwnedEntryTarget]
    let quantity: Int
    let hasConflict: Bool

    init(rows: [CatalogOwnershipCardSnapshot], variant: PhysicalVariant, treatments: [String],
         qualifiers: [String: String], name: String, projection: CollectionProjectionSnapshot?) {
        let treatmentSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: treatments))
        let matching = rows.filter { row in
            row.itemKind == .rawCard && row.variantID == variant.id
                && Set(MagicTreatmentKeyCodec.canonicalIDs(from: row.magicTreatmentIDsRaw)) == treatmentSet
                && row.magicTreatmentQualifiers.allSatisfy { key, value in qualifiers[key] == value }
        }
        price = OwnedCatalogPrice(rows: matching)
        let groups = Dictionary(grouping: matching, by: \.collectionKey)
        quantity = matching.reduce(0) { CollectionQuantityLimits.saturatingAdd($0, $1.quantity) }
        hasConflict = groups.contains { key, group in
            (projection?.physicalRowCountsByKey[key] ?? group.count) != group.count
                || Set(group.map(\.storedPriceKey)).count > 1
                || Set(group.map(\.selectedPriceKey)).count > 1
        }
        targets = groups.keys.sorted().compactMap { key in
            guard let row = projection?.rowsByCollectionKey[key] else { return nil }
            return CatalogOwnedEntryTarget(collectionKey: key, treatments: treatments,
                quantity: row.quantity, cardName: name, variantLabel: variant.label, dateAdded: row.dateAdded)
        }
    }
}

/// The single raw entry a − tap acts on, captured as the user saw it.
struct CatalogOwnedEntryTarget: Identifiable, Equatable {
    var id: String { collectionKey }
    let collectionKey: String
    let treatments: [String]
    let quantity: Int
    let cardName: String
    let variantLabel: String
    let dateAdded: Date
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

/// Owned quantity and two independent controls for one finish.
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
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(quantity == 0 || !canDecrease || isUpdating)
            .accessibilityLabel("Remove a \(variantLabel) copy")

            Text("\(quantity)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 20)
                .contentTransition(.numericText())
                .accessibilityLabel("\(quantity) \(variantLabel) owned")
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
