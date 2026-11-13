import XCTest
@testable import TradingCardScanner

@MainActor
final class BrowseFilterTests: XCTestCase {
    private struct PageFailure: Error {}

    // MARK: Fixtures

    private func set(_ id: String, game: CardGame = .pokemon) -> CatalogSet {
        CatalogSet(catalogID: CatalogSetID(game: game, providerID: id), name: id.uppercased(), code: id.uppercased(),
                   logoURL: nil, symbolURL: nil, cardCount: nil, releaseDate: nil, sortRank: 0)
    }

    private func card(
        _ number: String, set: CatalogSet, variant: PhysicalVariant? = .normal,
        treatments: [String] = [], finishes: [String]? = nil
    ) -> CatalogCardSummary {
        CatalogCardSummary(
            game: set.catalogID.game, providerID: "\(set.catalogID.providerID)-\(number)", setID: set.catalogID,
            setName: set.name, setCode: set.code, name: "Card \(number)", collectorNumber: number,
            thumbnailURL: nil, imageURL: nil, masterSetVariant: variant,
            magicTreatmentIDsRaw: treatments, magicFinishIDs: finishes)
    }

    // MARK: Matching

    func testEmptyFiltersMatchEverythingAndReportInactive() {
        let filters = CatalogBrowseFilters.none
        XCTAssertFalse(filters.isActive)
        XCTAssertEqual(filters.activeCount, 0)
        XCTAssertTrue(filters.matchesWithoutPrice(card("1", set: set("a")), isOwned: false))
    }

    func testActiveCountCountsGroupsNotValues() {
        var filters = CatalogBrowseFilters()
        filters.variantIDs = ["holo", "reverse"]
        filters.ownership = .owned
        filters.price = .band(.fiveToTen)
        XCTAssertEqual(filters.activeCount, 3)
        XCTAssertTrue(filters.needsPrices)
    }

    func testFinishFilterUsesPokemonVariantAndMagicFinishIDs() {
        var filters = CatalogBrowseFilters()
        filters.variantIDs = ["holo", "foil"]
        let pokemon = set("sv1")
        let magic = set("neo", game: .magic)
        XCTAssertTrue(filters.matchesWithoutPrice(card("1", set: pokemon, variant: .holo), isOwned: false))
        XCTAssertFalse(filters.matchesWithoutPrice(card("2", set: pokemon, variant: .normal), isOwned: false))
        XCTAssertTrue(filters.matchesWithoutPrice(
            card("3", set: magic, variant: nil, finishes: ["nonfoil", "foil"]), isOwned: false))
        XCTAssertFalse(filters.matchesWithoutPrice(
            card("4", set: magic, variant: nil, finishes: ["nonfoil"]), isOwned: false))
        // A search row with no finish data cannot satisfy a finish question.
        XCTAssertFalse(filters.matchesWithoutPrice(card("5", set: pokemon, variant: nil), isOwned: false))
    }

    func testTreatmentFilterIsCaseInsensitiveAndIgnoresUnknownRequests() {
        let magic = set("neo", game: .magic)
        var filters = CatalogBrowseFilters()
        filters.magicTreatmentIDs = ["GalaxyFoil"]
        XCTAssertTrue(filters.matchesWithoutPrice(card("1", set: magic, variant: nil, treatments: ["galaxyfoil"]), isOwned: false))
        XCTAssertFalse(filters.matchesWithoutPrice(card("2", set: magic, variant: nil, treatments: ["surgefoil"]), isOwned: false))
        filters.magicTreatmentIDs = ["   "]
        XCTAssertFalse(filters.matchesWithoutPrice(card("3", set: magic, variant: nil, treatments: ["galaxyfoil"]), isOwned: false))
    }

