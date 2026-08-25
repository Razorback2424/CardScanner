import SwiftData
import SwiftUI

/// Shared settings sheet for the app. Built as a `Form` from the start so that adding
/// the next setting is a new row rather than a layout rewrite.
struct SettingsView: View {
    @EnvironmentObject private var scannerModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingCollectionDeletion = false
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            Form {
                finishLockSection
                cameraSection
                PriceFallbackSettingsSection()
                collectionSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete entire collection?",
                isPresented: $isConfirmingCollectionDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    deleteCollection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every card in your collection.")
            }
            .alert("Collection Couldn’t Be Deleted", isPresented: deletionErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionError ?? "Please try again.")
            }
        }
    }

    private var collectionSection: some View {
        Section("Collection") {
            NavigationLink {
                CollectionActivityLogView()
            } label: {
                Label("Review Activity", systemImage: "clock.arrow.circlepath")
            }

            Button("Delete Entire Collection", role: .destructive) {
                isConfirmingCollectionDeletion = true
            }
        }
    }

    /// Contextual evidence the user already has: a stack of reverses really is a
    /// stack of reverses. Set here rather than on the camera because it is a
    /// property of the pile being worked through, not of the card in frame.
    ///
    /// One lock per game. The scanner no longer knows which game is coming next,
    /// so a single shared lock would either be wrong half the time or would have
    /// to be re-set every time the pile changed game.
    private var finishLockSection: some View {
        Section {
            ForEach(CardGame.allCases) { game in
                Picker(game.label, selection: lockBinding(for: game)) {
                    Text("Auto").tag(PhysicalVariant?.none)
                    ForEach(PhysicalVariant.selectable(for: game)) { variant in
                        Text(variant.label).tag(PhysicalVariant?.some(variant))
                    }
                }
            }
        } header: {
            Text("Finish Lock")
        } footer: {
            Text("On Auto, a card whose finish cannot be determined asks for one tap. A lock answers that question in advance — but only where the catalog agrees the finish is physically possible, so it can never record a variant that was never printed.")
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        Section {
            if scannerModel.scanner.availableLenses.count > 1 {
                Picker("Lens", selection: lensBinding) {
                    ForEach(scannerModel.scanner.availableLenses) { lens in
                        Text(lens.label).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                LabeledContent("Lens", value: scannerModel.scanner.lens.label)
            }
        } header: {
            Text("Camera")
        } footer: {
            if scannerModel.scanner.availableLenses.contains(.macro) {
                Text("Macro uses the ultra wide lens, which focuses down to a few centimetres. The standard lens cannot focus close enough to read a card's set code.")
            } else {
                Text("This device has no ultra wide camera that can focus close, so only the standard lens is available.")
            }
        }
    }

    private func lockBinding(for game: CardGame) -> Binding<PhysicalVariant?> {
        Binding(
            get: { scannerModel.finishLock(for: game) },
            set: { scannerModel.setFinishLock($0, for: game) }
        )
    }

    /// `scanner.lens` is `private(set)` and only changes once the capture session has
    /// actually swapped inputs, so the picker writes through `setLens` and reads back
    /// the hardware's answer rather than holding its own selection state.
    private var lensBinding: Binding<CameraLens> {
        Binding(
            get: { scannerModel.scanner.lens },
            set: { scannerModel.scanner.setLens($0) }
        )
    }

    private var deletionErrorBinding: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )
    }

    private func deleteCollection() {
        do {
            try CollectionStore(context: modelContext).deleteAll()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

/// Shared between Scan settings and Collection so the fallback can be managed
/// where its results and remaining work are visible.
struct PriceFallbackSettingsSection: View {
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var vendorKeyEntry = ""
    @State private var hasVendorKey = PriceVendorCredentials.hasKey
    @State private var vendorKeyMessage: String?
    @State private var vendorKeyMessageIsError = false

    var body: some View {
        Section {
            Toggle("Use price fallback", isOn: $usesPriceFallback)
                .disabled(!hasVendorKey)

            SecureField("API key", text: $vendorKeyEntry)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            HStack {
                Button("Save Key") { saveVendorKey() }
                    .disabled(vendorKeyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if hasVendorKey {
                    Button("Remove", role: .destructive) { removeVendorKey() }
                }
            }

            if let vendorKeyMessage {
                Text(vendorKeyMessage)
                    .font(.footnote)
                    .foregroundStyle(vendorKeyMessageIsError ? .red : .secondary)
            }
        } header: {
            Text("Price Fallback")
        } footer: {
            Text(hasVendorKey
                 ? "A key is saved in your keychain. Free-tier safety limits vendor traffic to 95 requests per UTC day; automatic price work stops at 75 to reserve 20 for sealed products and other direct actions."
                 : "Optional. Adds prices for cards TCGdex and Scryfall don't cover, such as Japanese sets, promos, tokens and art cards.")
        }
    }

    private func saveVendorKey() {
        do {
            try PriceVendorCredentials.store(vendorKeyEntry)
            // Never keep the value in view state after it is stored.
            vendorKeyEntry = ""
            hasVendorKey = PriceVendorCredentials.hasKey
            vendorKeyMessageIsError = false
            vendorKeyMessage = "Key saved to keychain."
        } catch {
            vendorKeyMessageIsError = true
            vendorKeyMessage = error.localizedDescription
        }
    }

    private func removeVendorKey() {
        PriceVendorCredentials.remove()
        vendorKeyEntry = ""
        hasVendorKey = false
        usesPriceFallback = false
        vendorKeyMessageIsError = false
        vendorKeyMessage = "Key removed."
    }

}
