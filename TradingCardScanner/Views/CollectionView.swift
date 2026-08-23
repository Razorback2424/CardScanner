import SwiftData
import SwiftUI

struct CollectionView: View {
    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var totalCards: Int {
        cards.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Scan a card and add it to your collection.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(cards) { card in
                                NavigationLink {
                                    CollectionCardDetailView(card: card)
                                } label: {
                                    CollectionCardTile(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("Collection")
            .toolbar {
                if !cards.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(totalCards)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CollectionCardTile: View {
    let card: CollectedCard

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: card.lowImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .aspectRatio(0.727, contentMode: .fit)
                        .overlay { Image(systemName: "photo") }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if card.quantity > 1 {
                Text("×\(card.quantity)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.78), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(5)
            }
        }
        .accessibilityLabel("\(card.name), quantity \(card.quantity)")
    }
}
