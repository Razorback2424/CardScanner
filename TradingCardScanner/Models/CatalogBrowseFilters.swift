import Foundation

/// The questions a collector can ask of a game's Browse grid. Kept apart from
/// `CollectionFilters`: catalog summaries are not owned rows, so quantity and
/// grading have no meaning here, while ownership does.
struct CatalogBrowseFilters: Equatable, Sendable {
    /// Empty means every set.
    var setIDs: Set<CatalogSetID> = []
    var pokemonPrintRuns: Set<PokemonPrintRun> = []
    /// Finish ids: a Pokémon master-set `PhysicalVariant.id`, or a Magic finish id.
    var variantIDs: Set<String> = []
    var magicTreatmentIDs: Set<String> = []
    var ownership: CatalogOwnershipFilter = .all
    var price: PriceFilter?

    static let none = CatalogBrowseFilters()

    var isActive: Bool { activeCount > 0 }

    /// One per filter group in use, for the button badge and accessibility label.
    var activeCount: Int {
        [!setIDs.isEmpty, !pokemonPrintRuns.isEmpty, !variantIDs.isEmpty, !magicTreatmentIDs.isEmpty,
         ownership != .all, price != nil].filter { $0 }.count
    }

    /// Only a price question needs quotes, which are the expensive part of a fill.
    var needsPrices: Bool { price != nil }

    func includesSet(_ id: CatalogSetID) -> Bool {
        (setIDs.isEmpty || setIDs.contains(id))
            && (pokemonPrintRuns.isEmpty || id.pokemonPrintRun.map(pokemonPrintRuns.contains) == true)
    }

    /// Narrows the walk to the chosen sets. For treatment filters, visit sets
    /// with known matches first and keep the remaining sets eligible.
    func restrictedSets(_ orderedSets: [CatalogSet]) -> [CatalogSet] {
        let selected = orderedSets.filter { includesSet($0.catalogID) }
        guard !magicTreatmentIDs.isEmpty else { return selected }
        let knownCodes = MagicTreatmentCatalogStore.bundledDefault.setCodes(forTreatmentIDs: magicTreatmentIDs)
        let hasKnownTreatment: (CatalogSet) -> Bool = {
            $0.game == .magic && knownCodes.contains($0.providerID.lowercased())
        }
        return selected.filter(hasKnownTreatment) + selected.filter { !hasKnownTreatment($0) }
    }

    /// Every filter except price. Cheap, so it runs before any quote is requested.
    func matchesWithoutPrice(_ card: CatalogCardSummary, isOwned: Bool) -> Bool {
        matchesWithoutPrice(card, isOwned: { _ in isOwned })
    }

    func matchesWithoutPrice(_ card: CatalogCardSummary, isOwned: (CatalogCardSummary) -> Bool) -> Bool {
        guard includesSet(card.setID) else { return false }
        return !matchingPrintings(for: card, isOwned: isOwned).isEmpty
    }

    func scopesFinish(of card: CatalogCardSummary) -> Bool {
        (card.game == .magic && (!variantIDs.isEmpty || !magicTreatmentIDs.isEmpty))
            || (card.verifiedBrowseFinishes != nil && !variantIDs.isEmpty)
    }

    /// Keeps Magic finish, treatment and ownership constraints on the same
    /// physical copy. Unfiltered cards retain their printing-level identity.
    func matchingPrintings(
        for card: CatalogCardSummary,
        isOwned: (CatalogCardSummary) -> Bool,
        expandFinishes: Bool = false
    ) -> [CatalogCardSummary] {
        let explicit = scopesFinish(of: card) || expandFinishes ? Self.explicitFinishes(of: card) : []
        let candidates = explicit.isEmpty ? [card] : explicit
        let requested = Set(magicTreatmentIDs.compactMap { MagicTreatment(id: $0)?.id })
        return candidates.filter { copy in
            guard variantIDs.isEmpty || !Self.finishIDs(of: copy).isDisjoint(with: variantIDs) else { return false }
            if !magicTreatmentIDs.isEmpty {
                let treatments = copy.masterSetVariant.map {
                    copy.magicTreatmentEvidence.applicableTreatments(for: $0)
                } ?? copy.magicTreatments
                guard treatments.contains(where: { requested.contains($0.id) }) else { return false }
            }
            switch ownership {
            case .all: return true
            case .owned: return isOwned(copy)
            case .notOwned: return !isOwned(copy)
            }
        }
    }

