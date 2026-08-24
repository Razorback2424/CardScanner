import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The scanner reduces friction according to certainty. The collection reduces
/// it according to intent: four chips and one sort menu answer nearly every
/// question a collector actually asks, and none of them touch the network.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CollectedCard.dateAdded, order: .reverse)
    private var cards: [CollectedCard]

    @Query private var priceRecords: [PriceRecord]
    @Query private var productIdentities: [ProductIdentity]

    @StateObject private var refresh = PriceRefreshController()
    @StateObject private var catalogNormalizer = CollectionCatalogNormalizer()
    @AppStorage("usesPriceFallback") private var usesPriceFallback = false

    @State private var searchText = ""
    /// What the grid is actually filtered by. Trails `searchText` by one short
    /// debounce so a large grid is not rebuilt on every keystroke.
    @State private var searchQuery = ""
    @State private var filters = CollectionFilters.none
    @State private var sort: CollectionSort = .priceHighToLow
    @State private var activeSheet: ActiveSheet?
    @State private var hasCheckedForStalePrices = false
    @State private var pendingRemoval: RemovedCardSnapshot?
    @State private var removalUndoTask: Task<Void, Never>?
    @State private var showsManualRefreshStatus = false
    @State private var refreshStatusTask: Task<Void, Never>?
    @State private var isShowingCSVImporter = false
    @State private var isShowingCSVExporter = false
    @State private var csvExportDocument: CollectionCSVDocument?
    @State private var csvExportFilename = "CardScanner Collection"
    @State private var lastSkippedCSVText: String?
    @State private var pendingCSVImport: CollectionCSVImportPlan?
    @State private var csvMessage: CSVMessage?
    @FocusState private var isSearchFocused: Bool

    private enum ActiveSheet: String, Identifiable {
        case set, price, finish, priceFallback
        var id: String { rawValue }
    }

    private struct CSVMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let skippedCSVText: String?

        init(title: String, message: String, skippedCSVText: String? = nil) {
            self.title = title
            self.message = message
            self.skippedCSVText = skippedCSVText
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    var body: some View {
        // Built once per render and threaded through. Filtering and sorting are
        // pure local work, but recomputing them separately for the header, the
        // grid and the refresh targets would do it four times for nothing.
        let snapshot = makeSnapshot()

        return NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Scan a card and it lands here.")
                    )
                } else {
                    content(snapshot)
                }
            }
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh Prices") {
                        Task { await refreshAllPrices() }
                    }
                    .disabled(isRefreshing)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu("Collection Actions", systemImage: "ellipsis.circle") {
                        Button("Import CSV", systemImage: "square.and.arrow.down") {
                            isShowingCSVImporter = true
                        }

                        Button("Export CSV", systemImage: "square.and.arrow.up") {
                            csvExportDocument = CollectionCSV.export(cards)
                            csvExportFilename = "CardScanner Collection"
                            isShowingCSVExporter = true
                        }
                        .disabled(cards.isEmpty)

                        Button("Export Skipped Rows", systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                            exportSkippedRows()
                        }
                        .disabled(lastSkippedCSVText == nil)

                        Divider()

                        Button("Export Unpriced Cards", systemImage: "dollarsign.circle") {
                            csvExportDocument = CollectionCSV.exportUnpriced(
                                cards,
                                priceRecords: priceRecords
                            )
                            csvExportFilename = "CardScanner Unpriced Cards"
                            isShowingCSVExporter = true
                        }
                        .disabled(snapshot.unpricedCount == 0)

                        Button("Export Missing Artwork", systemImage: "photo") {
                            csvExportDocument = CollectionCSV.exportMissingArtwork(
                                cards,
                                priceRecords: priceRecords
                            )
                            csvExportFilename = "CardScanner Missing Artwork"
                            isShowingCSVExporter = true
                        }
                        .disabled(!cards.contains { $0.highImageURL == nil })

                        Divider()

                        Button("Price Fallback Settings", systemImage: "dollarsign.arrow.circlepath") {
                            activeSheet = .priceFallback
                        }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Collection actions")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFocused = false
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .set:
                MultiSelectFilterSheet(title: "Sets", options: setOptions(snapshot), selection: $filters.setCodes)
            case .finish:
                MultiSelectFilterSheet(title: "Finish", options: finishOptions(snapshot), selection: $filters.variantIDs)
            case .price:
                PriceFilterSheet(selection: $filters.price)
            case .priceFallback:
                CollectionPriceFallbackSettingsView()
            }
        }
        .task(id: cards.count) { await refreshStalePricesIfNeeded() }
        .task { await catalogNormalizer.normalizeImportedCards(in: modelContext) }
        .task(id: fallbackAvailabilityTaskID(snapshot)) {
            await refresh.updateFallbackAvailability(pending: fallbackPendingCount(snapshot))
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            searchQuery = searchText
        }
        .onDisappear {
            refreshStatusTask?.cancel()
        }
        .safeAreaInset(edge: .bottom) {
            if let pendingRemoval {
                removalUndoBanner(pendingRemoval)
            }
        }
        .fileImporter(
            isPresented: $isShowingCSVImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case let .success(url):
                Task { await prepareCSVImport(from: url) }
            case let .failure(error):
                csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription)
            }
        }
        .fileExporter(
            isPresented: $isShowingCSVExporter,
            document: csvExportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: csvExportFilename
        ) { result in
            defer { csvExportDocument = nil }
            if case let .failure(error) = result {
                csvMessage = CSVMessage(title: "Export Failed", message: error.localizedDescription)
            }
        }
        .confirmationDialog(
            "Import CSV?",
            isPresented: Binding(
                get: { pendingCSVImport != nil },
                set: { if !$0 { pendingCSVImport = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let plan = pendingCSVImport {
                Button("Import \(plan.totalQuantity) Cards") {
                    importCSV(plan)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCSVImport = nil
            }
        } message: {
            if let plan = pendingCSVImport {
                Text(importConfirmationMessage(plan))
            }
        }
        .alert(item: $csvMessage) { message in
            if let skippedCSVText = message.skippedCSVText {
                return Alert(
                    title: Text(message.title),
                    message: Text(message.message),
                    primaryButton: .default(Text("Export Skipped Rows")) {
                        exportSkippedRows(skippedCSVText)
                    },
                    secondaryButton: .cancel(Text("Done"))
                )
            }
            return Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func content(_ snapshot: Snapshot) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header(snapshot)
                searchField
                filterBar(snapshot)

                if snapshot.entries.isEmpty {
                    noMatches
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(snapshot.entries) { entry in
                            NavigationLink {
                                CollectionCardDetailView(
                                    card: entry.card,
                                    price: entry.row.price,
                                    onRemoved: presentUndo(for:)
                                )
                            } label: {
                                CollectionCardTile(card: entry.card, price: entry.row.price)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refreshAllPrices() }
        .animation(.easeOut(duration: 0.2), value: filters)
        .animation(.easeOut(duration: 0.2), value: sort)
        .animation(.easeOut(duration: 0.2), value: searchQuery)
    }

    // MARK: - CSV transfer

    @MainActor
    private func prepareCSVImport(from url: URL) async {
        do {
            let plan = try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                return try CollectionCSV.parse(data)
            }.value
            pendingCSVImport = plan
        } catch {
            csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func importCSV(_ plan: CollectionCSVImportPlan) {
        pendingCSVImport = nil
        // A large imported collection should not immediately start hundreds of
        // network requests. Pricing remains an explicit toolbar action.
        hasCheckedForStalePrices = true

        do {
            let result = try CollectionCSV.apply(plan, to: modelContext)
            lastSkippedCSVText = plan.skippedCSVText
            Task { await catalogNormalizer.normalizeImportedCards(in: modelContext) }
            var details = "Added \(result.totalQuantity) cards across \(result.insertedEntries + result.mergedEntries) entries."
            if result.mergedEntries > 0 {
                details += " \(result.mergedEntries) matched existing entries."
            }
            if result.skippedRows > 0 {
                details += " Ignored \(result.skippedRows) unsupported, non-English, or non-card rows."
            }
            details += " Artwork loads automatically. Refresh prices when you're ready."
            csvMessage = CSVMessage(
                title: "Import Complete",
                message: details,
                skippedCSVText: plan.skippedCSVText
            )
        } catch {
            csvMessage = CSVMessage(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func importConfirmationMessage(_ plan: CollectionCSVImportPlan) -> String {
        var message = "Adds \(plan.totalQuantity) cards in \(plan.entries.count) entries. Matching entries will be combined."
        if plan.skippedRows > 0 {
            message += " \(plan.skippedRows) unsupported, non-English, or non-card rows will be ignored."
        }
        return message
    }

    private func exportSkippedRows(_ text: String? = nil) {
        guard let text = text ?? lastSkippedCSVText else { return }
        csvExportDocument = CollectionCSVDocument(text: text)
        csvExportFilename = "CardScanner Skipped Rows"
        isShowingCSVExporter = true
    }

    // MARK: - Removal undo

    private func presentUndo(for removed: RemovedCardSnapshot) {
        removalUndoTask?.cancel()
        pendingRemoval = removed

        removalUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, pendingRemoval?.id == removed.id else { return }
            pendingRemoval = nil
        }
    }

    private func undoRemoval(_ removed: RemovedCardSnapshot) {
        removalUndoTask?.cancel()
        removed.restore(in: modelContext)
        pendingRemoval = nil
    }

    private func removalUndoBanner(_ removed: RemovedCardSnapshot) -> some View {
        HStack(spacing: 12) {
            Text("Removed \(removed.name)")
                .font(.subheadline)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Undo") {
                undoRemoval(removed)
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityLabel("Undo removal of \(removed.name)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private func header(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.pricedValue, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.34))
                    .monospacedDigit()
                    .accessibilityLabel("Collection value")

                Spacer()

                if isNarrowed {
                    Text("\(snapshot.visibleQuantity) of \(snapshot.totalQuantity)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if snapshot.unpricedCount > 0 {
                Text("\(snapshot.unpricedCount) cop\(snapshot.unpricedCount == 1 ? "y" : "ies") unpriced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // These have a price; it is simply not in dollars, so it is missing
            // from the total above. Saying which is the difference between an
            // honest total and one that looks complete.
            if snapshot.otherCurrencyCount > 0 {
                Text(
                    "\(snapshot.otherCurrencyCount) cop\(snapshot.otherCurrencyCount == 1 ? "y" : "ies") priced in another currency, not included in total"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showsManualRefreshStatus {
                freshnessLabel
                    .padding(.top, 2)
            }

            catalogNormalizationLabel
            fallbackStatusLabel(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var catalogNormalizationLabel: some View {
        switch catalogNormalizer.status {
        case let .normalizing(total):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding artwork for \(total) cards…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case let .finished(matched, unmatched):
            Text(
                unmatched > 0
                    ? "Found artwork for \(matched) cards · \(unmatched) unmatched"
                    : "Card artwork updated"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .failed:
            Text("Artwork lookup will retry later")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fallbackStatusLabel(_ snapshot: Snapshot) -> some View {
        let pending = fallbackPendingCount(snapshot)
        if pending > 0 {
            Button {
                activeSheet = .priceFallback
            } label: {
                Label(fallbackStatusText(pending: pending), systemImage: fallbackStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(fallbackStatusColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens price fallback settings")
        }
    }

    private func fallbackStatusText(pending: Int) -> String {
        guard PriceVendorCredentials.hasKey else {
            return "Price fallback needs an API key · \(pending) card types waiting"
        }
        guard usesPriceFallback else {
            return "Price fallback is off · \(pending) card types waiting"
        }

        switch refresh.fallbackStatus {
        case let .available(remainingToday):
            return "\(pending) card types waiting · \(remainingToday) requests left today"
        case let .running(completed, total, remainingToday):
            return "Price fallback \(completed)/\(total) · \(remainingToday) requests left today"
        case let .finished(_, _, remainingToday):
            return "\(pending) card types still waiting · \(remainingToday) requests left today"
        case let .budgetReached(_, resetAt):
            return "Daily fallback budget reached · resumes after \(resetAt.formatted(date: .abbreviated, time: .shortened))"
        case let .rateLimited(_, retryAt):
            return "Price fallback paused by provider · retry after \(retryAt.formatted(date: .abbreviated, time: .shortened))"
        case .idle, .disabled, .unconfigured:
            return "\(pending) card types waiting for price fallback"
        }
    }

    private var fallbackStatusSymbol: String {
        switch refresh.fallbackStatus {
        case .budgetReached: return "calendar.badge.clock"
        case .rateLimited: return "pause.circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .idle, .disabled, .unconfigured, .available, .finished:
            return usesPriceFallback && PriceVendorCredentials.hasKey
                ? "dollarsign.circle"
                : "exclamationmark.circle"
        }
    }

    private var fallbackStatusColor: Color {
        switch refresh.fallbackStatus {
        case .budgetReached, .rateLimited: return .orange
        case .idle, .disabled, .unconfigured, .available, .running, .finished: return .secondary
        }
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        switch refresh.status {
        case let .refreshing(completed, total):
            Text("Checking prices… \(completed)/\(total) card types")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

        case let .finished(result):
            VStack(alignment: .leading, spacing: 1) {
                Label(
                    result.failed > 0
                        ? "Checked just now · \(result.failed) card types couldn't be reached"
                        : refreshSuccessText(result),
                    systemImage: result.failed > 0 ? "exclamationmark.triangle" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(result.failed > 0 ? Color.orange : Color.secondary)

                if !result.checkedUnstampedProvider, let asOf = result.latestSourceUpdate {
                    Text("Market data current through \(asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .recentlyChecked:
            Label("Prices were checked recently", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .idle:
            EmptyView()
        }
    }

    private func refreshSuccessText(_ result: PriceRefreshController.Summary) -> String {
        if result.changedPrices { return "Prices updated" }
        if result.checkedUnstampedProvider { return "Prices checked" }
        return result.foundNothingNewer
            ? "Checked just now · no newer market prices"
            : "Prices updated"
    }

    // MARK: - Search

    /// The fifth filter, and the simplest one. It composes with the chips rather
    /// than replacing them: typing a name narrows whatever view is already set up.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search cards", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($isSearchFocused)
                .onSubmit {
                    isSearchFocused = false
                }

            if !searchText.isEmpty {
                Button {
                    // Clears only the name search. The chips are a separate
                    // question and stay exactly as they were.
                    searchText = ""
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var isNarrowed: Bool {
        filters.isActive || !searchQuery.isEmpty
    }

    @ViewBuilder
    private var noMatches: some View {
        if !searchQuery.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
                .padding(.top, 24)
        } else {
            ContentUnavailableView(
                "Nothing matches these filters",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try clearing one of them.")
            )
            .padding(.top, 24)
        }
    }

    // MARK: - Filters

    private func filterBar(_ snapshot: Snapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All") { selectGame(nil) }
                    ForEach(CardGame.allCases) { game in
                        Button(game.label) { selectGame(game) }
                    }
                } label: {
                    FilterChipLabel(title: filters.game?.label ?? "Game", isActive: filters.game != nil)
                }

                FilterChip(
                    title: setChipTitle(snapshot),
                    isActive: !filters.setCodes.isEmpty
                ) { activeSheet = .set }

                FilterChip(
                    title: filters.price?.label ?? "Price",
                    isActive: filters.price != nil
                ) { activeSheet = .price }

                FilterChip(
                    title: finishChipTitle,
                    isActive: !filters.variantIDs.isEmpty
                ) { activeSheet = .finish }

                Divider().frame(height: 20)

                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CollectionSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    FilterChipLabel(title: "Sort", isActive: false, symbol: "arrow.up.arrow.down")
                }

                if filters.isActive {
                    Button("Clear") { filters = .none }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func setChipTitle(_ snapshot: Snapshot) -> String {
        switch filters.setCodes.count {
        case 0: return "Set"
        case 1:
            guard let selected = filters.setCodes.first else { return "Set" }
            return snapshot.all.first(where: { $0.setFilterID == selected })?.setCode ?? "Set"
        default: return "\(filters.setCodes.count) sets"
        }
    }

    /// Set and finish selections are scoped by game. Carrying them across a game
    /// change can leave an apparently active filter with no selectable option in
    /// the new game, producing an unexplained empty collection.
    private func selectGame(_ game: CardGame?) {
        guard filters.game != game else { return }
        filters.game = game
        filters.setCodes.removeAll()
        filters.variantIDs.removeAll()
    }

    private var finishChipTitle: String {
        switch filters.variantIDs.count {
        case 0: return "Finish"
        case 1:
            let id = filters.variantIDs.first ?? ""
            return PhysicalVariant.resolving(id).label
        default: return "\(filters.variantIDs.count) finishes"
        }
    }

    // MARK: - Data

    /// Everything one render of this screen needs, derived once.
    struct Snapshot {
        struct Entry: Identifiable {
            let row: CollectionRow
            let card: CollectedCard

            var id: String { row.id }
        }

        let all: [CollectionRow]
        let visible: [CollectionRow]
        let entries: [Entry]
        let totalQuantity: Int
        let visibleQuantity: Int
        /// Only what is actually priced. A total that quietly folds in unknowns
        /// is worse than an honest gap.
        let pricedValue: Double
        /// Copies whose price is real but quoted in another currency, so they
        /// are deliberately absent from `pricedValue` rather than converted at
        /// a rate this app has no live source for. Reported instead of hidden.
        let otherCurrencyCount: Int
        let unpricedCount: Int
        let pricesAsOf: Date?
        /// Whether `pricesAsOf` is a provider's own "current through" stamp or
        /// merely when this app last looked. The two get different wording.
        let isSourceStamped: Bool
        let cardsByKey: [String: CollectedCard]
        let recordsByKey: [String: PriceRecord]
    }

    @MainActor
    private func makeSnapshot() -> Snapshot {
        let recordsByKey = Dictionary(priceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let cardsByKey = Dictionary(cards.map { ($0.collectionKey, $0) }, uniquingKeysWith: { first, _ in first })

        let all = cards.map { card in
            CollectionRow(
                id: card.collectionKey,
                game: card.cardGame,
                name: card.name,
                setCode: card.setCode,
                setName: card.setName,
                setReleaseOrder: card.setReleaseOrder,
                cardNumber: card.cardNumber,
                variantID: card.variantID,
                variantLabel: card.variantLabel,
                quantity: card.quantity,
                dateAdded: card.dateAdded,
                price: recordsByKey[card.priceKey]?.display ?? .unknown
            )
        }

        let visible = CollectionQuery.apply(
            nameQuery: searchQuery,
            filters: filters,
            sort: sort,
            to: all
        )

        var pricedValue: Double = 0
        var unpriced = 0
        var otherCurrency = 0
        var visibleQuantity = 0
        for row in visible {
            visibleQuantity += row.quantity
            guard let price = row.unitPrice else {
                unpriced += row.quantity
                continue
            }
            // Summing euros into a dollar total would overstate the collection
            // by whatever the exchange rate happens to be. Without a live rate
            // the only honest options are to convert or to exclude, and this
            // app has no rate source — so it excludes, and says so.
            guard row.price.currencyCode == "USD" else {
                otherCurrency += row.quantity
                continue
            }
            pricedValue += price * Double(row.quantity)
        }

        // Freshness belongs to the collection currently being summarized, not to
        // unrelated hidden records. A mixed provider view cannot make a universal
        // provider-side freshness claim because Scryfall publishes no such stamp;
        // in that case report the oldest successful check instead.
        let relevantRecords = visible.compactMap { row -> PriceRecord? in
            guard let card = cardsByKey[row.id] else { return nil }
            return recordsByKey[card.priceKey]
        }
        let allSourceStamped = !relevantRecords.isEmpty && relevantRecords.allSatisfy {
            $0.source?.publishesSourceTimestamp == true && $0.sourceUpdatedAt != nil
        }
        let asOf: Date?
        if allSourceStamped {
            asOf = relevantRecords.compactMap(\.sourceUpdatedAt).min()
        } else {
            asOf = relevantRecords.compactMap { $0.lastCheckedAt ?? $0.fetchedAt }.min()
        }

        return Snapshot(
            all: all,
            visible: visible,
            entries: visible.compactMap { row -> Snapshot.Entry? in
                guard let card = cardsByKey[row.id] else { return nil }
                return Snapshot.Entry(row: row, card: card)
            },
            totalQuantity: all.reduce(0) { $0 + $1.quantity },
            visibleQuantity: visibleQuantity,
            pricedValue: pricedValue,
            otherCurrencyCount: otherCurrency,
            unpricedCount: unpriced,
            pricesAsOf: asOf,
            isSourceStamped: allSourceStamped,
            cardsByKey: cardsByKey,
            recordsByKey: recordsByKey
        )
    }

    /// Options come from the collection, narrowed by the game chip so a Pokémon
    /// session never has to scroll past Magic finishes.
    private func rowsForOptions(_ snapshot: Snapshot) -> [CollectionRow] {
        let searched = CollectionQuery.filter(snapshot.all, nameQuery: searchQuery, with: .none)
        guard let game = filters.game else { return searched }
        return searched.filter { $0.game == game }
    }

    /// Accumulator for building a filter option. A named type rather than a
    /// tuple: the tuple version of this made the type checker give up.
    private struct OptionTally {
        var label: String
        var group: String
        var groupOrder: String
        var count: Int
        var sortValue: Int
    }

    private func setOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rowsForOptions(snapshot) {
            if var existing = tallies[row.setFilterID] {
                existing.count += row.quantity
                tallies[row.setFilterID] = existing
            } else {
                tallies[row.setFilterID] = OptionTally(
                    label: row.setName,
                    group: row.game.label,
                    groupOrder: row.game.rawValue,
                    count: row.quantity,
                    // Newest set first.
                    sortValue: -row.setReleaseOrder
                )
            }
        }

        return orderedOptions(from: tallies)
    }

    private func finishOptions(_ snapshot: Snapshot) -> [FilterOption] {
        var tallies: [String: OptionTally] = [:]

        for row in rowsForOptions(snapshot) {
            guard let variant = row.variant else { continue }
            if var existing = tallies[variant.id] {
                existing.count += row.quantity
                tallies[variant.id] = existing
            } else {
                tallies[variant.id] = OptionTally(
                    label: variant.label,
                    group: row.game.label,
                    groupOrder: row.game.rawValue,
                    count: row.quantity,
                    sortValue: variant.choicePriority
                )
            }
        }

        return orderedOptions(from: tallies)
    }

    private func orderedOptions(from tallies: [String: OptionTally]) -> [FilterOption] {
        let sorted = tallies.sorted { left, right in
            let a = left.value
            let b = right.value
            if a.groupOrder != b.groupOrder { return a.groupOrder < b.groupOrder }
            if a.sortValue != b.sortValue { return a.sortValue < b.sortValue }
            return a.label < b.label
        }

        return sorted.map { key, tally in
            FilterOption(id: key, label: tally.label, group: tally.group, count: tally.count)
        }
    }

    // MARK: - Pricing

    private var isRefreshing: Bool {
        if case .refreshing = refresh.status { return true }
        return false
    }

    /// One entry per unique printing-and-variant, in display order so whatever
    /// the user is looking at becomes fresh first. Eight owned copies of one
    /// printing are one target, not eight.
    @MainActor
    private func priceTargets(_ snapshot: Snapshot, includeImported: Bool) -> [PriceTarget] {
        var seen = Set<String>()
        var result: [PriceTarget] = []

        for row in snapshot.visible + snapshot.all {
            guard let card = snapshot.cardsByKey[row.id] else { continue }
            if card.providerID.hasPrefix("csv:"), !includeImported { continue }
            guard seen.insert(card.priceKey).inserted else { continue }
            let record = snapshot.recordsByKey[card.priceKey]
            // When fallback is enabled, a fresh euro observation is still
            // unfinished: it cannot contribute to the USD collection total and
            // must reach the fallback immediately rather than waiting eight
            // hours for the ordinary catalog refresh interval.
            let hasFinishedPrice = PriceRefreshController.hasFinishedPrice(
                amount: record?.unitMarketPriceUSD,
                currencyCode: record?.currencyCode,
                usesFallback: usesPriceFallback
            )
            result.append(
                PriceTarget(
                    game: card.cardGame,
                    printingID: card.providerID,
                    catalogPrintingID: card.catalogProviderID,
                    setCode: card.setCode,
                    variantID: card.variantID,
                    importedIdentity: card.providerID.hasPrefix("csv:") && card.catalogProviderID == nil
                        ? ImportedPriceIdentity(
                            name: card.name,
                            setName: card.setName,
                            cardNumber: card.cardNumber
                        )
                        : nil,
                    catalogMetadataCheckedAt: card.catalogMetadataCheckedAt,
                    lastFailureAt: record?.lastFailureAt,
                    hasPrice: hasFinishedPrice,
                    lastCheckedAt: record?.lastCheckedAt
                )
            )
        }
        return result
    }

    /// Unique printing-and-finish rows that still lack a USD value. Counts card
    /// types rather than copies so the header matches refresh progress and quota
    /// cost instead of making a stack of duplicates look like extra work.
    private func fallbackPendingCount(_ snapshot: Snapshot) -> Int {
        var seen: Set<String> = []
        let currentMisses = Set(productIdentities.compactMap { identity in
            identity.vendorCardID == nil && identity.isCurrent() ? identity.key : nil
        })
        return snapshot.cardsByKey.values.reduce(into: 0) { count, card in
            guard seen.insert(card.priceKey).inserted else { return }
            guard !currentMisses.contains(card.priceKey) else { return }
            let record = snapshot.recordsByKey[card.priceKey]
            if record?.unitMarketPriceUSD == nil || record?.currencyCode != "USD" {
                count += 1
            }
        }
    }

    private func fallbackAvailabilityTaskID(_ snapshot: Snapshot) -> String {
        "\(fallbackPendingCount(snapshot)):\(usesPriceFallback):\(PriceVendorCredentials.hasKey)"
    }

    @MainActor
    private func refreshAllPrices() async {
        refreshStatusTask?.cancel()
        showsManualRefreshStatus = true
        let targets = PriceRefreshController.staleTargets(
            from: priceTargets(makeSnapshot(), includeImported: true)
        )
        guard !targets.isEmpty else {
            refresh.markRecentlyChecked()
            scheduleRefreshStatusDismissal()
            return
        }
        await runRefresh(targets, showsStatus: true)
    }

    /// Quiet background top-up. Existing prices stay visible the whole time —
    /// there is no blank grid and no blocking spinner.
    @MainActor
    private func refreshStalePricesIfNeeded() async {
        guard !hasCheckedForStalePrices, !cards.isEmpty else { return }
        hasCheckedForStalePrices = true

        let stale = PriceRefreshController.staleTargets(
            from: priceTargets(makeSnapshot(), includeImported: false)
        )
        guard !stale.isEmpty else { return }
        await runRefresh(stale, showsStatus: false)
    }

    @MainActor
    private func runRefresh(_ targets: [PriceTarget], showsStatus: Bool) async {
        await refresh.refresh(targets, store: PriceStore(context: modelContext))
        guard showsStatus else {
            refresh.dismissSummary()
            return
        }

        scheduleRefreshStatusDismissal()
    }

    private func scheduleRefreshStatusDismissal() {
        refreshStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            showsManualRefreshStatus = false
            refresh.dismissSummary()
        }
    }
}

private struct CollectionPriceFallbackSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                PriceFallbackSettingsSection()
            }
            .navigationTitle("Price Fallback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Menu labels cannot use `FilterChip` directly because a `Menu` supplies its own
/// button behaviour, so the visual half is shared instead.
struct FilterChipLabel: View {
    let title: String
    let isActive: Bool
    var symbol: String = "chevron.down"

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .background(
            isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
            in: Capsule()
        )
    }
}

private struct CollectionCardTile: View {
    let card: CollectedCard
    let price: PriceDisplay

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.secondary.opacity(0.08)

                CollectionCardArtwork(
                    thumbnailURL: card.lowImageURL,
                    fullSizeURL: card.highImageURL
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if card.quantity > 1 {
                    Text("×\(card.quantity)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.78), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.name)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PriceLabel(price: price, style: .compact)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Text(card.setName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let variant = card.variant {
                        CollectionFinishBadge(variant: variant)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(card.name), \(card.setName), \(accessiblePrice), \(card.variant?.label ?? "unknown finish"), quantity \(card.quantity)"
        )
    }

    private var accessiblePrice: String {
        if let amount = price.amount {
            return amount.formatted(.currency(code: price.currencyCode))
        }
        return price.state() == .unavailable ? "price unavailable" : "price not checked"
    }
}

private struct CollectionFinishBadge: View {
    let variant: PhysicalVariant

    var body: some View {
        Label(variant.label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private var tint: Color {
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return .teal
        case PhysicalVariant.foil.id, PhysicalVariant.holo.id, PhysicalVariant.etched.id:
            return .purple
        case PhysicalVariant.pokeBall.id, PhysicalVariant.masterBall.id, PhysicalVariant.firstEdition.id:
            return .orange
        case PhysicalVariant.normal.id, PhysicalVariant.nonfoil.id:
            return .secondary
        default:
            return .blue
        }
    }

    private var symbol: String {
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return "arrow.triangle.2.circlepath"
        case PhysicalVariant.foil.id, PhysicalVariant.holo.id, PhysicalVariant.etched.id:
            return "sparkles"
        case PhysicalVariant.pokeBall.id, PhysicalVariant.masterBall.id:
            return "circle.circle"
        case PhysicalVariant.firstEdition.id:
            return "1.circle"
        default:
            return "circle.fill"
        }
    }
}

/// Use the same URL that powers the detail screen. Some newly returned catalog
/// records have a working full-size image while their thumbnail endpoint remains
/// unavailable, which otherwise leaves the grid stuck on a placeholder.
private struct CollectionCardArtwork: View {
    let thumbnailURL: URL?
    let fullSizeURL: URL?

    private var primaryURL: URL? { fullSizeURL ?? thumbnailURL }

    private var fallbackURL: URL? {
        guard let thumbnailURL, thumbnailURL != primaryURL else { return nil }
        return thumbnailURL
    }

    var body: some View {
        AsyncImage(url: primaryURL) { phase in
            switch phase {
            case let .success(image):
                cardImage(image)
            case .failure:
                fallback
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let fallbackURL {
            AsyncImage(url: fallbackURL) { phase in
                switch phase {
                case let .success(image):
                    cardImage(image)
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private func cardImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(0.727, contentMode: .fit)
            .overlay { Image(systemName: "photo") }
    }
}

/// One place decides how a price is allowed to be described.
struct PriceLabel: View {
    enum Style { case compact, detailed }

    let price: PriceDisplay
    var style: Style = .compact

    var body: some View {
        switch price.state() {
        case .current:
            amount(.primary)

        case .stale:
            VStack(spacing: 1) {
                amount(.secondary)
                if style == .detailed, let asOf = price.effectiveAsOf {
                    Text("Last updated \(asOf.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .unavailable:
            Text(style == .compact ? "—" : "Price unavailable")
                .font(style == .compact ? .headline : .subheadline)
                .foregroundStyle(.secondary)

        case .unknown:
            Text(style == .compact ? "—" : "Not checked yet")
                .font(style == .compact ? .headline : .subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private func amount(_ shade: HierarchicalShapeStyle) -> some View {
        Text(price.amount ?? 0, format: .currency(code: price.currencyCode))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(shade)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
