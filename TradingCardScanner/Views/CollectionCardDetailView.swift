import SwiftData
import SwiftUI

struct CollectionCardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: CollectedCard
    let price: PriceDisplay
    let onRemoved: (RemovedCardSnapshot) -> Void

    @State private var isConfirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AsyncImage(url: card.highImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        ProgressView().frame(height: 410)
                    }
                }
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 7) {
                    Text(card.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(card.setName)
                        .foregroundStyle(.secondary)
                    Text("\(card.setCode)  \(card.cardNumber)")
                        .font(.headline.monospacedDigit())
                    if let rarity = card.rarity {
                        Text(rarity)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                pricing
                finish

                Stepper("Quantity: \(card.quantity)", value: $card.quantity, in: 1...999)
                    .padding(.horizontal)

                Button("Remove from Collection", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "Remove \(card.name)?",
                    isPresented: $isConfirmingRemoval,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        removeCard()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(removalMessage)
                }
            }
            .padding(20)
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var removalMessage: String {
        if card.quantity == 1 {
            return "This removes the card. You can undo it."
        }
        return "This removes all \(card.quantity) copies. You can undo it."
    }

    private func removeCard() {
        let removed = RemovedCardSnapshot(card: card)
        modelContext.delete(card)
        try? modelContext.save()
        onRemoved(removed)
        dismiss()
    }

    /// The price belongs to this printing *and* this finish. When the provider
    /// exposes nothing for the variant the user owns, the app says so instead of
    /// borrowing a different finish's number.
    private var pricing: some View {
        VStack(spacing: 6) {
            PriceLabel(price: price, style: .detailed)

            if let source = price.source, price.amount != nil {
                Text(source.publishesSourceTimestamp
                     ? "\(source.label) · current as of \(price.effectiveAsOf?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")"
                     : "\(source.label) · checked \(price.fetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if price.refreshFailed {
                Label("Last refresh failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var finish: some View {
        VStack {
            LabeledContent("Finish", value: card.variant?.label ?? "Unknown")
        }
        .font(.subheadline)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Everything needed to restore a removed row without another catalog request.
/// The value safely outlives the deleted SwiftData model.
struct RemovedCardSnapshot: Identifiable {
    let id = UUID()
    let collectionKey: String
    let game: CardGame
    let providerID: String
    let name: String
    let setName: String
    let setCode: String
    let cardNumber: String
    let rarity: String?
    let imageURL: String?
    let thumbnailURL: String?
    let quantity: Int
    let dateAdded: Date
    let variant: PhysicalVariant?
    let variantResolution: VariantResolution
    let identityResolution: IdentityResolution
    let setReleaseOrder: Int

    init(card: CollectedCard) {
        collectionKey = card.collectionKey
        game = card.cardGame
        providerID = card.providerID
        name = card.name
        setName = card.setName
        setCode = card.setCode
        cardNumber = card.cardNumber
        rarity = card.rarity
        imageURL = card.imageURL
        thumbnailURL = card.thumbnailURL
        quantity = card.quantity
        dateAdded = card.dateAdded
        variant = card.variant
        variantResolution = card.variantResolution ?? .catalogSilent
        identityResolution = card.identityResolution ?? .printedIdentifier
        setReleaseOrder = card.setReleaseOrder
    }

    @MainActor
    func restore(in context: ModelContext) {
        let key = collectionKey
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.quantity += quantity
            existing.dateAdded = max(existing.dateAdded, dateAdded)
        } else {
            context.insert(
                CollectedCard(
                    collectionKey: collectionKey,
                    game: game,
                    providerID: providerID,
                    name: name,
                    setName: setName,
                    setCode: setCode,
                    cardNumber: cardNumber,
                    rarity: rarity,
                    imageURL: imageURL,
                    thumbnailURL: thumbnailURL,
                    variant: variant,
                    variantResolution: variantResolution,
                    identityResolution: identityResolution,
                    setReleaseOrder: setReleaseOrder,
                    quantity: quantity,
                    dateAdded: dateAdded
                )
            )
        }

        try? context.save()
    }
}
