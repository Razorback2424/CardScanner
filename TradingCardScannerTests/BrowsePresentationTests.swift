import XCTest
@testable import TradingCardScanner

@MainActor
final class BrowsePresentationTests: XCTestCase {
    func testClassicCollectionFallbackAgreesWithChecklistAndSeparatesParent() {
        let parent = ownershipSet("30th", name: "30th Celebration", code: "30C", total: 128)
        let classic = ownershipSet("30th-c", name: "30th Celebration Classic Collection", code: "30C", total: 30)
        let classicCards = (3...7).map { ownershipCard(set: classic, number: $0) }
        let parentCards = (10...26).map { ownershipCard(set: parent, number: $0) }
        classicCards[0].quantity = 8
        let owned = CatalogOwnershipIndex(classicCards + parentCards)

        XCTAssertEqual(owned.directoryProgress(for: classic), .init(owned: 5, total: 30))
        XCTAssertEqual(owned.directoryProgress(for: parent), .init(owned: 17, total: 128))
        XCTAssertEqual(owned.ownedRowCounts(for: [parent, classic]), [parent.id: 17, classic.id: 5])
        let slots = (1...30).map { number in
            CatalogCardSummary(game: .pokemon, providerID: "30th-c-\(String(format: "%03d", number))",
                setID: classic.catalogID, setName: classic.name, setCode: classic.code,
                name: "Card", collectorNumber: String(format: "%03d", number),
                thumbnailURL: nil, imageURL: nil, masterSetVariant: .holo, isSoleSlotForCard: true)
        }
        XCTAssertEqual(owned.progress(for: slots), .init(owned: 5, total: 30, unit: "variations"))
        // A main-set card with the same number must not fill a missing classic slot.
        let overlapping = CatalogOwnershipIndex([ownershipCard(set: parent, number: 1)])
        XCTAssertFalse(overlapping.owns(slots[0]))
    }

    func testSharedCodesNeverCombineDifferentPokemonSets() {
        // Shared codes found in the bundled checklist and current publisher input.
        let pairs = [("30th", "30th-c", "30C"), ("cel25", "cel25cc", "CEL"),
            ("ex7", "pl2", "RR"), ("swsh10", "swsh10tg", "ASR"),
            ("swsh4.5", "swsh4.5sv", "SHF"), ("swsh9", "swsh9tg", "BRS")]
        for (leftID, rightID, code) in pairs {
            let left = ownershipSet(leftID, name: leftID, code: code)
            let right = ownershipSet(rightID, name: rightID, code: code)
            let owned = CatalogOwnershipIndex([ownershipCard(set: left, number: 1),
                ownershipCard(set: right, number: 2)])
            XCTAssertEqual(owned.directoryProgress(for: left).owned, 1, leftID)
            XCTAssertEqual(owned.directoryProgress(for: right).owned, 1, rightID)
            XCTAssertEqual(owned.ownedRowCounts(for: [left, right]), [left.id: 1, right.id: 1])
        }
    }

    func testLegacyFallbackRequiresNameAndReconciledAliasTakesPrecedence() {
        let parent = ownershipSet("30th", name: "30th Celebration", code: "30C")
        let classic = ownershipSet("30th-c", name: "30th Celebration Classic Collection", code: "30C")
        let legacy = ownershipCard(set: classic, number: 1)
        legacy.providerID = "import-001"
        let alias = ownershipCard(set: parent, number: 2)
        alias.catalogProviderID = "30th-c-002"
        // Retain stale parent display metadata to prove catalog identity wins.
        let owned = CatalogOwnershipIndex([legacy, alias])
        XCTAssertEqual(owned.directoryProgress(for: classic).owned, 2)
        XCTAssertEqual(owned.directoryProgress(for: parent).owned, 0)
        XCTAssertEqual(owned.ownedRowCounts(for: [parent, classic]), [classic.id: 2])
    }

    func testLegacyPrintRunFallbackAcceptsDirectoryDisplaySuffix() {
        let base = ownershipSet("base1", name: "Base Set", code: "BS", total: 102)
        let legacy = ownershipCard(set: base, number: 1)
        legacy.providerID = "import-001"
        legacy.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        let first = CatalogSet(catalogID: .init(game: .pokemon, providerID: "base1",
            pokemonPrintRun: .firstEdition), name: "Base Set — 1st Edition", code: "BS",
            logoURL: nil, symbolURL: nil, cardCount: 102, releaseDate: nil, sortRank: 0)
        let owned = CatalogOwnershipIndex([legacy])
        XCTAssertEqual(owned.directoryProgress(for: first).owned, 1)
        XCTAssertEqual(owned.directoryProgress(for: base).owned, 0)
        XCTAssertEqual(owned.ownedRowCounts(for: [base, first]), [first.id: 1])
    }

