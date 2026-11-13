import SwiftData
import SwiftUI

/// Creating unverified reports stays off in TestFlight and App Store builds
/// until the CloudKit schema is deployed and the two-device and pre-feature
/// build acceptance in the plan pass. Existing report rows are always
/// displayed and protected, whatever this says.
///
/// Besides DEBUG builds, only the optimized on-device `ReleaseLocal`
/// configuration (ProfileLocal) turns it on, through
/// `UNVERIFIED_REPORTS_LOCAL_BETA`. That flag also requires the local-only
/// signing and no-CloudKit conditions, so it cannot take effect in a
/// CloudKit-entitled or distributed build even if set by mistake.
enum UnverifiedReportsFeature {
    static var isEnabled: Bool {
        #if DEBUG
        return true
        #elseif UNVERIFIED_REPORTS_LOCAL_BETA && LOCAL_ONLY_SIGNING && NO_CLOUDKIT
        return true
        #else
        return false
        #endif
    }
}

/// The collector's description of a card the catalog doesn't list yet.
struct UnverifiedReportForm: View {
    enum Mode {
        /// The printing is known; only its variant is missing.
        case knownCard(baseProviderID: String, cardName: String)
        /// The set or number isn't in the catalog. Prefilled from the scan.
        case unknownSet(UnverifiedReport.ObservedIdentity)
    }

