import SwiftData
import SwiftUI

struct CollectionCardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: CollectedCard

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

                Stepper("Quantity: \(card.quantity)", value: $card.quantity, in: 1...999)
                    .padding(.horizontal)

                Button("Remove from Collection", role: .destructive) {
                    modelContext.delete(card)
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
    }
}
