import SwiftData
import SwiftUI

struct CollectionActivityLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionActivity.occurredAt, order: .reverse)
    private var activities: [CollectionActivity]
    @Query private var cards: [CollectedCard]

    var body: some View {
        Group {
            if activities.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("New scans, imports, and catalog additions will appear here.")
                )
            } else {
                List(activities) { activity in
                    NavigationLink {
                        CollectionActivityEditor(activity: activity)
                    } label: {
                        activityRow(activity)
                    }
                }
            }
        }
        .navigationTitle("Collection Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { backfillExistingCollectionIfNeeded() }
    }

    private func activityRow(_ activity: CollectionActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activity.source.symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(metadataLine(activity))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(activity.occurredAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if activity.quantity > 1 {
                Text("×\(activity.quantity)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metadataLine(_ activity: CollectionActivity) -> String {
        let finish = activity.variantLabel ?? activity.itemKind.label
        return [
            activity.source.label,
            activity.setName,
            activity.cardNumber,
            activity.pokemonPrintRun?.label,
            finish
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Older stores predate the audit entity. Preserve what can be known from
    /// the collection row without inventing individual scan times: one event at
    /// the row's recorded add date, carrying its full current quantity.
    @MainActor
    private func backfillExistingCollectionIfNeeded() {
        let loggedKeys = Set(activities.map(\.collectionKey))
        var inserted = false
        for card in cards where !loggedKeys.contains(card.collectionKey) {
            let source: CollectionActivitySource
            switch card.itemKind {
            case .sealedProduct: source = .sealedCatalog
            case .gradedCard: source = .gradedCatalog
            case .rawCard:
                switch card.identityResolution {
                case .imported: source = .csvImport
                case .printedIdentifier: source = .scan
                case .catalogSelected, .userCorrected, .none: source = .catalog
                }
            }
            modelContext.insert(
                CollectionActivity(
                    card: card,
                    source: source,
                    quantity: card.quantity,
                    occurredAt: card.dateAdded
                )
            )
            inserted = true
        }
        if inserted { try? modelContext.save() }
    }
}

private struct CollectionActivityEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var activity: CollectionActivity

    @State private var name: String
    @State private var setName: String
    @State private var setCode: String
    @State private var cardNumber: String
    @State private var variantID: String?
    @State private var pokemonPrintRunRaw: String?
    @State private var errorMessage: String?
    @State private var isConfirmingIdentityChange = false

    init(activity: CollectionActivity) {
        self.activity = activity
        _name = State(initialValue: activity.name)
        _setName = State(initialValue: activity.setName)
        _setCode = State(initialValue: activity.setCode)
        _cardNumber = State(initialValue: activity.cardNumber)
        _variantID = State(initialValue: activity.variantID)
        _pokemonPrintRunRaw = State(initialValue: activity.pokemonPrintRunRaw)
    }

    var body: some View {
        Form {
            Section("Recorded") {
                LabeledContent("Source", value: activity.source.label)
                LabeledContent(
                    "Added",
                    value: activity.occurredAt.formatted(date: .abbreviated, time: .shortened)
                )
                LabeledContent("Game", value: activity.game.label)
                LabeledContent("Item Type", value: activity.itemKind.label)
                if activity.quantity > 1 {
                    LabeledContent("Quantity", value: "\(activity.quantity)")
                }
                if let correctedAt = activity.correctedAt {
                    LabeledContent(
                        "Last Corrected",
                        value: correctedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            Section {
                TextField("Name", text: $name)
                TextField("Set Name", text: $setName)
                TextField("Set Code", text: $setCode)
                    .textInputAutocapitalization(.characters)
                TextField("Card Number", text: $cardNumber)

                if activity.itemKind == .rawCard {
                    if activity.game == .pokemon {
                        Picker("Print Run", selection: $pokemonPrintRunRaw) {
                            Text("Standard / Not Applicable").tag(nil as String?)
                            Text(PokemonPrintRun.firstEdition.label)
                                .tag(PokemonPrintRun.firstEdition.rawValue as String?)
                            Text(PokemonPrintRun.shadowless.label)
                                .tag(PokemonPrintRun.shadowless.rawValue as String?)
                            Text(PokemonPrintRun.unlimited.label)
                                .tag(PokemonPrintRun.unlimited.rawValue as String?)
                        }
                    }
                    Picker("Finish", selection: $variantID) {
                        Text("Unknown").tag(nil as String?)
                        ForEach(PhysicalVariant.selectable(for: activity.game)) { variant in
                            Text(variant.label).tag(variant.id as String?)
                        }
                    }
                }
            } header: {
                Text("Metadata")
            } footer: {
                Text("Changing identity metadata removes the old catalog artwork and price link so information from the previous product cannot remain attached.")
            }
        }
        .navigationTitle("Review Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { prepareSave() }
                    .disabled(!hasChanges || name.trimmed.isEmpty)
            }
        }
        .confirmationDialog(
            "Change card identity?",
            isPresented: $isConfirmingIdentityChange,
            titleVisibility: .visible
        ) {
            Button("Save and Clear Old Catalog Link", role: .destructive) {
                save(identityChanged: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The old artwork and linked price may belong to a different printing. They will be removed from this collection entry.")
        }
        .alert("Correction Couldn’t Be Saved", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var hasChanges: Bool {
        name.trimmed != activity.name
            || setName.trimmed != activity.setName
            || setCode.trimmed != activity.setCode
            || cardNumber.trimmed != activity.cardNumber
            || variantID != activity.variantID
            || pokemonPrintRunRaw != activity.pokemonPrintRunRaw
    }

    private var identityChanged: Bool {
        name.trimmed != activity.name
            || setName.trimmed != activity.setName
            || setCode.trimmed != activity.setCode
            || cardNumber.trimmed != activity.cardNumber
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func prepareSave() {
        if identityChanged {
            isConfirmingIdentityChange = true
        } else {
            save(identityChanged: false)
        }
    }

    private func save(identityChanged: Bool) {
        let oldKey = activity.collectionKey
        guard let card = collectionCard(key: oldKey) else {
            errorMessage = "The corresponding collection entry no longer exists."
            return
        }

        let providerID: String
        if identityChanged {
            providerID = "corrected:\(UUID().uuidString.lowercased())"
        } else {
            providerID = card.providerID
        }
        let baseKey = identityChanged
            ? providerID
            : card.collectionKey
                .split(separator: "@", maxSplits: 1).first.map(String.init)?
                .split(separator: "#", maxSplits: 1).first.map(String.init) ?? card.providerID
        let finishKey = variantID.map { "\(baseKey)#\($0)" } ?? baseKey
        let newKey = pokemonPrintRunRaw.map { "\(finishKey)@\($0)" } ?? finishKey

        if newKey != oldKey, collectionCard(key: newKey) != nil {
            errorMessage = "A collection entry with this identity and finish already exists."
            return
        }

        // Captured before the row is rewritten: afterwards the old identity is
        // gone and the outgoing leg has nothing to value itself against.
        let ledger = InventoryLedger(context: modelContext)
        let previousPriceStorageKey = ledger.priceStorageKey(for: card)
        let movedQuantity = card.quantity

        card.collectionKey = newKey
        card.name = name.trimmed
        card.setName = setName.trimmed
        card.setCode = setCode.trimmed.uppercased()
        card.cardNumber = cardNumber.trimmed
        card.variantID = variantID
        card.variantLabel = variantID.map { PhysicalVariant.resolving($0).label }
        card.pokemonPrintRunRaw = pokemonPrintRunRaw
        card.variantResolutionRaw = VariantResolution.userConfirmed.rawValue

        if identityChanged {
            card.providerID = providerID
            card.catalogProviderID = nil
            card.catalogMetadataCheckedAt = nil
            card.catalogMetadataVersion = 0
            card.imageURL = nil
            card.thumbnailURL = nil
            card.tcgplayerURL = nil
            card.justTCGCardID = nil
            card.justTCGVariantID = nil
            card.justTCGAPIVersion = nil
            card.identityResolutionRaw = IdentityResolution.userCorrected.rawValue
        }

        let descriptor = FetchDescriptor<CollectionActivity>(
            predicate: #Predicate { $0.collectionKey == oldKey }
        )
        let related = (try? modelContext.fetch(descriptor)) ?? [activity]
        for event in related {
            event.collectionKey = newKey
            event.name = card.name
            event.setName = card.setName
            event.setCode = card.setCode
            event.cardNumber = card.cardNumber
            event.variantID = card.variantID
            event.variantLabel = card.variantLabel
            event.pokemonPrintRunRaw = card.pokemonPrintRunRaw
            event.correctedAt = .now
        }

        // A correction, never an acquisition. Correcting a variant from $8 to
        // $74 is +$66 of corrections; showing it as a market gain would be
        // precisely the thing this feature exists to stop.
        let newPriceStorageKey = ledger.priceStorageKey(for: card)
        if newKey != oldKey || newPriceStorageKey != previousPriceStorageKey {
            ledger.recordCorrection(
                fromCollectionKey: oldKey,
                fromPriceStorageKey: previousPriceStorageKey,
                toCard: card,
                quantity: movedQuantity
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func collectionCard(key: String) -> CollectedCard? {
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
