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

    func testSetPriceScopeUsesSearchTierAndFinishBeforeResolvingPrices() {
        let set = set("a")
        let normal = card("1", set: set)
        let reverse = card("1", set: set, variant: .reverse)
        var expanded = card("1", set: set, variant: .pokeBall)
        expanded.isExpandedMasterSetVariant = true
        let unrelated = card("2", set: set, variant: .reverse)
        let cards = [normal, reverse, expanded, unrelated]
        let filters = CatalogBrowseFilters(variantIDs: [reverse.masterSetVariant!.id, PhysicalVariant.pokeBall.id],
            price: .band(.fiveToTen))
        let owned = CatalogOwnershipIndex(rows: [])

        XCTAssertEqual(CatalogBrowsePresentation.setPriceCandidates(cards, in: set, search: "1",
            tier: .standard, filters: filters, ownership: owned), [reverse])
        XCTAssertEqual(CatalogBrowsePresentation.setPriceCandidates(cards, in: set, search: "1",
            tier: .expanded, filters: filters, ownership: owned), [reverse, expanded])
        XCTAssertEqual(CatalogBrowsePresentation.setPriceCandidates(cards, in: set, search: "",
            tier: .standard, filters: filters, ownership: owned), [reverse, unrelated])
    }

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

    func testQuoteRetryKeepsLastKnownPriceUntilProviderConfirmsGap() {
        let previous = CatalogBrowseQuote(amount: 17, status: .priced, asOf: .distantPast, source: .scryfall)
        let pending = CatalogPriceUpdate(prices: [:], resolvedIDs: [], unresolvedIDs: [])
        XCTAssertEqual(CatalogBrowseQuote.merging(pending, id: "foil", previous: previous), previous)
        let failed = CatalogPriceUpdate(prices: [:], resolvedIDs: [], unresolvedIDs: ["foil"])
        let retained = CatalogBrowseQuote.merging(failed, id: "foil", previous: previous)
        XCTAssertEqual(retained, .init(amount: 17, status: .stale, asOf: .distantPast, source: .scryfall))
        let gap = CatalogPriceUpdate(prices: [:], resolvedIDs: ["foil"], unresolvedIDs: [])
        XCTAssertEqual(CatalogBrowseQuote.merging(gap, id: "foil", previous: retained),
                       .init(amount: nil, status: .noQuote))
    }

    func testChocoboTrackFoilUsesMatchingQuoteForFilterTileAndSort() throws {
        let fic = set("fic", game: .magic)
        let forest = card("482", set: fic, variant: nil, treatments: ["chocobotrackfoil"], finishes: ["foil", "nonfoil"])
        let mountain = card("481", set: fic, variant: nil, treatments: ["chocobotrackfoil"], finishes: ["foil", "nonfoil"])
        let owned = CatalogOwnershipIndex(rows: [])
        let filters = CatalogBrowseFilters(magicTreatmentIDs: ["chocobotrackfoil"], price: .custom(min: 5, max: 20))
        let allSlots = CatalogBrowsePresentation.candidates([forest, mountain], filters: .none, ownership: owned)
        let quotes = Dictionary(uniqueKeysWithValues: allSlots.map { slot in
            let price: Double = slot.masterSetVariant == .foil ? (slot.providerID == forest.providerID ? 17 : 8) : 90
            return (slot.id, CatalogBrowseQuote(amount: price, status: .priced))
        })
        let matching = CatalogBrowsePresentation.candidates([mountain, forest], filters: filters, ownership: owned)
        XCTAssertEqual(matching.map(\.masterSetVariant), [.foil, .foil])
        let rows = CatalogBrowsePresentation.rows(matching, filters: filters, sort: .priceDescending,
                                                   sets: [fic], quotes: quotes, ownership: owned)
        XCTAssertEqual(rows.map { $0.group.preferredSummary.providerID }, [forest.providerID, mountain.providerID])
        XCTAssertEqual(rows.map(\.price), [17, 8])
        XCTAssertEqual(rows.map { $0.representative?.masterSetVariant }, [.foil, .foil])
    }

    func testPriceAndReleaseOrderingAcrossEachGameWithUnknownValues() {
        let owned = CatalogOwnershipIndex(rows: [])
        let games: [CardGame] = [.magic, .pokemon, .onePiece, .lorcana, .yuGiOh]
        for game in games {
            let firstSet = set("first", game: game), secondSet = set("second", game: game)
            var latePage = card("2", set: secondSet)
            latePage.printingReleaseDate = Date(timeIntervalSince1970: 20)
            var firstPage = card("1", set: firstSet)
            firstPage.printingReleaseDate = Date(timeIntervalSince1970: 10)
            let unknown = card("3", set: firstSet)
            let quotes: [String: CatalogBrowseQuote] = [
                firstPage.id: .init(amount: 5, status: .priced),
                latePage.id: .init(amount: 50, status: .priced),
                unknown.id: .init(amount: nil, status: .failed)
            ]
            let filters = CatalogBrowseFilters(setIDs: [firstSet.catalogID, secondSet.catalogID],
                                               variantIDs: [PhysicalVariant.normal.id])
            let forward = [firstPage, unknown, latePage]
            let reverse = Array(forward.reversed())
            for sort: CatalogBrowseSort in [.priceDescending, .priceAscending, .releaseDescending, .releaseAscending] {
                let lhs = CatalogBrowsePresentation.rows(
                    CatalogBrowsePresentation.candidates(forward, filters: filters, ownership: owned),
                    filters: filters, sort: sort, sets: [], quotes: quotes, ownership: owned
                )
                let rhs = CatalogBrowsePresentation.rows(
                    CatalogBrowsePresentation.candidates(reverse, filters: filters, ownership: owned),
                    filters: filters, sort: sort, sets: [], quotes: quotes, ownership: owned
                )
                XCTAssertEqual(lhs.map(\.id), rhs.map(\.id), game.label)
                XCTAssertEqual(lhs.last?.group.preferredSummary.id, unknown.id, game.label)
                let highestFirst = sort == .priceDescending || sort == .releaseDescending
                XCTAssertEqual(lhs.first?.group.preferredSummary.id, highestFirst ? latePage.id : firstPage.id, game.label)
            }
        }
    }

    func testAdapterFinishSelectionRetainsVerifiedPrintingIdentity() throws {
        var printing = card("OP01-001", set: set("op01", game: .onePiece), variant: nil)
        printing.verifiedBrowseFinishes = [.foil]
        let selected = try XCTUnwrap(CatalogBrowseFilters.explicitFinishes(of: printing).first)
        XCTAssertNotEqual(selected.id, printing.id)
        XCTAssertEqual(selected.baseBrowseSelection, printing)
        var unsupported = selected
        unsupported.masterSetVariant = .etched
        XCTAssertEqual(unsupported.baseBrowseSelection, unsupported)
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

    func testMagicFilteredBrowseMatchesFinishTreatmentAndOwnershipOnTheSameCopy() async throws {
        let printing = card("98", set: set("fic", game: .magic), variant: nil,
                            treatments: ["surgefoil"], finishes: ["nonfoil", "foil"])
        let plain = CollectedCard(collectionKey: "fic-98#nonfoil", game: .magic, providerID: printing.providerID,
            name: printing.name, setName: printing.setName, setCode: printing.setCode, cardNumber: "98",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .nonfoil, variantResolution: .userConfirmed)
        let owned = CatalogOwnershipIndex([plain])
        var filters = CatalogBrowseFilters(variantIDs: ["nonfoil"], magicTreatmentIDs: ["surgefoil"])
        XCTAssertFalse(filters.matchesWithoutPrice(printing, isOwned: owned.owns))

        filters.variantIDs = ["foil"]
        filters.ownership = .owned
        XCTAssertFalse(filters.matchesWithoutPrice(printing, isOwned: owned.owns))
        filters.ownership = .notOwned
        let fill = await CatalogFilteredPager.fill(from: CatalogSearchPosition.start, filters: filters,
            loadPage: { _ in .init(items: [printing], next: nil) }, isOwned: owned.owns,
            resolvePrices: { _ in [:] }, isCurrent: { true })
        XCTAssertEqual(fill?.matches, [printing])
        XCTAssertEqual(filters.matchingPrintings(for: printing, isOwned: owned.owns).compactMap(\.masterSetVariant), [.foil])

        filters.variantIDs = []
        filters.ownership = .owned
        XCTAssertFalse(filters.matchesWithoutPrice(printing, isOwned: owned.owns))
        filters.ownership = .notOwned
        XCTAssertTrue(filters.matchesWithoutPrice(printing, isOwned: owned.owns))
    }

    func testPokemonPrintRunCombinesWithSetAndFinishFilters() {
        let firstID = CatalogSetID(game: .pokemon, providerID: "base1", pokemonPrintRun: .firstEdition)
        let unlimitedID = CatalogSetID(game: .pokemon, providerID: "base1", pokemonPrintRun: .unlimited)
        let first = CatalogCardSummary(game: .pokemon, providerID: "base1-4", setID: firstID,
            setName: "Base Set — 1st Edition", setCode: "BS", name: "Charizard", collectorNumber: "4",
            thumbnailURL: nil, imageURL: nil, masterSetVariant: .holo)
        let unlimited = CatalogCardSummary(game: .pokemon, providerID: "base1-4", setID: unlimitedID,
            setName: "Base Set — Unlimited", setCode: "BS", name: "Charizard", collectorNumber: "4",
            thumbnailURL: nil, imageURL: nil, masterSetVariant: .holo)
        var filters = CatalogBrowseFilters(pokemonPrintRuns: [.firstEdition], variantIDs: ["holo"])
        XCTAssertTrue(filters.matchesWithoutPrice(first, isOwned: false))
        XCTAssertFalse(filters.matchesWithoutPrice(unlimited, isOwned: false))
        filters.setIDs = [unlimitedID]
        XCTAssertFalse(filters.matchesWithoutPrice(first, isOwned: false))
    }

    func testPokemonMissingSearchExpandsFinishesWithoutAnExplicitFinishFilter() async throws {
        let set = set("base1")
        let holo = card("4", set: set, variant: .holo)
        let normal = card("4", set: set, variant: .normal)
        let hit = card("4", set: set, variant: nil)
        let stored = CollectedCard(collectionKey: "normal", game: .pokemon, providerID: normal.providerID,
            name: normal.name, setName: set.name, setCode: set.code, cardNumber: normal.collectorNumber,
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal, variantResolution: .userConfirmed)
        let ownership = CatalogOwnershipIndex([stored])
        let filters = CatalogBrowseFilters(ownership: .notOwned)
        XCTAssertTrue(CatalogSearchFinishExpansion.needsExpansion(game: .pokemon, filters: filters))
        let expanded = try await CatalogSearchFinishExpansion.expand([hit], setsByID: [set.catalogID: set]) { _ in [normal, holo] }
        XCTAssertEqual(expanded.filter { filters.matchesWithoutPrice($0, isOwned: ownership.owns) }, [holo])
    }

    func testVerifiedAdapterFinishFilterScopesOwnershipWithoutChangingPrintingID() throws {
        let set = set("d23", game: .lorcana)
        let foil = LorcanaPhysicalFinish.rainbowPillarsFoil.variant
        let browseOnly = card("1", set: set, variant: nil)
        var verified = browseOnly
        verified.verifiedBrowseFinishes = [.normal, foil]
        var facets = CatalogBrowseFacets()
        facets.record([verified])
        XCTAssertEqual(facets.finishOptions(base: [], for: .lorcana), [.normal, foil])
        let filters = CatalogBrowseFilters(variantIDs: [foil.id], ownership: .notOwned)
        let owned = CollectedCard(collectionKey: "normal", game: .lorcana, providerID: verified.providerID,
            name: verified.name, setName: set.name, setCode: set.code, cardNumber: verified.collectorNumber,
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal, variantResolution: .userConfirmed)
        XCTAssertTrue(filters.matchesWithoutPrice(verified, isOwned: CatalogOwnershipIndex([owned]).owns))
        XCTAssertFalse(filters.matchesWithoutPrice(browseOnly, isOwned: false))
        XCTAssertEqual(try JSONDecoder().decode(CatalogCardSummary.self, from: JSONEncoder().encode(verified)).id, browseOnly.id)
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
        XCTAssertTrue(magicFacets.treatmentOptions(for: .magic).contains(.galaxyFoil))
    }

    func testPokemonBrowseExposesBundledSpecialtyFinishesBeforeCardsLoad() async {
        let bundled = await PokemonBrowseFinishCatalog.bundled.value
        let options = CatalogBrowseFacets().finishOptions(base: PokemonVariantPolicy().selectableVariants,
                                                          catalog: bundled, for: .pokemon)
        XCTAssertTrue(options.contains(.pokemonFoilPattern("cosmos")))
        XCTAssertTrue(options.contains(PokemonReviewedPhysicalObjects.cosmosHolo))
        XCTAssertTrue(options.contains(PokemonReviewedPhysicalObjects.cosmosReverse))
        XCTAssertTrue(options.contains(.pokemonFoilPattern("cracked-ice")))
        XCTAssertFalse(options.contains(.firstEdition))
        XCTAssertFalse(options.contains(.jumbo))
    }

    func testFullSetSortIncludesCardsOnTheLastPage() async throws {
        let magic = set("fin", game: .magic)
        let first = card("5", set: magic, variant: nil)
        let middle = card("11", set: magic, variant: nil)
        let last = card("1", set: magic, variant: nil)
        let pages: [String: CatalogPage<CatalogCardSummary>] = [
            "second": .init(items: [middle], nextCursor: "third"),
            "third": .init(items: [last], nextCursor: nil)
        ]
        let result = await CatalogSetPageLoader.collect(from: "second", limit: nil) { cursor in
            try XCTUnwrap(pages[cursor ?? ""])
        }
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result.nextCursor)
        XCTAssertNil(result.error)
        let cards = [first] + result.items
        let ownership = CatalogOwnershipIndex(rows: [])
        let prices = [first.id: 10.0, middle.id: 1.0, last.id: 100.0]
        XCTAssertEqual(CatalogSetQuery.apply(cards, search: "", sort: .numberLowToHigh,
            ownership: .all, owned: ownership, prices: prices).map(\.id), [last.id, first.id, middle.id])
        XCTAssertEqual(CatalogSetQuery.apply(cards, search: "", sort: .priceHighToLow,
            ownership: .all, owned: ownership, prices: prices).map(\.id), [last.id, first.id, middle.id])
    }

    func testFilteredPagerRejectsCyclesAcrossFillsAndCountsOnlyNewCards() async throws {
        let card = card("1", set: set("a"))
        let a = CatalogSearchPosition(cursor: "a"), b = CatalogSearchPosition(cursor: "b")
        let first = await CatalogFilteredPager.fill(from: a, filters: .none,
            limits: .init(targetMatchCount: 1, maxPagesPerFill: 1), loadPage: { _ in .init(items: [card], next: b) },
            isOwned: { _ in false }, resolvePrices: { _ in [:] }, isCurrent: { true })
        let initial = try XCTUnwrap(first)
        let c = CatalogSearchPosition(cursor: "c")
        let next = await CatalogFilteredPager.fill(from: initial.position, filters: .none,
            limits: .init(targetMatchCount: 1, maxPagesPerFill: 8), visitedPositions: initial.visitedPositions,
            existingIDs: Set(initial.matches.map(\.id)), loadPage: { position in
                .init(items: [card], next: position == b ? c : a)
            }, isOwned: { _ in false }, resolvePrices: { _ in [:] }, isCurrent: { true })
        XCTAssertEqual(next?.matches, [])
        XCTAssertEqual(next?.position, c)
        XCTAssertEqual(next?.visitedPositions, [a, b])
        XCTAssertNotNil(next?.error)
    }

    func testFullSetSortKeepsCompletedPagesAndRetriesFailedCursor() async {
        let s = set("fin", game: .magic)
        let middle = card("2", set: s, variant: nil), last = card("3", set: s, variant: nil)
        let first = await CatalogSetPageLoader.collect(from: "2", limit: nil) { cursor in
            guard cursor == "2" else { throw PageFailure() }
            return .init(items: [middle], nextCursor: "3")
        }
        XCTAssertEqual(first.items, [middle])
        XCTAssertEqual(first.nextCursor, "3")
        XCTAssertNotNil(first.error)
        let resumed = await CatalogSetPageLoader.collect(from: first.nextCursor, limit: nil,
            visitedCursors: first.visitedCursors) { cursor in
            XCTAssertEqual(cursor, "3")
            return .init(items: [last], nextCursor: nil)
        }
        XCTAssertEqual(resumed.items, [last])
        XCTAssertNil(resumed.nextCursor)
        XCTAssertNil(resumed.error)
    }

    func testChocoboTrackFoilIsAvailableBeforeLoadingCardsAndPrioritizesKnownSets() {
        let options = CatalogBrowseFacets().treatmentOptions(for: .magic)
        XCTAssertEqual(options.first { $0.id == "chocobotrackfoil" }?.label, "Chocobo Track Foil")
        XCTAssertTrue(CatalogBrowseFacets().treatmentOptions(for: .pokemon).isEmpty)

        let newer = set("ecl", game: .magic)
        let finalFantasy = set("fin", game: .magic)
        let commander = set("fic", game: .magic)
        let directory = [newer, finalFantasy, commander]
        var filters = CatalogBrowseFilters(magicTreatmentIDs: ["chocobotrackfoil"])
        XCTAssertEqual(filters.restrictedSets(directory), [finalFantasy, commander, newer])

        filters.setIDs = [newer.catalogID, commander.catalogID]
        XCTAssertEqual(filters.restrictedSets(directory), [commander, newer])
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