    static func explicitFinishes(of card: CatalogCardSummary) -> [CatalogCardSummary] {
        guard card.masterSetVariant == nil else { return [] }
        return finishes(of: card).map { finish in
            var slot = card
            slot.masterSetVariant = finish
            return slot
        }
    }

    /// `nil` means the answer depends on a price that is not known yet. Such a
    /// card is held back rather than shown as cheap or unpriced.
    func matches(
        _ card: CatalogCardSummary,
        isOwned: Bool,
        price resolution: CatalogPriceResolution
    ) -> Bool? {
        guard matchesWithoutPrice(card, isOwned: isOwned) else { return false }
        return matchesPrice(resolution)
    }

    func matchesPrice(_ resolution: CatalogPriceResolution) -> Bool? {
        guard let price else { return true }
        switch resolution {
        case let .priced(value): return price.matches(value)
        case .unpriced: return price.matches(nil)
        case .pending: return nil
        }
    }

    static func finishIDs(of card: CatalogCardSummary) -> Set<String> {
        Set(finishes(of: card).map(\.id))
    }

    static func finishes(of card: CatalogCardSummary) -> [PhysicalVariant] {
        if let variant = card.masterSetVariant { return [variant] }
        return card.verifiedBrowseFinishes ?? (card.magicFinishIDs ?? []).map(PhysicalVariant.resolving)
    }
}

enum CatalogBrowseSort: String, CaseIterable, Identifiable, Sendable {
    case recommended, priceDescending, priceAscending
    case releaseDescending, releaseAscending, nameAscending, nameDescending

    var id: Self { self }

    var label: String {
        switch self {
        case .recommended: return "Recommended"
        case .priceDescending: return "Price High to Low"
        case .priceAscending: return "Price Low to High"
        case .releaseDescending: return "Release Newest First"
        case .releaseAscending: return "Release Oldest First"
        case .nameAscending: return "Name A–Z"
        case .nameDescending: return "Name Z–A"
        }
    }

    var needsPrices: Bool { self == .priceDescending || self == .priceAscending }
    var usesReleaseDate: Bool { self == .releaseDescending || self == .releaseAscending }

    static func releaseDateLabel(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }

    func ordered<Value>(_ values: [Value], price: (Value) -> Double?, date: (Value) -> Date?,
                        name: (Value) -> String, tie: (Value, Value) -> Bool) -> [Value] {
        guard self != .recommended else { return values }
        return values.sorted { precedes($0, $1, price: price, date: date, name: name, tie: tie) }
    }

    func precedes<Value>(_ left: Value, _ right: Value, price: (Value) -> Double?, date: (Value) -> Date?,
                         name: (Value) -> String, tie: (Value, Value) -> Bool) -> Bool {
        switch self {
        case .priceDescending, .priceAscending:
            let lhs = price(left), rhs = price(right)
            if lhs != rhs { return Self.precedes(lhs, rhs, ascending: self == .priceAscending) }
        case .releaseDescending, .releaseAscending:
            let lhs = date(left), rhs = date(right)
            if lhs != rhs { return Self.precedes(lhs, rhs, ascending: self == .releaseAscending) }
        case .nameAscending, .nameDescending:
            let comparison = name(left).localizedStandardCompare(name(right))
            if comparison != .orderedSame {
                return comparison == (self == .nameAscending ? .orderedAscending : .orderedDescending)
            }
        case .recommended: break
        }
        return tie(left, right)
    }

    private static func precedes<T: Comparable>(_ lhs: T?, _ rhs: T?, ascending: Bool) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return ascending ? lhs < rhs : lhs > rhs
    }
}