    func testSetAndOwnershipFilters() {
        let a = set("a"), b = set("b")
        var filters = CatalogBrowseFilters()
        filters.setIDs = [a.catalogID]
        XCTAssertTrue(filters.matchesWithoutPrice(card("1", set: a), isOwned: false))
        XCTAssertFalse(filters.matchesWithoutPrice(card("1", set: b), isOwned: false))
        XCTAssertEqual(filters.restrictedSets([b, a]).map(\.catalogID), [a.catalogID])

        filters = CatalogBrowseFilters()
        filters.ownership = .notOwned
        XCTAssertTrue(filters.matchesWithoutPrice(card("1", set: a), isOwned: false))
        XCTAssertFalse(filters.matchesWithoutPrice(card("1", set: a), isOwned: true))
    }

    func testPriceMatchingKeepsPendingDistinctFromUnpriced() {
        let c = card("1", set: set("a"))
        var filters = CatalogBrowseFilters()
        filters.price = .band(.fiveToTen)
        XCTAssertEqual(filters.matches(c, isOwned: false, price: .priced(5)), true)
        XCTAssertEqual(filters.matches(c, isOwned: false, price: .priced(10)), false)
        XCTAssertEqual(filters.matches(c, isOwned: false, price: .unpriced), false)
        XCTAssertNil(filters.matches(c, isOwned: false, price: .pending))

        filters.price = .unpriced
        XCTAssertEqual(filters.matches(c, isOwned: false, price: .unpriced), true)
        XCTAssertNil(filters.matches(c, isOwned: false, price: .pending))
        // A card that already fails a cheap filter never waits on a price.
        filters.ownership = .owned
        XCTAssertEqual(filters.matches(c, isOwned: false, price: .pending), false)
    }

    func testPriceResolutionMergeSeparatesCoverageGapsFromFailures() {
        var resolutions: [String: CatalogPriceResolution] = [:]
        CatalogPriceResolution.merge(CatalogPriceUpdate(
            prices: ["a": 3], resolvedIDs: ["a", "b"], unresolvedIDs: ["c"], missingMappingIDs: ["d"]
        ), into: &resolutions)
        XCTAssertEqual(resolutions, ["a": .priced(3), "b": .unpriced, "c": .pending, "d": .unpriced])
        CatalogPriceResolution.merge(CatalogPriceUpdate(
            prices: ["c": 7], resolvedIDs: ["c"], unresolvedIDs: []
        ), into: &resolutions)
        XCTAssertEqual(resolutions["c"], .priced(7))
    }

    func testResolveStopsOnceEveryCardIsSettledAndReportsSilenceAsPending() async {
        let s = set("a")
        let cards = [card("1", set: s), card("2", set: s), card("3", set: s)]
        let (stream, continuation) = AsyncStream<CatalogPriceUpdate>.makeStream()
        continuation.yield(CatalogPriceUpdate(prices: [cards[0].id: 2], resolvedIDs: [cards[0].id], unresolvedIDs: [cards[1].id]))
        continuation.finish()
        let resolutions = await CatalogPriceResolution.resolve(cards, from: stream)
        XCTAssertEqual(resolutions[cards[0].id], .priced(2))
        XCTAssertEqual(resolutions[cards[1].id], .pending)
        XCTAssertEqual(resolutions[cards[2].id], .pending)

        // Never finished: returns as soon as all cards settle instead of hanging.
        let (open, openContinuation) = AsyncStream<CatalogPriceUpdate>.makeStream()
        openContinuation.yield(CatalogPriceUpdate(prices: [:], resolvedIDs: Set(cards.map(\.id)), unresolvedIDs: []))
        let settled = await CatalogPriceResolution.resolve(cards, from: open)
        XCTAssertEqual(Set(settled.values), [.unpriced])
        openContinuation.finish()
    }

    // MARK: Positions

