import SwiftData
import SwiftUI

struct CatalogCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var ownedCards: [CollectedCard]
    let summary: CatalogCardSummary
    let catalog: any BrowseCatalogProviding

    @State private var details: CatalogCardDetails?
    @State private var error: String?
    @State private var isLoading = false
    @State private var finishOptions: [PhysicalVariant] = []
    @State private var showsFinishChoice = false
    @State private var pendingMutation: CollectionMutation?
    @State private var undoTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            if let details { content(details) }
            else if isLoading { ProgressView().padding(.top, 100) }
            else if let error {
                ContentUnavailableView("Couldn't load this card", systemImage: "wifi.exclamationmark", description: Text(error))
                Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .task { if details == nil { await load() } }
        .confirmationDialog("Choose a finish", isPresented: $showsFinishChoice, titleVisibility: .visible) {
            ForEach(finishOptions) { variant in
                Button(variant.label) { commit(ResolvedVariant(variant: variant, resolution: .userConfirmed)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Add the physical version you own.") }
        .safeAreaInset(edge: .bottom) {
            if let mutation = pendingMutation { addedBanner(mutation) }
        }
    }

    private func content(_ details: CatalogCardDetails) -> some View {
        VStack(spacing: 20) {
            CatalogArtworkView(thumbnailURL: summary.thumbnailURL, imageURL: details.card.displayImageURL ?? summary.imageURL)
                .frame(maxHeight: 470)

            VStack(spacing: 6) {
                Text(details.card.name).font(.title2.bold()).multilineTextAlignment(.center)
                Text(details.card.setName).foregroundStyle(.secondary)
                Text(details.card.identifier).font(.headline.monospacedDigit())
                if let rarity = details.card.rarity { Text(rarity.capitalized).font(.subheadline).foregroundStyle(.secondary) }
            }

            ownedSection(details.card)
            priceSection(details.card)

            Button { prepareAdd(details.card) } label: {
                Label("Add to Collection", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    @ViewBuilder private func ownedSection(_ card: IdentifiedCard) -> some View {
        let rows = ownedRows(card)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Owned").font(.headline)
                ForEach(rows) { row in
                    LabeledContent(row.variant?.label ?? "Unknown finish", value: "\(row.quantity)")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private func priceSection(_ card: IdentifiedCard) -> some View {
        if !card.marketPrices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Published market prices").font(.headline)
                ForEach(card.marketPrices) { price in
                    LabeledContent(price.label, value: price.value.formatted(.currency(code: "USD")))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func prepareAdd(_ card: IdentifiedCard) {
        switch VariantResolver.resolve(card.variantEvidence) {
        case let .resolved(resolved): commit(resolved)
        case let .needsChoice(options, _):
            finishOptions = options
            showsFinishChoice = true
        }
    }

    private func commit(_ resolved: ResolvedVariant) {
        guard let details else { return }
        let store = CollectionStore(context: modelContext)
        let mutation = store.add(
            details.card,
            resolved: resolved,
            identityResolution: .catalogSelected,
            setReleaseOrder: details.set.releaseOrder,
            matchCatalogAliases: true
        )
        let storageID = store.card(forKey: mutation.collectionKey)?.providerID ?? details.card.providerID
        let prices = PriceStore(context: modelContext)
        prices.store(
            CardPricing.price(for: details.card, variant: resolved.variant),
            game: details.card.game,
            printingID: storageID,
            variantID: resolved.variant?.id
        )
        prices.save()
        pendingMutation = mutation
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { pendingMutation = nil }
        }
    }

    private func ownedRows(_ card: IdentifiedCard) -> [CollectedCard] {
        ownedCards.filter { $0.providerID == card.providerID || $0.catalogProviderID == card.providerID }
            .sorted { ($0.variantLabel ?? "") < ($1.variantLabel ?? "") }
    }

    private func addedBanner(_ mutation: CollectionMutation) -> some View {
        HStack {
            Label("Added to Collection", systemImage: "checkmark.circle.fill")
            Spacer()
            Button("Undo") {
                undoTask?.cancel()
                CollectionStore(context: modelContext).undo(mutation)
                pendingMutation = nil
            }
            .fontWeight(.semibold)
            .frame(minHeight: 44)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func load() async {
        isLoading = true
        error = nil
        do { details = try await catalog.details(for: summary) }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }
}
