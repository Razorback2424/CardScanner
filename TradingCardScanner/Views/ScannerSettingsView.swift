import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shared settings sheet for the app. The root stays deliberately short: each
/// category leads to a focused form instead of asking someone to scan every
/// low-frequency control before finding the one they need.
struct SettingsView: View {
    @EnvironmentObject private var scannerModel: ScannerViewModel
    @EnvironmentObject private var writeCoordinator: DerivedStateWriteCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var storageGeneration = CollectionStorageGeneration.shared
    @State private var isConfirmingCollectionDeletion = false
    @State private var deletionError: String?
    @State private var isShowingCSVImporter = false
    @State private var isShowingCSVExporter = false
    @State private var isShowingDiagnosticsExporter = false
    @State private var csvExportDocument: CollectionCSVDocument?
    @State private var diagnosticsDocument: JSONExportDocument?
    @State private var csvExportFilename = "CardScanner Collection"
    @State private var pendingCSVImport: CollectionCSVImportPlan?
    @State private var csvMessage: CSVMessage?
    @State private var csvImportProgress: CSVImportProgress?
    @State private var csvImportToken = UUID()
    @State private var portfolioCloseCount = 0
    @State private var collectionCardCount = 0
    @State private var priceRecordCount = 0
    @State private var missingArtworkCount = 0
    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()

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
                        SettingsCategoryView("Collection Storage") {
                            CollectionStorageStatusSection()
                        }
                    } label: {
                        Label("Collection Storage", systemImage: "externaldrive.icloud")
                    }

                    NavigationLink {
                        PrivacyAndSupportSettingsView()
                    } label: {
                        Label("Privacy & Support", systemImage: "hand.raised")
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
            .task { loadCounts() }
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
            // Two `fileExporter` modifiers on the same view silently collapse
            // into one: only the last one applied ever presents, so stacking
            // them here left every CSV export doing nothing at all. Hosting
            // the diagnostics exporter on its own empty background view keeps
            // each exporter attached to a distinct view.
            .background {
                Color.clear
                    .fileExporter(
                        isPresented: $isShowingDiagnosticsExporter,
                        document: diagnosticsDocument,
                        contentType: .json,
                        defaultFilename: "CardScanner Sync Diagnostics"
                    ) { result in
                        diagnosticsDocument = nil
                        if case let .failure(error) = result {
                            csvMessage = CSVMessage(
                                title: "Export Failed",
                                message: error.localizedDescription,
                                skippedCSVText: nil
                            )
                        }
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
                do {
                    let cards = try modelContext.fetch(FetchDescriptor<CollectedCard>())
                    csvExportDocument = CollectionCSV.export(cards)
                    csvExportFilename = "CardScanner Collection"
                    isShowingCSVExporter = true
                } catch {
                    csvMessage = CSVMessage(
                        title: "Export Failed",
                        message: error.localizedDescription,
                        skippedCSVText: nil
                    )
                }
            }
            .disabled(collectionCardCount == 0)

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
        PortfolioEpoch.startedAt()
    }

    /// These counts only drive export affordances. Resolve them once when the
    /// settings surface appears instead of synchronously querying SwiftData
    /// every time a preference or disclosure state redraws the form.
    private func loadCounts() {
        portfolioCloseCount = (try? modelContext.fetchCount(
            FetchDescriptor<PortfolioDailyClose>()
        )) ?? 0
        collectionCardCount = (try? modelContext.fetchCount(
            FetchDescriptor<CollectedCard>()
        )) ?? 0
        priceRecordCount = (try? modelContext.fetchCount(
            FetchDescriptor<PriceRecord>()
        )) ?? 0
        missingArtworkCount = (try? modelContext.fetchCount(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { $0.imageURL == nil }
            )
        )) ?? 0
    }

    private var developerSection: some View {
        Section {
            DisclosureGroup("Developer") {
                Button("Export Unpriced Cards", systemImage: "dollarsign.circle") {
                    do {
                        let cards = try modelContext.fetch(FetchDescriptor<CollectedCard>())
                        let priceRecords = try modelContext.fetch(FetchDescriptor<PriceRecord>())
                        csvExportDocument = CollectionCSV.exportUnpriced(cards, priceRecords: priceRecords)
                        csvExportFilename = "CardScanner Unpriced Cards"
                        isShowingCSVExporter = true
                    } catch {
                        csvMessage = CSVMessage(
                            title: "Export Failed",
                            message: error.localizedDescription,
                            skippedCSVText: nil
                        )
                    }
                }
                .disabled(collectionCardCount == 0)

                Button("Export Missing Artwork", systemImage: "photo") {
                    do {
                        let cards = try modelContext.fetch(FetchDescriptor<CollectedCard>())
                        let priceRecords = try modelContext.fetch(FetchDescriptor<PriceRecord>())
                        let artworkOverrides = try modelContext.fetch(
                            FetchDescriptor<LocalArtworkOverride>()
                        )
                        csvExportDocument = CollectionCSV.exportMissingArtwork(
                            cards,
                            priceRecords: priceRecords,
                            localArtworkKeys: Set(artworkOverrides.map(\.collectionKey))
                        )
                        csvExportFilename = "CardScanner Missing Artwork"
                        isShowingCSVExporter = true
                    } catch {
                        csvMessage = CSVMessage(
                            title: "Export Failed",
                            message: error.localizedDescription,
                            skippedCSVText: nil
                        )
                    }
                }
                .disabled(missingArtworkCount == 0)

#if DEBUG
                Button("Run Overnight Price Refresh", systemImage: "moon.stars") {
                    Task {
                        await BackgroundPriceRefresh.run(.processing, allowsForeground: true)
                    }
                }
                .disabled(collectionCardCount == 0)
#endif

                Button("Export Sync Diagnostics", systemImage: "waveform.path.ecg") {
                    exportSyncDiagnostics()
                }
                .disabled(!TradingCardScannerApp.storageIsReady)
                Text("Redacted diagnostic data for support. It does not include card names, collection contents, credentials, or images.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportSyncDiagnostics() {
        guard TradingCardScannerApp.storageIsReady,
              let storeID = TradingCardScannerApp.activeStoreID else {
            csvMessage = CSVMessage(
                title: "Storage Is Not Ready",
                message: "Sync diagnostics are available after collection storage finishes opening.",
                skippedCSVText: nil
            )
            return
        }
        do {
            let digest = try CollectionStoreDigester.make(in: modelContext, storeID: storeID)
            let snapshot = CloudSyncDiagnosticsSnapshot(
                schemaVersion: 1,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                osVersion: UIDevice.current.systemVersion,
                deviceClass: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
                storageModeRaw: TradingCardScannerApp.activeStorageMode.rawValue,
                cloudAccountStatusRaw: TradingCardScannerApp.activeCloudAccountStatusRaw,
                attachmentStateRaw: TradingCardScannerApp.activeAttachmentStateRaw,
                storeIDSuffix: digest.storeIDSuffix,
                digest: digest,
                lastBootstrapErrorCategory: TradingCardScannerApp.lastBootstrapErrorCategory,
                generatedAt: .now
            )
            diagnosticsDocument = JSONExportDocument(
                data: try CollectionStoreDigester.redactedJSON(for: snapshot)
            )
            isShowingDiagnosticsExporter = true
        } catch {
            csvMessage = CSVMessage(
                title: "Export Failed",
                message: "CardScanner could not create a redacted diagnostics export.",
                skippedCSVText: nil
            )
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
        guard csvImportProgress == nil,
              let storageToken = storageGeneration.currentToken() else { return }
        pendingCSVImport = nil
        let container = modelContext.container
        let token = UUID()
        let shouldContinue = storageGeneration.continuation(for: storageToken)
        csvImportToken = token
        csvImportProgress = CSVImportProgress(
            completedEntries: 0,
            totalEntries: plan.entries.count
        )
        writeCoordinator.beginBulkWrite()
        Task { @MainActor in
            defer {
                writeCoordinator.endBulkWrite()
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
                            guard csvImportToken == token, shouldContinue() else { return }
                            csvImportProgress = CSVImportProgress(
                                completedEntries: completedEntries,
                                totalEntries: totalEntries
                            )
                        }
                    },
                    shouldContinue: shouldContinue
                )
                guard storageGeneration.isCurrent(storageToken) else { return }
                loadCounts()
                Task { @MainActor in
                    guard storageGeneration.isCurrent(storageToken) else { return }
                    await catalogNormalizer.normalizeImportedCards(
                        in: container,
                        shouldContinue: {
                            storageGeneration.isCurrent(storageToken)
                        }
                    )
                }
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
                guard storageGeneration.isCurrent(storageToken) else { return }
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
            loadCounts()
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

/// The app has no CardScanner account. This surface reports the storage mode
/// selected by the bootstrap and points to the system iCloud settings when a
/// person needs to change availability or account state.
struct CollectionStorageStatusSection: View {
    var body: some View {
        Section {
            LabeledContent(
                "Collection storage",
                value: TradingCardScannerApp.activeStorageMode.label
            )
            LabeledContent(
                "iCloud account",
                value: cloudAccountStatusLabel
            )
            LabeledContent(
                "Attachment",
                value: attachmentStateLabel
            )
            Text(TradingCardScannerApp.activeStorageMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if TradingCardScannerApp.activeCloudAccountStatusRaw
                == LocalStorageReason.temporarilyUnavailable.rawValue {
                Text("iCloud is temporarily unavailable. This local collection is visibly unverified for syncing and may resume when iCloud is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if TradingCardScannerApp.activeCloudAccountStatusRaw
                == LocalStorageReason.restorationUnproven.rawValue {
                Text("iCloud restoration is not proven yet. This collection is staying on this device until a safe restoration check is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Collection sync follows the device's iCloud account. CardScanner does not require a separate account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open iCloud Settings", action: openSystemSettings)
        } header: {
            Text("Storage")
        } footer: {
            if !TradingCardScannerApp.activeStorageMode.isCloudSyncing {
                Text("Value History and custom artwork stay on this device. If iCloud becomes available, CardScanner asks before attaching an existing collection to a different account.")
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var cloudAccountStatusLabel: String {
        switch TradingCardScannerApp.activeCloudAccountStatusRaw {
        case "available": return "Available"
        case LocalStorageReason.noAccount.rawValue: return "No iCloud account"
        case LocalStorageReason.restricted.rawValue: return "Restricted"
        case LocalStorageReason.temporarilyUnavailable.rawValue: return "Temporarily unavailable"
        case LocalStorageReason.attachmentSuspended.rawValue: return "Kept on this device"
        case LocalStorageReason.restorationUnproven.rawValue: return "Restoration not proven"
        default: return TradingCardScannerApp.activeCloudAccountStatusRaw
        }
    }

    private var attachmentStateLabel: String {
        switch TradingCardScannerApp.activeAttachmentStateRaw {
        case CloudAttachmentState.neverAttached.rawValue: return "Never attached"
        case CloudAttachmentState.attached.rawValue: return "Attached"
        case CloudAttachmentState.suspended.rawValue: return "Suspended"
        case CloudAttachmentState.conflict.rawValue: return "Conflict"
        default: return TradingCardScannerApp.activeAttachmentStateRaw
        }
    }
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