    private func ownershipSet(_ id: String, name: String, code: String, total: Int = 30) -> CatalogSet {
        .init(catalogID: .init(game: .pokemon, providerID: id), name: name, code: code,
            logoURL: nil, symbolURL: nil, cardCount: total, releaseDate: nil, sortRank: 0)
    }

    private func ownershipCard(set: CatalogSet, number: Int) -> CollectedCard {
        let printed = String(format: "%03d", number)
        return CollectedCard(collectionKey: "\(set.providerID)-\(printed)", game: .pokemon,
            providerID: "\(set.providerID)-\(printed)", name: "Card", setName: set.name,
            setCode: set.code, cardNumber: printed, rarity: nil, imageURL: nil,
            thumbnailURL: nil, variant: .holo, variantResolution: .userConfirmed)
    }

    func testDirectoryFallbackMatchesLegacyRulesWithOnePreparedOwnershipPass() throws {
        let sets = (0..<60).map { index in
            CatalogSet(catalogID: .init(game: .pokemon, providerID: "fixture-\(index)"),
                name: "Fixture \(index)", code: "FIX\(index)", logoURL: nil, symbolURL: nil,
                cardCount: index == 0 ? nil : 100, releaseDate: nil, sortRank: index)
        }
        let cards = (0..<2_000).map { index in
            CollectedCard(collectionKey: "fixture-\(index)", game: .pokemon,
                providerID: "fixture-\(index % sets.count)-\(index % 100)", name: "Fixture",
                setName: "Fixture", setCode: "FIX\(index % sets.count)", cardNumber: "\(index % 100)",
                rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: index.isMultiple(of: 2) ? .normal : .reverse,
                variantResolution: .userConfirmed)
        }
        let rows = cards.map(CatalogOwnershipCardSnapshot.init)
        let clock = ContinuousClock()
        let prepareStart = clock.now
        let ownership = CatalogOwnershipIndex(rows: rows)
        let prepareTime = prepareStart.duration(to: clock.now)
        // Freeze the original whole-collection fallback as a differential
        // reference. This also quantifies its repeated rendering-path work.
        let legacyStart = clock.now
        let legacy = sets.map { set in
            Set(rows.compactMap { row -> String? in
                guard row.game == set.game, row.quantity > 0,
                      row.itemKind.countsTowardSetCompletion,
                      !PokemonStampedReleaseCatalog.isStamped(variantID: row.variantID),
                      row.pokemonPrintRun == nil else { return nil }
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                let locale = Locale(identifier: "en_US_POSIX")
                if row.setCode.folding(options: options, locale: locale)
                    == set.code.folding(options: options, locale: locale) {
                    return SetCompletionCalculator.canonicalNumber(row.cardNumber)
                }
                return (row.catalogProviderID ?? row.providerID).lowercased()
                    .hasPrefix(set.providerID.lowercased() + "-")
                    ? SetCompletionCalculator.canonicalNumber(row.cardNumber) : nil
            }).count
        }
        let legacyTime = legacyStart.duration(to: clock.now)
        let currentStart = clock.now
        let current = sets.map { ownership.directoryProgress(for: $0) }
        let currentTime = currentStart.duration(to: clock.now)
        XCTAssertEqual(current.map(\.owned), legacy)
        XCTAssertNil(current[0].total)
        XCTAssertNil(current[0].fraction)
        print("BROWSE_DIRECTORY rows=\(rows.count) sets=\(sets.count) prepare=\(prepareTime) legacy=\(legacyTime) prepared=\(currentTime) legacyRowVisits=\(rows.count * sets.count) preparedRowVisits=0")
    }

    func testPreparedProjectionPreservesQuerySortOwnershipTierAndGroupingAcrossGames() async throws {
        for game in [CardGame.pokemon, .magic, .onePiece, .lorcana, .yuGiOh] {
            let cards = fixtureCards(game: game)
            let card = CollectedCard(collectionKey: "owned", game: game, providerID: cards[0].providerID,
                name: cards[0].name, setName: "Fixture", setCode: "FIX", cardNumber: "010",
                rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal,
                variantResolution: .userConfirmed)
            let owned = CatalogOwnershipIndex([card])
            let builder = CatalogSetPresentationBuilder()
            let generation = UUID()
            for tier in PokemonMasterSetTier.allCases {
                let slots = game == .pokemon && tier == .standard
                    ? cards.filter { !$0.isExpandedMasterSetVariant } : cards
                for sort in CatalogSetSort.allCases {
                    for filter in CatalogOwnershipFilter.allCases {
                        for search in ["", "eEVee", "525", "ho oh", "no match", ""] {
                            let prices = [cards[0].id: 2.0, cards[1].id: 2.0, cards[2].id: 8.0]
                            let inputs = inputs(cards, generation: generation, search: search,
                                sort: sort, filter: filter, tier: tier, prices: prices)
                            let expected = CatalogCardDisplayGrouping.groups(for: CatalogSetQuery.apply(
                                slots, search: search, sort: sort, ownership: filter, owned: owned, prices: prices))
                            let actual = try await builder.groups(for: inputs, owned: owned)
                            XCTAssertEqual(actual, expected, "\(game) \(tier) \(sort) \(filter) \(search)")
                        }
                    }
                }
            }
            let diagnostics = await builder.diagnostics
            XCTAssertEqual(diagnostics.preparations, 1)
        }
    }