struct CatalogBrowseQuote: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case pending, priced, stale, noQuote, mappingPending, printingReview, failed

        var label: String? {
            switch self {
            case .pending, .priced: return nil
            case .stale: return "Stale price"
            case .noQuote: return "No USD quote"
            case .mappingPending: return "Price mapping pending"
            case .printingReview: return "Printing needs review"
            case .failed: return "Price unavailable"
            }
        }
    }

    var amount: Double?
    var status: Status
    var asOf: Date? = nil
    var source: PriceSource? = nil

    static let pending = Self(amount: nil, status: .pending)
    static let failed = Self(amount: nil, status: .failed)

    var canRetry: Bool { status == .failed || status == .stale }

    var freshnessLabel: String? {
        guard amount != nil, let asOf else { return status.label }
        let dated = PriceDisplay.datedFreshnessLabel(asOf: asOf)
        // A quote kept after a failed refresh must still say so, even when the
        // capture itself is recent enough to read as current.
        guard status == .stale || status == .failed,
              PriceDisplay.freshness(asOf: asOf) == .current else { return dated }
        return String(localized: "Refresh failed · \(dated)")
    }

    static func from(_ update: CatalogPriceUpdate, id: String) -> Self {
        if update.printingNeedsReviewIDs.contains(id) { return .init(amount: nil, status: .printingReview) }
        if update.missingMappingIDs.contains(id) { return .init(amount: nil, status: .mappingPending) }
        if let amount = update.prices[id], amount.isFinite, amount > 0 {
            let date = update.quoteDates[id]
            let stale = date.map { !SortPriceHint(price: amount, checkedAt: $0).isFresh() } ?? false
            return .init(amount: amount, status: stale || update.unresolvedIDs.contains(id) ? .stale : .priced,
                         asOf: date, source: update.quoteSources[id])
        }
        if update.resolvedIDs.contains(id) { return .init(amount: nil, status: .noQuote) }
        return update.unresolvedIDs.contains(id) ? .init(amount: nil, status: .failed) : .pending
    }

    static func merging(_ update: CatalogPriceUpdate, id: String, previous: Self?) -> Self? {
        let previous = previous.flatMap {
            TCGCSVPriceMirror.hasValidCapture(source: $0.source, capturedAt: $0.asOf) ? $0 : nil
        }
        let incoming = from(update, id: id)
        if incoming.status == .pending { return previous }
        if incoming.status == .failed, var lastQuote = previous, lastQuote.amount != nil {
            lastQuote.status = .stale
            return lastQuote
        }
        return incoming
    }

    func matches(_ filter: PriceFilter?) -> Bool {
        guard let filter else { return true }
        if let amount { return filter.matches(amount) }
        return (status == .noQuote || status == .mappingPending || status == .printingReview) && filter.matches(nil)
    }
}

struct CatalogBrowsePresentation: Sendable {
    struct Row: Identifiable, Sendable {
        let group: CatalogCardDisplayGroup
        let quotes: [String: CatalogBrowseQuote]
        let releaseDate: Date?
        let usesSetDate: Bool
        let representative: CatalogCardSummary?
        var id: String { group.id }
        var price: Double? { representative.flatMap { quotes[$0.id]?.amount } }
    }

    static func candidates(_ cards: [CatalogCardSummary], filters: CatalogBrowseFilters,
                           ownership: CatalogOwnershipIndex) -> [CatalogCardSummary] {
        var ids: Set<String> = []
        return cards.flatMap { card in
            filters.includesSet(card.setID)
                ? filters.matchingPrintings(for: card, isOwned: ownership.owns, expandFinishes: true) : []
        }.filter { ids.insert($0.id).inserted }
    }