    func testSetWalkPositionAdvancesThroughCursorsThenSets() {
        let start = CatalogSetWalkPosition.start
        XCTAssertEqual(start.advanced(by: "p2", setCount: 2), CatalogSetWalkPosition(setIndex: 0, cursor: "p2"))
        XCTAssertEqual(start.advanced(by: nil, setCount: 2), CatalogSetWalkPosition(setIndex: 1, cursor: nil))
        XCTAssertNil(CatalogSetWalkPosition(setIndex: 1, cursor: "x").advanced(by: nil, setCount: 2))
        XCTAssertEqual(CatalogSetWalkPosition(setIndex: 0, cursor: "x").skippingSet(setCount: 2)?.setIndex, 1)
        XCTAssertNil(CatalogFilteredPager.setWalkStart(sets: []))
    }

    // MARK: Pager

    /// Builds a set walk over `pages[setID]`, recording each request.
    private func walk(
        _ sets: [CatalogSet], pages: [String: [[CatalogCardSummary]]], failing: Set<String> = [],
        requests: @escaping (String) -> Void = { _ in }
    ) -> (CatalogSetWalkPosition) async throws -> CatalogFilteredPager.Page<CatalogSetWalkPosition> {
        CatalogFilteredPager.setWalkLoader(sets: sets) { set, cursor in
            let id = set.catalogID.providerID
            let index = Int(cursor ?? "0") ?? 0
            requests("\(id)#\(index)")
            if failing.contains("\(id)#\(index)") { throw PageFailure() }
            let setPages = pages[id] ?? [[]]
            return CatalogPage(items: setPages[index], nextCursor: index + 1 < setPages.count ? String(index + 1) : nil)
        }
    }

    private func noPrices(_ cards: [CatalogCardSummary]) async -> [String: CatalogPriceResolution] {
        XCTFail("prices requested without a price filter")
        return [:]
    }

    func testFillKeepsLoadingAcrossSetsUntilTargetMatchesArrive() async throws {
        let a = set("a"), b = set("b"), c = set("c")
        let pages = [
            "a": [[card("1", set: a, variant: .normal), card("2", set: a, variant: .holo)],
                  [card("3", set: a, variant: .normal)]],
            "b": [[card("1", set: b, variant: .holo)]],
            "c": [[card("1", set: c, variant: .holo), card("2", set: c, variant: .holo)]],
        ]
        var requested: [String] = []
        var filters = CatalogBrowseFilters()
        filters.variantIDs = ["holo"]
        let fillResult = await CatalogFilteredPager.fill(
            from: .start, filters: filters, limits: .init(targetMatchCount: 2, maxPagesPerFill: 10),
            loadPage: walk([a, b, c], pages: pages) { requested.append($0) },
            isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { true })
        let fill = try XCTUnwrap(fillResult)
        XCTAssertEqual(fill.matches.map(\.id), [pages["a"]![0][1].id, pages["b"]![0][0].id])
        XCTAssertEqual(requested, ["a#0", "a#1", "b#0"])
        XCTAssertEqual(fill.position, CatalogSetWalkPosition(setIndex: 2, cursor: nil))
        XCTAssertFalse(fill.stoppedAtPageLimit)

        let restResult = await CatalogFilteredPager.fill(
            from: fill.position, filters: filters, loadPage: walk([a, b, c], pages: pages),
            isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { true })
        let rest = try XCTUnwrap(restResult)
        XCTAssertEqual(rest.matches.count, 2)
        XCTAssertTrue(rest.isExhausted)
    }

    func testFillStopsAtPageCapSoSelectiveFiltersDoNotCrawlSilently() async throws {
        let sets = (0..<5).map { set("s\($0)") }
        let pages = Dictionary(uniqueKeysWithValues: sets.map {
            ($0.catalogID.providerID, [[card("1", set: $0, variant: .normal)]])
        })
        var filters = CatalogBrowseFilters()
        filters.variantIDs = ["masterBall"]
        let fillResult = await CatalogFilteredPager.fill(
            from: .start, filters: filters, limits: .init(targetMatchCount: 24, maxPagesPerFill: 3),
            loadPage: walk(sets, pages: pages), isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { true })
        let fill = try XCTUnwrap(fillResult)
        XCTAssertTrue(fill.matches.isEmpty)
        XCTAssertTrue(fill.stoppedAtPageLimit)
        XCTAssertEqual(fill.pagesLoaded, 3)
        XCTAssertEqual(fill.scannedCount, 3)
        XCTAssertEqual(fill.position, CatalogSetWalkPosition(setIndex: 3, cursor: nil))
        XCTAssertFalse(fill.isExhausted)
    }