    func testDirectoryFallbackKeepsPrintRunsAliasesAndUnknownTotalsSeparate() {
        func card(_ number: String, run: PokemonPrintRun?, game: CardGame = .pokemon) -> CollectedCard {
            let card = CollectedCard(collectionKey: "\(game.rawValue)-\(number)", game: game,
                providerID: "import-\(number)", name: "Card", setName: "Fixture", setCode: "FIX",
                cardNumber: number, rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: .normal, variantResolution: .userConfirmed)
            card.pokemonPrintRunRaw = run?.rawValue
            return card
        }
        let alias = card("001", run: nil)
        alias.setCode = "OTHER"
        alias.catalogProviderID = "fixture-001"
        let owned = CatalogOwnershipIndex([alias, card("002", run: .firstEdition),
            card("003", run: .shadowless), card("004", run: .unlimited),
            card("005", run: nil, game: .magic)])
        func set(_ run: PokemonPrintRun?) -> CatalogSet {
            .init(catalogID: .init(game: .pokemon, providerID: "fixture", pokemonPrintRun: run),
                name: "Fixture", code: "FIX", logoURL: nil, symbolURL: nil, cardCount: nil,
                releaseDate: nil, sortRank: 0)
        }
        XCTAssertEqual(owned.directoryProgress(for: set(nil)), .init(owned: 1, total: nil))
        XCTAssertEqual(owned.directoryProgress(for: set(.firstEdition)), .init(owned: 1, total: nil))
        XCTAssertEqual(owned.directoryProgress(for: set(.shadowless)), .init(owned: 1, total: nil))
        XCTAssertEqual(owned.directoryProgress(for: set(.unlimited)), .init(owned: 2, total: nil))
    }

    func testPreparationAndOrderingAreReusedAndSameCountCatalogAndOwnershipChangesInvalidate() async throws {
        var cards = fixtureCards()
        let builder = CatalogSetPresentationBuilder()
        let generation = UUID()
        let empty = CatalogOwnershipIndex(rows: [])
        for search in ["", "", "e", "ee", "eev", "", ""] {
            _ = try await builder.groups(for: inputs(cards, generation: generation, search: search), owned: empty)
        }
        var diagnostics = await builder.diagnostics
        XCTAssertEqual(diagnostics.preparations, 1)
        XCTAssertEqual(diagnostics.priceSorts, 0)
        XCTAssertEqual(diagnostics.projections, 5, "Identical normalized inputs reuse the whole presentation")

        let priced = inputs(cards, generation: generation, sort: .priceLowToHigh, prices: [cards[0].id: 1])
        _ = try await builder.groups(for: priced, owned: empty)
        _ = try await builder.groups(for: inputs(cards, generation: generation, search: "ee",
            sort: .priceLowToHigh, prices: priced.prices), owned: empty)
        diagnostics = await builder.diagnostics
        XCTAssertEqual(diagnostics.priceSorts, 1, "Typing does not re-sort unchanged prices")
        _ = try await builder.groups(for: inputs(cards, generation: generation, sort: .priceLowToHigh,
            prices: [cards[0].id: 3]), owned: empty)
        diagnostics = await builder.diagnostics
        XCTAssertEqual(diagnostics.priceSorts, 2)

        let ownedCard = CollectedCard(collectionKey: "owned", game: .pokemon, providerID: cards[0].providerID,
            name: "Eevee", setName: "Fixture", setCode: "FIX", cardNumber: "010", rarity: nil,
            imageURL: nil, thumbnailURL: nil, variant: .normal, variantResolution: .userConfirmed)
        let owned = CatalogOwnershipIndex([ownedCard])
        let missing = try await builder.groups(for: inputs(cards, filter: .owned), owned: empty)
        XCTAssertTrue(missing.isEmpty)
        let present = try await builder.groups(for: inputs(cards, filter: .owned, revision: 1), owned: owned)
        XCTAssertEqual(present.flatMap(\.summaries).map(\.id), [cards[0].id])

        cards[0] = summary(game: .pokemon, providerID: "replacement", name: "Replacement", number: "001")
        let replacement = try await builder.groups(for: inputs(cards, search: "replacement"), owned: empty)
        XCTAssertEqual(replacement.first?.preferredSummary.name, "Replacement")
        diagnostics = await builder.diagnostics
        XCTAssertEqual(diagnostics.preparations, 2, "Same-count catalog replacement must rebuild metadata")
    }

