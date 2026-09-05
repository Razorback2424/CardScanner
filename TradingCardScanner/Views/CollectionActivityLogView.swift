import SwiftData
import SwiftUI

struct CollectionActivityLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionActivity.occurredAt, order: .reverse)
    private var activities: [CollectionActivity]
    @Query private var cards: [CollectedCard]
    @Query private var inventoryEvents: [InventoryEvent]
    @State private var selectedKind: CollectionActivityKind?
    @State private var pendingRemovalID: UUID?
    @State private var errorMessage: String?

    private struct ActivityIndex {
        let cardsByCollectionKey: [String: CollectedCard]
        let quantitiesByCollectionKey: [String: Int]
        let lineage: CollectionStore.LineageIndex
        let eventsByCollectionKey: [String: [InventoryEvent]]
    }

    var body: some View {
        let index = makeIndex()

        Group {
            if visibleActivities.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        selectedKind == nil
                            ? "New scans, imports, and collection changes will appear here."
                            : "No \(selectedKind?.label.lowercased() ?? "matching") history yet."
                    )
                )
            } else {
                List {
                    ForEach(visibleActivities) { activity in
                        HStack(spacing: 8) {
                            NavigationLink {
                                CollectionActivityEditor(activity: activity)
                            } label: {
                                activityRow(activity)
                            }
                            activityActions(for: activity, using: index)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canRemove(activity, using: index) {
                                Button("Remove", role: .destructive) {
                                    pendingRemovalID = activity.id
                                }
                            }
                            if canRestore(activity, using: index) {
                                Button("Restore") {
                                    restore(activity)
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Collection Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                kindFilter
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "copies")?",
            isPresented: removalDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { remove(pendingRemoval) }
            }
            Button("Cancel", role: .cancel) { pendingRemovalID = nil }
        } message: {
            Text("Only the copies claimed by this history entry will be removed.")
        }
        .task { try? CollectionStore(context: modelContext).backfillExistingCollectionIfNeeded() }
        .alert("History Action Couldn’t Be Saved", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var visibleActivities: [CollectionActivity] {
        guard let selectedKind else { return activities }
        return activities.filter { $0.kind == selectedKind }
    }

    private var pendingRemoval: CollectionActivity? {
        guard let pendingRemovalID else { return nil }
        return activities.first { $0.id == pendingRemovalID }
    }

    private var removalDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingRemovalID != nil },
            set: { if !$0 { pendingRemovalID = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func makeIndex() -> ActivityIndex {
        let projection = LogicalCollection.project(cards: cards) { $0.priceKey }
        return ActivityIndex(
            cardsByCollectionKey: projection.byKey.mapValues(\.representative),
            quantitiesByCollectionKey: projection.quantities,
            lineage: CollectionStore.LineageIndex(events: inventoryEvents),
            eventsByCollectionKey: Dictionary(grouping: inventoryEvents, by: \.collectionKey)
        )
    }

    private var kindFilter: some View {
        Menu {
            Button {
                selectedKind = nil
            } label: {
                filterLabel("All", selected: selectedKind == nil)
            }
            ForEach(CollectionActivityKind.allCases) { kind in
                Button {
                    selectedKind = kind
                } label: {
                    filterLabel(kind.label, selected: selectedKind == kind)
                }
            }
        } label: {
            Image(systemName: selectedKind == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(
            selectedKind.map { "Filter history: \($0.label)" } ?? "Filter history"
        )
    }

    @ViewBuilder
    private func filterLabel(_ label: String, selected: Bool) -> some View {
        if selected {
            Label(label, systemImage: "checkmark")
        } else {
            Text(label)
        }
    }

    private func activityRow(_ activity: CollectionActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activity.kind.symbolName)
                .foregroundStyle(color(for: activity.kind))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.kind.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: activity.kind))
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

            Text(signedQuantity(activity.signedQuantity))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func activityActions(
        for activity: CollectionActivity,
        using index: ActivityIndex
    ) -> some View {
        Menu {
            if canCorrect(activity, using: index) {
                NavigationLink {
                    CollectionActivityEditor(activity: activity)
                } label: {
                    Label("Correct finish…", systemImage: "pencil")
                }
            } else {
                Button("Correct finish…", systemImage: "pencil") {}
                    .disabled(true)
                Text(actionReason(activity, action: .correct, using: index))
                    .font(.caption)
            }

            if canRemove(activity, using: index) {
                Button("Remove copies…", systemImage: "minus.circle") {
                    pendingRemovalID = activity.id
                }
            } else {
                Button("Remove copies…", systemImage: "minus.circle") {}
                    .disabled(true)
                Text(actionReason(activity, action: .remove, using: index))
                    .font(.caption)
            }

            if canRestore(activity, using: index) {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    restore(activity)
                }
            } else if activity.kind == .removed {
                Button("Restore", systemImage: "arrow.uturn.backward") {}
                    .disabled(true)
                Text(actionReason(activity, action: .restore, using: index))
                    .font(.caption)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("Actions for \(activity.name)")
    }

    private func metadataLine(_ activity: CollectionActivity) -> String {
        let finish = activity.variantLabel ?? activity.itemKind.label
        return [
            activity.source.label,
            activity.setName,
            activity.cardNumber,
            activity.pokemonPrintRun?.label,
            activity.magicContentKind == .regular ? nil : activity.magicContentKind.label,
            finish,
            treatmentLabel(for: activity)
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func treatmentLabel(for activity: CollectionActivity) -> String? {
        activity.magicTreatmentEvidence.displayLabel
    }

    private enum Action {
        case correct
        case remove
        case restore
    }

    private func canCorrect(_ activity: CollectionActivity, using index: ActivityIndex) -> Bool {
        activity.kind.hasQuantityClaim
            && activity.signedQuantity > 0
            && activity.itemKind == .rawCard
            && activity.remainingQuantity > 0
            && activity.variantID != nil
            && (index.quantitiesByCollectionKey[activity.collectionKey] ?? 0) >= activity.remainingQuantity
            && CollectionStore.hasValidLineage(
                activity.ledgerOperationIDs,
                for: activity.collectionKey,
                quantity: activity.claimedQuantity,
                using: index.lineage
            )
    }

    private func canRemove(_ activity: CollectionActivity, using index: ActivityIndex) -> Bool {
        activity.kind.hasQuantityClaim
            && activity.signedQuantity > 0
            && activity.remainingQuantity > 0
            && CollectionStore.hasValidLineage(
                activity.ledgerOperationIDs,
                for: activity.collectionKey,
                quantity: activity.claimedQuantity,
                using: index.lineage
            )
            && (index.quantitiesByCollectionKey[activity.collectionKey] ?? 0) >= activity.remainingQuantity
    }

    private func canRestore(_ activity: CollectionActivity, using index: ActivityIndex) -> Bool {
        guard activity.kind == .removed,
              activity.remainingQuantity > 0,
              activity.removalSnapshotData != nil,
              Date.now.timeIntervalSince(activity.occurredAt) <= CollectionActivity.restoreWindow,
              CollectionStore.hasValidRemovalLineage(activity, using: index.lineage)
        else { return false }

        guard card(for: activity, using: index) != nil else { return true }
        return !positionWasReacquired(activity, using: index)
    }

    private func actionReason(
        _ activity: CollectionActivity,
        action: Action,
        using index: ActivityIndex
    ) -> String {
        switch action {
        case .correct:
            if activity.kind != .added && activity.kind != .restored {
                return "Only entries that claim owned copies can be corrected."
            }
            if activity.signedQuantity <= 0 { return "This entry does not claim added copies." }
            if activity.remainingQuantity == 0 { return "This entry has already been acted on." }
            if activity.itemKind != .rawCard { return "Only raw card finishes can be corrected." }
            if activity.variantID == nil { return "This entry has no known finish." }
            if (index.quantitiesByCollectionKey[activity.collectionKey] ?? 0) < activity.remainingQuantity {
                return "The current collection quantity is too small."
            }
            if !CollectionStore.hasValidLineage(
                activity.ledgerOperationIDs,
                for: activity.collectionKey,
                quantity: activity.claimedQuantity,
                using: index.lineage
            ) {
                return "The ledger lineage is missing, incomplete, or already reversed."
            }
            return "The collection row is no longer available."
        case .remove:
            if !activity.kind.hasQuantityClaim { return "This entry does not claim removable copies." }
            if activity.signedQuantity <= 0 { return "This entry does not claim added copies." }
            if activity.remainingQuantity == 0 { return "This entry has already been acted on." }
            if (index.quantitiesByCollectionKey[activity.collectionKey] ?? 0) < activity.remainingQuantity {
                return "The current collection quantity is too small."
            }
            if !CollectionStore.hasValidLineage(
                activity.ledgerOperationIDs,
                for: activity.collectionKey,
                quantity: activity.claimedQuantity,
                using: index.lineage
            ) {
                return "The ledger lineage is missing, incomplete, or already reversed."
            }
            return "The current collection quantity is too small or unavailable."
        case .restore:
            if activity.removalSnapshotData == nil { return "This removal has no restore snapshot." }
            if activity.remainingQuantity == 0 { return "This removal has already been restored." }
            if !CollectionStore.hasValidRemovalLineage(activity, using: index.lineage) {
                return "The removal ledger lineage is missing, incomplete, or already reversed."
            }
            if positionWasReacquired(activity, using: index) { return "The position was acquired again." }
            if Date.now.timeIntervalSince(activity.occurredAt) > CollectionActivity.restoreWindow {
                return "This removal is outside the restore window."
            }
            return "This removal has already been restored."
        }
    }

    private func card(
        for activity: CollectionActivity,
        using index: ActivityIndex
    ) -> CollectedCard? {
        index.cardsByCollectionKey[activity.collectionKey]
    }

    /// A surviving row is not automatically a re-acquisition: a per-entry
    /// removal can leave sibling copies in that same quantity row. The disposal
    /// event and the absence of a later positive event are the proof the store
    /// uses before allowing that merge.
    private func positionWasReacquired(
        _ activity: CollectionActivity,
        using index: ActivityIndex
    ) -> Bool {
        guard card(for: activity, using: index) != nil else { return false }
        guard let data = activity.removalSnapshotData,
              let snapshot = try? JSONDecoder().decode(RemovedCardSnapshot.self, from: data),
              let operationID = snapshot.operationID else { return true }
        let removalRecordedAt = index.lineage.eventsByOperationID[operationID]?
            .map(\.recordedAt)
            .max()
        guard let removalRecordedAt else { return true }
        return index.eventsByCollectionKey[activity.collectionKey]?.contains {
            $0.recordedAt >= removalRecordedAt
                && $0.deltaQuantity > 0
        } == true
    }

    private func remove(_ activity: CollectionActivity) {
        pendingRemovalID = nil
        do {
            _ = try CollectionStore(context: modelContext).remove(activity)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ activity: CollectionActivity) {
        do {
            try CollectionStore(context: modelContext).restore(activity)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signedQuantity(_ quantity: Int) -> String {
        if quantity > 0 { return "+\(quantity)" }
        if quantity < 0 { return "−\(-quantity)" }
        return "—"
    }

    private func color(for kind: CollectionActivityKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .restored: return .mint
        case .corrected: return .orange
        case .quantityAdjusted: return .blue
        case .undone: return .purple
        }
    }
}

struct CollectionActivityEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var activity: CollectionActivity

    @State private var variantID: String?
    @State private var errorMessage: String?
    @State private var fallbackQuoteTask: Task<Void, Never>?

    init(activity: CollectionActivity) {
        self.activity = activity
        _variantID = State(initialValue: activity.variantID)
    }

    var body: some View {
        Form {
            Section("Recorded") {
                LabeledContent("Action", value: activity.kind.label)
                LabeledContent("Source", value: activity.source.label)
                LabeledContent(
                    "When",
                    value: activity.occurredAt.formatted(date: .abbreviated, time: .shortened)
                )
                LabeledContent("Game", value: activity.game.label)
                LabeledContent("Item Type", value: activity.itemKind.label)
                LabeledContent("Quantity", value: signedQuantity(activity.signedQuantity))
                LabeledContent("Entry status", value: activity.isResolved ? "Resolved" : "Open")
                if let correctedAt = activity.correctedAt {
                    LabeledContent(
                        "Last Corrected",
                        value: correctedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            if activity.kind.hasQuantityClaim, activity.itemKind == .rawCard {
                Section {
                    Picker("Finish", selection: $variantID) {
                        ForEach(PhysicalVariant.selectable(for: activity.game)) { variant in
                            Text(variant.label).tag(variant.id as String?)
                        }
                    }
                } header: {
                    Text("Correct Finish")
                } footer: {
                    Text("The correction applies to the copies claimed by this entry and is recorded in the ledger.")
                }
                .disabled(!canSave)
            } else {
                Section {
                    Text("This history entry records a completed collection action. It cannot be corrected again.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .alert("History Action Couldn’t Be Saved", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var canSave: Bool {
        activity.kind.hasQuantityClaim
            && activity.itemKind == .rawCard
            && activity.remainingQuantity > 0
            && variantID != nil
            && variantID != activity.variantID
            && collectionCard.map { $0.quantity >= activity.remainingQuantity } == true
            && CollectionStore(context: modelContext).hasValidLineage(
                activity.ledgerOperationIDs,
                for: activity.collectionKey,
                quantity: activity.claimedQuantity
            )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var collectionCard: CollectedCard? {
        let key = activity.collectionKey
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func save() {
        guard let card = collectionCard,
              let variantID else {
            errorMessage = "The collection entry is no longer available."
            return
        }
        let variant = PhysicalVariant.resolving(variantID)

        do {
            let store = CollectionStore(context: modelContext)
            guard let mutation = try store.recordVariantCorrection(
                for: card,
                to: ResolvedVariant(variant: variant, resolution: .userConfirmed),
                activityID: activity.id,
                quantity: activity.remainingQuantity
            )
            else {
                errorMessage = "This entry could not be corrected."
                return
            }
            if let correctedCard = store.card(forKey: mutation.collectionKey) {
                queueFallbackPrice(for: correctedCard)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func queueFallbackPrice(for card: CollectedCard) {
        // A correction can land on a destination row that already has a valid
        // observation. Leave it alone; the normal stale-target gate owns later
        // refreshes for that exact printing and finish.
        let prices = PriceStore(context: modelContext)
        let existing = prices.record(forKey: card.priceKey)
        let usesFallback = UserDefaults.standard.bool(forKey: "usesPriceFallback")
        guard !PriceRefreshController.hasFinishedPrice(
            amount: existing?.effectiveUnitMarketPriceUSD,
            currencyCode: existing?.currencyCode,
            usesFallback: usesFallback
        ), usesFallback, PriceVendorCredentials.hasKey else { return }

        fallbackQuoteTask?.cancel()
        let input = PriceFallbackCardInput(
            card: card,
            variant: card.variant,
            pokemonPrintRun: card.pokemonPrintRun
        )
        let fallbackContext = ModelContext(modelContext.container)
        let fallbackPrices = PriceStore(context: fallbackContext)
        let resolver = PriceFallbackQuoteResolver(context: fallbackContext)
        fallbackQuoteTask = Task { @MainActor in
            switch await resolver.resolve(input) {
            case let .lookup(quote):
                guard !Task.isCancelled else { return }
                let identityKey = ProductIdentity.key(
                    game: input.game,
                    printingID: input.printingID,
                    variantID: input.variant?.id,
                    treatmentIDs: input.treatmentIDs
                )
                let marketVariantID = ProductIdentityStore(context: fallbackContext)
                    .cachedVariantID(forKey: identityKey)
                fallbackPrices.store(
                    quote,
                    game: input.game,
                    printingID: input.printingID,
                    variantID: input.variant?.id,
                    marketVariantID: marketVariantID,
                    treatmentIDs: input.treatmentIDs
                )
                _ = fallbackPrices.save()
            case .failed:
                break
            }
        }
    }

    private func signedQuantity(_ quantity: Int) -> String {
        if quantity > 0 { return "+\(quantity)" }
        if quantity < 0 { return "−\(-quantity)" }
        return "—"
    }
}
