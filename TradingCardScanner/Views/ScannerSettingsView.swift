import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shared settings sheet for the app. The root stays deliberately short: each
/// category leads to a focused form instead of asking someone to scan every
/// low-frequency control before finding the one they need.
struct SettingsView: View {
    @Environment(\.cardGameRuntimes) private var runtimes

    var body: some View { SettingsContentView(runtimes: runtimes) }
}

private struct SettingsContentView: View {
    private let runtimes: CardGameRuntimeContainer?
    @EnvironmentObject private var scannerModel: ScannerViewModel
    @EnvironmentObject private var writeCoordinator: DerivedStateWriteCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sharedBrowseCatalog) private var sharedBrowseCatalog
    @ObservedObject private var storageGeneration = CollectionStorageGeneration.shared
    @State private var isConfirmingCollectionDeletion = false
    @State private var deletionError: String?
    @State private var isShowingCSVImporter = false
    @State private var isShowingCSVExporter = false
    @State private var isPreparingCSVExport = false
    @State private var isPreparingDiagnosticsExport = false
    @State private var isPreparingCatalogHealthExport = false
    @State private var catalogHealthExportProgress = ""
    @State private var checkLiveCatalogPrices = true
    @State private var catalogHealthExportTask: Task<Void, Never>?
    @State private var isShowingDiagnosticsExporter = false
    @State private var csvExportDocument: CollectionCSVDocument?
    @State private var csvExportTiming: CSVExportTiming?
    @State private var csvExportPickerSpan: CSVExportTiming.Span?
    @State private var diagnosticsDocument: JSONExportDocument?
    @State private var csvExportFilename = "ScanStash Collection"
    @State private var pendingCSVImport: CollectionCSVImportPlan?
    @State private var csvImportPreparationID = UUID()
    @State private var isPreparingCSVImport = false
    @State private var pendingCSVAlreadyImportedEntryCount = 0
    @State private var portfolioCloseCount = 0
    @State private var collectionCardCount = 0
    @State private var priceRecordCount = 0
    @State private var missingArtworkCount = 0
    @State private var priceCoverageGaps: [PriceCoverageGapLog.Gap] = []
    @AppStorage("pokemonMasterSetTier") private var pokemonMasterSetTier: PokemonMasterSetTier = .standard
    @StateObject private var catalogNormalizer: CollectionCatalogNormalizer

    init(runtimes: CardGameRuntimeContainer?) {
        self.runtimes = runtimes
        _catalogNormalizer = StateObject(wrappedValue: runtimes?.makeCollectionNormalizer() ?? CollectionCatalogNormalizer())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SettingsCategoryView("Scanning") {
                            ScannerCameraSettingsSection(scanner: scannerModel.scanner)
                            ScannerStudyMetricsSection()
                        }
                    } label: {
                        Label("Scanning", systemImage: "viewfinder")
                    }

                    NavigationLink {
                        SettingsCategoryView("Pricing") {
                            PriceFallbackSettingsSection(onKeySaved: retrySealedNormalization)
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
                        Label("Collection Storage", systemImage: "externaldrive")
                    }

                    NavigationLink {
                        PrivacyAndSupportSettingsView()
                    } label: {
                        Label("Privacy & Support", systemImage: "hand.raised")
                    }
                }

                Section("Advanced") {
                    NavigationLink {
                        SettingsCategoryView("Collection Diagnostics") {
                            diagnosticsSection
                        }
                    } label: {
                        Label("Collection Diagnostics", systemImage: "waveform.path.ecg")
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
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
            }
        }
            // Present from the persistent navigation container. The root Form
            // is offscreen while a settings category is pushed; attaching CSV
            // confirmation there hides it until the user navigates back.
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
            .fileExporter(isPresented: $isShowingCSVExporter, document: csvExportDocument,
                          contentTypes: [.commaSeparatedText], defaultFilename: csvExportFilename, onCompletion: { result in
                switch result {
                case .success: finishCSVExport(outcome: "saved")
                case .failure: finishCSVExport(outcome: "failed")
                }
                if case let .failure(error) = result {
                    writeCoordinator.csvMessage = CSVMessage(title: "Export Failed", message: error.localizedDescription, skippedCSVText: nil)
                }
            }, onCancellation: {
                finishCSVExport(outcome: "cancelled")
            })
            .onChange(of: isShowingCSVExporter) { _, presented in
                csvExportTiming?.event("CSVExport.presentationBinding", "requested=\(presented)")
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
                        defaultFilename: "ScanStash Sync Diagnostics"
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
                        csvExportFilename = "ScanStash Failed Import Rows"
                        isShowingCSVExporter = true
                    }, secondaryButton: .cancel(Text("Done")))
                }
                if let skippedCSVText = message.skippedCSVText {
                    return Alert(title: Text(message.title), message: Text(message.message), primaryButton: .default(Text("Export Skipped Rows")) {
                        csvExportDocument = CollectionCSVDocument(text: skippedCSVText)
                        csvExportFilename = "ScanStash Skipped Rows"
                        isShowingCSVExporter = true
                    }, secondaryButton: .cancel(Text("Done")))
                    }
                return Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("OK")))
            }
            .interactiveDismissDisabled(writeCoordinator.activeExclusiveOperation != nil)
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
            .disabled(isPreparingCSVImport || writeCoordinator.activeExclusiveOperation != nil)

            if isPreparingCSVImport {
                HStack {
                    ProgressView()
                    Text("Reading CSV…")
                }
                .accessibilityElement(children: .combine)
            }

            Button("Export CSV", systemImage: "square.and.arrow.up") {
                prepareCSVExport(.collection, filename: "ScanStash Collection")
            }
            .disabled(collectionCardCount == 0 || isPreparingCSVExport || writeCoordinator.activeExclusiveOperation != nil)

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
                prepareCSVExport(.portfolioHistory, filename: "ScanStash Value History")
            }
            .disabled(portfolioCloseCount == 0 || isPreparingCSVExport || writeCoordinator.activeExclusiveOperation != nil)
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

    private var diagnosticsSection: some View {
        Section {
            DisclosureGroup("Collection Exports & Price Coverage") {
                Button("Export Catalog Health Report", systemImage: "square.and.arrow.up") {
                    prepareCatalogHealthExport()
                }
                .disabled(runtimes == nil || isPreparingCatalogHealthExport || isPreparingCSVExport ||
                          writeCoordinator.activeExclusiveOperation != nil)
                if isPreparingCatalogHealthExport {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(catalogHealthExportProgress).font(.footnote)
                        Spacer(minLength: 0)
                        Button("Cancel") { catalogHealthExportTask?.cancel() }
                    }
                }
                Toggle("Check catalog prices", isOn: $checkLiveCatalogPrices)
                    .disabled(isPreparingCatalogHealthExport)
                Text("Exports catalog issues across all five games, including cards you don’t own. Price checks use Browse prices, which may be cached, and may require many network requests. Turn off to skip price checks.")
                    .font(.footnote).foregroundStyle(.secondary)

                Button("Export Cards Excluded from USD Value", systemImage: "dollarsign.circle") {
                    prepareCSVExport(.unpriced, filename: "ScanStash Unpriced Cards")
                }
                .disabled(collectionCardCount == 0 || isPreparingCSVExport || isPreparingCatalogHealthExport || writeCoordinator.activeExclusiveOperation != nil)

                Button("Export Price Evidence for All Cards", systemImage: "clock.badge.checkmark") {
                    prepareCSVExport(.priceEvidence, filename: "ScanStash Price Evidence")
                }
                .disabled(collectionCardCount == 0 || isPreparingCSVExport || writeCoordinator.activeExclusiveOperation != nil)

                Button("Export Missing Artwork", systemImage: "photo") {
                    prepareCSVExport(.missingArtwork, filename: "ScanStash Missing Artwork")
                }
                .disabled(missingArtworkCount == 0 || isPreparingCSVExport || writeCoordinator.activeExclusiveOperation != nil)

#if DEBUG
                Button("Run Overnight Price Refresh", systemImage: "moon.stars") {
                    Task {
                        await BackgroundPriceRefresh.run(.processing, allowsForeground: true,
                            prepareRuntimes: { [runtimes] in
                                if let runtimes { return runtimes }
                                return await CardGameRuntimeContainer.preparedAppDefaults()
                            })
                    }
                }
                .disabled(collectionCardCount == 0)
#endif

#if !NO_CLOUDKIT
                Button("Export Sync Diagnostics", systemImage: "waveform.path.ecg") {
                    exportSyncDiagnostics()
                }
                .disabled(!TradingCardScannerApp.storageIsReady || isPreparingDiagnosticsExport)
                Text("Redacted diagnostic data for support. It does not include card names, collection contents, credentials, or images.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
#endif

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

            }
        }
    }

    private func refreshPriceCoverageGaps() {
        priceCoverageGaps = PriceCoverageGapLog.shared.currentGaps()
    }

    private func retrySealedNormalization() {
        guard let token = storageGeneration.currentToken() else { return }
        let container = modelContext.container
        let shouldContinue = storageGeneration.continuation(for: token)
        Task { @MainActor in
            await catalogNormalizer.normalizeImportedCards(
                in: container, retryFailedSealed: true, shouldContinue: shouldContinue
            )
        }
    }

    private func prepareCatalogHealthExport() {
        guard !isPreparingCatalogHealthExport, !isPreparingCSVExport,
              writeCoordinator.activeExclusiveOperation == nil, let runtimes else { return }
        // Use the same Browse actor as the running app, including its active
        // catalog revisions and in-session price observations.
        let browse = (sharedBrowseCatalog as Any as? BrowseCatalog) ?? runtimes.makeBrowseCatalog()
        isPreparingCatalogHealthExport = true
        catalogHealthExportProgress = "Reading active catalog…"
        catalogHealthExportTask = Task { @MainActor in
            defer {
                isPreparingCatalogHealthExport = false
                catalogHealthExportTask = nil
            }
            do {
                let document = try await ActiveCatalogHealthCSV.makeDocument(
                    runtimes: runtimes, browse: browse, checkPrices: checkLiveCatalogPrices
                ) { message in
                    catalogHealthExportProgress = message
                }
                try Task.checkCancellation()
                csvExportDocument = document
                csvExportFilename = "ScanStash Active Catalog Health"
                isShowingCSVExporter = true
            } catch is CancellationError {
                // A cancelled run never offers a misleading partial report.
            } catch {
                writeCoordinator.csvMessage = CSVMessage(
                    title: "Catalog Export Failed", message: error.localizedDescription,
                    skippedCSVText: nil
                )
            }
        }
    }

    private func prepareCSVExport(_ kind: CollectionCSV.ExportKind, filename: String) {
        guard !isPreparingCSVExport, !isPreparingCatalogHealthExport,
              let token = storageGeneration.currentToken() else { return }
        let container = modelContext.container
        let timing = CSVExportTiming(kind: String(describing: kind))
        timing.event("CSVExport.requested")
        let preparation = timing.begin("CSVExport.tapToReady")
        isPreparingCSVExport = true
        Task { @MainActor in
            defer { isPreparingCSVExport = false }
            do {
                let document = try await CollectionCSV.exportIsolated(from: container, kind: kind, timing: timing)
                timing.end(preparation, "outcome=ready")
                guard storageGeneration.isCurrent(token) else {
                    timing.event("CSVExport.discarded", "reason=obsoleteStorage")
                    return
                }
                timing.event("CSVExport.uiResumed")
                csvExportTiming = timing
                csvExportDocument = document
                csvExportFilename = filename
                // This spans the system picker and the user's selection time;
                // it is a lifecycle boundary, not a main-thread stall duration.
                csvExportPickerSpan = timing.begin("CSVExport.pickerLifecycle")
                timing.event("CSVExport.presentationRequested")
                isShowingCSVExporter = true
            } catch {
                timing.end(preparation, "outcome=failed")
                guard storageGeneration.isCurrent(token) else { return }
                writeCoordinator.csvMessage = CSVMessage(
                    title: "Export Failed",
                    message: error.localizedDescription,
                    skippedCSVText: nil
                )
            }
        }
    }

    private func finishCSVExport(outcome: String) {
        csvExportTiming?.event("CSVExport.completed", "outcome=\(outcome)")
        if let span = csvExportPickerSpan { csvExportTiming?.end(span, "outcome=\(outcome)") }
        csvExportPickerSpan = nil
        let release = csvExportTiming?.begin("CSVExport.releaseDocument")
        csvExportDocument = nil
        if let release { csvExportTiming?.end(release) }
        csvExportTiming = nil
    }

    private func exportSyncDiagnostics() {
        guard !isPreparingDiagnosticsExport else { return }
        guard TradingCardScannerApp.storageIsReady,
              let storeID = TradingCardScannerApp.activeStoreID,
              let token = storageGeneration.currentToken() else {
            writeCoordinator.csvMessage = CSVMessage(
                title: "Storage Is Not Ready",
                message: "Sync diagnostics are available after collection storage finishes opening.",
                skippedCSVText: nil
            )
            return
        }
        let container = modelContext.container
        isPreparingDiagnosticsExport = true
        Task { @MainActor in
            defer { isPreparingDiagnosticsExport = false }
            do {
                let digest = try await CollectionStoreDigester.makeIsolated(from: container, storeID: storeID)
                guard storageGeneration.isCurrent(token) else { return }
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
                guard storageGeneration.isCurrent(token) else { return }
                writeCoordinator.csvMessage = CSVMessage(
                    title: "Export Failed",
                    message: "ScanStash could not create a redacted diagnostics export.",
                    skippedCSVText: nil
                )
            }
        }
    }

    @MainActor
    private func prepareCSVImport(from url: URL) async {
        guard let storageToken = storageGeneration.currentToken() else { return }
        let preparationID = UUID()
        csvImportPreparationID = preparationID
        isPreparingCSVImport = true
        defer {
            if csvImportPreparationID == preparationID { isPreparingCSVImport = false }
        }
        pendingCSVImport = nil
        do {
            let container = modelContext.container
            let prepared = try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let plan = try CollectionCSV.parse(Data(contentsOf: url, options: .mappedIfSafe))
                    .resumingAdditionalCopyRunIfNeeded()
                let context = ModelContext(container)
                let count = try CollectionCSV.alreadyImportedEntryCount(for: plan, in: context)
                return (plan, count)
            }.value
            guard storageGeneration.isCurrent(storageToken),
                  csvImportPreparationID == preparationID else { return }
            pendingCSVImport = prepared.0
            pendingCSVAlreadyImportedEntryCount = prepared.1
        } catch {
            guard storageGeneration.isCurrent(storageToken),
                  csvImportPreparationID == preparationID else { return }
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
                // Catalog activation may suspend. Resolve the immutable import
                // snapshot before taking the collection's exclusive write lock.
                let importAdapters = await runtimes?.currentImportAdapters() ?? (try! GameImportAdapterRegistry(adapters: []))
                let gameRegistry = runtimes?.registry ?? .standard
                guard storageShouldContinue(), stopFlag.shouldContinue else { return }
                let result = try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
                    let exclusiveToken = try await CollectionWriteSerializer.beginExclusiveInBackground {
                        storageShouldContinue() && stopFlag.shouldContinue
                    }
                    defer { CollectionWriteSerializer.endExclusive(exclusiveToken) }
                    return try await CollectionCSV.applyIsolated(
                        plan,
                        to: container,
                        batchSize: 100,
                        exclusiveToken: exclusiveToken,
                        gameRegistry: gameRegistry,
                        gameImportAdapters: importAdapters,
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
                        shouldContinue: storageGeneration.continuation(for: storageToken)
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
                guard storageGeneration.isCurrent(storageToken) else { return }
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
                let actor = await CollectionDeletionModelActor.makeBackground(modelContainer: container)
                let didDelete = try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
                    let exclusiveToken = try await CollectionWriteSerializer.beginExclusiveInBackground(shouldContinue: shouldContinue)
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

private struct ScannerStudyMetricsSection: View {
    @EnvironmentObject private var scannerModel: ScannerViewModel
    @AppStorage(ScanSessionMetricsLog.enabledDefaultsKey) private var isEnabled = false

    var body: some View {
        Section {
            Toggle("Record session metrics", isOn: $isEnabled)
            ShareLink(item: scannerModel.sessionMetricsExport,
                      preview: SharePreview("ScanStash Session Log")) {
                Label("Export session log", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Study metrics")
        } footer: {
            Text("Applies to your next scan session. Logs stay on this device and include times, outcomes, interruptions and correction counts. No card details are recorded. Export shares a JSON file.")
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
    var onKeySaved: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false
    @State private var vendorKeyEntry = ""
    @State private var hasVendorKey = PriceVendorCredentials.hasKey
    @State private var vendorKeyMessage: String?
    @State private var vendorKeyMessageIsError = false

    var body: some View {
        Section {
            Toggle("Fill gaps in catalog prices", isOn: $usesPriceFallback)
                .disabled(!hasVendorKey)

            SecureField("JustTCG API key", text: $vendorKeyEntry)
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
            Text("JustTCG Pricing")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("A JustTCG key is required to load market price history, graded listings and provider-backed sealed prices. Listing coverage varies. Saved prices and cached history remain available without a key.")
                Text("Fill gaps adds JustTCG prices when the catalog has no supported price. Turning it off does not disable history, graded or sealed lookups.")
                Text(hasVendorKey
                     ? "Your key is saved in Keychain. Requests share a daily allowance: at most 95 per UTC day, with automatic work stopping at 75 to reserve 20 for direct actions. Remove and save a replacement key here if access changes."
                     : "Save your own key here to enable these features. Your key stays in Keychain; it is not included in collection exports.")
                Link("JustTCG account and API access", destination: URL(string: "https://justtcg.com")!)
            }
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
            onKeySaved()
            queueGradedPriceRefresh()
        } catch {
            vendorKeyMessageIsError = true
            vendorKeyMessage = error.localizedDescription
        }
    }

    private func removeVendorKey() {
        guard PriceVendorCredentials.remove() else {
            vendorKeyMessageIsError = true
            vendorKeyMessage = "The API key could not be removed from Keychain. Please try again."
            return
        }
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
            Text("iCloud sync is not available in ScanStash 1.0.")
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

    
// A read-only report of the catalog Browse actually uses. This deliberately
// does not scan a user's collection or equate "not checked" with "unpriced".
enum ActiveCatalogHealthCSV {
    private static let games: [CardGame] = [.pokemon, .magic, .onePiece, .lorcana, .yuGiOh]
    static let headers = [
        "record_type", "exported_at_utc", "app_build", "game", "set_name", "set_code",
        "active_release_revision", "expected_set_card_count", "enumerated_set_row_count",
        "product_set_id", "catalog_generation", "set_notice", "card_name",
        "card_number", "catalog_card_id", "printing_id", "finish_id",
        "verification_status", "market_mapping_status", "price_status",
        "browse_aggregate_price_usd", "market_provider", "market_group_id",
        "market_product_id", "market_product_name", "market_number",
        "market_lane", "issue_codes", "issue_details", "recommended_action",
        "card_notice", "image_url", "evidence_scope"
    ]

    struct Evidence {
        var finish: String = ""
        var verification: String = "not_evaluated"
        var mapping: String = "not_evaluated"
        var provider: String = ""
        var group: String = ""
        var product: String = ""
        var productName: String = ""
        var marketNumber: String = ""
        var lane: String = ""
        var issues: [String] = []
        var details: [String] = []
        var actions: [String] = []

        mutating func issue(_ code: String, _ detail: String, _ action: String) {
            guard !issues.contains(code) else { return }
            issues.append(code)
            details.append(detail)
            actions.append(action)
        }
    }

    static func escaped(_ value: String) -> String {
        // Excel/Numbers may evaluate formulas even inside quoted CSV fields.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafeControl = value.first.map { "\t\r\n".contains($0) } == true
        let safe = unsafeControl || trimmed.first.map({ "=+-@".contains($0) }) == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ fields: [String]) -> String {
        fields.map(escaped).joined(separator: ",") + "\r\n"
    }

    static func shouldExport(_ evidence: Evidence) -> Bool {
        !evidence.issues.isEmpty
    }

    static func row(
        kind: String, exported: String, build: String, game: CardGame,
        set: CatalogSet? = nil, card: CatalogCardSummary? = nil,
        evidence: Evidence = Evidence(), priceStatus: String = "not_checked",
        price: Double? = nil, generation: String = "", note: String = "",
        revision: Int? = nil, observedCount: Int? = nil,
        scope: String = "active_browse"
    ) -> String {
        let issues = evidence.issues.joined(separator: "|")
        let details = evidence.details.joined(separator: " | ")
        return line([
            kind, exported, build, game.rawValue, set?.name ?? "", set?.code ?? "",
            revision.map(String.init) ?? "", set?.cardCount.map(String.init) ?? "",
            observedCount.map(String.init) ?? "",
            set?.providerID ?? "", generation.isEmpty ? card?.catalogGeneration ?? "" : generation,
            set?.collectionAvailabilityNotice ?? "", card?.name ?? "",
            card?.collectorNumber ?? "", card?.providerID ?? "",
            card.flatMap { UUID(uuidString: $0.providerID) != nil ? $0.providerID : nil } ?? "",
            evidence.finish, evidence.verification, evidence.mapping, priceStatus,
            price.map { String($0) } ?? "", evidence.provider, evidence.group,
            evidence.product, evidence.productName, evidence.marketNumber, evidence.lane,
            issues, details, evidence.actions.joined(separator: " | "),
            note.isEmpty ? card?.collectionAvailabilityNotice ?? "" : note,
            card?.imageURL?.absoluteString ?? "", scope
        ])
    }

    static func checkedPriceStatus(
        _ summary: CatalogCardSummary, update: CatalogPriceUpdate?, evidence: inout Evidence
    ) -> (String, Double?) {
        guard let update else { return ("not_checked", nil) }
        if update.printingNeedsReviewIDs.contains(summary.id) {
            evidence.issue("PRINTING_NEEDS_REVIEW", "Browse price resolver requires printing verification.",
                           "Review physical printing")
            return ("printing_needs_review", nil)
        }
        if update.missingMappingIDs.contains(summary.id) {
            evidence.issue("BROWSE_PRICE_MAPPING_MISSING", "Browse could not establish a card-level price mapping; this result does not identify a specific finish.",
                           "Research exact market mapping")
            return ("mapping_missing", nil)
        }
        if update.unresolvedIDs.contains(summary.id) {
            evidence.issue("PRICE_CHECK_UNRESOLVED",
                           "Browse returned an unresolved price check without an underlying error or quote timestamp; the cause cannot be determined from this result.",
                           "Inspect provider, mapping and quote freshness diagnostics")
            return ("unresolved", nil)
        }
        if update.resolvedIDs.contains(summary.id) {
            if let amount = update.prices[summary.id] { return ("priced", amount) }
            evidence.issue("NO_USD_QUOTE", "Browse found no accepted USD quote for this card; this aggregate result is not a per-finish check.",
                           "Investigate quote availability for the printed identity")
            return ("no_usd_quote", nil)
        }
        // An interrupted or absent check is not proof that a quote is missing.
        return ("not_checked", nil)
    }

    static func printingEvidence(
        for summary: CatalogCardSummary, catalog: (any GameCatalogAdapter)?
    ) -> [Evidence] {
        var base = Evidence()
        if let notice = summary.collectionAvailabilityNotice {
            switch notice {
            case "Printing needs review", "Browse only":
                base.verification = "needs_review"
                base.issue("PRINTING_NEEDS_REVIEW", notice, "Reconcile physical printing and source evidence")
            default:
                base.issue("CATALOG_NOTICE", notice, "Review catalog notice")
            }
        }

        if let registry = (catalog as? OnePieceCatalogAdapter)?.registry,
           let uuid = UUID(uuidString: summary.providerID),
           let printing = registry.printingByID[uuid] {
            base.verification = printing.status.rawValue
            let supported = printing.supportedVariantIDs
            if supported.isEmpty {
                var value = base
                value.issue("FINISH_UNVERIFIED", "No reviewed finish is retained.", "Verify physical finish")
                return [value]
            }
            return supported.sorted().map { finish in
                var value = base
                value.finish = finish
                let mappingCandidates = printing.marketMappings.filter { $0.variantID == finish }
                let exact = mappingCandidates.filter {
                    $0.status == .exact && $0.provider == "tcgplayer" &&
                    $0.market == "us" && $0.currency == "USD" && $0.condition == "aggregate"
                }
                if printing.status != .verified {
                    value.mapping = "blocked_by_verification"
                    value.issue("PRINTING_NEEDS_REVIEW", "Physical printing is not verified.", "Verify printing first")
                } else if exact.count > 1 {
                    value.mapping = "conflict"
                    value.issue("PRICE_MAPPING_CONFLICT", "Multiple exact mappings for this finish.", "Reconcile market-product identities")
                } else if let market = exact.first {
                    value.mapping = "exact"
                    value.provider = market.provider
                    value.product = market.productID
                    value.group = market.qualifiers["groupID"] ?? ""
                    value.productName = market.qualifiers["productName"] ?? ""
                    value.marketNumber = summary.collectorNumber
                    value.lane = market.providerVariantID ?? ""
                    if value.group.isEmpty || value.lane.isEmpty || value.productName.isEmpty {
                        value.mapping = "incomplete"
                        value.issue("MARKET_MAPPING_INCOMPLETE", "Exact mapping lacks required group, name or lane.", "Correct marketplace evidence")
                    }
                } else if !mappingCandidates.isEmpty {
                    value.mapping = "unapproved"
                    value.issue("PRICE_MAPPING_UNAPPROVED", "Market leads exist, but none is approved as an exact USD mapping.", "Review mapping evidence")
                } else {
                    value.mapping = "missing"
                    value.issue("PRICE_MAPPING_MISSING", "No approved market mapping for this verified finish.", "Research exact marketplace product")
                }
                return value
            }
        }

        if let registry = (catalog as? LorcanaCatalogAdapter)?.registry ?? (catalog as? LorcanaDiscoveryCatalog)?.registry,
           let uuid = UUID(uuidString: summary.providerID),
           let printing = registry.physicalCatalog?.printingByID[uuid] {
            base.verification = printing.status.rawValue
            let finishes = printing.finishes.map(\.finish)
            let family = registry.physicalCatalog?.universesByFooter[printing.identity.footer]
            if family?.isComplete != true {
                base.issue("PHYSICAL_FAMILY_INCOMPLETE", "Physical printing family is not certified complete.", "Review all physical appearances")
            }
            if finishes.isEmpty {
                base.issue("FINISH_UNVERIFIED", "No reviewed physical finishes.", "Verify finish evidence")
                return [base]
            }
            return finishes.map { finish in
                var value = base
                value.finish = finish.rawValue
                let matches = (printing.marketMappings ?? []).filter { $0.finish == finish }
                if printing.status != .verified || family?.isComplete != true {
                    value.mapping = "blocked_by_verification"
                } else if let market = matches.first {
                    value.mapping = market.hasValidMarketLane ? "exact" : "invalid"
                    value.provider = "tcgplayer"
                    value.group = String(market.groupID)
                    value.product = String(market.productID)
                    value.productName = market.productName
                    value.marketNumber = market.productNumber
                    value.lane = market.providerVariantID
                    if !market.hasValidMarketLane {
                        value.issue("MARKET_MAPPING_INCOMPLETE", "Mapping lane contradicts reviewed finish.", "Verify marketplace lane")
                    }
                } else {
                    value.mapping = "missing"
                    value.issue("PRICE_MAPPING_MISSING", "No exact market mapping for reviewed finish.", "Research exact marketplace product")
                }
                return value
            }
        }

        if let catalog = (catalog as? YuGiOhCatalogAdapter)?.catalog,
           let uuid = UUID(uuidString: summary.providerID),
           let printing = catalog.printingByID[uuid] {
            base.verification = printing.explicitSelectionSupported ? "supported" : "held"
            if let reason = printing.identityReason {
                base.issue("PRINTING_NEEDS_REVIEW", reason, "Review physical printing identity")
            }
            if printing.canonicalLinkStatus == "unresolved" {
                base.issue("CANONICAL_LINK_UNRESOLVED", "Unresolved canonical card link.", "Review canonical card relationship")
            }
            if catalog.incompleteCodes.contains(printing.code) {
                base.issue("PRINTING_FAMILY_INCOMPLETE", "The printed-code family is incomplete.", "Review printing family")
            }
            if printing.editions.isEmpty {
                base.issue("EDITION_UNVERIFIED", "No supported edition retained.", "Verify edition evidence")
                return [base]
            }
            return printing.editions.map { edition in
                var value = base
                value.finish = edition.rawValue
                if printing.explicitSelectionSupported, let id = printing.productID,
                   let group = printing.marketGroupID {
                    value.mapping = "exact"
                    value.provider = "tcgplayer"
                    value.group = String(group)
                    value.product = String(id)
                    value.productName = printing.productName
                    value.marketNumber = printing.code
                    value.lane = edition.tcgplayerSubtype
                } else if printing.explicitSelectionSupported {
                    value.mapping = "missing"
                    value.issue("PRICE_MAPPING_MISSING", "No market product for supported edition.", "Research marketplace identity")
                } else {
                    value.mapping = "blocked_by_verification"
                }
                return value
            }
        }

        if summary.game == .pokemon {
            base.finish = summary.masterSetVariant?.id ?? ""
            if let market = PokemonTCGCSVMapping.byCardID[summary.providerID] {
                base.provider = "tcgplayer"
                base.group = String(market.groupID)
                base.product = String(market.productID)
                base.productName = market.productName
                base.marketNumber = market.printedNumber
                // This source-level mapping does not prove the lane for each
                // checklist finish. Preserve the product lead without claiming
                // that every physical variant uses its aggregate Holofoil lane.
                base.mapping = "reviewed_product_finish_not_evaluated"
            }
        } else if summary.game == .magic {
            let finishes = summary.magicFinishIDs ?? []
            if !finishes.isEmpty {
                return finishes.sorted().map { finish in
                    var value = base
                    value.finish = finish
                    return value
                }
            }
        }
        return [base]
    }

    static func makeDocument(
        runtimes: CardGameRuntimeContainer, browse: any BrowseCatalogProviding,
        checkPrices: Bool, progress: @escaping @MainActor (String) -> Void
    ) async throws -> CollectionCSVDocument {
        let date = ISO8601DateFormatter().string(from: .now)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        var csv = line(headers)
        csv.reserveCapacity(10_000_000)
        var auditedRevisions: [(CardGameRuntime, Int?, Int?, Int?)] = []
        for game in games {
            try Task.checkCancellation()
            await progress("Reading \(game.label)…")
            let runtime = runtimes.runtime(for: game)
            let pokemonRevision = await runtime?.legacyCatalogBindings.pokemon?.revision
            let magicRevision = await runtime?.legacyCatalogBindings.magic?.revision
            var snapshot = await runtime?.activationSource?.currentSnapshot()
            var activeCatalog = snapshot?.catalog ?? runtime?.catalog
            var activeGeneration = activeCatalog?.generation ?? ""
            let sets: [CatalogSet]
            do {
                sets = try await browse.sets(for: game)
            } catch {
                var issue = Evidence()
                issue.issue("CATALOG_DIRECTORY_FAILED", error.localizedDescription, "Investigate active catalog loading")
                csv.append(row(kind: "game_error", exported: date, build: build, game: game,
                               evidence: issue, generation: activeGeneration, scope: "not_enumerated"))
                continue
            }
            // Read the live authority again after Browse loads the set
            // directory. A persisted release may first become active here.
            if let current = await runtime?.activationSource?.currentSnapshot() {
                if current.revision != snapshot?.revision {
                    throw CatalogHealthExportError.catalogChanged
                }
                snapshot = current
                activeCatalog = current.catalog
                activeGeneration = current.catalog.generation
            }
            if sets.isEmpty {
                var issue = Evidence()
                issue.issue("NO_ACTIVE_SETS", "No sets were available from this game's active Browse catalog.", "Verify game activation and rollout")
                csv.append(row(kind: "game_error", exported: date, build: build, game: game,
                               evidence: issue, generation: activeGeneration, scope: "not_enumerated"))
            }
            if [.pokemon, .magic].contains(game) || !checkPrices {
                var limitation = Evidence()
                if [.pokemon, .magic].contains(game) {
                    limitation.issue("MAPPING_COVERAGE_NOT_FULLY_EVALUATED",
                        "Browse does not expose complete per-finish mapping and verification evidence for this game.",
                        "Investigate catalog and provider evidence before treating missing rows as healthy")
                }
                if !checkPrices {
                    limitation.issue("PRICE_CHECK_SKIPPED", "The price check was turned off for this export.",
                        "Run the export with catalog price checks enabled to investigate pricing")
                }
                csv.append(row(kind: "game_notice", exported: date, build: build, game: game,
                               evidence: limitation, generation: activeGeneration,
                               revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                               scope: "coverage_not_fully_evaluated"))
            }
            for (index, set) in sets.enumerated() {
                try Task.checkCancellation()
                if index.isMultiple(of: 10) || index == sets.count - 1 {
                    await progress("\(game.label): set \(index + 1) of \(sets.count)")
                }
                if let notice = set.collectionAvailabilityNotice {
                    var issue = Evidence()
                    issue.issue("SET_PARTIAL_CATALOG", notice, "Review unresolved set membership and verification")
                    csv.append(row(kind: "set_notice", exported: date, build: build, game: game,
                                   set: set, evidence: issue, generation: activeGeneration))
                }
                do {
                    let summaries: [CatalogCardSummary]
                    if let complete = try await browse.completeLocalCards(in: set) {
                        summaries = complete
                    } else {
                        var cards: [CatalogCardSummary] = []
                        var cursor: String?
                        var seen = Set<String>()
                        repeat {
                            try Task.checkCancellation()
                            let page = try await browse.cards(in: set, cursor: cursor)
                            cards.append(contentsOf: page.items)
                            guard let next = page.nextCursor else { break }
                            guard seen.insert(next).inserted else {
                                throw CatalogHealthExportError.repeatedCursor
                            }
                            cursor = next
                        } while true
                        summaries = cards
                    }
                    var summaryIssue = Evidence()
                    if [.onePiece, .lorcana, .yuGiOh].contains(game),
                       let expected = set.cardCount, expected != summaries.count {
                        summaryIssue.issue("SET_BROWSE_COUNT_MISMATCH",
                            "Active set declares \(expected) Browse entries but enumerated \(summaries.count).",
                            "Reconcile set list and current catalog generation")
                    }
                    if !summaryIssue.issues.isEmpty {
                        csv.append(row(kind: "set_summary", exported: date, build: build, game: game,
                                       set: set, evidence: summaryIssue, generation: activeGeneration,
                                       revision: snapshot?.revision ?? pokemonRevision ?? magicRevision, observedCount: summaries.count))
                    }
                    // Resolve price states through the same engine as Browse.
                    // Mapping authority remains per-finish; observed price is
                    // explicitly a card-summary aggregate, not a per-finish quote.
                    var priceUpdate: CatalogPriceUpdate?
                    if checkPrices && !summaries.isEmpty {
                        await progress("\(game.label): checking \(set.name) prices…")
                        for await update in browse.sortPriceUpdates(for: summaries) {
                            try Task.checkCancellation()
                            priceUpdate = update
                        }
                    }
                    for summary in summaries {
                        try Task.checkCancellation()
                        let findings = printingEvidence(for: summary, catalog: activeCatalog)
                        for original in findings {
                            var finding = original
                            let (status, aggregateUSD) = checkedPriceStatus(
                                summary, update: priceUpdate, evidence: &finding
                            )
                            if checkPrices && status == "not_checked" {
                                finding.issue("PRICE_CHECK_NOT_COMPLETED", "Browse did not return a price result for this card.", "Retry the catalog price check")
                            }
                            guard shouldExport(finding) else { continue }
                            csv.append(row(kind: "card", exported: date, build: build, game: game,
                                           set: set, card: summary, evidence: finding,
                                           priceStatus: status, price: aggregateUSD,
                                           generation: summary.catalogGeneration ?? activeGeneration,
                                           revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                                           scope: checkPrices ? "active_browse; price may be cached" : "active_browse; price not checked"))
                        }
                    }
                } catch CatalogLookupError.staleCatalog {
                    throw CatalogHealthExportError.catalogChanged
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    var issue = Evidence()
                    issue.issue("SET_ENUMERATION_FAILED", error.localizedDescription, "Recheck this set and active revision")
                    csv.append(row(kind: "set_error", exported: date, build: build, game: game,
                                   set: set, evidence: issue, generation: activeGeneration, scope: "not_fully_enumerated"))
                }
            }
            if let source = runtime?.activationSource {
                let latest = await source.currentSnapshot()
                if latest?.revision != snapshot?.revision {
                    throw CatalogHealthExportError.catalogChanged
                }
            }
            let latestPokemonRevision = await runtime?.legacyCatalogBindings.pokemon?.revision
            let latestMagicRevision = await runtime?.legacyCatalogBindings.magic?.revision
            if latestPokemonRevision != pokemonRevision || latestMagicRevision != magicRevision {
                throw CatalogHealthExportError.catalogChanged
            }
            if let runtime {
                auditedRevisions.append((runtime, snapshot?.revision, pokemonRevision, magicRevision))
            }
        }
        // An earlier game can activate a new release while a later game is
        // being enumerated. Never save a mixed or already-obsolete report.
        for (runtime, revision, pokemonRevision, magicRevision) in auditedRevisions {
            let activeRevision = await runtime.activationSource?.currentSnapshot()?.revision
            let pokemon = await runtime.legacyCatalogBindings.pokemon?.revision
            let magic = await runtime.legacyCatalogBindings.magic?.revision
            if activeRevision != revision || pokemon != pokemonRevision || magic != magicRevision {
                throw CatalogHealthExportError.catalogChanged
            }
        }
        return CollectionCSVDocument(text: csv)
    }

    private enum CatalogHealthExportError: LocalizedError {
        case repeatedCursor, catalogChanged
        var errorDescription: String? {
            switch self {
            case .repeatedCursor: "Catalog pagination repeated a cursor."
            case .catalogChanged: "A catalog update activated during export. Run the report again for a consistent snapshot."
            }
        }
    }
}
