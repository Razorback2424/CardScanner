import SwiftUI

/// Creating unverified reports stays off in TestFlight and App Store builds
/// until the CloudKit schema is deployed and the two-device and pre-feature
/// build acceptance in the plan pass. Existing report rows are always
/// displayed and protected, whatever this says.
enum UnverifiedReportsFeature {
    static var isEnabled: Bool {
        #if DEBUG
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
            }
            .accessibilityElement(children: .combine)
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
            return "The catalog changed. Review this card to link it."
        case .linkUnavailable?:
            return "Not priced. Linking isn't available because some copies were removed or adjusted."
        case .waiting?, nil:
            return "Not priced. Waiting for the catalog to list it."
        }
    }
}