    func testFillOnlyWalksRestrictedSets() async throws {
        let a = set("a"), b = set("b")
        var filters = CatalogBrowseFilters()
        filters.setIDs = [b.catalogID]
        let sets = filters.restrictedSets([a, b])
        var requested: [String] = []
        let fillResult = await CatalogFilteredPager.fill(
            from: CatalogFilteredPager.setWalkStart(sets: sets), filters: filters,
            loadPage: walk(sets, pages: ["a": [[card("1", set: a)]], "b": [[card("1", set: b)]]]) { requested.append($0) },
            isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { true })
        let fill = try XCTUnwrap(fillResult)
        XCTAssertEqual(requested, ["b#0"])
        XCTAssertEqual(fill.matches.map(\.setID), [b.catalogID])
        XCTAssertTrue(fill.isExhausted)
    }

    func testFillKeepsPartialMatchesAndFailedPositionOnError() async throws {
        let a = set("a"), b = set("b")
        let pages = ["a": [[card("1", set: a)]], "b": [[card("1", set: b)]]]
        let fillResult = await CatalogFilteredPager.fill(
            from: .start, filters: CatalogBrowseFilters(ownership: .notOwned),
            loadPage: walk([a, b], pages: pages, failing: ["b#0"]),
            isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { true })
        let fill = try XCTUnwrap(fillResult)
        XCTAssertEqual(fill.matches.count, 1)
        XCTAssertNotNil(fill.error)
        XCTAssertEqual(fill.position, CatalogSetWalkPosition(setIndex: 1, cursor: nil))
        XCTAssertFalse(fill.isExhausted)
        XCTAssertNil(fill.position?.skippingSet(setCount: 2))
    }

    func testFillPricesOnlyCheapMatchesAndHoldsPendingBack() async throws {
        let a = set("a")
        let cheap = card("1", set: a, variant: .holo)
        let pricey = card("2", set: a, variant: .holo)
        let unknown = card("3", set: a, variant: .holo)
        let normal = card("4", set: a, variant: .normal)
        var filters = CatalogBrowseFilters()
        filters.variantIDs = ["holo"]
        filters.price = .band(.fiveToTen)
        var priced: [String] = []
        let fillResult = await CatalogFilteredPager.fill(
            from: .start, filters: filters,
            loadPage: walk([a], pages: ["a": [[cheap, pricey, unknown, normal]]]),
            isOwned: { _ in false },
            resolvePrices: { cards in
                priced = cards.map(\.id)
                return [cheap.id: .priced(6), pricey.id: .priced(60), unknown.id: .pending]
            },
            isCurrent: { true })
        let fill = try XCTUnwrap(fillResult)
        XCTAssertEqual(priced, [cheap.id, pricey.id, unknown.id])
        XCTAssertEqual(fill.matches.map(\.id), [cheap.id])
        XCTAssertEqual(fill.pendingPrice.map(\.id), [unknown.id])
        XCTAssertEqual(fill.priceResolutions[pricey.id], .priced(60))
    }

