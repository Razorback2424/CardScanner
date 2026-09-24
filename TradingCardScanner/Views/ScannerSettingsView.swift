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
    @State private var pendingCSVAlreadyImportedEntryCount = 0
    @State private var portfolioCloseCount = 0
    @State private var collectionCardCount = 0
    @State private var priceRecordCount = 0
    @State private var missingArtworkCount = 0
    @State private var priceCoverageGaps: [PriceCoverageGapLog.Gap] = []
    @State private var browseHistoryDiagnostics = BrowsePriceHistoryDiagnostics.empty
    @AppStorage("pokemonMasterSetTier") private var pokemonMasterSetTier: PokemonMasterSetTier = .standard
    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SettingsCategoryView("Scanning") {
                            ScannerCameraSettingsSection(scanner: scannerModel.scanner)
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
                            pokemonMasterSetSection
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
                        .disabled(writeCoordinator.activeExclusiveOperation != nil)
                }
            }
            .task {
                loadCounts()
                refreshPriceCoverageGaps()
                await refreshBrowseHistoryDiagnostics()
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
                case let .failure(error): writeCoordinator.csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription, skippedCSVText: nil)
                }
            }
            .fileExporter(isPresented: $isShowingCSVExporter, document: csvExportDocument, contentType: .commaSeparatedText, defaultFilename: csvExportFilename) { result in
                csvExportDocument = nil
                if case let .failure(error) = result {
                    writeCoordinator.csvMessage = CSVMessage(title: "Export Failed", message: error.localizedDescription, skippedCSVText: nil)
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
                            writeCoordinator.csvMessage = CSVMessage(
                                title: "Export Failed",
                                message: error.localizedDescription,
                                skippedCSVText: nil
                            )
                        }
                    }
            }
            .confirmationDialog("Import CSV?", isPresented: Binding(get: { pendingCSVImport != nil }, set: { if !$0 { pendingCSVImport = nil } }), titleVisibility: .visible) {
                if let plan = pendingCSVImport {
                    if pendingCSVAlreadyImportedEntryCount > 0 {
                        let remainingCount = max(0, plan.entries.count - pendingCSVAlreadyImportedEntryCount)
                        Button("Import remaining \(remainingCount) entries") { importCSV(plan) }
                        Button("Import all again as additional copies") {
                            importCSV(plan.importingAgainAsAdditionalCopies())
                        }
                    } else {
                        Button("Import \(plan.totalQuantity) Cards") { importCSV(plan) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingCSVImport = nil }
            } message: {
                if let plan = pendingCSVImport { Text(importConfirmationMessage(plan)) }
            }
            .alert(item: $writeCoordinator.csvMessage) { message in
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
            .interactiveDismissDisabled(writeCoordinator.activeExclusiveOperation != nil)
        }
    }

    private var collectionSection: some View {
        Section("Collection") {
            if let progress = writeCoordinator.csvImportProgress {
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
            if writeCoordinator.activeExclusiveOperation == .collectionDelete {
                HStack {
                    ProgressView()
                    Text("Deleting collection…")
                }
                .accessibilityElement(children: .combine)
            }

            Button("Import CSV", systemImage: "square.and.arrow.down") {
                isShowingCSVImporter = true
            }
            .disabled(writeCoordinator.activeExclusiveOperation != nil)

            Button("Export CSV", systemImage: "square.and.arrow.up") {
                do {
                    let cards = try modelContext.fetch(FetchDescriptor<CollectedCard>())
                    csvExportDocument = CollectionCSV.export(cards)
                    csvExportFilename = "CardScanner Collection"
                    isShowingCSVExporter = true
                } catch {
                    writeCoordinator.csvMessage = CSVMessage(
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
            .disabled(writeCoordinator.activeExclusiveOperation != nil)
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
                    writeCoordinator.csvMessage = CSVMessage(
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

    private var pokemonMasterSetSection: some View {
        Section {
            Picker("Definition", selection: $pokemonMasterSetTier) {
                ForEach(PokemonMasterSetTier.allCases) { tier in
                    Text(tier.label).tag(tier)
                }
            }

            Text(pokemonMasterSetTier.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Pokémon Master Set")
        } footer: {
            Text("This definition controls Pokémon set progress throughout the catalog.")
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
                        writeCoordinator.csvMessage = CSVMessage(
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
                        writeCoordinator.csvMessage = CSVMessage(
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

                DisclosureGroup {
                    if priceCoverageGaps.isEmpty {
                        Text("No unpriced Browse finishes have been recorded in this session.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(priceCoverageGaps) { gap in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(gap.summary)
                                    .font(.subheadline)
                                Text("Seen \(gap.observationCount) time\(gap.observationCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Button("Refresh list", systemImage: "arrow.clockwise") {
                        refreshPriceCoverageGaps()
                    }
                } label: {
                    Label(
                        "Browse price coverage (\(priceCoverageGaps.count))",
                        systemImage: "exclamationmark.triangle"
                    )
                }

                DisclosureGroup {
                    LabeledContent(
                        "Sets with history",
                        value: browseHistoryDiagnostics.setCount.formatted()
                    )
                    LabeledContent(
                        "Stored locally",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(browseHistoryDiagnostics.totalBytes),
                            countStyle: .file
                        )
                    )
                    if let oldest = browseHistoryDiagnostics.oldestProviderDay {
                        LabeledContent("Oldest provider day", value: oldest.rawValue)
                    }
                    if let newest = browseHistoryDiagnostics.newestProviderDay {
                        LabeledContent("Newest provider day", value: newest.rawValue)
                    }
                    LabeledContent(
                        "Corrupt files recovered",
                        value: browseHistoryDiagnostics.corruptFileRecoveryCount.formatted()
                    )
                    LabeledContent(
                        "Skipped timestamps",
                        value: browseHistoryDiagnostics.skippedTimestampWrites.formatted()
                    )
                    LabeledContent(
                        "Deduplicated observations",
                        value: browseHistoryDiagnostics.deduplicatedObservationCount.formatted()
                    )
                    LabeledContent(
                        "Unmapped variants",
                        value: browseHistoryDiagnostics.unmappedVariantCount.formatted()
                    )
                    Text(browseHistoryDiagnostics.pokemonShadowCoverageSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh history diagnostics", systemImage: "arrow.clockwise") {
                        Task { await refreshBrowseHistoryDiagnostics() }
                    }
                } label: {
                    Label("Browse history diagnostics", systemImage: "chart.xyaxis.line")
                }
            }
        }
    }

    private func refreshPriceCoverageGaps() {
        priceCoverageGaps = PriceCoverageGapLog.shared.currentGaps()
    }

    private func refreshBrowseHistoryDiagnostics() async {
        browseHistoryDiagnostics = await BrowsePriceHistoryStore.shared.diagnostics()
    }

    private func exportSyncDiagnostics() {
        guard TradingCardScannerApp.storageIsReady,
              let storeID = TradingCardScannerApp.activeStoreID else {
            writeCoordinator.csvMessage = CSVMessage(
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
            writeCoordinator.csvMessage = CSVMessage(
                title: "Export Failed",
                message: "CardScanner could not create a redacted diagnostics export.",
                skippedCSVText: nil
            )
        }
    }

    @MainActor
    private func prepareCSVImport(from url: URL) async {
        do {
            let container = modelContext.container
            let prepared = try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let plan = try CollectionCSV.parse(Data(contentsOf: url, options: .mappedIfSafe))
                let context = ModelContext(container)
                let count = try CollectionCSV.alreadyImportedEntryCount(for: plan, in: context)
                return (plan, count)
            }.value
            pendingCSVImport = prepared.0
            pendingCSVAlreadyImportedEntryCount = prepared.1
        } catch {
            writeCoordinator.csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription, skippedCSVText: nil)
        }
    }

    @MainActor
    private func importCSV(_ plan: CollectionCSVImportPlan) {
        guard let storageToken = storageGeneration.currentToken() else { return }
        guard let operationToken = writeCoordinator.beginCSVImport(
            totalEntries: plan.entries.count
        ) else {
            writeCoordinator.csvMessage = CSVMessage(
                title: "Import Unavailable",
                message: "Another collection write is still in progress. Try importing again when it finishes.",
                skippedCSVText: nil
            )
            return
        }
        pendingCSVImport = nil
        let container = modelContext.container
        let storageShouldContinue = storageGeneration.continuation(for: storageToken)
        let stopFlag = CollectionCSVImportStopFlag()
        Task { @MainActor in
            defer { writeCoordinator.endCSVImport(token: operationToken) }
            let backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "Collection CSV Import"
            ) {
                stopFlag.requestStop()
            }
            defer {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
            do {
                let result = try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
                    let exclusiveToken = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
                    defer { CollectionWriteSerializer.endExclusive(exclusiveToken) }
                    return try await CollectionCSV.applyIsolated(
                        plan,
                        to: container,
                        batchSize: 100,
                        exclusiveToken: exclusiveToken,
                        progress: { completedEntries, totalEntries in
                            Task { @MainActor in
                                writeCoordinator.updateCSVImportProgress(
                                    CSVImportProgress(
                                        completedEntries: completedEntries,
                                        totalEntries: totalEntries
                                    ),
                                    token: operationToken
                                )
                            }
                        },
                        shouldContinue: {
                            storageShouldContinue() && stopFlag.shouldContinue
                        }
                    )
                }
                guard storageGeneration.isCurrent(storageToken) else { return }
                // A completed partial run keeps its failed-row export as the
                // retry path. Clear the run salt so a later deliberate
                // "Import all again" starts a fresh additional-copy run.
                CollectionCSV.finishImportAgainRun(plan)
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
                if result.alreadyImportedEntries > 0 {
                    details += " Skipped \(result.alreadyImportedEntries) entries already imported from this file."
                }
                if result.skippedRows > 0 { details += " Ignored \(result.skippedRows) unsupported, non-English, or non-card rows." }
                if !result.failedRows.isEmpty {
                    details += " Could not import \(result.failedRows.count) entries. Export the failed rows to retry only those entries."
                }
                details += " Artwork loads automatically. Refresh prices when you're ready."
                writeCoordinator.csvMessage = CSVMessage(
                    title: result.failedRows.isEmpty ? "Import Complete" : "Import Partially Complete",
                    message: details,
                    skippedCSVText: result.failedRows.isEmpty ? plan.skippedCSVText : nil,
                    failedCSVText: result.failedEntries.isEmpty
                        ? nil
                        : CollectionCSV.exportFailedEntries(result.failedEntries).text
                )
            } catch {
                let message: String
                if let csvError = error as? CollectionCSVError,
                   case let .importInterrupted(completedEntries, totalEntries) = csvError {
                    message = "Added \(completedEntries) of \(totalEntries) entries before stopping. Import the same file again to add only the remaining entries."
                } else {
                    message = error.localizedDescription
                }
                writeCoordinator.csvMessage = CSVMessage(
                    title: "Import Stopped",
                    message: message,
                    skippedCSVText: nil
                )
            }
        }
    }

    private func importConfirmationMessage(_ plan: CollectionCSVImportPlan) -> String {
        let pendingCount = max(0, plan.entries.count - pendingCSVAlreadyImportedEntryCount)
        var message: String
        if pendingCSVAlreadyImportedEntryCount > 0 {
            message = "This file has already added \(pendingCSVAlreadyImportedEntryCount) of \(plan.entries.count) entries. Importing the remaining entries adds only those not already in the ledger."
        } else {
            message = "Adds \(plan.totalQuantity) cards in \(plan.entries.count) entries. Matching entries will be combined."
        }
        if pendingCount == 0 && pendingCSVAlreadyImportedEntryCount > 0 {
            message = "Every entry in this file has already been imported. You can import all again as additional copies."
        }
        if plan.skippedRows > 0 { message += " \(plan.skippedRows) unsupported, non-English, or non-card rows will be ignored." }
        return message
    }

    private var deletionErrorBinding: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )
    }

    private func deleteCollection() {
        guard let storageToken = storageGeneration.currentToken() else {
            deletionError = "Collection storage is not ready. Please try again."
            return
        }
        guard let operationToken = writeCoordinator.beginCollectionDelete() else {
            deletionError = "Another collection write is in progress. Wait for it to finish, then try again."
            return
        }
        let container = modelContext.container
        let shouldContinue = storageGeneration.continuation(for: storageToken)
        Task { @MainActor in
            defer { writeCoordinator.endCollectionDelete(token: operationToken) }
            do {
                let actor = CollectionDeletionModelActor(modelContainer: container)
                let didDelete = try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
                    let exclusiveToken = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
                    defer { CollectionWriteSerializer.endExclusive(exclusiveToken) }
                    return try await actor.deleteAll(
                        shouldContinue: shouldContinue,
                        exclusiveToken: exclusiveToken
                    )
                }
                guard didDelete, storageGeneration.isCurrent(storageToken) else { return }
                loadCounts()
            } catch {
                guard storageGeneration.isCurrent(storageToken) else { return }
                deletionError = error.localizedDescription
            }
        }
    }
}

private struct ScannerCameraSettingsSection: View {
    let scanner: CardScanner
    @ObservedObject private var state: CardScannerUIState

    init(scanner: CardScanner) {
        self.scanner = scanner
        _state = ObservedObject(wrappedValue: scanner.uiState)
    }

    var body: some View {
        Section {
            if state.availableLenses.count > 1 {
                Picker("Lens", selection: lensBinding) {
                    ForEach(state.availableLenses) { lens in
                        Text(lens.label).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                LabeledContent("Lens", value: state.lens.label)
            }
        } header: {
            Text("Camera")
        } footer: {
            if state.availableLenses.contains(.macro) {
                Text("Macro uses the ultra wide lens, which focuses down to a few centimetres. The standard lens cannot focus close enough to read a card's set code.")
            } else {
                Text("This device has no ultra wide camera that can focus close, so only the standard lens is available.")
            }
        }
    }

    /// `state.lens` is only changed once the capture session has actually swapped
    /// inputs, so the picker writes through `setLens` and reads back the hardware's
    /// answer rather than holding its own selection state.
    private var lensBinding: Binding<CameraLens> {
        Binding(
            get: { state.lens },
            set: { scanner.setLens($0) }
        )
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
    @Environment(\.modelContext) private var modelContext
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
            queueGradedPriceRefresh()
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

    private func queueGradedPriceRefresh() {
        Task { @MainActor in
            let storageGeneration = CollectionStorageGeneration.shared
            guard let storageToken = storageGeneration.currentToken() else { return }
            let shouldContinue = storageGeneration.continuation(for: storageToken)
            _ = await MagicTreatmentMigrationCoordinator.shared.withPriceRefresh(
                in: modelContext,
                runsNetworkMigration: false,
                storageToken: storageToken,
                shouldContinue: shouldContinue,
                operation: { permit in
                    guard shouldContinue() else { return false }
                    let request = PriceRefreshRequest(
                        usesPriceFallback: usesPriceFallback,
                        includeImported: true,
                        forceUnsupportedRetry: true,
                        sortOldestFirst: true,
                        maximumTargetCount: nil,
                        markRecentlyCheckedIfEmpty: false,
                        gradedOnly: true
                    )
                    return (await PriceRefreshController.shared.refresh(
                        request,
                        container: modelContext.container,
                        shouldContinue: shouldContinue,
                        identityRewritePermit: permit
                    )).didRun
                }
            )
        }
    }

}

/// CardScanner 1.0 keeps the collection on this device; iCloud sync is not
/// offered by the production build.
struct CollectionStorageStatusSection: View {
    var body: some View {
        Section {
            LabeledContent("Collection storage", value: "On this device")
            Text("iCloud sync is not available in CardScanner 1.0.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Storage")
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