    let mode: Mode
    let allowsQuantity: Bool
    /// Returns an error message, or `nil` when the report was saved.
    let onSave: (UnverifiedReport, Int) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var finishID: String?
    @State private var stamp = ""
    @State private var note = ""
    @State private var setCode = ""
    @State private var setName = ""
    @State private var number = ""
    @State private var name = ""
    @State private var quantity = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, allowsQuantity: Bool, onSave: @escaping (UnverifiedReport, Int) async -> String?) {
        self.mode = mode
        self.allowsQuantity = allowsQuantity
        self.onSave = onSave
        if case let .unknownSet(observed) = mode {
            _setCode = State(initialValue: observed.setCode)
            _setName = State(initialValue: observed.setName ?? "")
            _number = State(initialValue: observed.number)
            _name = State(initialValue: observed.name ?? "")
        } else {
            _finishID = State(initialValue: PhysicalVariant.holo.id)
        }
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var report: UnverifiedReport? {
        switch mode {
        case let .knownCard(baseProviderID, _):
            let described = Self.trimmed(note)
            guard finishID != nil || !described.isEmpty else { return nil }
            let stampID = Self.trimmed(stamp).lowercased().replacingOccurrences(of: " ", with: "-")
            return UnverifiedReport(kind: .knownCard, baseProviderID: baseProviderID, reportedFinishID: finishID,
                                    reportedStamps: stampID.isEmpty ? [] : [stampID],
                                    note: described.isEmpty ? nil : described)
        case .unknownSet:
            let code = Self.trimmed(setCode), printed = Self.trimmed(number)
            guard !code.isEmpty, !printed.isEmpty else { return nil }
            let set = Self.trimmed(setName), cardName = Self.trimmed(name)
            return UnverifiedReport(kind: .unknownSet, observed: .init(setCode: code, setName: set.isEmpty ? nil : set,
                                                                      number: printed, name: cardName.isEmpty ? nil : cardName))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case let .knownCard(_, cardName):
                    Section {
                        Picker("Finish", selection: $finishID) {
                            ForEach(PokemonVariantPolicy().selectableVariants) { variant in
                                Text(variant.label).tag(Optional(variant.id))
                            }
                            Text("Other (describe)").tag(String?.none)
                        }
                        TextField("Stamp, if any", text: $stamp)
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text(cardName)
                    }
                    Section(finishID == nil ? "Describe it" : "Note (optional)") {
                        TextField("What makes this copy different", text: $note, axis: .vertical)
                    }
                case .unknownSet:
                    Section("As printed on the card") {
                        TextField("Set code", text: $setCode)
                            .textInputAutocapitalization(.characters)
                        TextField("Number", text: $number)
                            .keyboardType(.numbersAndPunctuation)
                        TextField("Set name (optional)", text: $setName)
                        TextField("Card name (optional)", text: $name)
                    }
                }
                if allowsQuantity {
                    Section {
                        Stepper("Quantity: \(quantity)", value: $quantity, in: 1...CollectionQuantityLimits.maximum)
                    }
                }
                Section {
                    Text("Saved as Unverified, with no price. Scan Stash won't change it automatically. When the catalog lists this card, it's linked to the verified card, or you're asked to confirm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Unverified card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(report == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        guard let report, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let failure = await onSave(report, quantity)
            isSaving = false
            if let failure { errorMessage = failure } else { dismiss() }
        }
    }
}

/// What a collection row's report says, shown on its detail screen.
struct UnverifiedReportStatus: View {
    let card: CollectedCard
    let isWritePending: Bool
    let onUndoLink: () -> Void
    /// Opens the catalog to choose the verified card this report is.
    let onLink: () -> Void
    /// Dismisses a review and keeps the report waiting for the catalog.
    let onKeepUnverified: () -> Void

    var body: some View {
        if card.isUnverified {
            VStack(spacing: 4) {
                Label("Unverified · \(card.unverifiedReport?.label ?? card.variantLabel ?? "Unlisted variant")",
                      systemImage: "questionmark.diamond")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let report = card.unverifiedReport, report.isUnderstood, report.reviewState != .linkUnavailable {
                    Button("Link to verified card…", systemImage: "link", action: onLink)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(isWritePending)
                        .accessibilityIdentifier("unverified-report-link")
                    if report.reviewState == .needsReview {
                        Button("Keep as unverified", action: onKeepUnverified)
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                            .disabled(isWritePending)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("unverified-report-status")
        } else if card.hasReport {
            VStack(spacing: 4) {
                Label("From your report, now verified", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                if let report = card.unverifiedReport, report.linkedAt != nil, report.preLinkIdentity != nil {
                    Button("Undo link", action: onUndoLink)
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(isWritePending)
                } else {
                    Text("This report can't be read by this version, so the link can't be undone here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityIdentifier("linked-report-status")
        }
    }

    private var detail: String {
        guard let report = card.unverifiedReport else {
            return "This report can't be read by this version. It stays unpriced and unchanged."
        }
        switch report.reviewState {
        case .needsReview?:
            return "The catalog changed. Choose the verified card to link it, or keep it unverified."
        case .linkUnavailable?:
            return "Not priced. Linking isn't available because some copies were removed or adjusted."
        case .waiting?, nil:
            return "Not priced. Waiting for the catalog to list it."
        }
    }
}

/// Every unverified or linked report in the collection, so a report that
/// needs the collector's confirmation is always reachable.
struct UnverifiedReportsListView: View {
    let onSelect: (String) -> Void
    @Query private var rows: [CollectedCard]

    init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        let unverified = UnverifiedReportKey.unverifiedMarker
        _rows = Query(filter: #Predicate<CollectedCard> { $0.collectionKey.contains(unverified) },
                      sort: \CollectedCard.dateAdded, order: .reverse)
    }

    private var needsReview: [CollectedCard] {
        rows.filter { $0.unverifiedReport?.reviewState == .needsReview }
    }

    var body: some View {
        List {
            if !needsReview.isEmpty {
                Section("Needs your review") { ForEach(needsReview) { row($0) } }
            }
            let others = rows.filter { $0.unverifiedReport?.reviewState != .needsReview }
            if !others.isEmpty {
                Section("Waiting for the catalog") { ForEach(others) { row($0) } }
            }
            if rows.isEmpty {
                ContentUnavailableView("No unverified cards", systemImage: "checkmark.seal")
            }
        }
        .navigationTitle("Unverified cards")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ card: CollectedCard) -> some View {
        Button { onSelect(card.collectionKey) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name.isEmpty ? "Unknown card" : card.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text([card.setCode, card.cardNumber, card.unverifiedReport?.label ?? card.variantLabel]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Quantity \(card.quantity)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Evaluates unverified reports for the whole app, not only while the scanner
/// is open: at launch, after every Pokémon catalog activation, and when synced
/// rows arrive from another device.
struct UnverifiedReportReconciliationMonitor: View {
    @Environment(\.modelContext) private var modelContext
    let coordinator: PokemonCatalogCoordinator?
    @State private var remoteChanges: UInt = 0

    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: RunLoop.main)) { _ in remoteChanges &+= 1 }
            .task(id: remoteChanges) {
                // Coalesce a burst of synced rows into one pass.
                if remoteChanges > 0 { try? await Task.sleep(for: .seconds(2)) }
                guard !Task.isCancelled, let coordinator else { return }
                await coordinator.loadPersistedOrBundled()
                await reconcile(registry: await coordinator.registry)
            }
            .task {
                guard let coordinator else { return }
                for await event in await coordinator.activationEvents() {
                    guard !Task.isCancelled else { return }
                    await reconcile(registry: event.registry)
                }
            }
    }

    private func reconcile(registry: PokemonCatalogRegistry) async {
        guard UnverifiedReportsFeature.isEnabled else { return }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let writer = await ScannerCollectionWriter.makeBackground(modelContainer: modelContext.container)
        guard generation.isCurrent(token) else { return }
        _ = try? await UnverifiedReportReconciler.catalogBacked(writer: writer, registry: registry,
                                                                catalog: CardCatalog(registry: registry))
            .run(catalogRevision: registry.revision)
    }
}
