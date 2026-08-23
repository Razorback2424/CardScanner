import SwiftData
import SwiftUI
import UIKit

struct CardResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let card: TCGdexCard
    let setCode: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: card.highImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            imagePlaceholder
                        default:
                            ProgressView()
                                .frame(height: 410)
                        }
                    }
                    .frame(maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 7) {
                        Text(card.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(card.set.name)
                            .foregroundStyle(.secondary)

                        Text("\(setCode)  \(card.localId)/\(card.set.cardCount.official)")
                            .font(.headline.monospacedDigit())

                        if let rarity = card.rarity {
                            Text(rarity)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if !card.marketPrices.isEmpty {
                            VStack(spacing: 5) {
                                ForEach(card.marketPrices) { price in
                                    HStack(spacing: 5) {
                                        Text("\(price.label) market")
                                        Text(price.value, format: .currency(code: "USD"))
                                    }
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                        }
                    }

                    Button(action: addToCollection) {
                        Label("Add to Collection", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Scan Again") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
            }
            .navigationTitle("Card Found")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var imagePlaceholder: some View {
        ContentUnavailableView("Image unavailable", systemImage: "photo")
            .frame(height: 410)
    }

    private func addToCollection() {
        let cardID = card.id
        let descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { item in
                item.tcgdexID == cardID
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.quantity += 1
            existing.dateAdded = .now
        } else {
            modelContext.insert(CollectedCard(card: card, setCode: setCode))
        }

        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
