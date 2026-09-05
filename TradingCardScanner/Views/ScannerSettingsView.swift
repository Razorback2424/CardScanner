import AuthenticationServices
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Shared settings sheet for the app. The root stays deliberately short: each
/// category leads to a focused form instead of asking someone to scan every
/// low-frequency control before finding the one they need.
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
    @State private var csvImportProgress: CSVImportProgress?
    @State private var csvImportToken = UUID()
    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]
    @Query private var priceRecords: [PriceRecord]
    @Query private var artworkOverrides: [LocalArtworkOverride]

    private struct CSVMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let skippedCSVText: String?
        let failedCSVText: String?

        init(
            title: String,
            message: String,
            skippedCSVText: String?,
            failedCSVText: String? = nil
        ) {
            self.title = title
            self.message = message
            self.skippedCSVText = skippedCSVText
            self.failedCSVText = failedCSVText
        }
    }

    private struct CSVImportProgress: Equatable {
        let completedEntries: Int
        let totalEntries: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SettingsCategoryView("Scanning") {
                            cameraSection
                        }
                    } label: {
                        Label("Scanning", systemImage: "viewfinder")
                    }

                    NavigationLink {
                        SettingsCategoryView("Pricing") {
                            PriceFallbackSettingsSection()
                        }
                    } label: {
                        Label("Pricing", systemImage: "dollarsign.circle")
                    }

                    NavigationLink {
                        SettingsCategoryView("Collection & Portfolio") {
                            collectionSection
                            portfolioSection
                        }
                    } label: {
                        Label("Collection & Portfolio", systemImage: "rectangle.stack")
                    }

                    NavigationLink {
                        SettingsCategoryView("Account & Sync") {
                            AccountSettingsSection()
                        }
                    } label: {
                        Label("Account & Sync", systemImage: "person.crop.circle")
                    }
                }

                Section("Advanced") {
                    NavigationLink {
                        SettingsCategoryView("Developer & Diagnostics") {
                            developerSection
                        }
                    } label: {
                        Label("Developer & Diagnostics", systemImage: "wrench.and.screwdriver")
                    }
                }
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
                if let failedCSVText = message.failedCSVText {
                    return Alert(title: Text(message.title), message: Text(message.message), primaryButton: .default(Text("Export Failed Rows")) {
                        csvExportDocument = CollectionCSVDocument(text: failedCSVText)
                        csvExportFilename = "CardScanner Failed Import Rows"
                        isShowingCSVExporter = true
                    }, secondaryButton: .cancel(Text("Done")))
                }
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
            if let progress = csvImportProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                        Text("Importing collection…")
                    }
                    ProgressView(
                        value: Double(progress.completedEntries),
                        total: Double(max(1, progress.totalEntries))
                    )
                    Text("Saved " + String(progress.completedEntries) + " of " + String(progress.totalEntries) + " entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importing collection")
                .accessibilityValue("\(progress.completedEntries) of \(progress.totalEntries) entries saved")
            }

            Button("Import CSV", systemImage: "square.and.arrow.down") {
                isShowingCSVImporter = true
            }
            .disabled(csvImportProgress != nil)

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

    /// Read-only in Phase 1, deliberately.
    ///
    /// A mutable timezone setting would recompute old boundaries and rewrite
    /// months of already-published closes — the numbers changing underneath
    /// someone because they changed a preference is precisely the failure this
    /// feature exists to prevent. A permanent relocation is handled later by
    /// timezone *epochs* ("Mountain through Dec 31 · Eastern from Jan 1"),
    /// never by reinterpreting days that have already been published.
    private var portfolioSection: some View {
        Section {
            LabeledContent("Day boundary", value: portfolioTimeZoneLabel)
            if let started = portfolioStartedAt {
                LabeledContent(
                    "Tracking since",
                    value: started.formatted(date: .abbreviated, time: .omitted)
                )
            }

            Button("Export Value History", systemImage: "square.and.arrow.up") {
                do {
                    csvExportDocument = CollectionCSV.exportPortfolioHistory(
                        try PortfolioEngine.allCloses(in: modelContext)
                    )
                    csvExportFilename = "CardScanner Value History"
                    isShowingCSVExporter = true
                } catch {
                    csvMessage = CSVMessage(
                        title: "Export Failed",
                        message: error.localizedDescription,
                        skippedCSVText: nil
                    )
                }
            }
            .disabled(portfolioCloseCount == 0)
        } header: {
            Text("Portfolio")
        } footer: {
            Text("Daily closes are measured in the time zone tracking started in, and stay on this device. Export keeps a copy you own.")
        }
    }

    private var portfolioTimeZoneLabel: String {
        let zone = PortfolioCalendar.pinnedTimeZone() ?? .current
        return zone.identifier.replacingOccurrences(of: "_", with: " ")
    }

    private var portfolioStartedAt: Date? {
        PortfolioEpoch.startedAt(context: modelContext)
    }

    private var portfolioCloseCount: Int {
        (try? PortfolioEngine.allCloses(in: modelContext).count) ?? 0
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
                    csvExportDocument = CollectionCSV.exportMissingArtwork(
                        cards,
                        priceRecords: priceRecords,
                        localArtworkKeys: Set(artworkOverrides.map(\.collectionKey))
                    )
                    csvExportFilename = "CardScanner Missing Artwork"
                    isShowingCSVExporter = true
                }
                .disabled(!cards.contains { $0.highImageURL == nil })