    static func setPriceCandidates(_ cards: [CatalogCardSummary], in set: CatalogSet,
                                   search: String, tier: PokemonMasterSetTier, filters: CatalogBrowseFilters,
                                   ownership: CatalogOwnershipIndex) -> [CatalogCardSummary] {
        let query = CatalogSetCardSearch(query: CatalogCardSearchQuery(search), setID: set.catalogID,
            setCode: cards.first?.setCode ?? "", officialCollectorCount: set.officialCollectorCount)
        return candidates(cards.filter { card in
            (card.game != .pokemon || tier != .standard || !card.isExpandedMasterSetVariant) && query.matches(card)
        }, filters: filters, ownership: ownership)
    }

    static func rows(_ candidates: [CatalogCardSummary], filters: CatalogBrowseFilters,
                     sort: CatalogBrowseSort, sets: [CatalogSet], quotes: [String: CatalogBrowseQuote],
                     ownership: CatalogOwnershipIndex) -> [Row] {
        var resolved = quotes
        let matching = candidates.filter { card in
            resolved[card.id] = effectiveQuote(card, quoted: resolved[card.id], ownership: ownership)
            return (resolved[card.id] ?? .pending).matches(filters.price)
        }
        let dates = Dictionary(sets.compactMap { set in set.releaseDate.map { (set.catalogID, $0) } },
                               uniquingKeysWith: { first, _ in first })
        let rows = CatalogCardDisplayGrouping.groups(for: matching).map { group in
            let card = group.preferredSummary
            let setDate = dates[card.setID] ?? dates[CatalogSetID(game: card.game, providerID: card.setID.providerID)]
            return row(group, setDate: setDate, quotes: resolved)
        }
        return sort.ordered(rows, price: \.price, date: \.releaseDate, name: { $0.group.preferredSummary.name }) {
            let lhs = $0.group.preferredSummary, rhs = $1.group.preferredSummary
            if lhs.setID.id != rhs.setID.id { return lhs.setID.id < rhs.setID.id }
            let number = CollectorNumber.compare(lhs.collectorNumber, rhs.collectorNumber)
            return number == .orderedSame ? $0.id < $1.id : number == .orderedAscending
        }
    }

    static func row(_ group: CatalogCardDisplayGroup, setDate: Date?, quotes: [String: CatalogBrowseQuote],
                    ownership: CatalogOwnershipIndex? = nil) -> Row {
        let tileQuotes = Dictionary(uniqueKeysWithValues: group.summaries.map { card in
            (card.id, effectiveQuote(card, quoted: quotes[card.id], ownership: ownership))
        })
        let representative = group.summaries.filter { tileQuotes[$0.id]?.amount != nil }.max {
            (tileQuotes[$0.id]?.amount ?? 0) < (tileQuotes[$1.id]?.amount ?? 0)
        }
        let date = group.preferredSummary.printingReleaseDate
        return Row(group: group, quotes: tileQuotes, releaseDate: date ?? setDate,
                   usesSetDate: date == nil && setDate != nil, representative: representative)
    }

    static func effectiveQuote(_ card: CatalogCardSummary, quoted: CatalogBrowseQuote?,
                               ownership: CatalogOwnershipIndex?) -> CatalogBrowseQuote {
        guard let ownership else { return quoted ?? .pending }
        let owned = OwnedCatalogPrice(rows: ownership.matchingRows(for: card))
        guard !owned.entries.isEmpty else { return quoted ?? .pending }
        let amount = owned.display.amount
        let date = owned.display.effectiveAsOf
        let stale = date.map { !SortPriceHint(price: amount ?? 0, checkedAt: $0).isFresh() } ?? false
        return .init(amount: amount, status: amount == nil ? .noQuote : (stale ? .stale : .priced),
                     asOf: date, source: owned.display.source)
    }
}

/// What the price stream has said about one card slot so far.
enum CatalogPriceResolution: Hashable, Sendable {
    case priced(Double)
    /// The provider answered and has no USD quote, or no mapping exists.
    case unpriced
    /// Not answered yet, or the request failed and can be retried. An unknown
    /// price is not a missing price.
    case pending

