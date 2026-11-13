import Foundation

/// The questions a collector can ask of a game's Browse grid. Kept apart from
/// `CollectionFilters`: catalog summaries are not owned rows, so quantity and
/// grading have no meaning here, while ownership does.
struct CatalogBrowseFilters: Equatable, Sendable {
    /// Empty means every set.
    var setIDs: Set<CatalogSetID> = []
    /// Finish ids: a Pokémon master-set `PhysicalVariant.id`, or a Magic finish id.
    var variantIDs: Set<String> = []
    var magicTreatmentIDs: Set<String> = []
    var ownership: CatalogOwnershipFilter = .all
    var price: PriceFilter?

    static let none = CatalogBrowseFilters()

    var isActive: Bool { activeCount > 0 }

    /// One per filter group in use, for the button badge and accessibility label.
    var activeCount: Int {
        [!setIDs.isEmpty, !variantIDs.isEmpty, !magicTreatmentIDs.isEmpty,
         ownership != .all, price != nil].filter { $0 }.count
    }

    /// Only a price question needs quotes, which are the expensive part of a fill.
    var needsPrices: Bool { price != nil }

    /// The newest-first set walk, narrowed to the chosen sets. Order is kept.
    func restrictedSets(_ orderedSets: [CatalogSet]) -> [CatalogSet] {
        guard !setIDs.isEmpty else { return orderedSets }
        return orderedSets.filter { setIDs.contains($0.catalogID) }
    }

    /// Every filter except price. Cheap, so it runs before any quote is requested.
    func matchesWithoutPrice(_ card: CatalogCardSummary, isOwned: Bool) -> Bool {
        if !setIDs.isEmpty, !setIDs.contains(card.setID) { return false }
        if !variantIDs.isEmpty {
            guard !Self.finishIDs(of: card).isDisjoint(with: variantIDs) else { return false }
        }
        if !magicTreatmentIDs.isEmpty {
            let requested = Set(magicTreatmentIDs.compactMap { MagicTreatment(id: $0)?.id })
            guard !requested.isEmpty else { return false }
            let cardTreatments = Set(MagicTreatmentKeyCodec.canonicalIDs(from: card.magicTreatments))
            guard !cardTreatments.isDisjoint(with: requested) else { return false }
        }
        switch ownership {
        case .all: break
        case .owned: if !isOwned { return false }
        case .notOwned: if isOwned { return false }
        }
        return true
    }

    /// `nil` means the answer depends on a price that is not known yet. Such a
    /// card is held back rather than shown as cheap or unpriced.
    func matches(
        _ card: CatalogCardSummary,
        isOwned: Bool,
        price resolution: CatalogPriceResolution
    ) -> Bool? {
        guard matchesWithoutPrice(card, isOwned: isOwned) else { return false }
        guard let price else { return true }
        switch resolution {
        case let .priced(value): return price.matches(value)
        case .unpriced: return price.matches(nil)
        case .pending: return nil
        }
    }

    static func finishIDs(of card: CatalogCardSummary) -> Set<String> {
        if let variant = card.masterSetVariant { return [variant.id] }
        return Set(card.magicFinishIDs ?? [])
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
struct CatalogSetWalkPosition: Equatable, Sendable {
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
struct CatalogSearchPosition: Equatable, Sendable {
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

    struct Fill<Position> {
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
        /// The page cap stopped the fill before the target was reached.
        var stoppedAtPageLimit = false
        var error: Error?

        var isExhausted: Bool { position == nil && error == nil }
    }

    /// Returns `nil` when `isCurrent` turned false during the fill: a newer
    /// filter, search, or catalog revision owns the grid and this result must
    /// not publish.
    static func fill<Position>(
        from start: Position?,
        filters: CatalogBrowseFilters,
        limits: Limits = Limits(),
        loadPage: (Position) async throws -> Page<Position>,
        isOwned: (CatalogCardSummary) -> Bool,
        resolvePrices: ([CatalogCardSummary]) async -> [String: CatalogPriceResolution],
        isCurrent: () -> Bool
    ) async -> Fill<Position>? {
        var fill = Fill<Position>(position: start)
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
            fill.pagesLoaded += 1
            fill.scannedCount += page.items.count
            fill.position = page.next

            let candidates = page.items.filter {
                filters.matchesWithoutPrice($0, isOwned: isOwned($0))
            }
            guard filters.needsPrices, !candidates.isEmpty else {
                fill.matches += candidates
                continue
            }
            let resolutions = await resolvePrices(candidates)
            guard isCurrent(), !Task.isCancelled else { return nil }
            fill.priceResolutions.merge(resolutions) { _, newest in newest }
            for card in candidates {
                switch filters.matches(card, isOwned: isOwned(card), price: resolutions[card.id] ?? .pending) {
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

/// The finish and treatment choices a game's rows have actually shown so far.
/// A game whose browse rows carry no finish (for example an adapter that lists
/// one printing per card) never offers an empty Finish filter.
struct CatalogBrowseFacets: Equatable {
    private(set) var finishIDs: [String] = []
    private(set) var treatmentIDs: [String] = []

    mutating func record(_ cards: [CatalogCardSummary]) {
        var knownFinishes = Set(finishIDs)
        var knownTreatments = Set(treatmentIDs)
        for card in cards {
            let finishes = card.masterSetVariant.map { [$0.id] } ?? card.magicFinishIDs ?? []
            for id in finishes where knownFinishes.insert(id).inserted { finishIDs.append(id) }
            for treatment in card.magicTreatments where knownTreatments.insert(treatment.id).inserted {
                treatmentIDs.append(treatment.id)
            }
        }
    }

    /// The game's usual finishes first, in menu order, then any other finish
    /// the rows carried. Empty until a row has shown a finish at all.
    func finishOptions(base: [PhysicalVariant]) -> [PhysicalVariant] {
        guard !finishIDs.isEmpty else { return [] }
        var seen = Set<String>()
        return (base + finishIDs.map(PhysicalVariant.resolving)).filter { seen.insert($0.id).inserted }
    }
}

/// Pokémon search answers with one row per numbered card and no finish. A
/// finish question needs the card's master-set slots, which the set's local
/// checklist already holds.
enum CatalogSearchFinishExpansion {
    static func needsExpansion(game: CardGame, filters: CatalogBrowseFilters) -> Bool {
        game == .pokemon && !filters.variantIDs.isEmpty
    }

    /// Replaces each finish-less row with its slots, in the original order. A
    /// row whose set is unknown or has no slots is kept as it was.
    static func expand(
        _ cards: [CatalogCardSummary],
        setsByID: [CatalogSetID: CatalogSet],
        slots: (CatalogSet) async throws -> [CatalogCardSummary]
    ) async throws -> [CatalogCardSummary] {
        var slotsBySet: [CatalogSetID: [String: [CatalogCardSummary]]] = [:]
        var expanded: [CatalogCardSummary] = []
        for card in cards {
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