#if DEBUG
                Button("Run Overnight Price Refresh", systemImage: "moon.stars") {
                    Task {
                        await BackgroundPriceRefresh.run(.processing, allowsForeground: true)
                    }
                }
                .disabled(cards.isEmpty)
#endif
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
        guard csvImportProgress == nil else { return }
        pendingCSVImport = nil
        let container = modelContext.container
        let token = UUID()
        csvImportToken = token
        csvImportProgress = CSVImportProgress(
            completedEntries: 0,
            totalEntries: plan.entries.count
        )
        Task { @MainActor in
            defer {
                if csvImportToken == token {
                    // Progress callbacks are delivered through unstructured
                    // MainActor tasks from the isolated importer. Invalidate
                    // the token before clearing the row so a final queued
                    // callback cannot resurrect an "in progress" state after
                    // completion has already been published.
                    csvImportToken = UUID()
                    csvImportProgress = nil
                }
            }
            do {
                let result = try await CollectionCSV.applyIsolated(
                    plan,
                    to: container,
                    progress: { completedEntries, totalEntries in
                        Task { @MainActor in
                            guard csvImportToken == token else { return }
                            csvImportProgress = CSVImportProgress(
                                completedEntries: completedEntries,
                                totalEntries: totalEntries
                            )
                        }
                    }
                )
                Task { await catalogNormalizer.normalizeImportedCards(in: container) }
                var details = "Added \(result.importedQuantity) cards across \(result.insertedEntries + result.mergedEntries) entries."
                if result.mergedEntries > 0 { details += " \(result.mergedEntries) matched existing entries." }
                if result.skippedRows > 0 { details += " Ignored \(result.skippedRows) unsupported, non-English, or non-card rows." }
                if !result.failedRows.isEmpty {
                    details += " Could not import \(result.failedRows.count) entries. Export the failed rows to retry only those entries."
                }
                details += " Artwork loads automatically. Refresh prices when you're ready."
                csvMessage = CSVMessage(
                    title: result.failedRows.isEmpty ? "Import Complete" : "Import Partially Complete",
                    message: details,
                    skippedCSVText: result.failedRows.isEmpty ? plan.skippedCSVText : nil,
                    failedCSVText: result.failedEntries.isEmpty
                        ? nil
                        : CollectionCSV.exportFailedEntries(result.failedEntries).text
                )
            } catch {
                csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription, skippedCSVText: nil)
            }
        }
    }

    private func importConfirmationMessage(_ plan: CollectionCSVImportPlan) -> String {
        var message = "Adds \(plan.totalQuantity) cards in \(plan.entries.count) entries. Matching entries will be combined."
        if plan.skippedRows > 0 { message += " \(plan.skippedRows) unsupported, non-English, or non-card rows will be ignored." }
        return message
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

private struct SettingsCategoryView<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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

        Section {
            LabeledContent(
                "Background App Refresh",
                value: BackgroundPriceRefresh.availability.label
            )

            if let detail = BackgroundPriceRefresh.availability.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Automatic Price Refresh")
        } footer: {
            Text("Price updates run overnight when iOS permits background work.")
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

/// Sign in with Apple, kept deliberately as the only account option. It gates
/// whether the app attempts its cloud-backed configuration; the private
/// CloudKit database itself follows the device's iCloud account.
///
/// Whether the *store* SwiftData hands the app is CloudKit-backed is decided
/// once per launch, in `TradingCardScannerApp.makeContainer()`, and the
/// selected mode is shown below. Signing in or out here only updates the gate —
/// it cannot swap the live store underneath the running app, so both directions
/// say "restart" rather than silently doing nothing.
struct AccountSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignedIn = AppleAccountCredentials.isSignedIn
    @State private var displayName = AppleAccountCredentials.displayName
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Section {
            LabeledContent(
                "Collection storage",
                value: TradingCardScannerApp.activeStorageMode.label
            )
            Text(TradingCardScannerApp.activeStorageMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
#if LOCAL_ONLY_SIGNING
            // Sign in with Apple and iCloud need a paid Apple Developer Program
            // membership to provision. Offering the button in a build that
            // cannot use it would only produce an error on tap.
            Text("Everything stays on this device in this build. iCloud sync needs a paid Apple Developer Program membership to sign.")
                .font(.footnote)
                .foregroundStyle(.secondary)
#else
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
#endif
        } header: {
            Text("Account")
        } footer: {
#if LOCAL_ONLY_SIGNING
            Text("Your collection is stored locally and is not backed up by this app.")
#else
            if TradingCardScannerApp.activeStorageMode.isCloudSyncing {
                Text("Collection sync uses this device's iCloud account. Sign in with Apple only controls whether the cloud-backed configuration is attempted; restart after changing that sign-in state.")
            } else if isSignedIn {
                Text("Sign in with Apple is saved, but this launch is using local storage. Restart after checking iCloud and app provisioning to try the cloud-backed configuration again.")
            } else {
                Text("Optional. Sign in with Apple to allow a cloud-backed configuration on the next launch. The actual iCloud account is the device's iCloud account; signed-out use stays on this device.")
            }
#endif
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
                statusMessage = "Signed in. Restart the app to re-evaluate collection storage."
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
        statusMessage = "Signed out. Restart the app to re-evaluate collection storage."
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
        statusMessage = "Your Apple ID sign-in was revoked. Restart the app to re-evaluate collection storage."
    }
}