    func testOnlyLatestRequestPublishesAndDisappearCancelsEvenUncooperativeWork() async throws {
        let gate = PresentationGate()
        let store = CatalogSetPresentationStore(builder: gate)
        let cards = fixtureCards()
        let old = try XCTUnwrap(store.update(inputs(cards, search: "eevee"), owned: .init(rows: [])))
        try await waitForRequests(1, gate: gate)
        var changed = cards
        changed[0] = summary(game: .pokemon, providerID: "new", name: "New catalog", number: "001")
        let latestInputs = inputs(changed, search: "", sort: .numberHighToLow,
            revision: 3, tier: .expanded)
        let latest = try XCTUnwrap(store.update(latestInputs, owned: .init(rows: [])))
        try await waitForRequests(2, gate: gate)
        await gate.finish(1)
        await latest.value
        XCTAssertEqual(store.groups.first?.preferredSummary.name, "New catalog")
        await gate.finish(0)
        await old.value
        XCTAssertEqual(store.groups.first?.preferredSummary.name, "New catalog")

        let pendingInputs = inputs(cards, search: "ho")
        let pending = try XCTUnwrap(store.update(pendingInputs, owned: .init(rows: [])))
        try await waitForRequests(3, gate: gate)
        store.cancel()
        await gate.finish(2)
        await pending.value
        XCTAssertEqual(store.groups.first?.preferredSummary.name, "New catalog")
        XCTAssertFalse(store.isProjecting)
        let reopened = try XCTUnwrap(store.update(pendingInputs, owned: .init(rows: [])))
        try await waitForRequests(4, gate: gate)
        await gate.finish(3)
        await reopened.value
        XCTAssertEqual(store.groups.first?.preferredSummary.name, cards[0].name)
    }

    private func inputs(_ cards: [CatalogCardSummary], generation: UUID = UUID(), search: String = "",
                        sort: CatalogSetSort = .numberLowToHigh, filter: CatalogOwnershipFilter = .all,
                        revision: UInt = 0, tier: PokemonMasterSetTier = .standard,
                        prices: [String: Double] = [:]) -> CatalogSetPresentationInputs {
        .init(setID: cards[0].setID, contentGeneration: generation, cards: cards, search: search,
              sort: sort, ownership: filter, ownershipRevision: revision, tier: tier, prices: prices)
    }

    private func fixtureCards(game: CardGame = .pokemon) -> [CatalogCardSummary] {
        var expanded = summary(game: game, providerID: "ten", name: "Eevee", number: "010", variant: .masterBall)
        expanded.isExpandedMasterSetVariant = true
        return [summary(game: game, providerID: "ten", name: "Eevee", number: "010", variant: .normal),
                summary(game: game, providerID: "two", name: "Ho-Oh", number: "002"),
                summary(game: game, providerID: "suffix-b", name: "Eevee", number: "525b"),
                summary(game: game, providerID: "suffix-a", name: "Eevee", number: "525a"),
                summary(game: game, providerID: "ten", name: "Eevee", number: "010", variant: .reverse),
                expanded,
                summary(game: game, providerID: "unknown", name: "Unknown", number: "?")]
    }

    private func summary(game: CardGame, providerID: String, name: String, number: String,
                         variant: PhysicalVariant? = nil) -> CatalogCardSummary {
        .init(game: game, providerID: providerID, setID: .init(game: game, providerID: "fixture"),
              setName: "Fixture", setCode: "FIX", name: name, collectorNumber: number,
              thumbnailURL: nil, imageURL: nil, masterSetVariant: variant)
    }

    private func waitForRequests(_ count: Int, gate: PresentationGate) async throws {
        for _ in 0..<100 {
            if await gate.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Projection did not reach its gate")
    }
}

private actor PresentationGate: CatalogSetPresentationBuilding {
    private var pending: [(CatalogSetPresentationInputs, CheckedContinuation<[CatalogCardDisplayGroup], Error>)] = []
    var count: Int { pending.count }
    func groups(for inputs: CatalogSetPresentationInputs,
                owned: CatalogOwnershipIndex) async throws -> [CatalogCardDisplayGroup] {
        try await withCheckedThrowingContinuation { pending.append((inputs, $0)) }
    }
    func finish(_ index: Int) {
        let (inputs, continuation) = pending[index]
        continuation.resume(returning: CatalogCardDisplayGrouping.groups(for: [inputs.cards[0]]))
    }
}
