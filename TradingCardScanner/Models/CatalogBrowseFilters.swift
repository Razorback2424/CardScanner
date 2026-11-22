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
        isOwned: (CatalogCardSummary) -> Bool
    ) -> [CatalogCardSummary] {
        let candidates: [CatalogCardSummary]
        let available = Self.finishes(of: card)
        if scopesFinish(of: card), !available.isEmpty {
            candidates = available.map { finish in
                var copy = card
                copy.masterSetVariant = finish
                return copy
            }
        } else {
            candidates = [card]
        }
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
                seenIDs.insert($0.id).inserted && filters.matchesWithoutPrice($0, isOwned: isOwned)
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