    func testFillDropsResultWhenSupersededDuringLoadOrPricing() async {
        let a = set("a")
        var current = true
        let staleAfterLoad = await CatalogFilteredPager.fill(
            from: .start, filters: .none,
            loadPage: { (_: CatalogSetWalkPosition) in
                current = false
                return .init(items: [self.card("1", set: a)], next: nil)
            },
            isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { current })
        XCTAssertNil(staleAfterLoad)

        current = true
        var filters = CatalogBrowseFilters()
        filters.price = .unpriced
        let staleAfterPricing = await CatalogFilteredPager.fill(
            from: .start, filters: filters, loadPage: walk([a], pages: ["a": [[card("1", set: a)]]]),
            isOwned: { _ in false },
            resolvePrices: { cards in
                current = false
                return Dictionary(uniqueKeysWithValues: cards.map { ($0.id, .unpriced) })
            },
            isCurrent: { current })
        XCTAssertNil(staleAfterPricing)
    }

    func testSearchLoaderPagesByCursor() async throws {
        let a = set("a")
        var cursors: [String?] = []
        let loader = CatalogFilteredPager.searchLoader { cursor in
            cursors.append(cursor)
            return cursor == nil
                ? CatalogPage(items: [self.card("1", set: a, variant: .holo)], nextCursor: "next")
                : CatalogPage(items: [self.card("2", set: a, variant: .holo)], nextCursor: nil)
        }
        let fillResult = await CatalogFilteredPager.fill(
            from: CatalogSearchPosition.start, filters: CatalogBrowseFilters(variantIDs: ["holo"]),
            loadPage: loader, isOwned: { _ in false }, resolvePrices: noPrices, isCurrent: { true })
        let fill = try XCTUnwrap(fillResult)
        XCTAssertEqual(cursors, [nil, "next"])
        XCTAssertEqual(fill.matches.count, 2)
        XCTAssertTrue(fill.isExhausted)
    }

    // MARK: Facets and search expansion

    func testFacetsHideFinishUntilRowsCarryOneThenLeadWithTheGamesFinishes() {
        var facets = CatalogBrowseFacets()
        let a = set("a")
        facets.record([card("1", set: a, variant: nil)])
        XCTAssertTrue(facets.finishOptions(base: [.normal, .holo]).isEmpty)

        facets.record([card("1", set: a, variant: .masterBall), card("2", set: a, variant: .holo)])
        XCTAssertEqual(facets.finishOptions(base: [.normal, .holo]).map(\.id), ["normal", "holo", "masterBall"])

        let magic = set("neo", game: .magic)
        var magicFacets = CatalogBrowseFacets()
        magicFacets.record([card("1", set: magic, variant: nil, treatments: ["galaxyfoil"], finishes: ["nonfoil", "foil"])])
        XCTAssertEqual(magicFacets.finishOptions(base: []).map(\.id), ["nonfoil", "foil"])
        XCTAssertEqual(magicFacets.treatmentIDs, ["galaxyfoil"])
    }

    func testSearchExpansionReplacesFinishlessRowsWithTheirSlotsInOrder() async throws {
        let a = set("a"), unknown = set("gone")
        let pikachu = card("25", set: a, variant: nil)
        let raichu = card("26", set: a, variant: nil)
        let orphan = card("1", set: unknown, variant: nil)
        let slots = [card("25", set: a, variant: .normal), card("25", set: a, variant: .reverse),
                     card("26", set: a, variant: .holo), card("27", set: a, variant: .normal)]
        var slotRequests = 0
        let expanded = try await CatalogSearchFinishExpansion.expand(
            [pikachu, orphan, raichu], setsByID: [a.catalogID: a]
        ) { _ in
            slotRequests += 1
            return slots
        }
        XCTAssertEqual(expanded.map(\.id), [slots[0].id, slots[1].id, orphan.id, slots[2].id])
        XCTAssertEqual(slotRequests, 1)
        XCTAssertTrue(CatalogSearchFinishExpansion.needsExpansion(game: .pokemon, filters: CatalogBrowseFilters(variantIDs: ["holo"])))
        XCTAssertFalse(CatalogSearchFinishExpansion.needsExpansion(game: .pokemon, filters: .none))
        XCTAssertFalse(CatalogSearchFinishExpansion.needsExpansion(game: .magic, filters: CatalogBrowseFilters(variantIDs: ["foil"])))
    }
}
