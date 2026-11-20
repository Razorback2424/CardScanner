import SwiftData
import SwiftUI

/// How the Fix match sheet's pick is saved.
enum CardCorrectionMode: Equatable {
    /// Replace the card a scan already saved. `current` finds that card in the
    /// catalog so it can be offered first, which is how a swap is reversed.
    case replace(current: CatalogDetailLookup, variant: PhysicalVariant?)
    /// Add the card for a Needs attention record; nothing is saved yet.
    case add
}

/// What the sheet searches for, built once from what the scanner read.
struct CardCorrectionRequest: Equatable {
    let game: CardGame
    let mode: CardCorrectionMode
    /// The field's starting text. Empty when replacing: the scanner's number
    /// already led to the wrong card, and Likely matches cover the other sets.
    let initialQuery: String
    /// Searches whose first results become Likely matches, in order.
    let likelyQueries: [String]
    /// False when the save works the finish out itself (a graded slab's
    /// finish comes from its label), so rows save without finish chips.
    var choosesFinish = true

    /// - Parameter searchText: the game adapter's `catalogSearchText(for:)`
    ///   for the scan's identifier, when that game has one.
    init(game: CardGame, mode: CardCorrectionMode, searchText: String?, titleReadings: [String]) {
        self.game = game
        self.mode = mode
        var seen: Set<String> = []
        let titles = titleReadings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(3)
        let number = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        initialQuery = mode == .add ? (number ?? titles.first ?? "") : ""
        likelyQueries = ([number].compactMap { $0 } + titles)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    init(game: CardGame, mode: CardCorrectionMode, identifier: ScanIdentifier, titleReadings: [String],
         runtimes: CardGameRuntimeContainer?) {
        self.init(game: game, mode: mode,
                  searchText: runtimes?.runtime(for: game)?.recognizer?.catalogSearchText(for: identifier),
                  titleReadings: titleReadings)
    }
}

extension CardCorrectionRequest {
    /// The card names the scanner read, from whichever evidence it kept.
    static func titleReadings(for subject: ScanSubject) -> [String] {
        var readings = subject.inferredNameReadings ?? []
        if case let .pokemonHistorical(evidence) = subject.identifier.legacyIdentity {
            readings += evidence.titleCandidates
        }
        return readings
    }

    /// Fixing a card the scanner already saved.
    @MainActor static func replacing(_ scan: RecentScan, runtimes: CardGameRuntimeContainer?) -> Self {
        let current = CatalogDetailLookup(game: scan.card.game, providerID: scan.card.providerID,
            printRun: scan.pokemonPrintRun, name: scan.card.name, setCode: scan.card.setCode)
        return .init(game: scan.card.game, mode: .replace(current: current, variant: scan.resolved.variant),
                     identifier: scan.identifier, titleReadings: titleReadings(for: scan.subject),
                     runtimes: runtimes)
    }

    /// Finding the card for a Needs attention record.
    @MainActor static func adding(_ scan: UnresolvedScan, runtimes: CardGameRuntimeContainer?) -> Self {
        var request = Self(game: scan.game, mode: .add, identifier: scan.identifier,
              titleReadings: scan.requestEvidence.titleReadings + titleReadings(for: scan.subject),
              runtimes: runtimes)
        request.choosesFinish = scan.subject.slab == nil
        return request
    }
}

struct CardCorrectionPick {
    let details: CatalogCardDetails
    let summary: CatalogCardSummary
    let variant: PhysicalVariant?
    var printRun: PokemonPrintRun? { summary.pokemonPrintRun }
}

/// One sheet for fixing a scan: Likely matches first, then search. A row
/// with one physical choice saves on tap; one with several opens chips.
struct CardCorrectionPicker: View {
    let catalog: any BrowseCatalogProviding
    let request: CardCorrectionRequest
    /// Saves the pick. Returns the message to show when the save fails; nil
    /// closes the sheet.
    let onPick: @MainActor (CardCorrectionPick) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var query: String
    @State private var selection: TextSelection?
    @FocusState private var isFieldFocused: Bool
    @State private var current: CatalogCardSummary?
    @State private var likely: [CatalogCardSummary] = []
    @State private var isLoadingLikely = true
    @State private var results: [CatalogCardSummary] = []
    @State private var searchState = SearchState.idle
    @State private var expanded: Expanded?
    @State private var busyKey: String?
    @State private var rowMessages: [String: String] = [:]
    @State private var owned: [String: Int] = [:]

    enum SearchState: Equatable {
        case idle, searching, done
        case failed(String)
    }

    private struct Expanded {
        let key: String
        let details: CatalogCardDetails
        let summary: CatalogCardSummary
        let options: [PhysicalVariant]
    }

