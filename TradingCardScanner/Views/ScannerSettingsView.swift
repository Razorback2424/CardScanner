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
    /// Off by default: pricing every finish in all five games is the
    /// expensive path. Targeted price audits cover mapped finishes instead.
    @State private var checkLiveCatalogPrices = false
    @State private var priceAuditGame: CardGame = .onePiece
    @State private var priceAuditSet: CatalogSet?
    @State private var isChoosingPriceAuditSet = false
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
                    prepareCatalogHealthExport(scope: .fullCatalog(checkPrices: checkLiveCatalogPrices))
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
                Text("Exports catalog issues across all five games, including cards you don’t own. Magic reads Scryfall’s daily card file (about 80 MB). Checking every price sends many requests; use a price audit to check mapped prices for one game or set.")
                    .font(.footnote).foregroundStyle(.secondary)

                Picker("Price audit game", selection: $priceAuditGame) {
                    ForEach(ActiveCatalogHealthCSV.games, id: \.self) { game in
                        Text(game.label).tag(game)
                    }
                }
                .disabled(isPreparingCatalogHealthExport)
                .onChange(of: priceAuditGame) { _, _ in priceAuditSet = nil }
                Button {
                    isChoosingPriceAuditSet = true
                } label: {
                    LabeledContent("Price audit set", value: priceAuditSet?.name ?? "All sets")
                }
                .disabled(runtimes == nil || isPreparingCatalogHealthExport)
                .sheet(isPresented: $isChoosingPriceAuditSet) {
                    if let browse = catalogHealthBrowse() {
                        PriceAuditSetPicker(game: priceAuditGame, browse: browse, selection: $priceAuditSet)
                    }
                }
                Button("Export Price Audit", systemImage: "dollarsign.arrow.circlepath") {
                    prepareCatalogHealthExport(scope: .priceAudit(game: priceAuditGame, setID: priceAuditSet?.catalogID),
                                               auditSet: priceAuditSet)
                }
                .disabled(runtimes == nil || isPreparingCatalogHealthExport || isPreparingCSVExport ||
                          writeCoordinator.activeExclusiveOperation != nil)
                Text("Prices only verified printings with approved marketplace mappings, reusing cached prices and grouped price feeds. Stops early if a provider limits requests. The file lists pricing failures only.")
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

    /// The same Browse actor as the running app, including its active catalog
    /// revisions, in-session price observations and shared Scryfall pacing.
    private func catalogHealthBrowse() -> BrowseCatalog? {
        guard let runtimes else { return nil }
        return (sharedBrowseCatalog as Any as? BrowseCatalog) ?? runtimes.makeBrowseCatalog()
    }

    private func prepareCatalogHealthExport(scope: ActiveCatalogHealthCSV.Scope, auditSet: CatalogSet? = nil) {
        guard !isPreparingCatalogHealthExport, !isPreparingCSVExport,
              writeCoordinator.activeExclusiveOperation == nil, let runtimes,
              let browse = catalogHealthBrowse() else { return }
        isPreparingCatalogHealthExport = true
        catalogHealthExportProgress = "Reading active catalog…"
        catalogHealthExportTask = Task { @MainActor in
            defer {
                isPreparingCatalogHealthExport = false
                catalogHealthExportTask = nil
            }
            do {
                let document = try await ActiveCatalogHealthCSV.makeDocument(
                    runtimes: runtimes, browse: browse, scope: scope
                ) { message in
                    catalogHealthExportProgress = message
                }
                try Task.checkCancellation()
                csvExportDocument = document
                csvExportFilename = ActiveCatalogHealthCSV.auditFilename(for: scope, set: auditSet)
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

    
/// Chooses one active set for a targeted price audit, or all sets.
private struct PriceAuditSetPicker: View {
    let game: CardGame
    let browse: BrowseCatalog
    @Binding var selection: CatalogSet?
    @Environment(\.dismiss) private var dismiss
    @State private var sets: [CatalogSet] = []
    @State private var query = ""
    @State private var loadError: String?
    @State private var isLoading = true

    private var filtered: [CatalogSet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sets }
        return sets.filter { $0.name.localizedCaseInsensitiveContains(trimmed) || $0.code.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    choice(title: "All sets", subtitle: nil, isSelected: selection == nil) { selection = nil }
                }
                if isLoading {
                    ProgressView()
                } else if let loadError {
                    Text(loadError).foregroundStyle(.secondary)
                } else if filtered.isEmpty, !query.isEmpty {
                    Text("No matching sets").foregroundStyle(.secondary)
                }
                ForEach(filtered) { set in
                    choice(title: set.name, subtitle: set.code, isSelected: selection?.catalogID == set.catalogID) {
                        selection = set
                    }
                }
            }
            .searchable(text: $query, prompt: "Set name or code")
            .navigationTitle("\(game.label) Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                do {
                    sets = try await browse.sets(for: game)
                } catch is CancellationError {
                    return
                } catch {
                    loadError = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func choice(title: String, subtitle: String?, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button {
            select()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// A read-only report of the catalog Browse actually uses. This deliberately
// does not scan a user's collection or equate "not checked" with "unpriced".
enum ActiveCatalogHealthCSV {
    static let games: [CardGame] = [.pokemon, .magic, .onePiece, .lorcana, .yuGiOh]
    static let headers = [
        "record_type", "exported_at_utc", "app_build", "game", "set_name", "set_code",
        "active_release_revision", "expected_set_card_count", "enumerated_set_row_count",
        "product_set_id", "catalog_generation", "set_notice", "card_name",
        "card_number", "catalog_card_id", "printing_id", "finish_id",
        "verification_status", "market_mapping_status", "price_status",
        "finish_price_usd", "market_provider", "market_group_id",
        "market_product_id", "market_product_name", "market_number",
        "market_lane", "issue_codes", "issue_details", "recommended_action",
        "card_notice", "image_url", "evidence_scope", "pokemon_print_run", "magic_treatments",
        "price_source", "price_fetched_at_utc", "price_source_updated_at_utc", "price_listing",
        "finish_records", "checked_finishes", "issue_finishes", "unevaluated_finishes",
        "rows_without_finish", "complete_sets", "incomplete_sets", "deferred_sets",
        "actionable_rows", "blocked_price_finishes", "shared_issue_records", "shared_family_codes",
        "artwork_id", "price_audit_excluded_finishes"
    ]

    /// What one export examines.
    enum Scope: Equatable, Sendable {
        /// Every active set in all five games: identity and coverage, plus
        /// price evidence when `checkPrices` is on.
        case fullCatalog(checkPrices: Bool)
        /// Price checks for one game, optionally one set, limited to verified
        /// printings with approved marketplace mappings. Only pricing failures
        /// are exported; catalog identity problems belong to the full report.
        case priceAudit(game: CardGame, setID: CatalogSetID?)

        var checksPrices: Bool {
            switch self {
            case let .fullCatalog(checkPrices): checkPrices
            case .priceAudit: true
            }
        }

        var isPriceAudit: Bool {
            if case .priceAudit = self { return true }
            return false
        }
    }

    /// Issue codes that describe a failed or unusable price check, as opposed
    /// to catalog identity or coverage evidence.
    static let pricingIssueCodes: Set<String> = [
        "NO_USD_QUOTE", "INVALID_USD_QUOTE", "PRICE_EVIDENCE_STALE", "PRICE_CHECK_NOT_COMPLETED",
        "PRICE_PROVIDER_UNAVAILABLE", "PRICE_CHECK_FAILED", "PRICE_RESPONSE_INVALID",
        "PRICE_MAPPING_MISSING", "PRICE_IDENTITY_MISMATCH", "PRICE_UNSUPPORTED",
        "PRICE_PRINTING_NOT_FOUND", "FINISH_NOT_EVALUATED"
    ]

    /// Consecutive provider failures after which a price audit stops sending
    /// requests. A rate-limit response stops it immediately.
    static let auditProviderFailureLimit = 3

    /// Whether a card can have an approved marketplace mapping at all. Checked
    /// before loading provider details so an audit never spends a request on a
    /// card it will not price.
    static func isPriceAuditCandidate(_ summary: CatalogCardSummary, findings: [Evidence]) -> Bool {
        switch summary.game {
        case .magic:
            // Prices come from the exact Scryfall printing that enumeration
            // already returned; there is no separate marketplace mapping.
            true
        case .pokemon:
            // Only this card's own reviewed products name an approved finish
            // lane. Sharing a set with reviewed cards is not enough, and a
            // product-level TCGCSV mapping does not establish which physical
            // finishes it prices (`reviewed_product_finish_not_evaluated`).
            PokemonReviewedMarketProduct.entry(for: summary) != nil
                || PokemonBattleDeckFinishCatalog.hasReviewedFinishes(for: summary)
        default:
            findings.contains { $0.mapping == "exact" }
        }
    }

    /// Whether one finish of a candidate card is in a price audit's scope.
    static func isInPriceAuditScope(_ finding: Evidence, summary: CatalogCardSummary) -> Bool {
        switch summary.game {
        case .magic:
            !finding.finish.isEmpty
        case .pokemon:
            !finding.finish.isEmpty
                && PokemonReviewedMarketProduct.entry(for: summary, variantID: finding.finish)?.variant.id == finding.finish
        default:
            finding.mapping == "exact"
        }
    }

    /// A provider response that asks the caller to slow down.
    static func isThrottle(_ error: Error) -> Bool {
        switch error {
        case ScryfallError.rateLimited, PokemonTCGCSVError.retryLater: true
        case let failure as CatalogHealthScryfallFailure: failure.httpStatus == 429
        default: false
        }
    }

    static func auditFilename(for scope: Scope, set: CatalogSet?) -> String {
        guard case let .priceAudit(game, _) = scope else { return "ScanStash Active Catalog Health" }
        return ["ScanStash Price Audit", game.label, set?.code].compactMap { $0 }.joined(separator: " - ")
    }

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
        var priceSource: String = ""
        var fetchedAt: Date?
        var sourceUpdatedAt: Date?
        var priceListing: String = ""
        var artworkID = ""
        var familyCode = ""
        var issues: [String] = []
        var details: [String] = []
        var actions: [String] = []

        mutating func issue(_ code: String, _ detail: String, _ action: String) {
            guard !issues.contains(code) else { return }
            issues.append(code)
            details.append(detail)
            actions.append(action)
        }

        mutating func retainIssues(in codes: Set<String>) {
            let kept = issues.indices.filter { codes.contains(issues[$0]) }
            issues = kept.map { issues[$0] }
            details = kept.map { details[$0] }
            actions = kept.map { actions[$0] }
        }

        mutating func removeIssue(_ code: String) -> Bool {
            guard let index = issues.firstIndex(of: code) else { return false }
            issues.remove(at: index)
            details.remove(at: index)
            actions.remove(at: index)
            return true
        }
    }

    struct Coverage {
        var finishes = 0
        var checked = 0
        var issues = 0
        var unevaluated = 0
        var withoutFinish = 0
        var completeSets = 0
        var incompleteSets = 0
        var deferredSets = 0
        var actionableRows = 0
        var blockedPrices = 0
        /// Finishes a price audit left out because they lack a verified
        /// printing or an approved marketplace mapping.
        var auditExcluded = 0

        mutating func add(_ other: Self) {
            auditExcluded += other.auditExcluded
            finishes += other.finishes
            checked += other.checked
            issues += other.issues
            unevaluated += other.unevaluated
            withoutFinish += other.withoutFinish
            completeSets += other.completeSets
            incompleteSets += other.incompleteSets
            deferredSets += other.deferredSets
            actionableRows += other.actionableRows
            blockedPrices += other.blockedPrices
        }
    }

    struct FamilyCoverage {
        private(set) var affectedRecords = 0
        private(set) var codes = Set<String>()

        mutating func collect(from evidence: inout Evidence, printedCode: String) {
            guard evidence.removeIssue("PRINTING_FAMILY_INCOMPLETE") else { return }
            affectedRecords += 1
            if !printedCode.isEmpty { codes.insert(printedCode) }
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
        scope: String = "active_browse", coverage: Coverage? = nil,
        families: FamilyCoverage? = nil
    ) -> String {
        let issues = evidence.issues.joined(separator: "|")
        let details = evidence.details.joined(separator: " | ")
        return line([
            kind, exported, build, game.rawValue, set?.name ?? "", set?.code ?? "",
            revision.map(String.init) ?? "", set?.cardCount.map(String.init) ?? "",
            observedCount.map(String.init) ?? "",
            set?.providerID ?? "", generation.isEmpty ? card?.catalogGeneration ?? "" : generation,
            kind == "set_coverage" ? set?.collectionAvailabilityNotice ?? "" : "", card?.name ?? "",
            card?.collectorNumber ?? "", card?.providerID ?? "",
            card.flatMap { UUID(uuidString: $0.providerID) != nil ? $0.providerID : nil } ?? "",
            evidence.finish, evidence.verification, evidence.mapping, priceStatus,
            price.map { String($0) } ?? "", evidence.provider, evidence.group,
            evidence.product, evidence.productName, evidence.marketNumber, evidence.lane,
            issues, details, evidence.actions.joined(separator: " | "),
            note.isEmpty ? card?.collectionAvailabilityNotice ?? "" : note,
            card?.imageURL?.absoluteString ?? "", scope, card?.pokemonPrintRun?.rawValue ?? "",
            card?.magicTreatmentIDsRaw.joined(separator: "|") ?? "",
            evidence.priceSource, evidence.fetchedAt?.ISO8601Format() ?? "",
            evidence.sourceUpdatedAt?.ISO8601Format() ?? "", evidence.priceListing,
            coverage.map { String($0.finishes) } ?? "", coverage.map { String($0.checked) } ?? "",
            coverage.map { String($0.issues) } ?? "", coverage.map { String($0.unevaluated) } ?? "",
            coverage.map { String($0.withoutFinish) } ?? "",
            coverage.map { String($0.completeSets) } ?? "", coverage.map { String($0.incompleteSets) } ?? "",
            coverage.map { String($0.deferredSets) } ?? "", coverage.map { String($0.actionableRows) } ?? "",
            coverage.map { String($0.blockedPrices) } ?? "", families.map { String($0.affectedRecords) } ?? "",
            families?.codes.sorted().joined(separator: "|") ?? "", evidence.artworkID,
            coverage.map { String($0.auditExcluded) } ?? ""
        ])
    }

    static func priceStatus(
        _ lookup: PriceLookup, checkedAt: Date, evidence: inout Evidence
    ) -> (status: String, amount: Double?) {
        switch lookup {
        case let .price(quote):
            evidence.priceSource = quote.source.rawValue
            evidence.priceListing = quote.sourceVariantID
            evidence.fetchedAt = quote.fetchedAt
            evidence.sourceUpdatedAt = quote.sourceUpdatedAt
            guard quote.isUsableUSD else {
                evidence.issue("INVALID_USD_QUOTE", "The exact finish returned an unusable USD amount.", "Inspect the provider quote")
                return ("invalid_quote", nil)
            }
            guard !quote.isStale(now: checkedAt) else {
                evidence.issue("PRICE_EVIDENCE_STALE", "The exact finish quote exceeds the app’s price freshness threshold.", "Refresh the provider quote")
                return ("stale", quote.unitMarketPriceUSD)
            }
            return ("priced", quote.unitMarketPriceUSD)
        case let .unavailable(source):
            guard let source else {
                evidence.issue("PRICE_CHECK_NOT_COMPLETED", "No provider reported a result for this exact finish.", "Check exact finish coverage and retry")
                return ("not_checked", nil)
            }
            evidence.priceSource = source.rawValue
            evidence.issue("NO_USD_QUOTE", "The pricing source returned no accepted USD quote for this exact finish.", "Inspect the provider listing")
            return ("no_usd_quote", nil)
        }
    }

    static func recordPriceError(_ error: Error, evidence: inout Evidence) -> String {
        let code: String
        let reason: String
        switch error {
        case PriceQuoteError.mappingUnavailable:
            code = "PRICE_MAPPING_MISSING"
            reason = "The pricing resolver has no approved product mapping for this finish."
        case PriceQuoteError.identityMismatch, PokemonTCGCSVError.identityMismatch, ScryfallError.identityMismatch, TCGdexError.identityMismatch:
            code = "PRICE_IDENTITY_MISMATCH"
            reason = "The provider identity disagrees with the expected printing or finish."
        case PriceQuoteError.pricingUnsupported, ScryfallError.unsupportedPrinting, PokemonTCGCSVError.unsupportedSet:
            code = "PRICE_UNSUPPORTED"
            reason = "The pricing resolver does not support this printing, finish, or set."
        case PriceQuoteError.providerUnavailable, ScryfallError.providerUnavailable, ScryfallError.rateLimited,
             PokemonTCGCSVError.retryLater, TCGdexError.providerUnavailable, is URLError:
            code = "PRICE_PROVIDER_UNAVAILABLE"
            reason = "The provider check could not complete (\(String(reflecting: type(of: error))), code \((error as NSError).code))."
        case is DecodingError, PokemonTCGCSVError.invalidResponse, BrowseCatalogError.badResponse,
             ScryfallError.badResponse, TCGdexError.badResponse:
            code = "PRICE_RESPONSE_INVALID"
            reason = "The provider response could not be validated."
        case ScryfallError.cardNotFound, TCGdexError.cardNotFound:
            code = "PRICE_PRINTING_NOT_FOUND"
            reason = "The source did not return the exact printing listed in Browse."
        default:
            code = "PRICE_CHECK_FAILED"
            reason = "The exact finish check failed (\(String(reflecting: type(of: error))), code \((error as NSError).code))."
        }
        evidence.issue(code, reason, "Inspect the exact printing and provider evidence")
        return code.lowercased()
    }

    static func magicPrice(
        _ printing: ScryfallCard, card: IdentifiedCard, finish: PhysicalVariant,
        retrievedAt: Date, checkedAt: Date, evidence: inout Evidence
    ) -> (status: String, amount: Double?) {
        guard printing.finishes?.contains(finish.id) == true,
              let listing = CardPricing.scryfallListing(for: finish) else {
            evidence.issue("PRICE_UNSUPPORTED", "The exact Scryfall printing does not advertise a supported USD price field for this finish.", "Review Scryfall finish evidence")
            return ("unsupported", nil)
        }
        evidence.priceSource = PriceSource.scryfall.rawValue
        evidence.fetchedAt = retrievedAt
        evidence.priceListing = listing
        if let product = printing.tcgplayerProductID(for: finish) {
            evidence.provider = "tcgplayer"
            evidence.product = String(product)
            evidence.mapping = "provider_product"
        } else {
            evidence.mapping = "product_id_missing"
            evidence.issue("MARKET_PRODUCT_ID_MISSING", "Scryfall did not publish a numeric TCGplayer product ID for this finish.", "Review Scryfall marketplace links")
        }
        guard let prices = printing.prices else {
            return priceStatus(.unavailable(nil), checkedAt: checkedAt, evidence: &evidence)
        }
        let rawPrice = switch listing {
        case "usd": prices.usd
        case "usd_foil": prices.usdFoil
        default: prices.usdEtched
        }
        if rawPrice == nil {
            if checkedAt.timeIntervalSince(retrievedAt) > PriceDisplay.staleAfter {
                evidence.issue("PRICE_EVIDENCE_STALE", "The Scryfall observation for \(listing) is too old to establish current availability.", "Refresh the Scryfall printing")
                return ("stale_unverified", nil)
            }
            evidence.issue("NO_USD_QUOTE", "Scryfall \(listing) has no usable value for this exact printing and finish.", "Inspect the Scryfall printing")
            return ("no_usd_quote", nil)
        }
        guard let amount = prices.value(forKey: listing), amount.isFinite, amount >= 0 else {
            evidence.issue("INVALID_USD_QUOTE", "Scryfall \(listing) contains an invalid USD amount.", "Inspect the Scryfall printing")
            return ("invalid_quote", nil)
        }
        return priceStatus(CardPricing.price(for: card, variant: finish,
                           magicTreatments: card.magicTreatments(for: finish), at: retrievedAt),
                           checkedAt: checkedAt, evidence: &evidence)
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
            base.artworkID = printing.artworkID.uuidString
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
                base.familyCode = printing.code
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
        checkPrices: Bool,
        loadMagicSet: ((CatalogSet) async throws -> [(CatalogCardSummary, CatalogCardDetails)])? = nil,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> CollectionCSVDocument {
        try await makeDocument(runtimes: runtimes, browse: browse, scope: .fullCatalog(checkPrices: checkPrices),
                               loadMagicSet: loadMagicSet, progress: progress)
    }

    static func makeDocument(
        runtimes: CardGameRuntimeContainer, browse: any BrowseCatalogProviding,
        scope: Scope,
        loadMagicSet: ((CatalogSet) async throws -> [(CatalogCardSummary, CatalogCardDetails)])? = nil,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> CollectionCSVDocument {
        let checkPrices = scope.checksPrices
        let date = ISO8601DateFormatter().string(from: .now)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        var csv = line(headers)
        let examinedGames: [CardGame]
        let auditSetID: CatalogSetID?
        if case let .priceAudit(game, setID) = scope {
            examinedGames = [game]
            auditSetID = setID
        } else {
            examinedGames = games
            auditSetID = nil
        }
        // Magic enumeration source. A full report reads Scryfall's daily bulk
        // file once; a single-set audit is a few paced searches. Scryfall
        // asks for bulk data whenever many cards are looked up.
        var magicEvidenceScope = "scryfall_enumeration_response"
        var magicLoader = loadMagicSet
        if magicLoader == nil, examinedGames.contains(.magic), let catalog = browse as? BrowseCatalog {
            if auditSetID != nil {
                magicLoader = { set in try await catalog.catalogHealthMagicSet(set) }
            } else {
                let source = await catalog.catalogHealthMagicBulkSource(progress: progress)
                magicLoader = { set in try await source.entries(for: set) }
                magicEvidenceScope = "scryfall_bulk_data"
            }
        }
        var auditedRevisions: [(CardGameRuntime, Int?, Int?, Int?)] = []
        for game in examinedGames {
            try Task.checkCancellation()
            await progress("Reading \(game.label)…")
            let runtime = runtimes.runtime(for: game)
            let pokemonRevision = await runtime?.legacyCatalogBindings.pokemon?.revision
            let magicRevision = await runtime?.legacyCatalogBindings.magic?.revision
            var snapshot = await runtime?.activationSource?.currentSnapshot()
            var activeCatalog = snapshot?.catalog ?? runtime?.catalog
            var activeGeneration = activeCatalog?.generation ?? ""
            var sets: [CatalogSet]
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
            } else if let auditSetID {
                sets = sets.filter { $0.catalogID == auditSetID }
                if sets.isEmpty {
                    var issue = Evidence()
                    issue.issue("AUDIT_SET_NOT_ACTIVE", "The selected set (\(auditSetID.providerID)) is not in this game's active Browse catalog.",
                                "Choose a set from the current catalog")
                    csv.append(row(kind: "game_error", exported: date, build: build, game: game,
                                   evidence: issue, generation: activeGeneration, scope: "not_enumerated"))
                }
            }
            if scope.isPriceAudit {
                csv.append(row(kind: "audit_scope", exported: date, build: build, game: game,
                               set: auditSetID == nil ? nil : sets.first, generation: activeGeneration,
                               note: "Price audit of \(auditSetID == nil ? "all active sets" : "one set"). Only verified printings with approved marketplace mappings are priced (Magic: each Scryfall printing; Pokémon: reviewed TCGplayer products). Rows list pricing failures only; run the full Catalog Health report for identity issues.",
                               revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                               scope: "price_audit"))
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
            var gameCoverage = Coverage()
            var magicDeferredReason: String?
            var consecutiveMagicFailures = 0
            // A price audit stops sending price requests once a provider
            // throttles it or fails repeatedly, and reports the rest as deferred.
            var auditStopReason: String?
            var consecutiveProviderFailures = 0
            for (index, set) in sets.enumerated() {
                try Task.checkCancellation()
                if index.isMultiple(of: 10) || index == sets.count - 1 {
                    await progress("\(game.label): set \(index + 1) of \(sets.count)")
                }
                if let auditStopReason {
                    gameCoverage.deferredSets += 1
                    var issue = Evidence()
                    issue.issue("PRICE_AUDIT_STOPPED", auditStopReason, "Retry the audit later; provider limits were reached")
                    csv.append(row(kind: "set_deferred", exported: date, build: build, game: game,
                                   set: set, evidence: issue, generation: activeGeneration,
                                   revision: snapshot?.revision ?? pokemonRevision ?? magicRevision, scope: "set_not_examined"))
                    continue
                }
                if let magicDeferredReason {
                    gameCoverage.deferredSets += 1
                    var issue = Evidence()
                    issue.provider = "scryfall"
                    issue.issue("SET_ENUMERATION_DEFERRED", magicDeferredReason, "Retry after Scryfall is available")
                    csv.append(row(kind: "set_deferred", exported: date, build: build, game: game,
                                   set: set, evidence: issue, generation: activeGeneration,
                                   revision: snapshot?.revision ?? magicRevision, scope: "set_not_examined"))
                    continue
                }
                do {
                    let summaries: [CatalogCardSummary]
                    var magicDetails: [String: CatalogCardDetails] = [:]
                    if game == .magic, let magicLoader {
                        let entries = try await magicLoader(set)
                        summaries = entries.map { $0.0 }
                        if checkPrices {
                            magicDetails = Dictionary(uniqueKeysWithValues: entries.map { ($0.0.providerID, $0.1) })
                        }
                    } else if let complete = try await browse.completeLocalCards(in: set) {
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
                    if !scope.isPriceAudit, [.onePiece, .lorcana, .yuGiOh].contains(game),
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
                    var setCoverage = Coverage()
                    setCoverage.completeSets = 1
                    var sharedFamilies = FamilyCoverage()
                    if checkPrices {
                        await progress("\(game.label): checking \(set.name) finishes…")
                        if game == .pokemon, let catalog = browse as? BrowseCatalog {
                            await catalog.preparePokemonBulkPrices(for: summaries)
                        }
                    }
                    for summary in summaries {
                        try Task.checkCancellation()
                        var findings = printingEvidence(for: summary, catalog: activeCatalog)
                        if scope.isPriceAudit, !isPriceAuditCandidate(summary, findings: findings) {
                            setCoverage.auditExcluded += findings.count
                            continue
                        }
                        var details: CatalogCardDetails?
                        var detailError: Error?
                        // A single printing payload supplies all Magic finishes and USD fields.
                        // Pokémon normally enumerates one expected finish per checklist slot.
                        if checkPrices, auditStopReason == nil,
                           game == .magic || (game == .pokemon && summary.masterSetVariant == nil) {
                            do {
                                let loaded: CatalogCardDetails
                                if let fromPage = magicDetails[summary.providerID] {
                                    loaded = fromPage
                                } else {
                                    loaded = try await browse.details(for: summary)
                                }
                                details = loaded
                                let variants = loaded.card.variantEvidence.catalogVariants
                                if !variants.isEmpty {
                                    let original = findings[0]
                                    findings = Set(variants.map(\.id)).sorted().map { finish in
                                        var finding = original
                                        finding.finish = finish
                                        return finding
                                    }
                                }
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch CatalogLookupError.staleCatalog {
                                throw CatalogLookupError.staleCatalog
                            } catch {
                                detailError = error
                            }
                        }
                        for original in findings {
                            try Task.checkCancellation()
                            // A candidate whose provider details failed to load has no
                            // finishes to judge; report the failed lookup instead of
                            // counting it as excluded.
                            if scope.isPriceAudit, detailError == nil, !isInPriceAuditScope(original, summary: summary) {
                                setCoverage.auditExcluded += 1
                                continue
                            }
                            var finding = original
                            var status = "not_checked"
                            var amount: Double?
                            var priceError: Error?
                            if checkPrices, let auditStopReason {
                                finding.issue("PRICE_CHECK_DEFERRED", auditStopReason, "Retry the audit later")
                            } else if checkPrices {
                                if let detailError {
                                    priceError = detailError
                                    status = recordPriceError(detailError, evidence: &finding)
                                } else if finding.finish.isEmpty {
                                    finding.issue("FINISH_NOT_EVALUATED", "The active card record does not identify a finish to check.", "Review physical finish evidence")
                                } else {
                                    let finish = PhysicalVariant.resolving(finding.finish)
                                    let checkedAt = Date.now
                                    do {
                                        if let details, case let .magic(printing) = details.card.legacyIdentity {
                                            guard printing.id.caseInsensitiveCompare(summary.providerID) == .orderedSame else {
                                                throw PriceQuoteError.identityMismatch
                                            }
                                            (status, amount) = magicPrice(printing, card: details.card, finish: finish,
                                                retrievedAt: details.retrievedAt, checkedAt: checkedAt, evidence: &finding)
                                        } else if game == .magic {
                                            throw PriceQuoteError.identityMismatch
                                        } else {
                                            let reviewed = game == .pokemon
                                                ? PokemonReviewedMarketProduct.entry(for: summary, variantID: finish.id) : nil
                                            if let reviewed, reviewed.variant.id == finish.id {
                                                finding.provider = "tcgplayer"
                                                finding.product = String(reviewed.productID)
                                                finding.group = String(reviewed.groupID)
                                                finding.productName = reviewed.marketName
                                                finding.marketNumber = reviewed.number
                                                finding.lane = reviewed.printing
                                                finding.mapping = "reviewed_product"
                                            }
                                            let bulk = await (browse as? BrowseCatalog)?.catalogHealthBulkQuote(for: summary, variant: finish)
                                            var lookup: PriceLookup
                                            if let bulk {
                                                lookup = .price(bulk)
                                            } else if let catalog = browse as? BrowseCatalog {
                                                lookup = try await catalog.price(for: summary, variant: finish, catalogHealthCheck: true)
                                            } else {
                                                lookup = try await browse.price(for: summary, variant: finish)
                                            }
                                            if game == .pokemon, case .unavailable(.tcgplayer) = lookup {
                                                // TCGdex can return this for a blocked or absent exact lane.
                                                // Only a source that confirms the finish can establish no quote.
                                                lookup = .unavailable(nil)
                                            }
                                            (status, amount) = priceStatus(lookup, checkedAt: checkedAt, evidence: &finding)
                                            if game == .pokemon, shouldExport(finding), finding.product.isEmpty,
                                               let loaded = try? await browse.details(for: summary),
                                               let product = CardPricing.tcgplayerProductID(for: loaded.card, variant: finish, printRun: summary.pokemonPrintRun) {
                                                finding.provider = "tcgplayer"
                                                finding.product = String(product)
                                                finding.mapping = "provider_product"
                                            }
                                        }
                                    } catch is CancellationError {
                                        throw CancellationError()
                                    } catch CatalogLookupError.staleCatalog {
                                        throw CatalogLookupError.staleCatalog
                                    } catch {
                                        priceError = error
                                        status = recordPriceError(error, evidence: &finding)
                                    }
                                }
                            }
                            if scope.isPriceAudit, auditStopReason == nil, status != "not_checked" || priceError != nil {
                                let throttled = priceError.map(isThrottle) ?? false
                                if throttled || status == "price_provider_unavailable" {
                                    consecutiveProviderFailures += 1
                                } else {
                                    consecutiveProviderFailures = 0
                                }
                                if throttled || consecutiveProviderFailures >= auditProviderFailureLimit {
                                    auditStopReason = throttled
                                        ? "A pricing provider asked the audit to slow down at \(set.code) \(summary.collectorNumber). Price checks stopped to respect its limits."
                                        : "Price checks stopped at \(set.code) \(summary.collectorNumber) after \(consecutiveProviderFailures) consecutive provider failures."
                                }
                            }
                            let familyCode = finding.familyCode
                            sharedFamilies.collect(from: &finding, printedCode: familyCode)
                            if scope.isPriceAudit {
                                // Identity and coverage findings belong to the full report.
                                finding.retainIssues(in: pricingIssueCodes)
                            }
                            let hasIssue = shouldExport(finding)
                            let blockageCodes = ["PRICE_PROVIDER_UNAVAILABLE", "PRICE_CHECK_FAILED",
                                                 "PRICE_RESPONSE_INVALID", "PRICE_CHECK_NOT_COMPLETED", "FINISH_NOT_EVALUATED"]
                            let hasActionableIssue = finding.issues.contains { !blockageCodes.contains($0) }
                            if hasActionableIssue { setCoverage.actionableRows += 1 }
                            if !finding.finish.isEmpty {
                                setCoverage.finishes += 1
                                if ["priced", "no_usd_quote", "stale", "stale_unverified", "invalid_quote"].contains(status) {
                                    setCoverage.checked += 1
                                } else {
                                    setCoverage.unevaluated += 1
                                    if checkPrices { setCoverage.blockedPrices += 1 }
                                }
                                if hasIssue { setCoverage.issues += 1 }
                            } else {
                                setCoverage.withoutFinish += 1
                            }
                            guard hasIssue else { continue }
                            csv.append(row(kind: scope.isPriceAudit ? "price_failure" : "card",
                                           exported: date, build: build, game: game,
                                           set: set, card: summary, evidence: finding,
                                           priceStatus: status, price: amount,
                                           generation: summary.catalogGeneration ?? activeGeneration,
                                           revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                                           scope: !checkPrices ? "pricing_disabled"
                                               : status == "not_checked" || blockageCodes.contains(status.uppercased()) ? "price_check_incomplete"
                                               : game == .magic && magicDetails[summary.providerID] != nil ? magicEvidenceScope
                                               : "price_resolver_evidence_may_be_cached"))
                        }
                    }
                    gameCoverage.add(setCoverage)
                    consecutiveMagicFailures = 0
                    var sharedIssue = Evidence()
                    if sharedFamilies.affectedRecords > 0 {
                        sharedIssue.issue("PRINTING_FAMILY_INCOMPLETE",
                            "Shared catalog limitation across \(sharedFamilies.codes.count) printed-code families in this product. Counts can overlap between products.",
                            "Review printed-code families as groups")
                    }
                    csv.append(row(kind: "set_coverage", exported: date, build: build, game: game,
                                   set: set, evidence: sharedIssue, generation: activeGeneration,
                                   revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                                   observedCount: summaries.count,
                                   scope: checkPrices ? "enumeration_complete; see_finish_counts" : "enumeration_complete; pricing_disabled",
                                   coverage: setCoverage, families: sharedFamilies.affectedRecords > 0 ? sharedFamilies : nil))
                } catch CatalogLookupError.staleCatalog {
                    throw CatalogHealthExportError.catalogChanged
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    gameCoverage.incompleteSets += 1
                    var issue = Evidence()
                    let scryfallFailure = error as? CatalogHealthScryfallFailure
                    if game == .magic {
                        issue.provider = "scryfall"
                        // A response scoped to a single unmatched query does
                        // not establish a wider provider outage.
                        if scryfallFailure?.httpStatus == 404 || scryfallFailure?.setScoped == true {
                            consecutiveMagicFailures = 0
                        } else {
                            consecutiveMagicFailures += 1
                        }
                        if scryfallFailure?.defersProvider == true || consecutiveMagicFailures >= 3 {
                            magicDeferredReason = "Scryfall enumeration stopped at \(set.code). \(error.localizedDescription)"
                        }
                    }
                    issue.issue("SET_ENUMERATION_FAILED", error.localizedDescription, "Recheck this set and active revision")
                    csv.append(row(kind: "set_error", exported: date, build: build, game: game,
                                   set: set, evidence: issue, generation: activeGeneration,
                                   revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                                   observedCount: scryfallFailure?.observed, scope: "not_fully_enumerated"))
                }
            }
            csv.append(row(kind: "game_coverage", exported: date, build: build, game: game,
                           generation: activeGeneration, revision: snapshot?.revision ?? pokemonRevision ?? magicRevision,
                           coverage: gameCoverage))
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
        try Task.checkCancellation()
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
