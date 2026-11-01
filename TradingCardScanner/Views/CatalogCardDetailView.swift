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
    /// One transport per presentation, so the graded picker shares the app's
    /// pacing and request ledger rather than keeping its own.
    private let marketTransport = JustTCGTransport.shared

    var body: some View {
        ScrollView {
            if let details { content(details) }
            else if isLoading { ProgressView().padding(.top, 100) }
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
        .safeAreaInset(edge: .bottom) {
            if let mutation = pendingMutation {
                addedBanner(mutation).contentWidthLimit(.standard)
            }
        }
    }

    private func content(_ details: CatalogCardDetails) -> some View {
        VStack(spacing: 20) {
            CatalogArtworkView(
                thumbnailURL: summary.thumbnailURL,
                imageURL: details.card.displayImageURL ?? summary.imageURL,
                prefersFullSize: true,
                game: summary.game,
                setCode: summary.setCode,
                collectorNumber: summary.collectorNumber,
                limitlessArtworkAuthorized: summary.limitlessArtworkAuthorized,
                providerID: summary.providerID,
                providerSetID: summary.setID.providerID
            )
                .frame(maxHeight: 470)

            VStack(spacing: 6) {
                Text(details.card.name).font(.title2.bold()).multilineTextAlignment(.center)
                NavigationLink {
                    CatalogSetCardsView(set: details.set, catalog: catalog)
                } label: {
                    Text(details.card.setName)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityHint("View cards in this set")
                .accessibilityIdentifier("card-set-link")
                if let printRun = summary.pokemonPrintRun {
                    Text(printRun.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                if let variant = summary.masterSetVariant {
                    Label(variant.label, systemImage: "square.stack.3d.up.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Text(details.card.identifier).font(.headline.monospacedDigit())
                if let rarity = details.card.rarity { Text(rarity.capitalized).font(.subheadline).foregroundStyle(.secondary) }
            }

            treatmentSection(details.card)
            if let notice = details.catalogNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            ownedSection(details.card)
            if catalog.gameRegistry.supports(summary.game, .pricing),
               details.collectionWriteUnavailableReason == nil {
                priceSection(details.card)
                browsePriceHistorySection()
            } else {
                Text(details.collectionWriteUnavailableReason == nil
                     ? "Pricing unavailable" : "Pricing unavailable for this printing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let url = TCGplayerLinkBuilder.url(
                for: details.card,
                variant: summary.masterSetVariant,
                pokemonPrintRun: summary.pokemonPrintRun
            ) {
                CardDetailMarketplaceButton(url: url)
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
                Button { prepareAdd(details.card) } label: {
                    HStack {
                        if isWritePending { ProgressView().accessibilityLabel("Saving collection change") }
                        Label(
                            summary.masterSetVariant.map { "Add \($0.label) Copy" } ?? "Add Raw Copy",
                            systemImage: "plus.circle.fill"
                        )
                    }
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
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
                .disabled(isWritePending || !catalog.gameRegistry.supports(summary.game, .collectionWrite)
                    || details.collectionWriteUnavailableReason != nil)

                if catalog.gameRegistry.supports(summary.game, [.collectionWrite, .gradedPricing]) {
                    // A slab is a distinct object with a grade the user chooses.
                    Button { showsGradedPicker = true } label: {
                        Label("Add Graded Copy", systemImage: "seal")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWritePending)
                }
            }
        }
        .padding(20)
        .contentWidthLimit(.standard)
    }

    @ViewBuilder
    private func treatmentSection(_ card: IdentifiedCard) -> some View {
        if let label = card.magicTreatmentDisplayLabel {
            VStack(alignment: .leading, spacing: 8) {
                Label("Treatment", systemImage: "sparkles")
                    .font(.headline)

                Text(label)
                    .font(.body.weight(.semibold))
                    .accessibilityLabel("Treatment: \(label)")

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
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private func ownedSection(_ card: IdentifiedCard) -> some View {
        let rows = ownedRows(card)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Owned").font(.headline)
                ForEach(rows) { row in
                    LabeledContent(row.ownedDisplayLabel, value: "\(row.quantity)")
                        .accessibilityLabel("\(row.ownedDisplayLabel), \(row.quantity) owned")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private func priceSection(_ card: IdentifiedCard) -> some View {
        if let service = runtimes?.makePriceQuoteService(), service.supportsStoredPrintingRefresh(for: card.game) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Published market prices").font(.headline)
                ForEach(card.variantEvidence.catalogVariants) { variant in
                    LabeledContent(variant.label) {
                        if case let .price(price) = mappedPrices[variant.id] {
                            VStack(alignment: .trailing) {
                                Text(price.unitMarketPriceUSD.formatted(.currency(code: "USD")))
                                Text(price.fetchedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if !mappedPriceCheckFinished { ProgressView() }
                        else if failedPriceVariantIDs.contains(variant.id) {
                            Text("Couldn't check price").foregroundStyle(.secondary)
                        } else if mappedPrices[variant.id] == .unavailable(nil) {
                            Text("No price yet").foregroundStyle(.secondary)
                        } else { Text("No USD price").foregroundStyle(.secondary) }
                    }
                }
                Text("TCGplayer via TCGCSV · aggregate market price")
                    .font(.caption).foregroundStyle(.secondary)
                priceRetryButton
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        } else {
        let rows = CardPricing.publishedPrices(for: card,
                                              pokemonPrintRun: summary.pokemonPrintRun,
                                              at: details?.retrievedAt ?? .now)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Published market prices").font(.headline)
                if let details {
                    Text("Retrieved \(details.retrievedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { price in
                    if let variantID = price.variantID, case let .price(quote) = mappedPrices[variantID], quote.currencyCode == "USD" {
                        VStack(alignment: .leading, spacing: 3) {
                            LabeledContent(price.label, value: quote.unitMarketPriceUSD.formatted(.currency(code: "USD")))
                            Text("\(quote.source.label) · retrieved \(quote.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let variantID = price.variantID, mappedPrices[variantID] != nil {
                        LabeledContent(price.label) {
                            Text("No USD price").foregroundStyle(.secondary)
                        }
                    } else {
                        switch price.availability {
                        case let .published(amount):
                            LabeledContent(price.label, value: amount.formatted(.currency(code: "USD")))
                        case .noUSDQuote:
                            LabeledContent(price.label) {
                                if !mappedPriceCheckFinished { ProgressView() }
                                else {
                                    Text(failedPriceVariantIDs.contains(price.variantID ?? "") ? "Couldn't check price" : "No USD price")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                priceRetryButton
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        } else if let printRun = summary.pokemonPrintRun {
            Text("No published USD price for \(printRun.label).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        }
    }

    private func loadMappedPrices() async {
        guard let loadedDetails = details,
              catalog.gameRegistry.supports(loadedDetails.card.game, .pricing) else { return }
        let card = loadedDetails.card
        mappedPriceCheckFinished = false
        failedPriceVariantIDs = []
        let retryID = priceRetryID
        for variant in card.variantEvidence.catalogVariants {
            do {
                let quote = try await catalog.price(for: summary, variant: variant)
                guard !Task.isCancelled, details?.card.id == card.id, priceRetryID == retryID else { return }
                mappedPrices[variant.id] = quote
            } catch PriceQuoteError.mappingUnavailable {
                guard !Task.isCancelled, details?.card.id == card.id, priceRetryID == retryID else { return }
                mappedPrices[variant.id] = .unavailable(nil)
            } catch {
                guard !Task.isCancelled, details?.card.id == card.id, priceRetryID == retryID else { return }
                failedPriceVariantIDs.insert(variant.id)
            }
        }
        mappedPriceCheckFinished = true
    }

    @ViewBuilder private var priceRetryButton: some View {
        if mappedPriceCheckFinished && (!failedPriceVariantIDs.isEmpty
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
            if summary.masterSetVariant == nil, variants.count > 1 {
                Picker(summary.game == .yuGiOh ? "History edition" : "History finish", selection: Binding(
                    get: { variant?.id ?? "" }, set: { historyVariantID = $0 }
                )) {
                    ForEach(variants) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
            }
            CardMarketHistoryPanel(request: .init(card: details.card,
                variant: variant,
                printRun: summary.pokemonPrintRun))
                .id(variant?.id ?? "unknown")
        }
    }

    private func prepareAdd(_ card: IdentifiedCard) {
        guard !isWritePending else { return }
        guard catalog.gameRegistry.supports(card.game, .collectionWrite) else {
            addFailure = "Collection saving is not available for this game yet."
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
                    writer: writer, shouldContinue: shouldContinue)
                pendingMutation = receipt.mutation
                undoTask?.cancel()
                undoTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(6))
                    if !Task.isCancelled, pendingMutation == receipt.mutation { pendingMutation = nil }
                }
            } catch is CancellationError {
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
                    variantID: variant?.id, shouldContinue: shouldContinue)
            }
            return
        }
        guard PriceFallbackQuoteResolver.needsFallback(
                  catalogLookup,
                  identifiedCatalogCard: true
              ),
              (PokemonTCGCSVMapping.byCardID[card.providerID] != nil
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
        HStack {
            Label("Added to Collection", systemImage: "checkmark.circle.fill")
            Spacer()
            if isWritePending { ProgressView().accessibilityLabel("Saving collection change") }
            Button("Undo") {
                undoCatalogMutation(mutation)
            }
            .fontWeight(.semibold)
            .frame(minHeight: 44)
            .disabled(isWritePending)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
        do {
            details = try await catalog.details(for: summary)
        }
        catch is CancellationError { return }
        catch { self.error = CatalogFailurePresentation(error: error) }
    }
}

#if DEBUG
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