    /// Folds price-stream updates into per-card answers. A later update wins,
    /// matching how the set screen merges the same stream.
    static func merge(
        _ update: CatalogPriceUpdate,
        into resolutions: inout [String: CatalogPriceResolution]
    ) {
        for id in update.unresolvedIDs { resolutions[id] = .pending }
        for id in update.resolvedIDs.union(update.missingMappingIDs) {
            resolutions[id] = update.prices[id].map(CatalogPriceResolution.priced) ?? .unpriced
        }
        for (id, value) in update.prices { resolutions[id] = .priced(value) }
    }

    /// Drains a price stream for `cards`, stopping early once every card has a
    /// settled answer. Cards the stream never settles are reported `.pending`.
    static func resolve(
        _ cards: [CatalogCardSummary],
        from updates: AsyncStream<CatalogPriceUpdate>
    ) async -> [String: CatalogPriceResolution] {
        let wanted = Set(cards.map(\.id))
        var resolutions: [String: CatalogPriceResolution] = [:]
        for await update in updates {
            merge(update, into: &resolutions)
            if wanted.allSatisfy({ resolutions[$0].map { $0 != .pending } ?? false }) { break }
        }
        for id in wanted where resolutions[id] == nil { resolutions[id] = .pending }
        return resolutions
    }
}

/// Position in the newest-first, set-by-set walk the game grid uses.
struct CatalogSetWalkPosition: Hashable, Sendable {
    var setIndex: Int
    var cursor: String?

    static let start = CatalogSetWalkPosition(setIndex: 0, cursor: nil)

    /// The position after a page of `set` at `self` returned `nextCursor`, or
    /// `nil` when the walk is exhausted.
    func advanced(by nextCursor: String?, setCount: Int) -> CatalogSetWalkPosition? {
        if let nextCursor { return CatalogSetWalkPosition(setIndex: setIndex, cursor: nextCursor) }
        return skippingSet(setCount: setCount)
    }

    /// Moves past the current set, for "Skip this set" after a failure.
    func skippingSet(setCount: Int) -> CatalogSetWalkPosition? {
        setIndex + 1 < setCount ? CatalogSetWalkPosition(setIndex: setIndex + 1, cursor: nil) : nil
    }
}

/// Position in a single cursor-paged search stream.
struct CatalogSearchPosition: Hashable, Sendable {
    var cursor: String?
    static let start = CatalogSearchPosition(cursor: nil)
}

/// Loads pages until enough cards match the filters, without a silent crawl of
/// the whole catalog. Positions are generic so the set walk and service search
/// share one loop.
@MainActor
enum CatalogFilteredPager {
    struct Limits: Equatable, Sendable {
        /// Stop once this many matches have arrived.
        var targetMatchCount = 24
        /// Stop after this many pages in one fill even if matches are few, so
        /// the view can offer to keep searching older sets.
        var maxPagesPerFill = 8
    }

    struct Page<Position> {
        let items: [CatalogCardSummary]
        /// `nil` when nothing follows this page.
        let next: Position?
    }

    struct Fill<Position: Hashable> {
        var matches: [CatalogCardSummary] = []
        /// Cards that pass every other filter but whose price is not known yet.
        var pendingPrice: [CatalogCardSummary] = []
        /// Answers gathered for priced fills, so the grid can show them.
        var priceResolutions: [String: CatalogPriceResolution] = [:]
        var scannedCount = 0
        var pagesLoaded = 0
        /// Where the next fill starts. `nil` means the walk is exhausted. After
        /// an error it is the failed position, so a retry repeats it.
        var position: Position?
        var visitedPositions: Set<Position> = []
        /// The page cap stopped the fill before the target was reached.
        var stoppedAtPageLimit = false
        var error: Error?

        var isExhausted: Bool { position == nil && error == nil }
    }

