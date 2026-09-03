import SwiftData
import SwiftUI

/// Loads the graded variants of one card.
@MainActor
final class GradedVariantModel: ObservableObject {
    @Published private(set) var variants: [GradedVariant] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: JustTCGV2GradedClient

    init(transport: JustTCGTransport) {
        self.client = JustTCGV2GradedClient(transport: transport)
    }

    var isConfigured: Bool { PriceVendorCredentials.hasKey }

    /// Grouped grader-first, which is also how the picker navigates: choosing a
    /// grader then a grade keeps each screen to a handful of 44pt rows rather
    /// than presenting a hundred permutations in one dialog.
    var byCompany: [(company: GradingCompany, variants: [GradedVariant])] {
        Dictionary(grouping: variants, by: \.company)
            .map { (company: $0.key, variants: $0.value.sorted(by: Self.gradeOrder)) }
            .sorted { $0.company.label < $1.company.label }
    }

    /// Highest numeric grade first; non-numeric labels such as Authentic sort to
    /// the end rather than being treated as a zero.
    private static func gradeOrder(_ lhs: GradedVariant, _ rhs: GradedVariant) -> Bool {
        switch (lhs.grade.value.flatMap(Double.init), rhs.grade.value.flatMap(Double.init)) {
        case let (left?, right?): return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.displayName < rhs.displayName
        }
    }

    func load(identity: GradedCardIdentity, game: CardGame) async {
        guard isConfigured, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            variants = try await client.gradedVariants(identity: identity, game: game)
            errorMessage = variants.isEmpty
                ? "No graded prices are published for this card yet."
                : nil
        } catch {
            errorMessage = SealedBrowseModel.message(for: error)
        }
    }
}

/// Grader, then grade. Two short lists rather than one long one.
struct GradedVariantPickerView: View {
    let card: IdentifiedCard
    let setReleaseOrder: Int?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: GradedVariantModel
    @State private var addedSummary: String?

    init(card: IdentifiedCard, setReleaseOrder: Int?, transport: JustTCGTransport) {
        self.card = card
        self.setReleaseOrder = setReleaseOrder
        _model = StateObject(wrappedValue: GradedVariantModel(transport: transport))
    }

    var body: some View {
        NavigationStack {
            List {
                if !model.isConfigured {
                    Label(
                        "Add a pricing API key in Settings to add graded copies.",
                        systemImage: "key"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                ForEach(model.byCompany, id: \.company) { group in
                    Section(group.company.label) {
                        ForEach(group.variants) { variant in
                            NavigationLink {
                                GradedSlabConfirmationView(
                                    card: card,
                                    variant: variant,
                                    setReleaseOrder: setReleaseOrder,
                                    onAdded: { summary in
                                        addedSummary = summary
                                        dismiss()
                                    }
                                )
                            } label: {
                                gradeRow(variant)
                            }
                        }
                    }
                }
            }
            .overlay {
                if model.isLoading {
                    ProgressView("Loading graded prices…")
                }
            }
            .navigationTitle("Add Graded Copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await model.load(identity: GradedCardIdentity(card), game: card.game)
            }
        }
    }

    private func gradeRow(_ variant: GradedVariant) -> some View {
        HStack {
            Text(variant.displayName)
            Spacer()
            if let price = variant.marketPriceUSD {
                Text(price, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                // The vendor does not manufacture a number for every
                // grader/grade permutation, and absence is stated as such.
                Text("No price")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// The last step: review the price, optionally record a certificate, add.
struct GradedSlabConfirmationView: View {
    let card: IdentifiedCard
    let variant: GradedVariant
    let setReleaseOrder: Int?
    let onAdded: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var certificationNumber = ""
    @State private var addFailure: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Card", value: card.name)
                LabeledContent("Grade", value: variant.displayName)
                if let price = variant.marketPriceUSD {
                    LabeledContent("Market price") {
                        Text(price, format: .currency(code: "USD")).monospacedDigit()
                    }
                } else {
                    LabeledContent("Market price", value: "No reliable market price")
                }
                if let updatedAt = variant.updatedAt {
                    LabeledContent(
                        "Price as of",
                        value: updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            } footer: {
                // Stated plainly rather than dressed up as a confidence score.
                // Graded pricing is a beta API and has not been compared against
                // sold comps, so the app says what it knows and no more.
                Text("Beta graded pricing.")
            }

            Section {
                TextField("Certification number (optional)", text: $certificationNumber)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            } footer: {
                Text("A slab with a certificate number is tracked as its own copy rather than stacking with identical grades.")
            }

            Section {
                Button {
                    add()
                } label: {
                    Label("Add Slab", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(variant.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't add this slab",
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
    }

    private func add() {
        let trimmed = certificationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // `onAdded` dismisses the picker and is the only confirmation there
            // is. Returning silently on a throw left the sheet sitting there
            // looking untouched, with the slab not in the collection.
            _ = try CollectionStore(context: modelContext).addGraded(
                underlying: card,
                variant: variant,
                certificationNumber: trimmed.isEmpty ? nil : trimmed,
                setReleaseOrder: setReleaseOrder
            )
        } catch {
            addFailure = error.localizedDescription
            return
        }
        onAdded(variant.displayName)
    }
}
