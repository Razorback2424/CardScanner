import AuthenticationServices
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Shared settings sheet for the app. Built as a `Form` from the start so that adding
/// the next setting is a new row rather than a layout rewrite.
struct SettingsView: View {
    @EnvironmentObject private var scannerModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingCollectionDeletion = false
    @State private var deletionError: String?
    @State private var isShowingCSVImporter = false
    @State private var isShowingCSVExporter = false
    @State private var csvExportDocument: CollectionCSVDocument?
    @State private var csvExportFilename = "CardScanner Collection"
    @State private var pendingCSVImport: CollectionCSVImportPlan?
    @State private var csvMessage: CSVMessage?
    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]
    @Query private var priceRecords: [PriceRecord]

    private struct CSVMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let skippedCSVText: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                AccountSettingsSection()
                finishLockSection
                cameraSection
                PriceFallbackSettingsSection()
                collectionSection
                developerSection
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
            .fileImporter(isPresented: $isShowingCSVImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                switch result {
                case let .success(url): Task { await prepareCSVImport(from: url) }
                case let .failure(error): csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription, skippedCSVText: nil)
                }
            }
            .fileExporter(isPresented: $isShowingCSVExporter, document: csvExportDocument, contentType: .commaSeparatedText, defaultFilename: csvExportFilename) { result in
                csvExportDocument = nil
                if case let .failure(error) = result {
                    csvMessage = CSVMessage(title: "Export Failed", message: error.localizedDescription, skippedCSVText: nil)
                }
            }
            .confirmationDialog("Import CSV?", isPresented: Binding(get: { pendingCSVImport != nil }, set: { if !$0 { pendingCSVImport = nil } }), titleVisibility: .visible) {
                if let plan = pendingCSVImport {
                    Button("Import \(plan.totalQuantity) Cards") { importCSV(plan) }
                }
                Button("Cancel", role: .cancel) { pendingCSVImport = nil }
            } message: {
                if let plan = pendingCSVImport { Text(importConfirmationMessage(plan)) }
            }
            .alert(item: $csvMessage) { message in
                if let skippedCSVText = message.skippedCSVText {
                    return Alert(title: Text(message.title), message: Text(message.message), primaryButton: .default(Text("Export Skipped Rows")) {
                        csvExportDocument = CollectionCSVDocument(text: skippedCSVText)
                        csvExportFilename = "CardScanner Skipped Rows"
                        isShowingCSVExporter = true
                    }, secondaryButton: .cancel(Text("Done")))
                }
                return Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var collectionSection: some View {
        Section("Collection") {
            Button("Import CSV", systemImage: "square.and.arrow.down") {
                isShowingCSVImporter = true
            }

            Button("Export CSV", systemImage: "square.and.arrow.up") {
                csvExportDocument = CollectionCSV.export(cards)
                csvExportFilename = "CardScanner Collection"
                isShowingCSVExporter = true
            }
            .disabled(cards.isEmpty)

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

    private var developerSection: some View {
        Section {
            DisclosureGroup("Developer") {
                Button("Export Unpriced Cards", systemImage: "dollarsign.circle") {
                    csvExportDocument = CollectionCSV.exportUnpriced(cards, priceRecords: priceRecords)
                    csvExportFilename = "CardScanner Unpriced Cards"
                    isShowingCSVExporter = true
                }
                .disabled(priceRecords.isEmpty)

                Button("Export Missing Artwork", systemImage: "photo") {
                    csvExportDocument = CollectionCSV.exportMissingArtwork(cards, priceRecords: priceRecords)
                    csvExportFilename = "CardScanner Missing Artwork"
                    isShowingCSVExporter = true
                }
                .disabled(!cards.contains { $0.highImageURL == nil })
            }
        }
    }

    @MainActor
    private func prepareCSVImport(from url: URL) async {
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                return try CollectionCSV.parse(Data(contentsOf: url, options: .mappedIfSafe))
            }.value
            pendingCSVImport = plan
        } catch {
            csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription, skippedCSVText: nil)
        }
    }

    @MainActor
    private func importCSV(_ plan: CollectionCSVImportPlan) {
        pendingCSVImport = nil
        do {
            let result = try CollectionCSV.apply(plan, to: modelContext)
            Task { await catalogNormalizer.normalizeImportedCards(in: modelContext) }
            var details = "Added \(result.totalQuantity) cards across \(result.insertedEntries + result.mergedEntries) entries."
            if result.mergedEntries > 0 { details += " \(result.mergedEntries) matched existing entries." }
            if result.skippedRows > 0 { details += " Ignored \(result.skippedRows) unsupported, non-English, or non-card rows." }
            details += " Artwork loads automatically. Refresh prices when you're ready."
            csvMessage = CSVMessage(title: "Import Complete", message: details, skippedCSVText: plan.skippedCSVText)
        } catch {
            csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription, skippedCSVText: nil)
        }
    }

    private func importConfirmationMessage(_ plan: CollectionCSVImportPlan) -> String {
        var message = "Adds \(plan.totalQuantity) cards in \(plan.entries.count) entries. Matching entries will be combined."
        if plan.skippedRows > 0 { message += " \(plan.skippedRows) unsupported, non-English, or non-card rows will be ignored." }
        return message
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

/// Sign in with Apple, kept deliberately as the only account option. It exists
/// to answer one question — should this collection sync to iCloud, or stay
/// local-only — not to build a user-account system the app otherwise has no
/// use for.
///
/// Whether the *store* SwiftData hands the app is CloudKit-backed is decided
/// once per launch, in `TradingCardScannerApp.makeContainer()`, from
/// `AppleAccountCredentials.isSignedIn`. Signing in or out here only updates
/// that stored state — it cannot swap the live store underneath the running
/// app, so both directions say "restart" rather than silently doing nothing.
struct AccountSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignedIn = AppleAccountCredentials.isSignedIn
    @State private var displayName = AppleAccountCredentials.displayName
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Section {
            if isSignedIn {
                LabeledContent("Signed in as", value: displayName ?? "Apple ID")
                Button("Sign Out", role: .destructive) { signOut() }
            } else {
                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets())
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
        } header: {
            Text("Account")
        } footer: {
            Text(isSignedIn
                 ? "Your collection syncs to iCloud under this Apple ID. If you just signed in, restart the app to start syncing."
                 : "Optional. Sign in to back up your collection and sync it across your devices with iCloud. Everything works fully signed out — it just stays on this device.")
        }
        .task { await refreshCredentialState() }
    }

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only ever returns the name on the *first* authorization for
            // this app; a resumed sign-in on a later launch won't have it.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            do {
                try AppleAccountCredentials.store(
                    userIdentifier: credential.user,
                    displayName: name.isEmpty ? nil : name
                )
                isSignedIn = true
                displayName = AppleAccountCredentials.displayName
                statusIsError = false
                statusMessage = "Signed in. Restart the app to start syncing to iCloud."
            } catch {
                statusIsError = true
                statusMessage = error.localizedDescription
            }
        case let .failure(error):
            // The person dismissing the sheet arrives here as an error too —
            // that's not something worth reporting as a failure.
            let nsError = error as NSError
            guard nsError.domain == ASAuthorizationError.errorDomain,
                  nsError.code == ASAuthorizationError.canceled.rawValue else {
                statusIsError = true
                statusMessage = error.localizedDescription
                return
            }
        }
    }

    private func signOut() {
        AppleAccountCredentials.clear()
        isSignedIn = false
        displayName = nil
        statusIsError = false
        statusMessage = "Signed out. Restart the app to finish turning sync off."
    }

    /// Sign-in with Apple can be revoked from the device's Settings app at any
    /// time, entirely outside this app. Checking here is what keeps "Signed
    /// in" from lying after that happens instead of only finding out the next
    /// time a sync attempt silently fails.
    private func refreshCredentialState() async {
        guard let userIdentifier = AppleAccountCredentials.userIdentifier else { return }
        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { state, _ in
                continuation.resume(returning: state)
            }
        }
        guard state == .revoked || state == .notFound else { return }
        AppleAccountCredentials.clear()
        isSignedIn = false
        displayName = nil
        statusIsError = true
        statusMessage = "Your Apple ID sign-in was revoked. Restart the app to finish turning sync off."
    }
}
