import SwiftData
import SwiftUI

/// Loads sealed sets and products, one game at a time.
///
/// Kept apart from the card catalogue because the two use different directories.
/// The vendor groups sets its own way, and mapping those groupings onto TCGdex
/// or Scryfall set identities is unreliable — a wrong mapping would show the
/// wrong products under a familiar set name, which is worse than showing the
/// vendor's own grouping honestly.
@MainActor
final class SealedBrowseModel: ObservableObject {
    @Published private(set) var sets: [SealedSetSummary] = []
    @Published private(set) var products: [SealedProductSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasMore = false

    private let client: JustTCGV1Client
    private var offset = 0
    private var loadedGame: CardGame?

    init(transport: JustTCGTransport) {
        self.client = JustTCGV1Client(transport: transport)
    }

    var isConfigured: Bool { PriceVendorCredentials.hasKey }

    /// One request, and only when the directory is not already loaded for this
    /// game. Sealed browse is interactive, but it is still the user's quota.
    func loadSetsIfNeeded(game: CardGame) async {
        guard isConfigured, loadedGame != game || sets.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            sets = try await client.sealedSets(game: game)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            loadedGame = game
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadProducts(game: CardGame, setID: String?, query: String? = nil) async {
        guard isConfigured, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        offset = 0
        do {
            let page = try await client.searchSealedProducts(
                game: game, setID: setID, query: query, offset: 0
            )
            products = page.items
            hasMore = page.hasMore
            offset = page.items.count
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadMore(game: CardGame, setID: String?, query: String? = nil) async {
        guard isConfigured, hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.searchSealedProducts(
                game: game, setID: setID, query: query, offset: offset
            )
            products += page.items
            hasMore = page.hasMore
            offset += page.items.count
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Quota and rate-limit stops get their own wording, including when they
    /// lift — "try again later" with no time attached is not actionable.
    static func message(for error: Error) -> String {
        guard let transportError = error as? JustTCGTransport.TransportError else {
            return error.localizedDescription
        }
        switch transportError {
        case let .budgetReached(resetAt):
            return "Daily request budget reached · resumes \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        case let .monthlyBudgetReached(resetAt):
            return "Monthly request budget reached · resumes \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        case let .rateLimited(retryAt):
            return "Paused by the provider · retry after \(retryAt.formatted(date: .abbreviated, time: .shortened))"
        case .missingCredentials:
            return "Add a pricing API key in Settings to browse sealed products."
        case .invalidURL, .badResponse:
            return transportError.errorDescription ?? "Sealed products could not be loaded."
        }
    }
}

// MARK: - Set directory

struct SealedSetDirectoryView: View {
    let game: CardGame
    @ObservedObject var model: SealedBrowseModel

    var body: some View {
        List {
            if !model.isConfigured {
                unconfigured
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(model.sets) { set in
                NavigationLink {
                    SealedProductGridView(game: game, set: set, model: model)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.name)
                            Text("\(set.sealedCount) sealed product\(set.sealedCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    // 44pt minimum, and both lines read as one label.
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay {
            if model.isLoading, model.sets.isEmpty {
                ProgressView("Loading sealed sets…")
            } else if model.sets.isEmpty, model.errorMessage == nil, model.isConfigured {
                ContentUnavailableView(
                    "No Sealed Products",
                    systemImage: "shippingbox",
                    description: Text("This game has no sealed products in the price catalogue.")
                )
            }
        }
        .navigationTitle("Sealed")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: game) { await model.loadSetsIfNeeded(game: game) }
    }

    private var unconfigured: some View {
        Label(
            "Add a pricing API key in Settings to browse sealed products.",
            systemImage: "key"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Product grid

struct SealedProductGridView: View {
    let game: CardGame
    let set: SealedSetSummary
    @ObservedObject var model: SealedBrowseModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.products) { product in
                    NavigationLink {
                        SealedProductDetailView(game: game, product: product)
                    } label: {
                        SealedProductTile(product: product)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            if model.hasMore {
                Button("Load More") {
                    Task { await model.loadMore(game: game, setID: set.id) }
                }
                .padding(.bottom, 20)
                .disabled(model.isLoading)
            }
        }
        .overlay {
            if model.isLoading, model.products.isEmpty {
                ProgressView("Loading products…")
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: set.id) { await model.loadProducts(game: game, setID: set.id) }
    }
}

private struct SealedProductTile: View {
    let product: SealedProductSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SealedProductArtwork(imageURL: product.imageURL)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(product.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let price = product.marketPriceUSD {
                Text(price, format: .currency(code: "USD"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            } else {
                Text("No market price")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Product detail

struct SealedProductDetailView: View {
    let game: CardGame
    let product: SealedProductSummary

    @Environment(\.modelContext) private var modelContext
    @Query private var owned: [CollectedCard]
    @State private var pendingMutation: CollectionMutation?
    @State private var undoTask: Task<Void, Never>?

    private var ownedQuantity: Int {
        owned
            .filter { $0.itemKind == .sealedProduct && $0.justTCGCardID == product.id }
            .reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        List {
            Section {
                SealedProductArtwork(imageURL: product.imageURL)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                LabeledContent("Product", value: product.name)
                if let setName = product.setName {
                    LabeledContent("Set", value: setName)
                }
                if let price = product.marketPriceUSD {
                    LabeledContent("Market price") {
                        Text(price, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                } else {
                    // A missing price is stated, not hidden behind a dash.
                    LabeledContent("Market price", value: "No reliable market price")
                }
                if let updatedAt = product.updatedAt {
                    LabeledContent(
                        "Price as of",
                        value: updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                LabeledContent("Owned", value: "\(ownedQuantity)")
            }

            Section {
                Button {
                    add()
                } label: {
                    Label("Add to Collection", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Sealed Product")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if pendingMutation != nil {
                undoBanner
            }
        }
        .onDisappear { undoTask?.cancel() }
    }

    private var undoBanner: some View {
        HStack {
            Text("Added \(product.name)")
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("Undo") { undo() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Adding never waits on the network. The price already shown came with the
    /// listing, and routine repricing happens later through a batch.
    private func add() {
        let store = CollectionStore(context: modelContext)
        pendingMutation = store.addSealed(product, game: game)
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { pendingMutation = nil }
        }
    }

    private func undo() {
        guard let pendingMutation else { return }
        CollectionStore(context: modelContext).undo(pendingMutation)
        self.pendingMutation = nil
        undoTask?.cancel()
    }
}

private struct SealedProductArtwork: View {
    let imageURL: URL?

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            case .empty, .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08))
    }

    private var placeholder: some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: 34))
            .foregroundStyle(.secondary)
    }
}