    /// Returns `nil` when `isCurrent` turned false during the fill: a newer
    /// filter, search, or catalog revision owns the grid and this result must
    /// not publish.
    static func fill<Position: Hashable>(
        from start: Position?,
        filters: CatalogBrowseFilters,
        limits: Limits = Limits(),
        expandFinishes: Bool = false,
        visitedPositions: Set<Position> = [],
        existingIDs: Set<String> = [],
        loadPage: (Position) async throws -> Page<Position>,
        isOwned: (CatalogCardSummary) -> Bool,
        resolvePrices: ([CatalogCardSummary]) async -> [String: CatalogPriceResolution],
        isCurrent: () -> Bool
    ) async -> Fill<Position>? {
        var fill = Fill<Position>(position: start, visitedPositions: visitedPositions)
        var seenIDs = existingIDs
        while let position = fill.position, fill.matches.count < limits.targetMatchCount {
            if fill.pagesLoaded >= limits.maxPagesPerFill {
                fill.stoppedAtPageLimit = true
                break
            }
            let page: Page<Position>
            do {
                page = try await loadPage(position)
            } catch {
                guard isCurrent(), !Task.isCancelled else { return nil }
                fill.error = error
                break
            }
            guard isCurrent(), !Task.isCancelled else { return nil }
            if let next = page.next, next == position || fill.visitedPositions.contains(next) {
                fill.error = BrowseCatalogError.badResponse
                break
            }
            fill.visitedPositions.insert(position)
            fill.pagesLoaded += 1
            fill.scannedCount += page.items.count
            fill.position = page.next

            let candidates = page.items.filter {
                seenIDs.insert($0.id).inserted && filters.includesSet($0.setID)
                    && !filters.matchingPrintings(for: $0, isOwned: isOwned, expandFinishes: expandFinishes).isEmpty
            }
            guard filters.needsPrices, !candidates.isEmpty else {
                fill.matches += candidates
                continue
            }
            let resolutions = await resolvePrices(candidates)
            guard isCurrent(), !Task.isCancelled else { return nil }
            fill.priceResolutions.merge(resolutions) { _, newest in newest }
            for card in candidates {
                switch filters.matchesPrice(resolutions[card.id] ?? .pending) {
                case true?: fill.matches.append(card)
                case nil: fill.pendingPrice.append(card)
                case false?: break
                }
            }
        }
        return fill
    }

    /// The set-walk loader: adapts a `cards(in:cursor:)` call to positions.
    static func setWalkLoader(
        sets: [CatalogSet],
        cards: @escaping (CatalogSet, String?) async throws -> CatalogPage<CatalogCardSummary>
    ) -> (CatalogSetWalkPosition) async throws -> Page<CatalogSetWalkPosition> {
        { position in
            let page = try await cards(sets[position.setIndex], position.cursor)
            return Page(items: page.items, next: position.advanced(by: page.nextCursor, setCount: sets.count))
        }
    }

    /// The first position of a set walk, or `nil` when no set remains.
    static func setWalkStart(sets: [CatalogSet]) -> CatalogSetWalkPosition? {
        sets.isEmpty ? nil : .start
    }

    /// The search loader: adapts a cursor-paged search call to positions.
    static func searchLoader(
        search: @escaping (String?) async throws -> CatalogPage<CatalogCardSummary>
    ) -> (CatalogSearchPosition) async throws -> Page<CatalogSearchPosition> {
        { position in
            let page = try await search(position.cursor)
            return Page(items: page.items, next: page.nextCursor.map(CatalogSearchPosition.init(cursor:)))
        }
    }
}

/// Facets observed in Browse rows, supplemented by the reviewed Magic treatment vocabulary.
struct CatalogBrowseFacets: Equatable {
    private var observedFinishes: [PhysicalVariant] = []
    private var treatmentIDs: [String] = []

    mutating func record(_ cards: [CatalogCardSummary]) {
        var knownFinishes = Set(observedFinishes.map(\.id))
        var knownTreatments = Set(treatmentIDs)
        for card in cards {
            for finish in CatalogBrowseFilters.finishes(of: card) where knownFinishes.insert(finish.id).inserted {
                observedFinishes.append(finish)
            }
            for treatment in card.magicTreatments where knownTreatments.insert(treatment.id).inserted {
                treatmentIDs.append(treatment.id)
            }
        }
    }