    init(catalog: any BrowseCatalogProviding, request: CardCorrectionRequest,
         onPick: @escaping @MainActor (CardCorrectionPick) async -> String?) {
        self.catalog = catalog
        self.request = request
        self.onPick = onPick
        _query = State(initialValue: request.initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name or number", text: $query, selection: $selection)
                        .focused($isFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("correction-search-field")
                }
                likelySection
                resultsSection
            }
            .navigationTitle(request.mode == .add ? "Find card" : "Fix match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: isFieldFocused) { _, focused in
            // Typing replaces the pre-fill instead of appending to it.
            if focused, !query.isEmpty { selection = TextSelection(range: query.startIndex..<query.endIndex) }
        }
        .task { await loadLikelyMatches() }
        .task(id: query) { await search(query) }
    }

    // MARK: Sections

    @ViewBuilder private var likelySection: some View {
        if isLoadingLikely || current != nil || !likely.isEmpty {
            Section("Likely matches") {
                if let current {
                    row(current, key: "current", badge: "Current")
                }
                ForEach(likely) { summary in
                    row(summary, key: "likely:\(summary.id)", badge: ownedBadge(summary))
                }
                if isLoadingLikely {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder private var resultsSection: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .searching:
            Section("Results") {
                ProgressView("Searching…").frame(maxWidth: .infinity)
            }
        case let .failed(message):
            Section("Results") {
                Text(message).foregroundStyle(.secondary)
                    .accessibilityIdentifier("correction-search-message")
            }
        case .done:
            // Cards already shown in Likely matches aren't repeated, so a
            // pre-filled search doesn't list the same cards twice.
            let shown = results.filter { summary in
                !isCurrent(summary) && !likely.contains { $0.id == summary.id }
            }
            if results.isEmpty {
                Section("Results") {
                    Text("No cards found. Try the name or the number as printed.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("correction-search-message")
                }
            } else if !shown.isEmpty {
                Section("Results") {
                    ForEach(shown) { summary in
                        row(summary, key: "result:\(summary.id)", badge: ownedBadge(summary))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ summary: CatalogCardSummary, key: String, badge: String?) -> some View {
        Button {
            Task { await tap(summary, key: key) }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: summary.thumbnailURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .overlay { Image(systemName: "rectangle.portrait").foregroundStyle(.secondary) }
                }
                .frame(width: 44, height: 61)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.displayName.isEmpty ? "Unknown card name" : summary.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(summary.setName) · \(summary.printedCollectorNumber ?? "Unnumbered")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
                if busyKey == key {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(request.mode == .add ? "Adds this card" : "Changes the scanned card to this one")
        .accessibilityIdentifier("correction-row-\(key)")

        if let expanded, expanded.key == key {
            chips(expanded)
        }
        if let message = rowMessages[key] {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("correction-row-message")
        }
    }

    private func chips(_ expanded: Expanded) -> some View {
        let preselected = currentVariant.flatMap { variant in
            isCurrent(expanded.summary) ? expanded.options.first { $0.id == variant.id } : nil
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(expanded.options) { variant in
                    let allowed = PokemonVariantPolicy.allowsAcquisition(
                        of: expanded.details.card, finish: variant, printRun: expanded.summary.pokemonPrintRun)
                    Button(variant.label) {
                        Task { await save(expanded.details, expanded.summary, variant, key: expanded.key) }
                    }
                    .buttonStyle(.bordered)
                    .tint(variant.id == preselected?.id ? .accentColor : .secondary)
                    .disabled(!allowed || busyKey != nil)
                    .accessibilityAddTraits(variant.id == preselected?.id ? .isSelected : [])
                    .accessibilityIdentifier("correction-chip-\(variant.id)")
                }
            }
        }
    }

    // MARK: Actions

    private func tap(_ summary: CatalogCardSummary, key: String) async {
        guard busyKey == nil else { return }
        if expanded?.key == key {
            expanded = nil
            return
        }
        expanded = nil
        rowMessages[key] = nil
        busyKey = key
        let details: CatalogCardDetails
        do {
            if let installed = await catalog.installedDetails(for: summary) {
                details = installed
            } else {
                details = try await catalog.details(for: summary)
            }
        } catch {
            busyKey = nil
            rowMessages[key] = Self.isOffline(error)
                ? "This card needs a connection to load."
                : "Couldn't load this card. Try again."
            return
        }
        busyKey = nil
        if let reason = details.collectionWriteUnavailableReason {
            rowMessages[key] = reason
            return
        }
        guard request.choosesFinish else {
            await save(details, summary, nil, key: key)
            return
        }
        let options = Self.physicalChoices(for: details.card, summary: summary)
        if options.count > 1 {
            expanded = Expanded(key: key, details: details, summary: summary, options: options)
            return
        }
        // When adding, a card with one finish is left for the scanner to
        // settle, so it is recorded as the catalog's only finish rather than
        // as a choice the person made.
        await save(details, summary, request.mode == .add ? nil : options.first, key: key)
    }

    private func save(_ details: CatalogCardDetails, _ summary: CatalogCardSummary,
                      _ variant: PhysicalVariant?, key: String) async {
        guard busyKey == nil else { return }
        busyKey = key
        let failure = await onPick(CardCorrectionPick(details: details, summary: summary, variant: variant))
        busyKey = nil
        if let failure {
            rowMessages[key] = failure
        } else {
            dismiss()
        }
    }

    /// The finishes a person picks between for this printing. Edition is part
    /// of the summary (its own set), so the first-edition pseudo-finish is not
    /// a choice here.
    static func physicalChoices(for card: IdentifiedCard, summary: CatalogCardSummary) -> [PhysicalVariant] {
        CatalogCardDetailView.priceVariants(for: card, summary: summary)
            .filter { $0.id != PhysicalVariant.firstEdition.id }
    }

    // MARK: Loading

    private func loadLikelyMatches() async {
        defer { isLoadingLikely = false }
        if case let .replace(lookup, _) = request.mode {
            current = try? await lookup.summary(in: catalog)
        }
        var found: [CatalogCardSummary] = []
        func collect(_ text: String) async {
            guard let page = try? await catalog.searchCards(named: text, game: request.game, setIDs: [], cursor: nil)
            else { return }
            for summary in page.items.prefix(6) where !isCurrent(summary) && !found.contains(summary) {
                found.append(summary)
            }
        }
        for text in request.likelyQueries {
            await collect(text)
            if Task.isCancelled { return }
        }
        // A reprint can carry a different number (Yu-Gi-Oh set codes), so
        // fall back to the saved card's name in other sets.
        if found.isEmpty, case let .replace(lookup, _) = request.mode, !lookup.name.isEmpty {
            await collect(lookup.name)
        }
        guard !Task.isCancelled else { return }
        likely = Array(found.prefix(8))
        loadOwnership()
    }

    private func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            searchState = .idle
            return
        }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        searchState = .searching
        do {
            let page = try await catalog.searchCards(named: trimmed, game: request.game, setIDs: [], cursor: nil)
            guard !Task.isCancelled else { return }
            results = page.items
            searchState = .done
            loadOwnership()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            results = []
            searchState = .failed(Self.isOffline(error)
                ? "Search needs a connection. Likely matches still work."
                : "Couldn't search right now. Try again.")
        }
    }

    /// "You have 1" on a row, so joining an owned card isn't a surprise.
    private func loadOwnership() {
        let summaries = likely + results
        let ids = Array(Set(summaries.map(\.providerID)))
        guard !ids.isEmpty else { return }
        let descriptor = FetchDescriptor<CollectedCard>(predicate: #Predicate { ids.contains($0.providerID) })
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        var counts: [String: Int] = [:]
        for summary in summaries {
            counts[summary.id] = rows.filter {
                $0.game == summary.game.rawValue && $0.providerID == summary.providerID
                    && $0.pokemonPrintRunRaw == summary.pokemonPrintRun?.rawValue
            }.reduce(0) { $0 + $1.quantity }
        }
        owned = counts
    }

    // MARK: Helpers

    private var currentVariant: PhysicalVariant? {
        if case let .replace(_, variant) = request.mode { return variant }
        return nil
    }

    private func isCurrent(_ summary: CatalogCardSummary) -> Bool {
        guard case let .replace(lookup, _) = request.mode else { return false }
        return lookup.exactSummary(in: [summary]) != nil
    }

    private func ownedBadge(_ summary: CatalogCardSummary) -> String? {
        guard let count = owned[summary.id], count > 0 else { return nil }
        return "You have \(count)"
    }

    static func isOffline(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotConnectToHost, .cannotFindHost, .dataNotAllowed].contains(error.code)
        }
        return (error as NSError).domain == NSURLErrorDomain
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
/// `-ui_debug_route CardCorrection -ui_debug_state <state>` over the app's
/// real Browse catalog. States: `replace` (default), `add`, `fail`, and any
/// of them with `-large` for accessibility text.
struct CardCorrectionDebugView: View {
    let catalog: any BrowseCatalogProviding
    @State private var isPresented = true
    @State private var picked = "No card picked"
    private let state: String

    init(catalog: any BrowseCatalogProviding) {
        self.catalog = catalog
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "-ui_debug_state")
        state = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "replace"
    }

    private var request: CardCorrectionRequest {
        if state.hasPrefix("add") {
            return .init(game: .pokemon, mode: .add, searchText: "TG05/TG30", titleReadings: ["gardevoir"])
        }
        let current = CatalogDetailLookup(game: .pokemon, providerID: "g1-RC5", printRun: nil,
                                          name: "Charizard", setCode: "GEN")
        return .init(game: .pokemon, mode: .replace(current: current, variant: .holo),
                     searchText: "RC5/RC32", titleReadings: ["charizard"])
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Card correction fixture").font(.headline)
            Text(picked).accessibilityIdentifier("correction-fixture-result")
            Button("Open sheet") { isPresented = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isPresented) {
            CardCorrectionPicker(catalog: catalog, request: request) { pick in
                if state.hasPrefix("fail") { return "Couldn't change card. Try again." }
                picked = "\(pick.summary.name) · \(pick.summary.setName) · \(pick.variant?.label ?? "No finish")"
                return nil
            }
            .dynamicTypeSize(state.hasSuffix("-large") ? .accessibility3 : .large)
        }
    }
}
#endif
