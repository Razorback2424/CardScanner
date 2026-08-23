import SwiftUI

/// The way back into one record without leaving the session.
///
/// There is no "Add to Collection" button here because the card is already in
/// the collection — that decision was made the moment identity and variant were
/// both known. This sheet exists for the rarer, more useful question: is the
/// variant right, and what is it worth.
struct ScanReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scan: RecentScan
    let onCorrect: (PhysicalVariant) -> Void

    @State private var variant: PhysicalVariant?
    @State private var resolution: VariantResolution

    init(scan: RecentScan, onCorrect: @escaping (PhysicalVariant) -> Void) {
        self.scan = scan
        self.onCorrect = onCorrect
        _variant = State(initialValue: scan.resolved.variant)
        _resolution = State(initialValue: scan.resolved.resolution)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    AsyncImage(url: scan.card.displayImageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFit()
                        case .failure:
                            ContentUnavailableView("Image unavailable", systemImage: "photo")
                                .frame(height: 380)
                        default:
                            ProgressView().frame(height: 380)
                        }
                    }
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    identity
                    variantSection

                    if !scan.card.marketPrices.isEmpty {
                        prices
                    }
                }
                .padding(20)
            }
            .navigationTitle("Scanned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Text(scan.card.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(scan.card.setName)
                .foregroundStyle(.secondary)

            Text(scan.card.identifier)
                .font(.headline.monospacedDigit())

            if let rarity = scan.card.rarity {
                Text(rarity)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var variantSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Finish")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // Identity and finish are two different facts with two different
                // sources, so the record says where each one came from.
                Text(resolution.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scan.options.count > 1 {
                Picker("Finish", selection: Binding(
                    get: { variant },
                    set: { newValue in
                        guard let newValue, newValue != variant else { return }
                        variant = newValue
                        resolution = .userConfirmed
                        onCorrect(newValue)
                    }
                )) {
                    ForEach(scan.options) { option in
                        Text(option.label).tag(Optional(option))
                    }
                }
                .pickerStyle(.segmented)
            } else {
                HStack {
                    Text(variant?.label ?? "Unknown finish")
                        .font(.body.weight(.medium))
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var prices: some View {
        VStack(spacing: 8) {
            ForEach(scan.card.marketPrices) { price in
                let isResolved = price.variantID != nil && price.variantID == variant?.id
                HStack {
                    Text("\(price.label) market")
                        .font(.subheadline.weight(isResolved ? .semibold : .regular))
                    Spacer()
                    Text(price.value, format: .currency(code: "USD"))
                        .font(.subheadline.weight(isResolved ? .semibold : .regular))
                        .monospacedDigit()
                }
                .foregroundStyle(isResolved ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