    func finishOptions(base: [PhysicalVariant], catalog: [PhysicalVariant] = [], for game: CardGame? = nil) -> [PhysicalVariant] {
        let supportsVerifiedFinishes = (game == .lorcana || game == .onePiece) && !base.isEmpty
        guard game == .pokemon || game == .magic || supportsVerifiedFinishes || !observedFinishes.isEmpty else { return [] }
        var seen = Set<String>()
        return (base + catalog + observedFinishes).filter { finish in
            (game != .pokemon || (finish.id != PhysicalVariant.firstEdition.id && finish.id != PhysicalVariant.jumbo.id))
                && seen.insert(finish.id).inserted
        }
    }

    func treatmentOptions(for game: CardGame) -> [MagicTreatment] {
        guard game == .magic else { return [] }
        return Set(MagicTreatment.modelled + treatmentIDs.compactMap(MagicTreatment.init(id:)))
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}

/// Pokémon search answers with one row per numbered card and no finish. A
/// finish question needs the card's master-set slots, which the set's local
/// checklist already holds.
struct CatalogSearchFinishExpansion {
    private var slotsBySet: [CatalogSetID: [String: [CatalogCardSummary]]] = [:]

    static func needsExpansion(game: CardGame, filters: CatalogBrowseFilters) -> Bool {
        game == .pokemon && (!filters.variantIDs.isEmpty || filters.ownership != .all)
    }

    /// Replaces each finish-less row with its slots, in the original order. A
    /// row whose set is unknown or has no slots is kept as it was.
    static func expand(
        _ cards: [CatalogCardSummary],
        setsByID: [CatalogSetID: CatalogSet],
        slots: (CatalogSet) async throws -> [CatalogCardSummary]
    ) async throws -> [CatalogCardSummary] {
        var expansion = Self()
        return try await expansion.expand(cards, setsByID: setsByID, slots: slots)
    }

    mutating func expand(
        _ cards: [CatalogCardSummary],
        setsByID: [CatalogSetID: CatalogSet],
        slots: (CatalogSet) async throws -> [CatalogCardSummary]
    ) async throws -> [CatalogCardSummary] {
        var expanded: [CatalogCardSummary] = []
        for card in cards {
            try Task.checkCancellation()
            guard card.masterSetVariant == nil, let set = setsByID[card.setID] else {
                expanded.append(card)
                continue
            }
            if slotsBySet[card.setID] == nil {
                slotsBySet[card.setID] = Dictionary(grouping: try await slots(set).filter { $0.masterSetVariant != nil },
                                                    by: \.providerID)
            }
            let cardSlots = slotsBySet[card.setID]?[card.providerID] ?? []
            expanded += cardSlots.isEmpty ? [card] : cardSlots
        }
        return expanded
    }
}

/// Reads a bounded set refresh or every remaining page for an explicit full-set sort.
@MainActor
enum CatalogSetPageLoader {
    struct Result {
        var items: [CatalogCardSummary] = []
        var nextCursor: String?
        var count = 0
        var visitedCursors: Set<String> = []
        var error: Error?
    }

    static func collect(
        from cursor: String?,
        limit: Int?,
        visitedCursors: Set<String> = [],
        load: (String?) async throws -> CatalogPage<CatalogCardSummary>
    ) async -> Result {
        var result = Result(nextCursor: cursor, visitedCursors: visitedCursors)
        repeat {
            let current = result.nextCursor
            do {
                try Task.checkCancellation()
                let page = try await load(current)
                try Task.checkCancellation()
                if let next = page.nextCursor, next == current || result.visitedCursors.contains(next) {
                    throw BrowseCatalogError.badResponse
                }
                if let current { result.visitedCursors.insert(current) }
                result.items += page.items
                result.count += 1
                result.nextCursor = page.nextCursor
            } catch {
                result.error = error
                break
            }
        } while result.nextCursor != nil && (limit.map { result.count < $0 } ?? true)
        return result
    }
}
